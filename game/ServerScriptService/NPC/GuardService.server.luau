--!strict
-- Armed security guards that shoot back.
--  * they stay inside fenced zones far away, on the other side of the player's covers (ZONES): the
--    fences are invisible walls that only block guards (collision groups), so players, civilians and
--    bullets pass through, and the guards can never come close
--  * navy uniform with "SECURITY" on the back and a badge on the chest; an M4A1 (a copy of the
--    StarterPack one without its scripts) held with the players' torso weld + arm IK (GunPose)
--  * with nobody in sight they stroll around their zone, rifle low. When a player's head or torso is
--    in sight (line of sight from the guard's eyes) they stop, turn, raise the rifle and, after a short
--    reaction time, fire short inaccurate bursts at what they can see. Behind cover you are safe.
--  * shots: raycast from the muzzle, DAMAGE per hit to players only (no friendly fire on NPCs), effects
--    for everyone through the weapons' Shot remote (muzzle flash, sound, tracer, impact)
--  * killed like any NPC (tag "NPC": aim assist, kill flash); a new guard comes back after a while
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local NPCCommon = require(script.Parent:WaitForChild("NPCCommon"))
local GunPose = require(ReplicatedStorage:WaitForChild("Weapons"):WaitForChild("GunPose"))
local Shot = ReplicatedStorage:WaitForChild("WeaponRemotes"):WaitForChild("Shot") :: RemoteEvent

-- where guards live: rectangles (centre on the ground, size X/Z), far beyond the line of test covers
-- (the long wall and the two low covers along z = -16..-19), so every cover faces them
local ZONES = {
	{ center = Vector3.new(0, 0, -70), size = Vector2.new(72, 16) },
}
local PER_ZONE = 4
local FENCE_HEIGHT = 14

local SIGHT_RANGE = 260 -- studs
local REACTION = NumberRange.new(0.8, 1.3) -- seconds from seeing you to the first shot
local BURST = NumberRange.new(2, 4) -- shots per burst
local SHOT_GAP = 0.13 -- seconds between shots in a burst
local BURST_PAUSE = NumberRange.new(1.4, 2.6) -- seconds between bursts
local SPREAD = 4.5 -- degrees: they miss a lot at range
local DAMAGE = 4 -- per hit (players have 100 health): about 10 s to drop you in the open
local RANGE = 500
local THINK = 0.15 -- seconds between looks around
local STROLL_PAUSE = NumberRange.new(2, 5)
local REMOVE_AFTER = 5
local RESPAWN_AFTER = 8

local UNIFORM = Color3.fromRGB(28, 38, 66) -- navy shirt and sleeves
local TROUSERS = Color3.fromRGB(22, 22, 26)
local SKINS = {
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 105, 75),
	Color3.fromRGB(110, 72, 50),
}
local HAIR = { 7193401217, 9243992729, 9244010432 } -- short black / brown cuts (free, Roblox-made)

local rng = Random.new()

-- collision groups: the fences only stop guards
local function setupGroups()
	for _, g in { "Guards", "GuardFence" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(g)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("GuardFence", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("GuardFence", "Guards", true)
end
setupGroups()

local fenceFolder = workspace:FindFirstChild("GuardZones") or Instance.new("Folder")
fenceFolder.Name = "GuardZones"
fenceFolder.Parent = workspace
fenceFolder:ClearAllChildren()
for i, z in ZONES do
	local c, s = z.center, z.size
	local h = FENCE_HEIGHT
	local walls = {
		{ Vector3.new(s.X + 2, h, 1), Vector3.new(0, h / 2, -s.Y / 2 - 0.5) },
		{ Vector3.new(s.X + 2, h, 1), Vector3.new(0, h / 2, s.Y / 2 + 0.5) },
		{ Vector3.new(1, h, s.Y), Vector3.new(-s.X / 2 - 0.5, h / 2, 0) },
		{ Vector3.new(1, h, s.Y), Vector3.new(s.X / 2 + 0.5, h / 2, 0) },
	}
	for j, w in walls do
		local p = Instance.new("Part")
		p.Name = string.format("Fence%d_%d", i, j)
		p.Anchored = true
		p.Transparency = 1
		p.CanQuery = false -- bullets and cover rays ignore it
		p.CanTouch = false
		p.Size = w[1]
		p.CFrame = CFrame.new(c + w[2])
		p.CollisionGroup = "GuardFence"
		p.Parent = fenceFolder
	end
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function describe(): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.HairAccessory = tostring(pick(HAIR))
	local skin = pick(SKINS)
	d.HeadColor = skin
	d.TorsoColor, d.LeftArmColor, d.RightArmColor = UNIFORM, UNIFORM, UNIFORM
	d.LeftLegColor, d.RightLegColor = TROUSERS, TROUSERS
	return d
end

local function label(part: BasePart, face: Enum.NormalId, text: string, textSize: number, size: UDim2, pos: UDim2)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(200, 160)
	gui.LightInfluence = 1
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextSize = textSize
	t.Font = Enum.Font.GothamBlack
	t.Parent = gui
end

local function randomInZone(z: { center: Vector3, size: Vector2 }): Vector3
	local p = z.center + Vector3.new((rng:NextNumber() - 0.5) * (z.size.X - 3), 0, (rng:NextNumber() - 0.5) * (z.size.Y - 3))
	return NPCCommon.groundAt(p) or p
end

-- give the guard a rifle held like the players hold theirs (torso weld + both hands by IK)
local function arm(model: Model, hum: Humanoid): (Tool?, Weld?, BasePart?)
	local src = StarterPack:FindFirstChild("M4A1")
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	if not src or not torso then
		return nil, nil, nil
	end
	local tool = src:Clone() :: Tool
	for _, d in tool:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	tool.CanBeDropped = false
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		return nil, nil, nil
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
		end
	end
	tool.Parent = model
	-- the tool system welds it into the right hand: replace that with the torso hold
	local hand = model:FindFirstChild("RightHand")
	local function dropGrip()
		local g = hand and hand:FindFirstChild("RightGrip")
		if g then
			g:Destroy()
		end
	end
	dropGrip()
	if hand then
		hand.ChildAdded:Connect(function(c)
			if c.Name == "RightGrip" then
				task.defer(c.Destroy, c)
			end
		end)
	end
	local weld = Instance.new("Weld")
	weld.Name = "GunHold"
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = GunPose.cframe(torso.Size, 0, 0, 0)
	weld.Parent = handle
	for _, side in { "Right", "Left" } do
		local upper = model:FindFirstChild(side .. "UpperArm")
		local h = model:FindFirstChild(side .. "Hand")
		local grip = h and h:FindFirstChild(side .. "GripAttachment")
		local target = handle:FindFirstChild(side .. "HandIK")
		if upper and grip and target then
			local ik = Instance.new("IKControl")
			ik.Name = "Gun" .. side .. "ArmIK"
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upper
			ik.EndEffector = grip
			ik.Target = target
			ik.SmoothTime = 0.04
			ik.Parent = hum
		end
	end
	return tool, weld, torso
end

local function eyeParams(model: Model): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { NPCCommon.folder }
	local fx = workspace:FindFirstChild("WeaponFx")
	if fx then
		table.insert(ignore, fx)
	end
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = false
	return p
end

-- where a player's body really is, as points to look/shoot at (torso first, then head). Crouching
-- behind a low wall is a pose drawn on each player's screen (CoverPose) that the server never sees, so
-- for a player in low cover (character attribute CoverSide = +-2) use where the crouched body is.
local function targetPoints(char: Model): { Vector3 }
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cover = char:GetAttribute("CoverSide")
	if root and typeof(cover) == "number" and math.abs(cover) > 1.5 then
		return { root.Position + Vector3.new(0, -0.6, 0), root.Position + Vector3.new(0, 0.3, 0) }
	end
	local out = {}
	for _, name in { "UpperTorso", "Head" } do
		local part = char:FindFirstChild(name) :: BasePart?
		if part then
			table.insert(out, part.Position)
		end
	end
	return out
end

-- the first visible point of the nearest visible player, or nil
local function spot(from: Vector3, model: Model): Vector3?
	local params = eyeParams(model)
	local best: Vector3? = nil
	local bestDist = SIGHT_RANGE
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and hum and hum.Health > 0 then
			for _, point in targetPoints(char) do
				local d = (point - from).Magnitude
				if d < bestDist then
					local hit = workspace:Raycast(from, (point - from) * 1.02, params)
					if hit and hit.Instance:IsDescendantOf(char) then
						best, bestDist = point, d
						break
					end
				end
			end
		end
	end
	return best
end

local function fire(model: Model, tool: Tool, aimAt: Vector3)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	local muzzle = handle and handle:FindFirstChild("Muzzle") :: Attachment?
	if not muzzle then
		return
	end
	local origin = muzzle.WorldPosition
	local dir = (aimAt - origin).Unit
	local spread = math.rad(SPREAD) * math.sqrt(rng:NextNumber())
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, rng:NextNumber() * math.pi * 2) * CFrame.Angles(spread, 0, 0)).LookVector
	local hit = workspace:Raycast(origin, dir * RANGE, eyeParams(model))
	local hitPos = if hit then hit.Position else origin + dir * RANGE
	local normal = if hit then hit.Normal else -dir
	local hitChar = false
	if hit then
		local char = hit.Instance:FindFirstAncestorOfClass("Model")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and Players:GetPlayerFromCharacter(char) then
			hitChar = true
			hum:TakeDamage(DAMAGE)
		end
	end
	Shot:FireAllClients(tool, "Fire", hitPos, normal, hitChar)
end

local spawnGuard: (zoneIndex: number) -> ()

local function brain(zoneIndex: number, model: Model, hum: Humanoid, root: BasePart, tool: Tool, weld: Weld, torso: BasePart)
	local zone = ZONES[zoneIndex]
	local head = model:FindFirstChild("Head") :: BasePart
	local aim, pitch, yaw = 0, 0, 0 -- current gun pose
	local aimAt: Vector3? = nil -- what he is aiming at (nil = nobody)
	local seenAt = 0
	local nextShot = 0
	local leftInBurst = 0
	local nextStroll = os.clock() + rng:NextNumber(STROLL_PAUSE.Min, STROLL_PAUSE.Max)

	-- smooth pose: face the target and point the rifle at it, or carry it low
	local poseConn = RunService.Heartbeat:Connect(function(dt)
		if hum.Health <= 0 then
			return
		end
		aim += ((aimAt and 1 or 0) - aim) * math.min(1, dt * 8)
		local target = aimAt
		if target then
			local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
			if flat.Magnitude > 0.1 then
				local want = math.atan2(-flat.X, -flat.Z)
				local _, cur, _ = root.CFrame:ToOrientation()
				local d = (want - cur + math.pi) % (2 * math.pi) - math.pi
				root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, cur + math.clamp(d, -dt * 6, dt * 6), 0)
			end
			local y, p = GunPose.anglesTo(torso, 1, target)
			yaw += (y - yaw) * math.min(1, dt * 12)
			pitch += (p - pitch) * math.min(1, dt * 12)
		else
			yaw += (0 - yaw) * math.min(1, dt * 6)
			pitch += (0 - pitch) * math.min(1, dt * 6)
		end
		weld.C0 = GunPose.cframe(torso.Size, aim, pitch, yaw)
		local left = (tool:FindFirstChild("Handle") :: BasePart):FindFirstChild("LeftHandIK") :: Attachment?
		if left then
			left.Position = GunPose.LEFT_READY:Lerp(GunPose.LEFT_AIM, aim)
		end
	end)
	hum.Died:Connect(function()
		poseConn:Disconnect()
	end)

	while hum.Health > 0 and model.Parent do
		local now = os.clock()
		local point = spot(head.Position, model)
		if point then
			if not aimAt then
				seenAt = now + rng:NextNumber(REACTION.Min, REACTION.Max) -- reaction time
				nextShot = seenAt
				leftInBurst = rng:NextInteger(BURST.Min, BURST.Max)
			end
			aimAt = point
			hum.AutoRotate = false
			hum:Move(Vector3.zero) -- stand still to shoot
			hum:MoveTo(root.Position)
			-- shoot in bursts once the rifle is up
			while now >= nextShot and aim > 0.8 and hum.Health > 0 do
				fire(model, tool, point :: Vector3)
				leftInBurst -= 1
				if leftInBurst <= 0 then
					leftInBurst = rng:NextInteger(BURST.Min, BURST.Max)
					nextShot = now + rng:NextNumber(BURST_PAUSE.Min, BURST_PAUSE.Max)
				else
					nextShot = now + SHOT_GAP
				end
				if nextShot > now then
					break
				end
			end
		else
			aimAt = nil
			hum.AutoRotate = true
			if now >= nextStroll then
				nextStroll = now + rng:NextNumber(STROLL_PAUSE.Min, STROLL_PAUSE.Max)
				hum:MoveTo(randomInZone(zone))
			end
		end
		task.wait(if aimAt then math.min(THINK, SHOT_GAP) else THINK)
	end
end

spawnGuard = function(zoneIndex: number)
	local zone = ZONES[zoneIndex]
	local model, hum, root = NPCCommon.build(describe(), "SecurityGuard", randomInZone(zone), rng:NextNumber() * math.pi * 2)
	if not model or not hum or not root then
		return
	end
	local m, h, r = model :: Model, hum :: Humanoid, root :: BasePart
	-- uniform markings and the zone's collision group
	local torso = m:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		label(torso, Enum.NormalId.Back, "SECURITY", 40, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.18))
		label(torso, Enum.NormalId.Front, "SECURITY", 16, UDim2.fromScale(0.45, 0.15), UDim2.fromScale(0.52, 0.18))
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Guards"
		end
	end
	local tool, weld, t = arm(m, h)
	NPCCommon.animate(h, r)
	NPCCommon.onDeath(m, h, REMOVE_AFTER, RESPAWN_AFTER, function()
		spawnGuard(zoneIndex)
	end)
	if tool and weld and t then
		task.spawn(brain, zoneIndex, m, h, r, tool, weld, t)
	end
end

for i = 1, #ZONES do
	for _ = 1, PER_ZONE do
		task.spawn(spawnGuard, i)
	end
end
