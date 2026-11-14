--!strict
-- AtlasBankBuilder: builds workspace.AtlasBank, a one-floor bank branch.
--   Interior = the "ATLAS BANK - 01 / floor plan" (30 x 20 m, 14 rooms, 4 tellers, vault, 3 ATMs).
--   Exterior = cream horizontal siding between dark-brown pilasters, stone base, green sign pylon,
--   flag pole, hedges, sidewalk, street and a small parking lot.
-- Run from Edit mode (re-running replaces the old build):
--   require(game.ServerStorage.Builders.AtlasBankBuilder:Clone())()
-- Plan coordinates are metres: x east 0..30, z south 0..20 (north = -Z), 1 m = 3 studs.
-- Doors are Models tagged "BankDoor" (ServerScriptService.Bank.BankDoors opens/closes them).

local CollectionService = game:GetService("CollectionService")

local M = 3 -- studs per metre
local FY = 0.5 -- floor top (studs)
local H = 14 -- ceiling height above the floor
local TOP = 21 -- parapet top above the floor
local BASE = 9 -- height of the stone base band
local ROOT = CFrame.new(0, 0, 150) * CFrame.Angles(0, math.pi, 0) -- entrance faces the spawn (-Z world)
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
	return ROOT * CFrame.new(x * M - 45, FY + y, z * M - 30) * CFrame.Angles(0, rot or 0, 0)
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

------------------------------------------------------------------ build

local function build()
	local old = workspace:FindFirstChild("AtlasBank")
	if old then
		old:Destroy()
	end
	root = Instance.new("Model")
	root.Name = "AtlasBank"
	root:SetAttribute("Plan", "Atlas Bank ground floor, 30 x 20 m, 1 m = 3 studs")
	local shell = folder(root, "Shell")
	local rooms = folder(root, "Rooms")
	local doors = folder(root, "Doors")
	local site = folder(root, "Site")
	local lights = folder(root, "Lights")

	---------------------------------------------------------------- floors (one per room, from the plan)
	local floorSpec = {
		{ "09 Manager", 0, 0, 5, 7, RGB(78, 84, 98), MAT.Carpet },
		{ "10 Meeting", 5, 0, 10, 7, RGB(78, 84, 98), MAT.Carpet },
		{ "11 Staff Room", 10, 0, 16, 7, RGB(168, 128, 90), MAT.WoodPlanks },
		{ "12 Vault", 16, 0, 24, 7, RGB(112, 114, 120), MAT.DiamondPlate },
		{ "13 IT Services", 24, 0, 27, 7, RGB(150, 152, 156), MAT.SmoothPlastic },
		{ "14 Store Records", 27, 0, 30, 7, RGB(150, 152, 156), MAT.SmoothPlastic },
		{ "08 Staff Corridor", 0, 7, 30, 9, RGB(134, 142, 152), MAT.Plastic },
		{ "06 Teller Work Area", 0, 9, 20, 12, RGB(120, 110, 100), MAT.Carpet },
		{ "07 Cash Operations", 20, 9, 30, 12, RGB(150, 152, 156), MAT.SmoothPlastic },
		{ "02 Consultation B", 0, 12, 6, 16, RGB(92, 98, 112), MAT.Carpet },
		{ "01 Consultation A", 0, 16, 6, 20, RGB(92, 98, 112), MAT.Carpet },
		{ "03 Banking Hall", 6, 12, 24, 20, RGB(232, 226, 214), MAT.Marble },
		{ "05 Advisor Office", 24, 12, 30, 16, RGB(92, 98, 112), MAT.Carpet },
		{ "04 Customer WC", 24, 16, 30, 20, RGB(222, 226, 228), MAT.CeramicTiles },
	}
	local roomModels: { [string]: Model } = {}
	for _, r in floorSpec do
		local name, x0, z0, x1, z1 = r[1] :: string, r[2] :: number, r[3] :: number, r[4] :: number, r[5] :: number
		local rm = folder(rooms, name)
		roomModels[string.sub(name, 1, 2)] = rm
		local f = P(rm, "Floor", Vector3.new((x1 - x0) * M, 1, (z1 - z0) * M), at((x0 + x1) / 2, -0.5, (z0 + z1) / 2), r[6] :: Color3, r[7] :: Enum.Material)
		f:SetAttribute("Room", name)
	end
	local R = function(id: string): Model
		return roomModels[id]
	end
	-- foundation under the wall line
	P(shell, "Foundation", Vector3.new(30 * M + 4, 1, 20 * M + 4), at(15, -1.1, 10), C.stoneDark, MAT.Concrete)

	---------------------------------------------------------------- exterior walls (inner + outer layer)
	local IN, OUT = 0.4 / M, 0.4 / M -- layer centre offsets in metres
	local function ext(axis: string, f: number, dir: number, s: number, e: number, ops: { Op })
		-- inner layer: interior colour to the ceiling, then concrete parapet face
		local inOps: { Op } = {}
		for _, o in ops do
			table.insert(inOps, { a = o.a, b = o.b, top = o.top, sill = o.sill })
		end
		wall(shell, axis, f - dir * IN, s, e, 0, H, 0.8, inOps, C.wallHall, MAT.SmoothPlastic, 0, true)
		wall(shell, axis, f - dir * IN, s, e, H, TOP - 0.6, 0.8, {}, RGB(150, 146, 140), MAT.Concrete, 0)
		-- outer layer: stone base with the openings, siding backer above
		local outOps = table.clone(ops)
		wall(shell, axis, f + dir * OUT, s, e, -FY, BASE, 0.8, outOps, C.stone, MAT.Slate, 0.8)
		wall(shell, axis, f + dir * OUT, s, e, BASE, TOP, 0.8, {}, C.sidingGap, MAT.SmoothPlastic, 0.8)
	end
	ext("x", 0, -1, 0, 30, { -- north (rear)
		{ a = 1, b = 4, sill = 3, top = 8, glass = true },
		{ a = 6.2, b = 8.8, sill = 3, top = 8, glass = true },
		{ a = 12, b = 14, sill = 5, top = 8, glass = true },
	})
	ext("x", 20, 1, 0, 30, { -- south (street front)
		{ a = 1, b = 5, sill = 3, top = 8, glass = true },
		{ a = 7, b = 12.6, sill = 3, top = 8, glass = true },
		{ a = 13.6, b = 16.4, top = 9 },
		{ a = 26.5, b = 28.5, sill = 5, top = 8, glass = true, frosted = true },
	})
	ext("z", 0, -1, 0, 20, { -- west
		{ a = 7.3, b = 8.7, top = 8.5 },
		{ a = 13, b = 15, sill = 3, top = 8, glass = true },
		{ a = 17, b = 19, sill = 3, top = 8, glass = true },
	})
	ext("z", 30, 1, 0, 20, { -- east
		{ a = 7.3, b = 8.7, top = 8.5 },
		{ a = 13, b = 15, sill = 3, top = 8, glass = true },
	})

	---------------------------------------------------------------- interior walls
	local IW = 0.8
	local function iw(axis: string, f: number, s: number, e: number, ops: { Op }, color: Color3?, th: number?, mat: Enum.Material?)
		wall(shell, axis, f, s, e, 0, H, th or IW, ops, color or C.wallStaff, mat or MAT.SmoothPlastic)
	end
	local DH = 8.5 -- interior door height
	-- rear rooms / corridor line z = 7
	iw("x", 7, 0, 16, { { a = 3.2, b = 4.6, top = DH }, { a = 6.0, b = 7.4, top = DH }, { a = 11.6, b = 13.0, top = DH } })
	iw("x", 7, 16, 24, { { a = 17.2, b = 20.0, top = 9 } }, C.wallVault, 1.6, MAT.Concrete)
	iw("x", 7, 24, 30, { { a = 24.9, b = 26.3, top = DH }, { a = 28.0, b = 29.4, top = DH } })
	iw("z", 5, 0, 7, {})
	iw("z", 10, 0, 7, {})
	iw("z", 16, 0, 7, {}, C.wallVault, 1.6, MAT.Concrete)
	iw("z", 24, 0, 7, {}, C.wallVault, 1.6, MAT.Concrete)
	iw("z", 27, 0, 7, {})
	-- corridor south line z = 9
	iw("x", 9, 0, 30, { { a = 1.0, b = 2.4, top = DH }, { a = 21.2, b = 22.6, top = DH } })
	-- teller / cash ops divider
	iw("z", 20, 9, 12, { { a = 10.2, b = 11.6, top = DH } })
	-- line z = 12 (the 6..20 part is the teller counter, built below)
	iw("x", 12, 0, 6, {}, C.wallHall)
	iw("x", 12, 20, 30, {}, C.wallHall)
	-- consultation rooms / hall
	iw("z", 6, 12, 20, { { a = 13.4, b = 14.8, top = DH }, { a = 17.4, b = 18.8, top = DH } }, C.wallHall)
	iw("x", 16, 0, 6, {}, C.wallHall)
	-- advisor / WC / hall
	iw("z", 24, 12, 20, { { a = 13.0, b = 14.4, top = DH }, { a = 16.6, b = 18.0, top = DH } }, C.wallHall)
	iw("x", 16, 24, 30, {}, C.wallHall)

	---------------------------------------------------------------- ceiling + roof
	P(shell, "Ceiling", Vector3.new(30 * M, 0.5, 20 * M), at(15, H + 0.25, 10), C.ceiling, MAT.SmoothPlastic)
	P(shell, "Roof", Vector3.new(30 * M, 1, 20 * M), at(15, H + 1, 10), RGB(120, 118, 114), MAT.Pebble)

	---------------------------------------------------------------- doors
	door(doors, "09 Manager", "x", 7, 3.2, 4.6, DH, DOOR_WOOD, 1)
	door(doors, "10 Meeting", "x", 7, 6.0, 7.4, DH, DOOR_WOOD, 1)
	door(doors, "11 Staff Room", "x", 7, 11.6, 13.0, DH, DOOR_STAFF, 1)
	door(doors, "13 IT Services", "x", 7, 24.9, 26.3, DH, DOOR_STEEL, 1)
	door(doors, "14 Store Records", "x", 7, 28.0, 29.4, DH, DOOR_STAFF, 1)
	door(doors, "06 Teller Work Area", "x", 9, 1.0, 2.4, DH, DOOR_STAFF, -1)
	door(doors, "07 Cash Operations", "x", 9, 21.2, 22.6, DH, DOOR_STEEL, -1)
	door(doors, "07 Cash Operations (teller side)", "z", 20, 10.2, 11.6, DH, DOOR_STEEL, 1)
	door(doors, "02 Consultation B", "z", 6, 13.4, 14.8, DH, DOOR_WOOD, -1)
	door(doors, "01 Consultation A", "z", 6, 17.4, 18.8, DH, DOOR_WOOD, -1)
	door(doors, "05 Advisor Office", "z", 24, 13.0, 14.4, DH, DOOR_WOOD, 1)
	door(doors, "04 Customer WC", "z", 24, 16.6, 18.0, DH, DOOR_WOOD, 1)
	door(doors, "Exit West", "z", 0, 7.3, 8.7, 8.5, DOOR_STEEL, -1, false, 1.6)
	door(doors, "Exit East", "z", 30, 7.3, 8.7, 8.5, DOOR_STEEL, 1, false, 1.6)
	door(doors, "Main Entrance", "x", 20, 13.6, 16.4, 9, DOOR_GLASS, -1, true, 1.6)

	-- room plaques next to the doors
	plaque(doors, 2.6, 7 + 0.44 / M, 6.5, SOUTH, "09 MANAGER")
	plaque(doors, 8.3, 7 + 0.44 / M, 6.5, SOUTH, "10 MEETING")
	plaque(doors, 14.0, 7 + 0.44 / M, 6.5, SOUTH, "11 STAFF ROOM")
	plaque(doors, 21.3, 7 + 0.84 / M, 6.5, SOUTH, "12 VAULT")
	plaque(doors, 25.6, 7 + 0.44 / M, 9.6, SOUTH, "13 IT")
	plaque(doors, 28.7, 7 + 0.44 / M, 9.6, SOUTH, "14 RECORDS")
	plaque(doors, 6 + 0.44 / M, 15.5, 6.5, EAST, "02 CONSULTATION B")
	plaque(doors, 6 + 0.44 / M, 19.4, 6.5, EAST, "01 CONSULTATION A")
	plaque(doors, 24 - 0.44 / M, 15.2, 6.5, WEST, "05 ADVISOR")
	plaque(doors, 24 - 0.44 / M, 18.8, 6.5, WEST, "04 WC")
	plaque(doors, 3.2, 9 - 0.44 / M, 6.5, NORTH, "06 TELLERS")
	plaque(doors, 23.6, 9 - 0.44 / M, 6.5, NORTH, "07 CASH OPS")

	---------------------------------------------------------------- 03 BANKING HALL
	do
		local hall = R("03")
		roomLights(lights, 6, 12, 24, 20, 4, 2)
		-- pendant lamps over the hall
		for i = 0, 2 do
			local x = 9.5 + i * 5
			local cfp = at(x, H - 3.2, 16.6)
			cyl(hall, "PendantCord", 0.08, 3, at(x, H - 1.5, 16.6), RGB(30, 30, 30), MAT.Metal, true)
			local shade = cyl(hall, "PendantShade", 2.4, 1.0, cfp, C.greenDark, MAT.Metal, true)
			local bulb = ball(hall, "PendantBulb", 1.0, cfp * CFrame.new(0, -0.5, 0), RGB(255, 236, 200), MAT.Neon, true)
			light(bulb, "point", 0.9, 14)
			shade.Name = "PendantShade"
		end
		-- carpet runner + entrance mat
		P(hall, "EntranceMat", Vector3.new(10, 0.06, 5), at(15, 0.03, 19.1), RGB(40, 44, 48), MAT.Fabric, true)
		local mat = P(hall, "RunnerCarpet", Vector3.new(5.4, 0.04, 10.4), at(15, 0.02, 17.8), RGB(0, 110, 70), MAT.Carpet, true)
		mat.Name = "RunnerCarpet"
		-- queue stanchions (two rows, entry at the east end)
		local posts = { 8.2, 10.6, 13.0, 15.4, 17.8, 19.6 }
		for _, zrow in { 14.0, 15.4 } do
			local prev: Vector3? = nil
			for i, x in posts do
				if zrow == 15.4 and i == #posts then
					break -- leave the entry open
				end
				local cfp = at(x, 0, zrow)
				cyl(hall, "PostBase", 1.1, 0.15, cfp * CFrame.new(0, 0.08, 0), RGB(40, 40, 44), MAT.Metal)
				cyl(hall, "Post", 0.25, 3.0, cfp * CFrame.new(0, 1.6, 0), RGB(200, 200, 205), MAT.Metal)
				ball(hall, "PostTop", 0.4, cfp * CFrame.new(0, 3.15, 0), RGB(200, 200, 205), MAT.Metal, true)
				local here = (cfp * CFrame.new(0, 2.85, 0)).Position
				if prev then
					local mid = (prev + here) / 2
					local belt = P(hall, "Belt", Vector3.new(0.05, 0.3, (here - prev).Magnitude), CFrame.lookAt(mid, here), C.greenDark, MAT.Fabric)
					belt.CanQuery = false
				end
				prev = here
			end
		end
		local sgn = P(hall, "QueueSign", Vector3.new(2.6, 1.6, 0.1), at(20.6, 4.2, 14.7, EAST + math.rad(20)), RGB(30, 34, 40), MAT.SmoothPlastic, true)
		cyl(hall, "QueueSignPost", 0.2, 3.4, at(20.6, 1.7, 14.7), RGB(200, 200, 205), MAT.Metal, true)
		cyl(hall, "QueueSignBase", 1.1, 0.15, at(20.6, 0.08, 14.7), RGB(40, 40, 44), MAT.Metal, true)
		local g = surf(sgn, Enum.NormalId.Front, 50)
		text(g, "TELLER QUEUE", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.4))
		text(g, "please wait here", RGB(160, 220, 190), Enum.Font.Gotham, UDim2.fromScale(0.1, 0.55), UDim2.fromScale(0.8, 0.3))

		-- waiting area: 6 seats around a coffee table
		local wait = folder(hall, "Waiting")
		for i, x in { 7.8, 8.9, 10.0 } do
			guestChair(wait, at(x, 0, 16.6, SOUTH), RGB(0, 118, 76))
			guestChair(wait, at(x, 0, 18.9, NORTH), RGB(0, 118, 76))
			local _ = i
		end
		P(wait, "CoffeeTable", Vector3.new(8.5, 0.3, 3.2), at(8.9, 1.5, 17.75), C.oak, MAT.Wood)
		for _, o in { Vector3.new(3.8, 0, 1.3), Vector3.new(-3.8, 0, 1.3), Vector3.new(3.8, 0, -1.3), Vector3.new(-3.8, 0, -1.3) } do
			P(wait, "Leg", Vector3.new(0.25, 1.4, 0.25), at(8.9, 0.7, 17.75) * CFrame.new(o), RGB(50, 50, 54), MAT.Metal, true)
		end
		for k = 1, 3 do
			P(wait, "Magazine", Vector3.new(1.0, 0.06, 1.3), at(8.0 + k * 0.6, 1.7, 17.6) * CFrame.Angles(0, k * 0.5, 0),
				Color3.fromHSV(k * 0.27 % 1, 0.5, 0.85), MAT.SmoothPlastic, true)
		end
		plant(wait, at(6.6, 0, 19.3), 1.1)
		plant(hall, at(23.3, 0, 12.8), 1.2)
		plant(hall, at(6.7, 0, 12.8), 1.0)
				plant(hall, at(17.2, 0, 19.2), 0.9)
		-- WAITING floor sign
		local ws = P(wait, "WaitingSign", Vector3.new(4, 1.1, 0.1), at(8.9, 10.6, 20 - 0.85 / M, NORTH), RGB(30, 34, 40), MAT.SmoothPlastic, true)
		text(surf(ws, Enum.NormalId.Front, 60), "WAITING", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8))

		-- reception desk
		local rec = folder(hall, "Reception")
		local rcf = at(20.7, 0, 16.95)
		P(rec, "Front", Vector3.new(11.4, 3.6, 0.5), rcf * CFrame.new(0, 1.8, 1.3), C.walnut, MAT.Wood)
		P(rec, "FrontPanel", Vector3.new(10.4, 2.6, 0.1), rcf * CFrame.new(0, 1.9, 1.6), C.oak, MAT.Wood, true)
		P(rec, "Top", Vector3.new(11.8, 0.25, 1.4), rcf * CFrame.new(0, 3.7, 1.0), RGB(236, 232, 224), MAT.Marble)
		P(rec, "WorkTop", Vector3.new(11.0, 0.2, 2.2), rcf * CFrame.new(0, 2.8, -0.2), C.walnut, MAT.Wood)
		P(rec, "EndL", Vector3.new(0.5, 3.6, 3.0), rcf * CFrame.new(-5.6, 1.8, 0), C.walnut, MAT.Wood)
		P(rec, "EndR", Vector3.new(0.5, 3.6, 3.0), rcf * CFrame.new(5.6, 1.8, 0), C.walnut, MAT.Wood)
		local rs = P(rec, "ReceptionSign", Vector3.new(6, 1.0, 0.06), rcf * CFrame.new(0, 2.3, 1.66) * CFrame.Angles(0, math.pi, 0), C.white, MAT.SmoothPlastic, true)
		text(surf(rs, Enum.NormalId.Front, 70, true), "RECEPTION", RGB(220, 240, 230), Enum.Font.GothamBold)
		rs.Transparency = 1
		monitor(rec, rcf * CFrame.new(-1.5, 2.9, 0) * CFrame.Angles(0, 0, 0), "RECEPTION")
		office(rec, at(20.2, 0, 16.0, SOUTH))
		P(rec, "Bell", Vector3.new(0.5, 0.3, 0.5), rcf * CFrame.new(2.5, 3.98, 1.1), RGB(220, 190, 80), MAT.Metal, true)
		P(rec, "Brochures", Vector3.new(1.4, 0.8, 0.5), rcf * CFrame.new(4.2, 4.2, 1.1), C.green, MAT.SmoothPlastic, true)

		-- 3 ATMs against the south wall (x 18.5..23)
		local atms = folder(hall, "ATMs")
		for i, x in { 19.3, 20.8, 22.3 } do
			local acf = at(x, 0, 20 - 0.8 / M - 1.05 / M, NORTH) -- back against the wall, facing the hall
			local a = folder(atms, "ATM" .. i)
			P(a, "Body", Vector3.new(3.6, 6.4, 2.1), acf * CFrame.new(0, 3.2, 0), RGB(54, 58, 64), MAT.Metal)
			P(a, "Header", Vector3.new(3.6, 1.2, 2.3), acf * CFrame.new(0, 7.0, -0.1), C.green, MAT.SmoothPlastic)
			local hdr = P(a, "HeaderFace", Vector3.new(3.4, 1.0, 0.05), acf * CFrame.new(0, 7.0, -1.28), C.green, MAT.Neon, true)
			hdr.Transparency = 0.3
			text(surf(hdr, Enum.NormalId.Front, 80, true), "ATM", C.white, Enum.Font.GothamBlack)
			local scr = P(a, "Screen", Vector3.new(2.4, 1.7, 0.15), acf * CFrame.new(0, 5.0, -1.05) * CFrame.Angles(math.rad(-12), 0, 0), RGB(20, 20, 24), MAT.Glass, true)
			local sg = surf(scr, Enum.NormalId.Front, 70, true)
			local bg = frame(sg, RGB(0, 72, 50), UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.9, 0.88))
			text(bg, "ATLAS BANK", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.9, 0.28))
			text(bg, "Insert your card", RGB(170, 240, 200), Enum.Font.Gotham, UDim2.fromScale(0.1, 0.5), UDim2.fromScale(0.8, 0.22))
			P(a, "Shelf", Vector3.new(3.2, 0.3, 1.2), acf * CFrame.new(0, 3.5, -1.5), RGB(70, 74, 80), MAT.Metal)
			local kp = P(a, "Keypad", Vector3.new(1.3, 0.1, 0.9), acf * CFrame.new(-0.4, 3.7, -1.5) * CFrame.Angles(math.rad(10), 0, 0), RGB(150, 152, 156), MAT.Metal, true)
			local kg = surf(kp, Enum.NormalId.Top, 100)
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.fromScale(0.28, 0.2)
			grid.CellPadding = UDim2.fromScale(0.04, 0.04)
			grid.Parent = kg
			for _ = 1, 12 do
				frame(kg, RGB(60, 62, 66), UDim2.new(), UDim2.new(), 0.2)
			end
			local slot = P(a, "CardSlot", Vector3.new(0.8, 0.12, 0.1), acf * CFrame.new(1.0, 4.1, -1.08), RGB(0, 255, 140), MAT.Neon, true)
			slot.Name = "CardSlot"
			P(a, "CashSlot", Vector3.new(1.6, 0.15, 0.1), acf * CFrame.new(0, 2.9, -1.08), RGB(20, 20, 22), MAT.SmoothPlastic, true)
			P(a, "Receipt", Vector3.new(0.6, 0.1, 0.1), acf * CFrame.new(1.0, 3.95, -1.08), RGB(20, 20, 22), MAT.SmoothPlastic, true)
		end

		-- hall wall decoration
		picture(hall, at(6 + 0.48 / M, 6.5, 16.0, EAST), 4.5, 3, 11)
		picture(hall, at(24 - 0.48 / M, 6.5, 15.4, WEST), 3, 4, 12)
		-- clock above the WC/advisor wall
		local clk = cyl(hall, "Clock", 2.2, 0.2, at(24 - 0.4 / M - 0.12, 11.2, 17.6, WEST) * CFrame.Angles(math.pi / 2, 0, 0), C.white, MAT.SmoothPlastic, true)
		local _ = clk
		local ccf = at(24 - 0.4 / M - 0.12, 11.2, 17.6, WEST)
		cyl(hall, "ClockRim", 2.4, 0.15, ccf * CFrame.new(0, 0, 0.03) * CFrame.Angles(math.pi / 2, 0, 0), C.dark, MAT.Metal, true)
		P(hall, "HourHand", Vector3.new(0.14, 0.6, 0.04), ccf * CFrame.new(0.15, 0.2, -0.14) * CFrame.Angles(0, 0, math.rad(-35)), C.dark, MAT.SmoothPlastic, true)
		P(hall, "MinuteHand", Vector3.new(0.1, 0.9, 0.04), ccf * CFrame.new(-0.1, -0.3, -0.15) * CFrame.Angles(0, 0, math.rad(160)), C.dark, MAT.SmoothPlastic, true)
		-- rates screen
		local rate = P(hall, "RatesScreen", Vector3.new(5.5, 3.2, 0.2), at(6 + 0.5 / M, 9.6, 13.0 + 1.8 / M, EAST), RGB(20, 20, 24), MAT.SmoothPlastic, true)
		local rg = surf(rate, Enum.NormalId.Front, 50, true)
		local rbg = frame(rg, RGB(10, 40, 32), UDim2.fromScale(0.03, 0.05), UDim2.fromScale(0.94, 0.9))
		text(rbg, "TODAY'S RATES", RGB(120, 240, 180), Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.2))
		local lines = { "SAVINGS      2.50 %", "TERM 12M     3.10 %", "HOME LOAN    4.25 %", "AUTO LOAN    5.40 %" }
		for i, s in lines do
			text(rbg, s, C.white, Enum.Font.Code, UDim2.fromScale(0.08, 0.1 + i * 0.19), UDim2.fromScale(0.84, 0.15), Enum.TextXAlignment.Left)
		end
		camera(hall, at(23.6, H - 0.6, 12.6, math.rad(-135)))
		camera(hall, at(6.4, H - 0.6, 19.6, math.rad(45)))
		-- brochure stand by the entrance
		local br = folder(hall, "BrochureStand")
		P(br, "Stand", Vector3.new(2.2, 5, 0.6), at(13.05, 2.5, 19.4, NORTH), RGB(60, 64, 70), MAT.Metal)
		for k = 0, 2 do
			P(br, "Brochure", Vector3.new(1.8, 0.9, 0.2), at(13.05, 1.6 + k * 1.3, 19.4, NORTH) * CFrame.new(0, 0, -0.4),
				Color3.fromHSV(0.38 + k * 0.08, 0.6, 0.7), MAT.SmoothPlastic, true)
		end
		-- water cooler
		local wc = folder(hall, "WaterCooler")
		P(wc, "Body", Vector3.new(1.5, 3.4, 1.5), at(11.6, 1.7, 12.9), C.white, MAT.SmoothPlastic)
		local jug = cyl(wc, "Jug", 1.2, 1.7, at(11.6, 4.3, 12.9), RGB(150, 200, 230), MAT.Glass, true)
		jug.Transparency = 0.4
	end

	---------------------------------------------------------------- teller counter (z = 12, x 6..20) + 06 TELLER WORK AREA
	do
		local tw = R("06")
		local counter = folder(tw, "TellerCounter")
		local zc = 12
		local function cx(x: number, y: number, dz: number, rot: number?): CFrame
			return at(x, y, zc, rot) * CFrame.new(0, 0, dz)
		end
		local L = (20 - 6) * M
		local midx = 13
		-- counter body (positions 1-3 at 3.6 studs, position 4 lowered to 2.8)
		local windows = { 7.8, 10.9, 14.0, 17.6 }
		local bounds = { 6, 9.35, 12.45, 15.55, 20 }
		for i = 1, 4 do
			local a, b = bounds[i], bounds[i + 1]
			local w = (b - a) * M
			local mid = (a + b) / 2
			local hgt = if i == 4 then 2.8 else 3.6
			P(counter, "Body", Vector3.new(w, hgt, 2.6), cx(mid, hgt / 2, 0), C.walnut, MAT.Wood)
			P(counter, "Top", Vector3.new(w, 0.25, 3.3), cx(mid, hgt + 0.12, 0.1), RGB(232, 228, 220), MAT.Marble)
			P(counter, "FrontInset", Vector3.new(w - 1.2, hgt - 1.0, 0.1), cx(mid, hgt / 2, 1.35), C.oak, MAT.Wood, true)
			-- glass screen above the counter, with a 0.35 pass-through gap
			local g0 = hgt + 0.6
			local glass = P(counter, "Glass", Vector3.new(w - 0.3, 9 - g0, 0.2), cx(mid, (g0 + 9) / 2, -0.2), RGB(200, 225, 230), MAT.Glass)
			glass.Transparency = 0.7
			-- number sign on the header above each window (hall side)
			local ns = P(counter, "Number", Vector3.new(1.4, 1.4, 0.1), cx(windows[i], 10.0, 0.27), C.teal, MAT.SmoothPlastic, true)
			local ng = surf(ns, Enum.NormalId.Back, 60, true)
			text(ng, tostring(i), C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.9))
			-- staff side: cash drawer, monitor, stool, card terminal on the customer side
			P(counter, "CashDrawer", Vector3.new(2.4, 0.6, 0.2), cx(windows[i], hgt - 0.6, -1.35), RGB(70, 72, 78), MAT.Metal, true)
			monitor(counter, cx(windows[i] - 0.5, hgt + 0.25, -0.6) * CFrame.Angles(0, 0, 0), "TELLER " .. i)
			P(counter, "CardTerminal", Vector3.new(0.6, 0.25, 0.9), cx(windows[i] + 0.6, hgt + 0.37, 1.1), RGB(36, 36, 40), MAT.SmoothPlastic, true)
			P(counter, "PenChain", Vector3.new(0.12, 0.12, 0.8), cx(windows[i] - 0.6, hgt + 0.3, 1.2), RGB(30, 30, 30), MAT.SmoothPlastic, true)
			local stool = folder(counter, "Stool")
			local sh = if i == 4 then 1.9 else 2.6
			cyl(stool, "Base", 1.6, 0.2, cx(windows[i], 0.1, -2.6), RGB(50, 50, 54), MAT.Metal)
			cyl(stool, "Post", 0.25, sh, cx(windows[i], sh / 2, -2.6), RGB(160, 160, 165), MAT.Metal, true)
			cyl(stool, "Seat", 1.6, 0.4, cx(windows[i], sh + 0.2, -2.6), RGB(40, 44, 52), MAT.Fabric)
			if i == 4 then
				local ls = P(counter, "LoweredSign", Vector3.new(2.6, 0.6, 0.06), cx(windows[i], 2.2, 1.34), C.teal, MAT.SmoothPlastic, true)
				text(surf(ls, Enum.NormalId.Back, 60, true), "LOWERED COUNTER", C.white, Enum.Font.GothamBold, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8))
			end
		end
		-- mullions between windows
		for _, x in bounds do
			P(counter, "Mullion", Vector3.new(0.35, 9 - 2.8, 0.45), cx(x, 2.8 + (9 - 2.8) / 2, -0.2), C.frame, MAT.Metal)
		end
		-- header wall above the glass to the ceiling + wood fascia on the hall side
		P(counter, "Header", Vector3.new(L, H - 9, 0.8), cx(midx, 9 + (H - 9) / 2, -0.2), C.wallHall)
		P(counter, "Fascia", Vector3.new(L, 0.9, 0.3), cx(midx, 9.0, 0.35), C.walnut, MAT.Wood)
		local logoPanel = P(counter, "HallLogo", Vector3.new(16, 2.4, 0.1), cx(midx, 12.0, 0.25), C.white, MAT.SmoothPlastic, true)
		logoPanel.Transparency = 1
		local lg = surf(logoPanel, Enum.NormalId.Back, 40)
		logo(lg, UDim2.fromScale(0.0, 0.0), UDim2.fromScale(0.16, 1))
		text(lg, "ATLAS BANK", C.greenDark, Enum.Font.GothamBlack, UDim2.fromScale(0.17, 0.05), UDim2.fromScale(0.8, 0.9), Enum.TextXAlignment.Left)
		-- teller signs: "TELLER QUEUE / 4 POSITIONS"
		roomLights(lights, 0, 9, 20, 12, 5, 1)
		-- back office of the teller area (x 0..6): copier, filing, desk
		cabinet(tw, at(0.6, 0, 10.5, EAST) , 3.6, 4.4, 2.2, 4)
		local copier = folder(tw, "Copier")
		P(copier, "Body", Vector3.new(3, 3.4, 2.4), at(3.4, 1.7, 9.6), RGB(225, 225, 222), MAT.SmoothPlastic)
		P(copier, "Lid", Vector3.new(3, 0.3, 2.4), at(3.4, 3.55, 9.6), RGB(70, 72, 78), MAT.SmoothPlastic)
		P(copier, "Tray", Vector3.new(1.4, 0.15, 1.6), at(3.4, 2.5, 9.6) * CFrame.new(1.9, 0, 0), RGB(200, 200, 198), MAT.SmoothPlastic, true)
		-- notice board on the corridor wall (teller side)
		local nb = P(tw, "NoticeBoard", Vector3.new(6, 3.4, 0.2), at(10.5, 6.2, 9 + 0.5 / M, SOUTH), RGB(170, 130, 90), MAT.Fabric, true)
		local ng = surf(nb, Enum.NormalId.Front, 30)
		for k = 0, 5 do
			frame(ng, if k % 2 == 0 then C.white else RGB(250, 240, 160), UDim2.fromScale(0.05 + (k % 3) * 0.31, 0.08 + math.floor(k / 3) * 0.46), UDim2.fromScale(0.26, 0.38))
		end
		-- cash trolley behind position 2-3
		P(tw, "Bin", Vector3.new(1.6, 2.2, 1.2), at(19.2, 1.1, 9.6), RGB(60, 64, 70), MAT.Metal)
		camera(tw, at(19.6, H - 0.6, 9.4, math.rad(-120)))
	end

	---------------------------------------------------------------- 07 CASH / OPERATIONS
	do
		local co = R("07")
		roomLights(lights, 20, 9, 30, 12, 3, 1, RGB(235, 245, 255))
		local t = folder(co, "CountingTable")
		P(t, "Top", Vector3.new(10, 0.3, 3.4), at(25, 3.0, 10.5), RGB(200, 202, 206), MAT.Metal)
		for _, o in { Vector3.new(4.6, 0, 1.4), Vector3.new(-4.6, 0, 1.4), Vector3.new(4.6, 0, -1.4), Vector3.new(-4.6, 0, -1.4) } do
			P(t, "Leg", Vector3.new(0.25, 2.9, 0.25), at(25, 1.45, 10.5) * CFrame.new(o), RGB(80, 82, 86), MAT.Metal, true)
		end
		for i, x in { 23.6, 26.4 } do
			local mcf = at(x, 3.15, 10.5)
			P(t, "CountingMachine", Vector3.new(2, 1.2, 1.6), mcf * CFrame.new(0, 0.6, 0), RGB(230, 230, 228), MAT.SmoothPlastic)
			P(t, "Hopper", Vector3.new(1.3, 0.5, 0.8), mcf * CFrame.new(0, 1.35, 0.3), RGB(60, 62, 66), MAT.SmoothPlastic, true)
			local d = P(t, "Display", Vector3.new(0.8, 0.35, 0.05), mcf * CFrame.new(0, 0.85, -0.81), RGB(40, 220, 120), MAT.Neon, true)
			d.Name = "Display" .. i
			for k = 0, 3 do
				cashStack(t, mcf * CFrame.new(-1.7 + (k % 2) * 0.0, 0.25 + math.floor(k / 2) * 0.47, -0.6 + (k % 2) * 0.7))
			end
		end
		for k = 0, 5 do
			cashStack(t, at(25, 3.4 + math.floor(k / 3) * 0.47, 10.5) * CFrame.new(-0.6 + (k % 3) * 0, 0, -0.9 + (k % 3) * 0.65))
		end
		-- big safe in the corner
		local safe = folder(co, "Safe")
		local scf = at(29.2, 0, 11.2, WEST)
		P(safe, "Body", Vector3.new(4, 5.5, 3), scf * CFrame.new(0, 2.75, 0), RGB(54, 58, 62), MAT.Metal)
		P(safe, "Door", Vector3.new(3.4, 4.9, 0.2), scf * CFrame.new(0, 2.75, -1.55), RGB(70, 74, 80), MAT.Metal, true)
		cyl(safe, "Dial", 0.9, 0.2, scf * CFrame.new(0.4, 3.4, -1.7) * CFrame.Angles(math.pi / 2, 0, 0), RGB(200, 200, 205), MAT.Metal, true)
		P(safe, "Handle", Vector3.new(0.2, 1.2, 0.2), scf * CFrame.new(-0.8, 2.6, -1.75), RGB(200, 200, 205), MAT.Metal, true)
		-- shelf with cash bags along the corridor wall
		shelf(co, at(27.4, 0, 9 + 1.25 / M, SOUTH) * CFrame.Angles(0, 0, 0), 5, 5.5, 1.6, 3, "bags")
		-- cash trolley
		local tr = folder(co, "CashTrolley")
		P(tr, "Deck", Vector3.new(2.6, 0.2, 1.6), at(21.4, 0.7, 11.2), RGB(150, 152, 156), MAT.Metal)
		for k = 0, 3 do
			local wcf = at(21.4, 0.3, 11.2) * CFrame.new((k % 2 - 0.5) * 2.2, 0, (math.floor(k / 2) - 0.5) * 1.2)
			ball(tr, "Wheel", 0.5, wcf, RGB(30, 30, 30), MAT.Rubber, true)
		end
		P(tr, "Handle", Vector3.new(0.15, 2.6, 1.6), at(21.4, 1.9, 11.2) * CFrame.new(-1.25, 0, 0), RGB(150, 152, 156), MAT.Metal, true)
		for k = 0, 5 do
			cashStack(tr, at(21.4, 1.05 + math.floor(k / 3) * 0.47, 11.2) * CFrame.new(-0.2, 0, -0.55 + (k % 3) * 0.55) * CFrame.Angles(0, math.pi / 2, 0))
		end
		camera(co, at(29.6, H - 0.6, 9.4, math.rad(-135)))
	end

	---------------------------------------------------------------- 12 VAULT
	do
		local v = R("12")
		roomLights(lights, 16, 0, 24, 7, 2, 2, RGB(220, 235, 255))
		-- steel wall lining + safe-deposit box walls (west, east, north)
		local function boxes(cf: CFrame, w: number, h: number, cols: number, rows: number)
			local p = P(v, "DepositBoxes", Vector3.new(w, h, 0.3), cf, RGB(170, 174, 180), MAT.Metal)
			local g = surf(p, Enum.NormalId.Front, 25)
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.new(1 / cols, -4, 1 / rows, -4)
			grid.CellPadding = UDim2.fromOffset(4, 4)
			grid.Parent = g
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 3)
			pad.PaddingTop = UDim.new(0, 3)
			pad.Parent = g
			for _ = 1, cols * rows do
				local cell = frame(g, RGB(196, 200, 206), UDim2.new(), UDim2.new())
				local st = Instance.new("UIStroke")
				st.Color = RGB(110, 114, 120)
				st.Thickness = 2
				st.Parent = cell
				frame(cell, RGB(60, 62, 66), UDim2.fromScale(0.44, 0.38), UDim2.fromScale(0.12, 0.24), 1)
				frame(cell, RGB(120, 124, 130), UDim2.fromScale(0.3, 0.75), UDim2.fromScale(0.4, 0.08))
			end
		end
		boxes(at(16 + 0.8 / M + 0.05, 5.5, 3.5, EAST), 19, 9, 14, 7)
		boxes(at(24 - 0.8 / M - 0.05, 5.5, 3.5, WEST), 19, 9, 14, 7)
		boxes(at(20, 5.5, 0.8 / M + 0.05, SOUTH), 22, 9, 16, 7)
		-- centre table with gold bars and cash
		local t = folder(v, "GoldTable")
		P(t, "Top", Vector3.new(8, 0.35, 4), at(20, 3.0, 3.6), RGB(90, 94, 100), MAT.Metal)
		P(t, "Base", Vector3.new(7, 2.8, 3), at(20, 1.4, 3.6), RGB(70, 74, 80), MAT.DiamondPlate)
		local gcf = at(18.9, 3.4, 3.6)
		local n = 0
		for layer = 0, 2 do
			for ix = 0, 3 - layer do
				for iz = 0, 2 - layer do
					n += 1
					local bar = P(t, "GoldBar", Vector3.new(1.0, 0.42, 0.5),
						gcf * CFrame.new((ix - (3 - layer) / 2) * 1.05, layer * 0.43, (iz - (2 - layer) / 2) * 0.55), C.gold, MAT.Foil, true)
					bar.Reflectance = 0.15
				end
			end
		end
		for k = 0, 8 do
			cashStack(t, at(21.6, 3.42 + math.floor(k / 3) * 0.47, 3.6) * CFrame.new(-0.6 + (k % 3) * 0.0, 0, -0.65 + (k % 3) * 0.65))
		end
		-- two pallets of cash
		for i, x in { 17.6, 22.4 } do
			local pal = folder(v, "CashPallet" .. i)
			local pcf = at(x, 0, 1.6)
			P(pal, "Pallet", Vector3.new(4, 0.5, 3.2), pcf * CFrame.new(0, 0.25, 0), RGB(150, 116, 76), MAT.WoodPlanks)
			for ly = 0, 3 do
				for ix = 0, 2 do
					for iz = 0, 4 do
						if ly < 3 or (ix + iz) % 2 == 0 then
							cashStack(pal, pcf * CFrame.new((ix - 1) * 1.25, 0.75 + ly * 0.47, (iz - 2) * 0.62))
						end
					end
				end
			end
			local wrap = P(pal, "Wrap", Vector3.new(3.9, 1.9, 3.15), pcf * CFrame.new(0, 1.45, 0), RGB(220, 230, 235), MAT.Glass, true)
			wrap.Transparency = 0.85
		end
		-- money bags on the floor
		for k = 0, 3 do
			ball(v, "MoneyBag", 1.4, at(21.8 + k * 0.5, 0.7, 6.0 + (k % 2) * 0.35), RGB(196, 184, 150), MAT.Fabric, true)
		end
		camera(v, at(23.6, H - 0.6, 0.4, math.rad(-135)))
		-- warning stripes on the floor at the vault door
		for k = 0, 5 do
			P(v, "Stripe", Vector3.new(1.0, 0.04, 2.4), at(17.4 + k * 0.45, 0.02, 6.4) * CFrame.Angles(0, math.rad(35), 0),
				if k % 2 == 0 then RGB(240, 200, 30) else RGB(30, 30, 30), MAT.SmoothPlastic, true)
		end

		-- the vault door: thick steel slab with a round face, wheel and bolts (swings into the vault)
		local vd = Instance.new("Model")
		vd.Name = "12 Vault Door"
		vd.Parent = doors
		local w = (20.0 - 17.2) * M
		local hinge = at(17.2, 0, 7)
		local lf = Instance.new("Model")
		lf.Name = "Leaf"
		lf.Parent = vd
		local slab = P(lf, "Slab", Vector3.new(w - 0.15, 8.9, 1.2), hinge * CFrame.new(w / 2, 4.5, 0), RGB(150, 156, 164), MAT.Metal)
		local face = hinge * CFrame.new(w / 2, 4.6, 0.65) -- corridor side (+Z)
		cyl(lf, "Disc", 7.2, 0.25, face * CFrame.Angles(math.pi / 2, 0, 0), RGB(176, 182, 190), MAT.Metal, true)
		cyl(lf, "Ring", 5.4, 0.3, face * CFrame.new(0, 0, 0.05) * CFrame.Angles(math.pi / 2, 0, 0), RGB(130, 136, 144), MAT.Metal, true)
		cyl(lf, "Hub", 1.2, 0.8, face * CFrame.new(0, 0, 0.4) * CFrame.Angles(math.pi / 2, 0, 0), RGB(200, 204, 210), MAT.Metal, true)
		for k = 0, 2 do
			P(lf, "Spoke", Vector3.new(4.2, 0.3, 0.3), face * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, 0, k * math.pi / 3), RGB(210, 214, 220), MAT.Metal, true)
			for s2 = -1, 1, 2 do
				ball(lf, "Knob", 0.55, face * CFrame.Angles(0, 0, k * math.pi / 3) * CFrame.new(s2 * 2.1, 0, 0.6), RGB(40, 40, 44), MAT.Metal, true)
			end
		end
		for k = 0, 11 do
			local a = k * math.pi / 6
			ball(lf, "Bolt", 0.4, face * CFrame.new(math.cos(a) * 3.2, math.sin(a) * 3.2, 0.12), RGB(120, 124, 130), MAT.Metal, true)
		end
		P(lf, "Hinge", Vector3.new(0.6, 7.5, 1.6), hinge * CFrame.new(0.2, 4.5, 0.2), RGB(90, 94, 100), MAT.Metal, true)
		lf.PrimaryPart = slab
		lf.WorldPivot = hinge
		lf:SetAttribute("Closed", hinge)
		lf:SetAttribute("OpenAngle", math.rad(100))
		-- steel frame around the opening
		local fcf = at(18.6, 0, 7)
		P(vd, "Jamb", Vector3.new(0.7, 9.6, 2.0), fcf * CFrame.new(-w / 2 - 0.35, 4.8, 0), RGB(100, 104, 110), MAT.Metal, true)
		P(vd, "Jamb", Vector3.new(0.7, 9.6, 2.0), fcf * CFrame.new(w / 2 + 0.35, 4.8, 0), RGB(100, 104, 110), MAT.Metal, true)
		P(vd, "Lintel", Vector3.new(w + 1.4, 0.7, 2.0), fcf * CFrame.new(0, 9.35, 0), RGB(100, 104, 110), MAT.Metal, true)
		local pa = P(vd, "PromptAnchor", Vector3.new(0.2, 0.2, 0.2), fcf * CFrame.new(0, 4, 0), C.white, MAT.SmoothPlastic, true)
		pa.Transparency = 1
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "DoorPrompt"
		pp.ActionText = "Open"
		pp.ObjectText = "Vault"
		pp.HoldDuration = 1.5
		pp.MaxActivationDistance = 10
		pp.RequiresLineOfSight = false
		pp.Parent = pa
		vd:SetAttribute("Secure", true)
		vd:SetAttribute("TweenTime", 3)
		vd.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		CollectionService:AddTag(vd, "BankDoor")
		-- keypad beside the vault door
		local kp = P(vd, "Keypad", Vector3.new(0.9, 1.3, 0.2), at(21.0, 4.5, 7 + 0.9 / M), RGB(40, 42, 46), MAT.Metal, true)
		local led = P(vd, "KeypadLed", Vector3.new(0.25, 0.12, 0.05), kp.CFrame * CFrame.new(0, 0.45, 0.12), RGB(255, 50, 50), MAT.Neon, true)
		led.Name = "KeypadLed"
	end

	---------------------------------------------------------------- 09 MANAGER
	do
		local r = R("09")
		roomLights(lights, 0, 0, 5, 7, 1, 2)
		desk(r, at(2.5, 0, 3.2, SOUTH), 7, 3.2, C.walnut, "MANAGER")
		office(r, at(2.5, 0, 2.3, SOUTH), RGB(30, 30, 34))
		guestChair(r, at(1.8, 0, 4.6, NORTH), RGB(120, 40, 40))
		guestChair(r, at(3.3, 0, 4.6, NORTH), RGB(120, 40, 40))
		shelf(r, at(0.52, 0, 3.2, EAST), 6, 8, 1.4, 5, "books", C.walnut)
		plant(r, at(4.4, 0, 0.6), 1.0)
		cabinet(r, at(4.5, 0, 3.4, WEST), 2, 4.2, 2, 4, RGB(70, 72, 78))
		picture(r, at(5 - 0.48 / M, 6.5, 5.6, WEST), 3.2, 2.2, 21)
		-- small floor safe + nameplate
		P(r, "FloorSafe", Vector3.new(2, 2, 2), at(0.6, 1, 6.2), RGB(50, 52, 56), MAT.Metal)
		local np = P(r, "Nameplate", Vector3.new(1.6, 0.4, 0.1), at(2.5, 3.15, 3.2, SOUTH) * CFrame.new(0, 0, 1.45) * CFrame.Angles(0, math.pi, 0), RGB(200, 170, 80), MAT.Metal, true)
		text(surf(np, Enum.NormalId.Front, 80), "BRANCH MANAGER", RGB(40, 30, 10), Enum.Font.GothamBold)
		local rug = P(r, "Rug", Vector3.new(8, 0.04, 6), at(2.5, 0.02, 4.1), RGB(120, 40, 44), MAT.Fabric, true)
		rug.Name = "Rug"
	end

	---------------------------------------------------------------- 10 MEETING
	do
		local r = R("10")
		roomLights(lights, 5, 0, 10, 7, 1, 2)
		local t = folder(r, "MeetingTable")
		P(t, "Top", Vector3.new(9, 0.3, 4.4), at(7.5, 2.8, 3.4), RGB(238, 238, 234), MAT.SmoothPlastic)
		P(t, "Leg", Vector3.new(1, 2.7, 2.6), at(7.5, 1.35, 3.4) * CFrame.new(-2.8, 0, 0), RGB(60, 62, 66), MAT.Metal)
		P(t, "Leg", Vector3.new(1, 2.7, 2.6), at(7.5, 1.35, 3.4) * CFrame.new(2.8, 0, 0), RGB(60, 62, 66), MAT.Metal)
		for _, x in { 6.5, 7.5, 8.5 } do
			office(r, at(x, 0, 2.1, SOUTH), RGB(60, 64, 76))
			office(r, at(x, 0, 4.7, NORTH), RGB(60, 64, 76))
		end
		P(t, "Speaker", Vector3.new(1, 0.25, 1), at(7.5, 3.07, 3.4), RGB(30, 30, 34), MAT.SmoothPlastic, true)
		-- wall TV (west) and whiteboard (east)
		local tv = P(r, "TV", Vector3.new(6.5, 3.8, 0.25), at(5 + 0.53 / M, 6.6, 3.4, EAST), RGB(18, 18, 20), MAT.SmoothPlastic, true)
		local tg = surf(tv, Enum.NormalId.Front, 40, true)
		local tbg = frame(tg, RGB(240, 244, 240), UDim2.fromScale(0.02, 0.03), UDim2.fromScale(0.96, 0.94))
		text(tbg, "Q3 BRANCH REVIEW", C.greenDark, Enum.Font.GothamBlack, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.18))
		for i = 1, 5 do
			frame(tbg, C.green, UDim2.fromScale(0.1 + i * 0.14, 0.9 - i * 0.12), UDim2.fromScale(0.09, i * 0.12))
		end
		local wb = P(r, "Whiteboard", Vector3.new(7, 3.6, 0.15), at(10 - 0.48 / M, 6.4, 3.4, WEST), RGB(250, 250, 250), MAT.SmoothPlastic, true)
		local wg = surf(wb, Enum.NormalId.Front, 40)
		text(wg, "GOALS: +12% new accounts", RGB(30, 60, 160), Enum.Font.PermanentMarker, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.25))
		text(wg, "- mortgages  - savings week", RGB(170, 40, 40), Enum.Font.PermanentMarker, UDim2.fromScale(0.05, 0.45), UDim2.fromScale(0.8, 0.2))
		P(r, "Tray", Vector3.new(6.6, 0.2, 0.5), at(10 - 0.65 / M, 4.5, 3.4, WEST), RGB(190, 190, 195), MAT.Metal, true)
		plant(r, at(9.4, 0, 0.6), 0.9)
	end

	---------------------------------------------------------------- 11 STAFF ROOM
	do
		local r = R("11")
		roomLights(lights, 10, 0, 16, 7, 1, 2)
		local k = folder(r, "Kitchenette")
		local nz = 0.4 / M + 0.9 / M -- counter centre distance from the north wall line (m)
		P(k, "Counter", Vector3.new(13.6, 3.2, 2.4), at(12.5, 1.6, nz + 0.3 / M), RGB(236, 236, 232), MAT.SmoothPlastic)
		P(k, "CounterTop", Vector3.new(13.8, 0.25, 2.6), at(12.5, 3.3, nz + 0.3 / M), RGB(60, 60, 64), MAT.Granite)
		for i = 0, 5 do
			P(k, "DoorLine", Vector3.new(0.06, 2.6, 0.05), at(10.5 + i * 0.75, 1.5, nz + 0.3 / M) * CFrame.new(0, 0, 1.22), RGB(190, 190, 186), MAT.SmoothPlastic, true)
		end
		P(k, "Sink", Vector3.new(2.2, 0.15, 1.5), at(13.0, 3.43, nz + 0.3 / M), RGB(190, 194, 200), MAT.Metal, true)
		P(k, "Tap", Vector3.new(0.2, 1.0, 0.2), at(13.0, 3.9, nz), RGB(200, 200, 205), MAT.Metal, true)
		local mw = P(k, "Microwave", Vector3.new(2, 1.2, 1.4), at(11.2, 4.03, nz + 0.2 / M), RGB(40, 40, 44), MAT.SmoothPlastic)
		P(k, "MicrowaveGlass", Vector3.new(1.2, 0.8, 0.05), mw.CFrame * CFrame.new(-0.25, 0, 0.71), RGB(20, 20, 20), MAT.Glass, true)
		local cm = P(k, "CoffeeMachine", Vector3.new(1, 1.5, 1.2), at(14.3, 4.2, nz + 0.2 / M), RGB(30, 30, 32), MAT.SmoothPlastic)
		cm.Name = "CoffeeMachine"
		cyl(k, "Mug", 0.35, 0.45, at(14.6, 3.65, nz + 0.6 / M), C.white, MAT.SmoothPlastic, true)
		-- wall cabinets under the window line (window x 12..14, so cabinets left and right)
		P(k, "WallCabinet", Vector3.new(4.4, 2.2, 1.3), at(10.85, 9.4, 0.4 / M + 0.65 / M), RGB(236, 236, 232), MAT.SmoothPlastic)
		P(k, "WallCabinet", Vector3.new(4.4, 2.2, 1.3), at(15.0, 9.4, 0.4 / M + 0.65 / M), RGB(236, 236, 232), MAT.SmoothPlastic)
		-- fridge in the north-east corner
		local fr = P(k, "Fridge", Vector3.new(2.8, 6.4, 2.4), at(15.25, 3.2, 2.05 / M), RGB(214, 216, 220), MAT.Metal)
		P(k, "FridgeHandle", Vector3.new(0.15, 1.6, 0.15), fr.CFrame * CFrame.new(-1.1, 0.6, 1.25), RGB(120, 120, 125), MAT.Metal, true)
		-- break table + 4 chairs
		P(r, "BreakTable", Vector3.new(5, 0.3, 3.4), at(12.3, 2.8, 3.9), C.oak, MAT.Wood)
		cyl(r, "TableLeg", 0.6, 2.7, at(12.3, 1.35, 3.9), RGB(50, 50, 54), MAT.Metal)
		cyl(r, "TableFoot", 2.2, 0.15, at(12.3, 0.08, 3.9), RGB(50, 50, 54), MAT.Metal, true)
		guestChair(r, at(11.6, 0, 3.0, SOUTH), RGB(230, 140, 50))
		guestChair(r, at(13.0, 0, 3.0, SOUTH), RGB(230, 140, 50))
		guestChair(r, at(11.6, 0, 4.8, NORTH), RGB(230, 140, 50))
		guestChair(r, at(13.0, 0, 4.8, NORTH), RGB(230, 140, 50))
		-- lockers along the vault wall (east)
		for i = 0, 4 do
			local lcf = at(16 - 1.62 / M, 0, 2.9 + i * 0.4, WEST)
			P(r, "Locker", Vector3.new(1.15, 6.4, 1.6), lcf * CFrame.new(0, 3.2, 0), RGB(70, 110, 150), MAT.Metal)
			P(r, "LockerVent", Vector3.new(0.7, 0.6, 0.05), lcf * CFrame.new(0, 5.6, -0.82), RGB(50, 80, 110), MAT.Metal, true)
			P(r, "LockerHandle", Vector3.new(0.12, 0.6, 0.1), lcf * CFrame.new(0.35, 3.4, -0.84), RGB(200, 200, 205), MAT.Metal, true)
		end
		-- small sofa against the west wall
		local sofa = folder(r, "Sofa")
		local scf = at(10 + 1.65 / M, 0, 4.4, EAST)
		P(sofa, "Seat", Vector3.new(6, 1.6, 2.4), scf * CFrame.new(0, 0.8, -0.3), RGB(70, 90, 110), MAT.Fabric)
		P(sofa, "Back", Vector3.new(6, 2.4, 0.7), scf * CFrame.new(0, 2.4, 0.8), RGB(70, 90, 110), MAT.Fabric)
		P(sofa, "Arm", Vector3.new(0.6, 2.2, 3), scf * CFrame.new(3.1, 1.1, 0), RGB(62, 80, 100), MAT.Fabric)
		P(sofa, "Arm", Vector3.new(0.6, 2.2, 3), scf * CFrame.new(-3.1, 1.1, 0), RGB(62, 80, 100), MAT.Fabric)
	end

	---------------------------------------------------------------- 13 IT / SERVICES
	do
		local r = R("13")
		roomLights(lights, 24, 0, 27, 7, 1, 2, RGB(220, 235, 255))
		for i = 0, 1 do
			local rcf = at(25.5, 0, 1.4 + i * 2.3, EAST) -- racks against the west wall... facing east
			rcf = at(24 + 0.8 / M + 0.75, 0, 1.6 + i * 2.6, EAST)
			local rack = P(r, "ServerRack", Vector3.new(2.2, 7.5, 2.2), rcf * CFrame.new(0, 3.75, 0), RGB(28, 30, 34), MAT.Metal)
			local g = surf(rack, Enum.NormalId.Front, 30, true)
			for u = 0, 10 do
				local row = frame(g, RGB(50, 52, 58), UDim2.fromScale(0.08, 0.05 + u * 0.083), UDim2.fromScale(0.84, 0.065))
				for l = 0, 4 do
					local on = (u * 7 + l * 3 + i) % 4 ~= 0
					frame(row, if on then (if l % 2 == 0 then RGB(60, 255, 120) else RGB(80, 170, 255)) else RGB(255, 170, 40),
						UDim2.fromScale(0.62 + l * 0.07, 0.3), UDim2.fromScale(0.04, 0.4), 1)
				end
			end
		end
		P(r, "CableTray", Vector3.new(1.4, 0.3, 18), at(25.2, H - 1.2, 3.5), RGB(120, 124, 130), MAT.Metal, true)
		local ac = P(r, "WallAC", Vector3.new(4, 1.6, 1.1), at(27 - 0.95 / M, 10.5, 3.5, WEST), RGB(240, 240, 240), MAT.SmoothPlastic)
		P(r, "ACVent", Vector3.new(3.4, 0.2, 0.05), ac.CFrame * CFrame.new(0, -0.5, -0.56), RGB(150, 150, 150), MAT.SmoothPlastic, true)
		P(r, "UPS", Vector3.new(2, 2.2, 2.4), at(26.3, 1.1, 1.0), RGB(40, 40, 44), MAT.Metal)
	end

	---------------------------------------------------------------- 14 STORE / RECORDS
	do
		local r = R("14")
		roomLights(lights, 27, 0, 30, 7, 1, 2)
		shelf(r, at(30 - 1.65 / M, 0, 3.0, WEST), 12, 9, 1.6, 5, "boxes")
		shelf(r, at(27 + 1.25 / M, 0, 3.4, EAST), 10, 9, 1.6, 5, "binders")
		local lad = folder(r, "StepLadder")
		P(lad, "Rail", Vector3.new(0.2, 5, 0.2), at(28.5, 2.4, 1.0) * CFrame.new(-0.8, 0, 0) * CFrame.Angles(math.rad(10), 0, 0), RGB(200, 200, 205), MAT.Metal, true)
		P(lad, "Rail", Vector3.new(0.2, 5, 0.2), at(28.5, 2.4, 1.0) * CFrame.new(0.8, 0, 0) * CFrame.Angles(math.rad(10), 0, 0), RGB(200, 200, 205), MAT.Metal, true)
		for s2 = 0, 3 do
			P(lad, "Step", Vector3.new(1.8, 0.15, 0.6), at(28.5, 0.8 + s2 * 1.2, 1.0) * CFrame.new(0, 0, 0.1 - s2 * 0.2), RGB(200, 200, 205), MAT.Metal, true)
		end
	end

	---------------------------------------------------------------- 08 STAFF CORRIDOR
	do
		local r = R("08")
		for i = 0, 5 do
			ceilingLight(lights, 2.5 + i * 5, 8, 2.4)
		end
		for _, x in { 0, 30 } do
			local inside = if x == 0 then 0.95 / M else -0.95 / M
			local rot = if x == 0 then EAST else WEST
			local ex = P(r, "ExitSign", Vector3.new(2.4, 1, 0.3), at(x + inside, 9.6, 8, rot), RGB(245, 245, 245), MAT.SmoothPlastic, true)
			local g = surf(ex, Enum.NormalId.Front, 60, true)
			frame(g, RGB(0, 160, 80), UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84))
			text(g, "EXIT", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.12), UDim2.fromScale(0.8, 0.76))
			light(ex, "point", 0.4, 6, RGB(120, 255, 160))
		end
		-- fire extinguishers + alarm
		for _, x in { 9.6, 23.2 } do
			local fe = cyl(r, "Extinguisher", 0.6, 1.8, at(x, 2.2, 7 + 0.75 / M), RGB(200, 30, 30), MAT.SmoothPlastic, true)
			P(r, "Nozzle", Vector3.new(0.2, 0.3, 0.5), fe.CFrame * CFrame.new(0.9, 0.2, 0), RGB(30, 30, 30), MAT.SmoothPlastic, true)
			local al = P(r, "FireAlarm", Vector3.new(0.7, 0.9, 0.25), at(x + 0.5, 5, 7 + 0.52 / M, SOUTH), RGB(210, 30, 30), MAT.SmoothPlastic, true)
			local _ = al
		end
		camera(r, at(0.4, H - 0.6, 7.3, math.rad(-120)))
		camera(r, at(29.6, H - 0.6, 7.3, math.rad(120)))
	end

	---------------------------------------------------------------- 01 / 02 CONSULTATION, 05 ADVISOR
	local function consult(id: string, x0: number, z0: number, deskX: number, label: string, pic: number)
		local r = R(id)
		roomLights(lights, x0, z0, x0 + 6, z0 + 4, 1, 1)
		local dz = z0 + 2.2
		desk(r, at(deskX, 0, dz, SOUTH), 7.5, 3, C.oak, label)
		office(r, at(deskX, 0, dz - 1.0, SOUTH), RGB(30, 30, 34))
		guestChair(r, at(deskX - 0.55, 0, dz + 1.1, NORTH), RGB(0, 118, 76))
		guestChair(r, at(deskX + 0.55, 0, dz + 1.1, NORTH), RGB(0, 118, 76))
		plant(r, at(x0 + 0.6, 0, z0 + 3.4), 0.9)
		picture(r, at(deskX, 6.8, z0 + 0.48 / M, SOUTH), 4, 2.4, pic)
		cabinet(r, at(x0 + 5.3, 0, z0 + 0.6, SOUTH), 2, 3.2, 1.8, 3, RGB(200, 200, 196))
	end
	consult("02", 0, 12, 2.8, "CONSULT B", 31)
	consult("01", 0, 16, 2.8, "CONSULT A", 32)
	consult("05", 24, 12, 27.4, "ADVISOR", 33)

	---------------------------------------------------------------- 04 CUSTOMER WC (accessible)
	do
		local r = R("04")
		roomLights(lights, 24, 16, 30, 20, 1, 1)
		-- tiled wainscot
		P(r, "Wainscot", Vector3.new(0.1, 4, 12 - 0.8), at(30 - 0.85 / M, 2, 18), RGB(200, 214, 222), MAT.CeramicTiles, true)
		P(r, "Wainscot", Vector3.new(18 - 0.8 - 0.8, 4, 0.1), at(27, 2, 20 - 0.85 / M), RGB(200, 214, 222), MAT.CeramicTiles, true)
		-- toilet against the east wall
		local wc = folder(r, "Toilet")
		local tcf = at(30 - 1.75 / M, 0, 17.5, WEST)
		P(wc, "Tank", Vector3.new(2, 1.6, 0.8), tcf * CFrame.new(0, 3.0, 0.5), C.white, MAT.SmoothPlastic)
		P(wc, "Bowl", Vector3.new(1.6, 1.6, 2.2), tcf * CFrame.new(0, 0.8, -0.8), C.white, MAT.SmoothPlastic)
		P(wc, "Seat", Vector3.new(1.7, 0.15, 2.3), tcf * CFrame.new(0, 1.68, -0.8), RGB(235, 235, 235), MAT.SmoothPlastic)
		-- grab bars
		P(r, "GrabBar", Vector3.new(0.2, 0.2, 4), at(30 - 0.95 / M, 3.0, 17.0), RGB(200, 200, 205), MAT.Metal, true)
		P(r, "GrabBar", Vector3.new(3, 0.2, 0.2), at(28.8, 3.0, 16 + 0.55 / M), RGB(200, 200, 205), MAT.Metal, true)
		-- sink + mirror on the south wall
		local scf = at(26.0, 0, 20 - 1.6 / M, NORTH)
		P(r, "Basin", Vector3.new(2.6, 0.6, 1.6), scf * CFrame.new(0, 2.7, 0), C.white, MAT.SmoothPlastic)
		P(r, "Tap", Vector3.new(0.2, 0.6, 0.6), scf * CFrame.new(0, 3.2, 0.5), RGB(200, 200, 205), MAT.Metal, true)
		local mir = P(r, "Mirror", Vector3.new(2.6, 3, 0.1), at(26.0, 6.0, 20 - 0.85 / M, NORTH), RGB(200, 214, 222), MAT.Glass, true)
		mir.Reflectance = 0.6
		P(r, "HandDryer", Vector3.new(1.4, 1.2, 0.8), at(28.2, 4.6, 20 - 1.2 / M, NORTH), RGB(220, 220, 224), MAT.Metal, true)
		cyl(r, "Bin", 1, 1.6, at(27.4, 0.8, 19.3), RGB(160, 160, 165), MAT.Metal, true)
	end

	---------------------------------------------------------------- exterior: siding, pilasters, cornice, sign
	do
		local fa = folder(root, "Facade")
		local OUTF = 0.8 / M -- outer face distance from the plan line (m)
		-- per side: axis, plan line, outward dir, from, to
		local sides = {
			{ "x", 0, -1, 0, 30 },
			{ "x", 20, 1, 0, 30 },
			{ "z", 0, -1, 0, 20 },
			{ "z", 30, 1, 0, 20 },
		}
		local boardH = (TOP - 1.6 - (BASE + 0.7)) / 7
		for _, sd in sides do
			local axis, f, dir, s, e = sd[1] :: string, sd[2] :: number, sd[3] :: number, sd[4] :: number, sd[5] :: number
			local len = (e - s) * M + 1.6 + 0.5
			local mid = (s + e) / 2
			local function place(y: number, outward: number, size: Vector3): CFrame
				local fo = f + dir * (OUTF + outward / M)
				if axis == "x" then
					return at(mid, y, fo)
				else
					return at(fo, y, mid)
				end
			end
			local function sz(along: number, h: number, depth: number): Vector3
				return if axis == "x" then Vector3.new(along, h, depth) else Vector3.new(depth, h, along)
			end
			-- horizontal siding boards
			local y = BASE + 0.7
			local n = 0
			while y + boardH <= TOP - 1.55 do
				n += 1
				P(fa, "Siding", sz(len, boardH - 0.16, 0.3), place(y + boardH / 2, 0.15, Vector3.zero), if n % 2 == 0 then C.siding else C.siding2, MAT.Plaster)
				y += boardH
			end
			-- ledge on top of the stone base
			P(fa, "BaseLedge", sz(len + 0.4, 0.7, 1.1), place(BASE + 0.35, 0.45, Vector3.zero), RGB(150, 140, 126), MAT.Concrete)
			-- low plinth
			P(fa, "Plinth", sz(len + 0.2, 1.2, 0.7), place(-FY + 0.6, 0.25, Vector3.zero), C.stoneDark, MAT.Concrete)
			-- cornice + coping
			P(fa, "Cornice", sz(len + 1.2, 1.3, 1.6), place(TOP - 1.0, 0.7, Vector3.zero), C.cornice, MAT.Wood)
			P(fa, "Coping", sz(len + 1.6, 0.4, 2.6 + 0.8), place(TOP - 0.15, 0.3, Vector3.zero), RGB(80, 50, 38), MAT.Wood)
			-- dark-brown pilasters
			local count = math.floor((e - s) * M / 15)
			for i = 0, count do
				local along = -((e - s) * M) / 2 + i * ((e - s) * M) / count
				local cf = place((BASE + TOP - 1.6) / 2 + 0.2, 0.55, Vector3.zero)
				local off = if axis == "x" then CFrame.new(along, 0, 0) else CFrame.new(0, 0, along)
				P(fa, "Pilaster", sz(1.7, TOP - 1.6 - BASE + 0.4, 1.1), cf * off, C.pilaster, MAT.Wood)
				-- small cap where the pilaster meets the ledge
				local cap = place(BASE + 0.9, 0.75, Vector3.zero)
				P(fa, "PilasterFoot", sz(2.1, 0.5, 1.5), cap * off, RGB(70, 46, 34), MAT.Wood)
			end
			-- wall lights on the base band (between the windows)
			local spots: { number } = if axis == "x" and f == 0 then { 5, 10, 18, 22 } elseif axis == "x" then { 5.9, 13.0, 17.0, 24.5 } else {}
			for _, px in spots do
				local along = (px - mid) * M
				local cf = place(BASE - 1.0, 0.45, Vector3.zero) * CFrame.new(along, 0, 0)
				P(fa, "Sconce", Vector3.new(0.8, 1.1, 0.6), cf, C.dark, MAT.Metal, true)
				local lamp = P(fa, "SconceLamp", Vector3.new(0.6, 0.2, 0.4), cf * CFrame.new(0, -0.6, 0), RGB(255, 230, 180), MAT.Neon, true)
				light(lamp, "spot", 1.2, 14, nil, Enum.NormalId.Bottom)
			end
		end

		-- entrance: canopy + green sign panel above the doors
		local ecf = at(15, 0, 20 + OUTF)
		P(fa, "Canopy", Vector3.new(14, 0.5, 5), ecf * CFrame.new(0, 9.6, 2.5), RGB(46, 48, 52), MAT.Metal)
		P(fa, "CanopyEdge", Vector3.new(14.2, 0.9, 0.3), ecf * CFrame.new(0, 9.5, 5.0), C.greenDark, MAT.Metal)
		local canopyLight = P(fa, "CanopyLight", Vector3.new(6, 0.1, 1.2), ecf * CFrame.new(0, 9.32, 2.5), RGB(255, 240, 210), MAT.Neon, true)
		light(canopyLight, "surface", 1.4, 14)
		local sign = P(fa, "EntranceSign", Vector3.new(16, 4.2, 0.7), ecf * CFrame.new(0, 12.9, 1.0), C.green, MAT.SmoothPlastic)
		P(fa, "EntranceSignTrim", Vector3.new(16.6, 4.8, 0.5), ecf * CFrame.new(0, 12.9, 0.7), RGB(235, 235, 230), MAT.SmoothPlastic)
		local sg = surf(sign, Enum.NormalId.Back, 25, true) -- Back faces +Z local = south = street
		logo(sg, UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.2, 0.76))
		text(sg, "ATLAS BANK", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.28, 0.14), UDim2.fromScale(0.68, 0.56), Enum.TextXAlignment.Left)
		text(sg, "SAVINGS  -  LOANS  -  ATM", RGB(190, 240, 210), Enum.Font.GothamBold, UDim2.fromScale(0.28, 0.68), UDim2.fromScale(0.62, 0.2), Enum.TextXAlignment.Left)
		light(sign, "surface", 0.8, 10, RGB(160, 255, 200), Enum.NormalId.Back)
		-- opening-hours plate + security camera at the entrance
		local hours = P(fa, "Hours", Vector3.new(2.4, 3, 0.1), at(17.2, 4.8, 20 + OUTF + 0.06 / M, SOUTH), RGB(30, 34, 40), MAT.SmoothPlastic, true)
		local hg = surf(hours, Enum.NormalId.Front, 60)
		text(hg, "OPEN", RGB(120, 240, 170), Enum.Font.GothamBlack, UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.22))
		text(hg, "MON-FRI 9-17\nSAT 9-12", C.white, Enum.Font.Gotham, UDim2.fromScale(0.1, 0.36), UDim2.fromScale(0.8, 0.5))
		camera(fa, at(18.6, 8.4, 20 + OUTF + 0.4 / M, SOUTH))
		-- night-deposit slot beside the door
		P(fa, "NightDeposit", Vector3.new(2, 1.4, 0.4), at(18.4, 4.0, 20 + OUTF + 0.2 / M), RGB(150, 152, 156), MAT.Metal, true)
		P(fa, "NightDepositSlot", Vector3.new(1.4, 0.15, 0.1), at(18.4, 4.2, 20 + OUTF + 0.42 / M), RGB(20, 20, 20), MAT.SmoothPlastic, true)
	end

	---------------------------------------------------------------- roof equipment
	do
		local rf = folder(root, "Roof")
		local ry = H + 1.5
		for i, x in { 6, 15, 23 } do
			local u = folder(rf, "ACUnit" .. i)
			P(u, "Body", Vector3.new(7, 3.4, 5), at(x, ry + 1.7, 6), RGB(196, 198, 200), MAT.Metal)
			cyl(u, "Fan", 3.2, 0.3, at(x, ry + 3.5, 6), RGB(60, 62, 66), MAT.Metal, true)
			P(u, "Duct", Vector3.new(1.6, 1.4, 4), at(x, ry + 0.7, 6) * CFrame.new(0, 0, 4.4), RGB(170, 172, 176), MAT.Metal, true)
		end
		for k, x in { 4, 11, 19, 27 } do
			cyl(rf, "VentPipe", 0.8, 2.2, at(x, ry + 1.1, 14 + (k % 2)), RGB(150, 152, 156), MAT.Metal, true)
			cyl(rf, "VentCap", 1.4, 0.3, at(x, ry + 2.3, 14 + (k % 2)), RGB(150, 152, 156), MAT.Metal, true)
		end
		local dish = P(rf, "SatDish", Vector3.new(3, 3, 0.4), at(27.5, ry + 3, 16) * CFrame.Angles(math.rad(-35), math.rad(-30), 0), RGB(230, 230, 230), MAT.SmoothPlastic, true)
		dish.Shape = Enum.PartType.Cylinder
		dish.Size = Vector3.new(0.4, 3, 3)
		dish.CFrame = at(27.5, ry + 2.6, 16) * CFrame.Angles(math.rad(-35), math.rad(60), 0)
		P(rf, "DishPole", Vector3.new(0.3, 2.4, 0.3), at(27.5, ry + 1.2, 16), RGB(120, 120, 125), MAT.Metal, true)
		P(rf, "Hatch", Vector3.new(4, 0.8, 4), at(2.5, ry + 0.4, 2.5), RGB(120, 124, 130), MAT.DiamondPlate)
		-- rear ladder on the north facade
		local lcf = at(27.5, 0, -2.3 / M)
		for sx = -1, 1, 2 do
			P(rf, "LadderRail", Vector3.new(0.25, TOP + 2, 0.25), lcf * CFrame.new(sx * 1.0, (TOP + 2) / 2, 0), RGB(150, 152, 156), MAT.Metal, true)
		end
		for k = 1, 20 do
			P(rf, "Rung", Vector3.new(2, 0.15, 0.15), lcf * CFrame.new(0, k * 1.1, 0), RGB(150, 152, 156), MAT.Metal, true)
		end
	end

	---------------------------------------------------------------- site: sidewalk, street, parking, landscaping
	do
		local s = site
		local function ground(name: string, x0: number, z0: number, x1: number, z1: number, top: number, col: Color3, mat: Enum.Material, thick: number?)
			-- x/z in local studs (centre of the plan = 0,0), top in world-ish studs above y=0
			local t = thick or 1
			return P(s, name, Vector3.new(x1 - x0, t, z1 - z0), ROOT * CFrame.new((x0 + x1) / 2, top - t / 2, (z0 + z1) / 2), col, mat)
		end
		-- building is local x -45..45, z -30..30
		ground("Sidewalk", -62, 30.8, 50, 44, FY, RGB(196, 192, 184), MAT.Concrete)
		ground("SidewalkWest", -62, -46, -46.6, 30.8, FY, RGB(196, 192, 184), MAT.Concrete)
		ground("ServiceAlley", -62, -62, 50, -46, 0.08, RGB(64, 66, 70), MAT.Asphalt, 0.2)
		ground("SideStrip", -46.6, -46, -45.8, 30.8, FY, RGB(196, 192, 184), MAT.Concrete)
		ground("RearStrip", -46.6, -31.6, 46.6, -30.8, FY, RGB(196, 192, 184), MAT.Concrete)
		ground("EastStrip", 45.8, -31.6, 50, 30.8, FY, RGB(196, 192, 184), MAT.Concrete)
		ground("RearPad", -46, -46, 50, -31.6, FY - 0.05, RGB(186, 182, 174), MAT.Concrete)
		ground("Curb", -62, 43.6, 100, 44.4, FY + 0.05, RGB(220, 216, 208), MAT.Concrete)
		local road = ground("Street", -140, 44.4, 160, 66, 0.08, RGB(52, 54, 58), MAT.Asphalt, 0.2)
		road.Name = "Street"
		for k = 0, 16 do
			P(s, "LaneDash", Vector3.new(8, 0.05, 0.5), ROOT * CFrame.new(-130 + k * 18, 0.105, 55.2), RGB(240, 200, 40), MAT.SmoothPlastic, true)
		end
		ground("FarSidewalk", -140, 66, 160, 76, FY, RGB(196, 192, 184), MAT.Concrete)
		-- parking lot east of the bank
		ground("Parking", 50, -46, 100, 44.4, 0.08, RGB(60, 62, 66), MAT.Asphalt, 0.2)
		for k = 0, 5 do
			P(s, "StallLine", Vector3.new(0.4, 0.05, 14), ROOT * CFrame.new(58 + k * 8.5, 0.11, -18), RGB(235, 235, 235), MAT.SmoothPlastic, true)
			P(s, "StallLine", Vector3.new(0.4, 0.05, 14), ROOT * CFrame.new(58 + k * 8.5, 0.11, 12), RGB(235, 235, 235), MAT.SmoothPlastic, true)
		end
		P(s, "AccessibleBay", Vector3.new(8.1, 0.05, 13.6), ROOT * CFrame.new(62.25, 0.1, 12), RGB(30, 90, 170), MAT.SmoothPlastic, true)
		-- simple parked cars
		local function car(cf: CFrame, col: Color3)
			local m = folder(s, "ParkedCar")
			P(m, "Body", Vector3.new(6.2, 2.0, 13), cf * CFrame.new(0, 1.9, 0), col, MAT.SmoothPlastic)
			P(m, "Cabin", Vector3.new(5.6, 1.9, 6.6), cf * CFrame.new(0, 3.85, 0.6), col, MAT.SmoothPlastic)
			local gl = P(m, "Windows", Vector3.new(5.7, 1.5, 6.0), cf * CFrame.new(0, 3.9, 0.6), RGB(30, 40, 46), MAT.Glass, true)
			gl.Transparency = 0.2
			gl.Size = Vector3.new(5.72, 1.5, 6.7)
			for _, o in { Vector3.new(3, 0, 4), Vector3.new(-3, 0, 4), Vector3.new(3, 0, -4), Vector3.new(-3, 0, -4) } do
				local wcf = cf * CFrame.new(o.X, 1.1, o.Z)
				local w = P(m, "Wheel", Vector3.new(0.9, 2.2, 2.2), wcf, RGB(25, 25, 25), MAT.Rubber)
				w.Shape = Enum.PartType.Cylinder
			end
			P(m, "Headlight", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(2.2, 2.2, -6.52), RGB(255, 250, 220), MAT.Neon, true)
			P(m, "Headlight", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(-2.2, 2.2, -6.52), RGB(255, 250, 220), MAT.Neon, true)
			P(m, "Taillight", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(2.2, 2.2, 6.52), RGB(200, 20, 20), MAT.Neon, true)
			P(m, "Taillight", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(-2.2, 2.2, 6.52), RGB(200, 20, 20), MAT.Neon, true)
		end
		car(ROOT * CFrame.new(70.75, 0.1, -18), RGB(30, 30, 34))
		car(ROOT * CFrame.new(87.75, 0.1, 12) * CFrame.Angles(0, math.pi, 0), RGB(170, 30, 36))
		car(ROOT * CFrame.new(-20, 0.1, 61) * CFrame.Angles(0, math.pi / 2, 0), RGB(220, 220, 224))

		-- hedges in planters along the front (leave the entrance clear)
		for _, span in { { -44, -9 }, { 9, 44 } } do
			local a, b = span[1], span[2]
			local cfp = ROOT * CFrame.new((a + b) / 2, FY, 33.2)
			P(s, "Planter", Vector3.new(b - a, 1.2, 2.8), cfp * CFrame.new(0, 0.6, 0), RGB(170, 164, 154), MAT.Concrete)
			P(s, "Hedge", Vector3.new(b - a - 0.6, 2.2, 2.2), cfp * CFrame.new(0, 2.2, 0), RGB(58, 110, 48), MAT.Grass)
		end
		-- street trees
		local function tree(cf: CFrame)
			local m = folder(s, "Tree")
			P(m, "Grate", Vector3.new(5, 0.1, 5), cf * CFrame.new(0, 0.05, 0), RGB(60, 62, 64), MAT.Metal, true)
			cyl(m, "Trunk", 1.1, 12, cf * CFrame.new(0, 6, 0), RGB(96, 72, 52), MAT.Wood)
			ball(m, "Crown", 9, cf * CFrame.new(0, 14, 0), RGB(66, 120, 56), MAT.Grass, true)
			ball(m, "Crown", 6.5, cf * CFrame.new(2.6, 12.4, 1.2), RGB(80, 138, 62), MAT.Grass, true)
			ball(m, "Crown", 6, cf * CFrame.new(-2.4, 12.8, -1.4), RGB(72, 128, 58), MAT.Grass, true)
		end
		tree(ROOT * CFrame.new(-30, FY, 40))
		tree(ROOT * CFrame.new(22, FY, 40))
		tree(ROOT * CFrame.new(-54, FY, -10))
		-- street lamps
		for _, x in { -40, 30 } do
			local cfp = ROOT * CFrame.new(x, FY, 42.6)
			cyl(s, "LampPole", 0.6, 20, cfp * CFrame.new(0, 10, 0), RGB(60, 62, 66), MAT.Metal)
			P(s, "LampArm", Vector3.new(0.4, 0.4, 5), cfp * CFrame.new(0, 19.8, 2.4), RGB(60, 62, 66), MAT.Metal, true)
			local head = P(s, "LampHead", Vector3.new(1.6, 0.5, 2.6), cfp * CFrame.new(0, 19.6, 4.8), RGB(240, 230, 200), MAT.Neon, true)
			light(head, "spot", 2, 30, RGB(255, 226, 180), Enum.NormalId.Bottom)
		end

		-- tall green pylon sign at the front corner
		local py = folder(s, "PylonSign")
		local pcf = ROOT * CFrame.new(40, FY, 40)
		P(py, "Footing", Vector3.new(4, 1.2, 4), pcf * CFrame.new(0, 0.6, 0), RGB(170, 164, 154), MAT.Concrete)
		P(py, "Pole", Vector3.new(1.6, 22, 1.6), pcf * CFrame.new(0, 11, 0), RGB(70, 74, 80), MAT.Metal)
		local box = P(py, "SignBox", Vector3.new(1.8, 13, 10), pcf * CFrame.new(0, 27, 0), C.greenDark, MAT.SmoothPlastic)
		for side = -1, 1, 2 do
			local face = P(py, "SignFace", Vector3.new(0.1, 12.2, 9.2), pcf * CFrame.new(side * 0.93, 27, 0), C.green, MAT.SmoothPlastic, true)
			local g = surf(face, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, 12, true)
			logo(g, UDim2.fromScale(0.18, 0.06), UDim2.fromScale(0.64, 0.44))
			text(g, "ATLAS", C.white, Enum.Font.GothamBlack, UDim2.fromScale(0.06, 0.55), UDim2.fromScale(0.88, 0.2))
			text(g, "BANK", RGB(200, 255, 220), Enum.Font.GothamBold, UDim2.fromScale(0.2, 0.77), UDim2.fromScale(0.6, 0.15))
		end
		P(py, "SignTop", Vector3.new(2.2, 0.6, 10.4), pcf * CFrame.new(0, 33.8, 0), RGB(235, 235, 230), MAT.SmoothPlastic)
		P(py, "SignBottom", Vector3.new(2.2, 0.6, 10.4), pcf * CFrame.new(0, 20.2, 0), RGB(235, 235, 230), MAT.SmoothPlastic)
		light(box, "point", 1.2, 16, RGB(120, 255, 170))
		py:PivotTo(py:GetPivot() * CFrame.Angles(0, math.rad(-35), 0))

		-- flag pole on the west front corner
		local fp = folder(s, "FlagPole")
		local fcf = ROOT * CFrame.new(-54, FY, 40)
		P(fp, "Base", Vector3.new(3, 1, 3), fcf * CFrame.new(0, 0.5, 0), RGB(170, 164, 154), MAT.Concrete)
		cyl(fp, "Pole", 0.5, 34, fcf * CFrame.new(0, 17.5, 0), RGB(225, 225, 228), MAT.Metal)
		ball(fp, "Finial", 0.9, fcf * CFrame.new(0, 34.8, 0), RGB(220, 190, 80), MAT.Metal, true)
		local flag = P(fp, "Flag", Vector3.new(8, 4.6, 0.08), fcf * CFrame.new(4.25, 31.6, 0), C.white, MAT.Fabric, true)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local g = surf(flag, face, 20)
			for k = 0, 12 do
				frame(g, if k % 2 == 0 then RGB(178, 34, 52) else C.white, UDim2.fromScale(0, k / 13), UDim2.fromScale(1, 1 / 13 + 0.002))
			end
			local cx0 = if face == Enum.NormalId.Front then 0 else 0.6
			local canton = frame(g, RGB(60, 59, 110), UDim2.fromScale(cx0, 0), UDim2.fromScale(0.4, 7 / 13))
			for r2 = 0, 4 do
				for c2 = 0, 5 do
					frame(canton, C.white, UDim2.fromScale(0.07 + c2 * 0.155, 0.08 + r2 * 0.19), UDim2.fromScale(0.05, 0.08), 1)
				end
			end
		end
		flag.CFrame = flag.CFrame * CFrame.Angles(0, math.rad(-12), 0)

		-- service side: dumpster + AC condensers by the rear
		local dm = folder(s, "Dumpster")
		local dcf = ROOT * CFrame.new(-30, FY - 0.05, -40)
		P(dm, "Bin", Vector3.new(9, 5, 5), dcf * CFrame.new(0, 2.5, 0), RGB(30, 90, 60), MAT.Metal)
		P(dm, "Lid", Vector3.new(9.2, 0.3, 5.2), dcf * CFrame.new(0, 5.15, 0) * CFrame.Angles(math.rad(-6), 0, 0), RGB(30, 30, 32), MAT.Plastic)
		for k = 0, 1 do
			local ccf = ROOT * CFrame.new(10 + k * 7, FY - 0.05, -37)
			P(s, "Condenser", Vector3.new(5, 4, 5), ccf * CFrame.new(0, 2, 0), RGB(200, 200, 198), MAT.Metal)
			cyl(s, "CondenserFan", 3.6, 0.2, ccf * CFrame.new(0, 4.1, 0), RGB(50, 50, 52), MAT.Metal, true)
		end
		-- exit landings + lights at both corridor doors
		for _, x in { -1, 1 } do
			local lcf = ROOT * CFrame.new(x * 45.8 + x * 2.4, 0, 0) * CFrame.new(0, 0, (8 - 10) * M)
			local _ = lcf
			local wl = P(s, "ExitLight", Vector3.new(0.6, 0.6, 1.0), ROOT * CFrame.new(x * 46.2, FY + 10, (8 - 10) * M), RGB(255, 240, 210), MAT.Neon, true)
			light(wl, "point", 1, 12)
		end
		-- bollards in front of the entrance
		for k = -2, 2 do
			if k ~= 0 then
				cyl(s, "Bollard", 1, 3, ROOT * CFrame.new(k * 3.4, FY + 1.5, 41.5), RGB(60, 62, 66), MAT.Metal)
			end
		end
	end

	-- decoration parts never block the camera or bullets inside the hall
	root:SetAttribute("Built", os.time())
	root.Parent = workspace
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return string.format("AtlasBank built: %d parts, %d doors", n, #CollectionService:GetTagged("BankDoor"))
end

return build
