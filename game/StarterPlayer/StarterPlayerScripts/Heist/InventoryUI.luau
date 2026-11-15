--!strict
-- Inventory screen: category tabs, a grid of item tiles (drawn badge, name, count), item details.
-- The black market will sell new tech here later (button shown as "bientôt").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Heist = ReplicatedStorage:WaitForChild("Heist")
local B = require(Heist:WaitForChild("Blocky"))
local Items = require(Heist:WaitForChild("Items"))
local C = B.C

return function(shared: any)
	local M = {}
	local panel, body = B.panel(shared.gui, { Name = "Inventory", Size = UDim2.fromOffset(900, 580), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52), Visible = false, ZIndex = 10 }, "INVENTAIRE", C.dark)
	B.button(panel, "X", C.red, { Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -54, 0, 0), ZIndex = 14 }, function()
		M.close()
	end)
	local cash = B.label(panel, "", { FontFace = B.TITLE, Size = UDim2.fromOffset(240, 34), Position = UDim2.new(1, -310, 0, 4), ZIndex = 14,
		TextColor3 = C.lime, TextXAlignment = Enum.TextXAlignment.Right, MaxText = 28 })
	local tabs = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 11 }, body)
	B.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	local grid = B.new("ScrollingFrame", { BackgroundColor3 = C.darker, BorderSizePixel = 0, Size = UDim2.new(0.62, 0, 1, -56), Position = UDim2.fromOffset(0, 56),
		ScrollBarThickness = 8, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 11 }, body)
	B.outline(grid, 3)
	B.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, grid)
	B.new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local detail = B.new("Frame", { BackgroundColor3 = C.grey, BorderSizePixel = 0, Size = UDim2.new(0.36, 0, 1, -56), Position = UDim2.new(0.64, 0, 0, 56), ZIndex = 11 }, body)
	B.outline(detail, 3)
	local market = B.button(body, "MARCHÉ NOIR (BIENTÔT)", C.purple, { Size = UDim2.new(0.36, 0, 0, 44), Position = UDim2.new(0.64, 0, 1, -44), ZIndex = 13 }, function()
		B.toast("Le marché noir ouvre bientôt...", C.purple)
	end)
	local _ = market
	local current = "vehicle"

	local function showDetail(it: any)
		detail:ClearAllChildren()
		B.outline(detail, 3)
		if not it then
			B.label(detail, "Choisis un objet", { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 20), ZIndex = 12 })
			return
		end
		local ic = B.icon(detail, it, { Size = UDim2.fromOffset(120, 120), Position = UDim2.new(0.5, -60, 0, 16), ZIndex = 12 })
		ic.Rotation = -8
		B.tw(ic, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		B.label(detail, it.name, { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 146), ZIndex = 12, MaxText = 24 })
		local n = (shared.profile and shared.profile.inv[it.id]) or 0
		B.label(detail, "En stock : " .. n, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 188), ZIndex = 12, TextColor3 = C.yellow, MaxText = 20 })
		local d = B.label(detail, it.desc, { Size = UDim2.new(1, -20, 0, 90), Position = UDim2.fromOffset(10, 224), ZIndex = 12, FontFace = B.FONT_REG,
			TextWrapped = true, MaxText = 18 })
		local _ = d
	end

	local function render()
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		cash.Text = B.money(shared.profile and shared.profile.cash or 0)
		local i = 0
		for _, it in Items.list do
			if it.kind == current then
				i += 1
				local n = (shared.profile and shared.profile.inv[it.id]) or 0
				local tile = B.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.dark, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 12 }, grid)
				B.outline(tile, 3)
				local sc = B.new("UIScale", { Scale = 0.2 }, tile)
				task.delay(i * 0.04, function()
					B.tw(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
				end)
				B.icon(tile, it, { Size = UDim2.fromOffset(72, 72), Position = UDim2.new(0.5, -36, 0, 10), ZIndex = 13 })
				B.label(tile, it.name, { Size = UDim2.new(1, -12, 0, 36), Position = UDim2.fromOffset(6, 86), ZIndex = 13, MaxText = 16, TextWrapped = true })
				local cnt = B.label(tile, "x" .. n, { FontFace = B.TITLE, Size = UDim2.fromOffset(60, 26), Position = UDim2.new(1, -66, 0, 4), ZIndex = 14,
					TextColor3 = if n > 0 then C.yellow else C.red, MaxText = 22, TextXAlignment = Enum.TextXAlignment.Right })
				local _ = cnt
				tile.MouseEnter:Connect(function()
					B.tw(sc, 0.2, { Scale = 1.06 }, Enum.EasingStyle.Back)
				end)
				tile.MouseLeave:Connect(function()
					B.tw(sc, 0.2, { Scale = 1 })
				end)
				tile.Activated:Connect(function()
					B.click()
					tile.Rotation = 5
					B.tw(tile, 0.5, { Rotation = 0 }, Enum.EasingStyle.Elastic)
					showDetail(it)
				end)
			end
		end
	end

	local tabButtons: { [string]: TextButton } = {}
	for _, kind in Items.KIND_ORDER do
		tabButtons[kind] = B.button(tabs, Items.KIND_NAME[kind], C.dark, { Size = UDim2.fromOffset(150, 42), ZIndex = 12 }, function()
			current = kind
			for k, b in tabButtons do
				B.setButton(b, nil, if k == kind then C.yellow else C.dark)
			end
			render()
			showDetail(nil)
		end)
	end
	B.setButton(tabButtons.vehicle, nil, C.yellow)

	shared.on("profile", function()
		if panel.Visible then
			render()
		end
	end)

	function M.open()
		if panel.Visible then
			return
		end
		render()
		showDetail(nil)
		B.popIn(panel)
	end
	function M.close()
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
	return M
end
