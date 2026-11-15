--!strict
-- The heist itself, server side: phases (Hideout -> Scout / Heist -> Results -> Hideout), the 15 min
-- clock, alarms (bank alarm -> the bank calls the police unless every staff member is tied up; C4 and
-- gunfire without a silencer are heard), the ways into the vault (hack, drill, C4 on 5 spots, level 5
-- card), deposit lockers and money bags, ropes, EMP, breakable windows, security cameras, getaway
-- vehicles from the plan, the escape zone in the hideout garage, and the payout.
-- Nothing in the plan restricts the heist: every tool works wherever it makes sense.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local Noobla = require(Heist:WaitForChild("Noobla"))
local Net = require(Heist:WaitForChild("Net"))
local Sfx = require(Heist:WaitForChild("Sfx"))
local Data = require(script.Parent:WaitForChild("Data"))
local Plan = require(script.Parent:WaitForChild("Plan"))
local Tools = require(script.Parent:WaitForChild("Tools"))
local Npcs = require(script.Parent:WaitForChild("Npcs"))
local Vehicles = require(script.Parent:WaitForChild("Vehicles"))

local Run = {}
local RGB = Color3.fromRGB
local rng = Random.new()
local S = Net.state()
local Event = Net.event()

local crew: { [Player]: boolean } = {} -- in the current heist (alive or not)
local out: { [Player]: boolean } = {} -- went down during the heist
local scouts: { [Player]: boolean } = {}
local spawned: { { model: Model, owner: number, kind: string, returned: boolean } } = {}
local pendingVehicles: { any } = {}
local hackTokens: { [Player]: { token: number, at: number } } = {}
local camMeters: { [Instance]: number } = {}
local deadCams: { [Instance]: boolean } = {}
local alarmSound: Sound? = nil
local sirenSound: Sound? = nil
local nextWave = 0
local waveNo = 0 -- 1 = pistol squad, 2+ = SWAT with M4s
local resultsPending = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function bank(): Model?
	return workspace:FindFirstChild("NooblaBank") :: Model?
end

local function hook(name: string): Instance?
	local b = bank()
	local h = b and b:FindFirstChild("Hooks")
	return h and h:FindFirstChild(name, true)
end

local function toast(pl: Player?, text: string, kind: string?)
	if pl then
		Event:FireClient(pl, "Toast", text, kind or "info")
	else
		for p in crew do
			if p.Parent then
				Event:FireClient(p, "Toast", text, kind or "info")
			end
		end
		for p in scouts do
			if p.Parent then
				Event:FireClient(p, "Toast", text, kind or "info")
			end
		end
	end
end

local function marker(name: string): BasePart?
	local b = bank()
	local m = b and b:FindFirstChild("Markers")
	return m and m:FindFirstChild(name) :: BasePart?
end

local HIDEOUT_SPOT = CFrame.new(-170, 4, -4)

------------------------------------------------------------------ bank reset (pristine copy)

local function savePristine()
	local b = bank()
	if b and not ServerStorage:FindFirstChild("PristineBank") then
		local c = b:Clone()
		c.Name = "PristineBank"
		c.Parent = ServerStorage
	end
end

local function resetBank()
	local src = ServerStorage:FindFirstChild("PristineBank")
	if not src then
		return
	end
	local b = bank()
	if b then
		b:Destroy()
	end
	local c = src:Clone()
	c.Name = "NooblaBank"
	c.Parent = workspace
	camMeters = {}
	deadCams = {}
	local fx = workspace:FindFirstChild("HeistFx")
	if fx then
		fx:ClearAllChildren()
	end
end

------------------------------------------------------------------ carrying loot

local function bagModel(kind: string): Model
	local m = Instance.new("Model")
	m.Name = "CarriedLoot"
	local p = Instance.new("Part")
	p.Name = "Bag"
	p.Size = if kind == "case" then Vector3.new(1.8, 1.3, 0.6) else Vector3.new(1.9, 2, 1.3)
	p.Color = if kind == "case" then RGB(70, 46, 34) else RGB(70, 120, 60)
	p.Material = if kind == "case" then Enum.Material.Leather else Enum.Material.Fabric
	p.TopSurface = Enum.SurfaceType.Studs
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = m
	local tag = Instance.new("Part")
	tag.Name = "Tag"
	tag.Size = Vector3.new(0.8, 0.8, 0.05)
	tag.Color = if kind == "case" then RGB(230, 180, 40) else RGB(242, 243, 243)
	tag.CanCollide = false
	tag.Massless = true
	tag.CFrame = p.CFrame * CFrame.new(0, 0, p.Size.Z / 2 + 0.03)
	local w = Instance.new("WeldConstraint")
	w.Part0 = p
	w.Part1 = tag
	w.Parent = tag
	tag.Parent = m
	m.PrimaryPart = p
	return m
end

local function clearCarry(pl: Player)
	local char = pl.Character
	if not char then
		return
	end
	local c = char:FindFirstChild("CarriedLoot")
	if c then
		c:Destroy()
	end
	char:SetAttribute("Carry", nil)
	char:SetAttribute("CarryValue", nil)
	char:SetAttribute("CarryCount", nil)
end

local function setCarry(pl: Player, kind: string, value: number, count: number)
	local char = pl.Character
	local torso = char and char:FindFirstChild("UpperTorso") :: BasePart?
	if not char or not torso then
		return
	end
	if char:GetAttribute("Carry") ~= kind then
		local old = char:FindFirstChild("CarriedLoot")
		if old then
			old:Destroy()
		end
		local m = bagModel(kind)
		local bag = m.PrimaryPart :: BasePart
		bag.CFrame = torso.CFrame * CFrame.new(0, 0.1, torso.Size.Z / 2 + bag.Size.Z / 2 + 0.05)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = bag.CFrame * (if d == bag then CFrame.new() else CFrame.new(0, 0, -bag.Size.Z / 2 - 0.03))
			end
		end
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = bag
		w.Parent = bag
		m.Parent = char
	end
	char:SetAttribute("Carry", kind)
	char:SetAttribute("CarryValue", value)
	char:SetAttribute("CarryCount", count)
end

-- a loot bag lying in the world (dropped/thrown)
local function looseBag(kind: string, value: number, count: number, cf: CFrame, vel: Vector3?): BasePart
	local m = bagModel(kind)
	local p = m.PrimaryPart :: BasePart
	p.Name = "LootBag"
	p.Parent = Sfx.folder()
	p.CFrame = cf
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = true
	p.Massless = false
	local tagPart = m:FindFirstChild("Tag") :: BasePart
	tagPart.CFrame = p.CFrame * CFrame.new(0, 0, p.Size.Z / 2 + 0.03)
	tagPart.Parent = p
	m:Destroy()
	p:SetAttribute("Kind", kind)
	p:SetAttribute("Value", value)
	p:SetAttribute("Count", count)
	CollectionService:AddTag(p, "LootBag")
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "PickPrompt"
	pp.ActionText = "Ramasser"
	pp.ObjectText = if kind == "case" then "Mallette du casier 167" else ("Sac ($" .. value .. ")")
	pp.HoldDuration = 0.2
	pp.MaxActivationDistance = 8
	pp.RequiresLineOfSight = false
	pp.Parent = p
	if vel then
		p.AssemblyLinearVelocity = vel
		p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
	end
	-- landing in a vehicle's cargo bed loads it
	local done = false
	p.Touched:Connect(function(other)
		if done or other.Name ~= "Cargo" then
			return
		end
		local veh = other.Parent
		if veh and veh:IsA("Model") and CollectionService:HasTag(veh, "HeistVehicle") then
			if Vehicles.load(veh, value, kind == "case") then
				done = true
				p:Destroy()
			end
		end
	end)
	return p
end

------------------------------------------------------------------ alarms

local function setLightsRed(on: boolean)
	local b = bank()
	local lights = b and b:FindFirstChild("Lights", true)
	if not lights then
		return
	end
	for _, l in lights:GetDescendants() do
		if l:IsA("BasePart") and l.Material == Enum.Material.Neon then
			if l:GetAttribute("Orig") == nil then
				l:SetAttribute("Orig", l.Color)
			end
			l.Color = if on then RGB(255, 40, 30) else l:GetAttribute("Orig") :: Color3
		end
	end
end

local function policeAlert(why: string)
	if S:GetAttribute("PoliceAlert") then
		return
	end
	S:SetAttribute("PoliceAlert", true)
	S:SetAttribute("PoliceCallAt", 0)
	S:SetAttribute("PoliceArriveAt", now() + Noobla.policeDelay)
	nextWave = now() + Noobla.policeDelay
	waveNo = 0
	toast(nil, "LA POLICE EST PRÉVENUE (" .. why .. ") : arrivée dans " .. Noobla.policeDelay .. " s !", "bad")
end

local function bankAlert(why: string, pos: Vector3?)
	if S:GetAttribute("Phase") ~= "Heist" then
		return
	end
	if not S:GetAttribute("BankAlert") then
		S:SetAttribute("BankAlert", true)
		S:SetAttribute("AlarmWhy", why)
		Npcs.alarm()
		local b = bank()
		local hall = b and b:FindFirstChild("03 Banking Hall", true)
		local floor = hall and hall:FindFirstChild("Floor")
		if floor then
			alarmSound = Sfx.loop("alarm", floor, 0.55, 260)
		end
		if not S:GetAttribute("PoliceAlert") then
			S:SetAttribute("PoliceCallAt", now() + Noobla.bankCallDelay)
			toast(nil, "ALARME ! La banque appelle la police dans " .. Noobla.bankCallDelay .. " s. Attache tout le personnel pour l'en empêcher !", "bad")
		end
		task.spawn(function()
			local on = false
			while S:GetAttribute("BankAlert") and S:GetAttribute("Phase") == "Heist" do
				on = not on
				setLightsRed(on)
				task.wait(0.5)
			end
			setLightsRed(false)
		end)
	end
	if pos then
		Sfx.popText(pos + Vector3.new(0, 6, 0), "ALARME !", RGB(255, 60, 60), 9)
	end
end
Run.bankAlert = bankAlert

------------------------------------------------------------------ the vault

local function openVault(how: string)
	if S:GetAttribute("VaultOpen") then
		return
	end
	S:SetAttribute("VaultOpen", true)
	S:SetAttribute("VaultHow", how)
	local vd = hook("VaultDoor") :: Model?
	if vd and how ~= "c4door" and how ~= "wall" and how ~= "roof" then
		local leaf = vd:FindFirstChild("Leaf") :: Model
		local closed = vd:GetAttribute("Closed") :: CFrame
		local ang = vd:GetAttribute("OpenAngle") :: number
		local cv = Instance.new("CFrameValue")
		cv.Value = closed
		cv.Changed:Connect(function(v)
			leaf:PivotTo(v)
		end)
		Sfx.play("door", leaf.PrimaryPart :: BasePart, 1, 1, 200)
		-- goofy: the wheel spins first, then the door creaks open with an overshoot
		local wheel = leaf:FindFirstChild("Wheel")
		task.spawn(function()
			if wheel then
				for _ = 1, 12 do
					for _, w in wheel:GetChildren() do
						if w:IsA("BasePart") then
							local hub = (leaf.PrimaryPart :: BasePart).CFrame * CFrame.new(0, 0.1, 1.95)
							w.CFrame = hub * CFrame.Angles(0, 0, math.rad(30)) * hub:ToObjectSpace(w.CFrame)
						end
					end
					task.wait(0.05)
				end
			end
			TweenService:Create(cv, TweenInfo.new(2.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = closed * CFrame.Angles(0, ang, 0) }):Play()
		end)
	end
	for _, l in CollectionService:GetTagged("Locker") do
		if l:IsDescendantOf(workspace) and not l:GetAttribute("Destroyed") and not l:GetAttribute("Opened") then
			local pp = l:FindFirstChild("LockerPrompt") :: ProximityPrompt?
			if pp then
				pp.Enabled = true
			end
		end
	end
	if S:GetAttribute("ObjectiveState") == "locked" then
		S:SetAttribute("ObjectiveState", "inVault")
	end
	toast(nil, "LE COFFRE EST OUVERT ! Casier 167 = objectif. Les autres casiers = bonus.", "good")
end

local function lockersOnWall(side: string, fn: (BasePart) -> ())
	for _, l in CollectionService:GetTagged("Locker") do
		if l:IsA("BasePart") and l:IsDescendantOf(workspace) and l:GetAttribute("Wall") == side then
			fn(l)
		end
	end
end

local function explode(spot: BasePart, target: string)
	local pos = spot.Position
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = 14
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.Parent = workspace
	Sfx.puff(pos, 16, RGB(90, 90, 90), 10)
	Sfx.popText(pos + Vector3.new(0, 5, 0), "BOOM !", RGB(255, 170, 40), 14)
	Event:FireAllClients("Fx", "shake", pos, 1.2)
	-- damage
	for _, m in workspace:GetDescendants() do
		if m:IsA("Humanoid") and m.Health > 0 then
			local root = (m.Parent :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - pos).Magnitude
				if d < 16 then
					m:TakeDamage(if Players:GetPlayerFromCharacter(m.Parent) then 70 * (1 - d / 20) else 120)
					root.AssemblyLinearVelocity = (root.Position - pos).Unit * 60 + Vector3.new(0, 40, 0)
				end
			end
		end
	end
	local how = "wall"
	if target == "Door" then
		local vd = hook("VaultDoor") :: Model?
		local leaf = vd and vd:FindFirstChild("Leaf") :: Model?
		if leaf then
			-- the door flies into the corridor, spinning, and slams onto the floor
			local start = leaf:GetPivot()
			local land = start * CFrame.new(6, 0.6, 14) * CFrame.Angles(math.rad(-90), 0, 0)
			local cv = Instance.new("CFrameValue")
			cv.Value = start
			cv.Changed:Connect(function(v)
				leaf:PivotTo(v)
			end)
			TweenService:Create(cv, TweenInfo.new(1.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = land }):Play()
		end
		how = "c4door"
	elseif target == "Roof" then
		for _, n in { "BreakRoof", "VaultHatch" } do
			local p = hook(n) or (bank() :: Model):FindFirstChild(n, true)
			if p and p:IsA("BasePart") then
				Sfx.debris(p.Position, Vector3.new(0, 1, 0), 14, p.Color, p.Material)
				p:Destroy()
			end
		end
		local hole = hook("RopeHole")
		local pp = hole and hole:FindFirstChild("RopePrompt") :: ProximityPrompt?
		if pp then
			pp.Enabled = true
		end
		how = "roof"
	else
		local panel = hook("BreakWall_" .. target)
		if panel and panel:IsA("BasePart") then
			Sfx.debris(panel.Position, (panel.Position - pos).Unit, 22, panel.Color, panel.Material)
			panel:Destroy()
		end
		-- the lockers on that wall are blown to bits
		local lost = 0
		lockersOnWall(target, function(l)
			l:SetAttribute("Destroyed", true)
			l.Color = RGB(40, 36, 34)
			l.Material = Enum.Material.CorrodedMetal
			local g = l:FindFirstChildOfClass("SurfaceGui")
			if g then
				g:Destroy()
			end
			local pp = l:FindFirstChild("LockerPrompt") :: ProximityPrompt?
			if pp then
				pp.Enabled = false
			end
			lost += 1
			if l:GetAttribute("Number") == Noobla.objective.locker then
				S:SetAttribute("ObjectiveState", "destroyed")
				toast(nil, "LE CASIER 167 A ÉTÉ PULVÉRISÉ ! L'objectif est perdu...", "bad")
			end
		end)
		Sfx.confetti(pos, 30)
		toast(nil, lost .. " casiers détruits par l'explosion.", "warn")
	end
	bankAlert("explosion", pos)
	policeAlert("explosion")
	openVault(how)
end

local function placeC4(pl: Player, spot: BasePart)
	if spot:GetAttribute("Armed") or spot:GetAttribute("Used") then
		return
	end
	if not Tools.use(pl, "C4") then
		toast(pl, "Il te faut du C4.", "warn")
		return
	end
	spot:SetAttribute("Armed", true)
	local pp = spot:FindFirstChild("C4Prompt") :: ProximityPrompt?
	if pp then
		pp.Enabled = false
	end
	local brick = Instance.new("Part")
	brick.Name = "PlantedC4"
	brick.Size = Vector3.new(1.6, 1, 0.6)
	brick.Color = RGB(214, 190, 120)
	brick.TopSurface = Enum.SurfaceType.Studs
	brick.Anchored = true
	brick.CanCollide = false
	brick.CFrame = spot.CFrame
	brick.Parent = Sfx.folder()
	local led = Instance.new("Part")
	led.Size = Vector3.new(0.3, 0.3, 0.2)
	led.Color = RGB(255, 40, 40)
	led.Material = Enum.Material.Neon
	led.Anchored = true
	led.CanCollide = false
	led.CFrame = brick.CFrame * CFrame.new(0, 0.3, -0.35)
	led.Parent = brick
	local target = spot:GetAttribute("Target") :: string
	toast(nil, "C4 POSÉ ! Éloignez-vous : " .. Noobla.c4Fuse .. " s !", "warn")
	task.spawn(function()
		local t = Noobla.c4Fuse
		while t > 0 do
			Sfx.play("beep", brick, 0.8, 1 + (Noobla.c4Fuse - t) * 0.15)
			Sfx.popText(brick.Position + Vector3.new(0, 2, 0), tostring(math.ceil(t)), RGB(255, 80, 80), 4)
			led.Transparency = 0
			task.wait(0.12)
			led.Transparency = 0.8
			local step = if t > 2 then 1 else 0.5
			task.wait(step - 0.12)
			t -= step
		end
		brick:Destroy()
		spot:SetAttribute("Used", true)
		if S:GetAttribute("Phase") == "Heist" then
			explode(spot, target)
		end
	end)
end

local drilling = false
local drillFix: ((Player) -> ())? = nil
local function startDrill(pl: Player, spot: BasePart)
	if drilling or S:GetAttribute("VaultOpen") then
		return
	end
	if not Tools.use(pl, "Drill") then
		toast(pl, "Il te faut une perceuse.", "warn")
		return
	end
	drilling = true
	local pp = spot:FindFirstChild("DrillPrompt") :: ProximityPrompt?
	if pp then
		pp.Enabled = false
	end
	-- drill rig on the door (tripod + yellow body + spinning bit)
	local rig = Instance.new("Model")
	rig.Name = "DrillRig"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2.2, 2.2, 3.4)
	body.Color = RGB(245, 205, 48)
	body.TopSurface = Enum.SurfaceType.Studs
	body.Anchored = true
	body.CFrame = spot.CFrame * CFrame.new(0, 0, -1.9)
	body.Parent = rig
	local bit = Instance.new("Part")
	bit.Name = "Bit"
	bit.Shape = Enum.PartType.Cylinder
	bit.Size = Vector3.new(1.6, 0.5, 0.5)
	bit.Color = RGB(170, 174, 180)
	bit.Material = Enum.Material.Metal
	bit.Anchored = true
	bit.CFrame = spot.CFrame * CFrame.new(0, 0, -0.1) * CFrame.Angles(0, math.pi / 2, 0)
	bit.Parent = rig
	for i = -1, 1, 2 do
		local leg = Instance.new("Part")
		leg.Size = Vector3.new(0.3, 6.5, 0.3)
		leg.Color = RGB(60, 60, 64)
		leg.Anchored = true
		leg.CFrame = body.CFrame * CFrame.new(i * 1.2, -3.2, 0.5) * CFrame.Angles(0, 0, math.rad(i * 15))
		leg.Parent = rig
	end
	rig.Parent = Sfx.folder()
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(6, 1.2)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Parent = body
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = RGB(27, 42, 53)
	bg.Parent = bb
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = RGB(245, 205, 48)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.TextScaled = true
	lbl.FontFace = Font.fromEnum(Enum.Font.Arcade)
	lbl.TextColor3 = RGB(242, 243, 243)
	lbl.Text = "PERCEUSE 0%"
	lbl.ZIndex = 2
	lbl.Parent = bg
	local fixPrompt = Instance.new("ProximityPrompt")
	fixPrompt.Name = "FixPrompt"
	fixPrompt.ActionText = "Réparer la perceuse"
	fixPrompt.ObjectText = "Perceuse"
	fixPrompt.HoldDuration = 1.5
	fixPrompt.RequiresLineOfSight = false
	fixPrompt.Enabled = false
	fixPrompt.Parent = body
	local jammed = false
	drillFix = function(p2: Player)
		if crew[p2] and jammed then
			jammed = false
			fixPrompt.Enabled = false
			Sfx.popText(body.Position + Vector3.new(0, 3, 0), "VROOOM !", RGB(245, 205, 48), 7)
		end
	end
	local loop = Sfx.loop("drill", body, 1, 260)
	bankAlert("drill", body.Position)
	toast(nil, "La perceuse tourne (" .. Noobla.drillTime .. " s). Elle peut se coincer: reste à côté !", "warn")
	task.spawn(function()
		local progress = 0
		local nextJam = rng:NextNumber(20, 35)
		while progress < Noobla.drillTime and S:GetAttribute("Phase") == "Heist" and not S:GetAttribute("VaultOpen") do
			task.wait(0.25)
			if not jammed then
				progress += 0.25
				bit.CFrame = bit.CFrame * CFrame.Angles(math.rad(70), 0, 0)
				body.CFrame = spot.CFrame * CFrame.new(rng:NextNumber(-0.05, 0.05), rng:NextNumber(-0.05, 0.05), -1.9)
				if progress >= nextJam then
					jammed = true
					nextJam = progress + rng:NextNumber(20, 35)
					fixPrompt.Enabled = true
					loop.Playing = false
					Sfx.play("clank", body, 1, 0.8)
					Sfx.popText(body.Position + Vector3.new(0, 3, 0), "CRRRK... COINCÉE !", RGB(255, 80, 80), 8)
					toast(nil, "La perceuse est coincée ! Va la réparer.", "warn")
				end
			else
				loop.Playing = false
			end
			if not jammed and not loop.Playing then
				loop.Playing = true
			end
			fill.Size = UDim2.fromScale(progress / Noobla.drillTime, 1)
			lbl.Text = (if jammed then "COINCÉE ! " else "PERCEUSE ") .. math.floor(progress / Noobla.drillTime * 100) .. "%"
		end
		loop:Destroy()
		drilling = false
		drillFix = nil
		if progress >= Noobla.drillTime then
			Sfx.puff(body.Position, 8, RGB(240, 240, 240), 4)
			openVault("drill")
		end
	end)
end

------------------------------------------------------------------ lockers

local function lockerLoot(): (number, string?)
	local r = rng:NextNumber()
	if r < 0.06 then
		return 5, "un canard en plastique"
	elseif r < 0.1 then
		return 4500, "des dents en or !"
	elseif r < 0.14 then
		return 0, "rien du tout..."
	end
	return rng:NextInteger(Noobla.lockerCash[1], Noobla.lockerCash[2]), nil
end

local function openLocker(pl: Player, l: BasePart)
	if l:GetAttribute("Opened") or l:GetAttribute("Destroyed") or not S:GetAttribute("VaultOpen") then
		return
	end
	local char = pl.Character
	if not char then
		return
	end
	local num = l:GetAttribute("Number")
	local carry = char:GetAttribute("Carry")
	if num == Noobla.objective.locker then
		if carry then
			toast(pl, "Lâche d'abord ton sac (touche G) pour prendre la mallette du 167.", "warn")
			return
		end
	elseif carry == "case" then
		toast(pl, "Tu portes la mallette ! Charge-la d'abord dans un véhicule.", "warn")
		return
	elseif carry == "bag" and ((char:GetAttribute("CarryCount") :: number?) or 0) >= Noobla.bagCapacity then
		toast(pl, "Sac plein ! Charge-le dans un véhicule ou lance-le (G).", "warn")
		return
	end
	l:SetAttribute("Opened", true)
	local pp = l:FindFirstChild("LockerPrompt") :: ProximityPrompt?
	if pp then
		pp.Enabled = false
	end
	-- goofy: the little door flaps open
	local g = l:FindFirstChildOfClass("SurfaceGui")
	if g then
		local inner = g:FindFirstChildOfClass("Frame")
		if inner then
			inner.BackgroundColor3 = RGB(30, 30, 34)
		end
	end
	local flap = Instance.new("Part")
	flap.Size = Vector3.new(2.7, 2.7, 0.15)
	flap.Color = RGB(200, 204, 212)
	flap.Material = Enum.Material.Metal
	flap.Anchored = true
	flap.CanCollide = false
	local hinge = l.CFrame * CFrame.new(-1.35, 0, -0.42)
	flap.CFrame = hinge * CFrame.new(1.35, 0, 0)
	flap.Parent = Sfx.folder()
	local cv = Instance.new("CFrameValue")
	cv.Value = hinge
	cv.Changed:Connect(function(v)
		flap.CFrame = v * CFrame.new(1.35, 0, 0)
	end)
	TweenService:Create(cv, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Value = hinge * CFrame.Angles(0, math.rad(110), 0) }):Play()
	Sfx.play("clank", l, 0.6, 1.2 + rng:NextNumber() * 0.3)
	S:SetAttribute("LockersOpened", ((S:GetAttribute("LockersOpened") :: number?) or 0) + 1)
	if num == Noobla.objective.locker then
		setCarry(pl, "case", 0, 1)
		S:SetAttribute("ObjectiveState", "carried")
		Sfx.popText(l.Position + Vector3.new(0, 2, 0), "LA MALLETTE !", RGB(245, 205, 48), 9)
		toast(nil, pl.DisplayName .. " a la mallette du casier 167 ! Ramenez-la à la planque.", "good")
		return
	end
	local value, joke = lockerLoot()
	local have = if carry == "bag" then ((char:GetAttribute("CarryValue") :: number?) or 0) else 0
	local count = if carry == "bag" then ((char:GetAttribute("CarryCount") :: number?) or 0) else 0
	setCarry(pl, "bag", have + value, count + 1)
	Sfx.confetti(l.Position, 6)
	Sfx.popText(l.Position + Vector3.new(0, 2, 0), if joke then string.upper(joke) else ("+$" .. value), if joke then RGB(255, 160, 220) else RGB(120, 255, 140), 6)
	Sfx.play("cash", l, 0.5, 1 + rng:NextNumber() * 0.2)
end

------------------------------------------------------------------ ropes

local function climb(pl: Player, from: CFrame, to: CFrame, rope: BasePart)
	local char = pl.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or char:GetAttribute("Climbing") then
		return
	end
	char:SetAttribute("Climbing", true)
	root.Anchored = true
	local start = CFrame.new(from.Position + Vector3.new(0, 3, 0)) * (root.CFrame - root.Position)
	root.CFrame = start
	Sfx.play("rope", root, 0.8)
	-- wobbly climb: a few hops up the rope
	local steps = 6
	for i = 1, steps do
		local p = start.Position:Lerp(to.Position + Vector3.new(0, 3, 0), i / steps)
		local t = TweenService:Create(root, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(p) * CFrame.Angles(0, select(2, start:ToOrientation()), math.rad(if i % 2 == 0 then 8 else -8)) })
		t:Play()
		t.Completed:Wait()
	end
	root.CFrame = CFrame.new(to.Position + Vector3.new(0, 3, 0))
	root.Anchored = false
	char:SetAttribute("Climbing", nil)
	local _ = rope
end

local function ropeVisual(spot: BasePart)
	if spot:FindFirstChild("RopeLine") then
		return
	end
	local top = spot:GetAttribute("Top") :: CFrame
	local a, b = spot.Position, top.Position
	local hi = if a.Y > b.Y then a else b
	local lo = if a.Y > b.Y then b else a
	local line = Instance.new("Part")
	line.Name = "RopeLine"
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.Color = RGB(160, 110, 60)
	line.Material = Enum.Material.Fabric
	local len = (hi - lo).Magnitude
	line.Size = Vector3.new(0.3, 0.3, len)
	line.CFrame = CFrame.lookAt((hi + lo) / 2, hi)
	line.Parent = spot
	local hookPart = Instance.new("Part")
	hookPart.Anchored = true
	hookPart.CanCollide = false
	hookPart.Size = Vector3.new(0.8, 0.8, 0.8)
	hookPart.Color = RGB(170, 174, 180)
	hookPart.Material = Enum.Material.Metal
	hookPart.Position = hi
	hookPart.Parent = spot
end

-- RopePrompt goes base -> Top (ground -> roof, or roof -> vault); BackPrompt goes Top -> base
local function useRope(pl: Player, spot: BasePart, back: boolean)
	if not spot:GetAttribute("Installed") then
		if not Tools.use(pl, "Rope") then
			toast(pl, "Il te faut une corde de rappel.", "warn")
			return
		end
		spot:SetAttribute("Installed", true)
		ropeVisual(spot)
		local back = spot:FindFirstChild("BackPrompt", true) :: ProximityPrompt?
		if back then
			back.Enabled = true
		end
	end
	local top = spot:GetAttribute("Top") :: CFrame
	local base = spot.CFrame
	if back then
		climb(pl, top, base, spot)
	else
		climb(pl, base, top, spot)
	end
end

-- second prompt at the other end of each rope (enabled once the rope is installed)
local function addBackPrompts()
	for _, spot in CollectionService:GetTagged("RopeSpot") do
		if spot:IsA("BasePart") and spot:IsDescendantOf(workspace) and not spot:FindFirstChild("BackEnd") then
			local top = spot:GetAttribute("Top") :: CFrame
			local e = Instance.new("Part")
			e.Name = "BackEnd"
			e.Anchored = true
			e.CanCollide = false
			e.CanQuery = false
			e.Transparency = 1
			e.Size = Vector3.new(2, 2, 2)
			e.CFrame = top
			e.Parent = spot
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "BackPrompt"
			pp.ActionText = if spot:GetAttribute("Mode") == "Hole" then "Remonter (corde)" else "Redescendre (corde)"
			pp.ObjectText = "Corde"
			pp.HoldDuration = 0.5
			pp.MaxActivationDistance = 8
			pp.RequiresLineOfSight = false
			pp.Enabled = spot:GetAttribute("Installed") == true
			pp.Parent = e
		end
	end
end

------------------------------------------------------------------ windows, cameras, EMP

local function breakGlass(g: BasePart, by: Player?)
	if g:GetAttribute("Broken") then
		return
	end
	g:SetAttribute("Broken", true)
	Sfx.play("glass", g.Position, 1, 1, 200)
	Sfx.debris(g.Position, Vector3.new(0, 1, 0), 10, RGB(200, 225, 235), Enum.Material.Glass)
	g.Transparency = 1
	g.CanCollide = false
	g.CanQuery = false
	local pp = g:FindFirstChild("GlassPrompt")
	if pp then
		pp:Destroy()
	end
	-- the noise makes staff nearby suspicious
	for _, n in Npcs.list do
		if n.state == "Idle" and (n.root.Position - g.Position).Magnitude < 50 then
			n.meter = math.max(n.meter, 0.65)
		end
	end
	local _ = by
end

local function killCamera(cam: Instance)
	if deadCams[cam] then
		return
	end
	deadCams[cam] = true
	local led = cam:FindFirstChild("RecLed", true) :: BasePart?
	if led then
		led.Color = RGB(30, 30, 30)
	end
	local body = (cam :: Model).PrimaryPart
	if body then
		Sfx.play("zap", body, 0.7, 1.3)
		Sfx.puff(body.Position, 4, RGB(60, 60, 60), 1.5)
		body.CFrame = body.CFrame * CFrame.Angles(math.rad(-35), math.rad(20), 0)
	end
end

local function useEmp(pl: Player)
	if S:GetAttribute("Phase") ~= "Heist" then
		return
	end
	if not Tools.use(pl, "EMP") then
		return
	end
	local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	S:SetAttribute("EmpUntil", now() + Noobla.empTime)
	Sfx.play("zap", root, 1, 0.8, 300)
	Sfx.popText(root.Position + Vector3.new(0, 6, 0), "BZZZT !", RGB(120, 220, 255), 10)
	-- blue shockwave bubble
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.ForceField
	ball.Color = RGB(80, 180, 255)
	ball.Size = Vector3.new(2, 2, 2)
	ball.Position = root.Position
	ball.Parent = Sfx.folder()
	local t = TweenService:Create(ball, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(220, 220, 220), Transparency = 1 })
	t:Play()
	t.Completed:Once(function()
		ball:Destroy()
	end)
	toast(nil, "IEM ! Caméras et téléphones coupés pendant " .. Noobla.empTime .. " s.", "good")
end

------------------------------------------------------------------ throwing / loading loot

function Run.throw(pl: Player, dir: any)
	local char = pl.Character
	local kind = char and char:GetAttribute("Carry")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not kind or not root then
		return
	end
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.1 or dir ~= dir then
		dir = root.CFrame.LookVector
	end
	local d = (dir :: Vector3).Unit
	local value = (char:GetAttribute("CarryValue") :: number?) or 0
	local count = (char:GetAttribute("CarryCount") :: number?) or 0
	clearCarry(pl)
	looseBag(kind :: string, value, count, CFrame.new(root.Position + d * 2.5 + Vector3.new(0, 1.5, 0)),
		Vector3.new(d.X, 0, d.Z).Unit * 38 + Vector3.new(0, 26 + math.max(0, d.Y) * 25, 0))
	Sfx.play("whoosh", root, 0.8, 1.2)
end

local function pickUp(pl: Player, bag: BasePart)
	local char = pl.Character
	if not char or char:GetAttribute("Carry") then
		toast(pl, "Tu portes déjà quelque chose.", "warn")
		return
	end
	local kind = bag:GetAttribute("Kind") :: string
	setCarry(pl, kind, (bag:GetAttribute("Value") :: number?) or 0, (bag:GetAttribute("Count") :: number?) or 1)
	if kind == "case" then
		S:SetAttribute("ObjectiveState", "carried")
	end
	bag:Destroy()
	Sfx.play("thud", char:FindFirstChild("HumanoidRootPart") :: BasePart, 0.6, 1.3)
end

local function loadInto(pl: Player, veh: Model)
	local char = pl.Character
	local kind = char and char:GetAttribute("Carry")
	if not kind then
		toast(pl, "Tu ne portes rien.", "warn")
		return
	end
	if Vehicles.load(veh, (char:GetAttribute("CarryValue") :: number?) or 0, kind == "case") then
		if kind == "case" then
			S:SetAttribute("ObjectiveState", "loaded")
		end
		clearCarry(pl)
	else
		toast(pl, "Ce véhicule est plein !", "warn")
	end
end

------------------------------------------------------------------ scouting clues

local CLUE_UI = {
	teller = { "Écouter les guichetières", 3 },
	dumpster = { "Fouiller la benne", 2.5 },
	notice = { "Lire l'avis de travaux", 1.5 },
	manager = { "Écouter le directeur", 3 },
	truck = { "Observer le fourgon blindé", 2 },
	locker167 = { "Écouter le client", 2.5 },
}
local CLUE_KEY = { teller = "hack", dumpster = "drill", notice = "c4", manager = "card", truck = "refill", locker167 = "locker167" }

local function addCluePrompts()
	for _, m in CollectionService:GetTagged("HeistMarker") do
		local clue = m:GetAttribute("Clue")
		if clue and m:IsDescendantOf(workspace) and CLUE_UI[clue] and not m:FindFirstChild("CluePrompt") then
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "CluePrompt"
			pp.ActionText = CLUE_UI[clue][1]
			pp.ObjectText = "Repérage"
			pp.HoldDuration = CLUE_UI[clue][2]
			pp.MaxActivationDistance = 10
			pp.RequiresLineOfSight = false
			pp.Enabled = clue ~= "manager"
			pp.Parent = m
			m.Position += Vector3.new(0, 3, 0)
		end
	end
end

local function removeCluePrompts()
	for _, m in CollectionService:GetTagged("HeistMarker") do
		local pp = m:FindFirstChild("CluePrompt")
		if pp then
			pp:Destroy()
			m.Position -= Vector3.new(0, 3, 0)
		end
	end
end

local function onClue(pl: Player, m: BasePart)
	local clue = m:GetAttribute("Clue") :: string
	local key = CLUE_KEY[clue]
	if not key then
		return
	end
	if Data.learn(pl, key) then
		Event:FireClient(pl, "Intel", key)
		Sfx.play("pop", m.Position, 0.7, 1.2)
	else
		toast(pl, "Tu sais déjà ça : " .. Noobla.intel[key].title, "info")
	end
end

------------------------------------------------------------------ phases

local function teleport(pl: Player, cf: CFrame)
	local char = pl.Character
	if char then
		char:PivotTo(cf)
	end
end

local function respawnToHideout(pl: Player)
	if not pl.Parent then
		return
	end
	local conn: RBXScriptConnection
	conn = pl.CharacterAdded:Connect(function(char)
		conn:Disconnect()
		task.wait(0.2)
		char:PivotTo(HIDEOUT_SPOT)
	end)
	pl:LoadCharacter()
end

function Run.startScout(pl: Player): (boolean, string?)
	local phase = S:GetAttribute("Phase")
	if phase == "Heist" or phase == "Results" or phase == "Starting" then
		return false, "Un braquage est en cours."
	end
	if phase ~= "Scout" then
		resetBank()
		S:SetAttribute("Phase", "Scout")
		Npcs.spawnBank("Scout")
		addCluePrompts()
	end
	scouts[pl] = true
	pl:SetAttribute("Scouting", true)
	Tools.strip(pl)
	local start = marker("HeistStart")
	if start then
		teleport(pl, start.CFrame + Vector3.new(rng:NextNumber(-3, 3), 3, rng:NextNumber(-3, 3)))
	end
	toast(pl, "REPÉRAGE : promène-toi comme un client. Écoute, observe, fouille (E). Ne traîne pas dans les zones du personnel.", "info")
	return true, nil
end

function Run.leaveScout(pl: Player)
	if not scouts[pl] then
		return
	end
	scouts[pl] = nil
	pl:SetAttribute("Scouting", nil)
	respawnToHideout(pl)
	if next(scouts) == nil and S:GetAttribute("Phase") == "Scout" then
		removeCluePrompts()
		Npcs.clear()
		S:SetAttribute("Phase", "Hideout")
	end
end

function Run.startHeist(pl: Player): (boolean, string?)
	local phase = S:GetAttribute("Phase")
	if phase == "Heist" or phase == "Results" or phase == "Starting" then
		return false, "Un braquage est déjà en cours."
	end
	S:SetAttribute("Phase", "Starting") -- setup yields (NPCs load): the tick must not run on a half-built heist
	-- anyone scouting comes back first
	for p in scouts do
		scouts[p] = nil
		p:SetAttribute("Scouting", nil)
	end
	removeCluePrompts()
	resetBank()
	addBackPrompts()
	table.clear(crew)
	table.clear(out)
	table.clear(spawned)
	table.clear(hackTokens)
	Vehicles.clear()
	local t0 = now()
	for _, attr in { "BankAlert", "PoliceAlert", "VaultOpen" } do
		S:SetAttribute(attr, false)
	end
	S:SetAttribute("PoliceCallAt", 0)
	S:SetAttribute("PoliceArriveAt", 0)
	S:SetAttribute("EmpUntil", 0)
	S:SetAttribute("VaultHow", "")
	S:SetAttribute("Banked", 0)
	S:SetAttribute("LockersOpened", 0)
	S:SetAttribute("ObjectiveState", "locked")
	S:SetAttribute("StartTime", t0)
	S:SetAttribute("EndTime", t0 + Noobla.timeLimit)
	S:SetAttribute("Method", Plan.get().method)
	Npcs.spawnBank("Heist")
	local start = marker("HeistStart")
	local i = 0
	for _, p in Players:GetPlayers() do
		crew[p] = true
		p:SetAttribute("InHeist", true)
		clearCarry(p)
		Tools.equip(p, Plan.loadout(p))
		if start then
			teleport(p, start.CFrame * CFrame.new((i % 4) * 3 - 4.5, 3, math.floor(i / 4) * 3))
		end
		i += 1
	end
	-- vehicles from the plan, in arrival order
	pendingVehicles = {}
	for _, v in Plan.get().vehicles do
		table.insert(pendingVehicles, table.clone(v))
	end
	table.sort(pendingVehicles, function(a, b)
		return a.t < b.t
	end)
	-- the clock starts now that everything is in place
	t0 = now()
	S:SetAttribute("StartTime", t0)
	S:SetAttribute("EndTime", t0 + Noobla.timeLimit)
	S:SetAttribute("Phase", "Heist")
	Event:FireAllClients("HeistStarted", Plan.get())
	toast(nil, "C'EST PARTI ! 15:00 au chrono. Objectif : le casier 167.", "good")
	local _ = pl
	return true, nil
end

local function endHeist(reason: string)
	if S:GetAttribute("Phase") ~= "Heist" or resultsPending then
		return
	end
	resultsPending = true
	local nCrew, nOut = 0, 0
	for _ in crew do
		nCrew += 1
	end
	for _ in out do
		nOut += 1
	end
	print("[Heist] end:", reason, "crew", nCrew, "out", nOut)
	S:SetAttribute("Phase", "Results")
	S:SetAttribute("BankAlert", false)
	if alarmSound then
		alarmSound:Destroy()
		alarmSound = nil
	end
	if sirenSound then
		sirenSound:Destroy()
		sirenSound = nil
	end
	local banked = (S:GetAttribute("Banked") :: number?) or 0
	local objective = S:GetAttribute("ObjectiveState") == "secured"
	local total = banked + (if objective then Noobla.objective.bonus else 0)
	local members = {}
	for p in crew do
		if p.Parent then
			table.insert(members, p)
		end
	end
	local share = if #members > 0 then math.floor(total / #members) else 0
	-- vehicles that never made it back are seized by the police
	local lost: { [number]: { string } } = {}
	for _, v in spawned do
		if not v.returned then
			local owner = Players:GetPlayerByUserId(v.owner)
			if owner then
				Data.take(owner, v.kind, 1)
				lost[v.owner] = lost[v.owner] or {}
				table.insert(lost[v.owner], v.kind)
			end
		end
	end
	for _, p in members do
		Data.addCash(p, share)
		local prof = Data.get(p)
		if prof then
			prof.heists += 1
		end
		Event:FireClient(p, "Results", {
			reason = reason,
			banked = banked,
			objective = objective,
			objectiveState = S:GetAttribute("ObjectiveState"),
			bonus = if objective then Noobla.objective.bonus else 0,
			total = total,
			share = share,
			crew = #members,
			lockers = S:GetAttribute("LockersOpened"),
			alarm = S:GetAttribute("AlarmWhy") or "",
			police = S:GetAttribute("PoliceAlert"),
			lostVehicles = lost[p.UserId] or {},
			time = now() - ((S:GetAttribute("StartTime") :: number?) or now()),
		})
		task.spawn(Data.save, p)
	end
	task.delay(9, function()
		Npcs.clear()
		Vehicles.clear()
		resetBank()
		for p in crew do
			p:SetAttribute("InHeist", nil)
			if p.Parent then
				clearCarry(p)
				Tools.strip(p)
				respawnToHideout(p)
			end
		end
		table.clear(crew)
		table.clear(out)
		S:SetAttribute("Phase", "Hideout")
		S:SetAttribute("PoliceAlert", false)
		S:SetAttribute("AlarmWhy", nil)
		resultsPending = false
		Plan.broadcast()
	end)
end
Run.endHeist = endHeist

function Run.abandon(pl: Player)
	if crew[pl] and S:GetAttribute("Phase") == "Heist" then
		toast(nil, pl.DisplayName .. " a sonné la retraite !", "warn")
		endHeist("abandon")
	end
end

------------------------------------------------------------------ hack mini-game

function Run.hackResult(pl: Player, token: any, ok: any)
	local h = hackTokens[pl]
	if not h or h.token ~= token then
		return
	end
	hackTokens[pl] = nil
	local kp = hook("VaultKeypad") :: BasePart?
	if ok == true and os.clock() - h.at < 60 and S:GetAttribute("Phase") == "Heist" then
		local led = hook("KeypadLed") :: BasePart?
		if led then
			led.Color = RGB(60, 255, 120)
		end
		if kp then
			Sfx.play("granted", kp, 0.8)
			Sfx.popText(kp.Position + Vector3.new(0, 2, 0), "ACCÈS OK !", RGB(120, 255, 140), 7)
		end
		openVault("hack")
	else
		if kp then
			Sfx.play("key", kp, 0.8, 0.6)
			Sfx.popText(kp.Position + Vector3.new(0, 2, 0), "ERREUR", RGB(255, 80, 80), 6)
		end
		toast(pl, "Piratage raté : la clé a grillé. Il t'en faut une autre.", "warn")
	end
end

------------------------------------------------------------------ prompts

local function onPrompt(pp: ProximityPrompt, pl: Player)
	local phase = S:GetAttribute("Phase")
	local name = pp.Name
	local parent = pp.Parent
	if name == "CluePrompt" then
		if phase == "Scout" and scouts[pl] and parent and parent:IsA("BasePart") then
			onClue(pl, parent)
		end
		return
	end
	if phase ~= "Heist" or not crew[pl] or out[pl] then
		return
	end
	if name == "HackPrompt" then
		if S:GetAttribute("VaultOpen") then
			return
		end
		if not Tools.use(pl, "HackKey") then
			toast(pl, "Il te faut une clé de piratage Nv.1.", "warn")
			return
		end
		local token = rng:NextInteger(1, 1e9)
		hackTokens[pl] = { token = token, at = os.clock() }
		Event:FireClient(pl, "HackStart", token, 5)
	elseif name == "ReaderPrompt" then
		if S:GetAttribute("VaultOpen") then
			return
		end
		if not Tools.find(pl, "AccessCard") then
			toast(pl, "Il faut la carte d'accès Nv.5 (le directeur l'a sur lui).", "warn")
			return
		end
		local led = hook("CardLed") :: BasePart?
		if led then
			led.Color = RGB(60, 255, 120)
		end
		if parent and parent:IsA("BasePart") then
			Sfx.play("granted", parent, 0.8)
			Sfx.popText(parent.Position + Vector3.new(0, 2, 0), "BIP ! NV.5 OK", RGB(120, 255, 140), 7)
		end
		openVault("card")
	elseif name == "DrillPrompt" then
		if parent and parent:IsA("BasePart") then
			startDrill(pl, parent)
		end
	elseif name == "FixPrompt" then
		if drillFix then
			drillFix(pl)
		end
	elseif name == "C4Prompt" then
		if parent and parent:IsA("BasePart") then
			placeC4(pl, parent)
		end
	elseif name == "LockerPrompt" then
		if parent and parent:IsA("BasePart") then
			openLocker(pl, parent)
		end
	elseif name == "RopePrompt" then
		if parent and parent:IsA("BasePart") then
			useRope(pl, parent, false)
		end
	elseif name == "BackPrompt" then
		local spot = parent and parent.Parent
		if spot and spot:IsA("BasePart") then
			useRope(pl, spot, true)
		end
	elseif name == "GlassPrompt" then
		if parent and parent:IsA("BasePart") then
			breakGlass(parent, pl)
		end
	elseif name == "PickPrompt" then
		if parent and parent:IsA("BasePart") then
			pickUp(pl, parent)
		end
	elseif name == "LoadPrompt" then
		local veh = parent and parent.Parent
		if veh and veh:IsA("Model") then
			loadInto(pl, veh)
		end
	end
end

------------------------------------------------------------------ main loop

local function inZone(pos: Vector3, zone: BasePart): boolean
	local lp = zone.CFrame:PointToObjectSpace(pos)
	local s = zone.Size / 2
	return math.abs(lp.X) <= s.X and math.abs(lp.Y) <= s.Y and math.abs(lp.Z) <= s.Z
end

local function escapeZone(): BasePart?
	for _, z in CollectionService:GetTagged("EscapeZone") do
		if z:IsA("BasePart") and z:IsDescendantOf(workspace) then
			return z
		end
	end
	return nil
end

local function bankValue(v: number, objective: boolean, where: Vector3)
	S:SetAttribute("Banked", ((S:GetAttribute("Banked") :: number?) or 0) + v)
	if objective then
		S:SetAttribute("ObjectiveState", "secured")
		toast(nil, "LA MALLETTE DU CASIER 167 EST À LA PLANQUE ! +$" .. Noobla.objective.bonus, "good")
	end
	Sfx.popText(where + Vector3.new(0, 6, 0), "+$" .. v, RGB(120, 255, 140), 10)
	Sfx.confetti(where + Vector3.new(0, 3, 0), 20)
	Sfx.play("cash", where, 1)
end

local function camerasTick(dt: number)
	local empOn = ((S:GetAttribute("EmpUntil") :: number?) or 0) > now()
	for _, cam in CollectionService:GetTagged("SecurityCamera") do
		if cam:IsA("Model") and cam:IsDescendantOf(workspace) and not deadCams[cam] then
			local body = cam.PrimaryPart
			local led = cam:FindFirstChild("RecLed", true) :: BasePart?
			if body then
				if empOn then
					if led then
						led.Color = RGB(40, 40, 40)
					end
					camMeters[cam] = 0
				else
					if led then
						led.Color = RGB(255, 40, 40)
					end
					local m = camMeters[cam] or 0
					local seen = false
					for p in crew do
						if not out[p] then
							local s = Npcs.suspicion(p, "Camera")
							local head = p.Character and p.Character:FindFirstChild("Head") :: BasePart?
							if s > 0 and head then
								local to = head.Position - body.Position
								if to.Magnitude < 75 and body.CFrame.LookVector:Dot(to.Unit) > 0.55 then
									local params = RaycastParams.new()
									params.FilterType = Enum.RaycastFilterType.Exclude
									params.FilterDescendantsInstances = { cam, Sfx.folder() }
									local hit = workspace:Raycast(body.Position, to * 1.02, params)
									if hit and hit.Instance:IsDescendantOf(p.Character :: Model) then
										seen = true
										m += dt * s * 0.6
									end
								end
							end
						end
					end
					if not seen then
						m = math.max(0, m - dt * 0.3)
					end
					camMeters[cam] = m
					if m >= 1 and not S:GetAttribute("BankAlert") then
						Sfx.popText(body.Position + Vector3.new(0, 2, 0), "CLIC ! REPÉRÉ", RGB(255, 60, 60), 7)
						bankAlert("camera", body.Position)
					end
				end
			end
		end
	end
end

local acc = 0
local function tick(dt: number)
	acc += dt
	if acc < 0.25 then
		return
	end
	local step = acc
	acc = 0
	local phase = S:GetAttribute("Phase")
	if phase == "Scout" then
		-- the manager clue only works while he's on the phone in the hall
		local mclue = marker("ClueManager")
		local pp = mclue and mclue:FindFirstChild("CluePrompt") :: ProximityPrompt?
		if pp then
			local on = false
			for _, n in Npcs.list do
				if n.role == "Manager" and n.model:GetAttribute("OnPhone") and (n.root.Position - (mclue :: BasePart).Position).Magnitude < 14 then
					on = true
				end
			end
			pp.Enabled = on
		end
		return
	end
	if phase ~= "Heist" then
		return
	end
	local t = now()
	-- vehicles from the plan
	local startT = (S:GetAttribute("StartTime") :: number?) or t
	while #pendingVehicles > 0 and t - startT >= pendingVehicles[1].t do
		local v = table.remove(pendingVehicles, 1)
		local owner = Players:GetPlayerByUserId(v.by)
		if owner and Data.count(owner, v.kind) > 0 then
			local b = bank()
			local center = if b then (b:GetAttribute("Root") :: CFrame).Position else Vector3.zero
			local away = (Vector3.new(v.x, 0, v.z) - Vector3.new(center.X, 0, center.Z))
			local m = Vehicles.spawn(v.kind, Vector3.new(v.x, 0, v.z), if away.Magnitude > 1 then away.Unit else nil)
			if m then
				m:SetAttribute("Owner", v.by)
				table.insert(spawned, { model = m, owner = v.by, kind = v.kind, returned = false })
				toast(nil, "Le " .. Vehicles.SPECS[v.kind].name .. " de " .. v.byName .. " est arrivé !", "good")
			end
		end
	end
	camerasTick(step)
	-- the bank's call to the police
	local callAt = (S:GetAttribute("PoliceCallAt") :: number?) or 0
	if callAt > 0 and not S:GetAttribute("PoliceAlert") then
		if Npcs.staffNeutralized() then
			S:SetAttribute("PoliceCallAt", 0)
			toast(nil, "Tout le personnel est neutralisé : personne n'a pu appeler la police !", "good")
		elseif ((S:GetAttribute("EmpUntil") :: number?) or 0) > t then
			S:SetAttribute("PoliceCallAt", callAt + step) -- lines are dead: the call waits
		elseif t >= callAt then
			policeAlert("appel de la banque")
		end
	end
	-- police waves
	if S:GetAttribute("PoliceAlert") and t >= nextWave then
		nextWave = t + 35
		if Npcs.alive("Police") < 10 then
			waveNo += 1
			if waveNo == 1 then
				Npcs.spawnPolice(4, "Police")
				toast(nil, "LA POLICE DÉBARQUE ! (agents armés de pistolets)", "bad")
			else
				Npcs.spawnPolice(math.min(2 + waveNo, 5), "Swat")
				toast(nil, "RENFORTS : LE SWAT ARRIVE ! (fusils M4, gilets lourds)", "bad")
			end
			local st = marker("PoliceStage")
			if st and not sirenSound then
				sirenSound = Sfx.loop("siren", st, 0.6, 400)
			end
		end
	end
	-- escape zone: vehicles and people who reach the hideout garage
	local zone = escapeZone()
	if zone then
		for _, v in spawned do
			local chassis = v.model.Parent and v.model.PrimaryPart
			if not v.returned and chassis and inZone(chassis.Position, zone) then
				v.returned = true
				local value = (v.model:GetAttribute("Value") :: number?) or 0
				local obj = v.model:GetAttribute("Objective") == true
				if value > 0 or obj then
					bankValue(value, obj, chassis.Position)
				end
				v.model:SetAttribute("Value", 0)
				v.model:SetAttribute("Objective", false)
				Sfx.play("horn", chassis, 1, 1.15)
			end
		end
		for p in crew do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and not out[p] and char:GetAttribute("Carry") and inZone(root.Position, zone) then
				local kind = char:GetAttribute("Carry")
				bankValue((char:GetAttribute("CarryValue") :: number?) or 0, kind == "case", root.Position)
				clearCarry(p)
			end
		end
	end
	-- end conditions
	local alive, home = 0, 0
	for p in crew do
		if p.Parent and not out[p] then
			alive += 1
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if zone and root and inZone(root.Position, zone) then
				home += 1
			end
		end
	end
	if alive == 0 then
		endHeist("busted")
	elseif t >= ((S:GetAttribute("EndTime") :: number?) or math.huge) then
		endHeist("time")
	elseif home == alive and t - startT > 20 and (((S:GetAttribute("Banked") :: number?) or 0) > 0 or S:GetAttribute("ObjectiveState") == "secured") then
		endHeist("escaped")
	end
end

Run.trigger = onPrompt

function Run.isCrew(p: Player): boolean
	return (crew[p] == true and not out[p]) or scouts[p] == true
end

function Run.init()
	S:SetAttribute("Phase", "Hideout")
	savePristine()
	Npcs.isCrew = Run.isCrew
	Npcs.onAlarm = function(why: string, pos: Vector3)
		bankAlert(why, pos)
	end
	Npcs.onCard = function(p: Player)
		Tools.give(p, "AccessCard", 1)
		toast(p, "Tu as la carte d'accès Nv.5 ! Badge-la au lecteur à gauche de la porte du coffre.", "good")
	end
	Npcs.zipTie = function(p: Player): boolean
		if Tools.use(p, "ZipTies") then
			return true
		end
		toast(p, "Plus de zip ties !", "warn")
		return false
	end
	ProximityPromptService.PromptTriggered:Connect(function(pp, pl)
		local ok, err = pcall(onPrompt, pp, pl)
		if not ok then
			warn("[Heist] prompt", pp.Name, err)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(tick, dt)
		if not ok then
			warn("[Heist] tick", err)
		end
	end)
	-- windows get a "break" prompt during heists; tools activate (EMP)
	S:GetAttributeChangedSignal("Phase"):Connect(function()
		if S:GetAttribute("Phase") == "Heist" then
			for _, g in CollectionService:GetTagged("BreakableGlass") do
				if g:IsA("BasePart") and g:IsDescendantOf(workspace) and not g:FindFirstChild("GlassPrompt") then
					local pp = Instance.new("ProximityPrompt")
					pp.Name = "GlassPrompt"
					pp.ActionText = "Briser la vitre"
					pp.ObjectText = "Fenêtre"
					pp.HoldDuration = 0.6
					pp.MaxActivationDistance = 8
					pp.RequiresLineOfSight = false
					pp.Parent = g
				end
			end
		end
	end)
	-- unsuppressed gunfire is heard; bullets break windows and cameras (hook fired by WeaponServer)
	local shot = ServerStorage:FindFirstChild("HeistShot") or Instance.new("BindableEvent")
	shot.Name = "HeistShot"
	shot.Parent = ServerStorage;
	(shot :: BindableEvent).Event:Connect(function(pl: Player, tool: Tool, hit: Instance?, pos: Vector3)
		if S:GetAttribute("Phase") ~= "Heist" or not crew[pl] then
			return
		end
		if hit then
			if CollectionService:HasTag(hit, "BreakableGlass") and hit:IsA("BasePart") then
				breakGlass(hit, pl)
			end
			local cam = hit:FindFirstAncestorOfClass("Model")
			if cam and CollectionService:HasTag(cam, "SecurityCamera") then
				killCamera(cam)
			end
		end
		if tool:GetAttribute("Suppressed") ~= true then
			local b = bank()
			local center = if b then (b:GetAttribute("Root") :: CFrame).Position else Vector3.zero
			if (pos - center).Magnitude < 200 then
				bankAlert("gunshot")
			end
		end
	end)
	-- tools used by clicking
	local function watchTools(pl: Player)
		local function hookTool(t: Instance)
			if t:IsA("Tool") and t.Name == "EMP" and not t:GetAttribute("Hooked") then
				t:SetAttribute("Hooked", true)
				t.Activated:Connect(function()
					useEmp(pl)
				end)
			end
		end
		local function watch(holder: Instance)
			for _, t in holder:GetChildren() do
				hookTool(t)
			end
			holder.ChildAdded:Connect(hookTool)
		end
		local bp = pl:WaitForChild("Backpack", 10)
		if bp then
			watch(bp)
		end
		pl.CharacterAdded:Connect(function(char)
			watch(char)
			local b2 = pl:WaitForChild("Backpack", 10)
			if b2 then
				watch(b2)
			end
		end)
		if pl.Character then
			watch(pl.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		task.spawn(watchTools, p)
	end
	Players.PlayerAdded:Connect(watchTools)
	-- going down during a heist: drop what you carry, you're out
	local function onChar(pl: Player, char: Model)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		hum.Died:Connect(function()
			if crew[pl] and S:GetAttribute("Phase") == "Heist" then
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local kind = char:GetAttribute("Carry")
				if root and kind then
					looseBag(kind :: string, (char:GetAttribute("CarryValue") :: number?) or 0, (char:GetAttribute("CarryCount") :: number?) or 1, root.CFrame)
				end
				out[pl] = true
				toast(nil, pl.DisplayName .. " est à terre !", "bad")
			end
		end)
	end
	local function onPlayer(pl: Player)
		pl.CharacterAdded:Connect(function(c)
			onChar(pl, c)
		end)
		if pl.Character then
			onChar(pl, pl.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		crew[p] = nil
		out[p] = nil
		if scouts[p] then
			scouts[p] = nil
			if next(scouts) == nil and S:GetAttribute("Phase") == "Scout" then
				removeCluePrompts()
				Npcs.clear()
				S:SetAttribute("Phase", "Hideout")
			end
		end
	end)
end

Run.throwBag = Run.throw

return Run
