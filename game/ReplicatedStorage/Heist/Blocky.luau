--!strict
-- Blocky: the heist UI kit. Old-school Roblox look: brick colours, square corners, thick black
-- outlines, a light bevel on top and a dark one below, studs on title bars, chunky Arial-like text.
-- Motion is smooth and a bit goofy: panels pop in with an overshoot and a wobble, buttons squish
-- when pressed and bounce when hovered, toasts drop in and jiggle.
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local B = {}

local RGB = Color3.fromRGB
B.C = {
	red = RGB(196, 40, 28),
	blue = RGB(13, 105, 172),
	yellow = RGB(245, 205, 48),
	green = RGB(75, 151, 75),
	lime = RGB(164, 189, 71),
	orange = RGB(218, 133, 65),
	grey = RGB(163, 162, 165),
	dark = RGB(99, 95, 98),
	darker = RGB(54, 54, 58),
	black = RGB(27, 42, 53),
	white = RGB(242, 243, 243),
	sand = RGB(215, 197, 154),
	teal = RGB(18, 238, 212),
	purple = RGB(107, 50, 124),
}

B.FONT = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Bold)
B.FONT_REG = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Regular)
B.TITLE = Font.fromEnum(Enum.Font.Arcade) -- big titles (no accents in this font: use plain caps)

local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
local function darken(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
B.lighten = lighten
B.darken = darken

function B.new(class: string, props: { [string]: any }?, parent: Instance?): any
	local o = Instance.new(class)
	if props then
		for k, v in props do
			(o :: any)[k] = v
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function outline(g: GuiObject, t: number?, c: Color3?)
	B.new("UIStroke", {
		Thickness = t or 3,
		Color = c or B.C.black,
		LineJoinMode = Enum.LineJoinMode.Miter,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, g)
end
B.outline = outline

local function bevel(g: GuiObject, col: Color3)
	B.new("Frame", { Name = "BevelTop", BorderSizePixel = 0, BackgroundColor3 = lighten(col, 0.35),
		Size = UDim2.new(1, 0, 0, 4), ZIndex = g.ZIndex }, g)
	B.new("Frame", { Name = "BevelBottom", BorderSizePixel = 0, BackgroundColor3 = darken(col, 0.3),
		Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), ZIndex = g.ZIndex }, g)
end

-- text label with the black outline that old Roblox GUIs had
function B.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = B.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		FontFace = B.FONT,
		TextColor3 = B.C.white,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, parent)
	B.new("UIStroke", { Thickness = 1.5, Color = B.C.black, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	B.new("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 8 }, l)
	if props then
		for k, v in props do
			if k == "MaxText" then
				(l:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint).MaxTextSize = v
			else
				(l :: any)[k] = v
			end
		end
	end
	return l
end

-- row of round studs along the top of a title bar
function B.studs(parent: GuiObject, col: Color3, count: number?)
	local holder = B.new("Frame", { Name = "Studs", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 10),
		Position = UDim2.new(0, 4, 0, -6), ZIndex = parent.ZIndex + 1 }, parent)
	local n = count or 12
	for i = 0, n - 1 do
		local s = B.new("Frame", { BorderSizePixel = 0, BackgroundColor3 = lighten(col, 0.15),
			Size = UDim2.fromOffset(16, 10), Position = UDim2.new((i + 0.5) / n, -8, 0, 0), ZIndex = parent.ZIndex + 1 }, holder)
		B.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, s)
		outline(s, 2, darken(col, 0.45))
	end
	return holder
end

-- a brick panel with an optional title bar. Returns (panel, body)
function B.panel(parent: Instance, props: { [string]: any }, title: string?, col: Color3?): (Frame, Frame)
	local c = col or B.C.dark
	local p = B.new("Frame", { BackgroundColor3 = c, BorderSizePixel = 0 }, parent)
	for k, v in props do
		(p :: any)[k] = v
	end
	outline(p, 4)
	bevel(p, c)
	B.new("UIScale", { Name = "PopScale" }, p)
	local body = B.new("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -20),
		Position = UDim2.fromOffset(10, 10), ZIndex = p.ZIndex + 1 }, p)
	if title then
		local barCol = B.C.red
		local bar = B.new("Frame", { Name = "TitleBar", BackgroundColor3 = barCol, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, -2), ZIndex = p.ZIndex + 1 }, p)
		outline(bar, 4)
		bevel(bar, barCol)
		B.studs(bar, barCol, 10)
		B.label(bar, title, { Name = "Title", FontFace = B.TITLE, Size = UDim2.new(1, -110, 1, -12), Position = UDim2.fromOffset(14, 6),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = p.ZIndex + 2, MaxText = 32 })
		body.Size = UDim2.new(1, -20, 1, -66)
		body.Position = UDim2.fromOffset(10, 54)
	end
	return p, body
end

local clickSound: Sound? = nil
local popSound: Sound? = nil
local function snd(id: string, vol: number, pitch: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol
	s.PlaybackSpeed = pitch
	s.Parent = SoundService
	return s
end
function B.click()
	if not clickSound then
		clickSound = snd("rbxasset://sounds/electronicpingshort.wav", 0.35, 1.6)
	end
	(clickSound :: Sound).PlaybackSpeed = 1.5 + math.random() * 0.25;
	(clickSound :: Sound):Play()
end
function B.pop()
	if not popSound then
		popSound = snd("rbxasset://sounds/swoosh.wav", 0.4, 1.3)
	end
	(popSound :: Sound):Play()
end

local function tw(o: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end
B.tw = tw

-- chunky brick button. Squishes on press, bounces on hover. Returns the TextButton.
function B.button(parent: Instance, text: string, col: Color3?, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local c = col or B.C.blue
	local b = B.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = c, BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 44) }, parent)
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	outline(b, 3)
	bevel(b, c)
	local sc = B.new("UIScale", {}, b)
	B.label(b, text, { Name = "Label", Size = UDim2.new(1, -12, 1, -10), Position = UDim2.fromOffset(6, 5), ZIndex = b.ZIndex + 1, MaxText = 22 })
	b:SetAttribute("Color", c)
	b.MouseEnter:Connect(function()
		tw(sc, 0.25, { Scale = 1.07 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		tw(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Quad)
	end)
	b.MouseButton1Down:Connect(function()
		tw(sc, 0.08, { Scale = 0.88 })
	end)
	b.Activated:Connect(function()
		B.click()
		tw(sc, 0.45, { Scale = 1.04 }, Enum.EasingStyle.Elastic)
		-- goofy wiggle
		b.Rotation = math.random(-4, 4)
		tw(b, 0.35, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		if onClick then
			onClick()
		end
	end)
	return b
end

function B.setButton(b: TextButton, text: string?, col: Color3?)
	if text then
		(b:FindFirstChild("Label") :: TextLabel).Text = text
	end
	if col then
		b.BackgroundColor3 = col;
		(b:FindFirstChild("BevelTop") :: Frame).BackgroundColor3 = lighten(col, 0.35);
		(b:FindFirstChild("BevelBottom") :: Frame).BackgroundColor3 = darken(col, 0.3)
	end
end

-- pop a panel in (overshoot + wobble) / out (shrink, then hide)
function B.popIn(p: GuiObject)
	local sc = p:FindFirstChild("PopScale") :: UIScale?
	p.Visible = true
	B.pop()
	if sc then
		sc.Scale = 0.3
		tw(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	p.Rotation = -6
	tw(p, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
end

function B.popOut(p: GuiObject, done: (() -> ())?)
	local sc = p:FindFirstChild("PopScale") :: UIScale?
	if sc then
		local t = tw(sc, 0.18, { Scale = 0.2 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tw(p, 0.18, { Rotation = 8 })
		t.Completed:Once(function()
			p.Visible = false
			p.Rotation = 0
			if done then
				done()
			end
		end)
	else
		p.Visible = false
		if done then
			done()
		end
	end
end

-- drawn item badge (until image icons exist): brick tile with a 3-letter code
function B.icon(parent: Instance, item: { code: string, color: Color3, image: string? }, props: { [string]: any }?): Frame
	local f = B.new("Frame", { BackgroundColor3 = item.color, BorderSizePixel = 0, Size = UDim2.fromOffset(56, 56) }, parent)
	outline(f, 3)
	bevel(f, item.color)
	B.new("UIAspectRatioConstraint", {}, f)
	if item.image then
		B.new("ImageLabel", { BackgroundTransparency = 1, Image = item.image, Size = UDim2.fromScale(0.9, 0.9),
			Position = UDim2.fromScale(0.05, 0.05), ZIndex = f.ZIndex + 1 }, f)
	else
		local stud = B.new("Frame", { BorderSizePixel = 0, BackgroundColor3 = lighten(item.color, 0.2), Size = UDim2.fromScale(0.36, 0.2),
			Position = UDim2.fromScale(0.32, 0.1), ZIndex = f.ZIndex + 1 }, f)
		B.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stud)
		B.label(f, item.code, { FontFace = B.TITLE, Size = UDim2.fromScale(0.86, 0.42), Position = UDim2.fromScale(0.07, 0.42),
			ZIndex = f.ZIndex + 2, MaxText = 30 })
	end
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	return f
end

-- toasts: drop in at the top, jiggle, slide away
local toastGui: ScreenGui? = nil
local toastY = 0
function B.toast(text: string, col: Color3?, secs: number?)
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not toastGui or not toastGui.Parent then
		toastGui = B.new("ScreenGui", { Name = "HeistToasts", ResetOnSpawn = false, DisplayOrder = 50, IgnoreGuiInset = true }, pg)
	end
	local c = col or B.C.blue
	local f = B.new("Frame", { BackgroundColor3 = c, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(520, 54), Position = UDim2.new(0.5, 0, 0, -80) }, toastGui)
	outline(f, 3)
	bevel(f, c)
	B.label(f, text, { Size = UDim2.new(1, -24, 1, -14), Position = UDim2.fromOffset(12, 7), MaxText = 22 })
	local slot = toastY
	toastY += 1
	local y = 70 + (slot % 4) * 62
	tw(f, 0.45, { Position = UDim2.new(0.5, 0, 0, y) }, Enum.EasingStyle.Back)
	f.Rotation = math.random(-5, 5)
	tw(f, 0.7, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	task.delay(secs or 3.2, function()
		local t = tw(f, 0.3, { Position = UDim2.new(1.4, 0, 0, y) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		t.Completed:Once(function()
			f:Destroy()
		end)
	end)
end

function B.money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return "$" .. out:gsub("^ ", "")
end

function B.clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

return B
