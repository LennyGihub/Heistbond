--!strict
-- Heist client entry: one ScreenGui "HeistUI" with the hideout bar, the heist HUD, the scouting HUD,
-- intel popups, results, the hack mini-game, camera shake, and the G key to throw a carried bag.
-- Screens (Inventory, Planner) are separate modules next to this script.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local B = require(Heist:WaitForChild("Blocky"))
local Net = require(Heist:WaitForChild("Net"))
local Noobla = require(Heist:WaitForChild("Noobla"))
local Items = require(Heist:WaitForChild("Items"))
local Request = Net.request()
local Event = Net.event()
local S = Net.state()

local player = Players.LocalPlayer
local C = B.C

local gui = B.new("ScreenGui", { Name = "HeistUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

local shared = {
	gui = gui,
	profile = nil :: any,
	plan = nil :: any,
	request = function(...: any): (boolean, any)
		local ok, a, b = pcall(Request.InvokeServer, Request, ...)
		if not ok then
			return false, "Erreur réseau"
		end
		return a, b
	end,
	listeners = {} :: { [string]: { (any) -> () } },
}
function shared.on(name: string, fn: (any) -> ())
	shared.listeners[name] = shared.listeners[name] or {}
	table.insert(shared.listeners[name], fn)
end
local function emit(name: string, v: any)
	for _, fn in shared.listeners[name] or {} do
		task.spawn(fn, v)
	end
end

local Inventory = require(script.Parent:WaitForChild("InventoryUI"))(shared)
local Planner = require(script.Parent:WaitForChild("PlannerUI"))(shared)

local function toast(text: string, kind: string?)
	local col = if kind == "bad" then C.red elseif kind == "good" then C.green elseif kind == "warn" then C.orange else C.blue
	B.toast(text, col)
end

------------------------------------------------------------------ hideout bar (left)

local bar = B.new("Frame", { Name = "HideoutBar", BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 330),
	Position = UDim2.new(0, 14, 0.5, -150) }, gui)
local cashPanel = B.panel(bar, { Size = UDim2.fromOffset(220, 64), Position = UDim2.fromOffset(0, 0) }, nil, C.dark)
local cashLabel = B.label(cashPanel, "$0", { FontFace = B.TITLE, Size = UDim2.new(1, -20, 1, -14), Position = UDim2.fromOffset(10, 7),
	TextColor3 = C.lime, MaxText = 34 })
local function barButton(y: number, text: string, col: Color3, fn: () -> ())
	return B.button(bar, text, col, { Size = UDim2.fromOffset(220, 52), Position = UDim2.fromOffset(0, y) }, fn)
end
barButton(80, "INVENTAIRE", C.blue, function()
	Planner.close()
	Inventory.toggle()
end)
barButton(142, "PLAN DU BRAQUAGE", C.red, function()
	Inventory.close()
	Planner.toggle()
end)
local scoutBtn = barButton(204, "REPÉRAGE", C.orange, function()
	local ok, msg = shared.request("StartScout")
	if not ok and msg then
		toast(msg, "warn")
	end
end)
local _ = scoutBtn

------------------------------------------------------------------ heist HUD

local hud = B.new("Frame", { Name = "HeistHud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)
local timerPanel = B.panel(hud, { Size = UDim2.fromOffset(250, 70), Position = UDim2.new(0.5, -125, 0, 10), AnchorPoint = Vector2.zero }, nil, C.black)
local timerLabel = B.label(timerPanel, "15:00", { FontFace = B.TITLE, Size = UDim2.new(1, -20, 1, -16), Position = UDim2.fromOffset(10, 8), TextColor3 = C.yellow, MaxText = 48 })
local pills = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(760, 34), Position = UDim2.new(0.5, -380, 0, 88) }, hud)
B.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) }, pills)
local function pill(text: string, col: Color3): Frame
	local f = B.new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.fromOffset(180, 32) }, pills)
	B.outline(f, 3)
	B.label(f, text, { Name = "T", Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4), MaxText = 16 })
	return f
end
local pillBank = pill("BANQUE : CALME", C.green)
local pillPolice = pill("POLICE : -", C.dark)
local pillVault = pill("COFFRE : FERMÉ", C.dark)
local pillEmp = pill("IEM", C.blue)
pillEmp.Visible = false

local objPanel, objBody = B.panel(hud, { Size = UDim2.fromOffset(330, 230), Position = UDim2.new(0, 14, 0.5, -60) }, "OBJECTIFS", C.dark)
local _ = objPanel
local objLines: { TextLabel } = {}
for i = 1, 5 do
	objLines[i] = B.label(objBody, "", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, (i - 1) * 32),
		TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17 })
end
local carryPanel = B.panel(hud, { Size = UDim2.fromOffset(330, 64), Position = UDim2.new(0, 14, 0.5, 180) }, nil, C.green)
local carryLabel = B.label(carryPanel, "", { Size = UDim2.new(1, -20, 1, -14), Position = UDim2.fromOffset(10, 7), MaxText = 18 })
carryPanel.Visible = false
local abandon = B.button(hud, "ABANDONNER", C.red, { Size = UDim2.fromOffset(170, 44), Position = UDim2.new(1, -190, 0, 14) }, function()
	local ok, msg = shared.request("Abandon")
	if not ok and msg then
		toast(msg, "warn")
	end
end)
local _ = abandon
local throwBtn = B.button(hud, "LANCER LE SAC [G]", C.orange, { Size = UDim2.fromOffset(220, 44), Position = UDim2.new(0.5, -110, 1, -120), Visible = false }, function()
	local cam = workspace.CurrentCamera
	shared.request("Throw", cam.CFrame.LookVector)
end)

------------------------------------------------------------------ scouting HUD

local scoutPanel, scoutBody = B.panel(gui, { Size = UDim2.fromOffset(330, 200), Position = UDim2.new(0, 14, 0.5, -100), Visible = false }, "REPERAGE", C.orange)
local scoutCount = B.label(scoutBody, "Indices : 0/6", { Size = UDim2.new(1, 0, 0, 34), FontFace = B.TITLE, MaxText = 26 })
B.label(scoutBody, "Écoute, observe, fouille. Reste hors des zones du personnel.", { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 38),
	FontFace = B.FONT_REG, MaxText = 15, TextWrapped = true })
B.button(scoutBody, "RENTRER À LA PLANQUE", C.blue, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -46) }, function()
	shared.request("LeaveScout")
end)

------------------------------------------------------------------ intel popup (goofy notebook page)

local function intelPopup(key: string)
	local info = Noobla.intel[key]
	if not info then
		return
	end
	local p, body = B.panel(gui, { Size = UDim2.fromOffset(520, 290), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), ZIndex = 40 }, "INDICE TROUVE !", C.sand)
	B.label(body, info.title, { Size = UDim2.new(1, 0, 0, 36), TextColor3 = C.black, MaxText = 26, ZIndex = 41 }):FindFirstChildOfClass("UIStroke"):Destroy()
	local t = B.label(body, info.text, { Size = UDim2.new(1, 0, 1, -90), Position = UDim2.fromOffset(0, 40), FontFace = B.FONT_REG, TextWrapped = true,
		TextColor3 = C.black, MaxText = 18, ZIndex = 41, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	t:FindFirstChildOfClass("UIStroke"):Destroy()
	if info.method then
		local stamp = B.label(body, "MÉTHODE DÉBLOQUÉE !", { Size = UDim2.new(0.7, 0, 0, 40), Position = UDim2.new(0.15, 0, 1, -44), TextColor3 = C.red, MaxText = 26, ZIndex = 42, Rotation = -6 })
		local sc = B.new("UIScale", { Scale = 3 }, stamp)
		task.delay(0.5, function()
			B.tw(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			B.click()
		end)
	end
	B.popIn(p)
	task.delay(7, function()
		B.popOut(p, function()
			p:Destroy()
		end)
	end)
end

------------------------------------------------------------------ results

local function showResults(r: any)
	local p, body = B.panel(gui, { Size = UDim2.fromOffset(560, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 45 },
		if r.reason == "escaped" then "BRAQUAGE REUSSI !" elseif r.reason == "busted" then "TOUS A TERRE..." elseif r.reason == "time" then "TEMPS ECOULE" else "RETRAITE", C.dark)
	local lines = {
		{ "Butin ramené", B.money(r.banked) },
		{ "Casier 167", if r.objective then "SÉCURISÉ  +" .. B.money(r.bonus) elseif r.objectiveState == "destroyed" then "DÉTRUIT" else "RATÉ" },
		{ "Casiers ouverts", tostring(r.lockers or 0) },
		{ "Alarme", if r.alarm ~= "" then string.upper(r.alarm) else "JAMAIS !" },
		{ "Équipe", tostring(r.crew) .. " braqueur(s)" },
	}
	for i, l in lines do
		B.label(body, l[1], { Size = UDim2.new(0.5, 0, 0, 34), Position = UDim2.fromOffset(0, (i - 1) * 40), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20, ZIndex = 46 })
		B.label(body, l[2], { Size = UDim2.new(0.5, 0, 0, 34), Position = UDim2.new(0.5, 0, 0, (i - 1) * 40), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 20, ZIndex = 46,
			TextColor3 = C.yellow })
	end
	if #r.lostVehicles > 0 then
		local names = {}
		for _, k in r.lostVehicles do
			table.insert(names, Items.byId[k].name)
		end
		B.label(body, "Saisi par la police : " .. table.concat(names, ", "), { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 206), TextColor3 = C.red, MaxText = 16, ZIndex = 46 })
	end
	local share = B.label(body, "$0", { FontFace = B.TITLE, Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 1, -76), TextColor3 = C.lime, MaxText = 60, ZIndex = 46 })
	B.popIn(p)
	-- count up
	task.spawn(function()
		local target = r.share
		for i = 1, 40 do
			share.Text = "+" .. B.money(target * i / 40)
			if i % 4 == 0 then
				B.click()
			end
			task.wait(0.03)
		end
		share.Text = "+" .. B.money(target)
		local sc = B.new("UIScale", {}, share)
		sc.Scale = 1.5
		B.tw(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Elastic)
	end)
	task.delay(8.5, function()
		B.popOut(p, function()
			p:Destroy()
		end)
	end)
end

------------------------------------------------------------------ hack mini-game (SecuLock v1)

local KEYS = { { Enum.KeyCode.W, "W" }, { Enum.KeyCode.A, "A" }, { Enum.KeyCode.S, "S" }, { Enum.KeyCode.D, "D" } }
local hacking = false
local function hackGame(token: number, steps: number)
	if hacking then
		return
	end
	hacking = true
	local p, body = B.panel(gui, { Size = UDim2.fromOffset(560, 330), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 50 }, "SECULOCK V1", C.black)
	local info = B.label(body, "Tape la séquence ! (W A S D ou clique)", { Size = UDim2.new(1, 0, 0, 30), MaxText = 18, ZIndex = 51, TextColor3 = C.lime })
	local row = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 44), ZIndex = 51 }, body)
	B.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12) }, row)
	local seq = {}
	local tiles: { Frame } = {}
	for i = 1, steps do
		seq[i] = math.random(1, 4)
		local t = B.new("Frame", { BackgroundColor3 = C.darker, BorderSizePixel = 0, Size = UDim2.fromOffset(78, 78), ZIndex = 52 }, row)
		B.outline(t, 3, C.lime)
		B.label(t, KEYS[seq[i]][2], { FontFace = B.TITLE, ZIndex = 53, TextColor3 = C.lime, MaxText = 44 })
		tiles[i] = t
	end
	local barBg = B.new("Frame", { BackgroundColor3 = C.darker, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 140), ZIndex = 51 }, body)
	B.outline(barBg, 2)
	local barFill = B.new("Frame", { BackgroundColor3 = C.lime, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 52 }, barBg)
	local pad = B.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 172), ZIndex = 51 }, body)
	B.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12) }, pad)
	local pos = 1
	local mistakes = 0
	local done = false
	local function finish(ok: boolean)
		if done then
			return
		end
		done = true
		info.Text = if ok then "ACCÈS AUTORISÉ !" else "ÉCHEC : LA CLÉ GRILLE !"
		info.TextColor3 = if ok then C.lime else C.red
		shared.request("HackResult", token, ok)
		task.delay(1.1, function()
			B.popOut(p, function()
				p:Destroy()
				hacking = false
			end)
		end)
	end
	local function press(k: number)
		if done then
			return
		end
		B.click()
		if k == seq[pos] then
			tiles[pos].BackgroundColor3 = C.green
			local sc = B.new("UIScale", { Scale = 1.3 }, tiles[pos])
			B.tw(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			pos += 1
			if pos > steps then
				finish(true)
			end
		else
			mistakes += 1
			-- goofy shake and restart
			for _, t in tiles do
				t.BackgroundColor3 = C.red
			end
			p.Rotation = 4
			B.tw(p, 0.4, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			task.delay(0.25, function()
				for _, t in tiles do
					t.BackgroundColor3 = C.darker
				end
			end)
			pos = 1
			info.Text = "ERREUR " .. mistakes .. "/3 - recommence !"
			if mistakes >= 3 then
				finish(false)
			end
		end
	end
	for i, k in KEYS do
		B.button(pad, k[2], C.dark, { Size = UDim2.fromOffset(70, 56), ZIndex = 52 }, function()
			press(i)
		end)
	end
	local conn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		for i, k in KEYS do
			if input.KeyCode == k[1] then
				press(i)
			end
		end
	end)
	B.popIn(p)
	-- the vault opened some other way meanwhile: close quietly
	local vc = S:GetAttributeChangedSignal("VaultOpen"):Connect(function()
		if S:GetAttribute("VaultOpen") and not done then
			done = true
			B.popOut(p, function()
				p:Destroy()
				hacking = false
			end)
		end
	end)
	p.Destroying:Connect(function()
		vc:Disconnect()
	end)
	task.spawn(function()
		local total = 12
		local t0 = os.clock()
		while not done do
			local left = total - (os.clock() - t0)
			barFill.Size = UDim2.fromScale(math.max(0, left / total), 1)
			if left <= 0 then
				finish(false)
			end
			task.wait(0.05)
		end
		conn:Disconnect()
	end)
end

------------------------------------------------------------------ plan notes in the world (heist)

local noteFolder = B.new("Folder", { Name = "PlanNotes" }, gui)
local NOTE_COLORS = { C.yellow, C.red, C.blue, C.green, C.orange, C.purple }
local function showNotes(plan: any)
	noteFolder:ClearAllChildren()
	if not plan then
		return
	end
	for i, pin in plan.pins do
		local y = if pin.floor == "roof" then 22 else 6
		local a = B.new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1,
			Size = Vector3.new(0.2, 0.2, 0.2), Position = Vector3.new(pin.x, y, pin.z) }, workspace:FindFirstChild("HeistFx") or workspace)
		a.Name = "PlanNoteAnchor"
		local bb = B.new("BillboardGui", { Adornee = a, Size = UDim2.fromOffset(200, 64), AlwaysOnTop = true, MaxDistance = 260, LightInfluence = 0 }, noteFolder)
		local col = NOTE_COLORS[pin.color] or C.yellow
		local f = B.new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, bb)
		B.outline(f, 3)
		B.label(f, i .. ". " .. (if pin.text ~= "" then pin.text else "(note)"), { Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4), MaxText = 16, TextWrapped = true })
		bb.Destroying:Connect(function()
			a:Destroy()
		end)
	end
end

------------------------------------------------------------------ camera shake

local shake = 0
RunService:BindToRenderStep("HeistShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if shake > 0 then
		local cam = workspace.CurrentCamera
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(math.random(-10, 10) / 10 * shake), math.rad(math.random(-10, 10) / 10 * shake), 0)
		shake = math.max(0, shake - dt * 2.5)
	end
end)

------------------------------------------------------------------ updates

local function money(): string
	return B.money(if shared.profile then shared.profile.cash else 0)
end

local function refresh()
	local phase = S:GetAttribute("Phase")
	local inHeist = phase == "Heist" and player:GetAttribute("InHeist") == true
	bar.Visible = phase ~= "Heist" and player:GetAttribute("Scouting") ~= true
	hud.Visible = inHeist
	scoutPanel.Visible = player:GetAttribute("Scouting") == true
	cashLabel.Text = money()
	if inHeist then
		Inventory.close()
		Planner.close()
	end
end

local function intelCount(): number
	local n = 0
	if shared.profile then
		for _, k in Noobla.clueOrder do
			if shared.profile.intel[k] then
				n += 1
			end
		end
	end
	return n
end

-- a gun destroyed while equipped (heist loadout swap) can't clean its own HUD: remove orphans
local pgui = player:WaitForChild("PlayerGui")
task.spawn(function()
	while true do
		task.wait(0.5)
		local char = player.Character
		local holding = char and char:FindFirstChildOfClass("Tool")
		if not holding then
			for _, g in pgui:GetChildren() do
				if g.Name == "GunHUD" or g.Name == "ScopeOverlay" then
					g:Destroy()
				end
			end
		end
	end
end)

local lastSecond = -1
RunService.Heartbeat:Connect(function()
	if not hud.Visible then
		if scoutPanel.Visible then
			scoutCount.Text = "INDICES : " .. intelCount() .. "/6"
		end
		return
	end
	local t = workspace:GetServerTimeNow()
	local left = ((S:GetAttribute("EndTime") :: number?) or t) - t
	timerLabel.Text = B.clock(left)
	timerLabel.TextColor3 = if left < 60 then C.red else C.yellow
	local sec = math.floor(left)
	if sec ~= lastSecond and left < 30 and left > 0 then
		lastSecond = sec
		local sc = timerPanel:FindFirstChild("PopScale") :: UIScale
		sc.Scale = 1.15
		B.tw(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	-- pills
	local bankOn = S:GetAttribute("BankAlert") == true
	local function set(p: Frame, text: string, col: Color3)
		(p:FindFirstChild("T") :: TextLabel).Text = text
		p.BackgroundColor3 = col
	end
	set(pillBank, if bankOn then "BANQUE : ALARME !" else "BANQUE : CALME", if bankOn then C.red else C.green)
	local callAt = (S:GetAttribute("PoliceCallAt") :: number?) or 0
	local arrive = (S:GetAttribute("PoliceArriveAt") :: number?) or 0
	if S:GetAttribute("PoliceAlert") then
		if t < arrive then
			set(pillPolice, "POLICE : " .. B.clock(arrive - t), C.orange)
		else
			set(pillPolice, "POLICE SUR PLACE", C.red)
		end
	elseif callAt > 0 then
		set(pillPolice, "APPEL : " .. B.clock(callAt - t), C.orange)
	else
		set(pillPolice, "POLICE : -", C.dark)
	end
	set(pillVault, if S:GetAttribute("VaultOpen") then "COFFRE : OUVERT" else "COFFRE : FERMÉ", if S:GetAttribute("VaultOpen") then C.green else C.dark)
	local emp = ((S:GetAttribute("EmpUntil") :: number?) or 0) - t
	pillEmp.Visible = emp > 0
	if emp > 0 then
		set(pillEmp, "IEM : " .. B.clock(emp), C.blue)
	end
	-- objectives
	local os_ = S:GetAttribute("ObjectiveState")
	local function check(done: boolean, text: string): string
		return (if done then "[X] " else "[ ] ") .. text
	end
	objLines[1].Text = check(S:GetAttribute("VaultOpen") == true, "Ouvrir le coffre")
	objLines[2].Text = if os_ == "destroyed" then "[!] Casier 167 DÉTRUIT" else check(os_ ~= "locked" and os_ ~= "inVault", "Prendre la mallette (casier 167)")
	objLines[2].TextColor3 = if os_ == "destroyed" then C.red else C.white
	objLines[3].Text = check(os_ == "secured", "La ramener à la planque")
	objLines[4].Text = "Butin sécurisé : " .. B.money((S:GetAttribute("Banked") :: number?) or 0)
	objLines[4].TextColor3 = C.lime
	local method = S:GetAttribute("Method")
	objLines[5].Text = "Plan : " .. (if method and method ~= "" then string.upper(method) else "improvisation !")
	-- carrying
	local char = player.Character
	local carry = char and char:GetAttribute("Carry")
	carryPanel.Visible = carry ~= nil
	throwBtn.Visible = carry ~= nil
	if carry == "case" then
		carryLabel.Text = "MALLETTE DU 167 - [G] lancer"
		carryPanel.BackgroundColor3 = C.orange
	elseif carry then
		local cnt = (char :: Model):GetAttribute("CarryCount") or 0
		carryLabel.Text = "SAC " .. B.money((char :: Model):GetAttribute("CarryValue") or 0) .. " (" .. cnt .. "/" .. Noobla.bagCapacity .. ") [G]"
		carryPanel.BackgroundColor3 = C.green
	end
end)

for _, a in { "Phase", "BankAlert" } do
	S:GetAttributeChangedSignal(a):Connect(refresh)
end
player:GetAttributeChangedSignal("InHeist"):Connect(refresh)
player:GetAttributeChangedSignal("Scouting"):Connect(refresh)
S:GetAttributeChangedSignal("BankAlert"):Connect(function()
	if S:GetAttribute("BankAlert") and hud.Visible then
		shake = 0.6
	end
end)

Event.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
	if kind == "Profile" then
		shared.profile = a
		emit("profile", a)
		refresh()
	elseif kind == "Plan" then
		shared.plan = a
		emit("plan", a)
	elseif kind == "Toast" then
		toast(a, b)
	elseif kind == "Intel" then
		intelPopup(a)
	elseif kind == "HackStart" then
		hackGame(a, b)
	elseif kind == "Results" then
		showResults(a)
	elseif kind == "HeistStarted" then
		shared.plan = a
		showNotes(a)
	elseif kind == "Fx" and a == "shake" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - b).Magnitude < 160 then
			shake = math.max(shake, c or 1)
		end
	end
end)
S:GetAttributeChangedSignal("Phase"):Connect(function()
	if S:GetAttribute("Phase") ~= "Heist" and S:GetAttribute("Phase") ~= "Results" then
		noteFolder:ClearAllChildren()
	end
end)

-- hideout props open the screens
ProximityPromptService.PromptTriggered:Connect(function(pp: ProximityPrompt)
	if pp.Name == "PlanPrompt" then
		Inventory.close()
		Planner.open()
	elseif pp.Name == "InvPrompt" then
		Planner.close()
		Inventory.open()
	elseif pp.Name == "ScoutPrompt" then
		local ok, msg = shared.request("StartScout")
		if not ok and msg then
			toast(msg, "warn")
		end
	end
end)

-- G throws the carried bag where the camera looks
ContextActionService:BindAction("HeistThrow", function(_, state)
	if state == Enum.UserInputState.Begin then
		local char = player.Character
		if char and char:GetAttribute("Carry") then
			shared.request("Throw", workspace.CurrentCamera.CFrame.LookVector)
		end
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.G)

-- Studio-only test hooks: open screens from a test script
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("TestOpen"):Connect(function()
		local v = player:GetAttribute("TestOpen")
		if v == "planner" then
			Planner.open()
		elseif v == "inventory" then
			Inventory.open()
		elseif v == "close" then
			Planner.close()
			Inventory.close()
		elseif type(v) == "string" and string.sub(v, 1, 4) == "tab:" then
			Planner.tab(string.sub(v, 5))
		elseif v == "roof" or v == "ground" then
			Planner.floor(v)
		end
	end)
end

-- first data
task.spawn(function()
	local ok, p = shared.request("Profile")
	if ok and p then
		shared.profile = p
		emit("profile", p)
	end
	local ok2, plan = shared.request("Plan")
	if ok2 and plan then
		shared.plan = plan
		emit("plan", plan)
	end
	refresh()
end)
refresh()
local _ = CollectionService
