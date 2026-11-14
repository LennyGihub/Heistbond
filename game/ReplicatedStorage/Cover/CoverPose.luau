--!strict
-- The "in cover" body pose (R15), applied on top of the animations by overriding the joints'
-- Transform (Motor6D or AnimationConstraint). Used by CoverClient for every character in cover
-- (the local one and other players), every frame between the animations and physics.
--
-- Pose: back flat against the wall (the wall is right behind the root, which faces away from it),
-- knees a little bent, upper body and head turned toward `side` (+1 = the character's right,
-- -1 = its left). Empty hands: both palms flat on the wall, placed by a two-bone IK - the hand on the
-- look side out at shoulder height, the other one beside the hip; they sway a little with the steps.
-- Behind a low wall (`low`) the character crouches so its head is just under the wall's top.
-- While sliding along the wall the legs do a chasse step driven by `phase`. With a weapon in hand the
-- arms are left to the gun's IK.
--
-- Joint axes (R15 joint frames are body-aligned): +X swings a hanging limb forward, +Z moves it
-- toward the body's +X (right), +Y turns left.
local CoverPose = {}

export type State = {
	alpha: number, -- 0 = normal animation, 1 = full cover pose
	side: number, -- -1 .. 1, smoothed look side
	phase: number, -- sidestep cycle (radians)
	step: number, -- 0..1 how much the sidestep plays (0 = standing still)
	armed: boolean,
	wall: number?, -- measured distance from the root's centre to the wall behind it (nil = assume)
	reach: number?, -- how far the wall goes on the look side, from the root (nil = far enough)
	low: number, -- 0 = tall wall (standing), 1 = low wall (crouched behind it); smoothed
	top: number?, -- world height of the low wall's top (sets how deep to crouch)
}

CoverPose.BACK_GAP = 0.08 -- gap between the back and the wall (CoverClient keeps it)

-- chasse step: relative to the body each foot moves STEP_HALF studs either side of its spot; one
-- full cycle (each foot steps once, STEP_LEN studs) moves the body STEP_LEN studs, which CoverClient
-- uses to advance the phase so planted feet don't slide
CoverPose.STEP_HALF = 0.45
CoverPose.STEP_LEN = 4 * CoverPose.STEP_HALF
local LOW_STEP = 0.6 -- crouched steps are this much of the standing ones

-- STEP_LEN for a given crouch amount (0 = standing, 1 = crouched)
function CoverPose.stepLen(low: number): number
	return CoverPose.STEP_LEN * (1 + (LOW_STEP - 1) * math.clamp(low, 0, 1))
end

-- crouching behind a low wall: the head goes HEAD_BELOW studs under the wall's top, the hips drop
-- at most MAX_CROUCH studs (deeper than that the upper body hunches forward a little)
local HEAD_BELOW = 0.25
local MIN_CROUCH, MAX_CROUCH = 0.7, 1.45
local CRAB_TURN = 0.45 -- how far the thighs turn out when crouched (radians)

-- one foot over a step cycle: sideways offset along the travel direction and how high it lifts.
-- First half: in the air, swinging from behind to ahead (eased). Second half: planted, sliding back.
local function foot(ph: number, a: number): (number, number)
	ph %= 2 * math.pi
	if ph < math.pi then
		local u = ph / math.pi
		return -a + 2 * a * u * u * (3 - 2 * u), math.sin(ph)
	end
	return a - 2 * a * (ph - math.pi) / math.pi, 0
end

-- where the palms go on the wall (sideways past the shoulder, height in torso heights from the
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
	local root = rig(char, "LowerTorso", "Root")
	local waist = rig(char, "UpperTorso", "Waist")
	local head = char:FindFirstChild("Head") :: BasePart?

	-- how deep to crouch: enough to bring the head under the low wall's top
	local crouch, hunch = MIN_CROUCH, 0
	if low > 0 and root and waist and s.top then
		local torso0 = hrp.CFrame * root.c0 * root.c1:Inverse() * waist.c0 * waist.c1:Inverse()
		local headTop = torso0.Position.Y + upper.Size.Y / 2 + (head and head.Size.Y or 1.2) + 0.3
		local want = headTop - (s.top - HEAD_BELOW)
		crouch = math.clamp(want, MIN_CROUCH, MAX_CROUCH)
		hunch = math.clamp((want - MAX_CROUCH) * 0.5, 0, 0.4)
	end
	local drop = 0.32 + (crouch - 0.32) * low

	-- whole body: hips dropped (a little standing, deep crouched), turned a little toward the look
	-- side; it rises a touch while a foot is in the air (twice per step cycle)
	local bob = 0.05 * step * (1 - math.cos(2 * ph)) / 2
	set(root, CFrame.new(0, -drop + bob, 0) * A(0, -0.08 * side, 0), alpha)
	-- upper body leans back against the wall (hunches forward a bit behind very low walls) and twists
	-- toward the side
	set(waist, A(-0.04 + hunch * low, -0.12 * side, 0.03 * side), alpha)
	-- head looks over the shoulder, toward the side
	set(rig(char, "Head", "Neck"), A(0.05 + hunch * 0.5 * low, -1.0 * side, 0), alpha)

	-- legs. Sliding = a chasse step toward the look side: the lead leg steps out while the other
	-- stands, then the other one steps in next to it; the feet never cross. A foot on the ground moves
	-- back exactly as fast as the body slides (no foot slip).
	-- Standing: knees a little bent (fixed angles). Crouched: thigh/shin angles solved so the hips sit
	-- `drop` lower with the feet flat on the ground, a little forward. Blended by `low`.
	local hip, knee, ankle = rig(char, "RightUpperLeg", "RightHip"), rig(char, "RightLowerLeg", "RightKnee"), rig(char, "RightFoot", "RightAnkle")
	local footPart = char:FindFirstChild("RightFoot") :: BasePart?
	local L1, L2 = 1, 1
	if hip and knee and ankle then
		L1 = (hip.c1:Inverse() * knee.c0).Position.Magnitude
		L2 = (knee.c1:Inverse() * ankle.c0).Position.Magnitude
	end
	local footH = footPart and footPart.Size.Y / 2 or 0.2
	local standLever = (L1 + L2 + footH) * 0.8 -- knees bent: the foot is a bit closer to the hip
	local a = CoverPose.STEP_HALF * (1 + (LOW_STEP - 1) * low)
	local feetFwd = 0.1 + 0.4 * low
	-- crouched it walks like a crab: thighs turned out (knees and toes point outward), a wide stance
	local function leg(prefix: string, base: number, footPh: number, bias: number, turnOut: number)
		local off, lift = foot(footPh, a)
		local l = lift * step
		local lateral = dir * (off + bias) * step
		-- standing
		local sHipX, sKnee, sAnkle = 0.32 + l * 0.45, -0.55 - l * 0.85, 0.22 + l * 0.4
		local sHipZ = base + lateral / standLever
		-- crouched: two-bone solve in the side view (hip above, ankle below and slightly forward)
		local Dv = math.max(L1 + L2 - crouch - l * 0.3, 0.1)
		local Dl = math.clamp(math.sqrt(Dv * Dv + feetFwd * feetFwd), math.abs(L1 - L2) + 0.05, L1 + L2 - 0.01)
		local inner = math.acos(math.clamp((L1 * L1 + L2 * L2 - Dl * Dl) / (2 * L1 * L2), -1, 1))
		local atHip = math.acos(math.clamp((L1 * L1 + Dl * Dl - L2 * L2) / (2 * L1 * Dl), -1, 1))
		local cHipX = atHip + math.atan2(feetFwd, Dv)
		local cKnee = -(math.pi - inner)
		local cAnkle = -(cHipX + cKnee) -- keeps the foot flat
		local cHipZ = base + math.atan2(lateral, Dv + footH)
		local hipX, kneeX, ankleX = sHipX + (cHipX - sHipX) * low, sKnee + (cKnee - sKnee) * low, sAnkle + (cAnkle - sAnkle) * low
		local hipZ = sHipZ + (cHipZ - sHipZ) * low
		set(rig(char, prefix .. "UpperLeg", prefix .. "Hip"), A(0, turnOut * low, 0) * A(hipX, 0, hipZ), alpha)
		set(rig(char, prefix .. "LowerLeg", prefix .. "Knee"), A(kneeX, 0, 0), alpha)
		set(rig(char, prefix .. "Foot", prefix .. "Ankle"), A(ankleX, 0, -hipZ), alpha)
	end
	local rLead = dir > 0
	-- `bias`: while stepping the lead foot works a little further out and the other one a little
	-- further in, so the feet come together (closed) and spread (open) but never cross
	local spread = 0.07 + 0.2 * low -- crouched: wide crab stance
	leg("Right", spread, rLead and ph or ph + math.pi, rLead and a or -a, -CRAB_TURN)
	leg("Left", -spread, rLead and ph + math.pi or ph, rLead and -a or a, CRAB_TURN)

	if s.armed or not root or not waist then
		return -- the gun's IK owns the arms
	end

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
	solveArm(char, leadPrefix, torso, leadHand, leadPole, alpha)
	solveArm(char, backPrefix, torso, backHand, backPole, alpha)
end

return CoverPose
