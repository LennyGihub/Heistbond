--!strict
-- The "in cover" body pose (R15), applied on top of the animations by overriding the joints'
-- Transform (Motor6D or AnimationConstraint). Used by CoverClient for every character in cover
-- (the local one and other players), every frame between the animations and physics.
--
-- Tall wall (low = 0): back flat against the wall (the root faces away from it), knees a little
-- bent, upper body and head turned toward `side` (+1 = the character's right, -1 = its left).
-- Empty hands: both palms flat on the wall, placed by a two-bone IK - the hand on the look side out
-- at shoulder height, the other one beside the hip; they sway a little with the steps. Sliding along
-- the wall is a chasse step driven by `phase`.
--
-- Low wall (low = 1): side-on, the shoulder on the `side` side toward the wall (CoverClient turns the
-- root to face along the wall), upper body bent forward just enough to keep the head under the
-- wall's top. Still: down on the wall-side knee, the other foot flat in front. Moving: a crouched
-- walk. Empty hands hang in front and swing a little with the steps. `blind` (blind fire over the
-- wall) straightens the back a little and tucks the head; the shouldered gun is lifted over the top.
--
-- With a weapon in hand the arms are left to the gun's IK.
--
-- Joint axes (R15 joint frames are body-aligned): +X swings a hanging limb forward but tips an
-- upward part (upper body at the waist, head at the neck) backward; +Z moves a hanging limb toward
-- the body's +X (right); +Y turns left.
local CoverPose = {}

export type State = {
	alpha: number, -- 0 = normal animation, 1 = full cover pose
	side: number, -- -1 .. 1, smoothed look side
	phase: number, -- step cycle (radians)
	step: number, -- 0..1 how much the step cycle plays (0 = standing still)
	armed: boolean,
	wall: number?, -- measured distance from the root's centre to the wall behind it (nil = assume)
	reach: number?, -- how far the wall goes on the look side, from the root (nil = far enough)
	low: number, -- 0 = tall wall (standing, back to it), 1 = low wall (side-on, crouched); smoothed
	top: number?, -- world height of the low wall's top (sets how far to bend down)
	blind: number?, -- 0..1 blind firing over a low wall
	twist: number?, -- Studio tuning only: overrides BLIND_TWIST
}

CoverPose.BACK_GAP = 0.08 -- gap between the back and the wall (CoverClient keeps it)

-- steps: relative to the body each foot moves STEP_HALF studs either side of its spot; one full
-- cycle (each foot steps once) moves the body 4 * STEP_HALF studs, which CoverClient uses (stepLen)
-- to advance the phase so planted feet don't slide. Long steps keep the legs from looking frantic.
local STEP_HALF_TALL = 0.55 -- chasse step along a tall wall
local STEP_HALF_LOW = 0.65 -- crouched walk behind a low wall

-- step half-length and full cycle length for a given amount of low cover (0 = tall, 1 = low)
function CoverPose.stepHalf(low: number): number
	return STEP_HALF_TALL + (STEP_HALF_LOW - STEP_HALF_TALL) * math.clamp(low, 0, 1)
end
function CoverPose.stepLen(low: number): number
	return 4 * CoverPose.stepHalf(low)
end

-- behind a low wall the head stays HEAD_BELOW studs under the wall's top
local HEAD_BELOW = 0.25
local WALK_CROUCH = 1.35 -- hip drop while walking crouched
local MIN_LEAN, MAX_LEAN = 0.45, 1.1 -- forward bend of the upper body behind a low wall (radians)
local BLIND_STRAIGHTEN = 0.1 -- blind firing straightens the back this much, so the hands reach the raised gun
local BLIND_DUCK = 0.5 -- ...and tucks the head down this much, so it stays under the top
local BLIND_TWIST = 1.15 -- ...and turns the chest toward the wall, so both hands hold the gun over it
local KNEEL_THIGH = 0.15 -- the kneeling thigh leans back this much (radians)
local FRONT_FOOT = 0.85 -- kneeling: the front foot is this far ahead of the hip

-- one foot over a step cycle: offset along the travel direction and how high it lifts.
-- First half: in the air, swinging from behind to ahead (eased). Second half: planted, sliding back.
local function foot(ph: number, a: number): (number, number)
	ph %= 2 * math.pi
	if ph < math.pi then
		local u = ph / math.pi
		return -a + 2 * a * u * u * (3 - 2 * u), math.sin(ph)
	end
	return a - 2 * a * (ph - math.pi) / math.pi, 0
end

-- where the palms go on a tall wall (sideways past the shoulder, height in torso heights from the
-- upper torso's centre as posed)
local LEAD_OUT, LEAD_UP = 1.05, 0.375
local BACK_OUT, BACK_UP = 0.85, -0.325

local A = CFrame.Angles

-- a body joint: Motor6D on classic rigs, AnimationConstraint on avatars with the newer joints.
-- Both work the same: Part1 = Part0 * c0 * Transform * c1:Inverse()
type Joint = { Transform: CFrame }
type Rig = { j: Joint, c0: CFrame, c1: CFrame }

local function rig(char: Model, part: string, name: string): Rig?
	local p = char:FindFirstChild(part)
	local m = p and p:FindFirstChild(name)
	if m and m:IsA("Motor6D") then
		return { j = m :: any, c0 = m.C0, c1 = m.C1 }
	elseif m and m:IsA("AnimationConstraint") then
		local a0, a1 = m.Attachment0, m.Attachment1
		if a0 and a1 then
			return { j = m :: any, c0 = a0.CFrame, c1 = a1.CFrame }
		end
	end
	return nil
end

local function set(r: Rig?, cf: CFrame, alpha: number)
	if r then
		r.j.Transform = r.j.Transform:Lerp(cf, alpha)
	end
end

-- shortest rotation taking unit vector a onto unit vector b
local function rotBetween(a: Vector3, b: Vector3): CFrame
	local d = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		if d > 0 then
			return CFrame.identity
		end
		local perp = math.abs(a.X) < 0.9 and Vector3.xAxis or Vector3.yAxis
		return CFrame.fromAxisAngle(a:Cross(perp).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(d))
end

-- two-bone arm IK: the hand ends at `hand` (world CFrame), the elbow bends toward `pole` (world point).
-- `parentCF` is the world CFrame of the upper torso as posed this frame.
local function solveArm(char: Model, prefix: string, parentCF: CFrame, hand: CFrame, pole: Vector3, alpha: number)
	local sh = rig(char, prefix .. "UpperArm", prefix .. "Shoulder")
	local el = rig(char, prefix .. "LowerArm", prefix .. "Elbow")
	local wr = rig(char, prefix .. "Hand", prefix .. "Wrist")
	if not sh or not el or not wr then
		return
	end
	local S = parentCF * sh.c0 -- shoulder joint frame (before its rotation)
	-- rest-pose bone vectors in the shoulder / elbow joint frames
	local elbowRest = sh.c1:Inverse() * el.c0 -- elbow joint frame, in the shoulder frame
	local function wristAt(Tel: CFrame): Vector3
		return (elbowRest * Tel * el.c1:Inverse() * wr.c0).Position
	end
	local a = elbowRest.Position -- shoulder -> elbow
	local b = wristAt(CFrame.identity) - a -- elbow -> wrist
	local L1, L2 = a.Magnitude, b.Magnitude
	-- where the wrist joint must be so the hand lands on `hand`
	local wristWorld = hand:PointToWorldSpace(wr.c1.Position)
	local t = S:PointToObjectSpace(wristWorld)
	local D = math.clamp(t.Magnitude, math.abs(L1 - L2) + 0.05, L1 + L2 - 0.02)
	-- elbow: bend forward (+X) until shoulder->wrist is D long
	local cosIn = math.clamp((L1 * L1 + L2 * L2 - D * D) / (2 * L1 * L2), -1, 1)
	local restIn = math.acos(math.clamp(-a.Unit:Dot(b.Unit), -1, 1)) -- inner angle in the rest pose
	local bend = math.max(0, restIn - math.acos(cosIn))
	local Tel = A(bend, 0, 0)
	-- shoulder: point shoulder->wrist at the target, then roll the elbow toward the pole
	local wristRest = wristAt(Tel)
	local q1 = rotBetween(wristRest.Unit, t.Unit)
	local axis = t.Unit
	local e1 = q1:VectorToWorldSpace(a)
	local p = S:PointToObjectSpace(pole)
	local function flatTo(v: Vector3): Vector3
		return v - axis * v:Dot(axis)
	end
	local ef, pf = flatTo(e1), flatTo(p)
	local Tsh = q1
	if ef.Magnitude > 1e-4 and pf.Magnitude > 1e-4 then
		local ang = math.atan2(ef.Unit:Cross(pf.Unit):Dot(axis), ef.Unit:Dot(pf.Unit))
		Tsh = CFrame.fromAxisAngle(axis, ang) * q1
	end
	set(sh, Tsh, alpha)
	set(el, Tel, alpha)
	-- wrist: turn the hand to the wanted orientation
	local upperCF = S * Tsh * sh.c1:Inverse()
	local W = upperCF * el.c0 * Tel * el.c1:Inverse() * wr.c0
	set(wr, (W:Inverse() * hand * wr.c1).Rotation, alpha)
end


-- a leg solved in the side view: the ankle `Dv` below the hip and `fwd` ahead of it, foot flat.
-- Returns hip, knee and ankle angles about X.
local function sagittal(L1: number, L2: number, Dv: number, fwd: number): (number, number, number)
	local Dl = math.clamp(math.sqrt(Dv * Dv + fwd * fwd), math.abs(L1 - L2) + 0.05, L1 + L2 - 0.01)
	local inner = math.acos(math.clamp((L1 * L1 + L2 * L2 - Dl * Dl) / (2 * L1 * L2), -1, 1))
	local atHip = math.acos(math.clamp((L1 * L1 + Dl * Dl - L2 * L2) / (2 * L1 * Dl), -1, 1))
	local hipX = atHip + math.atan2(fwd, Dv)
	local knee = -(math.pi - inner)
	return hipX, knee, -(hipX + knee)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function CoverPose.isR15(char: Model): boolean
	return char:FindFirstChild("UpperTorso") ~= nil
end

function CoverPose.apply(char: Model, s: State)
	local alpha = math.clamp(s.alpha, 0, 1)
	if alpha <= 0.001 or not CoverPose.isR15(char) then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local upper = char:FindFirstChild("UpperTorso") :: BasePart?
	if not hrp or not upper then
		return
	end
	local side = math.clamp(s.side, -1, 1)
	local dir = side >= 0 and 1 or -1
	local step = math.clamp(s.step, 0, 1)
	local ph = s.phase
	local low = math.clamp(s.low or 0, 0, 1)
	local blind = math.clamp(s.blind or 0, 0, 1)
	local root = rig(char, "LowerTorso", "Root")
	local waist = rig(char, "UpperTorso", "Waist")
	local neck = rig(char, "Head", "Neck")
	local head = char:FindFirstChild("Head") :: BasePart?

	-- leg sizes from the joints (the parts' sizes overlap on some avatars)
	local hip, knee, ankle = rig(char, "RightUpperLeg", "RightHip"), rig(char, "RightLowerLeg", "RightKnee"), rig(char, "RightFoot", "RightAnkle")
	local L1, L2 = 1, 1
	if hip and knee and ankle then
		L1 = (hip.c1:Inverse() * knee.c0).Position.Magnitude
		L2 = (knee.c1:Inverse() * ankle.c0).Position.Magnitude
	end
	local footPart = char:FindFirstChild("RightFoot") :: BasePart?
	local shin = char:FindFirstChild("RightLowerLeg") :: BasePart?
	local footH = footPart and footPart.Size.Y / 2 or 0.2
	local kneeR = shin and math.min(shin.Size.Z, shin.Size.X) / 2 or 0.3
	local a = CoverPose.stepHalf(low)
	local bob = 0.05 * step * (1 - math.cos(2 * ph)) / 2 -- rises a touch while a foot is in the air

	-- TALL WALL: hips dropped a little, turned toward the look side, upper body leaning back on the
	-- wall and twisting toward the side, head looking over the shoulder
	local tRoot = CFrame.new(0, -0.32 + bob, 0) * A(0, -0.08 * side, 0)
	local tWaist = A(0.04, -0.12 * side, 0.03 * side)
	local tNeck = A(0.05, -1.0 * side, 0)

	-- LOW WALL: how low to get. Kneeling puts the hips at thigh length + the knee's thickness; walking
	-- crouched drops them WALK_CROUCH. Then bend forward until the head is under the wall's top.
	local kneelHip = L1 * math.cos(KNEEL_THIGH) + kneeR
	local kneelDrop = (L1 + L2 + footH) - kneelHip
	local lowDrop = lerp(kneelDrop, math.min(WALK_CROUCH, L1 + L2 - 0.5), step)
	local lean = MIN_LEAN
	if s.top and root and waist then
		local torso0 = hrp.CFrame * root.c0 * root.c1:Inverse() * waist.c0 * waist.c1:Inverse()
		local headTop = torso0.Position.Y + upper.Size.Y / 2 + (head and head.Size.Y or 1.2) + 0.3
		local need = headTop - (s.top - HEAD_BELOW) - lowDrop -- still to lose by bending forward
		local reachUp = upper.Size.Y + (head and head.Size.Y or 1.2) -- waist to the top of the head
		lean = math.clamp(math.acos(math.clamp(1 - need / reachUp, -1, 1)), MIN_LEAN, MAX_LEAN)
	end
	lean = math.max(lean - BLIND_STRAIGHTEN * blind, 0.2)
	local lRoot = CFrame.new(0, -lowDrop + bob * 0.6, 0)
	-- bent forward (-X tips the upper body forward). Blind fire first turns the chest to the wall (on
	-- the `dir` side: +Y turns left), so the bend then leans it over toward the wall and the gun
	local lWaist = A(0, -dir * (s.twist or BLIND_TWIST) * blind, 0) * A(-lean, 0, 0)
	local lNeck = A(lean * 0.75 - BLIND_DUCK * blind, 0, 0) -- the head tips back up to keep looking ahead

	set(root, tRoot:Lerp(lRoot, low), alpha)
	set(waist, tWaist:Lerp(lWaist, low), alpha)
	set(neck, tNeck:Lerp(lNeck, low), alpha)

	-- legs
	local rLead = dir > 0
	local wallLeg = rLead and "Right" or "Left" -- low wall: the leg on the wall side kneels
	local standLever = (L1 + L2 + footH) * 0.8 -- knees bent: the foot is a bit closer to the hip
	local function leg(prefix: string, base: number, footPh: number, bias: number)
		local off, lift = foot(footPh, a)
		local l = lift * step
		-- tall wall: chasse step sideways (`bias`: the lead foot works further out, the other further
		-- in, so the feet close and open but never cross)
		local tHipX, tKnee, tAnkle = 0.32 + l * 0.45, -0.55 - l * 0.85, 0.22 + l * 0.4
		local tHipZ = base + dir * (off + bias) * step / standLever
		-- low wall, still: kneeling
		local kHipX, kKnee, kAnkle
		if prefix == wallLeg then
			kHipX, kKnee, kAnkle = -KNEEL_THIGH, -math.pi / 2 + KNEEL_THIGH, 0.35 -- knee down, toes tucked
		else
			kHipX, kKnee, kAnkle = sagittal(L1, L2, kneelHip - footH, FRONT_FOOT) -- foot flat in front
		end
		-- low wall, moving: crouched walk forward (along the wall)
		local walkPh = prefix == wallLeg and ph or ph + math.pi
		local wOff, wLift = foot(walkPh, a)
		local wHipX, wKnee, wAnkle = sagittal(L1, L2, L1 + L2 - math.min(WALK_CROUCH, L1 + L2 - 0.5) - wLift * step * 0.3, 0.15 + wOff * step)
		local lHipX, lKnee, lAnkle = lerp(kHipX, wHipX, step), lerp(kKnee, wKnee, step), lerp(kAnkle, wAnkle, step)
		local lHipZ = prefix == "Right" and 0.1 or -0.1
		local hipX, kneeX, ankleX = lerp(tHipX, lHipX, low), lerp(tKnee, lKnee, low), lerp(tAnkle, lAnkle, low)
		local hipZ = lerp(tHipZ, lHipZ, low)
		set(rig(char, prefix .. "UpperLeg", prefix .. "Hip"), A(hipX, 0, hipZ), alpha)
		set(rig(char, prefix .. "LowerLeg", prefix .. "Knee"), A(kneeX, 0, 0), alpha)
		set(rig(char, prefix .. "Foot", prefix .. "Ankle"), A(ankleX, 0, -hipZ), alpha)
	end
	leg("Right", 0.07, rLead and ph or ph + math.pi, rLead and a or -a)
	leg("Left", -0.07, rLead and ph + math.pi or ph, rLead and -a or a)

	if s.armed or not root or not waist then
		return -- the gun's IK owns the arms
	end

	-- LOW WALL arms: hanging down (undoing most of the forward bend) a little in front, swinging a
	-- little against the steps
	if low > 0.001 then
		for _, prefix in { "Right", "Left" } do
			local swing = math.sin(prefix == wallLeg and ph + math.pi or ph) * 0.3 * step
			local out = prefix == "Right" and 0.1 or -0.1
			set(rig(char, prefix .. "UpperArm", prefix .. "Shoulder"), A(lean * 0.8 + 0.3 + swing, 0, out), alpha * low)
			set(rig(char, prefix .. "LowerArm", prefix .. "Elbow"), A(0.45, 0, 0), alpha * low)
			set(rig(char, prefix .. "Hand", prefix .. "Wrist"), A(0.1, 0, 0), alpha * low)
		end
	end
	if low > 0.999 then
		return
	end
	local tallAlpha = alpha * (1 - low)
	-- the upper torso as posed this frame (forward kinematics from the root part)
	local lower = hrp.CFrame * root.c0 * root.j.Transform * root.c1:Inverse()
	local torso = lower * waist.c0 * waist.j.Transform * waist.c1:Inverse()

	-- the wall: a plane right behind the back, facing where the root faces
	local n = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	n = n.Magnitude > 1e-3 and n.Unit or Vector3.zAxis
	local right = n:Cross(Vector3.yAxis) -- the character's right, along the wall
	local wallAt = hrp.Position - n * math.clamp(s.wall or (upper.Size.Z / 2 + CoverPose.BACK_GAP), 0.2, 2)
	local sx = upper.Size.X / 2 -- half shoulder width (scales with the avatar)
	local hy = upper.Size.Y -- torso height, for vertical placement

	-- a palm on the wall: centre on the wall plane, palm facing into it, fingers along `fingers`
	local function palm(prefix: string, lateral: number, height: number, fingers: Vector3): CFrame
		local handPart = char:FindFirstChild(prefix .. "Hand") :: BasePart?
		local thick = handPart and handPart.Size.X / 2 or 0.15
		local y = torso.Position.Y + height
		if s.top then
			y = math.min(y, s.top - 0.45) -- low wall: keep the hand on it, below its top
		end
		local pos = Vector3.new(wallAt.X, y, wallAt.Z) + right * lateral + n * thick
		-- hand axes: -Y runs to the fingertips; the palm is the -X face (right hand) / +X face (left)
		local Y = -fingers.Unit
		local X = prefix == "Right" and n or -n
		local Z = X:Cross(Y)
		return CFrame.fromMatrix(pos, X, Y, Z)
	end

	-- both palms flat on the wall, arms out along it: the lead hand (look side) at shoulder height,
	-- fingers pointing outward; the back hand beside the hip, fingers down and outward
	local leadPrefix = dir > 0 and "Right" or "Left"
	local backPrefix = dir > 0 and "Left" or "Right"
	local up = Vector3.yAxis
	-- at the end of the wall the lead hand grips its edge instead of pressing on thin air
	-- while stepping the hands drift a little along the wall and back (they follow the body only partly)
	local sway = math.sin(ph) * step
	local leadOut = math.min(sx + LEAD_OUT - 0.12 * sway, (s.reach or math.huge) + 0.1)
	local leadHand = palm(leadPrefix, dir * leadOut, hy * LEAD_UP + 0.04 * sway, up * 0.3 + right * dir)
	local backHand = palm(backPrefix, -dir * (sx + BACK_OUT + 0.1 * sway), hy * BACK_UP, -up + right * -dir * 0.6)
	-- elbows: the lead arm runs sideways, so its elbow points down and a little off the wall; the back
	-- arm runs down, so its elbow points out to the side. Each pole is well off its arm's line, so the
	-- elbow can't flip around when the body bobs.
	local leadShoulder = torso:PointToWorldSpace(Vector3.new(dir * sx, upper.Size.Y * 0.3, 0))
	local backShoulder = torso:PointToWorldSpace(Vector3.new(-dir * sx, upper.Size.Y * 0.3, 0))
	local leadPole = leadShoulder - up * 3 + n * 0.8
	local backPole = backShoulder + right * -dir * 3 + n * 0.8
	solveArm(char, leadPrefix, torso, leadHand, leadPole, tallAlpha)
	solveArm(char, backPrefix, torso, backHand, backPole, tallAlpha)
end

return CoverPose
