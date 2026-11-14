--!strict
-- Server authority for guns: ammo, fire rate, hit detection, damage, and auto-equip on spawn.
-- The client only asks to shoot (origin + direction); the server checks everything and does the raycast.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Weapons = ReplicatedStorage:WaitForChild("Weapons")
local Config = require(Weapons:WaitForChild("WeaponConfig"))
local GunPose = require(Weapons:WaitForChild("GunPose"))

local SPAWN_WEAPON = "M4A1" -- equipped automatically when a player spawns
local MAX_ORIGIN_OFFSET = 10 -- studs between the claimed muzzle and the player's head
local BURST_TOKENS = 3 -- shots that may arrive bunched together by network jitter

local remotes = ReplicatedStorage:FindFirstChild("WeaponRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "WeaponRemotes"
	remotes.Parent = ReplicatedStorage
end
local function remote(name: string): RemoteEvent
	local r = remotes:FindFirstChild(name) :: RemoteEvent?
	if not r then
		local n = Instance.new("RemoteEvent")
		n.Name = name
		n.Parent = remotes
		return n
	end
	return r
end
local FireRemote = remote("Fire")
local ReloadRemote = remote("Reload")
local ShotRemote = remote("Shot") -- server -> other clients, for effects
local PoseRemote = remote("Pose") -- client -> server: aiming + pitch, so everyone sees the gun raised

type State = { tokens: number, lastRefill: number, reloadToken: number, reloading: boolean }
local states: { [Player]: State } = {}

local function equippedWeapon(player: Player): (Tool?, any, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil, nil, nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil, nil
	end
	local cfg = Config[tool.Name]
	if not cfg then
		return nil, nil, nil
	end
	return tool, cfg, hum
end

local function isFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or c == math.huge or c == -math.huge then
			return false
		end
	end
	return true
end

local function others(player: Player, ...: any)
	for _, p in Players:GetPlayers() do
		if p ~= player then
			ShotRemote:FireClient(p, ...)
		end
	end
end

FireRemote.OnServerEvent:Connect(function(player: Player, origin: any, direction: any)
	if not isFiniteVector(origin) or not isFiniteVector(direction) then
		return
	end
	local tool, cfg, hum = equippedWeapon(player)
	local st = states[player]
	if not tool or not cfg or not hum or not st or st.reloading then
		return
	end
	-- fire-rate limit (token bucket: refills at the gun's real fire rate)
	local now = os.clock()
	local rate = cfg.RPM / 60
	st.tokens = math.min(BURST_TOKENS, st.tokens + (now - st.lastRefill) * rate)
	st.lastRefill = now
	if st.tokens < 1 then
		return
	end
	st.tokens -= 1

	local ammo = tool:GetAttribute("Ammo")
	if typeof(ammo) ~= "number" or ammo <= 0 then
		return
	end
	tool:SetAttribute("Ammo", ammo - 1)

	local char = player.Character :: Model
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head or (origin - head.Position).Magnitude > MAX_ORIGIN_OFFSET then
		return
	end
	if direction.Magnitude < 0.01 then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local fxFolder = Workspace:FindFirstChild("WeaponFx")
	params.FilterDescendantsInstances = fxFolder and { char, fxFolder } or { char }
	local result = Workspace:Raycast(origin, direction.Unit * cfg.Range, params)

	local hitPos = origin + direction.Unit * cfg.Range
	local normal = -direction.Unit
	local hitChar = false
	if result then
		hitPos, normal = result.Position, result.Normal
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local victim = model and model:FindFirstChildOfClass("Humanoid")
		if victim and victim.Health > 0 then
			hitChar = true
			local dmg = cfg.Damage
			if result.Instance.Name == "Head" then
				dmg *= cfg.HeadMultiplier
			end
			victim:TakeDamage(dmg)
		end
	end
	others(player, tool, "Fire", hitPos, normal, hitChar)
end)

ReloadRemote.OnServerEvent:Connect(function(player: Player)
	local tool, cfg = equippedWeapon(player)
	local st = states[player]
	if not tool or not cfg or not st or st.reloading then
		return
	end
	local ammo = tool:GetAttribute("Ammo") :: number
	local reserve = tool:GetAttribute("Reserve") :: number
	if ammo >= cfg.MagSize or reserve <= 0 then
		return
	end
	st.reloading = true
	st.reloadToken += 1
	local token = st.reloadToken
	others(player, tool, "Reload")
	task.delay(cfg.ReloadTime, function()
		if states[player] ~= st or st.reloadToken ~= token then
			return
		end
		st.reloading = false
		-- cancelled if the gun was put away or the player died mid-reload
		if tool.Parent ~= player.Character then
			return
		end
		local a = tool:GetAttribute("Ammo") :: number
		local r = tool:GetAttribute("Reserve") :: number
		local take = math.min(cfg.MagSize - a, r)
		tool:SetAttribute("Ammo", a + take)
		tool:SetAttribute("Reserve", r - take)
	end)
end)

-- Two-handed hold ----------------------------------------------------------
-- The gun is welded to the torso instead of the right hand; IKControls put both hands on it.
type Hold = { tool: Tool, weld: Weld, torso: BasePart, conns: { RBXScriptConnection }, lastPose: number }
local holds: { [Player]: Hold } = {}

local function armIK(hum: Humanoid, char: Model, side: string): IKControl?
	local name = "Gun" .. side .. "ArmIK"
	local existing = hum:FindFirstChild(name) :: IKControl?
	if existing then
		return existing
	end
	local upper = char:FindFirstChild(side .. "UpperArm")
	local hand = char:FindFirstChild(side .. "Hand")
	local gripAtt = hand and hand:FindFirstChild(side .. "GripAttachment")
	local torso = char:FindFirstChild("UpperTorso")
	if not upper or not gripAtt or not torso then
		return nil -- not an R15 rig: keep the default one-hand hold
	end
	local pole = Instance.new("Attachment")
	pole.Name = "Gun" .. side .. "ElbowPole"
	pole.Position = side == "Right" and Vector3.new(2, -2, 1) or Vector3.new(-2, -2.2, -0.5)
	pole.Parent = torso
	local ik = Instance.new("IKControl")
	ik.Name = name
	ik.Type = Enum.IKControlType.Transform
	ik.ChainRoot = upper
	ik.EndEffector = gripAtt
	ik.Pole = pole
	ik.SmoothTime = 0.04
	ik.Enabled = false
	ik.Parent = hum
	return ik
end

local function releaseHold(player: Player)
	local h = holds[player]
	if not h then
		return
	end
	holds[player] = nil
	for _, c in h.conns do
		c:Disconnect()
	end
	h.weld:Destroy()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		for _, side in { "Right", "Left" } do
			local ik = hum:FindFirstChild("Gun" .. side .. "ArmIK") :: IKControl?
			if ik then
				ik.Enabled = false
				ik.Target = nil
			end
		end
	end
end

local function takeHold(player: Player, char: Model, tool: Tool)
	releaseHold(player)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	local torso = GunPose.torsoFor(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not handle or not torso or not hum then
		return
	end
	local conns: { RBXScriptConnection } = {}
	-- remove the default "held in the right hand" weld, now and if the tool system re-adds it
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if hand then
		local old = hand:FindFirstChild("RightGrip")
		if old then
			old:Destroy()
		end
		table.insert(conns, hand.ChildAdded:Connect(function(c)
			if c.Name == "RightGrip" then
				task.defer(c.Destroy, c)
			end
		end))
	end
	local weld = Instance.new("Weld")
	weld.Name = "GunHold"
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = GunPose.cframe(torso.Size, 0, 0, 0)
	weld.Parent = handle
	holds[player] = { tool = tool, weld = weld, torso = torso, conns = conns, lastPose = 0 }

	for _, side in { "Right", "Left" } do
		local ik = armIK(hum, char, side)
		local target = handle:FindFirstChild(side .. "HandIK")
		if ik and target then
			ik.Target = target
			ik.Enabled = true
		end
	end
end

PoseRemote.OnServerEvent:Connect(function(player: Player, aiming: any, pitch: any, yaw: any)
	local h = holds[player]
	if not h or typeof(aiming) ~= "boolean" or typeof(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	if typeof(yaw) ~= "number" or yaw ~= yaw then
		yaw = 0
	end
	local now = os.clock()
	if now - h.lastPose < 1 / 30 then
		return
	end
	h.lastPose = now
	local p = math.clamp(pitch, -1.3, 1.3)
	local y = math.clamp(yaw, -GunPose.MAX_YAW, GunPose.MAX_YAW)
	h.weld.C0 = GunPose.cframe(h.torso.Size, aiming and 1 or 0, p, y)
	-- other clients rebuild the pose from these while they play this gun's reload animation
	h.tool:SetAttribute("PoseAim", aiming)
	h.tool:SetAttribute("PosePitch", p)
	h.tool:SetAttribute("PoseYaw", y)
end)

local function onCharacter(player: Player, char: Model)
	local st = states[player]
	if st then
		st.reloading = false
		st.reloadToken += 1
	end
	releaseHold(player)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") and Config[c.Name] then
			takeHold(player, char, c)
		end
	end)
	char.ChildRemoved:Connect(function(c)
		local h = holds[player]
		if h and h.tool == c then
			releaseHold(player)
		end
	end)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local backpack = player:WaitForChild("Backpack", 10)
	if not hum or not backpack then
		return
	end
	local tool = backpack:FindFirstChild(SPAWN_WEAPON) or backpack:WaitForChild(SPAWN_WEAPON, 10)
	if tool and tool:IsA("Tool") and hum.Health > 0 and player.Character == char then
		hum:EquipTool(tool)
	end
end

local function onPlayer(player: Player)
	states[player] = { tokens = BURST_TOKENS, lastRefill = os.clock(), reloadToken = 0, reloading = false }
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(p)
	releaseHold(p)
	states[p] = nil
end)
