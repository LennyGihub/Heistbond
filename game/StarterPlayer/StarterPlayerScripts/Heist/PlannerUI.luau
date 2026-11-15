--!strict
-- The heist planner: a live top-down view of the bank (a copy in a ViewportFrame, north up), two
-- floors (ROOF / GROUND: the ground view hides the roof and ceilings), zoom (wheel, +/-) and pan (drag).
-- Tabs: METHOD (only what scouting revealed), VEHICLES (place on the map + arrival time), EQUIPMENT (my
-- loadout from my inventory), NOTES (pins with text for the crew). The plan is shared by everyone in
-- the server and never locks anything during the heist.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Heist = ReplicatedStorage:WaitForChild("Heist")
local B = require(Heist:WaitForChild("Blocky"))
local Items = require(Heist:WaitForChild("Items"))
local Noobla = require(Heist:WaitForChild("Noobla"))
local C = B.C

local NOTE_COLORS = { C.yellow, C.red, C.blue, C.green, C.orange, C.purple }
local FLOOR_Y = { ground = 0.5, roof = 20 }
local H = 700 -- camera height

return function(shared: any)
	local M = {}
	local player = Players.LocalPlayer
	local panel, body = B.panel(shared.gui, { Name = "Planner", Size = UDim2.new(1, -40, 1, -40), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Visible = false, ZIndex = 10 }, "PLAN DU BRAQUAGE - LA NOOBLA BANK", C.dark)
	B.button(panel, "X", C.red, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -54, 0, 0), ZIndex = 14 }, function()
		M.close()
	end)

	---------------------------------------------------------------- map
	local mapFrame = B.new("Frame", { Name = "Map", BackgroundColor3 = C.black, BorderSizePixel = 0, Size = UDim2.new(0.6, 0, 1, -64),
		ClipsDescendants = true, ZIndex = 11 }, body)
	B.outline(mapFrame, 4)
	local vp = B.new("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 90, 70), Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.fromRGB(255, 250, 240), LightDirection = Vector3.new(-0.4, -1, -0.3), ZIndex = 11 }, mapFrame)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 20
	cam.Parent = vp
	vp.CurrentCamera = cam
	local overlay = B.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12, AutoButtonColor = false }, mapFrame)
	local markers = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 13 }, mapFrame)
	local hint = B.label(mapFrame, "", { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 1, -44), ZIndex = 16, MaxText = 20, TextColor3 = C.yellow })
	local floorBar = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 44), Position = UDim2.fromOffset(10, 10), ZIndex = 15 }, mapFrame)
	B.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, floorBar)
	local floor = "ground"
	local zoomFov = 13
	local pan = Vector3.zero
	local center = Vector3.new(0, 0, 260)
	local roofLayer: Instance? = nil
	local copy: Model? = nil
	local mode: string? = nil
	local pinColor = 1
	local selected: number? = nil

	local function buildCopy()
		if copy then
			return
		end
		local bank = workspace:FindFirstChild("NooblaBank")
		if not bank then
			return
		end
		local rc = bank:GetAttribute("Root")
		if typeof(rc) == "CFrame" then
			center = rc.Position
		end
		local c = bank:Clone()
		for _, d in c:GetDescendants() do
			if d:IsA("ProximityPrompt") or d:IsA("Light") or d:IsA("Sound") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
		c.Parent = vp
		copy = c
		roofLayer = c:FindFirstChild("RoofLayer")
		local roads = workspace:FindFirstChild("HeistRoads")
		if roads then
			roads:Clone().Parent = vp
		end
		-- big grass ground under everything
		B.new("Part", { Anchored = true, Size = Vector3.new(900, 1, 900), Position = Vector3.new(center.X, -0.6, center.Z), Color = Color3.fromRGB(96, 140, 80),
			Material = Enum.Material.Grass, TopSurface = Enum.SurfaceType.Smooth }, vp)
	end

	-- projection: camera straight down, north (+Z world) at the top, east (-X world) to the right
	local function eye(): Vector3
		return center + pan + Vector3.new(0, H, 0)
	end
	local function project(p: Vector3): (number, number)
		local size = mapFrame.AbsoluteSize
		local e = eye()
		local depth = e.Y - p.Y
		local tanH = math.tan(math.rad(zoomFov / 2))
		local aspect = size.X / math.max(1, size.Y)
		local x = -(p.X - e.X) / (depth * tanH * aspect)
		local y = (p.Z - e.Z) / (depth * tanH)
		return (x + 1) / 2 * size.X, (1 - y) / 2 * size.Y
	end
	local function unproject(u: number, v: number, planeY: number): Vector3
		local size = mapFrame.AbsoluteSize
		local e = eye()
		local depth = e.Y - planeY
		local tanH = math.tan(math.rad(zoomFov / 2))
		local aspect = size.X / math.max(1, size.Y)
		local x = u / size.X * 2 - 1
		local y = 1 - v / size.Y * 2
		return Vector3.new(e.X - x * depth * tanH * aspect, planeY, e.Z + y * depth * tanH)
	end
	local function updateCamera()
		local e = eye()
		cam.FieldOfView = zoomFov
		cam.CFrame = CFrame.lookAt(e, e - Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
	end

	local floorButtons: { [string]: TextButton } = {}
	local function setFloor(f: string)
		floor = f
		if roofLayer then
			roofLayer.Parent = if f == "roof" then copy else nil
		end
		for k, b in floorButtons do
			B.setButton(b, nil, if k == f then C.yellow else C.dark)
		end
		M.renderMarkers()
	end
	floorButtons.roof = B.button(floorBar, "TOIT", C.dark, { Size = UDim2.fromOffset(110, 40), ZIndex = 15 }, function()
		setFloor("roof")
	end)
	floorButtons.ground = B.button(floorBar, "REZ-DE-CHAUSSÉE", C.yellow, { Size = UDim2.fromOffset(200, 40), ZIndex = 15 }, function()
		setFloor("ground")
	end)
	B.button(mapFrame, "+", C.dark, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -54, 0, 10), ZIndex = 15 }, function()
		zoomFov = math.clamp(zoomFov - 3, 6, 30)
		updateCamera()
	end)
	B.button(mapFrame, "-", C.dark, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -54, 0, 58), ZIndex = 15 }, function()
		zoomFov = math.clamp(zoomFov + 3, 6, 30)
		updateCamera()
	end)

	---------------------------------------------------------------- right side: tabs
	local side = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.4, -14, 1, -64), Position = UDim2.new(0.6, 14, 0, 0), ZIndex = 11 }, body)
	local tabBar = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), ZIndex = 11 }, side)
	B.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, tabBar)
	local content = B.new("ScrollingFrame", { BackgroundColor3 = C.darker, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -54), Position = UDim2.fromOffset(0, 54),
		ScrollBarThickness = 8, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 11 }, side)
	B.outline(content, 3)
	B.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 10) }, content)
	B.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	local tab = "method"
	local tabButtons: { [string]: TextButton } = {}

	-- bottom bar
	local bottom = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 1, -52), ZIndex = 11 }, body)
	local summary = B.label(bottom, "", { Size = UDim2.new(0.6, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20, ZIndex = 12 })
	local armed = false
	local launch: TextButton
	launch = B.button(bottom, "LANCER LE BRAQUAGE", C.green, { Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.fromScale(0.62, 0), ZIndex = 12 }, function()
		if not armed then
			armed = true
			B.setButton(launch, "SÛR ? RE-CLIQUE !", C.orange)
			task.delay(3, function()
				armed = false
				B.setButton(launch, "LANCER LE BRAQUAGE", C.green)
			end)
			return
		end
		armed = false
		B.setButton(launch, "LANCER LE BRAQUAGE", C.green)
		local ok, msg = shared.request("StartHeist")
		if ok then
			M.close()
		elseif msg then
			B.toast(msg, C.red)
		end
	end)

	local function plan(): any
		return shared.plan or { method = "", vehicles = {}, pins = {}, loadouts = {} }
	end
	local function prof(): any
		return shared.profile or { cash = 0, inv = {}, intel = {} }
	end
	local function edit(...: any)
		local ok, msg = shared.request("PlanEdit", ...)
		if not ok and msg then
			B.toast(msg, C.red)
		end
		return ok
	end

	local order = 0
	local function row(h: number, col: Color3?): Frame
		order += 1
		local f = B.new("Frame", { BackgroundColor3 = col or C.dark, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h), LayoutOrder = order, ZIndex = 12 }, content)
		B.outline(f, 3)
		return f
	end
	local function heading(text: string)
		order += 1
		B.label(content, text, { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, ZIndex = 12, FontFace = B.TITLE, TextColor3 = C.yellow,
			TextXAlignment = Enum.TextXAlignment.Left, MaxText = 22 })
	end
	local function clear()
		for _, c in content:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		order = 0
	end

	---------------------------------------------------------------- METHOD tab
	local function renderMethod()
		heading("ENTRER DANS LE COFFRE")
		local p = prof()
		for _, m in Noobla.methods do
			local known = p.intel[m.id] == true
			local chosen = plan().method == m.id
			local r = row(118, if chosen then C.green elseif known and not m.locked then C.dark else C.darker)
			local badge = B.new("Frame", { BackgroundColor3 = if known then C.yellow else C.grey, BorderSizePixel = 0, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8), ZIndex = 13 }, r)
			B.outline(badge, 3)
			B.label(badge, tostring(m.n), { FontFace = B.TITLE, ZIndex = 14, TextColor3 = C.black, MaxText = 34 })
			if known or m.locked then
				B.label(r, m.name, { Size = UDim2.new(1, -190, 0, 28), Position = UDim2.fromOffset(66, 6), ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20 })
				B.label(r, m.desc, { Size = UDim2.new(1, -76, 0, 44), Position = UDim2.fromOffset(66, 34), ZIndex = 13, FontFace = B.FONT_REG, TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxText = 15 })
				B.label(r, "Il faut : " .. m.needs .. "   |   " .. m.alert, { Size = UDim2.new(1, -76, 0, 24), Position = UDim2.fromOffset(66, 84), ZIndex = 13,
					TextColor3 = C.yellow, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14 })
			else
				B.label(r, "? ? ?", { Size = UDim2.new(1, -190, 0, 28), Position = UDim2.fromOffset(66, 6), ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20 })
				B.label(r, "Méthode inconnue : fais des repérages à la banque pour la découvrir.", { Size = UDim2.new(1, -76, 0, 50), Position = UDim2.fromOffset(66, 36),
					ZIndex = 13, FontFace = B.FONT_REG, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 15 })
			end
			if m.locked then
				B.label(r, "BIENTÔT", { Size = UDim2.fromOffset(110, 34), Position = UDim2.new(1, -120, 0, 6), ZIndex = 13, TextColor3 = C.orange, Rotation = 8, MaxText = 22 })
			elseif known then
				B.button(r, if chosen then "CHOISIE" else "CHOISIR", if chosen then C.yellow else C.blue, { Size = UDim2.fromOffset(110, 36), Position = UDim2.new(1, -120, 0, 6), ZIndex = 14 }, function()
					edit("method", if chosen then "" else m.id)
				end)
			end
		end
		heading("REPÉRAGES")
		for _, k in Noobla.clueOrder do
			local info = Noobla.intel[k]
			local got = p.intel[k] == true
			local r = row(if got then 92 else 40, if got then C.sand else C.darker)
			local t = B.label(r, (if got then "[X] " .. info.title else "[ ] ???"), { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 6), ZIndex = 13,
				TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17, TextColor3 = if got then C.black else C.grey })
			if got then
				t:FindFirstChildOfClass("UIStroke"):Destroy()
				local d = B.label(r, info.text, { Size = UDim2.new(1, -16, 0, 54), Position = UDim2.fromOffset(8, 34), ZIndex = 13, FontFace = B.FONT_REG, TextWrapped = true,
					TextColor3 = C.black, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxText = 13 })
				d:FindFirstChildOfClass("UIStroke"):Destroy()
			end
		end
	end

	---------------------------------------------------------------- VEHICLES tab
	local function vehName(kind: string): string
		return Items.byId[kind] and Items.byId[kind].name or kind
	end
	local function renderVehicles()
		heading("TES VÉHICULES")
		local used: { [string]: number } = {}
		for _, v in plan().vehicles do
			if v.by == player.UserId then
				used[v.kind] = (used[v.kind] or 0) + 1
			end
		end
		for _, it in Items.list do
			if it.kind == "vehicle" then
				local have = (prof().inv[it.id] or 0) - (used[it.id] or 0)
				local r = row(64)
				B.icon(r, it, { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8), ZIndex = 13 })
				B.label(r, it.name, { Size = UDim2.new(1, -200, 0, 26), Position = UDim2.fromOffset(66, 6), ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
				B.label(r, "Dispo : " .. have, { Size = UDim2.new(1, -200, 0, 22), Position = UDim2.fromOffset(66, 34), ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = if have > 0 then C.yellow else C.red, MaxText = 15 })
				B.button(r, "PLACER", if have > 0 then C.blue else C.grey, { Size = UDim2.fromOffset(110, 40), Position = UDim2.new(1, -120, 0, 12), ZIndex = 14 }, function()
					if have <= 0 then
						B.toast("Plus de " .. it.name .. " disponible.", C.red)
						return
					end
					mode = "vehicle:" .. it.id
					setFloor("ground")
				end)
			end
		end
		heading("DANS LE PLAN")
		if #plan().vehicles == 0 then
			B.label(row(40, C.darker), "Aucun véhicule. Clique PLACER puis sur la carte.", { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), ZIndex = 13, MaxText = 15 })
		end
		for _, v in plan().vehicles do
			local r = row(96, if selected == v.id then C.blue else C.dark)
			B.icon(r, Items.byId[v.kind], { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8), ZIndex = 13 })
			B.label(r, vehName(v.kind) .. " (" .. v.byName .. ")", { Size = UDim2.new(1, -76, 0, 26), Position = UDim2.fromOffset(66, 6), ZIndex = 13,
				TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16 })
			B.label(r, "Arrive à T+" .. B.clock(v.t), { Size = UDim2.new(0, 170, 0, 24), Position = UDim2.fromOffset(66, 34), ZIndex = 13, TextColor3 = C.yellow,
				TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16 })
			local function bt(text: string, x: number, col: Color3, w: number, fn: () -> ())
				B.button(r, text, col, { Size = UDim2.fromOffset(w, 32), Position = UDim2.fromOffset(x, 60), ZIndex = 14 }, fn)
			end
			bt("-30s", 8, C.dark, 62, function()
				edit("timeVehicle", v.id, v.t - 30)
			end)
			bt("+30s", 76, C.dark, 62, function()
				edit("timeVehicle", v.id, v.t + 30)
			end)
			bt("+1min", 144, C.dark, 70, function()
				edit("timeVehicle", v.id, v.t + 60)
			end)
			bt("DÉPLACER", 220, C.blue, 100, function()
				mode = "move:" .. v.id
				selected = v.id
				setFloor("ground")
			end)
			bt("X", 326, C.red, 40, function()
				edit("removeVehicle", v.id)
			end)
		end
	end

	---------------------------------------------------------------- EQUIPMENT tab (my loadout)
	local WEAPON_CYCLE = { "", "pistol", "rifle", "sniper" }
	local function myLoadout(): any
		local lo = plan().loadouts[tostring(player.UserId)]
		if not lo then
			lo = { weapons = { { kind = "pistol", silencer = true, grip = false, holo = false } }, items = { zipties = 4, hackkey = 1 }, vest = false }
		end
		return lo
	end
	local function sendLoadout(lo: any)
		edit("loadout", lo)
	end
	local function renderEquip()
		local lo = myLoadout()
		local p = prof()
		heading("ARMES (2 MAX)")
		for slot = 1, 2 do
			local w = lo.weapons[slot]
			local r = row(104)
			local kind = w and w.kind or ""
			local it = Items.byId[kind]
			if it then
				B.icon(r, it, { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8), ZIndex = 13 })
			end
			B.label(r, "Arme " .. slot .. " : " .. (if it then it.name else "aucune"), { Size = UDim2.new(1, -200, 0, 26), Position = UDim2.fromOffset(66, 8), ZIndex = 13,
				TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17 })
			B.button(r, "CHANGER", C.blue, { Size = UDim2.fromOffset(110, 36), Position = UDim2.new(1, -120, 0, 8), ZIndex = 14 }, function()
				local idx = table.find(WEAPON_CYCLE, kind) or 1
				local new = WEAPON_CYCLE[idx % #WEAPON_CYCLE + 1]
				local copyLo = table.clone(lo)
				copyLo.weapons = table.clone(lo.weapons)
				if new == "" then
					table.remove(copyLo.weapons, slot)
				elseif copyLo.weapons[slot] then
					copyLo.weapons[slot] = { kind = new, silencer = new ~= "sniper" and copyLo.weapons[slot].silencer, grip = new == "rifle" and copyLo.weapons[slot].grip, holo = new == "rifle" and copyLo.weapons[slot].holo }
				else
					table.insert(copyLo.weapons, { kind = new, silencer = new ~= "sniper", grip = false, holo = false })
				end
				sendLoadout(copyLo)
			end)
			if w then
				local x = 66
				for _, att in { { "silencer", "SIL." }, { "grip", "POIGNÉE" }, { "holo", "HOLO" } } do
					local allowed = (att[1] == "silencer" and kind ~= "sniper") or kind == "rifle"
					if allowed then
						local on = w[att[1]] == true
						B.button(r, att[2], if on then C.green else C.darker, { Size = UDim2.fromOffset(104, 36), Position = UDim2.fromOffset(x, 56), ZIndex = 14 }, function()
							local copyLo = table.clone(lo)
							copyLo.weapons = table.clone(lo.weapons)
							local nw = table.clone(w)
							nw[att[1]] = not on
							copyLo.weapons[slot] = nw
							sendLoadout(copyLo)
						end)
						x += 112
					end
				end
			end
		end
		heading("ÉQUIPEMENT")
		do
			local r = row(64)
			B.icon(r, Items.byId.vest, { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8), ZIndex = 13 })
			B.label(r, "Veste lourde (x" .. (p.inv.vest or 0) .. ")", { Size = UDim2.new(1, -200, 0, 26), Position = UDim2.fromOffset(66, 18), ZIndex = 13,
				TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17 })
			B.button(r, if lo.vest then "PORTÉE" else "NON", if lo.vest then C.green else C.darker, { Size = UDim2.fromOffset(110, 40), Position = UDim2.new(1, -120, 0, 12), ZIndex = 14 }, function()
				local copyLo = table.clone(lo)
				copyLo.vest = not lo.vest
				sendLoadout(copyLo)
			end)
		end
		heading("OUTILS")
		for _, it in Items.list do
			if it.kind == "tool" then
				local n = lo.items[it.id] or 0
				local have = p.inv[it.id] or 0
				local r = row(64)
				B.icon(r, it, { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 8), ZIndex = 13 })
				B.label(r, it.name, { Size = UDim2.new(1, -230, 0, 24), Position = UDim2.fromOffset(66, 6), ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16 })
				B.label(r, "Pris : " .. n .. " / " .. have, { Size = UDim2.new(1, -230, 0, 22), Position = UDim2.fromOffset(66, 34), ZIndex = 13,
					TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if n > 0 then C.yellow else C.grey, MaxText = 15 })
				local function change(d: number)
					local copyLo = table.clone(lo)
					copyLo.items = table.clone(lo.items)
					copyLo.items[it.id] = math.clamp(n + d, 0, math.min(have, 20))
					sendLoadout(copyLo)
				end
				B.button(r, "-", C.dark, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -104, 0, 12), ZIndex = 14 }, function()
					change(-1)
				end)
				B.button(r, "+", C.blue, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -52, 0, 12), ZIndex = 14 }, function()
					change(1)
				end)
			end
		end
	end

	---------------------------------------------------------------- NOTES tab
	local function renderNotes()
		heading("NOTES POUR L'ÉQUIPE")
		local r = row(64)
		local x = 8
		for i, col in NOTE_COLORS do
			local sw = B.new("TextButton", { Text = "", BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(x, 12), ZIndex = 14, AutoButtonColor = false }, r)
			B.outline(sw, if i == pinColor then 4 else 2, if i == pinColor then C.white else C.black)
			sw.Activated:Connect(function()
				pinColor = i
				B.click()
				M.render()
			end)
			x += 46
		end
		B.button(r, "+ NOTE", C.green, { Size = UDim2.fromOffset(110, 40), Position = UDim2.new(1, -120, 0, 12), ZIndex = 14 }, function()
			mode = "pin"
		end)
		for i, pin in plan().pins do
			local pr = row(64, C.dark)
			local badge = B.new("Frame", { BackgroundColor3 = NOTE_COLORS[pin.color] or C.yellow, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 12), ZIndex = 13 }, pr)
			B.outline(badge, 3)
			B.label(badge, tostring(i), { FontFace = B.TITLE, ZIndex = 14, MaxText = 24 })
			local box = B.new("TextBox", { Text = pin.text, PlaceholderText = "Écris ta note... (" .. (if pin.floor == "roof" then "toit" else "RDC") .. ")",
				FontFace = B.FONT, TextScaled = true, TextColor3 = C.black, BackgroundColor3 = C.white, BorderSizePixel = 0, ClearTextOnFocus = false,
				Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(56, 12), ZIndex = 14, TextXAlignment = Enum.TextXAlignment.Left }, pr)
			B.outline(box, 2)
			B.new("UITextSizeConstraint", { MaxTextSize = 18 }, box)
			box.FocusLost:Connect(function()
				if box.Text ~= pin.text then
					edit("pinText", pin.id, box.Text)
				end
			end)
			B.button(pr, "X", C.red, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -52, 0, 12), ZIndex = 14 }, function()
				edit("removePin", pin.id)
			end)
		end
	end

	function M.render()
		if not panel.Visible then
			return
		end
		local y = content.CanvasPosition.Y
		clear()
		if tab == "method" then
			renderMethod()
		elseif tab == "vehicles" then
			renderVehicles()
		elseif tab == "equip" then
			renderEquip()
		else
			renderNotes()
		end
		content.CanvasPosition = Vector2.new(0, y)
		local mth = plan().method
		local mname = "à improviser"
		for _, m in Noobla.methods do
			if m.id == mth then
				mname = m.name
			end
		end
		summary.Text = "Temps limite 15:00  |  Méthode : " .. mname .. "  |  " .. #plan().vehicles .. " véhicule(s)"
		M.renderMarkers()
	end

	for _, t in { { "method", "MÉTHODE" }, { "vehicles", "VÉHICULES" }, { "equip", "ÉQUIPEMENT" }, { "notes", "NOTES" } } do
		tabButtons[t[1]] = B.button(tabBar, t[2], C.dark, { Size = UDim2.new(0.25, -5, 1, 0), ZIndex = 12 }, function()
			M.tab(t[1])
		end)
	end
	function M.tab(t: string)
		tab = t
		for k, b in tabButtons do
			B.setButton(b, nil, if k == t then C.yellow else C.dark)
		end
		content.CanvasPosition = Vector2.zero
		M.render()
	end

	---------------------------------------------------------------- markers on the map
	local markerObjs: { { gui: GuiObject, pos: Vector3 } } = {}
	function M.renderMarkers()
		markers:ClearAllChildren()
		table.clear(markerObjs)
		for _, v in plan().vehicles do
			local it = Items.byId[v.kind]
			local f = B.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(64, 80), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 14 }, markers)
			B.icon(f, it, { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 0), ZIndex = 14 })
			B.label(f, "T+" .. B.clock(v.t), { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 52), ZIndex = 15, TextColor3 = C.yellow, MaxText = 16 })
			f.Activated:Connect(function()
				selected = v.id
				M.tab("vehicles")
			end)
			table.insert(markerObjs, { gui = f, pos = Vector3.new(v.x, FLOOR_Y.ground, v.z) })
		end
		for i, pin in plan().pins do
			local same = pin.floor == floor
			local f = B.new("Frame", { BackgroundColor3 = NOTE_COLORS[pin.color] or C.yellow, BorderSizePixel = 0, Size = UDim2.fromOffset(34, 34),
				AnchorPoint = Vector2.new(0.5, 1), ZIndex = 14, BackgroundTransparency = if same then 0 else 0.6 }, markers)
			B.outline(f, 3)
			B.label(f, tostring(i), { FontFace = B.TITLE, ZIndex = 15, MaxText = 22 })
			if pin.text ~= "" and same then
				local tl = B.label(f, pin.text, { Size = UDim2.fromOffset(200, 26), Position = UDim2.fromOffset(38, 4), ZIndex = 15, MaxText = 16, TextXAlignment = Enum.TextXAlignment.Left })
				tl.TextColor3 = C.white
			end
			table.insert(markerObjs, { gui = f, pos = Vector3.new(pin.x, FLOOR_Y[pin.floor] or 0.5, pin.z) })
		end
		-- key spots: start + escape
		local bk = workspace:FindFirstChild("NooblaBank")
		local start = bk and bk:FindFirstChild("HeistStart", true) :: BasePart?
		if start then
			local f = B.label(markers, "DÉPART", { Size = UDim2.fromOffset(90, 26), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 14, TextColor3 = C.lime, MaxText = 18 })
			table.insert(markerObjs, { gui = f, pos = start.Position })
		end
	end
	RunService.RenderStepped:Connect(function()
		if not panel.Visible then
			return
		end
		for _, m in markerObjs do
			local u, v = project(m.pos)
			m.gui.Position = UDim2.fromOffset(u, v)
		end
		hint.Text = if mode == "pin" then "Clique sur la carte pour poser la note (" .. (if floor == "roof" then "TOIT" else "RDC") .. ")"
			elseif mode and string.sub(mode, 1, 8) == "vehicle:" then "Clique dehors, là où le véhicule doit arriver"
			elseif mode and string.sub(mode, 1, 5) == "move:" then "Clique le nouvel emplacement du véhicule"
			else "Molette = zoom  |  glisser = déplacer la vue"
	end)

	---------------------------------------------------------------- map input
	local dragging = false
	local dragStart = Vector2.zero
	local panStart = Vector3.zero
	local moved = false
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			panStart = pan
		end
	end)
	overlay.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoomFov = math.clamp(zoomFov - input.Position.Z * 2, 6, 30)
			updateCamera()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(input.Position.X, input.Position.Y) - dragStart
			if d.Magnitude > 6 then
				moved = true
			end
			if moved then
				local size = mapFrame.AbsoluteSize
				local scale = 2 * H * math.tan(math.rad(zoomFov / 2)) / math.max(1, size.Y)
				pan = panStart + Vector3.new(d.X * scale, 0, d.Y * scale)
				updateCamera()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			if moved or not mode then
				return
			end
			local abs = mapFrame.AbsolutePosition
			local u, v = input.Position.X - abs.X, input.Position.Y - abs.Y
			local m = mode :: string
			if m == "pin" then
				local p = unproject(u, v, FLOOR_Y[floor])
				if edit("addPin", floor, p.X, p.Z, pinColor) then
					mode = nil
					M.tab("notes")
				end
			elseif string.sub(m, 1, 8) == "vehicle:" then
				local p = unproject(u, v, FLOOR_Y.ground)
				if edit("addVehicle", string.sub(m, 9), p.X, p.Z, 0) then
					mode = nil
				end
			elseif string.sub(m, 1, 5) == "move:" then
				local p = unproject(u, v, FLOOR_Y.ground)
				if edit("moveVehicle", tonumber(string.sub(m, 6)), p.X, p.Z) then
					mode = nil
				end
			end
		end
	end)

	shared.on("plan", function()
		M.render()
	end)
	shared.on("profile", function()
		M.render()
	end)

	function M.open()
		if panel.Visible then
			return
		end
		buildCopy()
		pan = Vector3.zero
		updateCamera()
		setFloor(floor)
		B.popIn(panel)
		M.tab(tab)
	end
	function M.close()
		mode = nil
		if panel.Visible then
			B.popOut(panel)
		end
	end
	function M.toggle()
		if panel.Visible then
			M.close()
		else
			M.open()
		end
	end
	function M.floor(f: string)
		setFloor(f)
	end
	return M
end
