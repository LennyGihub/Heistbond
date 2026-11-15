--!strict
-- Procedural reload animation, played on every client (own gun and other players' guns).
-- A reload is a choreography of the left hand (its IK target, Handle.LeftHandIK), the magazine (moved
-- with the hand, hidden, or seated), the gun's own motion (rolled to show the mag well, jolted by the
-- slap and the charging handle) and timed events: sounds for every step, the empty magazine dropping
-- to the floor for real (a loose part that tumbles and clatters), a spent casing flying out of a bolt.
-- Three styles:
--   rifle  (M4A1)  roll the gun, thumb the release, strip the mag and let it fall, new mag from the
--                  vest, line up, insert, slap it home, reach over, pull the charging handle, release
--   pistol         mag drops by itself, fresh mag from the belt, insert, slap, rack the slide
--   bolt   (Sniper) bolt up and back (the casing flies), swap the mag, bolt forward and down
-- Call GunAnim.step every frame while a reload is active; it returns the gun's extra motion
-- (handle space) to multiply into the hold.
local Debris = game:GetService("Debris")

local GunAnim = {}

type Rest = { left: CFrame, mag: CFrame, grab: Vector3, bolt: Vector3, charge: Vector3 }
type Active = { start: number, duration: number, style: string, fired: { [number]: boolean }, magGone: boolean }

local rest: { [Tool]: Rest } = setmetatable({}, { __mode = "k" }) :: any
local active: { [Tool]: Active } = setmetatable({}, { __mode = "k" }) :: any

local DEFAULT_GRAB = Vector3.new(-0.02, -0.75, -0.16)
local DEFAULT_BOLT = Vector3.new(-0.24, 0.12, 0.08)

local SOUNDS = {
	release = { "rbxassetid://75426945055473", 0.35, 1.25 },
	magOut = { "rbxassetid://138445767056876", 0.55, 1.0 },
	pouch = { "rbxassetid://9113827004", 0.18, 1.6 },
	magIn = { "rbxassetid://126879077086551", 0.6, 1.0 },
	slap = { "rbxassetid://9117413937", 0.35, 1.9 },
	charge = { "rbxassetid://104732809594116", 0.55, 1.0 },
	slide = { "rbxassetid://140301163976554", 0.55, 1.05 },
	boltBack = { "rbxassetid://93265832279166", 0.6, 1.0 },
	boltFwd = { "rbxassetid://133390161654321", 0.6, 1.0 },
	clatter = { "rbxassetid://9113105142", 0.35, 1.25 },
	casing = { "rbxassetid://9113105344", 0.25, 1.6 },
}

-- Left-hand keys: { t (0..1), where, offset, magState, magRotDeg }
--   where: "rest" | "grab" (MagGrab + offset) | "body" (torso space) | "pt" (handle space point)
--          | "charge" (charging handle + offset) | "bolt" (bolt + offset)
--   magState: "seated" | "hand" (follows the hand) | "hidden"
-- Gun keys: { t, roll (deg, + = rolled right), pitch (deg, + = muzzle up), yaw, dx, dy, dz (studs) }
-- Events: { t, name, arg? }  ("snd" name | "drop" | "casing")
type Style = { hand: { { any } }, gun: { { number } }, events: { { any } } }
local V = Vector3.new

local STYLES: { [string]: Style } = {
	rifle = {
		hand = {
			{ 0.00, "rest", nil, "seated" },
			{ 0.07, "grab", V(0, -0.05, 0.02), "seated" }, -- hand cups the magazine, thumb on the release
			{ 0.13, "grab", V(0, -0.02, 0), "seated" },
			{ 0.20, "grab", V(0.02, -0.75, 0.1), "hand", -10 }, -- stripped out
			{ 0.25, "grab", V(0.25, -1.0, 0.25), "hidden", -40 }, -- flicked away (dropped at 0.24)
			{ 0.36, "body", V(-0.42, -0.62, -0.62), "hidden" }, -- vest pouch
			{ 0.42, "body", V(-0.40, -0.48, -0.66), "hand", 25 }, -- fresh mag out of the pouch
			{ 0.52, "grab", V(-0.05, -0.62, 0.12), "hand", 12 }, -- presented under the well
			{ 0.58, "grab", V(0, -0.32, 0.02), "hand", 4 }, -- lined up
			{ 0.63, "grab", V(0, -0.05, 0), "seated" }, -- in
			{ 0.665, "grab", V(0, -0.22, 0), "seated" }, -- hand drops...
			{ 0.69, "grab", V(0, -0.08, 0), "seated" }, -- ...and slaps it home
			{ 0.76, "charge", V(-0.05, 0.12, -0.05), "seated" }, -- over the top to the charging handle
			{ 0.81, "charge", V(-0.02, 0.06, 0.38), "seated" }, -- pulled back
			{ 0.84, "charge", V(-0.1, 0.16, 0.2), "seated" }, -- let go (it slams forward)
			{ 0.93, "rest", nil, "seated" },
			{ 1.00, "rest", nil, "seated" },
		},
		gun = {
			{ 0.00, 0, 0, 0, 0, 0, 0 },
			{ 0.08, 32, 6, 4, -0.06, 0.1, 0.12 },
			{ 0.20, 38, 10, 6, -0.08, 0.14, 0.12 },
			{ 0.24, 30, 8, 6, -0.08, 0.12, 0.12 },
			{ 0.45, 34, 14, 8, -0.1, 0.16, 0.16 },
			{ 0.63, 30, 16, 6, -0.08, 0.16, 0.14 },
			{ 0.69, 26, 24, 6, -0.08, 0.24, 0.14 }, -- jolt from the slap
			{ 0.73, 24, 12, 4, -0.06, 0.14, 0.12 },
			{ 0.81, -14, 8, -6, 0.02, 0.1, 0.18 }, -- turned left to pull the handle
			{ 0.845, -10, 14, -4, 0.02, 0.14, 0.08 }, -- bolt slams forward: kick
			{ 0.93, -2, 2, 0, 0, 0.02, 0.02 },
			{ 1.00, 0, 0, 0, 0, 0, 0 },
		},
		events = {
			{ 0.12, "snd", "release" },
			{ 0.16, "snd", "magOut" },
			{ 0.24, "drop" },
			{ 0.38, "snd", "pouch" },
			{ 0.61, "snd", "magIn" },
			{ 0.685, "snd", "slap" },
			{ 0.79, "snd", "charge" },
		},
	},
	pistol = {
		hand = {
			{ 0.00, "rest", nil, "seated" },
			{ 0.10, "body", V(-0.25, -0.5, -0.95), "seated" }, -- hand comes off, thumb drops the mag
			{ 0.22, "body", V(-0.48, -0.95, -0.5), "hidden" }, -- belt pouch
			{ 0.32, "body", V(-0.46, -0.82, -0.56), "hand", 20 },
			{ 0.46, "grab", V(-0.03, -0.55, 0.06), "hand", 10 },
			{ 0.53, "grab", V(0, -0.25, 0), "hand", 3 },
			{ 0.58, "grab", V(0, -0.04, 0), "seated" },
			{ 0.62, "grab", V(0, -0.2, 0), "seated" },
			{ 0.65, "grab", V(0, -0.05, 0), "seated" }, -- slap
			{ 0.74, "charge", V(0, 0.1, -0.1), "seated" }, -- over the slide
			{ 0.80, "charge", V(0, 0.08, 0.32), "seated" }, -- racked
			{ 0.83, "charge", V(-0.15, 0.2, 0.4), "seated" }, -- released
			{ 0.94, "rest", nil, "seated" },
			{ 1.00, "rest", nil, "seated" },
		},
		gun = {
			{ 0.00, 0, 0, 0, 0, 0, 0 },
			{ 0.08, 18, 22, 0, -0.04, 0.18, 0.1 }, -- muzzle up, mag well down: let it fall
			{ 0.14, 20, 28, 0, -0.04, 0.2, 0.1 },
			{ 0.40, 24, 12, 6, -0.06, 0.1, 0.12 },
			{ 0.58, 22, 10, 4, -0.06, 0.1, 0.12 },
			{ 0.65, 20, 20, 4, -0.06, 0.2, 0.12 }, -- slap jolt
			{ 0.70, 6, 8, -10, 0, 0.08, 0.1 },
			{ 0.80, 0, 6, -16, 0.04, 0.06, 0.16 },
			{ 0.835, 0, 14, -12, 0.04, 0.1, 0.08 }, -- slide snaps forward
			{ 0.94, 0, 2, 0, 0, 0.02, 0.02 },
			{ 1.00, 0, 0, 0, 0, 0, 0 },
		},
		events = {
			{ 0.08, "snd", "release" },
			{ 0.10, "drop" },
			{ 0.24, "snd", "pouch" },
			{ 0.56, "snd", "magIn" },
			{ 0.645, "snd", "slap" },
			{ 0.77, "snd", "slide" },
		},
	},
	bolt = {
		hand = {
			{ 0.00, "rest", nil, "seated" },
			{ 0.08, "bolt", V(0.05, 0.02, 0), "seated" }, -- reach over to the bolt handle
			{ 0.12, "bolt", V(0.08, 0.16, 0), "seated" }, -- bolt up
			{ 0.18, "bolt", V(0.08, 0.16, 0.42), "seated" }, -- bolt back: the casing flies
			{ 0.26, "grab", V(0, -0.04, 0), "seated" },
			{ 0.32, "grab", V(0.05, -0.7, 0.1), "hand", -12 },
			{ 0.36, "grab", V(0.3, -0.95, 0.25), "hidden", -40 }, -- dropped
			{ 0.46, "body", V(-0.42, -0.62, -0.62), "hidden" },
			{ 0.52, "body", V(-0.40, -0.48, -0.66), "hand", 25 },
			{ 0.62, "grab", V(-0.05, -0.6, 0.12), "hand", 12 },
			{ 0.67, "grab", V(0, -0.3, 0.02), "hand", 4 },
			{ 0.71, "grab", V(0, -0.05, 0), "seated" },
			{ 0.73, "grab", V(0, -0.18, 0), "seated" },
			{ 0.75, "grab", V(0, -0.06, 0), "seated" },
			{ 0.82, "bolt", V(0.08, 0.16, 0.42), "seated" },
			{ 0.87, "bolt", V(0.08, 0.16, 0), "seated" }, -- bolt forward
			{ 0.90, "bolt", V(0.05, 0.02, 0), "seated" }, -- and down
			{ 0.96, "rest", nil, "seated" },
			{ 1.00, "rest", nil, "seated" },
		},
		gun = {
			{ 0.00, 0, 0, 0, 0, 0, 0 },
			{ 0.08, -12, 4, -4, 0.02, 0.06, 0.12 },
			{ 0.18, -16, 6, -4, 0.02, 0.08, 0.14 },
			{ 0.26, 26, 8, 6, -0.06, 0.1, 0.14 },
			{ 0.50, 30, 12, 8, -0.08, 0.14, 0.16 },
			{ 0.71, 28, 14, 6, -0.08, 0.14, 0.14 },
			{ 0.75, 24, 20, 6, -0.08, 0.2, 0.14 },
			{ 0.80, -14, 6, -4, 0.02, 0.08, 0.14 },
			{ 0.90, -10, 10, -2, 0.02, 0.1, 0.08 },
			{ 0.96, -2, 2, 0, 0, 0.02, 0.02 },
			{ 1.00, 0, 0, 0, 0, 0, 0 },
		},
		events = {
			{ 0.11, "snd", "boltBack" },
			{ 0.17, "casing" },
			{ 0.28, "snd", "release" },
			{ 0.30, "snd", "magOut" },
			{ 0.36, "drop" },
			{ 0.48, "snd", "pouch" },
			{ 0.70, "snd", "magIn" },
			{ 0.745, "snd", "slap" },
			{ 0.84, "snd", "boltFwd" },
		},
	},
}

-- first person: the rear of the gun is right under the eye, so the left hand works the bolt release on
-- the side of the receiver instead of the charging handle (the forearm would fill the screen)
do
	local function fpCopy(src: Style, swap: { { any } }, from: number, to: number): Style
		local hand = {}
		for _, k in src.hand do
			if k[1] < from or k[1] > to then
				table.insert(hand, k)
			end
		end
		for _, k in swap do
			table.insert(hand, k)
		end
		table.sort(hand, function(x, y)
			return x[1] < y[1]
		end)
		return { hand = hand, gun = src.gun, events = src.events }
	end
	STYLES.rifle_fp = fpCopy(STYLES.rifle, {
		{ 0.76, "bolt", V(-0.14, 0.02, -0.06), "seated" },
		{ 0.80, "bolt", V(-0.02, 0, 0), "seated" }, -- thumb slams the bolt release
		{ 0.84, "bolt", V(-0.16, -0.05, -0.1), "seated" },
	}, 0.75, 0.85)
	STYLES.pistol_fp = fpCopy(STYLES.pistol, {
		{ 0.74, "bolt", V(-0.12, -0.02, -0.04), "seated" },
		{ 0.79, "bolt", V(-0.02, -0.02, 0), "seated" }, -- slide stop
		{ 0.83, "bolt", V(-0.15, -0.08, -0.08), "seated" },
	}, 0.73, 0.84)
end

local function styleOf(tool: Tool): string
	local s = tool:GetAttribute("ReloadStyle")
	if type(s) == "string" and STYLES[s] then
		return s
	end
	if tool.Name == "Sniper" or tool:GetAttribute("ItemId") == "sniper" then
		return "bolt"
	elseif tool.Name == "Pistol" or tool:GetAttribute("ItemId") == "pistol" then
		return "pistol"
	end
	return "rifle"
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function setMagHidden(mag: BasePart, hidden: boolean)
	local v = hidden and 1 or 0
	mag.LocalTransparencyModifier = v
	for _, d in mag:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = v
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.LocalTransparencyModifier = v
		end
	end
end

local function parts(tool: Tool): (BasePart?, Attachment?, Weld?, BasePart?)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		return nil, nil, nil, nil
	end
	return handle,
		handle:FindFirstChild("LeftHandIK") :: Attachment?,
		handle:FindFirstChild("MagWeld") :: Weld?,
		tool:FindFirstChild("Magazine") :: BasePart?
end

local function restOf(tool: Tool): Rest?
	local r = rest[tool]
	if r then
		return r
	end
	local _, left, magWeld = parts(tool)
	if not left or not magWeld then
		return nil
	end
	local handle = tool:FindFirstChild("Handle")
	local grabAtt = handle and handle:FindFirstChild("MagGrab") :: Attachment?
	local boltAtt = handle and handle:FindFirstChild("BoltRelease") :: Attachment?
	local chargeAtt = handle and handle:FindFirstChild("ChargingHandle") :: Attachment?
	local sight = handle and handle:FindFirstChild("Sight") :: Attachment?
	local rightIK = handle and handle:FindFirstChild("RightHandIK") :: Attachment?
	-- charging handle: at the back of the receiver, on top, just behind the sight (above the grip)
	local charge = if chargeAtt then chargeAtt.Position
		else Vector3.new(0, (if sight then sight.Position.Y - 0.12 else 0.2), (if rightIK then rightIK.Position.Z + 0.08 else 0.25))
	r = {
		left = left.CFrame,
		mag = magWeld.C0,
		grab = grabAtt and grabAtt.Position or DEFAULT_GRAB,
		bolt = boltAtt and boltAtt.Position or DEFAULT_BOLT,
		charge = charge,
	}
	rest[tool] = r
	return r
end

function GunAnim.remember(tool: Tool)
	restOf(tool)
end

local function playSound(at: Instance, name: string)
	local s = SOUNDS[name]
	if not s then
		return
	end
	local snd = Instance.new("Sound")
	snd.SoundId = s[1] :: string
	snd.Volume = s[2] :: number
	snd.PlaybackSpeed = (s[3] :: number) * (0.96 + math.random() * 0.08)
	snd.RollOffMaxDistance = 70
	snd.RollOffMinDistance = 4
	snd.Parent = at
	snd:Play()
	Debris:AddItem(snd, 3)
end

function GunAnim.startReload(tool: Tool, duration: number, firstPerson: boolean?)
	if restOf(tool) then
		local slow = tool:GetAttribute("TestAnimSlow") -- scripted playtests: slow motion to film it
		if type(slow) == "number" then
			duration *= slow
		end
		local style = styleOf(tool)
		if firstPerson and STYLES[style .. "_fp"] then
			style ..= "_fp"
		end
		active[tool] = { start = os.clock(), duration = duration, style = style, fired = {}, magGone = false }
	end
end

function GunAnim.isReloading(tool: Tool): boolean
	return active[tool] ~= nil
end

function GunAnim.stop(tool: Tool)
	active[tool] = nil
	local r = rest[tool]
	local _, left, magWeld, mag = parts(tool)
	if r and left and magWeld then
		left.CFrame = r.left
		magWeld.C0 = r.mag
	end
	if mag then
		setMagHidden(mag, false)
	end
end

local fxFolder: Folder? = nil
local function looseFolder(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "LooseGunParts"
		f.Parent = workspace
		fxFolder = f
	end
	return fxFolder :: Folder
end

-- the empty magazine leaves the gun for real: a loose copy tumbles to the floor and clatters
local function dropMag(mag: BasePart, handle: BasePart)
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - mag.Position).Magnitude > 140 then
		return
	end
	local m = mag:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	m.LocalTransparencyModifier = 0
	m.Anchored = false
	m.CanCollide = true
	m.CanQuery = false
	m.CanTouch = true
	m.Massless = false
	m.CFrame = mag.CFrame
	m.Parent = looseFolder()
	m.AssemblyLinearVelocity = handle.AssemblyLinearVelocity * 0.5 + handle.CFrame.RightVector * 2 + Vector3.new(0, -4, 0)
	m.AssemblyAngularVelocity = Vector3.new(math.random() * 8 - 4, math.random() * 6 - 3, math.random() * 8 - 4)
	local hits = 0
	m.Touched:Connect(function(other)
		if hits < 2 and other.CanCollide and not other:IsDescendantOf(handle.Parent :: Instance) then
			hits += 1
			playSound(m, "clatter")
		end
	end)
	Debris:AddItem(m, 15)
end

-- a spent brass casing pops out of the bolt
local function ejectCasing(handle: BasePart, at: Vector3)
	local c = Instance.new("Part")
	c.Name = "Casing"
	c.Size = Vector3.new(0.08, 0.08, 0.28)
	c.Color = Color3.fromRGB(214, 172, 70)
	c.Material = Enum.Material.Metal
	c.CanCollide = true
	c.CanQuery = false
	c.CFrame = handle.CFrame * CFrame.new(at)
	c.Parent = looseFolder()
	c.AssemblyLinearVelocity = handle.CFrame.RightVector * 9 + Vector3.new(0, 8, 0) + handle.CFrame.LookVector * -2
	c.AssemblyAngularVelocity = Vector3.new(20, 8, 14)
	local hit = false
	c.Touched:Connect(function(other)
		if not hit and other.CanCollide and not other:IsDescendantOf(handle.Parent :: Instance) then
			hit = true
			playSound(c, "casing")
		end
	end)
	Debris:AddItem(c, 10)
end

local function sampleGun(keys: { { number } }, t: number): CFrame
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t >= a[1] and t <= b[1] then
			local f = smooth((t - a[1]) / math.max(b[1] - a[1], 1e-3))
			local function L(k: number): number
				return a[k] + (b[k] - a[k]) * f
			end
			return CFrame.new(L(5), L(6), L(7)) * CFrame.Angles(math.rad(L(3)), math.rad(L(4)), math.rad(-L(2)))
		end
	end
	return CFrame.identity
end

-- Advance the animation; returns the gun's extra motion (handle space) for this frame.
function GunAnim.step(tool: Tool, torso: BasePart?): CFrame
	local a = active[tool]
	if not a then
		return CFrame.identity
	end
	local t = (os.clock() - a.start) / a.duration
	if t >= 1 then
		GunAnim.stop(tool)
		return CFrame.identity
	end
	local r = rest[tool]
	local handle, left, magWeld, mag = parts(tool)
	if not r or not handle or not left or not magWeld then
		return CFrame.identity
	end
	local style = STYLES[a.style]

	local function keyPos(k: { any }): Vector3
		local w = k[2]
		local off = (k[3] :: Vector3?) or Vector3.zero
		if w == "rest" then
			return r.left.Position
		elseif w == "grab" then
			return r.grab + off
		elseif w == "charge" then
			return r.charge + off
		elseif w == "bolt" then
			return r.bolt + off
		elseif w == "pt" then
			return off
		elseif w == "body" and torso then
			return handle.CFrame:PointToObjectSpace(torso.CFrame:PointToWorldSpace(off))
		end
		return r.left.Position
	end

	-- left hand + magazine
	local keys = style.hand
	local pos = r.left.Position
	local magState, magRot = "seated", 0
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if t >= k0[1] and t <= k1[1] then
			local f = smooth((t - k0[1]) / math.max(k1[1] - k0[1], 1e-3))
			pos = keyPos(k0):Lerp(keyPos(k1), f)
			-- the magazine state belongs to the segment's start; "hand" segments ending seated stay in hand
			magState = k0[4] :: string
			if magState == "hand" and k1[4] == "seated" and f > 0.98 then
				magState = "seated"
			end
			local r0 = (k0[5] :: number?) or 0
			local r1 = (k1[5] :: number?) or 0
			magRot = r0 + (r1 - r0) * f
			break
		end
	end
	left.CFrame = CFrame.new(pos) * r.left.Rotation

	if magState == "hand" then
		magWeld.C0 = CFrame.new(pos + (r.mag.Position - r.grab)) * r.mag.Rotation * CFrame.Angles(math.rad(magRot), 0, 0)
	else
		magWeld.C0 = r.mag
	end
	if mag then
		setMagHidden(mag, magState == "hidden" or (a.magGone and magState == "seated" and t < 0.5))
	end

	-- timed events
	for i, ev in style.events do
		if not a.fired[i] and t >= ev[1] then
			a.fired[i] = true
			if ev[2] == "snd" then
				playSound(handle, ev[3] :: string)
			elseif ev[2] == "drop" and mag then
				dropMag(mag, handle)
				a.magGone = true
			elseif ev[2] == "casing" then
				ejectCasing(handle, r.bolt + Vector3.new(0.1, 0.1, 0.1))
			end
		end
	end
	-- pistol: the magazine falls by itself; hide it from the drop until the fresh one comes out
	if (a.style == "pistol" or a.style == "pistol_fp") and mag and a.magGone and t < 0.32 then
		setMagHidden(mag, true)
	end

	return sampleGun(style.gun, t)
end

return GunAnim
