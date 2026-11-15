--!strict
-- The crew's black van for the opening cinematic: a hollow cargo van the crew sits in (benches along the
-- walls, a sliding side door on the right, a dim red cargo light), with a cab, glass, lights and wheels.
-- Model space: forward = -Z, right = +X, ground at Y = 0. All parts anchored; the clients move it along
-- the drive (Ride) and it ends exactly where the server parked it.
local CrewVan = {}

local RGB = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new

CrewVan.LENGTH = 18
CrewVan.WIDTH = 8
CrewVan.FLOOR = 2.0 -- cargo floor height
CrewVan.DOOR_Z = { -3.4, 2.4 } -- side door opening (local Z range, on the +X side)
CrewVan.DOOR_SLIDE = 6.2

-- seats: local CFrames of a seated rider's hips (facing inward). Left bench (-X) faces +X, right bench faces -X.
CrewVan.SEATS = {
	CF(-2.55, 0, -1.9) * CFrame.Angles(0, -math.pi / 2, 0),
	CF(2.55, 0, 5.0) * CFrame.Angles(0, math.pi / 2, 0),
	CF(-2.55, 0, 0.6) * CFrame.Angles(0, -math.pi / 2, 0),
	CF(2.55, 0, 7.4) * CFrame.Angles(0, math.pi / 2, 0),
	CF(-2.55, 0, 3.1) * CFrame.Angles(0, -math.pi / 2, 0),
	CF(-2.55, 0, 5.6) * CFrame.Angles(0, -math.pi / 2, 0),
	CF(-2.55, 0, 8.1) * CFrame.Angles(0, -math.pi / 2, 0),
	CF(0, 0, 8.2) * CFrame.Angles(0, 0, 0),
}
CrewVan.BENCH_TOP = 3.35

-- where a rider steps out to (local): just outside the side door
CrewVan.EXIT_INSIDE = V3(2.2, 0, -0.5)
CrewVan.EXIT_OUTSIDE = V3(13, 0, -1)

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.Parent = m
	return p
end

function CrewVan.build(at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "CrewVan"
	local L, W = CrewVan.LENGTH, CrewVan.WIDTH
	local F = CrewVan.FLOOR
	local H = 8.6 -- roof top
	local BLACK = RGB(28, 28, 32)
	local TRIM = RGB(18, 18, 20)
	local base = CF(0, 0, 0)
	local function p(name: string, size: Vector3, off: CFrame, col: Color3, mat: Enum.Material?, collide: boolean?): Part
		return part(m, name, size, base * off, col, mat, collide)
	end
	-- chassis + floor
	p("Chassis", V3(W - 0.6, 0.9, L - 0.6), CF(0, 1.25, 0), TRIM, Enum.Material.Metal)
	p("Floor", V3(W - 0.8, 0.3, 12.6), CF(0, F - 0.15, 2.4), RGB(55, 55, 60), Enum.Material.DiamondPlate)
	-- cargo box: left wall, right wall in two parts around the door, roof, rear doors
	local wallH = H - F
	p("WallLeft", V3(0.4, wallH, 13.2), CF(-W / 2 + 0.2, F + wallH / 2, 2.4), BLACK)
	local d0, d1 = CrewVan.DOOR_Z[1], CrewVan.DOOR_Z[2]
	local backLen = 8.9 - d1
	p("WallRightRear", V3(0.4, wallH, backLen), CF(W / 2 - 0.2, F + wallH / 2, d1 + backLen / 2), BLACK)
	p("WallRightFront", V3(0.4, wallH, d0 + 4.2), CF(W / 2 - 0.2, F + wallH / 2, (-4.2 + d0) / 2), BLACK)
	p("DoorHeader", V3(0.4, 1.0, d1 - d0), CF(W / 2 - 0.2, H - 0.5, (d0 + d1) / 2), BLACK)
	p("Roof", V3(W, 0.4, 13.4), CF(0, H - 0.2, 2.3), BLACK)
	p("RearDoors", V3(W, wallH, 0.4), CF(0, F + wallH / 2, 8.9), BLACK)
	p("RearSeam", V3(0.08, wallH - 0.4, 0.42), CF(0, F + wallH / 2, 8.91), TRIM, nil, false)
	for sx = -1, 1, 2 do
		local wnd = p("RearWindow", V3(2.6, 1.2, 0.1), CF(sx * 1.7, H - 2.0, 9.12), RGB(25, 35, 45), Enum.Material.Glass, false)
		wnd.Transparency = 0.25
		p("RearHandle", V3(0.5, 0.15, 0.15), CF(sx * 0.5, F + 2.6, 9.15), RGB(160, 160, 165), Enum.Material.Metal, false)
	end
	-- the red stripe and lettering band
	p("StripeL", V3(0.05, 0.5, 13), CF(-W / 2 - 0.02, F + 3.0, 2.4), RGB(196, 40, 28), nil, false)
	p("StripeRR", V3(0.05, 0.5, backLen), CF(W / 2 + 0.02, F + 3.0, d1 + backLen / 2), RGB(196, 40, 28), nil, false)
	-- cab: bulkhead, hood, windshield, cab roof, doors, dashboard, seats
	p("Bulkhead", V3(W - 0.8, wallH, 0.3), CF(0, F + wallH / 2, -4.1), RGB(40, 40, 44))
	p("CabFloor", V3(W, 0.4, 5), CF(0, F - 0.2, -6.5), TRIM)
	p("CabRoof", V3(W, 0.4, 3.0), CF(0, H - 0.6, -5.6), BLACK)
	p("Hood", V3(W, 2.0, 2.6), CF(0, F + 1.0, -7.7), BLACK)
	local ws = p("Windshield", V3(W - 0.6, 3.6, 0.15), CF(0, F + 3.7, -6.75) * CFrame.Angles(math.rad(-22), 0, 0), RGB(30, 45, 55), Enum.Material.Glass)
	ws.Transparency = 0.35
	for sx = -1, 1, 2 do
		p("CabDoor", V3(0.3, 3.0, 2.8), CF(sx * (W / 2 - 0.15), F + 1.5, -5.6), BLACK)
		local sw = p("SideWindow", V3(0.12, 2.4, 2.4), CF(sx * (W / 2 - 0.1), F + 4.3, -5.6), RGB(30, 45, 55), Enum.Material.Glass)
		sw.Transparency = 0.35
		p("Pillar", V3(0.3, 4.6, 0.3), CF(sx * (W / 2 - 0.15), F + 4.6, -4.2), BLACK)
		p("Mirror", V3(0.3, 0.8, 0.5), CF(sx * (W / 2 + 0.35), F + 3.6, -6.2), TRIM, nil, false)
		p("CabSeat", V3(2.2, 0.6, 2.0), CF(sx * 1.8, F + 1.0, -5.2), RGB(60, 60, 64), Enum.Material.Fabric, false)
		p("CabBack", V3(2.2, 2.4, 0.4), CF(sx * 1.8, F + 2.4, -4.4), RGB(60, 60, 64), Enum.Material.Fabric, false)
	end
	p("Dash", V3(W - 0.8, 0.9, 1.0), CF(0, F + 2.0, -6.9), TRIM, nil, false)
	p("Wheel", V3(0.3, 1.5, 1.5), CF(-1.8, F + 2.8, -6.2) * CFrame.Angles(math.rad(-30), 0, 0), RGB(30, 30, 30), nil, false).Name = "SteeringWheel"
	p("Grille", V3(W - 1.6, 1.2, 0.15), CF(0, F + 0.6, -9.05), RGB(40, 40, 44), Enum.Material.DiamondPlate, false)
	p("BumperFront", V3(W + 0.2, 0.8, 0.6), CF(0, 1.1, -9.1), TRIM, Enum.Material.Metal)
	p("BumperRear", V3(W + 0.2, 0.8, 0.6), CF(0, 1.1, 9.2), TRIM, Enum.Material.Metal)
	for sx = -1, 1, 2 do
		local hl = p("Headlight", V3(1.3, 0.6, 0.12), CF(sx * (W / 2 - 1.1), F + 1.2, -9.06), RGB(255, 248, 215), Enum.Material.Neon, false)
		local spot = Instance.new("SpotLight")
		spot.Brightness = 2
		spot.Range = 40
		spot.Angle = 50
		spot.Face = Enum.NormalId.Front
		spot.Color = RGB(255, 240, 210)
		spot.Parent = hl
		p("Taillight", V3(0.6, 1.4, 0.12), CF(sx * (W / 2 - 0.5), F + 2.0, 9.16), RGB(220, 30, 30), Enum.Material.Neon, false)
	end
	-- the sliding side door (closed), with its handle
	local door = p("SideDoor", V3(0.35, wallH - 1.0, d1 - d0), CF(W / 2 - 0.15, F + (wallH - 1.0) / 2, (d0 + d1) / 2), BLACK)
	part(m, "DoorHandle", V3(0.15, 0.2, 0.7), door.CFrame * CF(0.25, 0.2, -1.8), RGB(160, 160, 165), Enum.Material.Metal, false)
	part(m, "DoorStripe", V3(0.05, 0.5, d1 - d0), door.CFrame * CF(0.2, F + 3.0 - door.Position.Y, 0), RGB(196, 40, 28), nil, false)
	-- interior: benches, grab rails, cargo light
	p("BenchLeft", V3(1.5, CrewVan.BENCH_TOP - F, 11.6), CF(-W / 2 + 1.15, (F + CrewVan.BENCH_TOP) / 2, 2.9), RGB(70, 70, 76), Enum.Material.Fabric)
	p("BenchRight", V3(1.5, CrewVan.BENCH_TOP - F, 8.6 - d1 - 0.2), CF(W / 2 - 1.15, (F + CrewVan.BENCH_TOP) / 2, (d1 + 8.6) / 2 + 0.1), RGB(70, 70, 76), Enum.Material.Fabric)
	p("RailLeft", V3(0.15, 0.15, 11), CF(-W / 2 + 0.5, H - 1.4, 2.9), RGB(150, 150, 155), Enum.Material.Metal, false)
	p("RailRight", V3(0.15, 0.15, 5.8), CF(W / 2 - 0.5, H - 1.4, 5.6), RGB(150, 150, 155), Enum.Material.Metal, false)
	local lamp = p("CargoLamp", V3(1.2, 0.15, 0.6), CF(0, H - 0.47, 2.4), RGB(255, 60, 50), Enum.Material.Neon, false)
	local light = Instance.new("PointLight")
	light.Color = RGB(255, 70, 60)
	light.Brightness = 1.6
	light.Range = 14
	light.Shadows = true
	light.Parent = lamp
	-- gear on the floor: duffel bags, a crate
	p("Duffel", V3(2.2, 1.0, 1.1), CF(0.4, F + 0.5, 7.4), RGB(40, 44, 40), Enum.Material.Fabric, false)
	p("Crate", V3(1.4, 1.2, 1.4), CF(-0.6, F + 0.6, 7.9), RGB(120, 90, 50), Enum.Material.Wood, false)
	-- wheels (spun by the clients while driving)
	for _, o in { V3(W / 2 - 0.3, 0, -6.6), V3(-(W / 2 - 0.3), 0, -6.6), V3(W / 2 - 0.3, 0, 6.2), V3(-(W / 2 - 0.3), 0, 6.2) } do
		local w = p("Tire", V3(1.1, 2.8, 2.8), CF(o.X, 1.4, o.Z), RGB(22, 22, 22), Enum.Material.Rubber, false)
		w.Shape = Enum.PartType.Cylinder
		local hub = part(m, "Hub", V3(1.15, 1.2, 1.2), w.CFrame * CF(if o.X > 0 then 0.03 else -0.03, 0, 0), RGB(150, 150, 155), Enum.Material.Metal, false)
		hub.Shape = Enum.PartType.Cylinder
		hub:SetAttribute("Spin", true)
		w:SetAttribute("Spin", true)
	end
	m.WorldPivot = CFrame.identity -- the pivot is the ground point under the middle of the van
	m:PivotTo(at)
	return m
end

-- slide the side door open (k = 0..1), locally
function CrewVan.setDoor(m: Model, k: number)
	local door = m:FindFirstChild("SideDoor") :: BasePart?
	if not door then
		return
	end
	local closed = door:GetAttribute("Closed") :: CFrame?
	local pivot = m:GetPivot()
	if not closed then
		closed = pivot:ToObjectSpace(door.CFrame)
		door:SetAttribute("Closed", closed)
		for _, n in { "DoorHandle", "DoorStripe" } do
			local q = m:FindFirstChild(n) :: BasePart?
			if q then
				q:SetAttribute("Closed", pivot:ToObjectSpace(q.CFrame))
			end
		end
	end
	-- out by 0.45, then back along the body
	local out = math.clamp(k / 0.2, 0, 1)
	local slide = math.clamp((k - 0.15) / 0.85, 0, 1)
	local off = CF(0.45 * out, 0, CrewVan.DOOR_SLIDE * slide)
	door.CFrame = pivot * off * (closed :: CFrame)
	for _, n in { "DoorHandle", "DoorStripe" } do
		local q = m:FindFirstChild(n) :: BasePart?
		local c = q and q:GetAttribute("Closed") :: CFrame?
		if q and c then
			q.CFrame = pivot * off * c
		end
	end
end

return CrewVan
