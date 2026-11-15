--!strict
-- Heist sounds (Roblox library ids picked with AssetService:SearchAudio) and goofy effect helpers that
-- work on the server (everyone sees them) or on a client (only that player).
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Sfx = {}

Sfx.ID = {
	alarm = "rbxassetid://9113085203",
	drill = "rbxassetid://9117875538",
	beep = "rbxassetid://73008260408244",
	siren = "rbxassetid://9056622054",
	cash = "rbxassetid://120891770644830",
	zap = "rbxassetid://92090867642655",
	glass = "rbxassetid://139826391278483",
	horn = "rbxassetid://137100035389921",
	key = "rbxassetid://9113880475",
	granted = "rbxassetid://85528835890150",
	door = "rbxassetid://137843505116528",
	thud = "rbxassetid://9117413937",
	boing = "rbxassetid://131916027000817",
	whoosh = "rbxassetid://111254855668531",
	rope = "rbxassetid://9118718610",
	clank = "rbxassetid://9116541944",
	pop = "rbxassetid://9113263649",
}

-- one-shot sound at a part or a position
function Sfx.play(name: string, at: Instance | Vector3, volume: number?, pitch: number?, maxDist: number?): Sound
	local holder: Instance
	if typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		Debris:AddItem(a, 12)
		holder = a
	else
		holder = at
	end
	local s = Instance.new("Sound")
	s.SoundId = Sfx.ID[name] or name
	s.Volume = volume or 0.8
	s.PlaybackSpeed = pitch or 1
	s.RollOffMaxDistance = maxDist or 160
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = holder
	s:Play()
	Debris:AddItem(s, 12)
	return s
end

-- looped sound kept on a part (returns it so the caller can stop it)
function Sfx.loop(name: string, part: Instance, volume: number?, maxDist: number?): Sound
	local s = Instance.new("Sound")
	s.SoundId = Sfx.ID[name] or name
	s.Volume = volume or 0.7
	s.Looped = true
	s.RollOffMaxDistance = maxDist or 220
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = part
	s:Play()
	return s
end

local fxFolder: Folder? = nil
local function folder(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = workspace:FindFirstChild("HeistFx") or Instance.new("Folder")
		f.Name = "HeistFx"
		f.Parent = workspace
		fxFolder = f :: Folder
	end
	return fxFolder :: Folder
end
Sfx.folder = folder

-- cartoon text that pops above a point ("BOOM!", "+$1 200", "CLAC !")
function Sfx.popText(pos: Vector3, text: string, color: Color3?, size: number?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Position = pos
	p.Parent = folder()
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(size or 8, (size or 8) * 0.35)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = p
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = text
	l.TextScaled = true
	l.FontFace = Font.fromEnum(Enum.Font.Arcade)
	l.TextColor3 = color or Color3.fromRGB(245, 205, 48)
	l.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(27, 42, 53)
	st.Parent = l
	l.Rotation = math.random(-12, 12)
	local sc = Instance.new("UIScale")
	sc.Scale = 0.2
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos + Vector3.new(0, 5, 0) }):Play()
	task.delay(1.1, function()
		TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(st, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(p, 1.8)
end

-- round cartoon smoke puffs that grow and fade
function Sfx.puff(pos: Vector3, count: number?, color: Color3?, radius: number?)
	local r = radius or 4
	for _ = 1, count or 8 do
		local b = Instance.new("Part")
		b.Shape = Enum.PartType.Ball
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.SmoothPlastic
		b.Color = color or Color3.fromRGB(230, 230, 230)
		local s = math.random() * 1.5 + 1.2
		b.Size = Vector3.new(s, s, s)
		b.Position = pos + Vector3.new((math.random() - 0.5) * r, (math.random() - 0.2) * r * 0.6, (math.random() - 0.5) * r)
		b.Parent = folder()
		local grow = s * (2.2 + math.random())
		TweenService:Create(b, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(grow, grow, grow), Transparency = 1, Position = b.Position + Vector3.new(0, 3 + math.random() * 3, 0) }):Play()
		Debris:AddItem(b, 1)
	end
end

-- chunky debris blocks flying out, spinning, then fading (server: physics replicated)
function Sfx.debris(pos: Vector3, dir: Vector3, count: number, color: Color3, material: Enum.Material?)
	for _ = 1, count do
		local d = Instance.new("Part")
		local s = 0.6 + math.random() * 1.4
		d.Size = Vector3.new(s, s * (0.6 + math.random() * 0.8), s)
		d.Color = color
		d.Material = material or Enum.Material.Concrete
		d.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 4, (math.random() - 0.5) * 4, (math.random() - 0.5) * 4))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		d.CanQuery = false
		d.CanTouch = false
		d.CollisionGroup = "Default"
		d.Parent = folder()
		local v = (dir.Unit * (25 + math.random() * 35)) + Vector3.new((math.random() - 0.5) * 30, 15 + math.random() * 25, (math.random() - 0.5) * 30)
		d.AssemblyLinearVelocity = v
		d.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
		task.delay(4 + math.random() * 2, function()
			if d.Parent then
				TweenService:Create(d, TweenInfo.new(0.6), { Transparency = 1, Size = d.Size * 0.3 }):Play()
			end
		end)
		Debris:AddItem(d, 7)
	end
end

-- cash confetti (little green bills fluttering)
function Sfx.confetti(pos: Vector3, count: number?)
	for _ = 1, count or 14 do
		local b = Instance.new("Part")
		b.Size = Vector3.new(0.9, 0.05, 0.45)
		b.Color = Color3.fromRGB(104, 160, 92)
		b.Material = Enum.Material.SmoothPlastic
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		b.Parent = folder()
		b.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 30, 18 + math.random() * 18, (math.random() - 0.5) * 30)
		b.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
		local drag = Instance.new("VectorForce")
		local att = Instance.new("Attachment")
		att.Parent = b
		drag.Attachment0 = att
		drag.RelativeTo = Enum.ActuatorRelativeTo.World
		drag.Force = Vector3.new(0, b.AssemblyMass * workspace.Gravity * 0.85, 0)
		drag.Parent = b
		Debris:AddItem(b, 4 + math.random() * 2)
	end
end

return Sfx
