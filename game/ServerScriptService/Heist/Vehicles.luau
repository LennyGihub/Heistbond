--!strict
-- Getaway vehicles: blocky old-school cars built from parts. Arcade driving: the chassis slides on the
-- ground (low friction), a LinearVelocity pushes it and an AngularVelocity turns it, an AlignOrientation
-- keeps it upright with a bit of goofy wobble. The driver's client owns the physics and sets the
-- constraint targets (StarterPlayerScripts.Heist.Driving); the server sets network ownership.
-- Each vehicle has a cargo bed: bags thrown or loaded in are counted (attributes Bags/Value/Capacity)
-- and shown as little bags in the back.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Heist = ReplicatedStorage:WaitForChild("Heist")
local Sfx = require(Heist:WaitForChild("Sfx"))

local Vehicles = {}
local RGB = Color3.fromRGB

export type Spec = { name: string, size: Vector3, color: Color3, speed: number, turn: number, cargo: number, seats: number, armored: boolean }
local SPECS: { [string]: Spec } = {
	van = { name = "Van noir", size = Vector3.new(8, 4.2, 17), color = RGB(32, 32, 36), speed = 58, turn = 1.6, cargo = 12, seats = 2, armored = false },
	sportscar = { name = "Voiture de sport", size = Vector3.new(7.4, 2.4, 14), color = RGB(196, 40, 28), speed = 95, turn = 2.3, cargo = 3, seats = 2, armored = false },
	armoredcar = { name = "Voiture blindée", size = Vector3.new(8.4, 4, 15), color = RGB(110, 116, 122), speed = 52, turn = 1.5, cargo = 6, seats = 2, armored = true },
}
Vehicles.SPECS = SPECS

local folder: Folder
local function getFolder(): Folder
	if not folder or not folder.Parent then
		folder = (workspace:FindFirstChild("HeistVehicles") or Instance.new("Folder")) :: Folder
		folder.Name = "HeistVehicles"
		folder.Parent = workspace
	end
	return folder
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.CanCollide = collide == true
	p.Massless = not collide
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- build a vehicle of `kind` at `cf` (cf = ground point, facing LookVector)
local function build(kind: string, cf: CFrame): Model
	local s = SPECS[kind]
	local m = Instance.new("Model")
	m.Name = s.name
	local L, W, Hh = s.size.Z, s.size.X, s.size.Y
	local base = cf * CFrame.new(0, 1.2, 0)
	local chassis = part(m, "Chassis", Vector3.new(W, 1.2, L), base, RGB(30, 30, 32), Enum.Material.Metal, true)
	chassis.Massless = false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0.2, 100, 1)
	chassis.CanCollide = false
	m.PrimaryPart = chassis
	local function add(name: string, size: Vector3, off: CFrame, col: Color3, mat: Enum.Material?, collide: boolean?): Part
		local p = part(m, name, size, base * off, col, mat, collide)
		weld(chassis, p)
		return p
	end
	-- body
	if kind == "van" then
		add("Body", Vector3.new(W, Hh, L - 4), CFrame.new(0, Hh / 2 + 0.6, 1.5), s.color, nil, true)
		add("Hood", Vector3.new(W, Hh * 0.55, 4), CFrame.new(0, Hh * 0.275 + 0.6, -L / 2 + 2), s.color, nil, true)
		local ws = add("Windshield", Vector3.new(W - 0.6, Hh * 0.4, 0.2), CFrame.new(0, Hh * 0.75 + 0.6, -L / 2 + 4.05) * CFrame.Angles(math.rad(-20), 0, 0), RGB(40, 60, 70), Enum.Material.Glass)
		ws.Transparency = 0.2
		add("Stripe", Vector3.new(W + 0.05, 0.4, L - 5), CFrame.new(0, Hh * 0.55 + 0.6, 1.6), RGB(196, 40, 28))
	elseif kind == "sportscar" then
		add("Body", Vector3.new(W, Hh * 0.6, L), CFrame.new(0, Hh * 0.3 + 0.6, 0), s.color, nil, true)
		add("Cabin", Vector3.new(W - 1.4, Hh * 0.55, L * 0.38), CFrame.new(0, Hh * 0.6 + 0.6 + Hh * 0.27, 0.6), RGB(30, 30, 36), Enum.Material.Glass, true).Transparency = 0.55
		add("Spoiler", Vector3.new(W, 0.25, 1.2), CFrame.new(0, Hh + 0.9, L / 2 - 0.6), RGB(20, 20, 22))
		for sx = -1, 1, 2 do
			add("SpoilerLeg", Vector3.new(0.3, 0.8, 0.3), CFrame.new(sx * (W / 2 - 1), Hh + 0.4, L / 2 - 0.6), RGB(20, 20, 22))
		end
		add("Stripe", Vector3.new(1.2, 0.05, L + 0.02), CFrame.new(0, Hh * 0.6 + 0.63, 0), RGB(242, 243, 243))
	else
		add("Body", Vector3.new(W, Hh, L - 3), CFrame.new(0, Hh / 2 + 0.6, 1), s.color, Enum.Material.DiamondPlate, true)
		add("Hood", Vector3.new(W, Hh * 0.6, 3), CFrame.new(0, Hh * 0.3 + 0.6, -L / 2 + 1.5), s.color, Enum.Material.DiamondPlate, true)
		local slit = add("Slit", Vector3.new(W - 1.5, 0.5, 0.2), CFrame.new(0, Hh * 0.8 + 0.6, -L / 2 + 3.05), RGB(20, 20, 20), Enum.Material.Glass)
		slit.Transparency = 0.1
		add("Bumper", Vector3.new(W + 0.4, 1, 0.8), CFrame.new(0, 1, -L / 2 - 0.2), RGB(40, 40, 44), Enum.Material.Metal, true)
	end
	-- round skids at the corners: the real contact with the ground (they ride over kerbs)
	for _, o in { Vector3.new(W / 2 - 0.8, 0, -(L / 2 - 1.5)), Vector3.new(-(W / 2 - 0.8), 0, -(L / 2 - 1.5)), Vector3.new(W / 2 - 0.8, 0, L / 2 - 1.5), Vector3.new(-(W / 2 - 0.8), 0, L / 2 - 1.5) } do
		local sk = add("Skid", Vector3.new(1.6, 1.6, 1.6), CFrame.new(o.X, -0.4, o.Z), RGB(0, 0, 0), Enum.Material.SmoothPlastic, true)
		sk.Shape = Enum.PartType.Ball
		sk.Transparency = 1
		sk.Massless = false
		sk.CustomPhysicalProperties = PhysicalProperties.new(1, 0.02, 0, 100, 1)
	end
	-- wheels (visual, the Driving script spins them)
	local wz = L / 2 - 2.6
	for _, o in { Vector3.new(W / 2, 0, -wz), Vector3.new(-W / 2, 0, -wz), Vector3.new(W / 2, 0, wz), Vector3.new(-W / 2, 0, wz) } do
		local wh = add("Wheel", Vector3.new(1.1, 2.6, 2.6), CFrame.new(o.X, 0.1, o.Z), RGB(25, 25, 25), Enum.Material.Rubber)
		wh.Shape = Enum.PartType.Cylinder
		add("Hub", Vector3.new(1.15, 1.1, 1.1), CFrame.new(o.X + (if o.X > 0 then 0.05 else -0.05), 0.1, o.Z), RGB(190, 190, 195), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
	end
	-- lights
	for sx = -1, 1, 2 do
		add("Headlight", Vector3.new(1.2, 0.6, 0.1), CFrame.new(sx * (W / 2 - 1), 1.6, -L / 2 - 0.05), RGB(255, 250, 210), Enum.Material.Neon)
		add("Taillight", Vector3.new(1.2, 0.5, 0.1), CFrame.new(sx * (W / 2 - 1), 1.6, L / 2 + 0.05), RGB(220, 30, 30), Enum.Material.Neon)
	end
	-- seats
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = base * CFrame.new(-W / 4, 1.4, -L / 2 + (if kind == "van" then 5.5 else 5))
	seat.Transparency = 1
	seat.CanCollide = false
	seat.MaxSpeed = s.speed
	seat.Torque = 0
	seat.HeadsUpDisplay = false
	seat.Parent = m
	weld(chassis, seat)
	for i = 2, s.seats do
		local ps = Instance.new("Seat")
		ps.Name = "Passenger"
		ps.Size = Vector3.new(2, 1, 2)
		ps.CFrame = seat.CFrame * CFrame.new(W / 2, 0, 0)
		ps.Transparency = 1
		ps.CanCollide = false
		ps.Parent = m
		weld(chassis, ps)
		local _ = i
	end
	-- cargo bed (trigger + loading prompt)
	local cargo = add("Cargo", Vector3.new(W + 2, 6, if kind == "sportscar" then 5 else 7), CFrame.new(0, 3, L / 2 - (if kind == "sportscar" then 2.5 else 3.5)), RGB(255, 255, 0))
	cargo.Transparency = 1
	cargo.CanTouch = true
	cargo.CanQuery = false
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "LoadPrompt"
	pp.ActionText = "Charger le sac"
	pp.ObjectText = s.name
	pp.HoldDuration = 0.3
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.Parent = cargo
	-- physics movers (targets set by the driver's client)
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = chassis
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Move"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = chassis.AssemblyMass * 60 + 40000
	lv.PlaneVelocity = Vector2.zero
	lv.Parent = chassis
	local av = Instance.new("AngularVelocity")
	av.Name = "Turn"
	av.Attachment0 = att
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.MaxTorque = 4e6
	av.AngularVelocity = Vector3.zero
	av.Parent = chassis
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Upright"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.AlignType = Enum.AlignType.PrimaryAxisParallel
	ao.PrimaryAxis = Vector3.new(0, 1, 0)
	ao.MaxTorque = 2e6
	ao.Responsiveness = 18
	ao.Parent = chassis
	att.Axis = Vector3.new(0, 1, 0)
	att.SecondaryAxis = Vector3.new(1, 0, 0)
	m:SetAttribute("Kind", kind)
	m:SetAttribute("Speed", s.speed)
	m:SetAttribute("TurnRate", s.turn)
	m:SetAttribute("Capacity", s.cargo)
	m:SetAttribute("Bags", 0)
	m:SetAttribute("Value", 0)
	m:SetAttribute("Objective", false)
	CollectionService:AddTag(m, "HeistVehicle")
	-- ownership follows the driver
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local pl = occ and Players:GetPlayerFromCharacter(occ.Parent)
		pcall(function()
			if pl then
				chassis:SetNetworkOwner(pl)
			else
				lv.PlaneVelocity = Vector2.zero
				av.AngularVelocity = Vector3.zero
				chassis:SetNetworkOwnershipAuto()
			end
		end)
	end)
	return m
end

-- add a bag to a vehicle; false if full
function Vehicles.load(m: Model, value: number, isObjective: boolean): boolean
	local bags = (m:GetAttribute("Bags") :: number) or 0
	local cap = (m:GetAttribute("Capacity") :: number) or 0
	if bags >= cap then
		return false
	end
	bags += 1
	m:SetAttribute("Bags", bags)
	m:SetAttribute("Value", ((m:GetAttribute("Value") :: number) or 0) + value)
	if isObjective then
		m:SetAttribute("Objective", true)
	end
	-- a little bag appears in the back, with a bounce
	local cargo = m:FindFirstChild("Cargo") :: BasePart?
	local chassis = m.PrimaryPart
	if cargo and chassis then
		local col = if isObjective then RGB(60, 40, 30) else RGB(70, 120, 60)
		local b = Instance.new("Part")
		b.Name = "LoadedBag"
		b.Size = if isObjective then Vector3.new(1.6, 1.2, 0.5) else Vector3.new(1.6, 1.6, 1.6)
		b.Color = col
		b.Material = Enum.Material.Fabric
		b.TopSurface = Enum.SurfaceType.Studs
		b.CanCollide = false
		b.Massless = true
		local i = bags - 1
		local target = cargo.CFrame * CFrame.new(((i % 3) - 1) * 1.8, -1.6 + math.floor(i / 6) * 1.6, ((math.floor(i / 3) % 2) - 0.5) * 1.8)
		b.CFrame = target * CFrame.new(0, 4, 0)
		b.Anchored = true
		b.Parent = m
		local t = TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Bounce), { CFrame = target })
		t:Play()
		t.Completed:Once(function()
			if b.Parent and chassis.Parent then
				b.CFrame = chassis.CFrame * chassis.CFrame:ToObjectSpace(target)
				b.Anchored = false
				weld(chassis, b)
			end
		end)
		Sfx.play("thud", cargo, 0.8, 1.1)
		Sfx.popText(cargo.Position + Vector3.new(0, 4, 0), "+" .. bags .. "/" .. cap, RGB(120, 255, 140), 6)
	end
	return true
end

-- spawn a vehicle at a ground point: it drops from the sky with a goofy bounce and a honk
function Vehicles.spawn(kind: string, pos: Vector3, facing: Vector3?): Model?
	if not SPECS[kind] then
		return nil
	end
	local look = facing or Vector3.new(0, 0, -1)
	local ground = pos
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getFolder() }
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -150, 0), params)
	if hit then
		ground = hit.Position
	end
	local cf = CFrame.lookAt(ground, ground + Vector3.new(look.X, 0, look.Z))
	local m = build(kind, cf)
	local chassis = m.PrimaryPart :: BasePart
	local final = chassis.CFrame
	m:PivotTo(m:GetPivot() + Vector3.new(0, 40, 0))
	chassis.Anchored = true
	m.Parent = getFolder()
	local cv = Instance.new("CFrameValue")
	cv.Value = chassis.CFrame
	cv.Changed:Connect(function(v)
		m:PivotTo(v)
	end)
	local t = TweenService:Create(cv, TweenInfo.new(1.1, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = final })
	t:Play()
	t.Completed:Once(function()
		cv:Destroy()
		chassis.Anchored = false
		Sfx.puff(ground + Vector3.new(0, 1, 0), 10, RGB(220, 210, 190), 8)
		Sfx.play("horn", chassis, 1, 1, 260)
		Sfx.popText(ground + Vector3.new(0, 8, 0), "TUT TUT !", RGB(245, 205, 48), 8)
	end)
	return m
end

function Vehicles.clear()
	for _, v in getFolder():GetChildren() do
		v:Destroy()
	end
end

function Vehicles.all(): { Model }
	local out = {}
	for _, v in getFolder():GetChildren() do
		if v:IsA("Model") then
			table.insert(out, v)
		end
	end
	return out
end

return Vehicles
