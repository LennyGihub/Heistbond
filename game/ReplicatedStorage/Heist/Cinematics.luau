--!strict
-- The vault-entry cinematics (client). Each one is started by the server ("Cine" event) and timed
-- against CineMeta: the real effect (the charge appearing on the wall, the drill rig starting, the
-- reader or the keypad unlocking the door) happens on the server at Meta[kind].effectAt, while the
-- camera follows the character doing it: walking up, the hands at work (ActionAnim), the result.
-- Every camera goes through Cine.safe, so a wall or the vault door's wheel never blocks the view.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local Cine = require(Heist:WaitForChild("Cine"))
local AA = require(Heist:WaitForChild("ActionAnim"))
local Meta = require(Heist:WaitForChild("CineMeta"))
local Sfx = require(Heist:WaitForChild("Sfx"))
local Noobla = require(Heist:WaitForChild("Noobla"))

local C = {}
local player = Players.LocalPlayer
local V3 = Vector3.new

local function charParts(): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	return char, char and char:FindFirstChild("HumanoidRootPart") :: BasePart?, char and char:FindFirstChildOfClass("Humanoid")
end

-- the spot's frame: n = out of the surface toward the crew, up, right (the viewer's right facing it)
local function frame(spot: BasePart, from: Vector3): (Vector3, Vector3, Vector3, boolean)
	local lv = spot.CFrame.LookVector
	if math.abs(lv.Y) > 0.7 then
		-- a roof spot: n points up (the crew stands on the roof); "up" for the cameras is the horizontal
		-- direction from the spot toward where the character came from
		local flat = Vector3.new(from.X - spot.Position.X, 0, from.Z - spot.Position.Z)
		local toward = if flat.Magnitude > 0.5 then flat.Unit else Vector3.zAxis
		return Vector3.yAxis, toward, Vector3.yAxis:Cross(toward), true
	end
	local n = Vector3.new(lv.X, 0, lv.Z).Unit
	return n, Vector3.yAxis, Vector3.yAxis:Cross(n), false
end

local function dust(at: Vector3, big: boolean)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/smoke_main.dds"
	p.Color = ColorSequence.new(Color3.fromRGB(200, 195, 185))
	p.Size = NumberSequence.new(if big then 6 else 2, if big then 14 else 5)
	p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	p.Lifetime = NumberRange.new(1.2, 2.4)
	p.Speed = NumberRange.new(4, if big then 16 else 8)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rate = 0
	p.Parent = a
	p:Emit(if big then 40 else 14)
	Debris:AddItem(a, 4)
end

local function sparks(at: Vector3, n: number)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	p.LightEmission = 1
	p.Size = NumberSequence.new(0.35, 0)
	p.Lifetime = NumberRange.new(0.25, 0.6)
	p.Speed = NumberRange.new(8, 18)
	p.SpreadAngle = Vector2.new(60, 60)
	p.Acceleration = Vector3.new(0, -40, 0)
	p.Rate = 0
	p.Parent = a
	p:Emit(n)
	Debris:AddItem(a, 2)
end

-- the character walks to `pos` and turns to face `look`; yields
local function approach(pos: Vector3, look: Vector3, speed: number, timeout: number?)
	local char, root = charParts()
	if not char or not root then
		return
	end
	Cine.walk(char, Vector3.new(pos.X, root.Position.Y, pos.Z), speed, timeout or 2.2)
	Cine.face(char, look, 0.25)
end

local function timer(): () -> number
	local t0 = os.clock()
	return function()
		return os.clock() - t0
	end
end

local function waitUntil(T: () -> number, at: number)
	local d = at - T()
	if d > 0 then
		task.wait(d)
	end
end

------------------------------------------------------------------ C4 (door, the three walls, the roof)

function C.c4(spot: BasePart)
	local char, root = charParts()
	if not char or not root then
		return
	end
	local M = Meta.c4
	Cine.begin()
	local T = timer()
	local n, up, right, roof = frame(spot, root.Position)
	local P = spot.Position
	-- standing spot: in front of the wall (or on the roof, beside the charge's spot)
	local stand = if roof then P + up * 2.3 else P + n * 2.0
	local eye = if roof then P + V3(0, 1.0, 0) else P + n * 0.2
	-- A: a three-quarter tracking shot over the shoulder while walking up
	Cine.shot(2.2, function(u)
		local r = root.Position
		local back = Vector3.new(r.X - P.X, 0, r.Z - P.Z)
		back = if back.Magnitude > 0.2 then back.Unit else (if roof then up else n)
		local side = Vector3.yAxis:Cross(back)
		return Cine.safe(r + back * 7 + side * 3 + V3(0, 2.6, 0), r:Lerp(eye, 0.5) + V3(0, 0.8, 0)), 60 - 6 * u
	end)
	approach(stand, P, 12, 2.0)
	waitUntil(T, 2.2)
	-- the hands: charge out of the vest, carried to the wall, pressed on, armed
	AA.play(char, "c4Place", { target = spot.CFrame })
	-- B: from the side, the vest and the charge coming out
	Cine.shot(1.25, function(u)
		local r = root.Position
		local side = if roof then right else right
		return Cine.safe(r - side * (3.6 - 0.4 * u) + (if roof then up * 1.2 else n * 1.2) + V3(0, 1.2, 0), r + V3(0, 0.7, 0) + (if roof then -up else -n) * 0.6), 46
	end, 0.35)
	waitUntil(T, 3.45)
	-- C: close at the wall: the charge is pressed on (it stays there: the server's brick appears)
	Cine.shot(1.45, function(u)
		local pos = if roof then P + V3(0, 2.0 - 0.3 * u, 0) - right * 3.0 + up * 0.6 else P + n * (1.5 - 0.2 * u) - right * (3.0 - 0.3 * u) + up * 0.3
		return Cine.safe(pos, P + (if roof then V3(0, 0.3, 0) else n * 0.25)), 42
	end, 0.25)
	waitUntil(T, M.effectAt + 0.1)
	-- D: macro on the blinking light, the first beeps
	Cine.shot(0.8, function(u)
		local pos = if roof then P + V3(0, 1.1, 0) + right * 1.5 + up * 0.5 else P + n * 1.1 + right * 1.5 + up * 0.35
		return Cine.safe(pos, P + (if roof then V3(0, 0.2, 0) else n * 0.15)), 30 - 4 * u
	end)
	waitUntil(T, M.effectAt + 0.9)
	-- E: run! The camera pulls back wide while the crew gets clear
	-- run off to the left, as far as the room allows; the camera pulls back to the right
	-- (the most open of a few directions, stopping well short of walls so the game camera has room
	-- behind the character when it turns to watch the blast)
	local away = if roof then up else n
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local best, bestLen = (away * 10 - right * 6).Unit, -1
	for i, d in { away * 10 - right * 6, away * 12, away * 10 + right * 6, -right * 10 + away * 3, right * 10 + away * 3 } do
		local dir = d.Unit
		local hit = workspace:Raycast(root.Position, dir * 24, params)
		local free = if hit then (hit.Position - root.Position).Magnitude else 24
		if free > bestLen + (if i == 1 then 0 else 2) then
			best, bestLen = dir, free
		end
	end
	local fleeLen = math.clamp(bestLen - 7, 2, 11)
	local flee = root.Position + best * fleeLen
	local camSide = if best:Dot(right) > 0.2 then -right else right -- the camera on the other side
	task.spawn(function()
		Cine.walk(char, Vector3.new(flee.X, root.Position.Y, flee.Z), 18, 2.2)
		Cine.face(char, P, 0.3)
	end)
	local blastAt = M.effectAt + Noobla.c4Fuse
	Cine.shot(1.9, function(u)
		local k = Cine.smooth(u)
		local pos = if roof then P + V3(0, 2 + 6 * k, 0) + up * (3 + 10 * k) + camSide * (3 + 8 * k) else P + n * (3 + 9 * k) + camSide * (3 + 8 * k) + up * (0.4 + 3 * k)
		return Cine.safe(pos, P + (if roof then V3(0, 0.5, 0) else n * 0.3)), 46 + 16 * k
	end)
	-- the beeps speed up toward the blast
	task.spawn(function()
		local gap = 0.6
		while T() < blastAt - 0.15 do
			Sfx.play("beep", P, 0.25, 1.6, 80)
			task.wait(gap)
			gap = math.max(0.12, gap * 0.82)
		end
	end)
	waitUntil(T, M.effectAt + 2.8)
	-- F: wide, tension, the crew in cover in the foreground
	local hold = blastAt - T() - 0.05
	if hold > 0 then
		local wide = if roof then P + V3(0, 9, 0) + up * 14 + camSide * 12 else P + n * 13 + camSide * 12 + up * 3.4
		Cine.shot(hold, function(u)
			return Cine.safe(wide + (if roof then up else n) * (u * 1.5), P + (if roof then V3(0, 0.5, 0) else n * 0.3)), 62 - 6 * u
		end)
	end
	waitUntil(T, blastAt)
	Cine.shake(1.3, 2.6)
	Cine.fade(Color3.new(1, 1, 1), 0.15, 0.05)
	task.delay(0.12, function()
		Cine.fade(Color3.new(1, 1, 1), 1, 0.7)
	end)
	dust(P + (if roof then V3(0, 3, 0) else n * 4), true)
	local pull = if roof then P + V3(0, 10, 0) + up * 20 + camSide * 6 else P + n * 20 + camSide * 6 + up * 3
	Cine.shot(math.max(0.6, M.len - T() - 0.2), function(u)
		return Cine.safe(pull + (if roof then up else n) * (u * 3), P), 70 - 8 * u
	end)
	waitUntil(T, M.len - 0.2)
	Cine.finish(0.9)
end

------------------------------------------------------------------ the heavy drill on the vault door

function C.drill(spot: BasePart)
	local char, root = charParts()
	if not char or not root then
		return
	end
	local M = Meta.drill
	Cine.begin()
	local T = timer()
	local n, up, right = frame(spot, root.Position)
	local P = spot.Position
	local stand = P + n * 2.6 - up * (P.Y - root.Position.Y)
	-- carried in both arms from the first frame; set down, clamped, trigger pulled at ~3.35 s
	task.delay(0.15, function()
		AA.play(char, "drillMount", { target = spot.CFrame })
	end)
	-- A: side tracking: the crew lugging the heavy drill up to the door
	Cine.shot(1.7, function(u)
		local r = root.Position
		return Cine.safe(r + right * 6 + n * 2.5 + V3(0, 1.2, 0), r + V3(0, 0.6, 0)), 58
	end)
	approach(stand, P, 8, 1.6)
	waitUntil(T, 1.75)
	-- B: three-quarter wide: set against the door
	Cine.shot(1.3, function(u)
		return Cine.safe(P + n * (7.5 - u) + right * 5.5 + up * 0.4, P + n * 1.2 - up * 1.0), 54 - 4 * u
	end, 0.3)
	waitUntil(T, 3.0)
	-- C: low and close from the other side: the clamps, the trigger
	Cine.shot(0.9, function(u)
		return Cine.safe(P + n * 2.8 - right * (3.4 - 0.4 * u) - up * 1.6, P + n * 0.9 - up * 0.6), 44
	end)
	waitUntil(T, M.effectAt)
	-- D: the bit bites: macro at the bit, sparks, shaking
	task.spawn(function()
		while T() < M.effectAt + 1.6 do
			sparks(P + n * 0.5, 6)
			task.wait(0.12)
		end
	end)
	Cine.shot(1.6, function(u)
		Cine.shake(0.08, 0.2)
		return Cine.safe(P + n * 4.6 + right * (3.6 - 0.6 * u) + up * 1.4, P + n * 0.9), 44 - 6 * u
	end)
	waitUntil(T, M.effectAt + 1.6)
	-- E: wide: the crew steps back, the drill screaming on the door
	task.spawn(function()
		Cine.walk(char, Vector3.new(P.X + n.X * 8 + right.X * 3, root.Position.Y, P.Z + n.Z * 8 + right.Z * 3), 8, 2)
		Cine.face(char, P, 0.3)
	end)
	Cine.shot(math.max(0.5, M.len - T() - 0.2), function(u)
		Cine.shake(0.025, 1)
		return Cine.safe(P + n * (11 + 2 * u) + right * 4 + up * 1.2, P - up * 0.5), 58
	end, 0.35)
	waitUntil(T, M.len - 0.2)
	Cine.finish(0.9)
end

------------------------------------------------------------------ the level 5 card

function C.card(spot: BasePart)
	local char, root = charParts()
	if not char or not root then
		return
	end
	local M = Meta.card
	Cine.begin()
	local T = timer()
	local n, up, right = frame(spot, root.Position)
	local P = spot.Position
	local stand = P + n * 2.0 + right * 0.6
	-- A: tracking the walk to the reader
	Cine.shot(1.5, function(u)
		local r = root.Position
		local back = Vector3.new(r.X - P.X, 0, r.Z - P.Z)
		back = if back.Magnitude > 0.2 then back.Unit else n
		return Cine.safe(r + back * 6 - right * 2.5 + V3(0, 2.2, 0), P), 56 - 4 * u
	end)
	approach(stand, P, 9, 1.4)
	waitUntil(T, 1.5)
	AA.play(char, "cardSwipe", { target = spot.CFrame })
	-- B: side, chest height: the card comes out of the pocket, catches the light, a little twirl
	Cine.shot(1.5, function(u)
		local r = root.Position
		return Cine.safe(r - right * (4.4 - 0.4 * u) + n * 2.2 + V3(0, 1.3, 0), r + V3(0, 0.9, 0) - n * 0.5), 46
	end, 0.3)
	waitUntil(T, 3.0)
	-- C: close on the reader: the swipe, the beep, the light turns green (server, effectAt)
	Cine.shot(1.2, function(u)
		return Cine.safe(P + n * (2.0 - 0.3 * u) - right * 1.6 + up * 0.35, P), 38 - 4 * u
	end)
	waitUntil(T, M.effectAt + 0.15)
	Cine.shake(0.05, 3)
	-- D: the vault door: bolts back, the heavy door swings
	local door = spot.Parent and spot.Parent:FindFirstChild("VaultDoor")
	local dp = if door and door:IsA("Model") then door:GetPivot().Position else P + right * 10
	Cine.shot(2.0, function(u)
		return Cine.safe(dp + n * (12 - 3 * u) + right * (4 - 2 * u) + up * 0.6, dp + up * 0.2), 56 - 6 * u
	end, 0.4)
	waitUntil(T, M.effectAt + 2.15)
	-- E: back on the crew, turning to the open vault
	Cine.face(char, dp, 0.4)
	Cine.shot(math.max(0.5, M.len - T() - 0.2), function(u)
		local r = root.Position
		return Cine.safe(r + n * 5 + right * 3 + V3(0, 2.0, 0), r:Lerp(dp, 0.6) + V3(0, 1.4, 0)), 52
	end, 0.35)
	waitUntil(T, M.len - 0.2)
	Cine.finish(0.9)
end

------------------------------------------------------------------ hacking the keypad

function C.hack(spot: BasePart)
	local char, root = charParts()
	if not char or not root then
		return
	end
	local M = Meta.hack
	Cine.begin()
	local T = timer()
	local n, up, right = frame(spot, root.Position)
	local P = spot.Position
	local anim = AA.play(char, "hackType")
	-- a readout of scrolling code over the keypad
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 80)
	gui.StudsOffsetWorldSpace = n * 0.6 + up * 1.6
	gui.AlwaysOnTop = true
	gui.Adornee = spot
	gui.Parent = spot
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 20, 12)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(60, 255, 120)
	st.Thickness = 2
	st.Parent = bg
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.fromScale(1, 1)
	txt.TextColor3 = Color3.fromRGB(60, 255, 120)
	txt.FontFace = Font.fromEnum(Enum.Font.Code)
	txt.TextScaled = true
	txt.Text = ""
	txt.Parent = bg
	task.spawn(function()
		local rng = Random.new()
		while gui.Parent and T() < M.effectAt do
			local s = ""
			for _ = 1, 6 do
				s ..= string.format("%02X ", rng:NextInteger(0, 255))
			end
			txt.Text = s .. "\n" .. string.rep("#", math.clamp(math.floor(T() / M.effectAt * 20), 0, 20))
			task.wait(0.06)
		end
		txt.Text = "ACCES OK"
		txt.TextColor3 = Color3.fromRGB(120, 255, 160)
		task.wait(1.2)
		gui:Destroy()
	end)
	-- A: from the side: the device in the left hand, the right hand typing fast
	Cine.shot(1.5, function(u)
		local r = root.Position
		return Cine.safe(r - right * (3.0 - 0.3 * u) + n * 1.4 + V3(0, 1.4, 0), r + V3(0, 0.9, 0) - n * 0.6), 46
	end)
	waitUntil(T, 1.5)
	-- B: macro on the keypad and the readout filling up
	Cine.shot(1.5, function(u)
		return Cine.safe(P + n * (2.0 - 0.4 * u) + right * 0.9 + up * 0.6, P + up * 0.4 + n * 0.3), 40 - 6 * u
	end, 0.3)
	waitUntil(T, M.effectAt + 0.05)
	Cine.shake(0.05, 3)
	if anim then
		anim.stop()
	end
	-- C: the door unlocks and swings open
	local door = spot.Parent and spot.Parent:FindFirstChild("VaultDoor")
	local dp = if door and door:IsA("Model") then door:GetPivot().Position else P - right * 10
	Cine.shot(math.max(0.5, M.len - T() - 0.2), function(u)
		return Cine.safe(dp + n * (12 - 3 * u) - right * (4 - 2 * u) + up * 0.6, dp + up * 0.2), 58 - 6 * u
	end, 0.4)
	waitUntil(T, M.len - 0.2)
	Cine.finish(0.9)
end

C.META = Meta

return C
