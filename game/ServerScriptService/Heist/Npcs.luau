--!strict
-- People in the bank during a scouting trip or a heist: 4 tellers, the manager (he carries the level 5
-- card), customers, 2 armed guards, and police squads once the police is on its way.
--  * Detection: staff, guards and cameras notice a "suspicious" crew member in sight (a gun or heist tool
--    in hand, a money bag, or being in a staff-only zone; customers only care about guns and bags).
--    A "?" over their head fills up; when full a staff member/guard/camera raises the bank alarm,
--    a customer panics and runs out.
--  * Aim a gun at a civilian: hands up (they can't raise the alarm while scared). Then "Attacher" with a
--    zip tie: tied for good. The manager's card: "Subtiliser" from behind, or "Prendre" once he's tied.
--  * After the alarm, guards fight; police squads come in and hunt the crew (pathfinding + bursts).
-- The heist (Run) owns the lifecycle: Npcs.spawnBank(mode), Npcs.clear(), Npcs.spawnPolice(n).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local TweenService = game:GetService("TweenService")

local NPCCommon = require(script.Parent.Parent:WaitForChild("NPC"):WaitForChild("NPCCommon"))
local GunPose = require(ReplicatedStorage:WaitForChild("Weapons"):WaitForChild("GunPose"))
local Shot = ReplicatedStorage:WaitForChild("WeaponRemotes"):WaitForChild("Shot") :: RemoteEvent
local Heist = ReplicatedStorage:WaitForChild("Heist")
local Sfx = require(Heist:WaitForChild("Sfx"))
local Net = require(Heist:WaitForChild("Net"))

local Npcs = {}
local RGB = Color3.fromRGB
local rng = Random.new()

export type Npc = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	head: BasePart,
	role: string,
	state: string, -- Idle, HandsUp, Tied, Flee, Hostile, Dead
	meter: number,
	handsUntil: number,
	hasCard: boolean,
	bubble: BillboardGui?,
	gun: Tool?,
	weld: Weld?,
	torso: BasePart?,
	aimAt: Vector3?,
	target: Model?,
	nextPath: number,
	shoulders: { [string]: { m: Motor6D, c0: CFrame } },
	prompts: { [string]: ProximityPrompt },
}

local list: { Npc } = {}
Npcs.list = list
-- hooks set by Run
Npcs.onAlarm = function(_why: string, _pos: Vector3) end
Npcs.isCrew = function(_p: Player): boolean
	return false
end
Npcs.onCard = function(_p: Player) end
Npcs.zipTie = function(_p: Player): boolean
	return false
end
Npcs.mode = "Off" -- "Scout" (bank open, no crime expected) or "Heist"

local SKINS = { RGB(234, 184, 146), RGB(204, 142, 105), RGB(160, 105, 75), RGB(110, 72, 50) }
local HAIR = { 7193401217, 9243992729, 9244010432 }

local function describe(shirt: Color3, pants: Color3, hair: boolean?): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	if hair ~= false then
		d.HairAccessory = tostring(HAIR[rng:NextInteger(1, #HAIR)])
	end
	local skin = SKINS[rng:NextInteger(1, #SKINS)]
	d.HeadColor = skin
	d.LeftArmColor, d.RightArmColor = shirt, shirt
	d.TorsoColor = shirt
	d.LeftLegColor, d.RightLegColor = pants, pants
	return d
end

local function torsoLabel(model: Model, text: string, col: Color3)
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	if not torso then
		return
	end
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.CanvasSize = Vector2.new(200, 160)
		g.Parent = torso
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = if face == Enum.NormalId.Back then UDim2.fromScale(1, 0.4) else UDim2.fromScale(0.45, 0.15)
		t.Position = if face == Enum.NormalId.Back then UDim2.fromScale(0, 0.18) else UDim2.fromScale(0.52, 0.18)
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = col
		t.Font = Enum.Font.Arcade
		t.Parent = g
	end
end

------------------------------------------------------------------ bubble ("?" filling up, "!" when alarmed)

local function bubble(n: Npc): BillboardGui
	if n.bubble and n.bubble.Parent then
		return n.bubble
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Bubble"
	bb.Size = UDim2.fromScale(2.4, 2.4)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Parent = n.head
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = RGB(242, 243, 243)
	bg.BorderSizePixel = 0
	bg.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = RGB(27, 42, 53)
	st.Parent = bg
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = RGB(245, 205, 48)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local l = Instance.new("TextLabel")
	l.Name = "Mark"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = "?"
	l.TextScaled = true
	l.FontFace = Font.fromEnum(Enum.Font.Arcade)
	l.TextColor3 = RGB(27, 42, 53)
	l.ZIndex = 2
	l.Parent = bg
	bb.Enabled = false
	n.bubble = bb
	return bb
end

local function setBubble(n: Npc, meter: number, mark: string?, col: Color3?)
	local bb = bubble(n)
	bb.Enabled = meter > 0.02 or mark ~= nil
	local bg = bb:FindFirstChild("Bg") :: Frame
	local fill = bg:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(1, math.clamp(meter, 0, 1))
	fill.BackgroundColor3 = col or RGB(245, 205, 48);
	(bg:FindFirstChild("Mark") :: TextLabel).Text = mark or "?"
end

local function say(n: Npc, text: string, col: Color3?)
	Sfx.popText(n.head.Position + Vector3.new(0, 3.5, 0), text, col or RGB(242, 243, 243), 7)
end

------------------------------------------------------------------ poses (shoulder C0 offsets, goofy jitter)

local function captureShoulders(n: Npc)
	for _, side in { "Right", "Left" } do
		local arm = n.model:FindFirstChild(side .. "UpperArm")
		local m = arm and arm:FindFirstChild(side .. "Shoulder") :: Motor6D?
		if m then
			n.shoulders[side] = { m = m, c0 = m.C0 }
		end
	end
end

local function pose(n: Npc, kind: string)
	for side, s in n.shoulders do
		local sign = if side == "Right" then 1 else -1
		if kind == "up" then
			s.m.C0 = s.c0 * CFrame.Angles(math.rad(165), 0, math.rad(-12 * sign))
		elseif kind == "tied" then
			s.m.C0 = s.c0 * CFrame.Angles(math.rad(-35), 0, math.rad(20 * sign))
		else
			s.m.C0 = s.c0
		end
	end
end

------------------------------------------------------------------ guns for guards / police

local function eyeParams(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { NPCCommon.folder }
	for _, n in { "WeaponFx", "HeistFx" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = false -- decoration is CanQuery=false already; the crew's body parts may not collide
	return p
end

local function arm(n: Npc)
	local src = StarterPack:FindFirstChild("M4A1")
	local torso = n.model:FindFirstChild("UpperTorso") :: BasePart?
	if not src or not torso then
		return
	end
	local tool = src:Clone() :: Tool
	for _, d in tool:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
		end
	end
	tool.CanBeDropped = false
	local handle = tool:FindFirstChild("Handle") :: BasePart
	tool.Parent = n.model
	local hand = n.model:FindFirstChild("RightHand")
	local g = hand and hand:FindFirstChild("RightGrip")
	if g then
		g:Destroy()
	end
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
		local upper = n.model:FindFirstChild(side .. "UpperArm")
		local h = n.model:FindFirstChild(side .. "Hand")
		local grip = h and h:FindFirstChild(side .. "GripAttachment")
		local target = handle:FindFirstChild(side .. "HandIK")
		if upper and grip and target then
			local ik = Instance.new("IKControl")
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upper
			ik.EndEffector = grip
			ik.Target = target
			ik.SmoothTime = 0.04
			ik.Parent = n.hum
		end
	end
	n.gun, n.weld, n.torso = tool, weld, torso
end

local function crewPoints(char: Model): { Vector3 }
	local out = {}
	for _, name in { "UpperTorso", "Head" } do
		local p = char:FindFirstChild(name) :: BasePart?
		if p then
			table.insert(out, p.Position)
		end
	end
	return out
end

-- nearest visible crew point from `from` within range, and its character
local function spotCrew(from: Vector3, range: number): (Vector3?, Model?)
	local params = eyeParams()
	local best, bestChar, bestD = nil, nil, range
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and hum and hum.Health > 0 and Npcs.isCrew(pl) then
			for _, pt in crewPoints(char) do
				local d = (pt - from).Magnitude
				if d < bestD then
					local hit = workspace:Raycast(from, (pt - from) * 1.02, params)
					if hit and hit.Instance:IsDescendantOf(char) then
						best, bestChar, bestD = pt, char, d
						break
					end
				end
			end
		end
	end
	return best, bestChar
end

local function fire(n: Npc, aimAt: Vector3, damage: number, spreadDeg: number)
	local tool = n.gun
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	local muzzle = handle and handle:FindFirstChild("Muzzle") :: Attachment?
	if not tool or not muzzle then
		return
	end
	local origin = muzzle.WorldPosition
	local dir = (aimAt - origin).Unit
	local spread = math.rad(spreadDeg) * math.sqrt(rng:NextNumber())
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, rng:NextNumber() * math.pi * 2) * CFrame.Angles(spread, 0, 0)).LookVector
	local hit = workspace:Raycast(origin, dir * 400, eyeParams())
	local hitPos = if hit then hit.Position else origin + dir * 400
	local hitChar = false
	if hit then
		local char = hit.Instance:FindFirstAncestorOfClass("Model")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and Players:GetPlayerFromCharacter(char) then
			hitChar = true
			hum:TakeDamage(damage)
		end
	end
	Shot:FireAllClients(tool, "Fire", hitPos, if hit then hit.Normal else -dir, hitChar)
end

------------------------------------------------------------------ spawning

local function prompt(n: Npc, name: string, action: string, hold: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = n.model.Name
	pp.HoldDuration = hold
	pp.MaxActivationDistance = 7
	pp.RequiresLineOfSight = false
	pp.Enabled = false
	pp.Parent = n.root
	n.prompts[name] = pp
	return pp
end

local function new(role: string, name: string, cf: CFrame, desc: HumanoidDescription): Npc?
	-- floor right under the marker (a ray from high up would land on the bank's roof)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { NPCCommon.folder }
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	local pos = if hit then hit.Position else cf.Position
	local _, yaw, _ = cf:ToOrientation()
	local model, hum, root = NPCCommon.build(desc, name, pos, yaw)
	if not model or not hum or not root then
		return nil
	end
	local n: Npc = {
		model = model, hum = hum, root = root, head = model:FindFirstChild("Head") :: BasePart,
		role = role, state = "Idle", meter = 0, handsUntil = 0, hasCard = role == "Manager",
		bubble = nil, gun = nil, weld = nil, torso = nil, aimAt = nil, target = nil, nextPath = 0,
		shoulders = {}, prompts = {},
	}
	model:SetAttribute("Role", role)
	NPCCommon.animate(hum, root)
	captureShoulders(n)
	if role ~= "Guard" and role ~= "Police" then
		prompt(n, "TiePrompt", "Attacher (zip tie)", 1)
	end
	if role == "Manager" then
		local pick = prompt(n, "CardPrompt", "Subtiliser la carte Nv.5", 2.5)
		pick.MaxActivationDistance = 6
		model:SetAttribute("HasCard", true)
	end
	hum.Died:Connect(function()
		n.state = "Dead"
		for _, pp in n.prompts do
			pp.Enabled = false
		end
		if n.bubble then
			n.bubble.Enabled = false
		end
		if n.hasCard then
			-- the card drops on the floor next to the body
			n.hasCard = false
			Npcs.dropCard(root.Position)
		end
		task.delay(8, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)
	table.insert(list, n)
	return n
end

local function markers(role: string): { BasePart }
	local out = {}
	for _, m in CollectionService:GetTagged("HeistMarker") do
		if m:IsA("BasePart") and m:GetAttribute("Role") == role and m:IsDescendantOf(workspace) then
			table.insert(out, m)
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end
Npcs.markers = markers

-- the bank's people for a scouting trip ("Scout") or a heist ("Heist")
function Npcs.spawnBank(mode: string)
	Npcs.clear()
	Npcs.mode = mode
	for i, m in markers("Teller") do
		local n = new("Teller", "Guichetier " .. i, m.CFrame, describe(RGB(242, 243, 243), RGB(40, 40, 46)))
		if n then
			n.model:SetAttribute("Home", m.CFrame)
		end
	end
	local mgr = markers("Manager")[1]
	if mgr then
		local n = new("Manager", "M. Noobla (directeur)", mgr.CFrame, describe(RGB(36, 44, 80), RGB(36, 44, 80)))
		if n then
			n.model:SetAttribute("Home", mgr.CFrame)
			torsoLabel(n.model, "DIRECTEUR", RGB(230, 180, 40))
			-- gold card clipped to the belt
			local card = Instance.new("Part")
			card.Name = "BeltCard"
			card.Size = Vector3.new(0.5, 0.7, 0.05)
			card.Color = RGB(230, 180, 40)
			card.Material = Enum.Material.Metal
			card.CanCollide = false
			card.CanQuery = false
			card.Massless = true
			local lt = n.model:FindFirstChild("LowerTorso") :: BasePart?
			if lt then
				card.CFrame = lt.CFrame * CFrame.new(0.5, 0, -lt.Size.Z / 2 - 0.05)
				local w = Instance.new("WeldConstraint")
				w.Part0 = lt
				w.Part1 = card
				w.Parent = card
				card.Parent = n.model
			end
		end
	end
	for i, m in markers("Customer") do
		local shirt = Color3.fromHSV(rng:NextNumber(), 0.55, 0.85)
		new("Customer", "Client " .. i, m.CFrame, describe(shirt, RGB(50, 70, 120)))
	end
	for i, m in markers("Guard") do
		local n = new("Guard", "Vigile " .. i, m.CFrame, describe(RGB(28, 38, 66), RGB(22, 22, 26)))
		if n then
			torsoLabel(n.model, "SECURITE", RGB(242, 243, 243))
			n.model:SetAttribute("Home", m.CFrame)
			arm(n)
		end
	end
end

-- a police squad of `count` officers at the front sidewalk
function Npcs.spawnPolice(count: number)
	local stage = markers("PoliceStage")[1]
	if not stage then
		return
	end
	for i = 1, count do
		local cf = stage.CFrame * CFrame.new((i - count / 2) * 3, 0, rng:NextNumber(-2, 2))
		local n = new("Police", "Police", cf, describe(RGB(20, 40, 110), RGB(20, 24, 40), false))
		if n then
			torsoLabel(n.model, "POLICE", RGB(242, 243, 243))
			n.state = "Hostile"
			n.hum.WalkSpeed = 10
			arm(n)
			-- police cap
			local head = n.head
			local cap = Instance.new("Part")
			cap.Name = "Cap"
			cap.Size = Vector3.new(1.3, 0.45, 1.4)
			cap.Color = RGB(20, 30, 70)
			cap.TopSurface = Enum.SurfaceType.Studs
			cap.CanCollide = false
			cap.Massless = true
			cap.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.1, -0.1)
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = cap
			w.Parent = cap
			cap.Parent = n.model
		end
	end
end

function Npcs.clear()
	for _, n in list do
		if n.model.Parent then
			n.model:Destroy()
		end
	end
	table.clear(list)
	local card = workspace:FindFirstChild("DroppedCard", true)
	if card then
		card:Destroy()
	end
end

function Npcs.alive(role: string?): number
	local c = 0
	for _, n in list do
		if n.state ~= "Dead" and (role == nil or n.role == role) then
			c += 1
		end
	end
	return c
end

-- all staff that could call the police are tied up or dead
function Npcs.staffNeutralized(): boolean
	for _, n in list do
		if (n.role == "Teller" or n.role == "Manager" or n.role == "Guard") and n.state ~= "Dead" and n.state ~= "Tied" then
			return false
		end
	end
	return true
end

-- the card on the floor (manager killed): a pickup
function Npcs.dropCard(pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "DroppedCard"
	p.Size = Vector3.new(0.9, 0.1, 0.6)
	p.Color = RGB(230, 180, 40)
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.new(pos.X, pos.Y - 2.6, pos.Z)
	p.Parent = Sfx.folder()
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "PickCard"
	pp.ActionText = "Ramasser la carte Nv.5"
	pp.ObjectText = "Carte d'accès"
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.Parent = p
	pp.Triggered:Connect(function(pl)
		if p.Parent and Npcs.isCrew(pl) then
			p:Destroy()
			Npcs.onCard(pl)
		end
	end)
end

------------------------------------------------------------------ reactions

local function handsUp(n: Npc, by: Player)
	if n.state == "Tied" or n.state == "Dead" or n.role == "Guard" or n.role == "Police" then
		return
	end
	local first = n.state ~= "HandsUp"
	n.state = "HandsUp"
	n.handsUntil = os.clock() + 25
	n.meter = 0
	n.hum:MoveTo(n.root.Position)
	pose(n, "up")
	setBubble(n, 1, "!", RGB(120, 200, 255))
	if first then
		say(n, if n.role == "Customer" then "PITIE !" else "NE TIREZ PAS !", RGB(120, 200, 255))
		Sfx.play("boing", n.head, 0.5, 1.4)
	end
	n.prompts.TiePrompt.Enabled = true
	if n.prompts.CardPrompt and n.hasCard then
		n.prompts.CardPrompt.ActionText = "Prendre la carte Nv.5"
		n.prompts.CardPrompt.HoldDuration = 1
		n.prompts.CardPrompt.Enabled = true
	end
	local _ = by
end

local function tie(n: Npc, by: Player)
	if n.state ~= "HandsUp" then
		return
	end
	if not Npcs.zipTie(by) then
		return
	end
	n.state = "Tied"
	n.prompts.TiePrompt.Enabled = false
	pose(n, "tied")
	n.root.Anchored = true
	TweenService:Create(n.root, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { CFrame = n.root.CFrame * CFrame.new(0, -1.6, 0) }):Play()
	setBubble(n, 1, "Z", RGB(160, 160, 165))
	say(n, "MMMPH !", RGB(220, 220, 220))
	Sfx.play("clank", n.root, 0.6, 1.3)
	if n.prompts.CardPrompt and n.hasCard then
		n.prompts.CardPrompt.ActionText = "Prendre la carte Nv.5"
		n.prompts.CardPrompt.HoldDuration = 1
		n.prompts.CardPrompt.Enabled = true
	end
end

local function panic(n: Npc)
	if n.state == "Flee" or n.state == "Tied" or n.state == "Dead" then
		return
	end
	n.state = "Flee"
	say(n, "AAAAH !", RGB(255, 120, 120))
	setBubble(n, 1, "!", RGB(255, 80, 80))
	local start = markers("Start")[1]
	local exit = if start then start.Position else n.root.Position + Vector3.new(0, 0, -60)
	n.hum.WalkSpeed = 14
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(function()
			path:ComputeAsync(n.root.Position, exit)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			for _, wp in path:GetWaypoints() do
				if n.state ~= "Flee" then
					return
				end
				n.hum:MoveTo(wp.Position)
				n.hum.MoveToFinished:Wait()
			end
		end
		if n.state == "Flee" and n.model.Parent then
			n.model:Destroy()
		end
	end)
end

local function raise(n: Npc, why: string)
	if n.role == "Customer" then
		panic(n)
		return
	end
	setBubble(n, 1, "!", RGB(255, 60, 60))
	say(n, if n.role == "Guard" then "HALTE !" else "ALARME !", RGB(255, 90, 90))
	Npcs.onAlarm(why, n.root.Position)
end

-- prompts on the NPCs
local function wirePrompts()
	local function handle(pp: ProximityPrompt, player: Player)
		if pp.Name ~= "TiePrompt" and pp.Name ~= "CardPrompt" then
			return
		end
		for _, n in list do
			if n.prompts[pp.Name] == pp then
				if not Npcs.isCrew(player) then
					return
				end
				if pp.Name == "TiePrompt" then
					tie(n, player)
				elseif n.hasCard then
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not root then
						return
					end
					local calm = n.state == "Idle"
					if calm then
						-- pickpocket only works from behind
						local toPlayer = (root.Position - n.root.Position) * Vector3.new(1, 0, 1)
						local behind = toPlayer.Magnitude > 0.1 and n.root.CFrame.LookVector:Dot(toPlayer.Unit) < -0.2
						if not behind then
							n.meter = math.max(n.meter, 0.7)
							say(n, "HE ! VOS MAINS !", RGB(255, 200, 80))
							return
						end
					end
					n.hasCard = false
					n.model:SetAttribute("HasCard", false)
					local belt = n.model:FindFirstChild("BeltCard")
					if belt then
						belt:Destroy()
					end
					pp.Enabled = false
					Sfx.popText(n.head.Position + Vector3.new(0, 3, 0), if calm then "*CHOURAVE*" else "CARTE !", RGB(245, 205, 48), 7)
					Npcs.onCard(player)
				end
				return
			end
		end
	end
	Npcs.trigger = handle
	game:GetService("ProximityPromptService").PromptTriggered:Connect(handle)
end

------------------------------------------------------------------ the brain loop

local function inRestricted(pos: Vector3): boolean
	for _, z in CollectionService:GetTagged("Restricted") do
		if z:IsA("BasePart") and z:IsDescendantOf(workspace) then
			local lp = z.CFrame:PointToObjectSpace(pos)
			local s = z.Size / 2
			if math.abs(lp.X) <= s.X and math.abs(lp.Y) <= s.Y and math.abs(lp.Z) <= s.Z then
				return true
			end
		end
	end
	return false
end
Npcs.inRestricted = inRestricted

-- how suspicious a crew member looks to this kind of watcher (0 = not at all)
function Npcs.suspicion(pl: Player, watcher: string): number
	local char = pl.Character
	if not char then
		return 0
	end
	local held = char:FindFirstChildOfClass("Tool")
	if held and held:GetAttribute("HeistGear") then
		local id = held:GetAttribute("ItemId")
		if id == "pistol" or id == "rifle" or id == "sniper" then
			return 1.6 -- a gun out: obvious
		end
		if watcher ~= "Customer" then
			return 1
		end
	end
	if char:GetAttribute("Carry") then
		return 1.2
	end
	if watcher ~= "Customer" then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and inRestricted(root.Position) then
			return if Npcs.mode == "Scout" then 0.8 else 1
		end
	end
	return 0
end

-- player aiming at this NPC (gun up, facing it, close)
local function aimingAt(pl: Player, n: Npc): boolean
	local char = pl.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local held = char and char:FindFirstChildOfClass("Tool")
	-- the gun is raised (WeaponServer mirrors the client's aim as the tool attribute PoseAim)
	if not root or not held or not held:GetAttribute("HeistGear") or held:GetAttribute("PoseAim") ~= true then
		return false
	end
	local id = held:GetAttribute("ItemId")
	if id ~= "pistol" and id ~= "rifle" and id ~= "sniper" then
		return false
	end
	local to = n.root.Position - root.Position
	if to.Magnitude > 40 then
		return false
	end
	local yaw = held:GetAttribute("PoseYaw")
	local look = (root.CFrame * CFrame.Angles(0, if type(yaw) == "number" then yaw else 0, 0)).LookVector
	return Vector3.new(look.X, 0, look.Z).Unit:Dot(Vector3.new(to.X, 0, to.Z).Unit) > 0.9
end

local shoo: { [Player]: number } = {}

local function think(n: Npc, dt: number)
	if n.state == "Dead" or n.state == "Tied" or n.state == "Flee" or not n.model.Parent then
		return
	end
	local now = os.clock()
	-- scared civilians
	if n.role ~= "Guard" and n.role ~= "Police" then
		for _, pl in Players:GetPlayers() do
			if Npcs.isCrew(pl) and aimingAt(pl, n) then
				handsUp(n, pl)
			end
		end
		if n.state == "HandsUp" then
			-- goofy shaking
			for side, s in n.shoulders do
				local sign = if side == "Right" then 1 else -1
				s.m.C0 = s.c0 * CFrame.Angles(math.rad(165 + rng:NextNumber(-8, 8)), 0, math.rad(-12 * sign + rng:NextNumber(-6, 6)))
			end
			if now > n.handsUntil then
				n.state = "Idle"
				pose(n, "none")
				n.prompts.TiePrompt.Enabled = false
				setBubble(n, 0)
			end
			return
		end
	end
	if n.state == "Hostile" then
		return -- handled by the combat loop
	end
	-- detection
	local eye = n.head.Position
	local look = n.root.CFrame.LookVector
	local best = 0
	local who: Player? = nil
	for _, pl in Players:GetPlayers() do
		if Npcs.isCrew(pl) then
			local s = Npcs.suspicion(pl, n.role)
			local char = pl.Character
			local head = char and char:FindFirstChild("Head") :: BasePart?
			if s > 0 and head then
				local to = head.Position - eye
				local d = to.Magnitude
				if d < 70 and look:Dot(to.Unit) > 0.15 then
					local hit = workspace:Raycast(eye, to * 1.02, eyeParams())
					if hit and hit.Instance:IsDescendantOf(char :: Model) then
						local rate = s * (if d < 20 then 1.3 else (if d < 40 then 0.8 else 0.45))
						if rate > best then
							best, who = rate, pl
						end
					end
				end
			end
		end
	end
	if best > 0 and who then
		n.meter += dt * best * 0.75
		-- turn toward what they're looking at
		local wroot = who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if wroot and n.role ~= "Guard" then
			local flat = (wroot.Position - n.root.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.5 then
				n.root.CFrame = n.root.CFrame:Lerp(CFrame.lookAt(n.root.Position, n.root.Position + flat), math.min(1, dt * 3))
			end
		end
	else
		n.meter = math.max(0, n.meter - dt * 0.25)
	end
	if Npcs.mode == "Scout" then
		-- scouting: staff just shoo you out of staff areas, nobody raises an alarm
		if n.meter >= 1 and who then
			n.meter = 0.3
			if (shoo[who] or 0) < now then
				shoo[who] = now + 6
				say(n, "PERSONNEL UNIQUEMENT !", RGB(255, 200, 80))
				Net.event():FireClient(who, "Toast", "« Vous n'avez rien à faire ici ! » Reste discret pendant le repérage.", "warn")
				local start = markers("Start")[1]
				local char = who.Character
				if start and char and inRestricted((char:FindFirstChild("HumanoidRootPart") :: BasePart).Position) then
					char:PivotTo(start.CFrame + Vector3.new(0, 3, 0))
				end
			end
		end
		setBubble(n, n.meter)
		return
	end
	if n.meter >= 1 then
		n.meter = 1
		if n.role == "Guard" then
			n.state = "Hostile"
		end
		raise(n, if n.role == "Customer" then "panic" else "seen")
		return
	end
	setBubble(n, n.meter)
end

-- guards and police in a fight
local function fight(n: Npc)
	local now = os.clock()
	local point, char = spotCrew(n.head.Position, 260)
	if point then
		if not n.aimAt then
			n.nextPath = now + rng:NextNumber(0.6, 1.1) -- reaction time before the first burst
		end
		n.aimAt = point
		n.target = char
		n.hum.AutoRotate = false
		n.hum:MoveTo(n.root.Position)
		if now >= n.nextPath then
			for _ = 1, rng:NextInteger(2, 4) do
				if n.hum.Health <= 0 then
					break
				end
				fire(n, point, if n.role == "Police" then 6 else 5, 4.5)
				task.wait(0.13)
			end
			n.nextPath = os.clock() + rng:NextNumber(1.2, 2.2)
		end
	else
		n.aimAt = nil
		n.hum.AutoRotate = true
		-- walk toward the nearest crew member
		if now >= n.nextPath then
			n.nextPath = now + 1.5
			local best: Vector3? = nil
			local bd = 400
			for _, pl in Players:GetPlayers() do
				local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if r and Npcs.isCrew(pl) and (r.Position - n.root.Position).Magnitude < bd then
					best, bd = r.Position, (r.Position - n.root.Position).Magnitude
				end
			end
			if best then
				local goal = best
				task.spawn(function()
					local path = PathfindingService:CreatePath({ AgentRadius = 1.8, AgentHeight = 5, AgentCanJump = true })
					local ok = pcall(function()
						path:ComputeAsync(n.root.Position, goal)
					end)
					if ok and path.Status == Enum.PathStatus.Success then
						local wps = path:GetWaypoints()
						for i = 2, math.min(#wps, 6) do
							if n.aimAt or n.hum.Health <= 0 then
								return
							end
							n.hum:MoveTo(wps[i].Position)
							local reached = n.hum.MoveToFinished:Wait()
							if not reached then
								return
							end
						end
					else
						n.hum:MoveTo(goal)
					end
				end)
			end
		end
	end
end

-- smooth gun pose for armed NPCs
local function gunPose(n: Npc, dt: number)
	if not n.weld or not n.torso or not n.gun then
		return
	end
	local aim = (n.model:GetAttribute("Aim") :: number?) or 0
	aim += ((if n.aimAt then 1 else 0) - aim) * math.min(1, dt * 8)
	n.model:SetAttribute("Aim", aim)
	local yaw, pitch = 0, 0
	if n.aimAt then
		local flat = Vector3.new(n.aimAt.X - n.root.Position.X, 0, n.aimAt.Z - n.root.Position.Z)
		if flat.Magnitude > 0.1 then
			local want = math.atan2(-flat.X, -flat.Z)
			local _, cur, _ = n.root.CFrame:ToOrientation()
			local d = (want - cur + math.pi) % (2 * math.pi) - math.pi
			n.root.CFrame = CFrame.new(n.root.Position) * CFrame.fromOrientation(0, cur + math.clamp(d, -dt * 6, dt * 6), 0)
		end
		yaw, pitch = GunPose.anglesTo(n.torso, 1, n.aimAt)
	end
	n.weld.C0 = GunPose.cframe(n.torso.Size, aim, pitch, yaw)
	local left = (n.gun:FindFirstChild("Handle") :: BasePart):FindFirstChild("LeftHandIK") :: Attachment?
	if left then
		left.Position = GunPose.LEFT_READY:Lerp(GunPose.LEFT_AIM, aim)
	end
end

-- bank alarm: staff cower, guards fight, customers run
function Npcs.alarm()
	for _, n in list do
		if n.state ~= "Dead" and n.state ~= "Tied" then
			if n.role == "Guard" then
				n.state = "Hostile"
				setBubble(n, 1, "!", RGB(255, 60, 60))
			elseif n.role == "Customer" then
				panic(n)
			elseif n.state ~= "HandsUp" then
				n.meter = 0
				setBubble(n, 1, "!", RGB(255, 60, 60))
			end
		end
	end
end

-- manager wanders between his office, the corridor and the hall (the hall phone call is a scout clue)
local function managerRoutine(n: Npc)
	local walk = markers("ManagerWalk")
	local home = n.model:GetAttribute("Home")
	local i = 0
	while n.model.Parent and n.state ~= "Dead" do
		if n.state == "Idle" and Npcs.mode ~= "Off" and n.meter < 0.3 then
			i += 1
			local target = if i % 5 == 0 and typeof(home) == "CFrame" then home.Position else walk[(i - 1) % #walk + 1].Position
			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
			local ok = pcall(function()
				path:ComputeAsync(n.root.Position, target)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				for _, wp in path:GetWaypoints() do
					if n.state ~= "Idle" or n.meter > 0.3 then
						break
					end
					n.hum:MoveTo(wp.Position)
					n.hum.MoveToFinished:Wait()
				end
			end
			-- in the hall: he takes a call (scouts can listen in)
			local hallStop = walk[3]
			if hallStop and (n.root.Position - hallStop.Position).Magnitude < 6 and n.state == "Idle" then
				n.model:SetAttribute("OnPhone", true)
				say(n, "*DRING*", RGB(245, 205, 48))
				task.wait(14)
				n.model:SetAttribute("OnPhone", false)
			else
				task.wait(rng:NextNumber(5, 9))
			end
		else
			task.wait(1)
		end
	end
end

function Npcs.init()
	wirePrompts()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, n in list do
			if n.gun and n.state ~= "Dead" then
				gunPose(n, dt)
			end
		end
		acc += dt
		if acc < 0.2 then
			return
		end
		local step = acc
		acc = 0
		for _, n in list do
			if n.state ~= "Dead" then
				local ok, err = pcall(think, n, step)
				if not ok then
					warn("[Npcs]", err)
				end
			end
		end
	end)
	-- combat loop (yields inside, so one thread per armed NPC)
	task.spawn(function()
		local running: { [Npc]: boolean } = {}
		while true do
			for _, n in list do
				if n.state == "Hostile" and not running[n] and n.hum.Health > 0 then
					running[n] = true
					task.spawn(function()
						while n.state == "Hostile" and n.hum.Health > 0 and n.model.Parent do
							fight(n)
							task.wait(0.2)
						end
						running[n] = nil
					end)
				end
			end
			task.wait(0.3)
		end
	end)
	-- manager routine starts whenever a manager appears
	task.spawn(function()
		local started: { [Model]: boolean } = {}
		while true do
			for _, n in list do
				if n.role == "Manager" and not started[n.model] then
					started[n.model] = true
					task.spawn(managerRoutine, n)
				end
			end
			task.wait(1)
		end
	end)
end

return Npcs
