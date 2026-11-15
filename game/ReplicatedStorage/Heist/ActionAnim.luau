--!strict
-- ActionAnim: procedural body animations for every action of the heist (zip tie, plant C4, break a
-- window, pick a lock...). An animation is a set of joint keyframes (degrees) plus a body track that
-- lowers the hips (the legs bend by IK so the feet stay on the floor), props held in the hands and
-- timed events (sounds, props). It is played on a character on THIS machine, for the player's own
-- character and for other players' characters alike (the server tells every client with the "Act"
-- event), so everybody sees it. Unspecified joints keep their normal idle animation; the specified
-- ones fade in and out over the idle pose.
--
-- Joint conventions (the rig's own axes): shoulder +X = arm forward/up (90 = horizontal, 180 = straight
-- up), shoulder Z = out to the side (right arm negative, left arm positive); elbow +X = bend; hip +X =
-- thigh forward; knee -X = bend; waist -X = lean forward; neck -X = look down, Y = turn the head.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sfx = require(ReplicatedStorage:WaitForChild("Heist"):WaitForChild("Sfx"))

local AA = {}

type Key = { number } -- { t, x, y, z }
export type Ctx = { char: Model, props: { Instance }, target: CFrame?, extra: any?, rig: any }
export type Def = {
	dur: number,
	loop: boolean?,
	joints: { [string]: { Key } }?,
	body: { Key }?, -- { t, drop (studs), shift (studs forward), 0 }
	rootOnly: boolean?, -- body only moves the hips (no leg IK): for sitting, where the joints set the legs
	events: { { any } }?, -- { t, function(ctx) }
	fade: number?,
}

local RGB = Color3.fromRGB

------------------------------------------------------------------ rig

local JOINT_PARTS = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}

type Rig = { joints: { [string]: any }, upper: number, lower: number }
local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function rigOf(char: Model): Rig?
	local r = rigs[char]
	if r and r.joints.Root and r.joints.Root.Parent then
		return r
	end
	local joints: { [string]: any } = {}
	for name, partName in JOINT_PARTS do
		local part = char:FindFirstChild(partName)
		local j = part and part:FindFirstChild(name)
		if j then
			joints[name] = j
		end
	end
	local ul = char:FindFirstChild("RightUpperLeg") :: BasePart?
	local ll = char:FindFirstChild("RightLowerLeg") :: BasePart?
	local ft = char:FindFirstChild("RightFoot") :: BasePart?
	if not joints.Root or not ul or not ll or not ft then
		return nil
	end
	r = { joints = joints, upper = ul.Size.Y, lower = ll.Size.Y + ft.Size.Y }
	rigs[char] = r
	return r
end

------------------------------------------------------------------ sampling

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function sample(keys: { Key }, t: number): (number, number, number)
	local n = #keys
	if t <= keys[1][1] then
		local k = keys[1]
		return k[2] or 0, k[3] or 0, k[4] or 0
	end
	if t >= keys[n][1] then
		local k = keys[n]
		return k[2] or 0, k[3] or 0, k[4] or 0
	end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if t >= a[1] and t <= b[1] then
			local f = smooth((t - a[1]) / math.max(b[1] - a[1], 1e-4))
			return (a[2] or 0) + ((b[2] or 0) - (a[2] or 0)) * f, (a[3] or 0) + ((b[3] or 0) - (a[3] or 0)) * f, (a[4] or 0) + ((b[4] or 0) - (a[4] or 0)) * f
		end
	end
	return 0, 0, 0
end

-- legs for a hip drop (studs): thigh forward by h, knee bent back by k, ankle flattens the foot
local function legAngles(rig: Rig, drop: number): (number, number, number)
	local a, b = rig.upper, rig.lower
	local L = a + b
	local D = math.clamp(L - drop, L * 0.45, L)
	local cosK = math.clamp((a * a + b * b - D * D) / (2 * a * b), -1, 1)
	local kneeFlex = math.pi - math.acos(cosK)
	local cosH = math.clamp((a * a + D * D - b * b) / (2 * a * D), -1, 1)
	local hip = math.acos(cosH)
	return hip, kneeFlex, kneeFlex - hip -- ankle: keeps the foot flat
end

------------------------------------------------------------------ tracks

type Track = {
	char: Model,
	def: Def,
	t0: number,
	ctx: Ctx,
	fired: { [number]: boolean },
	stopAt: number?, -- fade out from here (loops)
	onDone: (() -> ())?,
}
local tracks: { Track } = {}
local bound = false

local function destroyProps(tr: Track)
	for _, p in tr.ctx.props do
		if p.Parent then
			p:Destroy()
		end
	end
	table.clear(tr.ctx.props)
end

-- the Animator rewrites every animated joint each frame, which would undo our pose: while an action
-- plays, the character's own animation tracks are stopped (and its Animate script paused, for the
-- local player) so the joints keep what we write.
local paused: { [Model]: number } = {}

local function suppressBase(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in (animator :: Animator):GetPlayingAnimationTracks() do
			t:Stop(0)
		end
	end
end

local function pauseBase(char: Model)
	paused[char] = (paused[char] or 0) + 1
	if paused[char] == 1 then
		local animate = char:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then
			animate.Enabled = false
		end
		suppressBase(char)
	end
end

local function resumeBase(char: Model)
	local n = (paused[char] or 1) - 1
	paused[char] = if n > 0 then n else nil
	if n <= 0 then
		local animate = char:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then
			animate.Enabled = true
		end
	end
end

local function apply(tr: Track, now: number): boolean
	local rig = tr.ctx.rig :: Rig
	local def = tr.def
	local t = now - tr.t0
	local fade = def.fade or 0.25
	local w: number
	local tt = t
	if def.loop then
		if tr.stopAt then
			w = 1 - smooth((now - tr.stopAt) / fade)
			if w <= 0 then
				return false
			end
		else
			w = smooth(t / fade)
		end
		tt = t % def.dur
	else
		if t >= def.dur then
			return false
		end
		w = math.min(smooth(t / fade), smooth((def.dur - t) / fade))
	end
	-- events
	if def.events then
		for i, ev in def.events do
			if not tr.fired[i] and t >= ev[1] and (not def.loop or tt >= ev[1]) then
				tr.fired[i] = true
				local ok, err = pcall(ev[2], tr.ctx)
				if not ok then
					warn("[ActionAnim] event", err)
				end
			end
		end
		if def.loop and tt < 0.05 then
			for i, ev2 in def.events do
				if ev2[3] == true then
					tr.fired[i] = nil -- repeating event (third value true)
				end
			end
		end
	end
	suppressBase(tr.char)
	local function setJoint(name: string, cf: CFrame)
		local j = rig.joints[name]
		if j then
			j.Transform = j.Transform:Lerp(cf, w)
		end
	end
	if def.body then
		local drop, shift = sample(def.body, tt)
		setJoint("Root", CFrame.new(0, -drop, shift))
		if not def.rootOnly then
			local hip, knee, ankle = legAngles(rig, drop)
			for _, side in { "Right", "Left" } do
				setJoint(side .. "Hip", CFrame.Angles(hip, 0, 0))
				setJoint(side .. "Knee", CFrame.Angles(-knee, 0, 0))
				setJoint(side .. "Ankle", CFrame.Angles(ankle, 0, 0))
			end
		end
	end
	if def.joints then
		for name, keys in def.joints do
			local x, y, z = sample(keys, tt)
			setJoint(name, CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)))
		end
	end
	return true
end

local function step()
	local now = os.clock()
	for i = #tracks, 1, -1 do
		local tr = tracks[i]
		local alive = tr.char.Parent ~= nil and apply(tr, now)
		if not alive then
			table.remove(tracks, i)
			destroyProps(tr)
			resumeBase(tr.char)
			if tr.onDone then
				task.defer(tr.onDone)
			end
		end
	end
end

local function ensureBound()
	if bound or not RunService:IsClient() then
		return
	end
	bound = true
	-- after the Animator has written this frame's idle pose (it runs before the simulation step), so
	-- ours is applied on top of it
	RunService.PreSimulation:Connect(step)
end

------------------------------------------------------------------ props and sound helpers (for the defs)

local function holdProp(ctx: Ctx, hand: string, part: BasePart, offset: CFrame)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local h = ctx.char:FindFirstChild(hand) :: BasePart?
	if not h then
		part:Destroy()
		return
	end
	part.CFrame = h.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = h
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	part.Parent = ctx.char
	table.insert(ctx.props, part)
end
AA.holdProp = holdProp

local function mk(name: string, size: Vector3, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end
AA.mk = mk

local function sub(parent: BasePart, name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = mk(name, size, color, mat)
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = parent.CFrame * off
	local w = Instance.new("WeldConstraint")
	w.Part0 = parent
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end
AA.sub = sub

local function snd(ctx: Ctx, name: string, vol: number?, pitch: number?)
	local root = ctx.char:FindFirstChild("HumanoidRootPart")
	if root then
		Sfx.play(name, root, vol or 0.4, pitch or 1, 60)
	end
end
AA.snd = snd

-- a C4 brick with a red LED, to hold in a hand
local function c4Brick(): BasePart
	local b = mk("C4", Vector3.new(0.5, 0.3, 0.9), RGB(214, 190, 120))
	sub(b, "Led", Vector3.new(0.12, 0.08, 0.12), CFrame.new(0, 0.18, -0.3), RGB(255, 40, 40), Enum.Material.Neon)
	sub(b, "Wire", Vector3.new(0.04, 0.04, 0.5), CFrame.new(0.12, 0.17, 0.1), RGB(30, 30, 30))
	return b
end
AA.c4Brick = c4Brick

------------------------------------------------------------------ the animations

local D: { [string]: Def } = {}
AA.defs = D

-- shorthand for the idle arms: shoulders hang down
local function arms(key: number, rs: { number }, re: number, ls: { number }, le: number): { [string]: Key }
	return {
		RightShoulder = { key, rs[1], rs[2] or 0, rs[3] or 0 },
		RightElbow = { key, re, 0, 0 },
		LeftShoulder = { key, ls[1], ls[2] or 0, ls[3] or 0 },
		LeftElbow = { key, le, 0, 0 },
	}
end
local _ = arms

D.zipTie = {
	dur = 3.0,
	body = { { 0, 0 }, { 0.5, 0.95, 0.15 }, { 2.5, 0.95, 0.15 }, { 3.0, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.5, -26 }, { 2.5, -26 }, { 3.0, 0 } },
		Neck = { { 0, 0 }, { 0.6, -22 }, { 2.4, -22 }, { 3.0, 0 } },
		-- right hand: to the belt for the tie, then in front to loop it round the wrists, two hard tugs
		RightShoulder = { { 0, 0, 0, 0 }, { 0.5, 25, 0, -14 }, { 0.8, 18, 0, -16 }, { 1.2, 62, 0, -8 }, { 1.5, 70, 12, -6 }, { 1.8, 68, -12, -6 }, { 2.05, 70, 0, -6 }, { 2.25, 38, 0, -10 }, { 2.4, 68, 0, -6 }, { 2.55, 36, 0, -10 }, { 3.0, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.5, 40 }, { 0.8, 70 }, { 1.2, 85 }, { 1.8, 78 }, { 2.05, 80 }, { 2.25, 40 }, { 2.4, 78 }, { 2.55, 35 }, { 3.0, 0 } },
		-- left hand holds the captive's wrists out in front
		LeftShoulder = { { 0, 0 }, { 0.5, 62, 0, 8 }, { 2.7, 62, 0, 8 }, { 3.0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.5, 60 }, { 2.7, 60 }, { 3.0, 0 } },
	},
	events = {
		{ 0.8, function(c)
			local z = mk("ZipTie", Vector3.new(0.06, 0.04, 0.55), RGB(25, 25, 28))
			sub(z, "Head", Vector3.new(0.12, 0.1, 0.12), CFrame.new(0, 0, 0.27), RGB(20, 20, 22))
			holdProp(c, "RightHand", z, CFrame.new(0, -0.15, -0.35) * CFrame.Angles(math.rad(-90), 0, 0))
		end },
		{ 1.3, function(c) snd(c, "clank", 0.12, 2.2) end },
		{ 2.05, function(c) snd(c, "clank", 0.3, 1.8) end },
		{ 2.4, function(c) snd(c, "clank", 0.35, 1.6) end },
	},
}

D.c4Place = {
	dur = 4.2,
	body = { { 0, 0 }, { 0.6, 0.75, 0.2 }, { 3.2, 0.75, 0.2 }, { 4.0, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.6, -14 }, { 2.0, -20 }, { 3.2, -14 }, { 4.2, 0 } },
		Neck = { { 0, 0 }, { 0.5, -10 }, { 1.6, -18 }, { 3.2, -12 }, { 4.2, 0 } },
		-- right hand to the vest, takes the charge; both hands carry it to the wall and press it on
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 28, 0, -16 }, { 0.9, 24, 0, -14 }, { 1.5, 92, 0, -6 }, { 2.0, 96, 0, -5 }, { 2.3, 108, 0, -5 }, { 2.5, 96, 0, -5 }, { 3.0, 80, 0, -8 }, { 3.5, 40, 0, -8 }, { 4.2, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.4, 100 }, { 0.9, 112 }, { 1.5, 38 }, { 2.0, 20 }, { 2.3, 8 }, { 3.0, 50 }, { 3.5, 60 }, { 4.2, 0 } },
		LeftShoulder = { { 0, 0 }, { 0.9, 0 }, { 1.4, 90, 0, 6 }, { 2.0, 96, 0, 6 }, { 2.3, 108, 0, 5 }, { 2.7, 90, 0, 8 }, { 3.0, 70, 0, 6 }, { 3.5, 30, 0, 6 }, { 4.2, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.9, 0 }, { 1.4, 40 }, { 2.0, 22 }, { 2.3, 10 }, { 2.7, 50 }, { 3.0, 80 }, { 3.5, 60 }, { 4.2, 0 } },
	},
	events = {
		{ 0.9, function(c)
			holdProp(c, "RightHand", c4Brick(), CFrame.new(0, -0.2, -0.4) * CFrame.Angles(math.rad(-90), 0, 0))
			snd(c, "pop", 0.25, 1.3)
		end },
		{ 2.3, function(c)
			snd(c, "thud", 0.35, 1.8)
		end },
		{ 2.55, function(c)
			-- the charge stays on the wall (the server's planted brick takes over)
			for _, p in c.props do
				p:Destroy()
			end
			table.clear(c.props)
		end },
		{ 3.0, function(c) snd(c, "beep", 0.4, 1.4) end },
	},
}

D.glassBreak = {
	dur = 1.4,
	body = { { 0, 0 }, { 0.3, 0.2, 0 }, { 0.6, 0.15, 0.1 }, { 1.4, 0 } },
	joints = {
		Waist = { { 0, 0, 0, 0 }, { 0.35, 6, 28, 0 }, { 0.58, -14, -32, 0 }, { 1.0, -4, -10, 0 }, { 1.4, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.35, 150, 0, -35 }, { 0.58, 62, 0, -10 }, { 1.0, 40, 0, -8 }, { 1.4, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.35, 85 }, { 0.58, 12 }, { 1.0, 30 }, { 1.4, 0 } },
		LeftShoulder = { { 0, 0 }, { 0.35, 40, 0, 20 }, { 0.58, 20, 0, 12 }, { 1.4, 0 } },
		Neck = { { 0, 0 }, { 0.58, -8, 15, 0 }, { 1.4, 0 } },
	},
	events = { { 0.57, function(c) snd(c, "thud", 0.5, 1.2) end } },
}


-- a bag of cash in the hands (for pick up / load)
local function bagProp(): BasePart
	local b = mk("Bag", Vector3.new(1.3, 1.0, 0.9), RGB(40, 90, 55), Enum.Material.Fabric)
	sub(b, "Strap", Vector3.new(1.0, 0.12, 0.95), CFrame.new(0, 0.3, 0), RGB(25, 60, 35), Enum.Material.Fabric)
	sub(b, "Cash", Vector3.new(0.7, 0.12, 0.5), CFrame.new(0, 0.52, 0), RGB(120, 190, 110))
	return b
end

D.pickup = {
	dur = 1.5,
	body = { { 0, 0 }, { 0.45, 0.95, 0.2 }, { 0.75, 0.95, 0.2 }, { 1.2, 0.2, 0 }, { 1.5, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.45, -38 }, { 0.75, -38 }, { 1.2, -6 }, { 1.5, 0 } },
		Neck = { { 0, 0 }, { 0.45, 10 }, { 0.75, -6 }, { 1.5, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.45, 50, 0, -12 }, { 0.75, 44, 0, -10 }, { 1.2, 55, 0, -6 }, { 1.5, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.45, 12 }, { 0.75, 28 }, { 1.2, 95 }, { 1.5, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.45, 46, 0, 12 }, { 0.75, 40, 0, 10 }, { 1.2, 55, 0, 6 }, { 1.5, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.45, 10 }, { 0.75, 26 }, { 1.2, 92 }, { 1.5, 0 } },
	},
	events = {
		{ 0.72, function(c)
			snd(c, "boing", 0.15, 1.8)
		end },
	},
}

D.loadBag = {
	dur = 1.7,
	body = { { 0, 0 }, { 0.35, 0.25, -0.1 }, { 0.75, 0.1, 0.25 }, { 1.7, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.35, 4 }, { 0.75, -24 }, { 1.1, -6 }, { 1.7, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.1, 55, 0, -10 }, { 0.35, 22, 0, -14 }, { 0.75, 128, 0, -8 }, { 1.1, 85, 0, -8 }, { 1.7, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.1, 90 }, { 0.35, 100 }, { 0.75, 18 }, { 1.1, 30 }, { 1.7, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.1, 55, 0, 10 }, { 0.35, 22, 0, 14 }, { 0.75, 128, 0, 8 }, { 1.1, 85, 0, 8 }, { 1.7, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.1, 90 }, { 0.35, 100 }, { 0.75, 18 }, { 1.1, 30 }, { 1.7, 0 } },
	},
	events = {
		{ 0.0, function(c) holdProp(c, "RightHand", bagProp(), CFrame.new(-0.6, -0.5, -0.3)) end },
		{ 0.78, function(c)
			for _, p in c.props do
				p:Destroy()
			end
			table.clear(c.props)
			snd(c, "thud", 0.3, 1.1)
		end },
	},
}

D.throwBag = {
	dur = 0.9,
	body = { { 0, 0 }, { 0.25, 0.2, -0.15 }, { 0.45, 0.1, 0.3 }, { 0.9, 0 } },
	joints = {
		Waist = { { 0, 0, 0, 0 }, { 0.25, 6, 38, 0 }, { 0.45, -14, -34, 0 }, { 0.9, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.25, -35, 0, -20 }, { 0.45, 135, 0, -6 }, { 0.9, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.25, 75 }, { 0.45, 8 }, { 0.9, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.25, 60, 0, 24 }, { 0.45, 30, 0, 18 }, { 0.9, 0, 0, 0 } },
	},
	events = { { 0.44, function(c) snd(c, "whoosh", 0.3, 1.2) end } },
}

D.locker = {
	dur = 2.8,
	body = { { 0, 0 }, { 0.4, 0.3, 0.1 }, { 2.3, 0.3, 0.1 }, { 2.8, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.4, -10 }, { 1.4, -4 }, { 1.9, 6 }, { 2.2, -12 }, { 2.8, 0 } },
		Neck = { { 0, 0 }, { 0.4, -12 }, { 1.0, -14 }, { 2.8, 0 } },
		-- right hand at the latch: three quick picks, then yanks the door open, then reaches in
		RightShoulder = { { 0, 0, 0, 0 }, { 0.35, 82, 0, -8 }, { 0.5, 84, 0, -8 }, { 0.62, 80, 0, -8 }, { 0.78, 84, 0, -8 }, { 0.9, 80, 0, -8 }, { 1.05, 83, 0, -8 }, { 1.2, 82, 0, -8 }, { 1.6, 70, 0, -10 }, { 1.95, 92, 0, -6 }, { 2.25, 40, 0, -10 }, { 2.8, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.35, 32 }, { 0.5, 38 }, { 0.62, 30 }, { 0.78, 38 }, { 0.9, 30 }, { 1.05, 36 }, { 1.2, 34 }, { 1.6, 105 }, { 1.95, 28 }, { 2.25, 110 }, { 2.8, 0 } },
		RightWrist = { { 0, 0 }, { 0.4, 0 }, { 0.5, 14 }, { 0.62, -14 }, { 0.78, 14 }, { 0.9, -14 }, { 1.05, 14 }, { 1.2, 0 }, { 2.8, 0 } },
		LeftShoulder = { { 0, 0 }, { 0.4, 78, 0, 8 }, { 1.5, 78, 0, 8 }, { 1.9, 60, 0, 10 }, { 2.3, 55, 0, 8 }, { 2.8, 0 } },
		LeftElbow = { { 0, 0 }, { 0.4, 25 }, { 1.5, 25 }, { 1.9, 60 }, { 2.3, 90 }, { 2.8, 0 } },
	},
	events = {
		{ 0.5, function(c) snd(c, "key", 0.18, 2.2) end },
		{ 0.78, function(c) snd(c, "key", 0.18, 2.0) end },
		{ 1.05, function(c) snd(c, "key", 0.2, 2.4) end },
		{ 1.3, function(c) snd(c, "clank", 0.3, 1.3) end },
		{ 1.65, function(c) snd(c, "door", 0.2, 1.4) end },
		{ 2.2, function(c) snd(c, "cash", 0.3, 1.0) end },
	},
}

-- typing on a keypad / a hacking device (loops while the hack minigame runs)
D.hackType = {
	dur = 1.6,
	loop = true,
	body = { { 0, 0.1 }, { 0.8, 0.15 }, { 1.6, 0.1 } },
	joints = {
		Waist = { { 0, -8 }, { 0.8, -10 }, { 1.6, -8 } },
		Neck = { { 0, -16, 6, 0 }, { 0.5, -18, -5, 0 }, { 1.1, -14, 8, 0 }, { 1.6, -16, 6, 0 } },
		-- left hand holds the device, the right fingers tap
		LeftShoulder = { { 0, 38, 0, 8 }, { 1.6, 38, 0, 8 } },
		LeftElbow = { { 0, 100 }, { 1.6, 100 } },
		RightShoulder = { { 0, 46, 0, -10 }, { 0.2, 50, 0, -10 }, { 0.4, 45, 0, -10 }, { 0.6, 51, 0, -10 }, { 0.8, 46, 0, -10 }, { 1.0, 50, 0, -10 }, { 1.2, 45, 0, -10 }, { 1.4, 51, 0, -10 }, { 1.6, 46, 0, -10 } },
		RightElbow = { { 0, 96 }, { 0.2, 88 }, { 0.4, 98 }, { 0.6, 86 }, { 0.8, 96 }, { 1.0, 88 }, { 1.2, 98 }, { 1.4, 86 }, { 1.6, 96 } },
		RightWrist = { { 0, 0 }, { 0.1, 12 }, { 0.2, -6 }, { 0.3, 10 }, { 0.4, -8 }, { 0.5, 12 }, { 0.6, -6 }, { 0.7, 10 }, { 0.8, 0 }, { 1.6, 0 } },
	},
	events = {
		{ 0.0, function(c)
			local d = mk("Device", Vector3.new(0.9, 0.12, 0.6), RGB(30, 34, 40), Enum.Material.Metal)
			sub(d, "Screen", Vector3.new(0.75, 0.04, 0.45), CFrame.new(0, 0.07, 0), RGB(60, 255, 120), Enum.Material.Neon)
			holdProp(c, "LeftHand", d, CFrame.new(0, -0.2, -0.4) * CFrame.Angles(math.rad(-60), 0, 0))
		end },
		{ 0.2, function(c) snd(c, "key", 0.1, 2.4) end, true },
		{ 0.6, function(c) snd(c, "key", 0.1, 2.6) end, true },
		{ 1.0, function(c) snd(c, "key", 0.1, 2.3) end, true },
	},
}

-- mounting the heavy drill on the vault door: carry, set down, tighten the clamps, pull the trigger
D.drillMount = {
	dur = 5.2,
	body = { { 0, 0.15, 0 }, { 1.0, 0.2, 0.1 }, { 1.8, 0.8, 0.25 }, { 3.6, 0.8, 0.25 }, { 4.4, 0.1, -0.2 }, { 5.2, 0 } },
	joints = {
		Waist = { { 0, -10 }, { 1.0, -12 }, { 1.8, -22 }, { 3.6, -18 }, { 4.4, 4 }, { 5.2, 0 } },
		Neck = { { 0, -6 }, { 1.8, -16 }, { 3.6, -14 }, { 5.2, 0 } },
		RightShoulder = { { 0, 62, 0, -8 }, { 1.0, 64, 0, -8 }, { 1.6, 96, 0, -6 }, { 2.0, 98, 0, -6 }, { 2.3, 92, 8, -6 }, { 2.6, 98, -8, -6 }, { 2.9, 92, 8, -6 }, { 3.2, 100, 0, -6 }, { 3.5, 96, 0, -6 }, { 4.0, 60, 0, -8 }, { 5.2, 0, 0, 0 } },
		RightElbow = { { 0, 72 }, { 1.0, 72 }, { 1.6, 30 }, { 3.2, 26 }, { 3.5, 40 }, { 4.0, 70 }, { 5.2, 0 } },
		LeftShoulder = { { 0, 60, 0, 8 }, { 1.0, 62, 0, 8 }, { 1.6, 92, 0, 6 }, { 3.6, 94, 0, 6 }, { 4.2, 50, 0, 8 }, { 5.2, 0, 0, 0 } },
		LeftElbow = { { 0, 74 }, { 1.0, 74 }, { 1.6, 34 }, { 3.6, 34 }, { 4.2, 70 }, { 5.2, 0 } },
	},
	events = {
		{ 0.0, function(c)
			local d = mk("DrillCarry", Vector3.new(1.4, 1.2, 2.0), RGB(245, 205, 48))
			sub(d, "Bit", Vector3.new(0.3, 0.3, 1.1), CFrame.new(0, 0, -1.4), RGB(170, 174, 180), Enum.Material.Metal)
			sub(d, "Handle", Vector3.new(0.3, 0.9, 0.3), CFrame.new(0, -0.9, 0.3), RGB(40, 40, 44))
			holdProp(c, "RightHand", d, CFrame.new(0.2, -0.3, -1.0))
		end },
		{ 1.9, function(c) snd(c, "clank", 0.4, 0.9) end },
		{ 2.3, function(c) snd(c, "clank", 0.25, 1.5) end },
		{ 2.9, function(c) snd(c, "clank", 0.25, 1.4) end },
		{ 3.2, function(c)
			for _, p in c.props do
				p:Destroy()
			end
			table.clear(c.props)
			snd(c, "drill", 0.35, 1.0)
		end },
	},
}

D.fixDrill = {
	dur = 2.6,
	body = { { 0, 0 }, { 0.4, 0.85, 0.2 }, { 2.0, 0.85, 0.2 }, { 2.6, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.4, -24 }, { 2.0, -22 }, { 2.6, 0 } },
		Neck = { { 0, 0 }, { 0.4, -16 }, { 2.0, -14 }, { 2.6, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 70, 0, -10 }, { 0.7, 92, 0, -10 }, { 1.0, 66, 0, -10 }, { 1.3, 94, 0, -10 }, { 1.6, 66, 0, -10 }, { 1.9, 96, 0, -10 }, { 2.1, 60, 0, -10 }, { 2.6, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.4, 50 }, { 0.7, 38 }, { 1.0, 70 }, { 1.3, 36 }, { 1.6, 70 }, { 1.9, 34 }, { 2.1, 60 }, { 2.6, 0 } },
		RightWrist = { { 0, 0 }, { 0.7, 0, 0, 25 }, { 1.0, 0, 0, -25 }, { 1.3, 0, 0, 25 }, { 1.6, 0, 0, -25 }, { 1.9, 0, 0, 25 }, { 2.6, 0 } },
		LeftShoulder = { { 0, 0 }, { 0.4, 78, 0, 8 }, { 2.0, 78, 0, 8 }, { 2.4, 40, 0, 8 }, { 2.6, 0 } },
		LeftElbow = { { 0, 0 }, { 0.4, 50 }, { 2.0, 50 }, { 2.6, 0 } },
	},
	events = {
		{ 0.7, function(c) snd(c, "clank", 0.2, 1.6) end },
		{ 1.3, function(c) snd(c, "clank", 0.2, 1.5) end },
		{ 1.9, function(c) snd(c, "clank", 0.3, 1.4) end },
		{ 2.05, function(c) snd(c, "thud", 0.3, 1.0) end },
	},
}

D.cardSwipe = {
	dur = 3.6,
	body = { { 0, 0 }, { 1.7, 0.05, 0.1 }, { 2.4, 0.05, 0.25 }, { 3.6, 0 } },
	joints = {
		Waist = { { 0, 0, 0, 0 }, { 0.6, 4, 0, 0 }, { 1.2, 6, 0, 0 }, { 1.9, -10, 0, 0 }, { 2.4, -12, 0, 0 }, { 3.0, 0, 0, 0 }, { 3.6, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.8, 8, 0, 0 }, { 1.3, -4, 12, 0 }, { 1.9, -10, 0, 0 }, { 2.6, 0, 0, 0 }, { 3.6, 0, 0, 0 } },
		-- right hand: chest pocket, out and up (the card catches the light), a little twirl, to the reader, swipe, away
		RightShoulder = { { 0, 0, 0, 0 }, { 0.5, 30, 0, -18 }, { 0.9, 36, 0, -14 }, { 1.4, 82, 0, -16 }, { 1.7, 90, 0, -10 }, { 1.95, 98, 0, -6 }, { 2.2, 98, 0, -6 }, { 2.5, 78, 0, -8 }, { 3.0, 34, 0, -10 }, { 3.6, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.5, 105 }, { 0.9, 112 }, { 1.4, 98 }, { 1.7, 40 }, { 1.95, 14 }, { 2.2, 16 }, { 2.5, 60 }, { 3.0, 90 }, { 3.6, 0 } },
		RightWrist = { { 0, 0 }, { 1.0, 0, 0, 0 }, { 1.2, 0, 0, -140 }, { 1.4, 0, 0, -330 }, { 1.5, 0, 0, 0 }, { 2.0, 0, 0, 0 }, { 2.2, 18, 0, 0 }, { 2.5, 0 }, { 3.6, 0 } },
		LeftShoulder = { { 0, 0 }, { 2.4, 0 }, { 2.7, 80, 0, 24 }, { 3.0, 120, 0, 20 }, { 3.2, 110, 0, 20 }, { 3.6, 0 } },
		LeftElbow = { { 0, 0 }, { 2.4, 0 }, { 2.7, 90 }, { 3.0, 100 }, { 3.6, 0 } },
	},
	events = {
		{ 0.55, function(c)
			local card = mk("Card", Vector3.new(0.5, 0.04, 0.34), RGB(230, 180, 40), Enum.Material.Metal)
			sub(card, "Stripe", Vector3.new(0.5, 0.045, 0.08), CFrame.new(0, 0, 0.08), RGB(30, 30, 30))
			holdProp(c, "RightHand", card, CFrame.new(0, -0.25, -0.3) * CFrame.Angles(math.rad(-90), 0, 0))
			snd(c, "pop", 0.2, 1.8)
		end },
		{ 1.3, function(c) snd(c, "whoosh", 0.2, 1.8) end },
		{ 2.05, function(c) snd(c, "key", 0.3, 1.2) end },
		{ 2.25, function(c) snd(c, "beep", 0.4, 1.7) end },
		{ 2.7, function(c)
			for _, p in c.props do
				p:Destroy()
			end
			table.clear(c.props)
		end },
	},
}

-- climbing a rope hand over hand (loops)
D.ropeClimb = {
	dur = 1.2,
	loop = true,
	body = { { 0, 0.4 }, { 0.3, 0.55 }, { 0.6, 0.4 }, { 0.9, 0.55 }, { 1.2, 0.4 } },
	joints = {
		Waist = { { 0, 6 }, { 1.2, 6 } },
		RightShoulder = { { 0, 158, 0, -8 }, { 0.6, 176, 0, -8 }, { 1.2, 158, 0, -8 } },
		RightElbow = { { 0, 60 }, { 0.6, 8 }, { 1.2, 60 } },
		LeftShoulder = { { 0, 176, 0, 8 }, { 0.6, 158, 0, 8 }, { 1.2, 176, 0, 8 } },
		LeftElbow = { { 0, 8 }, { 0.6, 60 }, { 1.2, 8 } },
		Neck = { { 0, 14, 0, 0 }, { 1.2, 14, 0, 0 } },
	},
	events = { { 0.3, function(c) snd(c, "rope", 0.18, 1.2) end, true } },
}

D.pickpocket = {
	dur = 2.0,
	body = { { 0, 0 }, { 0.4, 0.2, 0.15 }, { 1.6, 0.2, 0.15 }, { 2.0, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.4, -14 }, { 1.2, -16 }, { 2.0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.4, -6, 22, 0 }, { 1.4, -4, 24, 0 }, { 2.0, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 28, 0, -20 }, { 0.8, 48, 6, -10 }, { 1.0, 46, -4, -10 }, { 1.2, 50, 4, -10 }, { 1.5, 30, 0, -16 }, { 2.0, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.4, 40 }, { 0.8, 28 }, { 1.2, 32 }, { 1.5, 90 }, { 2.0, 0 } },
		RightWrist = { { 0, 0 }, { 0.8, -10 }, { 1.0, 12 }, { 1.2, -8 }, { 2.0, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.4, 12, 0, 14 }, { 1.6, 12, 0, 14 }, { 2.0, 0, 0, 0 } },
	},
	events = {
		{ 1.2, function(c)
			local card = mk("Card", Vector3.new(0.5, 0.04, 0.34), RGB(230, 180, 40), Enum.Material.Metal)
			holdProp(c, "RightHand", card, CFrame.new(0, -0.25, -0.3) * CFrame.Angles(math.rad(-90), 0, 0))
			snd(c, "pop", 0.15, 2.0)
		end },
	},
}

-- a push / press: doors, buttons, switches
D.interact = {
	dur = 0.95,
	joints = {
		Waist = { { 0, 0 }, { 0.3, -6 }, { 0.95, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.28, 86, 0, -6 }, { 0.45, 90, 0, -6 }, { 0.95, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.28, 34 }, { 0.45, 18 }, { 0.95, 0 } },
		Neck = { { 0, 0 }, { 0.3, -6 }, { 0.95, 0 } },
	},
	events = { { 0.42, function(c) snd(c, "pop", 0.15, 1.4) end } },
}

-- "À TERRE !": a free arm points, the chin goes up, a barked shout
D.shout = {
	dur = 1.3,
	joints = {
		Waist = { { 0, 0 }, { 0.2, 7 }, { 0.9, 5 }, { 1.3, 0 } },
		Neck = { { 0, 0 }, { 0.2, 14 }, { 0.9, 10 }, { 1.3, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.2, 98, 0, 22 }, { 0.35, 104, 0, 16 }, { 0.9, 100, 0, 18 }, { 1.3, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.2, 14 }, { 0.35, 6 }, { 1.3, 0 } },
	},
}

-- a gadget held out in both hands (EMP): hold, thumb on the button, flash
D.gadget = {
	dur = 1.9,
	joints = {
		Waist = { { 0, 0 }, { 0.3, -6 }, { 1.6, -4 }, { 1.9, 0 } },
		Neck = { { 0, 0 }, { 0.3, -14 }, { 1.6, -10 }, { 1.9, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.3, 58, 0, -10 }, { 1.1, 60, 0, -10 }, { 1.25, 66, 0, -10 }, { 1.6, 56, 0, -10 }, { 1.9, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.3, 78 }, { 1.1, 78 }, { 1.25, 64 }, { 1.9, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.3, 56, 0, 12 }, { 1.6, 56, 0, 12 }, { 1.9, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.3, 80 }, { 1.6, 80 }, { 1.9, 0 } },
	},
	events = {
		{ 0.1, function(c)
			local d = mk("Gadget", Vector3.new(0.8, 0.5, 1.1), RGB(50, 60, 80), Enum.Material.Metal)
			sub(d, "Dish", Vector3.new(0.5, 0.15, 0.5), CFrame.new(0, 0.3, -0.2), RGB(120, 200, 255), Enum.Material.Neon)
			holdProp(c, "RightHand", d, CFrame.new(0, -0.1, -0.5))
		end },
		{ 1.2, function(c) snd(c, "zap", 0.4, 1.0) end },
	},
}

-- seated in a vehicle (used by the cinematics' clones): hips and knees at 90 degrees, hands on the lap
D.sit = {
	dur = 1.0,
	loop = true,
	rootOnly = true,
	body = { { 0, 1.15, 0 }, { 1.0, 1.15, 0 } },
	joints = {
		RightHip = { { 0, 88 }, { 1, 88 } },
		LeftHip = { { 0, 88 }, { 1, 88 } },
		RightKnee = { { 0, -88 }, { 1, -88 } },
		LeftKnee = { { 0, -88 }, { 1, -88 } },
		RightAnkle = { { 0, 0 }, { 1, 0 } },
		LeftAnkle = { { 0, 0 }, { 1, 0 } },
		RightShoulder = { { 0, 22, 0, -6 }, { 1, 22, 0, -6 } },
		LeftShoulder = { { 0, 22, 0, 6 }, { 1, 22, 0, 6 } },
		RightElbow = { { 0, 70 }, { 1, 70 } },
		LeftElbow = { { 0, 70 }, { 1, 70 } },
	},
}

-- a quick hand on the van's door handle, then pulling it open (cinematics)
D.openDoor = {
	dur = 1.2,
	joints = {
		Waist = { { 0, 0 }, { 0.4, -8 }, { 0.8, 4 }, { 1.2, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.3, 70, 0, -12 }, { 0.5, 76, 0, -12 }, { 0.9, 40, 0, -14 }, { 1.2, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.3, 30 }, { 0.5, 36 }, { 0.9, 100 }, { 1.2, 0 } },
	},
}

-- scouting: rummaging through a dumpster / a truck: crouch, both hands digging in turn, a find
D.search = {
	dur = 2.1,
	body = { { 0, 0 }, { 0.35, 0.55, 0.15 }, { 1.7, 0.55, 0.15 }, { 2.1, 0 } },
	joints = {
		Waist = { { 0, 0, 0, 0 }, { 0.35, -28, 0, 0 }, { 0.7, -30, 8, 0 }, { 1.05, -27, -8, 0 }, { 1.4, -30, 6, 0 }, { 1.7, -14, 0, 0 }, { 2.1, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.35, -22, 0, 0 }, { 0.8, -20, 12, 0 }, { 1.2, -24, -10, 0 }, { 1.55, -8, 0, 0 }, { 2.1, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.35, 62, 0, -8 }, { 0.55, 48, 0, -10 }, { 0.75, 66, 0, -6 }, { 0.95, 50, 0, -10 }, { 1.15, 64, 0, -8 }, { 1.45, 92, 0, -6 }, { 1.7, 70, 0, -8 }, { 2.1, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.35, 30 }, { 0.55, 60 }, { 0.75, 25 }, { 0.95, 62 }, { 1.15, 28 }, { 1.45, 70 }, { 1.7, 85 }, { 2.1, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.35, 50, 0, 8 }, { 0.55, 66, 0, 6 }, { 0.75, 48, 0, 10 }, { 0.95, 64, 0, 6 }, { 1.15, 50, 0, 10 }, { 1.45, 40, 0, 10 }, { 2.1, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.35, 62 }, { 0.55, 25 }, { 0.75, 60 }, { 0.95, 28 }, { 1.15, 58 }, { 1.45, 40 }, { 2.1, 0 } },
	},
	events = {
		{ 0.5, function(c) snd(c, "clank", 0.12, 1.4) end },
		{ 0.9, function(c) snd(c, "pop", 0.1, 0.8) end },
		{ 1.25, function(c) snd(c, "clank", 0.15, 1.2) end },
		{ 1.45, function(c)
			-- a crumpled sheet of paper comes up in the hand
			local paper = mk("Paper", Vector3.new(0.5, 0.04, 0.6), RGB(240, 236, 220))
			holdProp(c, "RightHand", paper, CFrame.new(0, -0.2, -0.3) * CFrame.Angles(math.rad(-70), 0, math.rad(10)))
		end },
	},
}

-- scouting: eavesdropping: casual lean toward the voices, hand cupped at the ear, head cocked
D.listen = {
	dur = 2.2,
	joints = {
		Waist = { { 0, 0, 0, 0 }, { 0.4, -6, 14, 4 }, { 1.8, -7, 16, 5 }, { 2.2, 0, 0, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.4, 4, 26, 14 }, { 1.0, 2, 30, 16 }, { 1.5, 5, 24, 12 }, { 1.8, 0, 20, 10 }, { 2.2, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 120, 0, -40 }, { 1.8, 122, 0, -42 }, { 2.2, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.4, 138 }, { 1.8, 140 }, { 2.2, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.4, 8, 0, 4 }, { 2.2, 0, 0, 0 } },
	},
	events = { { 1.6, function(c) snd(c, "pop", 0.08, 1.8) end } },
}

-- scouting: reading a notice: lean in, eyes running down the lines, a little nod
D.read = {
	dur = 2.2,
	body = { { 0, 0 }, { 0.4, 0.1, 0.2 }, { 1.8, 0.1, 0.2 }, { 2.2, 0 } },
	joints = {
		Waist = { { 0, 0 }, { 0.4, -10 }, { 1.8, -10 }, { 2.2, 0 } },
		Neck = { { 0, 0, 0, 0 }, { 0.4, -4, 14, 0 }, { 0.7, -6, -12, 0 }, { 0.95, -10, 14, 0 }, { 1.25, -12, -12, 0 }, { 1.5, -16, 10, 0 }, { 1.75, -6, 0, 0 }, { 1.9, -14, 0, 0 }, { 2.2, 0, 0, 0 } },
		RightShoulder = { { 0, 0, 0, 0 }, { 0.4, 30, 0, -14 }, { 1.8, 30, 0, -14 }, { 2.2, 0, 0, 0 } },
		RightElbow = { { 0, 0 }, { 0.4, 120 }, { 1.8, 122 }, { 2.2, 0 } },
		LeftShoulder = { { 0, 0, 0, 0 }, { 0.4, 26, 0, 16 }, { 1.8, 26, 0, 16 }, { 2.2, 0, 0, 0 } },
		LeftElbow = { { 0, 0 }, { 0.4, 95 }, { 1.8, 95 }, { 2.2, 0 } },
	},
}

AA.dur = function(name: string): number
	local d = D[name]
	return if d then d.dur else 0
end

------------------------------------------------------------------ public

-- play `name` on `char`. opts: target (CFrame), extra, onDone. Returns a handle with :stop().
function AA.play(char: Model, name: string, opts: { target: CFrame?, extra: any?, onDone: (() -> ())? }?): { stop: () -> () }?
	local def = D[name]
	local rig = rigOf(char)
	if not def or not rig then
		return nil
	end
	ensureBound()
	local o = opts or {}
	local ctx: Ctx = { char = char, props = {}, target = o.target, extra = o.extra, rig = rig }
	local tr: Track = { char = char, def = def, t0 = os.clock(), ctx = ctx, fired = {}, stopAt = nil, onDone = o.onDone }
	table.insert(tracks, tr)
	pauseBase(char)
	return {
		stop = function()
			if def.loop then
				tr.stopAt = os.clock()
			else
				tr.t0 = os.clock() - def.dur + 0.2 -- run out the fade
			end
		end,
	}
end

-- a held static pose (seated, etc.) until stop(); keys are just values
function AA.stopAll(char: Model)
	for _, tr in tracks do
		if tr.char == char then
			tr.stopAt = os.clock()
			tr.t0 = os.clock() - tr.def.dur + 0.1
		end
	end
end

function AA.isPlaying(char: Model): boolean
	for _, tr in tracks do
		if tr.char == char then
			return true
		end
	end
	return false
end

local _p = Players
return AA
