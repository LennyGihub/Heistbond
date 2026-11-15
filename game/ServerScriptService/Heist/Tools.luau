--!strict
-- Heist tools: blocky Tool models (C4, drill, hack key, EMP, rope, zip ties, access card), the light
-- pistol, weapon attachments (silencer / vertical grip / holo sight shown or removed on the M4A1, and
-- the tool attributes GunClient reads), the heavy vest, and giving a player their planned loadout.
-- A usable tool carries attribute Count; Tools.use() spends one (from the tool and from the profile).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")
local Items = require(ReplicatedStorage:WaitForChild("Heist"):WaitForChild("Items"))
local Data = require(script.Parent:WaitForChild("Data"))

local Tools = {}
local RGB = Color3.fromRGB

local templates: Folder

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Studs -- old-school studs on top
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function weldAll(tool: Tool, handle: BasePart)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and d ~= handle then
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
		end
	end
	handle.Anchored = false
end

-- a simple tool: handle + extra parts built by `extra(tool, handleCf)`
local function simple(name: string, itemId: string, size: Vector3, color: Color3, mat: Enum.Material?, extra: ((Tool, CFrame) -> ())?, grip: CFrame?): Tool
	local t = Instance.new("Tool")
	t.Name = name
	t.CanBeDropped = false
	t.RequiresHandle = true
	t.ToolTip = Items.byId[itemId].name
	t:SetAttribute("ItemId", itemId)
	local cf = CFrame.new(0, 100, 0)
	local h = part(t, "Handle", size, cf, color, mat)
	if extra then
		extra(t, cf)
	end
	weldAll(t, h)
	if grip then
		t.Grip = grip
	end
	t.Parent = templates
	return t
end

local function buildTemplates()
	templates = ServerStorage:FindFirstChild("HeistTools") :: Folder
	if templates then
		templates:Destroy()
	end
	templates = Instance.new("Folder")
	templates.Name = "HeistTools"
	templates.Parent = ServerStorage

	simple("C4", "c4", Vector3.new(1.4, 0.6, 0.9), RGB(214, 190, 120), Enum.Material.Plastic, function(t, cf)
		part(t, "Tape", Vector3.new(0.25, 0.65, 0.95), cf * CFrame.new(-0.35, 0, 0), RGB(40, 40, 44))
		part(t, "Tape", Vector3.new(0.25, 0.65, 0.95), cf * CFrame.new(0.35, 0, 0), RGB(40, 40, 44))
		part(t, "Timer", Vector3.new(0.5, 0.2, 0.4), cf * CFrame.new(0, 0.4, 0), RGB(30, 30, 30))
		part(t, "Led", Vector3.new(0.15, 0.1, 0.15), cf * CFrame.new(0.12, 0.55, 0), RGB(255, 40, 40), Enum.Material.Neon)
		part(t, "Wire", Vector3.new(0.08, 0.08, 1.1), cf * CFrame.new(-0.1, 0.35, 0.2) * CFrame.Angles(0.3, 0, 0), RGB(200, 40, 40))
	end)
	simple("Drill", "drill", Vector3.new(1.2, 1.2, 2.2), RGB(245, 205, 48), Enum.Material.SmoothPlastic, function(t, cf)
		part(t, "Motor", Vector3.new(1.0, 1.0, 1.0), cf * CFrame.new(0, 0.6, 0.6), RGB(40, 40, 44))
		local bit = part(t, "Bit", Vector3.new(1.4, 0.3, 0.3), cf * CFrame.new(0, 0, -1.7) * CFrame.Angles(0, math.pi / 2, 0), RGB(170, 174, 180), Enum.Material.Metal)
		bit.Shape = Enum.PartType.Cylinder
	end, CFrame.new(0, -0.2, 0.4))
	simple("HackKey", "hackkey", Vector3.new(0.3, 0.15, 0.8), RGB(30, 170, 80), Enum.Material.SmoothPlastic, function(t, cf)
		part(t, "Plug", Vector3.new(0.25, 0.1, 0.3), cf * CFrame.new(0, 0, -0.55), RGB(190, 190, 195), Enum.Material.Metal)
		part(t, "Chip", Vector3.new(0.15, 0.05, 0.15), cf * CFrame.new(0, 0.1, 0.1), RGB(120, 255, 140), Enum.Material.Neon)
	end)
	simple("EMP", "emp", Vector3.new(0.9, 0.7, 0.9), RGB(40, 120, 220), Enum.Material.SmoothPlastic, function(t, cf)
		part(t, "Antenna", Vector3.new(0.1, 1.2, 0.1), cf * CFrame.new(0.3, 0.9, 0.3), RGB(30, 30, 30))
		part(t, "Tip", Vector3.new(0.25, 0.25, 0.25), cf * CFrame.new(0.3, 1.5, 0.3), RGB(120, 220, 255), Enum.Material.Neon)
		part(t, "Button", Vector3.new(0.3, 0.12, 0.3), cf * CFrame.new(-0.2, 0.4, 0), RGB(220, 40, 40))
	end)
	simple("Rope", "rope", Vector3.new(0.6, 1.6, 1.6), RGB(160, 110, 60), Enum.Material.Fabric, function(t, cf)
		(t:FindFirstChild("Handle") :: Part).Shape = Enum.PartType.Cylinder
		part(t, "Hook", Vector3.new(0.2, 0.8, 0.5), cf * CFrame.new(0, 1, 0), RGB(170, 174, 180), Enum.Material.Metal)
	end)
	simple("ZipTies", "zipties", Vector3.new(0.3, 0.3, 1.2), RGB(30, 30, 30), Enum.Material.Plastic, function(t, cf)
		for i = -1, 1 do
			part(t, "Tie", Vector3.new(0.05, 0.6, 0.6), cf * CFrame.new(0.15, 0, i * 0.35), RGB(20, 20, 20))
		end
	end)
	simple("AccessCard", "card5", Vector3.new(0.08, 0.6, 0.9), RGB(230, 180, 40), Enum.Material.Metal, function(t, cf)
		part(t, "Stripe", Vector3.new(0.09, 0.15, 0.9), cf * CFrame.new(0, -0.15, 0), RGB(30, 30, 30))
	end)

	-- light pistol: the M4A1 tool's rig (handle attachments, scripts) with a blocky pistol body
	local src = StarterPack:FindFirstChild("M4A1")
	if src then
		local p = src:Clone() :: Tool
		p.Name = "Pistol"
		p.ToolTip = "Pistolet léger"
		local h = p:FindFirstChild("Handle") :: BasePart
		for _, n in { "Body", "HoloSight" } do
			local c = p:FindFirstChild(n)
			if c then
				c:Destroy()
			end
		end
		local mag = p:FindFirstChild("Magazine") :: BasePart?
		if mag then
			for _, c in mag:GetChildren() do
				if c:IsA("BasePart") then
					c:Destroy()
				end
			end
		end
		local body = Instance.new("Model")
		body.Name = "Body"
		body.Parent = p
		local cf = h.CFrame
		local function bp(name: string, size: Vector3, off: CFrame, col: Color3, mat: Enum.Material?)
			local q = part(body, name, size, cf * off, col, mat)
			q.TopSurface = Enum.SurfaceType.Smooth
			local w = Instance.new("WeldConstraint")
			w.Part0 = h
			w.Part1 = q
			w.Parent = q
			return q
		end
		bp("Slide", Vector3.new(0.22, 0.24, 0.95), CFrame.new(0, 0.1, -0.5), RGB(45, 45, 50), Enum.Material.Metal)
		bp("Frame", Vector3.new(0.2, 0.14, 0.8), CFrame.new(0, -0.06, -0.45), RGB(30, 30, 34))
		bp("Grip", Vector3.new(0.2, 0.55, 0.26), CFrame.new(0, -0.25, 0.05) * CFrame.Angles(math.rad(-15), 0, 0), RGB(30, 30, 34), Enum.Material.Fabric)
		bp("Guard", Vector3.new(0.06, 0.06, 0.3), CFrame.new(0, -0.2, -0.25), RGB(30, 30, 34))
		bp("FrontSight", Vector3.new(0.05, 0.06, 0.05), CFrame.new(0, 0.25, -0.92), RGB(255, 255, 255), Enum.Material.Neon)
		local muzzle = h:FindFirstChild("Muzzle") :: Attachment
		muzzle.Position = Vector3.new(0, 0.1, -1.0)
		local sight = h:FindFirstChild("Sight") :: Attachment
		sight.Position = Vector3.new(0, 0.26, -0.1)
		local left = h:FindFirstChild("LeftHandIK") :: Attachment
		left.Position = Vector3.new(0, -0.24, 0.05)
		local grab = h:FindFirstChild("MagGrab") :: Attachment
		grab.Position = Vector3.new(0, -0.5, 0.05)
		if mag then
			mag.Size = Vector3.new(0.14, 0.4, 0.2)
			mag.Transparency = 0
			mag.Color = RGB(30, 30, 34)
			-- the magazine sits in the grip (its base just shows under it)
			local mw = h:FindFirstChild("MagWeld") :: Weld?
			if mw then
				mw.C0 = CFrame.new(0, -0.36, 0.08) * CFrame.Angles(math.rad(-15), 0, 0)
			end
		end
		grab.Position = Vector3.new(0, -0.56, 0.1)
		-- the rear of the slide, where the left hand grips it to rack it (GunAnim)
		local rack = Instance.new("Attachment")
		rack.Name = "ChargingHandle"
		rack.Position = Vector3.new(0, 0.12, -0.12)
		rack.Parent = h
		p:SetAttribute("ReloadStyle", "pistol")
		p:SetAttribute("Ammo", 15)
		p:SetAttribute("Reserve", 60)
		p.Parent = templates
	end
end

-- weapon tool for a planned weapon, with its attachments
local function makeWeapon(w: { kind: string, silencer: boolean, grip: boolean, holo: boolean }): Tool?
	local item = Items.byId[w.kind]
	if not item or not item.tool then
		return nil
	end
	local src = templates:FindFirstChild(item.tool) or StarterPack:FindFirstChild(item.tool)
	if not src then
		return nil
	end
	local t = src:Clone() :: Tool
	local body = t:FindFirstChild("Body")
	local function drop(name: string)
		local c = (body and body:FindFirstChild(name)) or t:FindFirstChild(name)
		if c then
			c:Destroy()
		end
	end
	if t.Name == "M4A1" then
		if not w.silencer then
			drop("Suppressor")
			drop("Cage")
			local h = t:FindFirstChild("Handle") :: BasePart
			local m = h and h:FindFirstChild("Muzzle") :: Attachment?
			if m then
				m.Position = Vector3.new(m.Position.X, m.Position.Y, -1.62)
			end
		end
		if not w.grip then
			drop("KAC Forward Pistol Grip")
		end
		if not w.holo then
			drop("HoloSight")
			drop("Lens")
			drop("SightMark")
		end
	end
	t:SetAttribute("Suppressed", w.silencer)
	t:SetAttribute("RecoilMult", if w.grip then 0.65 else 1)
	t:SetAttribute("SpreadMult", if w.holo then 0.5 else 1)
	local label = string.upper(item.name)
	if w.silencer then
		label ..= "  SIL."
	end
	t:SetAttribute("Label", label)
	t:SetAttribute("ItemId", w.kind)
	t:SetAttribute("HeistGear", true)
	return t
end

function Tools.give(player: Player, toolName: string, count: number): Tool?
	local src = templates:FindFirstChild(toolName)
	local bp = player:FindFirstChild("Backpack")
	if not src or not bp then
		return nil
	end
	local existing = bp:FindFirstChild(toolName) or (player.Character and player.Character:FindFirstChild(toolName))
	if existing and existing:IsA("Tool") then
		existing:SetAttribute("Count", (existing:GetAttribute("Count") or 0) + count)
		return existing
	end
	local t = src:Clone() :: Tool
	t:SetAttribute("Count", count)
	t:SetAttribute("HeistGear", true)
	t.Parent = bp
	return t
end

-- the tool (in hand or backpack) or nil
function Tools.find(player: Player, toolName: string): Tool?
	local c = player.Character and player.Character:FindFirstChild(toolName)
	if c and c:IsA("Tool") then
		return c
	end
	local b = player:FindFirstChild("Backpack")
	local t = b and b:FindFirstChild(toolName)
	return if t and t:IsA("Tool") then t else nil
end

-- spend one use of a tool: true if the player had one (also taken from the saved inventory)
function Tools.use(player: Player, toolName: string): boolean
	local t = Tools.find(player, toolName)
	if not t then
		return false
	end
	local n = (t:GetAttribute("Count") :: number?) or 1
	if n <= 0 then
		return false
	end
	local itemId = t:GetAttribute("ItemId")
	if type(itemId) == "string" and itemId ~= "card5" then
		Data.take(player, itemId, 1)
	end
	if n - 1 <= 0 then
		t:Destroy()
	else
		t:SetAttribute("Count", n - 1)
	end
	return true
end

-- remove every heist tool and every gun (the hideout gives the StarterPack guns back on respawn)
function Tools.strip(player: Player)
	-- unequip first so the gun scripts clean up their HUD
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:UnequipTools()
	end
	for _, holder in { player:FindFirstChild("Backpack"), player.Character } do
		if holder then
			for _, t in holder:GetChildren() do
				if t:IsA("Tool") then
					t:Destroy()
				end
			end
		end
	end
end

-- vest: more health + chunky armour plates
local function wearVest(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local torso = char and char:FindFirstChild("UpperTorso") :: BasePart?
	if not hum or not torso then
		return
	end
	hum.MaxHealth = 160
	hum.Health = 160
	char:SetAttribute("Vest", true)
	local v = Instance.new("Model")
	v.Name = "HeavyVest"
	local function plate(name: string, size: Vector3, off: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = RGB(60, 80, 60)
		p.Material = Enum.Material.Fabric
		p.TopSurface = Enum.SurfaceType.Studs
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.CFrame = torso.CFrame * off
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = p
		w.Parent = p
		p.Parent = v
	end
	plate("Front", Vector3.new(torso.Size.X + 0.3, torso.Size.Y * 0.85, 0.35), CFrame.new(0, 0, -torso.Size.Z / 2 - 0.1))
	plate("Back", Vector3.new(torso.Size.X + 0.3, torso.Size.Y * 0.85, 0.35), CFrame.new(0, 0, torso.Size.Z / 2 + 0.1))
	plate("Pouch", Vector3.new(0.5, 0.4, 0.3), CFrame.new(-0.4, -0.2, -torso.Size.Z / 2 - 0.35))
	plate("Pouch", Vector3.new(0.5, 0.4, 0.3), CFrame.new(0.4, -0.2, -torso.Size.Z / 2 - 0.35))
	v.Parent = char
end

-- give a player their planned loadout (replaces whatever they carried)
function Tools.equip(player: Player, lo: any)
	Tools.strip(player)
	local bp = player:FindFirstChild("Backpack")
	if not bp then
		return
	end
	for _, w in lo.weapons do
		if Data.count(player, w.kind) > 0 then
			local t = makeWeapon(w)
			if t then
				t.Parent = bp
			end
		end
	end
	for id, n in lo.items do
		local it = Items.byId[id]
		if it and it.tool then
			local have = math.min(n, Data.count(player, id))
			if have > 0 then
				Tools.give(player, it.tool, have)
			end
		end
	end
	if lo.vest and Data.count(player, "vest") > 0 then
		wearVest(player)
	end
end

function Tools.init()
	buildTemplates()
end

return Tools
