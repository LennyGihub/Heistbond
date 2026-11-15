--!strict
-- NpcPoses: the frightened civilians' body language, as joint rotations (R15 Transform values).
-- Pure maths: NpcBody (client) calls NpcPoses.sample every frame for each scared NPC and writes the
-- result into the joints. Kinds:
--   "up"    standing, hands up: flinch, then arms raised, trembling, quick shallow breaths, eyes darting
--   "down"  on the knees, fingers locked behind the head, hunched, rocking, glancing up at the robbers
--   "tied"  on the knees, wrists tied behind the back, head hanging, sobbing jerks
--   "none"  (blending back to the normal idle)
-- The legs follow the REAL hip drop of the body (the server lowers HipHeight smoothly): the thighs stay
-- upright and the shins fold back until the knees touch the floor.
local NpcPoses = {}

local rad = math.rad
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

export type State = {
	kind: string,
	since: number, -- time the kind started
	from: { [string]: CFrame }?, -- pose to blend from (snapshot of the last output)
	last: { [string]: CFrame },
	seed: number,
	glanceYaw: number,
	glancePitch: number,
	wantYaw: number,
	wantPitch: number,
	nextGlance: number,
	sobAt: number,
	dropL: number,
	dropR: number,
}

function NpcPoses.new(seed: number): State
	return {
		kind = "none",
		since = 0,
		from = nil,
		last = {},
		seed = seed,
		glanceYaw = 0,
		glancePitch = 0,
		wantYaw = 0,
		wantPitch = 0,
		nextGlance = 0,
		sobAt = 0,
		dropL = 0,
		dropR = 0,
	}
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
NpcPoses.smooth = smooth

-- overshoot ease (fast start, settles past the target and back): for flinches
local function backOut(x: number): number
	x = math.clamp(x, 0, 1)
	local c = 1.9
	return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
end

-- a limb's upper-joint rotation (torso space) so that the upper bone points along `dir` and the next
-- joint bends toward `bendTo`. Arms bend forward with +X at the elbow (sign 1), legs bend backward
-- with -X at the knee (sign -1).
local function limb(dir: Vector3, bendTo: Vector3, sign: number): CFrame
	local down = dir.Unit
	local y = -down
	local b = bendTo - down * bendTo:Dot(down)
	if b.Magnitude < 1e-3 then
		b = Vector3.zAxis - down * down.Z
	end
	local z = if sign > 0 then -b.Unit else b.Unit
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x.Unit, y, z)
end
NpcPoses.limb = limb

local function noise(seed: number, t: number, f: number): number
	return math.noise(seed, t * f, 0.5) * 2 -- about -1..1
end

-- tremor: a small, fast, irregular rotation
local function tremor(seed: number, t: number, deg: number): CFrame
	return ANG(rad(noise(seed, t, 11) * deg), rad(noise(seed + 3.1, t, 9) * deg * 0.6), rad(noise(seed + 7.7, t, 13) * deg))
end

type Pose = { [string]: CFrame }

-- arms in torso space: x = out to the side for that arm (mirrored), y = up, z = back
local function arm(side: number, dir: Vector3, bendTo: Vector3, bend: number): (CFrame, CFrame)
	local d = V3(dir.X * side, dir.Y, dir.Z)
	local b = V3(bendTo.X * side, bendTo.Y, bendTo.Z)
	return limb(d, b, 1), ANG(rad(bend), 0, 0)
end

local function setArms(p: Pose, dir: Vector3, bendTo: Vector3, bend: number, wristX: number?, asym: number?)
	local a = asym or 0
	p.RightShoulder, p.RightElbow = arm(1, dir + V3(0, a, 0), bendTo, bend + a * 20)
	p.LeftShoulder, p.LeftElbow = arm(-1, dir - V3(0, a, 0), bendTo, bend - a * 20)
	if wristX then
		p.RightWrist = ANG(rad(wristX), 0, 0)
		p.LeftWrist = ANG(rad(wristX), 0, 0)
	end
end

local function lerpPose(a: Pose, b: Pose, k: number): Pose
	local out: Pose = {}
	for name, cf in b do
		local from = a[name] or CFrame.identity
		out[name] = from:Lerp(cf, k)
	end
	for name, cf in a do
		if not b[name] then
			out[name] = cf:Lerp(CFrame.identity, k)
		end
	end
	return out
end

-- the target pose (upper body) for a kind at time t in it
local function upper(st: State, kind: string, t: number, now: number): Pose
	local p: Pose = {}
	local s = st.seed
	if kind == "up" then
		-- 0..0.35 s: flinch, hands come up in front of the face, shoulders hunched
		local raise = backOut((t - 0.22) / 0.55)
		local flinch = smooth(t / 0.12) * (1 - smooth((t - 0.25) / 0.3))
		-- raised: upper arms up and out, forearms up, palms out
		local upDir = V3(0.62, 0.72, -0.12)
		local f1, f2 = V3(0.35, -0.1, -0.93), V3(-0.55, 1, -0.2)
		local rs, re = arm(1, upDir:Lerp(f1, flinch), V3(0, 1, -0.15):Lerp(f2, flinch), 55 + 75 * flinch)
		local ls, le = arm(-1, upDir:Lerp(f1, flinch), V3(0, 1, -0.15):Lerp(f2, flinch), 55 + 75 * flinch)
		local k = math.max(raise, flinch)
		p.RightShoulder = CFrame.identity:Lerp(rs, k) * tremor(s, now, 3.2)
		p.LeftShoulder = CFrame.identity:Lerp(ls, k) * tremor(s + 20, now, 3.2)
		p.RightElbow = CFrame.identity:Lerp(re, k) * ANG(rad(noise(s + 5, now, 8) * 5), 0, 0)
		p.LeftElbow = CFrame.identity:Lerp(le, k) * ANG(rad(noise(s + 25, now, 8) * 5), 0, 0)
		p.RightWrist = ANG(rad(-20 * k), 0, 0)
		p.LeftWrist = ANG(rad(-20 * k), 0, 0)
		-- leaning back from the gun, quick shallow breaths
		local breath = math.sin(now * 2 * math.pi * 1.25 + s) * 1.6
		p.Waist = ANG(rad(-14 * flinch + 6 * raise + breath), 0, rad(noise(s + 9, now, 0.6) * 3))
		p.Root = CF(noise(s + 11, now, 0.45) * 0.08, 0, 0.12 * raise) * ANG(0, 0, rad(noise(s + 13, now, 0.5) * 2))
	elseif kind == "down" then
		-- arms come down onto the back of the head, fingers locked
		local k = smooth((t - 0.15) / 0.75)
		local rs, re = arm(1, V3(0.78, 0.48, 0.18), V3(-1, 0.25, 0.35), 128)
		local ls, le = arm(-1, V3(0.78, 0.48, 0.18), V3(-1, 0.25, 0.35), 128)
		-- coming from "up": the arms were up; this blends through the pose blend, k shapes the settle
		p.RightShoulder = rs:Lerp(rs * ANG(rad(-12), 0, 0), 1 - k) * tremor(s, now, 2.2)
		p.LeftShoulder = ls:Lerp(ls * ANG(rad(-12), 0, 0), 1 - k) * tremor(s + 20, now, 2.2)
		p.RightElbow = re
		p.LeftElbow = le
		p.RightWrist = ANG(rad(35), 0, 0)
		p.LeftWrist = ANG(rad(35), 0, 0)
		-- hunched over, rocking slowly, fast breathing, small shudders
		local rock = math.sin(now * 1.35 + s) * 3.5
		local breath = math.sin(now * 2 * math.pi * 1.1 + s) * 1.8
		local shudder = math.max(0, noise(s + 31, now, 1.7) - 0.55) * 18 * math.sin(now * 38)
		p.Waist = ANG(rad(-20 * k + rock + breath + shudder), rad(noise(s + 9, now, 0.4) * 6), 0)
	elseif kind == "tied" then
		-- wrists together behind the back, shoulders pulled back
		local k = smooth(t / 0.6)
		local rs, re = arm(1, V3(0.22, -0.9, 0.36), V3(-1, 0.35, 0.2), 62)
		local ls, le = arm(-1, V3(0.22, -0.9, 0.36), V3(-1, 0.35, 0.2), 62)
		p.RightShoulder = CFrame.identity:Lerp(rs, k) * tremor(s, now, 1.2)
		p.LeftShoulder = CFrame.identity:Lerp(ls, k) * tremor(s + 20, now, 1.2)
		p.RightElbow = re
		p.LeftElbow = le
		-- slumped, sobbing in bursts (three jerks every few seconds)
		local sob = 0
		local ts = now - st.sobAt
		if ts >= 0 and ts < 1.2 then
			sob = math.max(0, math.sin(ts * math.pi * 2.5)) * 5 * (1 - ts / 1.2)
		end
		local breath = math.sin(now * 2 * math.pi * 0.7 + s) * 1.4
		p.Waist = ANG(rad(-17 * k - sob + breath), rad(noise(s + 9, now, 0.3) * 5), 0)
	end
	return p
end

-- head: darting glances. Hostages mostly look at the floor and glance up at the robbers.
local function head(st: State, kind: string, now: number, dt: number): CFrame
	if now >= st.nextGlance then
		local r = Random.new(math.floor(now * 1000) + math.floor(st.seed * 100))
		if kind == "up" then
			st.wantYaw = r:NextNumber(-40, 40)
			st.wantPitch = r:NextNumber(-12, 12)
			st.nextGlance = now + r:NextNumber(0.5, 1.6)
		elseif kind == "down" then
			local up = r:NextNumber() < 0.35
			st.wantYaw = r:NextNumber(-45, 45)
			st.wantPitch = if up then r:NextNumber(5, 20) else r:NextNumber(-30, -18)
			st.nextGlance = now + (if up then r:NextNumber(0.4, 0.9) else r:NextNumber(1.0, 2.6))
		elseif kind == "tied" then
			local up = r:NextNumber() < 0.2
			st.wantYaw = r:NextNumber(-30, 30)
			st.wantPitch = if up then r:NextNumber(-5, 10) else r:NextNumber(-38, -26)
			st.nextGlance = now + r:NextNumber(1.2, 3.2)
			if r:NextNumber() < 0.35 then
				st.sobAt = now + r:NextNumber(0, 0.8)
			end
		else
			st.wantYaw, st.wantPitch = 0, 0
			st.nextGlance = now + 1
		end
	end
	-- quick, jerky head moves (scared eyes)
	local k = math.min(1, dt * (if kind == "tied" then 4 else 9))
	st.glanceYaw += (st.wantYaw - st.glanceYaw) * k
	st.glancePitch += (st.wantPitch - st.glancePitch) * k
	local jitter = if kind == "none" then 0 else noise(st.seed + 41, now, 10) * 1.5
	return ANG(rad(st.glancePitch + jitter), rad(st.glanceYaw), 0)
end

-- legs from the real hip drop (studs): thighs upright, shins folding back, feet flat behind
local function legs(p: Pose, st: State, drop: number, shin: number, dt: number)
	-- the left leg lags a little: one knee goes down first
	st.dropR += (drop - st.dropR) * math.min(1, dt * 14)
	st.dropL += (drop - st.dropL) * math.min(1, dt * 6)
	for _, side in { "Right", "Left" } do
		local d = if side == "Right" then st.dropR else st.dropL
		if d > 0.01 then
			local c = math.clamp(1 - d / shin, -0.2, 1)
			local knee = math.acos(c)
			local thighLean = rad(8) * math.min(1, d / shin) -- thighs a touch forward
			p[side .. "Hip"] = ANG(thighLean, 0, 0)
			p[side .. "Knee"] = ANG(-knee - thighLean, 0, 0)
			p[side .. "Ankle"] = ANG(-knee * 0.85, 0, 0)
		end
	end
end

-- one frame: the joint rotations for this NPC.
-- kind: current kind; drop: real hip drop (studs, 0 standing); shin: lower leg length (knee to sole)
function NpcPoses.sample(st: State, kind: string, now: number, dt: number, drop: number, shin: number): Pose
	if kind ~= st.kind then
		st.from = st.last
		st.kind = kind
		st.since = now
		st.nextGlance = 0
	end
	local t = now - st.since
	local target = upper(st, kind, t, now)
	target.Neck = head(st, kind, now, dt)
	legs(target, st, drop, shin, dt)
	local blendDur = if kind == "none" then 0.5 elseif kind == "up" then 0.12 else 0.55
	local out = target
	if st.from then
		local k = smooth(t / blendDur)
		if k >= 1 then
			st.from = nil
		else
			-- legs always follow the body exactly (no blend), the rest crossfades
			local blended = lerpPose(st.from :: Pose, target, k)
			for _, j in { "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle" } do
				blended[j] = target[j]
			end
			out = blended
		end
	end
	st.last = out
	return out
end

-- true while this state still has something to show (a pose, a blend, bent legs)
function NpcPoses.busy(st: State): boolean
	if st.kind ~= "none" or st.from ~= nil or st.dropL > 0.02 or st.dropR > 0.02 then
		return true
	end
	for _, cf in st.last do
		if cf ~= CFrame.identity then
			local _, ang = cf:ToAxisAngle()
			if math.abs(ang) > 0.01 or cf.Position.Magnitude > 0.005 then
				return true
			end
		end
	end
	return false
end

return NpcPoses
