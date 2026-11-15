--!strict
-- Cinematic camera director (client). A cinematic = Cine.begin() ... shots ... Cine.finish().
--  * letterbox bars, HUD hidden, the player's character locked (attribute Acting) and protected;
--  * a shot is a function u(0..1) -> camera CFrame, fov; cuts are instant, or blended from the previous
--    camera over `blend` seconds;
--  * camera shake, fade/flash overlay, title text;
--  * finish() blends the camera from the last shot into the normal gameplay camera, so the way back to
--    the game is smooth (the player's character must be where the last shot ended).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Cine = {}
local player = Players.LocalPlayer

local active = false
local gui: ScreenGui? = nil
local barTop: Frame? = nil
local barBottom: Frame? = nil
local veil: Frame? = nil
local titleLabel: TextLabel? = nil
local hidden: { [ScreenGui]: boolean } = {}
local shotFn: ((u: number) -> (CFrame, number?))? = nil
local shotT0, shotDur = 0, 1
local blendFrom: CFrame? = nil
local blendFov = 60
local blendDur = 0
local lastCF = CFrame.new()
local lastFov = 60
local shakeAmp, shakeDecay = 0, 4
local rng = Random.new()
local forceField: ForceField? = nil

-- the player's movement controls are switched off while a cinematic plays (WASD would fight MoveTo)
local function controls(on: boolean)
	local ps = player:FindFirstChild("PlayerScripts")
	local mod = ps and ps:FindFirstChild("PlayerModule")
	if not mod or not mod:IsA("ModuleScript") then
		return -- no default control module in this game: HeavyMovement already ignores input while Acting
	end
	local ok, err = pcall(function()
		local pm = require(mod) :: any
		local c = pm:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end)
	if not ok then
		warn("[Cine] controls", err)
	end
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
Cine.smooth = smooth

local function cam(): Camera
	return workspace.CurrentCamera
end

local function makeGui()
	if gui and gui.Parent then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "HeistCine"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 1000
	g.Parent = player:WaitForChild("PlayerGui")
	local function bar(top: boolean): Frame
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		f.Position = UDim2.fromScale(0, if top then 0 else 1)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = g
		return f
	end
	barTop, barBottom = bar(true), bar(false)
	local v = Instance.new("Frame")
	v.BackgroundColor3 = Color3.new(0, 0, 0)
	v.BackgroundTransparency = 1
	v.BorderSizePixel = 0
	v.Size = UDim2.fromScale(1, 1)
	v.ZIndex = 5
	v.Parent = g
	veil = v
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.fromScale(0.8, 0.2)
	t.FontFace = Font.fromEnum(Enum.Font.Arcade)
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(245, 205, 48)
	t.TextStrokeTransparency = 0
	t.TextTransparency = 1
	t.TextStrokeColor3 = Color3.fromRGB(27, 42, 53)
	t.ZIndex = 6
	t.Text = ""
	t.Parent = g
	titleLabel = t
	gui = g
end

local function step(dt: number)
	local c = cam()
	c.CameraType = Enum.CameraType.Scriptable
	local cf, fov = lastCF, lastFov
	if shotFn then
		local now = os.clock()
		local u = math.clamp((now - shotT0) / shotDur, 0, 1)
		local f2: number?
		cf, f2 = shotFn(u)
		fov = f2 or 60
		if blendFrom and blendDur > 0 then
			local k = smooth((now - shotT0) / blendDur)
			if k >= 1 then
				blendFrom = nil
			else
				cf = (blendFrom :: CFrame):Lerp(cf, k)
				fov = blendFov + (fov - blendFov) * k
			end
		end
	end
	lastCF, lastFov = cf, fov
	if shakeAmp > 0.001 then
		local a = shakeAmp
		cf = cf * CFrame.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0) * CFrame.Angles(rng:NextNumber(-a, a) * 0.03, rng:NextNumber(-a, a) * 0.03, rng:NextNumber(-a, a) * 0.05)
		shakeAmp = math.max(0, shakeAmp - shakeAmp * shakeDecay * dt)
	end
	c.CFrame = cf
	c.FieldOfView = fov
end

function Cine.isActive(): boolean
	return active
end

function Cine.begin()
	if active then
		return
	end
	active = true
	makeGui()
	-- HUD away
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
				hidden[g] = true
				g.Enabled = false
			end
		end
	end
	TweenService:Create(barTop :: Frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 0.11) }):Play()
	TweenService:Create(barBottom :: Frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 0.11) }):Play()
	local c = cam()
	lastCF, lastFov = c.CFrame, c.FieldOfView
	c.CameraType = Enum.CameraType.Scriptable
	local char = player.Character
	if char then
		char:SetAttribute("Acting", true)
		local ff = Instance.new("ForceField")
		ff.Visible = false
		ff.Parent = char
		forceField = ff
	end
	controls(false)
	RunService:BindToRenderStep("HeistCine", Enum.RenderPriority.Camera.Value + 10, step)
end

-- start a shot (does not wait). blend = seconds to glide from the previous camera instead of cutting.
function Cine.shot(dur: number, fn: (u: number) -> (CFrame, number?), blend: number?)
	blendFrom = if blend and blend > 0 then lastCF else nil
	blendFov = lastFov
	blendDur = blend or 0
	shotFn = fn
	shotT0 = os.clock()
	shotDur = math.max(dur, 0.05)
end

function Cine.wait(seconds: number)
	task.wait(seconds)
end

-- a shot and wait for it
function Cine.play(dur: number, fn: (u: number) -> (CFrame, number?), blend: number?)
	Cine.shot(dur, fn, blend)
	task.wait(dur)
end

function Cine.shake(amp: number, decay: number?)
	shakeAmp = math.max(shakeAmp, amp)
	shakeDecay = decay or 4
end

-- screen veil: colour, target transparency (0 = opaque), seconds
function Cine.fade(color: Color3, to: number, dur: number)
	if veil then
		veil.BackgroundColor3 = color
		TweenService:Create(veil, TweenInfo.new(dur, Enum.EasingStyle.Quad), { BackgroundTransparency = to }):Play()
	end
end

function Cine.title(text: string, dur: number)
	if titleLabel then
		titleLabel.Text = text
		titleLabel.TextTransparency = 1
		titleLabel.TextStrokeTransparency = 1
		TweenService:Create(titleLabel, TweenInfo.new(0.4), { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
		task.delay(dur, function()
			if titleLabel then
				TweenService:Create(titleLabel, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end
end

-- walk the player's character (or any model) somewhere with its own walk animation; yields
function Cine.walk(char: Model, pos: Vector3, speed: number, timeout: number?)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	hum.WalkSpeed = speed
	hum:MoveTo(pos)
	local t0 = os.clock()
	local last = os.clock()
	while os.clock() - t0 < (timeout or 4) do
		local flat = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
		if flat.Magnitude < 1 then
			break
		end
		-- turn toward the way it walks (smoothly)
		local dt = os.clock() - last
		last = os.clock()
		local want = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		local cur = root.CFrame
		root.CFrame = cur:Lerp(want, math.min(1, dt * 12))
		hum:MoveTo(pos)
		RunService.Heartbeat:Wait()
	end
	hum:MoveTo(root.Position)
end

-- turn a character to face a point over `dur` seconds
function Cine.face(char: Model, at: Vector3, dur: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local t0 = os.clock()
	local from = root.CFrame
	local flat = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	local to = CFrame.lookAt(root.Position, root.Position + flat)
	while os.clock() - t0 < dur do
		root.CFrame = from:Lerp(to, smooth((os.clock() - t0) / dur))
		task.wait()
	end
	root.CFrame = to
end

-- leave the cinematic: bars away, the camera glides from the last shot into the gameplay camera
function Cine.finish(blend: number?)
	if not active then
		return
	end
	local dur = blend or 0.9
	local c = cam()
	local from = lastCF
	local fromFov = lastFov
	shotFn = nil
	RunService:UnbindFromRenderStep("HeistCine")
	c.CameraType = Enum.CameraType.Custom
	local t0 = os.clock()
	RunService:BindToRenderStep("HeistCineOut", Enum.RenderPriority.Camera.Value + 1, function()
		local k = smooth((os.clock() - t0) / dur)
		-- the default camera has just placed itself for this frame: slide from the cinematic's last frame
		c.CFrame = from:Lerp(c.CFrame, k)
		c.FieldOfView = fromFov + (c.FieldOfView - fromFov) * k
		if k >= 1 then
			RunService:UnbindFromRenderStep("HeistCineOut")
		end
	end)
	if barTop and barBottom then
		TweenService:Create(barTop, TweenInfo.new(0.6), { Size = UDim2.fromScale(1, 0) }):Play()
		TweenService:Create(barBottom, TweenInfo.new(0.6), { Size = UDim2.fromScale(1, 0) }):Play()
	end
	if veil then
		TweenService:Create(veil, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end
	for g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hidden)
	local char = player.Character
	if char then
		char:SetAttribute("Acting", nil)
	end
	controls(true)
	if forceField then
		local ff = forceField
		task.delay(1.5, function()
			ff:Destroy()
		end)
		forceField = nil
	end
	active = false
end

-- hide (or show again) a model on this client only
function Cine.hide(m: Instance, hidden: boolean)
	local v = if hidden then 1 else 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			(d :: any).LocalTransparencyModifier = v
		end
	end
	if m:IsA("BasePart") then
		m.LocalTransparencyModifier = v
	end
end

-- a one-shot sound (not attached to the cinematic's lifetime)
function Cine.sound(id: string, at: Instance | Vector3, volume: number?, pitch: number?, maxDist: number?): Sound
	local parent: Instance
	if typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		Debris:AddItem(a, 12)
		parent = a
	else
		parent = at :: Instance
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.RollOffMaxDistance = maxDist or 250
	s.RollOffMinDistance = 8
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 12)
	return s
end

------------------------------------------------------------------ camera helpers for the shots

-- a camera at `pos` looking at `target`, pulled in toward the target if a wall, a door wheel or any
-- other solid thing sits between them (characters, NPCs, effects and see-through parts don't count)
local safeParams = RaycastParams.new()
safeParams.FilterType = Enum.RaycastFilterType.Exclude
function Cine.safe(pos: Vector3, target: Vector3): CFrame
	local ignore: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, n in { "NPCs", "LooseGunParts", "HeistFx", "WeaponFx", "CinePolice" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	safeParams.FilterDescendantsInstances = ignore
	local dir = pos - target
	local hit = workspace:Raycast(target, dir, safeParams)
	for _ = 1, 4 do
		if hit and (hit.Instance.Transparency > 0.6 or not hit.Instance.CanCollide and hit.Instance.Transparency > 0.2) then
			table.insert(ignore, hit.Instance)
			safeParams.FilterDescendantsInstances = ignore
			hit = workspace:Raycast(target, dir, safeParams)
		else
			break
		end
	end
	if hit then
		local d = math.max(0.6, (hit.Position - target).Magnitude - 0.5)
		pos = target + dir.Unit * d
	end
	return CFrame.lookAt(pos, target)
end


-- camera at `pos` looking at `target`
function Cine.look(pos: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(pos, target)
end

-- orbit: angle in degrees around `center`, at `radius` and `height` above it
function Cine.orbit(center: Vector3, radius: number, height: number, angleDeg: number, lookAtOffset: Vector3?): CFrame
	local a = math.rad(angleDeg)
	local pos = center + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)
	return CFrame.lookAt(pos, center + (lookAtOffset or Vector3.zero))
end

return Cine
