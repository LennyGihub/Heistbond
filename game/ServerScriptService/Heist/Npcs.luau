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
-- The heist (Run) owns the lifecycle: Npcs.spawnBank(mode), Npcs.clear(), Npcs.spawnPolice(n, unit).
--  * F with a gun out (Npcs.shout): the civilians in front of you drop to their knees and become
--    hostages. Zip-tie them; hostages you stop watching for a while stand up and run out of the bank
--    (staff raise the alarm on the way).
--  * Guards and police fight from cover as a squad (NpcCombat); the people in the bank live their day
--    and react to each other (NpcLife); every NPC has its own voice (Voices + NpcLines).
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
local Voices = require(Heist:WaitForChild("Voices"))
local Lines = require(script.Parent:WaitForChild("NpcLines"))
local Nav = require(script.Parent:WaitForChild("NpcNav"))
local ServerStorage = game:GetService("ServerStorage")
local Life: any = nil -- NpcLife, NpcCombat: required in Npcs.init (they get this module)
local Combat: any = nil

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
	shoulders: { [string]: { inst: any, prop: string, c0: CFrame } },
	joints: { [string]: { inst: any, prop: string, c0: CFrame, joint: any } },
	prompts: { [string]: ProximityPrompt },
	-- persona
	first: string,
	voice: number,
	bravery: number, -- 0 coward .. 1 brave
	chatty: number,
	unit: string, -- "Staff" | "Guard" | "Police" | "Swat"
	stance: string, -- stand | crouch | kneel
	hipBase: number,
	sayUntil: number,
	-- hostage
	unwatched: number,
	escapeAfter: number,
	warned: boolean,
	-- routines
	busy: string?,
	life: any,
	fight: any,
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

-- speech: the clients draw the bubble and play the voice (NpcVoice); mood = normal | scared | scream | angry | whisper
function Npcs.speak(n: Npc, text: string, mood: string?, force: boolean?)
	if n.state == "Dead" or not n.model.Parent then
		return
	end
	local t = os.clock()
	if not force and t < n.sayUntil then
		return
	end
	n.sayUntil = t + 0.8 + #text * 0.05
	Net.event():FireAllClients("Say", n.model, text, mood or "normal")
end

local function say(n: Npc, text: string, mood: string?)
	Npcs.speak(n, text, mood, true)
end

function Npcs.sfx(name: string, at: Instance, volume: number?, pitch: number?, dist: number?)
	Sfx.play(name, at, volume, pitch, dist)
end

local usedVoices: { [number]: boolean } = {}
local function assignVoice(model: Model, group: string)
	local pool = (Voices.groups :: any)[group] :: { number }
	local freeOnes = {}
	for _, v in pool do
		if not usedVoices[v] then
			table.insert(freeOnes, v)
		end
	end
	local v = if #freeOnes > 0 then freeOnes[rng:NextInteger(1, #freeOnes)] else pool[rng:NextInteger(1, #pool)]
	usedVoices[v] = true
	model:SetAttribute("Voice", v)
	model:SetAttribute("VoiceShift", if #freeOnes > 0 then rng:NextNumber(0.97, 1.03) else rng:NextNumber(0.86, 1.14))
	return v
end

------------------------------------------------------------------ poses (shoulder C0 offsets, goofy jitter)

local function captureShoulders(n: Npc)
	local function grab(part: string, joint: string)
		local p = n.model:FindFirstChild(part)
		local m = p and p:FindFirstChild(joint)
		if m then
			-- R15 rigs from a HumanoidDescription use AnimationConstraints (C0 is read-only there: the
			-- offset lives on Attachment0) or classic Motor6Ds
			local mm = m :: any
			if m:IsA("Motor6D") then
				n.joints[joint] = { inst = mm, prop = "C0", c0 = mm.C0, joint = mm }
			elseif mm.Attachment0 then
				n.joints[joint] = { inst = mm.Attachment0, prop = "CFrame", c0 = mm.Attachment0.CFrame, joint = mm }
			end
		end
	end
	for _, side in { "Right", "Left" } do
		grab(side .. "UpperArm", side .. "Shoulder")
		grab(side .. "LowerArm", side .. "Elbow")
		grab(side .. "UpperLeg", side .. "Hip")
		grab(side .. "LowerLeg", side .. "Knee")
		local sh = n.joints[side .. "Shoulder"]
		if sh then
			n.shoulders[side] = sh
		end
	end
	n.hipBase = n.hum.HipHeight
end

local function rotate(n: Npc, joint: string, rot: CFrame)
	local j = n.joints[joint]
	if j then
		j.inst[j.prop] = j.c0 * rot
	end
end

-- a posed NPC stops its idle/walk animation (NPCCommon watches the NoAnim attribute) and its joints'
-- leftover animation Transform is cleared, so the offsets below read as intended
local function refreshAnim(n: Npc)
	local posed = (n.model:GetAttribute("PoseKind") or "none") ~= "none" or n.stance ~= "stand"
	if n.model:GetAttribute("NoAnim") == posed then
		return
	end
	n.model:SetAttribute("NoAnim", posed)
	if posed then
		task.delay(0.2, function()
			if n.model:GetAttribute("NoAnim") then
				for _, j in n.joints do
					pcall(function()
						j.joint.Transform = CFrame.identity
					end)
				end
			end
		end)
	end
end

local function pose(n: Npc, kind: string)
	n.model:SetAttribute("PoseKind", kind)
	refreshAnim(n)
	for _, joint in { "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow" } do
		rotate(n, joint, CFrame.identity)
	end
	for _, side in { "Right", "Left" } do
		local sign = if side == "Right" then 1 else -1
		if kind == "up" then
			rotate(n, side .. "Shoulder", CFrame.Angles(math.rad(165), 0, math.rad(-12 * sign)))
		elseif kind == "tied" then
			rotate(n, side .. "Shoulder", CFrame.Angles(math.rad(-35), 0, math.rad(20 * sign)))
		elseif kind == "talk" and side == "Right" then
			rotate(n, "RightShoulder", CFrame.Angles(math.rad(50), 0, math.rad(-8)))
			rotate(n, "RightElbow", CFrame.Angles(math.rad(60), 0, 0))
		elseif kind == "phone" and side == "Right" then
			rotate(n, "RightShoulder", CFrame.Angles(math.rad(40), 0, math.rad(-10)))
			rotate(n, "RightElbow", CFrame.Angles(math.rad(115), 0, 0))
		end
	end
end
Npcs.pose = pose

-- stance: stand | crouch (behind a counter) | kneel (hostage). Lowers the hips and bends the legs.
local STANCES = {
	stand = { drop = 0, hip = 0, knee = 0 },
	crouch = { drop = 0.95, hip = math.rad(75), knee = math.rad(-120) },
	kneel = { drop = 1.15, hip = 0, knee = math.rad(-90) },
}
function Npcs.setStance(n: Npc, name: string)
	if n.stance == name or n.state == "Dead" then
		return
	end
	n.stance = name
	refreshAnim(n)
	local s = STANCES[name]
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad)
	TweenService:Create(n.hum, info, { HipHeight = n.hipBase - s.drop }):Play()
	for _, side in { "Left", "Right" } do
		local hip, knee = n.joints[side .. "Hip"], n.joints[side .. "Knee"]
		if hip then
			TweenService:Create(hip.inst, info, { [hip.prop] = hip.c0 * CFrame.Angles(s.hip, 0, 0) }):Play()
		end
		if knee then
			TweenService:Create(knee.inst, info, { [knee.prop] = knee.c0 * CFrame.Angles(s.knee, 0, 0) }):Play()
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

-- a ray that sees and shoots through glass (windows, glass partitions): they hide nothing and stop nothing
-- for the player's eyes, so they must not for the NPCs' either. Invisible blockers (transparency ~1) stay solid.
-- decor = true (cover tests): plants, trees and small props don't count as cover either
local function ray(origin: Vector3, vec: Vector3, params: RaycastParams, decor: boolean?): RaycastResult?
	for _ = 1, 6 do
		local hit = workspace:Raycast(origin, vec, params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		local t = inst.Transparency
		local small = false
		if decor then
			local m = inst:FindFirstAncestorWhichIsA("Model")
			local nm = if m then string.lower(m.Name) else ""
			small = inst.Size.Magnitude < 4 or string.find(nm, "plant") ~= nil or string.find(nm, "tree") ~= nil or string.find(nm, "bush") ~= nil
		end
		if (t >= 0.2 and t < 0.95) or inst.Material == Enum.Material.Glass or small then
			local list = params.FilterDescendantsInstances
			table.insert(list, inst)
			params.FilterDescendantsInstances = list
		else
			return hit
		end
	end
	return nil
end
Npcs.ray = ray

local function arm(n: Npc, gun: string?)
	local tools = ServerStorage:FindFirstChild("HeistTools")
	local src = (if gun == "Pistol" and tools then tools:FindFirstChild("Pistol") else nil) or StarterPack:FindFirstChild("M4A1")
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
					local hit = ray(from, (pt - from) * 1.02, params)
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
	local hit = ray(origin, dir * 400, eyeParams())
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
Npcs.fire = fire
Npcs.spotCrew = spotCrew
Npcs.eyeParams = eyeParams
Npcs.folder = NPCCommon.folder

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
		shoulders = {}, joints = {}, prompts = {},
		first = name, voice = 0, bravery = rng:NextNumber(0.05, 0.95), chatty = rng:NextNumber(0.3, 1),
		unit = if role == "Guard" then "Guard" elseif role == "Police" then "Police" else "Staff",
		stance = "stand", hipBase = hum.HipHeight, sayUntil = 0,
		unwatched = 0, escapeAfter = 10, warned = false, busy = nil, life = { chatAt = 0 }, fight = nil,
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
		local wasPos = root.Position
		n.state = "Dead"
		if Life and (role == "Teller" or role == "Manager" or role == "Customer" or role == "Guard") then
			Life.witness("death", n, wasPos)
		end
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

local function person(role: string, title: string, cf: CFrame, shirt: Color3, pants: Color3, group: string, female: boolean): Npc?
	local first = (if female then Lines.firstF else Lines.firstM)[rng:NextInteger(1, 12)]
	local n = new(role, first .. " (" .. title .. ")", cf, describe(shirt, pants))
	if n then
		n.first = first
		n.voice = assignVoice(n.model, group)
	end
	return n
end

-- the bank's people for a scouting trip ("Scout") or a heist ("Heist")
function Npcs.spawnBank(mode: string)
	Npcs.clear()
	Npcs.mode = mode
	for _, m in markers("Teller") do
		local female = rng:NextNumber() < 0.7
		local n = person("Teller", if female then "guichetière" else "guichetier", m.CFrame, RGB(242, 243, 243), RGB(40, 40, 46), if female then "CustomerF" else "CustomerM", female)
		if n then
			n.model:SetAttribute("Home", m.CFrame)
		end
	end
	local mgr = markers("Manager")[1]
	if mgr then
		local n = person("Manager", "directeur", mgr.CFrame, RGB(36, 44, 80), RGB(36, 44, 80), "Manager", false)
		if n then
			n.model.Name = "M. " .. n.first .. " Noobla (directeur)"
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
	for _, m in markers("Customer") do
		local female = rng:NextNumber() < 0.5
		local shirt = Color3.fromHSV(rng:NextNumber(), 0.55, 0.85)
		person("Customer", if female then "cliente" else "client", m.CFrame, shirt, RGB(50, 70, 120), if female then "CustomerF" else "CustomerM", female)
	end
	for _, m in markers("Guard") do
		local n = person("Guard", "vigile", m.CFrame, RGB(28, 38, 66), RGB(22, 22, 26), "Guard", false)
		if n then
			torsoLabel(n.model, "SECURITE", RGB(242, 243, 243))
			n.model:SetAttribute("Home", m.CFrame)
			arm(n, "Pistol")
		end
	end
	if Life then
		task.defer(Life.start)
	end
end

-- a police squad of `count` officers at the front sidewalk: unit "Police" (pistols) or "Swat" (M4s, armoured)
function Npcs.spawnPolice(count: number, unit: string?)
	local stage = markers("PoliceStage")[1]
	if not stage then
		return
	end
	local kind = unit or "Police"
	local swat = kind == "Swat"
	task.spawn(function()
		for i = 1, count do
			local cf = stage.CFrame * CFrame.new((i - count / 2) * 3, 0, rng:NextNumber(-2, 2) + (if swat then 5 else 0))
			local first = Lines.firstM[rng:NextInteger(1, #Lines.firstM)]
			local shirt = if swat then RGB(22, 24, 30) else RGB(20, 40, 110)
			local pants = if swat then RGB(18, 18, 22) else RGB(20, 24, 40)
			local n = new("Police", (if swat then "SWAT " else "Agent ") .. first, cf, describe(shirt, pants, false))
			if n then
				n.first = first
				n.unit = kind
				n.model:SetAttribute("Unit", kind)
				n.voice = assignVoice(n.model, if swat then "Swat" else "Police")
				torsoLabel(n.model, if swat then "SWAT" else "POLICE", RGB(242, 243, 243))
				n.state = "Hostile"
				n.hum.WalkSpeed = 12
				if swat then
					n.hum.MaxHealth = 160
					n.hum.Health = 160
				end
				arm(n, if swat then "M4A1" else "Pistol")
				-- headgear: a police cap, or a black SWAT helmet with a visor
				local head = n.head
				local cap = Instance.new("Part")
				cap.Name = if swat then "Helmet" else "Cap"
				cap.Size = if swat then Vector3.new(1.45, 0.8, 1.5) else Vector3.new(1.3, 0.45, 1.4)
				cap.Color = if swat then RGB(26, 28, 34) else RGB(20, 30, 70)
				cap.Material = if swat then Enum.Material.Metal else Enum.Material.Plastic
				cap.TopSurface = Enum.SurfaceType.Smooth
				cap.CanCollide = false
				cap.Massless = true
				cap.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + (if swat then -0.05 else 0.1), -0.1)
				local w = Instance.new("WeldConstraint")
				w.Part0 = head
				w.Part1 = cap
				w.Parent = cap
				cap.Parent = n.model
				if swat then
					local visor = Instance.new("Part")
					visor.Name = "Visor"
					visor.Size = Vector3.new(1.25, 0.35, 0.1)
					visor.Color = RGB(60, 90, 110)
					visor.Material = Enum.Material.Glass
					visor.CanCollide = false
					visor.Massless = true
					visor.CFrame = head.CFrame * CFrame.new(0, 0.1, -head.Size.Z / 2 - 0.02)
					local vw = Instance.new("WeldConstraint")
					vw.Part0 = head
					vw.Part1 = visor
					vw.Parent = visor
					visor.Parent = n.model
				end
				if i == 1 then
					local pool = (Lines.combat :: any)[if swat then "swat" else "police"] :: { string }
					Npcs.speak(n, Lines.pick(pool), "normal", true)
				end
			end
			task.wait(0.35)
		end
	end)
end

function Npcs.clear()
	for _, n in list do
		if n.model.Parent then
			n.model:Destroy()
		end
	end
	table.clear(list)
	table.clear(usedVoices)
	if Life then
		Life.reset()
	end
	if Combat then
		Combat.reset()
	end
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

local function cardPrompt(n: Npc)
	if n.prompts.CardPrompt and n.hasCard then
		n.prompts.CardPrompt.ActionText = "Prendre la carte Nv.5"
		n.prompts.CardPrompt.HoldDuration = 1
		n.prompts.CardPrompt.Enabled = true
	end
end

local function handsUp(n: Npc, by: Player)
	if n.state == "Tied" or n.state == "Dead" or n.state == "Down" or n.role == "Guard" or n.role == "Police" then
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
		say(n, Lines.react_("handsUp", n.role), "scared")
		Sfx.play("boing", n.head, 0.5, 1.4)
	end
	n.prompts.TiePrompt.Enabled = true
	cardPrompt(n)
	local _ = by
end

-- runs for the exit and leaves the bank
local function flee(n: Npc, speed: number)
	n.state = "Flee"
	n.busy = nil
	n.hum.WalkSpeed = speed
	setBubble(n, 1, "!", RGB(255, 80, 80))
	local start = markers("Start")[1]
	local exit = if start then start.Position else n.root.Position + Vector3.new(0, 0, -60)
	task.spawn(function()
		local function abort(): boolean
			return n.state ~= "Flee" or not n.model.Parent
		end
		local ok = Nav.walk(n.hum, n.root, exit, { speed = speed, abort = abort, arrive = 6, timeout = 40 })
		if not ok and not abort() then
			-- no path: run straight at it
			n.hum:MoveTo(exit)
			local t0 = os.clock()
			while not abort() and os.clock() - t0 < 6 and (n.root.Position - exit).Magnitude > 6 do
				task.wait(0.2)
			end
		end
		if not abort() then
			n.model:Destroy()
		end
	end)
end

local function panic(n: Npc)
	if n.state == "Flee" or n.state == "Tied" or n.state == "Dead" then
		return
	end
	say(n, Lines.react_("panic", n.role), "scream")
	if Life then
		Life.witness("flee", n, n.root.Position)
	end
	pose(n, "none")
	Npcs.setStance(n, "stand")
	flee(n, 14)
end

-- on their knees, hands up: a hostage. `auto` = they dropped by themselves out of fear.
local function down(n: Npc, by: Player?, auto: boolean?)
	if n.state == "Tied" or n.state == "Dead" or n.role == "Guard" or n.role == "Police" then
		return
	end
	local first = n.state ~= "Down"
	n.state = "Down"
	n.busy = nil
	n.unwatched = 0
	n.warned = false
	n.escapeAfter = rng:NextNumber(8, 13) * (1.25 - n.bravery * 0.5) * (if auto then 1.7 else 1)
	n.meter = 0
	n.hum:MoveTo(n.root.Position)
	n.hum.WalkSpeed = 0
	pose(n, "up")
	Npcs.setStance(n, "kneel")
	n.prompts.TiePrompt.Enabled = true
	cardPrompt(n)
	setBubble(n, 0)
	if first then
		say(n, Lines.react_("down", n.role), "scared")
		Sfx.play("boing", n.head, 0.4, 1.2)
		if not auto and Life then
			Life.witness("hostage", n, n.root.Position)
		end
	end
	local _ = by
end
Npcs.down = down

-- a hostage the crew has been ignoring gets up and runs; staff shout for help (alarm)
local function escapeHostage(n: Npc)
	if n.state ~= "Down" then
		return
	end
	pose(n, "none")
	Npcs.setStance(n, "stand")
	for _, pp in n.prompts do
		pp.Enabled = false
	end
	setBubble(n, 0)
	local staff = n.role ~= "Customer"
	say(n, Lines.react_(if staff then "escapeStaff" else "escapeCustomer", n.role), "scream")
	if staff and Npcs.mode == "Heist" then
		Npcs.onAlarm("otage échappé", n.root.Position)
	end
	if Life then
		Life.witness("flee", n, n.root.Position)
	end
	flee(n, 14)
end

-- is a crew member watching this NPC (in front of them, in sight, or very close)?
local function watchedBy(n: Npc): boolean
	local params = eyeParams()
	for _, pl in Players:GetPlayers() do
		if Npcs.isCrew(pl) then
			local char = pl.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local head = char and char:FindFirstChild("Head") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if char and root and head and hum and hum.Health > 0 then
				local to = n.root.Position - root.Position
				local d = to.Magnitude
				if d < 45 then
					local flatTo = Vector3.new(to.X, 0, to.Z)
					local look = root.CFrame.LookVector
					local facing = d < 9 or (flatTo.Magnitude > 0.1 and Vector3.new(look.X, 0, look.Z).Unit:Dot(flatTo.Unit) > 0.25)
					if facing then
						local hit = workspace:Raycast(head.Position, n.head.Position - head.Position, params)
						if not hit or hit.Instance:IsDescendantOf(char) then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function hostageTick(n: Npc, dt: number)
	if watchedBy(n) then
		n.unwatched = math.max(0, n.unwatched - dt * 2.5)
	else
		n.unwatched += dt
	end
	local p = n.unwatched / n.escapeAfter
	setBubble(n, if p > 0.06 then p else 0, ">>", RGB(255, 150, 40))
	if p > 0.6 and not n.warned then
		n.warned = true
		say(n, Lines.react_("warnEscape", n.role), "whisper")
	end
	if p >= 1 then
		escapeHostage(n)
	end
end

-- a frightened civilian: runs or drops to the floor depending on their nerve
function Npcs.scare(n: Npc, strong: boolean)
	if n.state == "Tied" or n.state == "Dead" or n.state == "Down" or n.state == "Flee" or n.role == "Guard" or n.role == "Police" then
		return
	end
	if n.role == "Customer" and n.bravery < (if strong then 0.55 else 0.4) then
		panic(n)
	else
		down(n, nil, true)
	end
end

local function tie(n: Npc, by: Player)
	if n.state ~= "HandsUp" and n.state ~= "Down" then
		return
	end
	if not Npcs.zipTie(by) then
		return
	end
	n.state = "Tied"
	n.prompts.TiePrompt.Enabled = false
	pose(n, "tied")
	Npcs.setStance(n, "kneel")
	n.hum.WalkSpeed = 0
	setBubble(n, 1, "Z", RGB(160, 160, 165))
	say(n, Lines.react_("tied", n.role), "scared")
	Sfx.play("clank", n.root, 0.6, 1.3)
	cardPrompt(n)
end

local function raise(n: Npc, why: string)
	if n.role == "Customer" then
		Npcs.scare(n, false)
		return
	end
	setBubble(n, 1, "!", RGB(255, 60, 60))
	say(n, if n.role == "Guard" then "HALTE !" else Lines.react_("alarmStaff", n.role), "angry")
	Npcs.onAlarm(why, n.root.Position)
end

-- F with a gun out: everybody in front of you (staff and customers) drops to their knees
local shoutAt: { [Player]: number } = {}
function Npcs.shout(pl: Player, look: Vector3): (boolean, string?)
	if not Npcs.isCrew(pl) then
		return false, nil
	end
	local char = pl.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = char and char:FindFirstChild("Head") :: BasePart?
	local held = char and char:FindFirstChildOfClass("Tool")
	if not char or not root or not head then
		return false, nil
	end
	local id = if held then held:GetAttribute("ItemId") else nil
	if not held or not held:GetAttribute("HeistGear") or (id ~= "pistol" and id ~= "rifle" and id ~= "sniper") then
		return false, "Sors une arme pour crier « À terre ! »"
	end
	if (shoutAt[pl] or 0) > os.clock() - 1.5 then
		return false, nil
	end
	shoutAt[pl] = os.clock()
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.1 then
		dir = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	dir = dir.Unit
	Net.event():FireAllClients("Say", char, Lines.pick({ "À TERRE ! TOUT LE MONDE À TERRE !", "TOUS À TERRE !", "À TERRE ! MAINS VISIBLES !", "PERSONNE NE BOUGE !" }), "angry")
	local params = eyeParams()
	for _, n in list do
		if n.state ~= "Dead" and n.state ~= "Tied" and n.state ~= "Down" and n.role ~= "Guard" and n.role ~= "Police" and n.model.Parent then
			local to = n.root.Position - root.Position
			local flatTo = Vector3.new(to.X, 0, to.Z)
			local d = flatTo.Magnitude
			if d < 34 and (d < 4 or flatTo.Unit:Dot(dir) > 0.55) then
				local hit = workspace:Raycast(head.Position, n.head.Position - head.Position, params)
				if not hit or hit.Instance:IsDescendantOf(char) then
					down(n, pl)
				end
			end
		end
	end
	return true, nil
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
							say(n, Lines.react_("cardGrab", n.role), "angry")
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
	if n.state == "Down" then
		hostageTick(n, dt)
		return
	end
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
				s.inst[s.prop] = s.c0 * CFrame.Angles(math.rad(165 + rng:NextNumber(-8, 8)), 0, math.rad(-12 * sign + rng:NextNumber(-6, 6)))
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
				say(n, Lines.react_("notice", n.role), "angry")
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

-- bank alarm: guards fight, customers run or drop to the floor, staff press the button then cower
function Npcs.alarm()
	for _, n in list do
		if n.state ~= "Dead" and n.state ~= "Tied" then
			if n.role == "Guard" then
				n.state = "Hostile"
				setBubble(n, 1, "!", RGB(255, 60, 60))
			elseif n.role == "Customer" then
				Npcs.scare(n, true)
			elseif n.state ~= "HandsUp" and n.state ~= "Down" then
				n.meter = 0
				setBubble(n, 1, "!", RGB(255, 60, 60))
				local who = n
				task.delay(rng:NextNumber(0.4, 1.6), function()
					if who.state == "Idle" or who.state == "HandsUp" then
						say(who, Lines.react_("alarmStaff", who.role), "scream")
						down(who, nil, true)
					end
				end)
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
		if n.state == "Idle" and Npcs.mode ~= "Off" and n.meter < 0.3 and n.busy ~= "talk" then
			i += 1
			local target = if i % 5 == 0 and typeof(home) == "CFrame" then home.Position else walk[(i - 1) % #walk + 1].Position
			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
			local ok = pcall(function()
				path:ComputeAsync(n.root.Position, target)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				for _, wp in path:GetWaypoints() do
					if n.state ~= "Idle" or n.meter > 0.3 or n.busy == "talk" then
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
				if Life and n.state == "Idle" then
						Life.tryChat(n, 18)
					end
					task.wait(rng:NextNumber(3, 7))
			end
		else
			task.wait(1)
		end
	end
end

function Npcs.combatInfo(): any
	return Combat and Combat.stats
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
	-- ambient life, witnesses, and the tactical combat brains
	Life = require(script.Parent:WaitForChild("NpcLife"))
	Combat = require(script.Parent:WaitForChild("NpcCombat"))
	Life.init(Npcs)
	Combat.init(Npcs)
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
