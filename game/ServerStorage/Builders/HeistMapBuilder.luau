--!strict
-- HeistMapBuilder: builds the heist world (run from Edit mode, re-running replaces it):
--   workspace.NooblaBank  - the bank from the "ATLAS BANK - third-person game layout, expanded
--                           revision" plan (54 x 40 m, 6 m corridor, 4 m portals, 6 m ceilings), with the
--                           hooks the heist uses: vault door + keypad (hack) + card reader (level 5 card)
--                           + drill spot, C4 spots (door, roof, 3 vault walls), breakable vault walls/roof,
--                           100 numbered deposit lockers (101-200, objective 167 on the north wall),
--                           rope spots, breakable windows, restricted zones, NPC/scout markers, cameras.
--   workspace.Hideout     - the crew's hideout: planning table, equipment locker, scouting board,
--                           garage drop zone (escape zone).
--   workspace.HeistRoads  - street in front of the bank and the road to the hideout.
--   require(game.ServerStorage.Builders.HeistMapBuilder:Clone())()
-- Plan coordinates are metres: x east 0..54, z south 0..40 (north = -Z), 1 m = 3 studs.
-- Tags used by the heist scripts: Locker, C4Spot, RopeSpot, BreakableGlass, Restricted, SecurityCamera,
-- HeistMarker, PlannerTable, InventoryLocker, ScoutBoard, EscapeZone, ScoutClue, BankDoor.

local CollectionService = game:GetService("CollectionService")

local M = 3 -- studs per metre
local FY = 0.5 -- floor top (studs)
local H = 18 -- ceiling height above the floor (6 m clear)
local TOP = 26 -- parapet top above the floor
local BASE = 11 -- height of the stone base band
local ROOT = CFrame.new(0, 0, 260) * CFrame.Angles(0, math.pi, 0) -- entrance faces the spawn (-Z world)
local NORTH, SOUTH, WEST, EAST = 0, math.pi, math.pi / 2, -math.pi / 2


local RGB = Color3.fromRGB
local MAT = Enum.Material

-- palette
local C = {
	siding = RGB(236, 222, 190),
	siding2 = RGB(226, 210, 176),
	sidingGap = RGB(120, 100, 80),
	pilaster = RGB(86, 56, 42),
	cornice = RGB(112, 64, 48),
	stone = RGB(132, 124, 114),
	stoneDark = RGB(98, 92, 86),
	glass = RGB(48, 66, 72),
	frame = RGB(52, 54, 58),
	green = RGB(0, 150, 92),
	greenDark = RGB(0, 102, 62),
	wallHall = RGB(238, 233, 222),
	wallStaff = RGB(206, 212, 218),
	wallVault = RGB(122, 124, 128),
	ceiling = RGB(246, 246, 242),
	walnut = RGB(92, 60, 40),
	oak = RGB(170, 128, 86),
	steel = RGB(150, 154, 160),
	dark = RGB(38, 40, 44),
	white = RGB(245, 245, 245),
	teal = RGB(62, 112, 128),
	leaf = RGB(62, 124, 58),
	leaf2 = RGB(78, 146, 66),
	cash = RGB(104, 150, 92),
	gold = RGB(236, 182, 46),
}

local root: Model -- set in build()

------------------------------------------------------------------ helpers

local function at(x: number, y: number, z: number, rot: number?): CFrame
	return ROOT * CFrame.new(x * M - 81, FY + y, z * M - 60) * CFrame.Angles(0, rot or 0, 0)
end

local function folder(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function P(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or MAT.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if deco then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	p.Parent = parent
	return p
end

-- cylinder whose axis is the cf's local Y (upright when cf is upright)
local function cyl(parent: Instance, name: string, d: number, h: number, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): Part
	local p = P(parent, name, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, deco)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, d: number, cf: CFrame, color: Color3, mat: Enum.Material?, deco: boolean?): Part
	local p = P(parent, name, Vector3.new(d, d, d), cf, color, mat, deco)
	p.Shape = Enum.PartType.Ball
	return p
end

local function surf(part: BasePart, face: Enum.NormalId, pps: number, lit: boolean?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = if lit then 0 else 1
	g.Brightness = if lit then 1.6 else 1
	g.Parent = part
	return g
end

local function frame(parent: Instance, color: Color3, pos: UDim2, size: UDim2, corner: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(corner, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function text(parent: Instance, s: string, color: Color3, font: Enum.Font?, pos: UDim2?, size: UDim2?, xa: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = s
	l.TextColor3 = color
	l.FontFace = Font.fromEnum(font or Enum.Font.GothamBold)
	l.TextScaled = true
	l.Position = pos or UDim2.new()
	l.Size = size or UDim2.fromScale(1, 1)
	l.TextXAlignment = xa or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

-- the bank's logo: green square with a white "A" mountain mark, then words
local function logo(g: Instance, pos: UDim2, size: UDim2)
	local sq = frame(g, C.green, pos, size, 0.18)
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = sq
	local st = Instance.new("UIStroke")
	st.Color = C.white
	st.Thickness = 3
	st.Parent = sq
	text(sq, "A", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.88))
end

local function light(part: BasePart, kind: string, brightness: number, range: number, color: Color3?, face: Enum.NormalId?)
	local l: Light
	if kind == "surface" then
		local s = Instance.new("SurfaceLight")
		s.Face = face or Enum.NormalId.Bottom
		s.Angle = 120
		l = s
	elseif kind == "spot" then
		local s = Instance.new("SpotLight")
		s.Face = face or Enum.NormalId.Bottom
		s.Angle = 70
		l = s
	else
		l = Instance.new("PointLight")
	end
	l.Brightness = brightness
	l.Color = color or RGB(255, 242, 222)
	l.Shadows = false;
	(l :: any).Range = range
	l.Parent = part
end

------------------------------------------------------------------ walls

type Op = { a: number, b: number, top: number, sill: number?, glass: boolean?, frosted: boolean? }

-- Wall along an axis. axis "x": runs along x from s to e (metres) at z = f. axis "z": along z at x = f.
-- y0..y1 in studs above the floor, th in studs. ops = door/window openings.
local function wall(parent: Instance, axis: string, f: number, s: number, e: number, y0: number, y1: number, th: number,
	ops: { Op }, color: Color3, mat: Enum.Material?, ext: number?, noFrames: boolean?)
	local extA = if ext ~= nil then ext else th / 2
	local function seg(a: number, b: number, h0: number, h1: number, col: Color3, m: Enum.Material?, name: string, thick: number?): Part?
		if b - a <= 0.001 or h1 - h0 <= 0.001 then
			return nil
		end
		local e0 = if a == s then extA else 0
		local e1 = if b == e then extA else 0
		local len = (b - a) * M + e0 + e1
		local shift = (e1 - e0) / 2
		local mid = (a + b) / 2
		local cy = (h0 + h1) / 2
		local t = thick or th
		if axis == "x" then
			return P(parent, name, Vector3.new(len, h1 - h0, t), at(mid, cy, f) * CFrame.new(shift, 0, 0), col, m)
		else
			return P(parent, name, Vector3.new(t, h1 - h0, len), at(f, cy, mid) * CFrame.new(0, 0, shift), col, m)
		end
	end
	table.sort(ops, function(p, q)
		return p.a < q.a
	end)
	local cur = s
	for _, op in ops do
		seg(cur, op.a, y0, y1, color, mat, "Wall")
		local sill = op.sill or y0
		seg(op.a, op.b, y0, math.min(sill, y1), color, mat, "Wall")
		seg(op.a, op.b, math.max(op.top, y0), y1, color, mat, "Wall")
		if op.glass and sill < y1 and op.top > y0 then
			local g = seg(op.a, op.b, math.max(sill, y0), math.min(op.top, y1), C.glass, MAT.Glass, "Window", 0.3)
			if g then
				g.Transparency = if op.frosted then 0.15 else 0.45
				g.Reflectance = 0.12
				if op.frosted then
					g.Color = RGB(200, 214, 220)
					g.Material = MAT.SmoothPlastic
				end
				if not noFrames then
					-- aluminium frame + centre mullion
					local w = (op.b - op.a) * M
					local hgt = g.Size.Y
					local fr = folder(parent, "WindowFrame")
					local base = g.CFrame
					local thick = th + 0.12
					local function fp(sz: Vector3, off: Vector3)
						local size = if axis == "x" then sz else Vector3.new(sz.Z, sz.Y, sz.X)
						local o = if axis == "x" then off else Vector3.new(off.Z, off.Y, off.X)
						P(fr, "Frame", size, base * CFrame.new(o), C.frame, MAT.Metal, true)
					end
					fp(Vector3.new(w, 0.3, thick), Vector3.new(0, hgt / 2, 0))
					fp(Vector3.new(w, 0.3, thick), Vector3.new(0, -hgt / 2, 0))
					fp(Vector3.new(0.3, hgt, thick), Vector3.new(w / 2, 0, 0))
					fp(Vector3.new(0.3, hgt, thick), Vector3.new(-w / 2, 0, 0))
					if w > 9 then
						fp(Vector3.new(0.25, hgt, 0.45), Vector3.new(0, 0, 0))
					end
					-- sill ledge
					fp(Vector3.new(w + 0.6, 0.25, th + 0.9), Vector3.new(0, -hgt / 2 - 0.15, 0))
				end
			end
		end
		cur = op.b
	end
	seg(cur, e, y0, y1, color, mat, "Wall")
end

------------------------------------------------------------------ doors

type DoorStyle = { color: Color3, mat: Enum.Material, thick: number, glass: boolean?, push: boolean?, vision: boolean? }
local DOOR_WOOD: DoorStyle = { color = RGB(150, 108, 72), mat = MAT.Wood, thick = 0.3 }
local DOOR_STAFF: DoorStyle = { color = RGB(196, 200, 204), mat = MAT.SmoothPlastic, thick = 0.3, vision = true }
local DOOR_STEEL: DoorStyle = { color = RGB(120, 126, 132), mat = MAT.DiamondPlate, thick = 0.35, push = true }
local DOOR_GLASS: DoorStyle = { color = C.frame, mat = MAT.Metal, thick = 0.3, glass = true }

local function leaf(m: Model, hinge: CFrame, w: number, h: number, st: DoorStyle, angle: number)
	local lf = Instance.new("Model")
	lf.Name = "Leaf"
	lf.Parent = m
	local slab: Part
	if st.glass then
		-- aluminium frame + big glass pane
		slab = P(lf, "Slab", Vector3.new(w - 0.1, 0.6, st.thick), hinge * CFrame.new(w / 2, 0.35, 0), st.color, st.mat)
		P(lf, "Top", Vector3.new(w - 0.1, 0.4, st.thick), hinge * CFrame.new(w / 2, h - 0.25, 0), st.color, st.mat)
		P(lf, "Stile", Vector3.new(0.35, h - 0.1, st.thick), hinge * CFrame.new(0.22, h / 2, 0), st.color, st.mat)
		P(lf, "Stile", Vector3.new(0.35, h - 0.1, st.thick), hinge * CFrame.new(w - 0.27, h / 2, 0), st.color, st.mat)
		local g = P(lf, "Glass", Vector3.new(w - 0.6, h - 1.1, 0.12), hinge * CFrame.new(w / 2, h / 2 + 0.05, 0), RGB(170, 200, 205), MAT.Glass)
		g.Transparency = 0.6
		-- push bar
		P(lf, "Bar", Vector3.new(w - 0.9, 0.18, 0.18), hinge * CFrame.new(w / 2, 3.4, st.thick / 2 + 0.3), RGB(200, 200, 205), MAT.Metal, true)
		P(lf, "Bar", Vector3.new(w - 0.9, 0.18, 0.18), hinge * CFrame.new(w / 2, 3.4, -st.thick / 2 - 0.3), RGB(200, 200, 205), MAT.Metal, true)
	else
		slab = P(lf, "Slab", Vector3.new(w - 0.1, h - 0.05, st.thick), hinge * CFrame.new(w / 2, h / 2, 0), st.color, st.mat)
		for side = -1, 1, 2 do
			local z = side * (st.thick / 2 + 0.12)
			if st.push then
				P(lf, "PushBar", Vector3.new(w - 1, 0.2, 0.2), hinge * CFrame.new(w / 2, 3.3, z), RGB(200, 60, 50), MAT.Metal, true)
			else
				P(lf, "Handle", Vector3.new(0.7, 0.14, 0.14), hinge * CFrame.new(w - 0.75, 3.3, z + side * 0.08), RGB(205, 205, 210), MAT.Metal, true)
				P(lf, "Rose", Vector3.new(0.3, 0.5, 0.1), hinge * CFrame.new(w - 0.45, 3.3, z - side * 0.05), RGB(205, 205, 210), MAT.Metal, true)
			end
		end
		if st.vision then
			local v = P(lf, "Vision", Vector3.new(0.6, 2.4, st.thick + 0.04), hinge * CFrame.new(w - 1.2, 5.6, 0), RGB(170, 200, 205), MAT.Glass, true)
			v.Transparency = 0.5
		end
	end
	lf.PrimaryPart = slab
	lf.WorldPivot = hinge
	lf:SetAttribute("Closed", hinge)
	lf:SetAttribute("OpenAngle", angle)
end

-- door in an opening a..b (metres) of a wall on `axis` at f. swing = +1/-1 picks the side it opens to.
local function door(parent: Instance, name: string, axis: string, f: number, a: number, b: number, h: number,
	st: DoorStyle, swing: number, double: boolean?, thick: number?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	local w = (b - a) * M
	local hingeA = if axis == "x" then at(a, 0, f) else at(f, 0, a, -math.pi / 2)
	local hingeB = if axis == "x" then at(b, 0, f, math.pi) else at(f, 0, b, math.pi / 2)
	if double then
		leaf(m, hingeA, w / 2, h, st, swing * math.rad(92))
		leaf(m, hingeB, w / 2, h, st, -swing * math.rad(92))
	else
		leaf(m, hingeA, w, h, st, swing * math.rad(95))
	end
	-- casing trim on both faces
	local t = (thick or 0.8) + 0.25
	local trim = if st == DOOR_STEEL then RGB(90, 94, 98) else RGB(240, 238, 232)
	local cf = hingeA * CFrame.new(w / 2, 0, 0)
	P(m, "Casing", Vector3.new(0.35, h, t), cf * CFrame.new(-w / 2 - 0.17, h / 2, 0), trim, MAT.SmoothPlastic, true)
	P(m, "Casing", Vector3.new(0.35, h, t), cf * CFrame.new(w / 2 + 0.17, h / 2, 0), trim, MAT.SmoothPlastic, true)
	P(m, "Casing", Vector3.new(w + 0.7, 0.35, t), cf * CFrame.new(0, h + 0.17, 0), trim, MAT.SmoothPlastic, true)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "DoorPrompt"
	pp.ActionText = "Open"
	pp.ObjectText = name
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Default
	local holder = P(m, "PromptAnchor", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 3.6, 0), C.white, MAT.SmoothPlastic, true)
	holder.Transparency = 1
	pp.Parent = holder
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(m, "BankDoor")
	return m
end

-- small room-name plaque, centred at plan (x,z), facing rot, y studs
local function plaque(parent: Instance, x: number, z: number, y: number, rot: number, s: string)
	local p = P(parent, "Plaque", Vector3.new(2.6, 0.75, 0.08), at(x, y, z, rot), RGB(40, 46, 52), MAT.SmoothPlastic, true)
	local g = surf(p, Enum.NormalId.Front, 60)
	text(g, s, C.white, Enum.Font.GothamBold, UDim2.fromScale(0.06, 0.15), UDim2.fromScale(0.88, 0.7))
end

------------------------------------------------------------------ furniture

local function office(parent: Instance, cf: CFrame, color: Color3?) -- office chair facing cf.LookVector
	local m = folder(parent, "Chair")
	local col = color or RGB(40, 44, 52)
	cyl(m, "Base", 2, 0.25, cf * CFrame.new(0, 0.15, 0), RGB(60, 62, 66), MAT.Metal)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		P(m, "Leg", Vector3.new(0.25, 0.2, 1.1), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -0.55), RGB(50, 50, 54), MAT.Metal, true)
	end
	cyl(m, "Post", 0.3, 1.4, cf * CFrame.new(0, 1.0, 0), RGB(150, 150, 155), MAT.Metal, true)
	P(m, "Seat", Vector3.new(2.1, 0.45, 2), cf * CFrame.new(0, 1.85, 0), col, MAT.Fabric)
	P(m, "Back", Vector3.new(2, 2.4, 0.35), cf * CFrame.new(0, 3.25, 0.95) * CFrame.Angles(math.rad(-8), 0, 0), col, MAT.Fabric)
	P(m, "Arm", Vector3.new(0.25, 0.2, 1.3), cf * CFrame.new(1.0, 2.6, 0.1), RGB(50, 50, 54), MAT.SmoothPlastic, true)
	P(m, "Arm", Vector3.new(0.25, 0.2, 1.3), cf * CFrame.new(-1.0, 2.6, 0.1), RGB(50, 50, 54), MAT.SmoothPlastic, true)
end

local function guestChair(parent: Instance, cf: CFrame, color: Color3?)
	local m = folder(parent, "GuestChair")
	local col = color or RGB(150, 70, 52)
	for _, o in { Vector3.new(0.8, 0, 0.8), Vector3.new(-0.8, 0, 0.8), Vector3.new(0.8, 0, -0.8), Vector3.new(-0.8, 0, -0.8) } do
		P(m, "Leg", Vector3.new(0.2, 1.7, 0.2), cf * CFrame.new(o.X, 0.85, o.Z), RGB(60, 60, 64), MAT.Metal, true)
	end
	P(m, "Seat", Vector3.new(2, 0.4, 2), cf * CFrame.new(0, 1.85, 0), col, MAT.Fabric)
	P(m, "Back", Vector3.new(2, 1.9, 0.3), cf * CFrame.new(0, 3.0, 0.9), col, MAT.Fabric)
end

local function monitor(parent: Instance, cf: CFrame, label: string?) -- screen faces cf.LookVector
	local m = folder(parent, "Monitor")
	P(m, "Foot", Vector3.new(0.9, 0.1, 0.7), cf * CFrame.new(0, 0.05, 0.1), RGB(30, 30, 34), MAT.SmoothPlastic, true)
	P(m, "Neck", Vector3.new(0.2, 0.8, 0.15), cf * CFrame.new(0, 0.45, 0.25), RGB(30, 30, 34), MAT.SmoothPlastic, true)
	local s = P(m, "Screen", Vector3.new(2.3, 1.4, 0.15), cf * CFrame.new(0, 1.35, 0.2), RGB(22, 22, 26), MAT.SmoothPlastic, true)
	local g = surf(s, Enum.NormalId.Front, 60, true)
	local bg = frame(g, RGB(20, 46, 70), UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.92, 0.88))
	frame(bg, C.green, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.16))
	text(bg, label or "ATLAS", C.white, Enum.Font.GothamBold, UDim2.fromScale(0.04, 0.01), UDim2.fromScale(0.6, 0.14), Enum.TextXAlignment.Left)
	for i = 1, 4 do
		frame(bg, RGB(120, 160, 190), UDim2.fromScale(0.08, 0.2 + i * 0.15), UDim2.fromScale(0.3 + (i % 3) * 0.17, 0.06))
	end
	P(m, "Keyboard", Vector3.new(1.7, 0.08, 0.55), cf * CFrame.new(0, 0.05, -0.9), RGB(40, 40, 44), MAT.SmoothPlastic, true)
	P(m, "Mouse", Vector3.new(0.22, 0.08, 0.34), cf * CFrame.new(1.2, 0.05, -0.9), RGB(40, 40, 44), MAT.SmoothPlastic, true)
end

-- desk: worker sits on the +Z side of cf (behind), facing cf.LookVector... front panel faces -Z
local function desk(parent: Instance, cf: CFrame, w: number, d: number, color: Color3?, screen: string?)
	local m = folder(parent, "Desk")
	local col = color or C.walnut
	P(m, "Top", Vector3.new(w, 0.25, d), cf * CFrame.new(0, 2.8, 0), col, MAT.Wood)
	P(m, "Side", Vector3.new(0.25, 2.7, d - 0.2), cf * CFrame.new(w / 2 - 0.2, 1.35, 0), col, MAT.Wood)
	P(m, "Side", Vector3.new(0.25, 2.7, d - 0.2), cf * CFrame.new(-w / 2 + 0.2, 1.35, 0), col, MAT.Wood)
	P(m, "Modesty", Vector3.new(w - 0.4, 1.8, 0.2), cf * CFrame.new(0, 1.8, -d / 2 + 0.25), col, MAT.Wood)
	-- drawer pedestal
	P(m, "Pedestal", Vector3.new(1.5, 2.5, d - 0.6), cf * CFrame.new(w / 2 - 1.2, 1.3, 0.1), RGB(70, 70, 74), MAT.SmoothPlastic)
	for i = 0, 2 do
		P(m, "Pull", Vector3.new(0.6, 0.08, 0.08), cf * CFrame.new(w / 2 - 1.2, 0.6 + i * 0.75, d / 2 - 0.25), RGB(190, 190, 195), MAT.Metal, true)
	end
	-- monitor faces the worker (+Z side)
	monitor(m, cf * CFrame.new(-0.4, 2.93, -0.2) * CFrame.Angles(0, math.pi, 0), screen)
	-- papers + pen cup + phone
	P(m, "Papers", Vector3.new(0.85, 0.05, 1.1), cf * CFrame.new(-w / 2 + 1, 2.95, 0.3) * CFrame.Angles(0, 0.2, 0), C.white, MAT.SmoothPlastic, true)
	cyl(m, "PenCup", 0.3, 0.5, cf * CFrame.new(w / 2 - 0.5, 3.18, -0.5), RGB(60, 60, 64), MAT.SmoothPlastic, true)
	P(m, "Phone", Vector3.new(0.6, 0.2, 0.7), cf * CFrame.new(w / 2 - 1.1, 3.03, -0.4), RGB(30, 30, 32), MAT.SmoothPlastic, true)
end

local function plant(parent: Instance, cf: CFrame, s: number?)
	local k = s or 1
	local m = folder(parent, "Plant")
	cyl(m, "Pot", 1.6 * k, 1.8 * k, cf * CFrame.new(0, 0.9 * k, 0), RGB(214, 210, 200), MAT.SmoothPlastic)
	cyl(m, "Soil", 1.45 * k, 0.1, cf * CFrame.new(0, 1.78 * k, 0), RGB(70, 50, 36), MAT.Ground, true)
	cyl(m, "Stem", 0.2 * k, 2 * k, cf * CFrame.new(0, 2.6 * k, 0), RGB(90, 70, 40), MAT.Wood, true)
	ball(m, "Leaves", 2.4 * k, cf * CFrame.new(0, 3.9 * k, 0), C.leaf, MAT.Grass, true)
	ball(m, "Leaves", 1.8 * k, cf * CFrame.new(0.7 * k, 3.2 * k, 0.4 * k), C.leaf2, MAT.Grass, true)
	ball(m, "Leaves", 1.7 * k, cf * CFrame.new(-0.6 * k, 3.4 * k, -0.4 * k), C.leaf2, MAT.Grass, true)
end

local function shelf(parent: Instance, cf: CFrame, w: number, h: number, d: number, levels: number, fill: string, color: Color3?)
	local m = folder(parent, "Shelf")
	local col = color or RGB(120, 124, 130)
	P(m, "Side", Vector3.new(0.2, h, d), cf * CFrame.new(w / 2, h / 2, 0), col, MAT.Metal)
	P(m, "Side", Vector3.new(0.2, h, d), cf * CFrame.new(-w / 2, h / 2, 0), col, MAT.Metal)
	P(m, "Back", Vector3.new(w, h, 0.1), cf * CFrame.new(0, h / 2, d / 2 - 0.05), col, MAT.Metal, true)
	local rng = Random.new(math.floor(w * 100 + h * 10))
	for i = 0, levels - 1 do
		local y = 0.3 + i * (h - 0.4) / levels
		P(m, "Board", Vector3.new(w, 0.15, d), cf * CFrame.new(0, y, 0), col, MAT.Metal)
		local gap = (h - 0.4) / levels - 0.3
		if i < levels and gap > 0.6 then
			local x = -w / 2 + 0.3
			while x < w / 2 - 0.6 do
				if fill == "books" then
					local bw = rng:NextNumber(0.25, 0.45)
					local bh = math.min(gap, rng:NextNumber(0.9, 1.4))
					local hue = rng:NextNumber()
					P(m, "Book", Vector3.new(bw, bh, d - 0.5), cf * CFrame.new(x + bw / 2, y + 0.08 + bh / 2, 0), Color3.fromHSV(hue, 0.45, 0.6), MAT.SmoothPlastic, true)
					x += bw + 0.03
				elseif fill == "boxes" then
					local bw = 1.6
					local bh = math.min(gap, 1.2)
					P(m, "ArchiveBox", Vector3.new(bw - 0.1, bh, d - 0.3), cf * CFrame.new(x + bw / 2, y + 0.08 + bh / 2, 0), RGB(196, 160, 112), MAT.Cardboard, true)
					x += bw
				elseif fill == "binders" then
					local bw = 0.4
					local bh = math.min(gap, 1.3)
					local cols = { RGB(30, 80, 140), RGB(160, 40, 40), RGB(40, 120, 70), RGB(40, 40, 46) }
					P(m, "Binder", Vector3.new(bw - 0.04, bh, d - 0.4), cf * CFrame.new(x + bw / 2, y + 0.08 + bh / 2, 0), cols[rng:NextInteger(1, 4)], MAT.SmoothPlastic, true)
					x += bw
				elseif fill == "bags" then
					local bw = 1.4
					ball(m, "CashBag", 1.25, cf * CFrame.new(x + bw / 2, y + 0.7, 0), RGB(190, 180, 150), MAT.Fabric, true)
					x += bw
				else
					break
				end
			end
		end
	end
	P(m, "Board", Vector3.new(w, 0.15, d), cf * CFrame.new(0, h, 0), col, MAT.Metal)
end

local function cabinet(parent: Instance, cf: CFrame, w: number, h: number, d: number, drawers: number, color: Color3?)
	local m = folder(parent, "Cabinet")
	P(m, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color or RGB(150, 154, 160), MAT.Metal)
	for i = 1, drawers do
		local y = h * (i - 0.5) / drawers
		P(m, "Pull", Vector3.new(w * 0.4, 0.1, 0.12), cf * CFrame.new(0, y, -d / 2 - 0.05), RGB(60, 60, 64), MAT.Metal, true)
		P(m, "Line", Vector3.new(w - 0.1, 0.05, 0.04), cf * CFrame.new(0, h * i / drawers - 0.02, -d / 2 - 0.01), RGB(90, 92, 96), MAT.Metal, true)
	end
end

local function picture(parent: Instance, cf: CFrame, w: number, h: number, seed: number) -- faces cf.LookVector
	local fr = P(parent, "Picture", Vector3.new(w, h, 0.15), cf, RGB(40, 34, 30), MAT.Wood, true)
	local g = surf(fr, Enum.NormalId.Front, 40)
	local rng = Random.new(seed)
	local art = frame(g, RGB(240, 236, 226), UDim2.fromScale(0.06, 0.07), UDim2.fromScale(0.88, 0.86))
	local sky = Color3.fromHSV(rng:NextNumber(0.5, 0.62), 0.35, 0.92)
	frame(art, sky, UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.84, 0.8))
	frame(art, Color3.fromHSV(rng:NextNumber(0.25, 0.4), 0.45, 0.55), UDim2.fromScale(0.08, 0.58), UDim2.fromScale(0.84, 0.32))
	frame(art, Color3.fromHSV(rng:NextNumber(0.05, 0.12), 0.5, 0.75), UDim2.fromScale(0.2 + rng:NextNumber() * 0.4, 0.25), UDim2.fromScale(0.2, 0.2), 1)
end

local function camera(parent: Instance, cf: CFrame) -- security camera pointing along cf.LookVector, cf at the mount
	local m = folder(parent, "SecurityCamera")
	P(m, "Mount", Vector3.new(0.4, 0.4, 0.8), cf, RGB(230, 230, 230), MAT.SmoothPlastic, true)
	local body = P(m, "Body", Vector3.new(0.7, 0.6, 1.5), cf * CFrame.new(0, -0.5, -0.9) * CFrame.Angles(math.rad(-25), 0, 0), RGB(235, 235, 235), MAT.SmoothPlastic, true)
	P(m, "Lens", Vector3.new(0.45, 0.45, 0.1), body.CFrame * CFrame.new(0, 0, -0.78), RGB(20, 20, 24), MAT.Glass, true)
	local led = P(m, "Led", Vector3.new(0.1, 0.1, 0.05), body.CFrame * CFrame.new(0.25, 0.2, -0.76), RGB(255, 40, 40), MAT.Neon, true)
	led.Name = "RecLed"
	m.PrimaryPart = body
	CollectionService:AddTag(m, "SecurityCamera")
end

local function ceilingLight(parent: Instance, x: number, z: number, w: number?, color: Color3?)
	local s = w or 3.6
	local p = P(parent, "CeilingLight", Vector3.new(s, 0.15, s), at(x, H - 0.08, z), RGB(255, 252, 240), MAT.Neon, true)
	p.Transparency = 0.15
	P(parent, "LightTrim", Vector3.new(s + 0.3, 0.1, s + 0.3), at(x, H - 0.03, z), RGB(225, 225, 225), MAT.SmoothPlastic, true)
	light(p, "surface", 1.1, 18, color)
end

local function roomLights(parent: Instance, x0: number, z0: number, x1: number, z1: number, nx: number, nz: number, color: Color3?)
	for i = 1, nx do
		for j = 1, nz do
			ceilingLight(parent, x0 + (x1 - x0) * (i - 0.5) / nx, z0 + (z1 - z0) * (j - 0.5) / nz, nil, color)
		end
	end
end

local function cashStack(parent: Instance, cf: CFrame)
	P(parent, "Cash", Vector3.new(1.2, 0.45, 0.6), cf, C.cash, MAT.SmoothPlastic, true)
	P(parent, "Band", Vector3.new(0.2, 0.47, 0.62), cf, RGB(240, 230, 200), MAT.SmoothPlastic, true)
end

------------------------------------------------------------------ heist hooks

local function tag(inst: Instance, t: string): Instance
	CollectionService:AddTag(inst, t)
	return inst
end

-- invisible marker part (NPC spots, scout clues, spawn points...)
local markers: Model
local function marker(name: string, cf: CFrame, attrs: { [string]: any }?): Part
	local p = P(markers, name, Vector3.new(1, 1, 1), cf, RGB(255, 0, 255), MAT.SmoothPlastic, true)
	p.Transparency = 1
	if attrs then
		for k, v in attrs do
			p:SetAttribute(k, v)
		end
	end
	tag(p, "HeistMarker")
	return p
end

local function prompt(parent: Instance, name: string, action: string, object: string, hold: number, dist: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = dist or 8
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

-- a slab over the whole plan (0..54 x 0..40) with a rectangular hole, as up to 4 parts
local function slabWithHole(parent: Instance, name: string, y0: number, y1: number, col: Color3, mat: Enum.Material,
	hx0: number, hz0: number, hx1: number, hz1: number)
	local function rect(x0: number, z0: number, x1: number, z1: number)
		if x1 - x0 > 0.01 and z1 - z0 > 0.01 then
			P(parent, name, Vector3.new((x1 - x0) * M, y1 - y0, (z1 - z0) * M), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), col, mat)
		end
	end
	rect(0, 0, 54, hz0)
	rect(0, hz1, 54, 40)
	rect(0, hz0, hx0, hz1)
	rect(hx1, hz0, 54, hz1)
end

------------------------------------------------------------------ bank

local function buildBank(): Model
	root = Instance.new("Model")
	root.Name = "NooblaBank"
	root:SetAttribute("Plan", "54 x 40 m, 1 m = 3 studs, plan origin = north-west corner")
	root:SetAttribute("Root", ROOT)
	local shell = folder(root, "Shell")
	local rooms = folder(root, "Rooms")
	local roofLayer = folder(root, "RoofLayer") -- hidden in the planner's ground-floor view
	local lights = folder(roofLayer, "Lights")
	local doors = folder(root, "Doors")
	local hooks = folder(root, "Hooks")
	markers = folder(root, "Markers")

	---------------------------------------------------------------- floors
	local floorSpec = {
		{ "09 Manager", 0, 0, 9, 8, RGB(78, 84, 98), MAT.Carpet },
		{ "10 Meeting", 9, 0, 18, 8, RGB(78, 84, 98), MAT.Carpet },
		{ "11 Staff Room", 18, 0, 28, 8, RGB(168, 128, 90), MAT.WoodPlanks },
		{ "12 Vault", 28, 0, 40, 8, RGB(112, 114, 120), MAT.DiamondPlate },
		{ "13 IT", 40, 0, 47, 8, RGB(150, 152, 156), MAT.SmoothPlastic },
		{ "14 Records", 47, 0, 54, 8, RGB(150, 152, 156), MAT.SmoothPlastic },
		{ "08 Staff Corridor", 0, 8, 54, 14, RGB(134, 142, 152), MAT.Plastic },
		{ "06 Teller Work Area", 0, 14, 44, 20, RGB(120, 110, 100), MAT.Carpet },
		{ "07 Cash Operations", 44, 14, 54, 20, RGB(150, 152, 156), MAT.SmoothPlastic },
		{ "02 Consult B", 0, 20, 10, 30, RGB(92, 98, 112), MAT.Carpet },
		{ "01 Consult A", 0, 30, 10, 40, RGB(92, 98, 112), MAT.Carpet },
		{ "03 Banking Hall", 10, 20, 44, 40, RGB(232, 226, 214), MAT.Marble },
		{ "05 Advisor", 44, 20, 54, 30, RGB(92, 98, 112), MAT.Carpet },
		{ "04 Customer WC", 44, 30, 54, 40, RGB(222, 226, 228), MAT.CeramicTiles },
	}
	local R: { [string]: Model } = {}
	for _, r in floorSpec do
		local name, x0, z0, x1, z1 = r[1] :: string, r[2] :: number, r[3] :: number, r[4] :: number, r[5] :: number
		local rm = folder(rooms, name)
		R[string.sub(name, 1, 2)] = rm
		local f = P(rm, "Floor", Vector3.new((x1 - x0) * M, 1, (z1 - z0) * M), at((x0 + x1) / 2, -0.5, (z0 + z1) / 2), r[6] :: Color3, r[7] :: Enum.Material)
		f:SetAttribute("Room", name)
	end
	P(shell, "Foundation", Vector3.new(54 * M + 4, 1, 40 * M + 4), at(27, -1.1, 20), C.stoneDark, MAT.Concrete)

	---------------------------------------------------------------- exterior walls
	local IN, OUT = 0.4 / M, 0.4 / M
	local function ext(axis: string, f: number, dir: number, s: number, e: number, ops: { Op })
		local inOps: { Op } = {}
		for _, o in ops do
			table.insert(inOps, { a = o.a, b = o.b, top = o.top, sill = o.sill })
		end
		wall(shell, axis, f - dir * IN, s, e, 0, H, 0.8, inOps, C.wallHall, MAT.SmoothPlastic, 0, true)
		wall(roofLayer, axis, f - dir * IN, s, e, H, TOP - 0.6, 0.8, {}, RGB(150, 146, 140), MAT.Concrete, 0)
		local outOps = table.clone(ops)
		wall(shell, axis, f + dir * OUT, s, e, -FY, BASE, 0.8, outOps, C.stone, MAT.Slate, 0.8)
		wall(shell, axis, f + dir * OUT, s, e, BASE, TOP, 0.8, {}, C.sidingGap, MAT.SmoothPlastic, 0.8)
	end
	ext("x", 0, -1, 0, 54, { -- north (rear alley)
		{ a = 2, b = 7, sill = 3, top = 10, glass = true },
		{ a = 11, b = 16, sill = 3, top = 10, glass = true },
		{ a = 21, b = 26, sill = 3, top = 10, glass = true }, -- staff room window (vans park behind it)
		{ a = 30, b = 38, top = BASE }, -- vault north wall: breakable panel
	})
	ext("x", 40, 1, 0, 54, { -- south (street front)
		{ a = 2, b = 8, sill = 3, top = 10, glass = true },
		{ a = 12, b = 22, sill = 3, top = 10, glass = true },
		{ a = 24, b = 30, top = 12 }, -- 6 m main entrance
		{ a = 47, b = 51, sill = 6, top = 10, glass = true, frosted = true },
	})
	ext("z", 0, -1, 0, 40, { -- west
		{ a = 9, b = 13, top = 11 },
		{ a = 22, b = 28, sill = 3, top = 10, glass = true },
		{ a = 32, b = 38, sill = 3, top = 10, glass = true },
	})
	ext("z", 54, 1, 0, 40, { -- east
		{ a = 9, b = 13, top = 11 },
		{ a = 22, b = 28, sill = 3, top = 10, glass = true },
	})
	-- every clear exterior window can be broken
	for _, d in shell:GetChildren() do
		if d.Name == "Window" and d:IsA("BasePart") and d.Transparency > 0.3 then
			tag(d, "BreakableGlass")
		end
	end

	---------------------------------------------------------------- interior walls
	local IW = 1.0
	local function iw(axis: string, f: number, s: number, e: number, ops: { Op }, color: Color3?, th: number?, mat: Enum.Material?)
		wall(shell, axis, f, s, e, 0, H, th or IW, ops, color or C.wallStaff, mat or MAT.SmoothPlastic)
	end
	local PH = 12 -- portal height (4 m wide openings, 4 m tall)
	iw("x", 8, 0, 28, { { a = 2.5, b = 6.5, top = PH }, { a = 11.5, b = 15.5, top = PH }, { a = 21, b = 25, top = PH } })
	iw("x", 8, 28, 40, { { a = 32, b = 36, top = 13 } }, C.wallVault, 2, MAT.Concrete)
	iw("x", 8, 40, 54, { { a = 41.5, b = 45.5, top = PH }, { a = 48.5, b = 52.5, top = PH } })
	iw("z", 9, 0, 8, {})
	iw("z", 18, 0, 8, {})
	iw("z", 28, 0, 8, { { a = 1, b = 7, top = BASE } }, C.wallVault, 2, MAT.Concrete)
	iw("z", 40, 0, 8, { { a = 1, b = 7, top = BASE } }, C.wallVault, 2, MAT.Concrete)
	iw("z", 47, 0, 8, {})
	iw("x", 14, 0, 54, { { a = 24, b = 30, top = 13 }, { a = 47, b = 51, top = PH } })
	iw("z", 44, 14, 20, {})
	iw("x", 20, 0, 10, {}, C.wallHall)
	iw("z", 10, 20, 40, { { a = 24, b = 28, top = PH }, { a = 34, b = 38, top = PH } }, C.wallHall)
	iw("x", 30, 0, 10, {}, C.wallHall)
	iw("z", 44, 20, 40, { { a = 24, b = 28, top = PH }, { a = 34, b = 38, top = PH } }, C.wallHall)
	iw("x", 30, 44, 54, {}, C.wallHall)

	-- breakable vault walls (C4): panels filling the openings left above
	local function breakPanel(name: string, size: Vector3, cf: CFrame, side: string, col: Color3, mat: Enum.Material)
		local p = P(hooks, name, size, cf, col, mat)
		p:SetAttribute("Side", side)
		tag(p, "BreakWall")
		return p
	end
	breakPanel("BreakWall_West", Vector3.new(2, BASE, 6 * M), at(28, BASE / 2, 4), "West", C.wallVault, MAT.Concrete)
	breakPanel("BreakWall_East", Vector3.new(2, BASE, 6 * M), at(40, BASE / 2, 4), "East", C.wallVault, MAT.Concrete)
	breakPanel("BreakWall_North", Vector3.new(8 * M, BASE + FY, 1.6), at(34, (BASE - FY) / 2, 0), "North", C.stone, MAT.Slate)

	---------------------------------------------------------------- ceiling + roof (hole over the vault is a breakable panel)
	slabWithHole(roofLayer, "Ceiling", H, H + 0.5, C.ceiling, MAT.SmoothPlastic, 31, 2, 37, 6)
	slabWithHole(roofLayer, "Roof", H + 0.5, H + 1.5, RGB(120, 118, 114), MAT.Pebble, 31, 2, 37, 6)
	local roofPanel = breakPanel("BreakRoof", Vector3.new(6 * M, 1.5, 4 * M), at(34, H + 0.75, 4), "Roof", RGB(110, 108, 104), MAT.Pebble)
	roofPanel.Parent = roofLayer
	-- skylight hatch look on the roof panel
	local hatch = P(roofLayer, "VaultHatch", Vector3.new(6, 0.4, 6), at(34, H + 1.7, 4), RGB(140, 144, 150), MAT.DiamondPlate, true)
	hatch:SetAttribute("Side", "Roof")

	---------------------------------------------------------------- vault door (opened by the heist: hack, card, drill, C4)
	do
		local vd = Instance.new("Model")
		vd.Name = "VaultDoor"
		vd.Parent = hooks
		local w = 4 * M
		local hinge = at(32, 0, 8)
		local lf = Instance.new("Model")
		lf.Name = "Leaf"
		lf.Parent = vd
		local slab = P(lf, "Slab", Vector3.new(w - 0.15, 12.9, 2.2), hinge * CFrame.new(w / 2, 6.5, 0), RGB(150, 156, 164), MAT.Metal)
		local face = hinge * CFrame.new(w / 2, 6.6, 1.15)
		cyl(lf, "Disc", 10.6, 0.3, face * CFrame.Angles(math.pi / 2, 0, 0), RGB(176, 182, 190), MAT.Metal, true)
		cyl(lf, "Ring", 8, 0.35, face * CFrame.new(0, 0, 0.08) * CFrame.Angles(math.pi / 2, 0, 0), RGB(130, 136, 144), MAT.Metal, true)
		cyl(lf, "Hub", 1.6, 1, face * CFrame.new(0, 0, 0.5) * CFrame.Angles(math.pi / 2, 0, 0), RGB(200, 204, 210), MAT.Metal, true)
		local wheel = folder(lf, "Wheel")
		for k = 0, 2 do
			P(wheel, "Spoke", Vector3.new(6, 0.4, 0.4), face * CFrame.new(0, 0, 0.8) * CFrame.Angles(0, 0, k * math.pi / 3), RGB(210, 214, 220), MAT.Metal, true)
			for s2 = -1, 1, 2 do
				ball(wheel, "Knob", 0.8, face * CFrame.Angles(0, 0, k * math.pi / 3) * CFrame.new(s2 * 3, 0, 0.8), RGB(40, 40, 44), MAT.Metal, true)
			end
		end
		for k = 0, 15 do
			local a = k * math.pi / 8
			ball(lf, "Bolt", 0.55, face * CFrame.new(math.cos(a) * 4.7, math.sin(a) * 4.7, 0.15), RGB(120, 124, 130), MAT.Metal, true)
		end
		local plate = P(lf, "NamePlate", Vector3.new(4, 0.9, 0.1), face * CFrame.new(0, -5.4, 0.2), RGB(200, 170, 80), MAT.Metal, true)
		text(surf(plate, Enum.NormalId.Back, 60), "NOOBLA SAFE CO.", RGB(50, 36, 10), Enum.Font.GothamBlack)
		P(lf, "Hinge", Vector3.new(0.8, 11, 2.6), hinge * CFrame.new(0.3, 6.5, 0.3), RGB(90, 94, 100), MAT.Metal, true)
		lf.PrimaryPart = slab
		lf.WorldPivot = hinge
		vd:SetAttribute("Closed", hinge)
		vd:SetAttribute("OpenAngle", math.rad(100))
		vd:SetAttribute("Open", false)
		local fcf = at(34, 0, 8)
		P(vd, "Jamb", Vector3.new(0.8, 13.6, 2.6), fcf * CFrame.new(-w / 2 - 0.4, 6.8, 0), RGB(100, 104, 110), MAT.Metal, true)
		P(vd, "Jamb", Vector3.new(0.8, 13.6, 2.6), fcf * CFrame.new(w / 2 + 0.4, 6.8, 0), RGB(100, 104, 110), MAT.Metal, true)
		P(vd, "Lintel", Vector3.new(w + 1.6, 0.8, 2.6), fcf * CFrame.new(0, 13.4, 0), RGB(100, 104, 110), MAT.Metal, true)
		vd.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

		-- keypad (hack, method 1) and card reader (level 5 card, method 4) on the corridor side
		local wallFace = 8 + 1.0 / M
		local kp = P(hooks, "VaultKeypad", Vector3.new(1.2, 1.7, 0.3), at(37.2, 5, wallFace + 0.15 / M, SOUTH), RGB(40, 42, 46), MAT.Metal)
		local kg = surf(kp, Enum.NormalId.Front, 60, true)
		local scr = frame(kg, RGB(20, 60, 30), UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.22))
		text(scr, "SECULOCK v1", RGB(120, 255, 140), Enum.Font.Code)
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.26, 0.13)
		grid.CellPadding = UDim2.fromScale(0.04, 0.03)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		local pad = frame(kg, RGB(40, 42, 46), UDim2.fromScale(0.08, 0.33), UDim2.fromScale(0.86, 0.62))
		grid.Parent = pad
		for _ = 1, 12 do
			frame(pad, RGB(150, 152, 156), UDim2.new(), UDim2.new())
		end
		local kled = P(hooks, "KeypadLed", Vector3.new(0.25, 0.25, 0.1), kp.CFrame * CFrame.new(0.4, 1.0, -0.15), RGB(255, 40, 40), MAT.Neon, true)
		kled:SetAttribute("Side", "Keypad")
		prompt(kp, "HackPrompt", "Pirater", "Clavier du coffre", 0, 7)
		kp:SetAttribute("Kind", "Keypad")

		local cr = P(hooks, "VaultCardReader", Vector3.new(1.1, 1.6, 0.3), at(30.8, 5, wallFace + 0.15 / M, SOUTH), RGB(30, 32, 36), MAT.Metal)
		local cg = surf(cr, Enum.NormalId.Front, 60, true)
		frame(cg, RGB(230, 180, 40), UDim2.fromScale(0.15, 0.1), UDim2.fromScale(0.7, 0.18))
		text(cg, "NV. 5", RGB(30, 30, 30), Enum.Font.GothamBlack, UDim2.fromScale(0.15, 0.1), UDim2.fromScale(0.7, 0.18))
		frame(cg, RGB(10, 10, 12), UDim2.fromScale(0.2, 0.45), UDim2.fromScale(0.6, 0.08))
		local cled = P(hooks, "CardLed", Vector3.new(0.25, 0.25, 0.1), cr.CFrame * CFrame.new(0, -0.55, -0.15), RGB(255, 40, 40), MAT.Neon, true)
		cled:SetAttribute("Side", "Card")
		prompt(cr, "ReaderPrompt", "Badger", "Lecteur de carte Nv.5", 0, 7)
		cr:SetAttribute("Kind", "CardReader")

		-- drill spot on the door face
		local ds = P(hooks, "DrillSpot", Vector3.new(3, 3, 0.4), at(34, 6.6, wallFace + 1.4 / M, SOUTH), RGB(255, 200, 0), MAT.Neon, true)
		ds.Transparency = 1
		prompt(ds, "DrillPrompt", "Installer la perceuse", "Porte du coffre", 1.2, 9)
	end

	---------------------------------------------------------------- C4 spots
	local function c4spot(name: string, cf: CFrame, target: string, label: string)
		local s = P(hooks, name, Vector3.new(2.4, 2.4, 0.3), cf, RGB(255, 140, 0), MAT.Neon, true)
		s.Transparency = 1
		s:SetAttribute("Target", target)
		tag(s, "C4Spot")
		prompt(s, "C4Prompt", "Poser le C4", label, 1.5, 9)
	end
	c4spot("C4_Door", at(34, 3, 8 + 2.5 / M, SOUTH), "Door", "Porte du coffre")
	c4spot("C4_West", at(28 - 1.2 / M, 4, 4, WEST), "West", "Mur du coffre (salle du personnel)")
	c4spot("C4_East", at(40 + 1.2 / M, 4, 4, EAST), "East", "Mur du coffre (salle IT)")
	c4spot("C4_North", at(34, 4, -1.1 / M, NORTH), "North", "Mur du coffre (ruelle)")
	c4spot("C4_Roof", at(34, H + 1.7, 4) * CFrame.Angles(-math.pi / 2, 0, 0), "Roof", "Toit au-dessus du coffre")

	---------------------------------------------------------------- deposit lockers (101-200, 167 = objective, north wall)
	do
		local vault = R["12"]
		local lf = folder(vault, "Lockers")
		local num = 101
		local function row(wallName: string, startCf: CFrame, cols: number)
			-- startCf: centre of the first column on the wall face, facing into the vault; columns go along +X
			for c = 0, cols - 1 do
				for r = 0, 3 do
					local cf = startCf * CFrame.new(c * 3, 1.5 + 3 * r + 1.5, 0)
					local lk = P(lf, "Locker_" .. num, Vector3.new(2.85, 2.85, 0.7), cf, RGB(186, 190, 198), MAT.Metal)
					lk:SetAttribute("Number", num)
					lk:SetAttribute("Wall", wallName)
					tag(lk, "Locker")
					local g = surf(lk, Enum.NormalId.Front, 40)
					local inner = frame(g, RGB(200, 204, 212), UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.84))
					local st = Instance.new("UIStroke")
					st.Color = RGB(110, 114, 120)
					st.Thickness = 3
					st.Parent = inner
					text(inner, tostring(num), RGB(40, 44, 50), Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.34))
					frame(inner, RGB(60, 62, 66), UDim2.fromScale(0.42, 0.56), UDim2.fromScale(0.16, 0.2), 1)
					local pp = prompt(lk, "LockerPrompt", "Forcer", "Casier " .. num, 1.5, 6)
					pp.Enabled = false -- the heist turns these on once the vault is open
					num += 1
				end
			end
		end
		-- west wall: faces east, columns run north -> south
		local wx = 28 + 1.0 / M + 0.35 / M
		row("West", at(wx, -1.5, 0.8 / M + 1.5 / M + 0.1, EAST) * CFrame.Angles(0, 0, 0) * CFrame.new(0, 0, 0), 7)
		-- north wall: faces south, columns run west -> east
		row("North", at(40 - 3.5 / M, -1.5, 0.8 / M + 0.35 / M, SOUTH), 11)
		-- east wall: faces west, columns run south -> north
		row("East", at(40 - 1.0 / M - 0.35 / M, -1.5, 8 - 1.0 / M - 1.5 / M - 0.1, WEST), 7)
		-- open storage zone: steel table with empty trays + bench
		P(vault, "StorageTable", Vector3.new(10, 0.4, 4), at(34, 3.2, 4.4), RGB(90, 94, 100), MAT.Metal)
		P(vault, "TableBase", Vector3.new(8, 3, 2.6), at(34, 1.5, 4.4), RGB(70, 74, 80), MAT.DiamondPlate)
		for k = 0, 2 do
			P(vault, "Tray", Vector3.new(2.6, 0.3, 1.6), at(32.6 + k * 1.4, 3.55, 4.4), RGB(170, 174, 180), MAT.Metal, true)
		end
		roomLights(lights, 28, 0, 40, 8, 2, 2, RGB(220, 235, 255))
		camera(vault, at(39.5, H - 0.6, 0.5, math.rad(-135)))
		for k = 0, 7 do
			P(vault, "Stripe", Vector3.new(1.2, 0.04, 3), at(32.3 + k * 0.5, 0.02, 7.2) * CFrame.Angles(0, math.rad(35), 0),
				if k % 2 == 0 then RGB(240, 200, 30) else RGB(30, 30, 30), MAT.SmoothPlastic, true)
		end
	end

	---------------------------------------------------------------- 03 BANKING HALL
	do
		local hall = R["03"]
		roomLights(lights, 10, 20, 44, 40, 6, 3)
		for i = 0, 3 do
			local x = 15 + i * 8
			local cfp = at(x, H - 4, 31)
			cyl(lights, "PendantCord", 0.1, 4, at(x, H - 2, 31), RGB(30, 30, 30), MAT.Metal, true)
			cyl(lights, "PendantShade", 3, 1.2, cfp, C.greenDark, MAT.Metal, true)
			local bulb = ball(lights, "PendantBulb", 1.2, cfp * CFrame.new(0, -0.6, 0), RGB(255, 236, 200), MAT.Neon, true)
			light(bulb, "point", 0.9, 18)
		end
		-- 6 m clear route from the entrance to the teller area: green runner
		P(hall, "RouteCarpet", Vector3.new(6 * M - 2, 0.04, 20 * M - 6), at(27, 0.02, 30), RGB(0, 110, 70), MAT.Carpet, true)
		P(hall, "EntranceMat", Vector3.new(6 * M - 2, 0.06, 6), at(27, 0.03, 38.8), RGB(40, 44, 48), MAT.Fabric, true)
		-- columns + low writing islands (cover for the shootouts), kept off the central route
		for _, x in { 16, 38 } do
			P(hall, "Column", Vector3.new(4, H, 4), at(x, H / 2, 25), RGB(226, 220, 208), MAT.Marble)
			P(hall, "ColumnBase", Vector3.new(4.8, 1, 4.8), at(x, 0.5, 25), C.walnut, MAT.Wood)
			local isl = folder(hall, "WritingIsland")
			P(isl, "Body", Vector3.new(8, 3.6, 3), at(x, 1.8, 29), C.walnut, MAT.Wood)
			P(isl, "Top", Vector3.new(8.6, 0.3, 3.6), at(x, 3.75, 29), RGB(236, 232, 224), MAT.Marble)
			for k = -1, 1 do
				P(isl, "Slips", Vector3.new(1, 0.08, 1.3), at(x, 3.95, 29) * CFrame.new(k * 2.4, 0, 0) * CFrame.Angles(0, k * 0.3, 0), C.white, MAT.SmoothPlastic, true)
			end
		end
		-- queue stanchions in front of tellers 1-2 and 3-4
		for _, x0 in { 12, 32 } do
			local prev: Vector3? = nil
			for k = 0, 4 do
				local cfp = at(x0 + k * 2.5, 0, 23)
				cyl(hall, "PostBase", 1.1, 0.15, cfp * CFrame.new(0, 0.08, 0), RGB(40, 40, 44), MAT.Metal)
				cyl(hall, "Post", 0.25, 3.0, cfp * CFrame.new(0, 1.6, 0), RGB(200, 200, 205), MAT.Metal)
				local here = (cfp * CFrame.new(0, 2.85, 0)).Position
				if prev then
					P(hall, "Belt", Vector3.new(0.05, 0.3, (here - prev).Magnitude), CFrame.lookAt((prev + here) / 2, here), C.greenDark, MAT.Fabric)
				end
				prev = here
			end
		end
		-- two seating benches (5 seats each) facing each other
		local wait = folder(hall, "Seating")
		for k = 0, 4 do
			guestChair(wait, at(12.5 + k * 1.1, 0, 33.2, SOUTH), RGB(0, 118, 76))
			guestChair(wait, at(12.5 + k * 1.1, 0, 36.6, NORTH), RGB(0, 118, 76))
		end
		P(wait, "CoffeeTable", Vector3.new(14, 0.3, 3.4), at(14.7, 1.5, 34.9), C.oak, MAT.Wood)
		P(wait, "TableBase", Vector3.new(12, 1.3, 2), at(14.7, 0.7, 34.9), RGB(50, 50, 54), MAT.Metal)
		for k = 1, 4 do
			P(wait, "Magazine", Vector3.new(1.0, 0.06, 1.3), at(13 + k * 0.7, 1.7, 34.8) * CFrame.Angles(0, k * 0.5, 0),
				Color3.fromHSV(k * 0.27 % 1, 0.5, 0.85), MAT.SmoothPlastic, true)
		end
		-- reception desk (x 36..42, z 32.5..34)
		local rec = folder(hall, "Reception")
		local rcf = at(39, 0, 33.3)
		P(rec, "Front", Vector3.new(17, 3.6, 0.5), rcf * CFrame.new(0, 1.8, 2), C.walnut, MAT.Wood)
		P(rec, "FrontPanel", Vector3.new(16, 2.6, 0.1), rcf * CFrame.new(0, 1.9, 2.3), C.oak, MAT.Wood, true)
		P(rec, "Top", Vector3.new(17.4, 0.25, 1.4), rcf * CFrame.new(0, 3.7, 1.7), RGB(236, 232, 224), MAT.Marble)
		P(rec, "WorkTop", Vector3.new(16.6, 0.2, 2.4), rcf * CFrame.new(0, 2.8, 0.4), C.walnut, MAT.Wood)
		P(rec, "EndL", Vector3.new(0.5, 3.6, 3.6), rcf * CFrame.new(-8.4, 1.8, 0.6), C.walnut, MAT.Wood)
		P(rec, "EndR", Vector3.new(0.5, 3.6, 3.6), rcf * CFrame.new(8.4, 1.8, 0.6), C.walnut, MAT.Wood)
		local rs = P(rec, "Sign", Vector3.new(7, 1.1, 0.06), rcf * CFrame.new(0, 2.2, 2.36) * CFrame.Angles(0, math.pi, 0), C.white, MAT.SmoothPlastic, true)
		rs.Transparency = 1
		text(surf(rs, Enum.NormalId.Front, 60, true), "ACCUEIL", RGB(220, 240, 230), Enum.Font.GothamBold)
		monitor(rec, rcf * CFrame.new(-3, 2.9, 0.4), "ACCUEIL")
		office(rec, at(38, 0, 32.4, SOUTH))
		-- 3 ATMs against the south wall (x 34..42)
		for i, x in { 35, 38, 41 } do
			local acf = at(x, 0, 40 - 0.8 / M - 1.05 / M, NORTH)
			local a = folder(hall, "ATM" .. i)
			P(a, "Body", Vector3.new(3.6, 6.4, 2.1), acf * CFrame.new(0, 3.2, 0), RGB(54, 58, 64), MAT.Metal)
			P(a, "Header", Vector3.new(3.6, 1.2, 2.3), acf * CFrame.new(0, 7.0, -0.1), C.green, MAT.SmoothPlastic)
			local hdr = P(a, "HeaderFace", Vector3.new(3.4, 1.0, 0.05), acf * CFrame.new(0, 7.0, -1.28), C.green, MAT.Neon, true)
			hdr.Transparency = 0.3
			text(surf(hdr, Enum.NormalId.Front, 80, true), "ATM", C.white, Enum.Font.GothamBlack)
			local scr = P(a, "Screen", Vector3.new(2.4, 1.7, 0.15), acf * CFrame.new(0, 5.0, -1.05) * CFrame.Angles(math.rad(-12), 0, 0), RGB(20, 20, 24), MAT.Glass, true)
			local sg = surf(scr, Enum.NormalId.Front, 70, true)
			local bg = frame(sg, RGB(0, 72, 50), UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.9, 0.88))
			text(bg, "NOOBLA BANK", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.9, 0.28))
			text(bg, "Insérez votre carte", RGB(170, 240, 200), Enum.Font.Gotham, UDim2.fromScale(0.1, 0.5), UDim2.fromScale(0.8, 0.22))
			P(a, "Shelf", Vector3.new(3.2, 0.3, 1.2), acf * CFrame.new(0, 3.5, -1.5), RGB(70, 74, 80), MAT.Metal)
			P(a, "CardSlot", Vector3.new(0.8, 0.12, 0.1), acf * CFrame.new(1.0, 4.1, -1.08), RGB(0, 255, 140), MAT.Neon, true)
		end
		-- notice board (scouting clue: renovation notice -> C4 roof/walls)
		local nb = P(hall, "NoticeBoard", Vector3.new(8, 5, 0.3), at(10 + 0.5 / M + 0.1, 7, 31.5, EAST), RGB(170, 130, 90), MAT.Fabric)
		local ng = surf(nb, Enum.NormalId.Front, 30)
		text(ng, "AVIS AUX CLIENTS", RGB(60, 30, 10), Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.14))
		frame(ng, C.white, UDim2.fromScale(0.06, 0.22), UDim2.fromScale(0.4, 0.7))
		frame(ng, RGB(250, 240, 160), UDim2.fromScale(0.54, 0.22), UDim2.fromScale(0.4, 0.34))
		frame(ng, RGB(200, 230, 255), UDim2.fromScale(0.54, 0.6), UDim2.fromScale(0.4, 0.32))
		text(ng, "TRAVAUX", RGB(160, 30, 30), Enum.Font.GothamBlack, UDim2.fromScale(0.08, 0.26), UDim2.fromScale(0.36, 0.12))
		marker("ClueNotice", at(10 + 2.5, 0, 31.5, WEST), { Clue = "notice" })
		-- hall decoration
		picture(hall, at(44 - 0.5 / M - 0.1, 8, 31.5, WEST), 5, 3.4, 51)
		picture(hall, at(10 + 0.5 / M + 0.1, 8, 22.2, EAST), 4, 3, 52)
		plant(hall, at(11, 0, 39), 1.3)
		plant(hall, at(22.6, 0, 39), 1.1)
		plant(hall, at(31.4, 0, 39), 1.1)
		plant(hall, at(43, 0, 21), 1.2)
		plant(hall, at(11, 0, 21), 1.2)
		local rate = P(hall, "RatesScreen", Vector3.new(7, 4, 0.2), at(44 - 0.5 / M - 0.1, 11, 22.2, WEST), RGB(20, 20, 24), MAT.SmoothPlastic, true)
		local rg = surf(rate, Enum.NormalId.Front, 40, true)
		local rbg = frame(rg, RGB(10, 40, 32), UDim2.fromScale(0.03, 0.05), UDim2.fromScale(0.94, 0.9))
		text(rbg, "TAUX DU JOUR", RGB(120, 240, 180), Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.2))
		for i, s in { "EPARGNE     2,50 %", "TERME 12M   3,10 %", "IMMOBILIER  4,25 %", "AUTO        5,40 %" } do
			text(rbg, s, C.white, Enum.Font.Code, UDim2.fromScale(0.08, 0.1 + i * 0.19), UDim2.fromScale(0.84, 0.15), Enum.TextXAlignment.Left)
		end
		camera(hall, at(43.5, H - 0.6, 20.6, math.rad(-135)))
		camera(hall, at(10.5, H - 0.6, 39.5, math.rad(45)))
		-- "staff only" over the central opening to the teller area
		P(hall, "OpeningHeader", Vector3.new(6 * M, H - 13, 1), at(27, 13 + (H - 13) / 2, 20), C.wallHall)
		local so = P(hall, "StaffOnly", Vector3.new(10, 1.4, 0.2), at(27, 14.2, 20 + 0.6 / M), RGB(160, 30, 30), MAT.SmoothPlastic, true)
		text(surf(so, Enum.NormalId.Back, 40, true), "PERSONNEL UNIQUEMENT", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8))
		for k = 0, 11 do
			P(hall, "FloorLine", Vector3.new(1.2, 0.05, 0.6), at(24.3 + k * 0.5, 0.03, 20.4),
				if k % 2 == 0 then RGB(240, 200, 30) else RGB(30, 30, 30), MAT.SmoothPlastic, true)
		end
	end

	---------------------------------------------------------------- teller counter (z = 20) + 06 TELLER WORK AREA
	do
		local tw = R["06"]
		local counter = folder(tw, "TellerCounter")
		local function cx(x: number, y: number, dz: number): CFrame
			return at(x, y, 20) * CFrame.new(0, 0, dz)
		end
		local windows = { { 12, 16, 1 }, { 18, 22, 2 }, { 32, 36, 3 }, { 38, 42, 4 } }
		for _, seg in { { 10, 24 }, { 30, 44 } } do
			local a, b = seg[1], seg[2]
			local mid, w = (a + b) / 2, (b - a) * M
			P(counter, "Body", Vector3.new(w, 3.6, 2.6), cx(mid, 1.8, 0), C.walnut, MAT.Wood)
			P(counter, "Top", Vector3.new(w, 0.25, 3.3), cx(mid, 3.72, 0.1), RGB(232, 228, 220), MAT.Marble)
			P(counter, "FrontInset", Vector3.new(w - 1.2, 2.6, 0.1), cx(mid, 1.8, 1.35), C.oak, MAT.Wood, true)
			P(counter, "Header", Vector3.new(w, H - 11, 1), cx(mid, 11 + (H - 11) / 2, -0.2), C.wallHall)
			P(counter, "Fascia", Vector3.new(w, 1, 0.3), cx(mid, 11, 0.4), C.walnut, MAT.Wood)
			-- solid wall between windows, glass over the windows
			local cur = a
			for _, wd in windows do
				if wd[1] >= a and wd[2] <= b then
					if wd[1] > cur then
						P(counter, "Pier", Vector3.new((wd[1] - cur) * M, 11 - 3.85, 1), cx((cur + wd[1]) / 2, 3.85 + (11 - 3.85) / 2, -0.2), C.wallHall)
					end
					local gl = P(counter, "Glass", Vector3.new((wd[2] - wd[1]) * M, 11 - 4.45, 0.25), cx((wd[1] + wd[2]) / 2, 4.45 + (11 - 4.45) / 2, -0.2), RGB(200, 225, 230), MAT.Glass)
					gl.Transparency = 0.7
					local i = wd[3]
					local wx = (wd[1] + wd[2]) / 2
					local ns = P(counter, "Number", Vector3.new(1.8, 1.8, 0.1), cx(wx, 12.5, 0.36), C.teal, MAT.SmoothPlastic, true)
					text(surf(ns, Enum.NormalId.Back, 50, true), tostring(i), C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.9))
					monitor(counter, cx(wx - 0.7, 3.97, -0.6), "GUICHET " .. i)
					P(counter, "CashDrawer", Vector3.new(2.4, 0.6, 0.2), cx(wx, 3.0, -1.35), RGB(70, 72, 78), MAT.Metal, true)
					P(counter, "CardTerminal", Vector3.new(0.6, 0.25, 0.9), cx(wx + 0.6, 3.97, 1.1), RGB(36, 36, 40), MAT.SmoothPlastic, true)
					local stool = folder(counter, "Stool")
					cyl(stool, "Base", 1.6, 0.2, cx(wx, 0.1, -3), RGB(50, 50, 54), MAT.Metal)
					cyl(stool, "Post", 0.25, 2.6, cx(wx, 1.3, -3), RGB(160, 160, 165), MAT.Metal, true)
					cyl(stool, "Seat", 1.6, 0.4, cx(wx, 2.8, -3), RGB(40, 44, 52), MAT.Fabric)
					marker("Teller" .. i, cx(wx, 0, -4) * CFrame.Angles(0, math.pi, 0), { Role = "Teller" })
					marker("TellerCustomer" .. i, cx(wx, 0, 3.6), { Role = "Customer" })
					cur = wd[2]
				end
			end
			if b > cur then
				P(counter, "Pier", Vector3.new((b - cur) * M, 11 - 3.85, 1), cx((cur + b) / 2, 3.85 + (11 - 3.85) / 2, -0.2), C.wallHall)
			end
		end
		local logoPanel = P(counter, "HallLogo", Vector3.new(26, 3.4, 0.1), cx(17, 15.2, 0.32), C.white, MAT.SmoothPlastic, true)
		logoPanel.Transparency = 1
		local lg = surf(logoPanel, Enum.NormalId.Back, 30)
		logo(lg, UDim2.fromScale(0.0, 0.0), UDim2.fromScale(0.13, 1))
		text(lg, "NOOBLA BANK", C.greenDark, Enum.Font.GothamBlack, UDim2.fromScale(0.15, 0.05), UDim2.fromScale(0.83, 0.9), Enum.TextXAlignment.Left)
		roomLights(lights, 0, 14, 44, 20, 7, 1)
		-- back office (x 0..10)
		cabinet(tw, at(0.8, 0, 17, EAST), 4, 4.4, 2.2, 4)
		cabinet(tw, at(0.8, 0, 15.2, EAST), 2.2, 4.4, 2.2, 4)
		local copier = folder(tw, "Copier")
		P(copier, "Body", Vector3.new(3, 3.4, 2.4), at(5, 1.7, 14 + 1.9 / M), RGB(225, 225, 222), MAT.SmoothPlastic)
		P(copier, "Lid", Vector3.new(3, 0.3, 2.4), at(5, 3.55, 14 + 1.9 / M), RGB(70, 72, 78), MAT.SmoothPlastic)
		desk(tw, at(5, 0, 18.4, SOUTH), 7, 3, C.oak, "BACK OFFICE")
		office(tw, at(5, 0, 17.4, SOUTH))
		camera(tw, at(43.5, H - 0.6, 14.5, math.rad(-120)))
		-- teller conversation (scouting clue: the keypad runs SecuLock v1 -> hack)
		marker("ClueTeller", cx(20, 0, 3.4), { Clue = "teller" })
	end

	---------------------------------------------------------------- 07 CASH / OPERATIONS
	do
		local co = R["07"]
		roomLights(lights, 44, 14, 54, 20, 2, 1, RGB(235, 245, 255))
		local t = folder(co, "CountingTable")
		P(t, "Top", Vector3.new(14, 0.3, 4), at(49, 3.0, 17.4), RGB(200, 202, 206), MAT.Metal)
		P(t, "Base", Vector3.new(12, 2.8, 3), at(49, 1.45, 17.4), RGB(80, 82, 86), MAT.Metal)
		for _, x in { 47, 51 } do
			local mcf = at(x, 3.15, 17.4)
			P(t, "CountingMachine", Vector3.new(2, 1.2, 1.6), mcf * CFrame.new(0, 0.6, 0), RGB(230, 230, 228), MAT.SmoothPlastic)
			P(t, "Display", Vector3.new(0.8, 0.35, 0.05), mcf * CFrame.new(0, 0.85, -0.81), RGB(40, 220, 120), MAT.Neon, true)
			for k = 0, 3 do
				cashStack(t, mcf * CFrame.new(-1.8, 0.25 + math.floor(k / 2) * 0.47, -0.6 + (k % 2) * 0.7))
			end
		end
		local safe = folder(co, "Safe")
		local scf = at(54 - 2.4 / M, 0, 18.4, WEST)
		P(safe, "Body", Vector3.new(4, 5.5, 3), scf * CFrame.new(0, 2.75, 0), RGB(54, 58, 62), MAT.Metal)
		P(safe, "Door", Vector3.new(3.4, 4.9, 0.2), scf * CFrame.new(0, 2.75, -1.55), RGB(70, 74, 80), MAT.Metal, true)
		-- armored-truck refill schedule (scouting clue for method 5)
		local sch = P(co, "RefillSchedule", Vector3.new(3, 4, 0.1), at(44 + 0.5 / M + 0.06, 7, 17, EAST), C.white, MAT.SmoothPlastic, true)
		local sg = surf(sch, Enum.NormalId.Front, 50)
		text(sg, "REMPLISSAGE COFFRE", RGB(30, 30, 30), Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.12))
		for i = 1, 5 do
			frame(sg, RGB(180, 180, 180), UDim2.fromScale(0.08, 0.15 + i * 0.14), UDim2.fromScale(0.84, 0.03))
		end
		camera(co, at(53.5, H - 0.6, 14.5, math.rad(-135)))
	end

	---------------------------------------------------------------- 09 MANAGER
	do
		local r = R["09"]
		roomLights(lights, 0, 0, 9, 8, 2, 2)
		desk(r, at(3, 0, 3.6, SOUTH), 8, 3.4, C.walnut, "DIRECTION")
		office(r, at(3, 0, 2.5, SOUTH), RGB(30, 30, 34))
		guestChair(r, at(2.2, 0, 5.1, NORTH), RGB(120, 40, 40))
		guestChair(r, at(3.8, 0, 5.1, NORTH), RGB(120, 40, 40))
		shelf(r, at(0.52, 0, 4.2, EAST), 8, 9, 1.4, 5, "books", C.walnut)
		plant(r, at(8.2, 0, 0.8), 1.1)
		cabinet(r, at(9 - 1.6 / M, 0, 2.2, WEST), 2, 4.2, 2, 4, RGB(70, 72, 78))
		picture(r, at(9 - 0.5 / M - 0.1, 8, 5.6, WEST), 4, 2.6, 21)
		P(r, "Rug", Vector3.new(10, 0.04, 7), at(3.2, 0.02, 4.5), RGB(120, 40, 44), MAT.Fabric, true)
		local np = P(r, "Nameplate", Vector3.new(2, 0.5, 0.1), at(3, 3.2, 3.6, SOUTH) * CFrame.new(0, 0, 1.6) * CFrame.Angles(0, math.pi, 0), RGB(200, 170, 80), MAT.Metal, true)
		text(surf(np, Enum.NormalId.Front, 80), "M. NOOBLA - DIRECTEUR", RGB(40, 30, 10), Enum.Font.GothamBold)
		marker("Manager", at(3, 0, 1.8, SOUTH), { Role = "Manager" })
		marker("ManagerWalk1", at(4.5, 0, 11, EAST), { Role = "ManagerWalk" })
		marker("ManagerWalk2", at(27, 0, 11, EAST), { Role = "ManagerWalk" })
		marker("ManagerWalk3", at(27, 0, 24, SOUTH), { Role = "ManagerWalk" })
		marker("ManagerWalk4", at(13.5, 0, 5, NORTH), { Role = "ManagerWalk" })
	end

	---------------------------------------------------------------- 10 MEETING
	do
		local r = R["10"]
		roomLights(lights, 9, 0, 18, 8, 2, 2)
		local t = folder(r, "MeetingTable")
		P(t, "Top", Vector3.new(14, 0.3, 5), at(13.5, 2.8, 4), RGB(238, 238, 234), MAT.SmoothPlastic)
		P(t, "Leg", Vector3.new(1, 2.7, 3), at(13.5, 1.35, 4) * CFrame.new(-4.5, 0, 0), RGB(60, 62, 66), MAT.Metal)
		P(t, "Leg", Vector3.new(1, 2.7, 3), at(13.5, 1.35, 4) * CFrame.new(4.5, 0, 0), RGB(60, 62, 66), MAT.Metal)
		for _, x in { 11.5, 13.5, 15.5 } do
			office(r, at(x, 0, 2.6, SOUTH), RGB(60, 64, 76))
			office(r, at(x, 0, 5.4, NORTH), RGB(60, 64, 76))
		end
		local tv = P(r, "TV", Vector3.new(8, 4.5, 0.25), at(9 + 0.5 / M + 0.14, 8, 4, EAST), RGB(18, 18, 20), MAT.SmoothPlastic, true)
		local tg = surf(tv, Enum.NormalId.Front, 40, true)
		local tbg = frame(tg, RGB(240, 244, 240), UDim2.fromScale(0.02, 0.03), UDim2.fromScale(0.96, 0.94))
		text(tbg, "BILAN TRIMESTRIEL", C.greenDark, Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.18))
		for i = 1, 5 do
			frame(tbg, C.green, UDim2.fromScale(0.1 + i * 0.14, 0.9 - i * 0.12), UDim2.fromScale(0.09, i * 0.12))
		end
		local wb = P(r, "Whiteboard", Vector3.new(8, 4, 0.15), at(18 - 0.5 / M - 0.1, 7.5, 4, WEST), RGB(250, 250, 250), MAT.SmoothPlastic, true)
		local wg = surf(wb, Enum.NormalId.Front, 40)
		text(wg, "OBJECTIF: +12% de clients", RGB(30, 60, 160), Enum.Font.PermanentMarker, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.25))
		text(wg, "Rappel: badge Nv.5 = directeur", RGB(170, 40, 40), Enum.Font.PermanentMarker, UDim2.fromScale(0.05, 0.45), UDim2.fromScale(0.9, 0.2))
		plant(r, at(17.2, 0, 0.8), 1.0)
	end

	---------------------------------------------------------------- 11 STAFF ROOM (window on the alley: vans load here)
	do
		local r = R["11"]
		roomLights(lights, 18, 0, 28, 8, 2, 2)
		local k = folder(r, "Kitchenette")
		local nz = (0.8 + 1.2) / M
		P(k, "Counter", Vector3.new(8, 3.2, 2.4), at(19.5, 1.6, nz), RGB(236, 236, 232), MAT.SmoothPlastic)
		P(k, "CounterTop", Vector3.new(8.2, 0.25, 2.6), at(19.5, 3.3, nz), RGB(60, 60, 64), MAT.Granite)
		P(k, "Sink", Vector3.new(2.2, 0.15, 1.5), at(19.8, 3.43, nz), RGB(190, 194, 200), MAT.Metal, true)
		local mw = P(k, "Microwave", Vector3.new(2, 1.2, 1.4), at(18.7, 4.03, nz), RGB(40, 40, 44), MAT.SmoothPlastic)
		P(k, "MicrowaveGlass", Vector3.new(1.2, 0.8, 0.05), mw.CFrame * CFrame.new(-0.25, 0, 0.71), RGB(20, 20, 20), MAT.Glass, true)
		P(k, "CoffeeMachine", Vector3.new(1, 1.5, 1.2), at(20.6, 4.2, nz), RGB(30, 30, 32), MAT.SmoothPlastic)
		local fr = P(k, "Fridge", Vector3.new(2.8, 6.4, 2.4), at(27 - 0.6 / M, 3.2, 2.05 / M), RGB(214, 216, 220), MAT.Metal)
		P(k, "FridgeHandle", Vector3.new(0.15, 1.6, 0.15), fr.CFrame * CFrame.new(-1.1, 0.6, 1.25), RGB(120, 120, 125), MAT.Metal, true)
		P(r, "BreakTable", Vector3.new(6, 0.3, 4), at(22.5, 2.8, 4.6), C.oak, MAT.Wood)
		cyl(r, "TableLeg", 0.6, 2.7, at(22.5, 1.35, 4.6), RGB(50, 50, 54), MAT.Metal)
		for _, o in { { 21.6, 3.5, SOUTH }, { 23.4, 3.5, SOUTH }, { 21.6, 5.7, NORTH }, { 23.4, 5.7, NORTH } } do
			guestChair(r, at(o[1], 0, o[2], o[3]), RGB(230, 140, 50))
		end
		for i = 0, 3 do
			local lcf = at(28 - 1.82 / M, 0, 6.0 + i * 0.4, WEST)
			P(r, "Locker", Vector3.new(1.15, 6.4, 1.6), lcf * CFrame.new(0, 3.2, 0), RGB(70, 110, 150), MAT.Metal)
			P(r, "LockerVent", Vector3.new(0.7, 0.6, 0.05), lcf * CFrame.new(0, 5.6, -0.82), RGB(50, 80, 110), MAT.Metal, true)
		end
		local sofa = folder(r, "Sofa")
		local scf = at(18 + 2.15 / M, 0, 5.2, EAST)
		P(sofa, "Seat", Vector3.new(6, 1.6, 2.4), scf * CFrame.new(0, 0.8, -0.3), RGB(70, 90, 110), MAT.Fabric)
		P(sofa, "Back", Vector3.new(6, 2.4, 0.7), scf * CFrame.new(0, 2.4, 0.8), RGB(70, 90, 110), MAT.Fabric)
		-- outside the staff-room window: a loading spot in the alley
		marker("LoadSpotStaffWindow", at(23.5, 0, -4, SOUTH), { Role = "LoadSpot" })
	end

	---------------------------------------------------------------- 13 IT, 14 RECORDS
	do
		local r = R["13"]
		roomLights(lights, 40, 0, 47, 8, 1, 2, RGB(220, 235, 255))
		for i = 0, 1 do
			local rcf = at(47 - (0.5 + 1.2) / M, 0, 2 + i * 3, WEST)
			local rack = P(r, "ServerRack", Vector3.new(2.2, 8, 2.2), rcf * CFrame.new(0, 4, 0), RGB(28, 30, 34), MAT.Metal)
			local g = surf(rack, Enum.NormalId.Front, 30, true)
			for u = 0, 10 do
				local rw = frame(g, RGB(50, 52, 58), UDim2.fromScale(0.08, 0.05 + u * 0.083), UDim2.fromScale(0.84, 0.065))
				for l = 0, 4 do
					local on = (u * 7 + l * 3 + i) % 4 ~= 0
					frame(rw, if on then (if l % 2 == 0 then RGB(60, 255, 120) else RGB(80, 170, 255)) else RGB(255, 170, 40),
						UDim2.fromScale(0.62 + l * 0.07, 0.3), UDim2.fromScale(0.04, 0.4), 1)
				end
			end
		end
		local note = P(r, "StickyNote", Vector3.new(0.8, 0.8, 0.05), at(47 - (0.5 + 2.4) / M, 6, 2, WEST), RGB(250, 240, 120), MAT.SmoothPlastic, true)
		text(surf(note, Enum.NormalId.Front, 60), "MAJ SECULOCK v1 ?!", RGB(40, 40, 40), Enum.Font.PermanentMarker)
		P(r, "UPS", Vector3.new(2, 2.2, 2.4), at(41.5, 1.1, 1.0), RGB(40, 40, 44), MAT.Metal)
		local rr = R["14"]
		roomLights(lights, 47, 0, 54, 8, 1, 2)
		shelf(rr, at(54 - 1.65 / M, 0, 3.6, WEST), 16, 9, 1.6, 5, "boxes")
		shelf(rr, at(47 + 1.35 / M, 0, 3.6, EAST), 14, 9, 1.6, 5, "binders")
	end

	---------------------------------------------------------------- 08 CORRIDOR
	do
		local r = R["08"]
		for i = 0, 8 do
			ceilingLight(lights, 3 + i * 6, 11, 3)
		end
		camera(r, at(0.5, H - 0.6, 8.6, math.rad(-120)))
		camera(r, at(53.5, H - 0.6, 8.6, math.rad(120)))
		for _, x in { 0, 54 } do
			local inside = if x == 0 then 0.95 / M else -0.95 / M
			local ex = P(r, "ExitSign", Vector3.new(3, 1.2, 0.3), at(x + inside, 12.5, 11, if x == 0 then EAST else WEST), RGB(245, 245, 245), MAT.SmoothPlastic, true)
			local g = surf(ex, Enum.NormalId.Front, 50, true)
			frame(g, RGB(0, 160, 80), UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84))
			text(g, "SORTIE", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.12), UDim2.fromScale(0.8, 0.76))
		end
		for _, x in { 16.5, 38.5 } do
			cyl(r, "Extinguisher", 0.7, 2, at(x, 2.4, 8 + 1.0 / M), RGB(200, 30, 30), MAT.SmoothPlastic, true)
		end
		door(doors, "Sortie ouest", "z", 0, 9, 13, 11, DOOR_STEEL, -1, true, 1.6)
		door(doors, "Sortie est", "z", 54, 9, 13, 11, DOOR_STEEL, 1, true, 1.6)
		marker("Guard2", at(40, 0, 11, WEST), { Role = "Guard" })
	end

	---------------------------------------------------------------- consult A/B, advisor, WC
	local function consult(id: string, x0: number, z0: number, label: string, pic: number)
		local r = R[id]
		roomLights(lights, x0, z0, x0 + 10, z0 + 10, 2, 2)
		local dx = x0 + 4.2
		desk(r, at(dx, 0, z0 + 4.5, SOUTH), 8, 3.2, C.oak, label)
		office(r, at(dx, 0, z0 + 3.4, SOUTH), RGB(30, 30, 34))
		guestChair(r, at(dx - 0.7, 0, z0 + 5.8, NORTH), RGB(0, 118, 76))
		guestChair(r, at(dx + 0.7, 0, z0 + 5.8, NORTH), RGB(0, 118, 76))
		plant(r, at(x0 + 0.9, 0, z0 + 9), 1.1)
		picture(r, at(dx, 8, z0 + 0.5 / M + 0.1, SOUTH), 4.5, 3, pic)
		cabinet(r, at(x0 + 8.8, 0, z0 + 0.9, SOUTH), 2.4, 3.2, 1.8, 3, RGB(200, 200, 196))
	end
	consult("02", 0, 20, "CONSEIL B", 31)
	consult("01", 0, 30, "CONSEIL A", 32)
	consult("05", 44, 20, "CONSEILLER", 33)
	do
		local r = R["04"]
		roomLights(lights, 44, 30, 54, 40, 2, 2)
		for i = 0, 1 do
			local z = 31.5 + i * 3.4
			P(r, "Stall", Vector3.new(0.3, 7, 9), at(50, 3.5, z + 1.7), RGB(120, 150, 170), MAT.SmoothPlastic)
			local tcf = at(54 - 1.75 / M, 0, z + 1.5, WEST)
			P(r, "Tank", Vector3.new(2, 1.6, 0.8), tcf * CFrame.new(0, 3.0, 0.5), C.white, MAT.SmoothPlastic)
			P(r, "Bowl", Vector3.new(1.6, 1.6, 2.2), tcf * CFrame.new(0, 0.8, -0.8), C.white, MAT.SmoothPlastic)
		end
		for i = 0, 1 do
			local scf = at(46 + i * 2, 0, 40 - 1.6 / M, NORTH)
			P(r, "Basin", Vector3.new(2.6, 0.6, 1.6), scf * CFrame.new(0, 2.7, 0), C.white, MAT.SmoothPlastic)
			local mir = P(r, "Mirror", Vector3.new(2.6, 3, 0.1), at(46 + i * 2, 6.0, 40 - 0.85 / M, NORTH), RGB(200, 214, 222), MAT.Glass, true)
			mir.Reflectance = 0.6
		end
	end

	---------------------------------------------------------------- restricted zones (staff only)
	local function restricted(name: string, x0: number, z0: number, x1: number, z1: number)
		local p = P(hooks, name, Vector3.new((x1 - x0) * M, H, (z1 - z0) * M), at((x0 + x1) / 2, H / 2, (z0 + z1) / 2), RGB(255, 0, 0), MAT.SmoothPlastic, true)
		p.Transparency = 1
		tag(p, "Restricted")
	end
	restricted("Restricted_Back", 0, 0, 54, 14)
	restricted("Restricted_Teller", 0, 14, 54, 20)

	---------------------------------------------------------------- facade (same style as the reference photo)
	do
		local fa = folder(root, "Facade")
		local OUTF = 0.8 / M
		local sides = { { "x", 0, -1, 0, 54 }, { "x", 40, 1, 0, 54 }, { "z", 0, -1, 0, 40 }, { "z", 54, 1, 0, 40 } }
		local boardH = (TOP - 1.6 - (BASE + 0.7)) / 8
		for _, sd in sides do
			local axis, f, dir, s, e = sd[1] :: string, sd[2] :: number, sd[3] :: number, sd[4] :: number, sd[5] :: number
			local len = (e - s) * M + 1.6 + 0.5
			local mid = (s + e) / 2
			local function place(y: number, outward: number): CFrame
				local fo = f + dir * (OUTF + outward / M)
				return if axis == "x" then at(mid, y, fo) else at(fo, y, mid)
			end
			local function sz(along: number, h: number, depth: number): Vector3
				return if axis == "x" then Vector3.new(along, h, depth) else Vector3.new(depth, h, along)
			end
			local y = BASE + 0.7
			local n = 0
			while y + boardH <= TOP - 1.55 do
				n += 1
				P(fa, "Siding", sz(len, boardH - 0.16, 0.3), place(y + boardH / 2, 0.15), if n % 2 == 0 then C.siding else C.siding2, MAT.Plaster)
				y += boardH
			end
			P(fa, "BaseLedge", sz(len + 0.4, 0.7, 1.1), place(BASE + 0.35, 0.45), RGB(150, 140, 126), MAT.Concrete)
			P(fa, "Cornice", sz(len + 1.2, 1.3, 1.6), place(TOP - 1.0, 0.7), C.cornice, MAT.Wood)
			P(fa, "Coping", sz(len + 1.6, 0.4, 3.4), place(TOP - 0.15, 0.3), RGB(80, 50, 38), MAT.Wood)
			local count = math.floor((e - s) * M / 18)
			for i = 0, count do
				local along = -((e - s) * M) / 2 + i * ((e - s) * M) / count
				local off = if axis == "x" then CFrame.new(along, 0, 0) else CFrame.new(0, 0, along)
				P(fa, "Pilaster", sz(1.9, TOP - 1.6 - BASE + 0.4, 1.2), place((BASE + TOP - 1.6) / 2 + 0.2, 0.6) * off, C.pilaster, MAT.Wood)
				P(fa, "PilasterFoot", sz(2.3, 0.5, 1.6), place(BASE + 0.9, 0.8) * off, RGB(70, 46, 34), MAT.Wood)
			end
		end
		-- entrance canopy + sign
		local ecf = at(27, 0, 40 + OUTF)
		P(fa, "Canopy", Vector3.new(24, 0.6, 7), ecf * CFrame.new(0, 12.4, 3.5), RGB(46, 48, 52), MAT.Metal)
		P(fa, "CanopyEdge", Vector3.new(24.2, 1, 0.3), ecf * CFrame.new(0, 12.3, 7), C.greenDark, MAT.Metal)
		local cl = P(fa, "CanopyLight", Vector3.new(14, 0.1, 2), ecf * CFrame.new(0, 12.07, 3.5), RGB(255, 240, 210), MAT.Neon, true)
		light(cl, "surface", 1.4, 16)
		P(fa, "EntranceSignTrim", Vector3.new(26.6, 6, 0.5), ecf * CFrame.new(0, 17.2, 0.7), RGB(235, 235, 230), MAT.SmoothPlastic)
		local sign = P(fa, "EntranceSign", Vector3.new(26, 5.4, 0.7), ecf * CFrame.new(0, 17.2, 1.0), C.green, MAT.SmoothPlastic)
		local sg = surf(sign, Enum.NormalId.Back, 18, true)
		logo(sg, UDim2.fromScale(0.03, 0.12), UDim2.fromScale(0.16, 0.76))
		text(sg, "NOOBLA BANK", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.22, 0.12), UDim2.fromScale(0.75, 0.56), Enum.TextXAlignment.Left)
		text(sg, "EPARGNE  -  PRETS  -  DISTRIBUTEURS", RGB(190, 240, 210), Enum.Font.GothamBold, UDim2.fromScale(0.22, 0.7), UDim2.fromScale(0.7, 0.18), Enum.TextXAlignment.Left)
		light(sign, "surface", 0.8, 12, RGB(160, 255, 200), Enum.NormalId.Back)
		local hours = P(fa, "Hours", Vector3.new(2.6, 3.2, 0.1), at(31.4, 5.5, 40 + OUTF + 0.06 / M, SOUTH), RGB(30, 34, 40), MAT.SmoothPlastic, true)
		local hg = surf(hours, Enum.NormalId.Front, 50)
		text(hg, "OUVERT", RGB(120, 240, 170), Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.22))
		text(hg, "LUN-VEN 9-17\nSAM 9-12", C.white, Enum.Font.Gotham, UDim2.fromScale(0.1, 0.36), UDim2.fromScale(0.8, 0.5))
		camera(fa, at(31.2, 10, 40 + OUTF + 0.4 / M, SOUTH))
		camera(fa, at(22, 10, -OUTF - 0.4 / M, NORTH))
	end

	---------------------------------------------------------------- rope spots (climb to the roof / down the vault hole)
	do
		local function rope(name: string, base: CFrame, top: CFrame, mode: string, label: string)
			local s = P(hooks, name, Vector3.new(3, 4, 1), base, RGB(160, 110, 60), MAT.SmoothPlastic, true)
			s.Transparency = 1
			s:SetAttribute("Mode", mode)
			s:SetAttribute("Top", top)
			tag(s, "RopeSpot")
			prompt(s, "RopePrompt", if mode == "Hole" then "Descendre en rappel" else "Grimper (corde)", label, 1, 8)
			return s
		end
		local roofY = H + 1.5
		-- climb spots: base outside the wall, top just inside the parapet
		rope("RopeAlley", at(19.5, 2, -1.5), at(19.5, roofY + 3, 1.5), "Climb", "Mur arrière (ruelle)")
		rope("RopeEast", at(55.5, 2, 4), at(52.5, roofY + 3, 4), "Climb", "Mur est (parking)")
		rope("RopeWest", at(-1.5, 2, 17), at(1.5, roofY + 3, 17), "Climb", "Mur ouest")
		-- the vault hole (enabled once the roof is blown): top on the roof, bottom in the vault
		local hole = rope("RopeHole", at(38, roofY + 2, 4), at(34, 0.5 + 3, 4), "Hole", "Trou du toit")
		hole.RopePrompt.Enabled = false
		-- the roof access hatch from the records room ladder is locked: no free way up
	end

	---------------------------------------------------------------- outside markers
	marker("Guard1", at(20, 0, 37, NORTH), { Role = "Guard" })
	marker("Customer1", at(14, 0, 33.2, SOUTH), { Role = "Customer" })
	marker("Customer2", at(36, 0, 38.5, NORTH), { Role = "Customer" })
	marker("Customer3", at(19.5, 0, 24, NORTH), { Role = "Customer" })
	marker("Customer4", at(40, 0, 30, NORTH), { Role = "Customer" })
	marker("ClueDumpster", at(12, 0, -6, SOUTH), { Clue = "dumpster" })
	marker("ClueManager", at(27, 0, 23.5, NORTH), { Clue = "manager" })
	marker("ClueCustomer", at(14, 0, 23.6, NORTH), { Clue = "locker167" })
	return root
end

------------------------------------------------------------------ site around the bank (ROOT-local studs)

local function buildSite(bank: Model)
	local s = folder(bank, "Site")
	local function L(x: number, y: number, z: number): CFrame
		return ROOT * CFrame.new(x, y, z)
	end
	local function ground(name: string, x0: number, z0: number, x1: number, z1: number, top: number, col: Color3, mat: Enum.Material, thick: number?)
		local t = thick or 1
		return P(s, name, Vector3.new(x1 - x0, t, z1 - z0), L((x0 + x1) / 2, top - t / 2, (z0 + z1) / 2), col, mat)
	end
	local CONC = RGB(196, 192, 184)
	ground("Sidewalk", -112, 60.8, 86, 78, FY, CONC, MAT.Concrete)
	ground("SidewalkWest", -112, -64, -81.8, 60.8, FY, CONC, MAT.Concrete)
	ground("RearStrip", -81.8, -64, 86, -60.8, FY, CONC, MAT.Concrete)
	ground("EastStrip", 81.8, -64, 86, 60.8, FY, CONC, MAT.Concrete)
	ground("Alley", -112, -100, 86, -64, 0.08, RGB(64, 66, 70), MAT.Asphalt, 0.2)
	ground("Parking", 86, -100, 160, 78, 0.08, RGB(60, 62, 66), MAT.Asphalt, 0.2)
	ground("Curb", -112, 77.6, 86, 78.4, FY + 0.05, RGB(220, 216, 208), MAT.Concrete)
	for k = 0, 7 do
		P(s, "StallLine", Vector3.new(0.4, 0.05, 16), L(96 + k * 9, 0.11, -30), RGB(235, 235, 235), MAT.SmoothPlastic, true)
		P(s, "StallLine", Vector3.new(0.4, 0.05, 16), L(96 + k * 9, 0.11, 20), RGB(235, 235, 235), MAT.SmoothPlastic, true)
	end
	-- hedges in planters along the front (entrance clear)
	for _, span in { { -78, -14 }, { 14, 78 } } do
		local a, b = span[1], span[2]
		local cfp = L((a + b) / 2, FY, 63.4)
		P(s, "Planter", Vector3.new(b - a, 1.2, 2.8), cfp * CFrame.new(0, 0.6, 0), RGB(170, 164, 154), MAT.Concrete)
		P(s, "Hedge", Vector3.new(b - a - 0.6, 2.2, 2.2), cfp * CFrame.new(0, 2.2, 0), RGB(58, 110, 48), MAT.Grass)
	end
	local function tree(cf: CFrame)
		local m = folder(s, "Tree")
		cyl(m, "Trunk", 1.2, 14, cf * CFrame.new(0, 7, 0), RGB(96, 72, 52), MAT.Wood)
		ball(m, "Crown", 10, cf * CFrame.new(0, 16, 0), RGB(66, 120, 56), MAT.Grass, true)
		ball(m, "Crown", 7, cf * CFrame.new(2.8, 14, 1.2), RGB(80, 138, 62), MAT.Grass, true)
		ball(m, "Crown", 6.5, cf * CFrame.new(-2.6, 14.6, -1.4), RGB(72, 128, 58), MAT.Grass, true)
	end
	for _, x in { -60, -30, 30, 60 } do
		tree(L(x, FY, 72))
	end
	for _, x in { -90, 0, 70 } do
		local cfp = L(x, FY, 76.5)
		cyl(s, "LampPole", 0.6, 22, cfp * CFrame.new(0, 11, 0), RGB(60, 62, 66), MAT.Metal)
		P(s, "LampArm", Vector3.new(0.4, 0.4, 5), cfp * CFrame.new(0, 21.8, 2.4), RGB(60, 62, 66), MAT.Metal, true)
		local head = P(s, "LampHead", Vector3.new(1.6, 0.5, 2.6), cfp * CFrame.new(0, 21.6, 4.8), RGB(240, 230, 200), MAT.Neon, true)
		light(head, "spot", 2, 32, RGB(255, 226, 180), Enum.NormalId.Bottom)
	end
	for k = -3, 3 do
		if math.abs(k) > 0 then
			cyl(s, "Bollard", 1, 3, L(k * 4, FY + 1.5, 75), RGB(60, 62, 66), MAT.Metal)
		end
	end
	-- green sign pylon
	local py = folder(s, "PylonSign")
	local pcf = L(98, 0.1, 70)
	P(py, "Footing", Vector3.new(4, 1.2, 4), pcf * CFrame.new(0, 0.6, 0), RGB(170, 164, 154), MAT.Concrete)
	P(py, "Pole", Vector3.new(1.8, 26, 1.8), pcf * CFrame.new(0, 13, 0), RGB(70, 74, 80), MAT.Metal)
	P(py, "SignBox", Vector3.new(2, 15, 11), pcf * CFrame.new(0, 32, 0), C.greenDark, MAT.SmoothPlastic)
	for side = -1, 1, 2 do
		local face = P(py, "SignFace", Vector3.new(0.1, 14, 10.2), pcf * CFrame.new(side * 1.03, 32, 0), C.green, MAT.SmoothPlastic, true)
		local g = surf(face, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, 11, true)
		logo(g, UDim2.fromScale(0.18, 0.06), UDim2.fromScale(0.64, 0.42))
		text(g, "NOOBLA", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.06, 0.54), UDim2.fromScale(0.88, 0.2))
		text(g, "BANK", RGB(200, 255, 220), Enum.Font.GothamBold, UDim2.fromScale(0.2, 0.77), UDim2.fromScale(0.6, 0.15))
	end
	py:PivotTo(py:GetPivot() * CFrame.Angles(0, math.rad(-35), 0))
	-- flag pole
	local fp = folder(s, "FlagPole")
	local fcf = L(-98, FY, 70)
	cyl(fp, "Pole", 0.5, 36, fcf * CFrame.new(0, 18, 0), RGB(225, 225, 228), MAT.Metal)
	local flag = P(fp, "Flag", Vector3.new(8, 4.6, 0.08), fcf * CFrame.new(4.25, 33.6, 0), C.white, MAT.Fabric, true)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local g = surf(flag, face, 20)
		for k = 0, 12 do
			frame(g, if k % 2 == 0 then RGB(178, 34, 52) else C.white, UDim2.fromScale(0, k / 13), UDim2.fromScale(1, 1 / 13 + 0.002))
		end
		local canton = frame(g, RGB(60, 59, 110), UDim2.fromScale(if face == Enum.NormalId.Front then 0 else 0.6, 0), UDim2.fromScale(0.4, 7 / 13))
		for r2 = 0, 4 do
			for c2 = 0, 5 do
				frame(canton, C.white, UDim2.fromScale(0.07 + c2 * 0.155, 0.08 + r2 * 0.19), UDim2.fromScale(0.05, 0.08), 1)
			end
		end
	end
	-- dumpster in the alley (scouting clue: maintenance invoice -> the vault door can be drilled)
	local dm = folder(s, "Dumpster")
	local dcf = L(-45, 0.1, -84)
	P(dm, "Bin", Vector3.new(10, 5.5, 5.5), dcf * CFrame.new(0, 2.75, 0), RGB(30, 90, 60), MAT.Metal)
	P(dm, "Lid", Vector3.new(10.2, 0.3, 5.7), dcf * CFrame.new(0, 5.65, 0) * CFrame.Angles(math.rad(-6), 0, 0), RGB(30, 30, 32), MAT.Plastic)
	for k = 0, 2 do
		P(dm, "TrashBag", Vector3.new(2.2, 1.8, 2), dcf * CFrame.new(-6.5 - k * 1.2, 0.9, 2 - k * 1.5) * CFrame.Angles(0, k, 0), RGB(25, 25, 28), MAT.Plastic, true)
	end
	-- armored truck parked by the parking (scouting clue for method 5)
	local tr = folder(s, "ArmoredTruck")
	local tcf = L(112, 0.1, 50)
	P(tr, "Box", Vector3.new(8, 8, 14), tcf * CFrame.new(0, 5, 2), RGB(120, 126, 132), MAT.DiamondPlate)
	P(tr, "Cab", Vector3.new(8, 6, 6), tcf * CFrame.new(0, 4, -8), RGB(110, 116, 122), MAT.Metal)
	local ws = P(tr, "Windshield", Vector3.new(7, 2.2, 0.2), tcf * CFrame.new(0, 5.6, -11), RGB(30, 40, 46), MAT.Glass, true)
	ws.Transparency = 0.2
	for _, o in { Vector3.new(4, 0, -8), Vector3.new(-4, 0, -8), Vector3.new(4, 0, 5), Vector3.new(-4, 0, 5) } do
		local w = P(tr, "Wheel", Vector3.new(1, 3, 3), tcf * CFrame.new(o.X, 1.5, o.Z), RGB(25, 25, 25), MAT.Rubber)
		w.Shape = Enum.PartType.Cylinder
	end
	local ts = P(tr, "Logo", Vector3.new(0.1, 3, 8), tcf * CFrame.new(4.06, 6, 2), C.green, MAT.SmoothPlastic, true)
	text(surf(ts, Enum.NormalId.Right, 30), "NOOBLA TRANSFERTS", C.white, Enum.Font.GothamBlack)
	markers.Parent = bank
	local m = marker("ClueTruck", L(104, FY, 50) * CFrame.Angles(0, -math.pi / 2, 0), { Clue = "truck" })
	local _ = m
	-- where the crew appears for a scouting trip / the heist, and where police cars come from
	marker("HeistStart", L(-100, FY, 70) * CFrame.Angles(0, math.pi / 2, 0), { Role = "Start" })
	marker("PoliceSpawn1", L(-260, 0.1, 90) * CFrame.Angles(0, -math.pi / 2, 0), { Role = "Police" })
	marker("PoliceSpawn2", L(260, 0.1, 90) * CFrame.Angles(0, math.pi / 2, 0), { Role = "Police" })
	marker("PoliceStage", L(0, FY, 72), { Role = "PoliceStage" })
end

------------------------------------------------------------------ roads (world coordinates)

local function buildRoads(): Model
	local r = Instance.new("Model")
	r.Name = "HeistRoads"
	local ASPH = RGB(52, 54, 58)
	-- the bank street: ROOT-local z 78..104 -> world z 182..156
	P(r, "BankStreet", Vector3.new(640, 0.2, 26), CFrame.new(0, -0.02, 169), ASPH, MAT.Asphalt)
	for k = 0, 31 do
		P(r, "LaneDash", Vector3.new(9, 0.05, 0.6), CFrame.new(-300 + k * 20, 0.105, 169), RGB(240, 200, 40), MAT.SmoothPlastic, true)
	end
	P(r, "FarSidewalk", Vector3.new(640, 1, 10), CFrame.new(0, 0, 151), RGB(196, 192, 184), MAT.Concrete)
	-- road to the hideout
	P(r, "HideoutRoad", Vector3.new(24, 0.2, 128), CFrame.new(-170, -0.02, 92), ASPH, MAT.Asphalt)
	for k = 0, 5 do
		P(r, "LaneDash", Vector3.new(0.6, 0.05, 9), CFrame.new(-170, 0.105, 40 + k * 20), RGB(240, 200, 40), MAT.SmoothPlastic, true)
	end
	return r
end

------------------------------------------------------------------ hideout (world coordinates)

local function buildHideout(): Model
	local h = Instance.new("Model")
	h.Name = "Hideout"
	local O = CFrame.new(-170, 0, 0) -- centre of the warehouse floor
	local W, D, HT = 70, 56, 22
	local WALL = RGB(64, 92, 70)
	P(h, "Floor", Vector3.new(W, 1, D), O * CFrame.new(0, 0, 0), RGB(120, 120, 116), MAT.Concrete)
	-- walls: back (-Z), sides, front (+Z) with a big garage opening x -16..16
	P(h, "WallBack", Vector3.new(W, HT, 1.5), O * CFrame.new(0, HT / 2, -D / 2), WALL, MAT.Metal)
	P(h, "WallWest", Vector3.new(1.5, HT, D), O * CFrame.new(-W / 2, HT / 2, 0), WALL, MAT.Metal)
	P(h, "WallEast", Vector3.new(1.5, HT, D), O * CFrame.new(W / 2, HT / 2, 0), WALL, MAT.Metal)
	P(h, "WallFrontL", Vector3.new(W / 2 - 16, HT, 1.5), O * CFrame.new(-(16 + (W / 2 - 16) / 2), HT / 2, D / 2), WALL, MAT.Metal)
	P(h, "WallFrontR", Vector3.new(W / 2 - 16, HT, 1.5), O * CFrame.new(16 + (W / 2 - 16) / 2, HT / 2, D / 2), WALL, MAT.Metal)
	P(h, "WallFrontTop", Vector3.new(32, HT - 16, 1.5), O * CFrame.new(0, 16 + (HT - 16) / 2, D / 2), WALL, MAT.Metal)
	P(h, "Roof", Vector3.new(W + 2, 1, D + 2), O * CFrame.new(0, HT + 0.5, 0), RGB(70, 72, 76), MAT.Metal)
	-- roll-up door rolled open + yellow frame
	P(h, "DoorRoll", Vector3.new(33, 2.2, 2.2), O * CFrame.new(0, 17, D / 2 + 0.5), RGB(150, 150, 146), MAT.Metal)
	for sx = -1, 1, 2 do
		P(h, "DoorFrame", Vector3.new(0.8, 16, 1.8), O * CFrame.new(sx * 16.4, 8, D / 2), RGB(230, 190, 30), MAT.Metal)
	end
	-- big sign over the garage
	local sign = P(h, "Sign", Vector3.new(24, 4, 0.6), O * CFrame.new(0, 19.6, D / 2 + 1.1), RGB(30, 30, 34), MAT.SmoothPlastic)
	local sg = surf(sign, Enum.NormalId.Back, 20, true)
	text(sg, "LA PLANQUE", RGB(255, 210, 40), Enum.Font.Arcade, UDim2.fromScale(0.03, 0.08), UDim2.fromScale(0.94, 0.84))
	-- lights
	for _, o in { Vector3.new(-18, 0, -12), Vector3.new(18, 0, -12), Vector3.new(-18, 0, 12), Vector3.new(18, 0, 12) } do
		local lamp = P(h, "Lamp", Vector3.new(4, 0.6, 4), O * CFrame.new(o.X, HT - 1, o.Z), RGB(255, 230, 180), MAT.Neon, true)
		cyl(h, "LampCord", 0.15, 1, O * CFrame.new(o.X, HT - 0.4, o.Z), RGB(30, 30, 30), MAT.Metal, true)
		light(lamp, "point", 1.2, 30, RGB(255, 220, 170))
	end
	-- garage drop zone (escape zone): yellow/black border, invisible volume
	local zone = P(h, "EscapeZone", Vector3.new(30, 14, 26), O * CFrame.new(0, 7.5, 14), RGB(255, 210, 40), MAT.SmoothPlastic, true)
	zone.Transparency = 1
	CollectionService:AddTag(zone, "EscapeZone")
	for k = 0, 29 do
		local col = if k % 2 == 0 then RGB(240, 200, 30) else RGB(30, 30, 30)
		P(h, "Stripe", Vector3.new(1, 0.05, 1), O * CFrame.new(-14.5 + k, 0.53, 1.5), col, MAT.SmoothPlastic, true)
	end
	local zl = P(h, "ZoneLabel", Vector3.new(16, 0.05, 4), O * CFrame.new(0, 0.54, 6), RGB(240, 200, 30), MAT.SmoothPlastic, true)
	zl.Transparency = 1
	text(surf(zl, Enum.NormalId.Top, 20), "ZONE DE DEPOT", RGB(255, 210, 40), Enum.Font.Arcade)
	-- planning table (opens the planner)
	local pt = folder(h, "PlanningTable")
	local tcf = O * CFrame.new(18, 0, -12)
	P(pt, "Top", Vector3.new(14, 0.6, 9), tcf * CFrame.new(0, 3.3, 0), RGB(110, 76, 50), MAT.Wood)
	for _, o in { Vector3.new(6, 0, 3.6), Vector3.new(-6, 0, 3.6), Vector3.new(6, 0, -3.6), Vector3.new(-6, 0, -3.6) } do
		P(pt, "Leg", Vector3.new(0.8, 3, 0.8), tcf * CFrame.new(o.X, 1.5, o.Z), RGB(90, 60, 40), MAT.Wood)
	end
	local bp = P(pt, "Blueprint", Vector3.new(12, 0.05, 7.4), tcf * CFrame.new(0, 3.63, 0), RGB(40, 90, 170), MAT.SmoothPlastic, true)
	local bg = surf(bp, Enum.NormalId.Top, 20)
	for i = 1, 11 do
		frame(bg, RGB(120, 170, 240), UDim2.fromScale(i / 12, 0), UDim2.fromScale(0.004, 1))
	end
	for i = 1, 6 do
		frame(bg, RGB(120, 170, 240), UDim2.fromScale(0, i / 7), UDim2.fromScale(1, 0.006))
	end
	text(bg, "NOOBLA BANK", C.white, Enum.Font.Arcade, UDim2.fromScale(0.1, 0.35), UDim2.fromScale(0.8, 0.3))
	local tl = P(pt, "TableLamp", Vector3.new(3, 1, 3), tcf * CFrame.new(0, 11, 0), RGB(40, 120, 60), MAT.Metal, true)
	cyl(pt, "LampCord", 0.12, 9, tcf * CFrame.new(0, 16, 0), RGB(30, 30, 30), MAT.Metal, true)
	light(tl, "spot", 2, 20, RGB(255, 236, 200), Enum.NormalId.Bottom)
	local ptAnchor = P(pt, "PromptAnchor", Vector3.new(1, 1, 1), tcf * CFrame.new(0, 4, 0), C.white, MAT.SmoothPlastic, true)
	ptAnchor.Transparency = 1
	prompt(ptAnchor, "PlanPrompt", "Planifier", "Table de planification", 0, 12)
	CollectionService:AddTag(ptAnchor, "PlannerTable")
	-- equipment locker wall (inventory)
	local eq = folder(h, "EquipmentWall")
	local ecf = O * CFrame.new(-W / 2 + 1.6, 0, -10) * CFrame.Angles(0, -math.pi / 2, 0)
	for i = 0, 5 do
		local lcf = ecf * CFrame.new(-7.5 + i * 3, 0, 0)
		P(eq, "Locker", Vector3.new(2.8, 9, 2), lcf * CFrame.new(0, 4.5, 0), RGB(40, 60, 120), MAT.Metal)
		P(eq, "Vent", Vector3.new(1.6, 1, 0.1), lcf * CFrame.new(0, 7.6, -1.02), RGB(25, 40, 90), MAT.Metal, true)
		P(eq, "Handle", Vector3.new(0.2, 1, 0.2), lcf * CFrame.new(0.9, 4.5, -1.1), RGB(220, 220, 225), MAT.Metal, true)
	end
	local rack = P(eq, "GunRack", Vector3.new(14, 6, 0.5), ecf * CFrame.new(0, 13, 0.6), RGB(90, 60, 40), MAT.Wood)
	local _ = rack
	local eqAnchor = P(eq, "PromptAnchor", Vector3.new(1, 1, 1), ecf * CFrame.new(0, 4, -3), C.white, MAT.SmoothPlastic, true)
	eqAnchor.Transparency = 1
	prompt(eqAnchor, "InvPrompt", "Inventaire", "Casiers d'équipement", 0, 12)
	CollectionService:AddTag(eqAnchor, "InventoryLocker")
	-- scouting board (photos + red strings) on the back wall
	local sb = folder(h, "ScoutBoard")
	local scf = O * CFrame.new(-14, 0, -D / 2 + 1)
	local board = P(sb, "Board", Vector3.new(16, 9, 0.5), scf * CFrame.new(0, 8, 0), RGB(170, 130, 90), MAT.Fabric)
	local bgs = surf(board, Enum.NormalId.Back, 20)
	for i = 0, 5 do
		frame(bgs, C.white, UDim2.fromScale(0.05 + (i % 3) * 0.32, 0.1 + math.floor(i / 3) * 0.45), UDim2.fromScale(0.24, 0.34))
	end
	text(bgs, "REPERAGE", RGB(160, 30, 30), Enum.Font.Arcade, UDim2.fromScale(0.25, 0.42), UDim2.fromScale(0.5, 0.16))
	for i = 0, 3 do
		P(sb, "String", Vector3.new(0.08, 0.08, 6), scf * CFrame.new(-4 + i * 2.6, 8 + (i % 2) * 1.5, 0.35) * CFrame.Angles(0, math.pi / 2, math.rad(15 - i * 10)), RGB(200, 20, 20), MAT.Fabric, true)
	end
	local sbAnchor = P(sb, "PromptAnchor", Vector3.new(1, 1, 1), scf * CFrame.new(0, 4, 3), C.white, MAT.SmoothPlastic, true)
	sbAnchor.Transparency = 1
	prompt(sbAnchor, "ScoutPrompt", "Partir en repérage", "Tableau de repérage", 0, 12)
	CollectionService:AddTag(sbAnchor, "ScoutBoard")
	-- lounge: couch, TV, crates, workbench
	local lounge = folder(h, "Lounge")
	local lc = O * CFrame.new(-22, 0, 10) * CFrame.Angles(0, math.pi / 2, 0)
	P(lounge, "CouchSeat", Vector3.new(10, 2, 3.4), lc * CFrame.new(0, 1, 0), RGB(140, 50, 40), MAT.Fabric)
	P(lounge, "CouchBack", Vector3.new(10, 3, 1), lc * CFrame.new(0, 3, 1.4), RGB(140, 50, 40), MAT.Fabric)
	local tv = P(lounge, "TV", Vector3.new(7, 4, 0.5), O * CFrame.new(-32.5, 6, 10) * CFrame.Angles(0, -math.pi / 2, 0), RGB(20, 20, 22), MAT.SmoothPlastic)
	local tg = surf(tv, Enum.NormalId.Front, 30, true)
	frame(tg, RGB(30, 80, 160), UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.84))
	text(tg, "INFO: BANQUE NOOBLA\nRECORD D'EPARGNE", C.white, Enum.Font.Arcade, UDim2.fromScale(0.08, 0.2), UDim2.fromScale(0.84, 0.6))
	for i = 0, 4 do
		P(lounge, "Crate", Vector3.new(4, 4, 4), O * CFrame.new(26 + (i % 2) * 4.2, 2 + math.floor(i / 2) * 4, 18 - (i % 3) * 4.2) * CFrame.Angles(0, i * 0.2, 0), RGB(150, 110, 60), MAT.WoodPlanks)
	end
	P(lounge, "Workbench", Vector3.new(12, 3.4, 3.6), O * CFrame.new(18, 1.7, -D / 2 + 3), RGB(110, 80, 56), MAT.Wood)
	P(lounge, "Pegboard", Vector3.new(12, 6, 0.3), O * CFrame.new(18, 7, -D / 2 + 1), RGB(200, 170, 120), MAT.Wood, true)
	-- money display: the crew's cash pile grows with total earnings (HeistServer updates it)
	local pile = P(h, "CashPile", Vector3.new(6, 0.5, 4), O * CFrame.new(28, 0.75, -4), C.cash, MAT.SmoothPlastic, true)
	pile:SetAttribute("BaseCF", pile.CFrame)
	return h
end

------------------------------------------------------------------ entry

local function build(): string
	for _, n in { "AtlasBank", "NooblaBank", "Hideout", "HeistRoads" } do
		local old = workspace:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local bank = buildBank()
	buildSite(bank)
	bank.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	bank.Parent = workspace
	local roads = buildRoads()
	roads.Parent = workspace
	local hide = buildHideout()
	hide.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	hide.Parent = workspace
	local n = 0
	for _, d in bank:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return string.format("NooblaBank %d parts, lockers %d, C4 spots %d, ropes %d, markers %d", n,
		#CollectionService:GetTagged("Locker"), #CollectionService:GetTagged("C4Spot"),
		#CollectionService:GetTagged("RopeSpot"), #CollectionService:GetTagged("HeistMarker"))
end

return build
