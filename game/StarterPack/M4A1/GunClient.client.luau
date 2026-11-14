--!strict
-- M4A1 client: input, over-the-shoulder + first-person aiming, recoil, reload animation, HUD and local effects.
-- The server (WeaponServer) decides hits, damage and ammo; this script predicts them for instant feel.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local tool = script.Parent :: Tool
local handle = tool:WaitForChild("Handle") :: BasePart
local muzzle = handle:WaitForChild("Muzzle") :: Attachment

local Weapons = ReplicatedStorage:WaitForChild("Weapons")
local Config = require(Weapons:WaitForChild("WeaponConfig"))
local Fx = require(Weapons:WaitForChild("WeaponFx"))
local GunPose = require(Weapons:WaitForChild("GunPose"))
local GunAnim = require(Weapons:WaitForChild("GunAnim"))
local cfg = Config[tool.Name]
local remotes = ReplicatedStorage:WaitForChild("WeaponRemotes")
local FireRemote = remotes:WaitForChild("Fire") :: RemoteEvent
local ReloadRemote = remotes:WaitForChild("Reload") :: RemoteEvent
local PoseRemote = remotes:WaitForChild("Pose") :: RemoteEvent
local gameSettings = UserSettings():GetService("UserGameSettings")

-- camera offsets in camera space (right, up); aiming also pulls the camera in close
local HIP_OFFSET = Vector2.new(1.6, 0.35)
local AIM_OFFSET = Vector2.new(3.1, 0.45)
local AIM_DISTANCE = 6.5 -- studs from the character while aiming
local FACE_AFTER_SHOT = 0.6 -- seconds the character keeps facing the camera after hip fire
local BASE_FOV = 70
-- first person: where the gun's handle sits relative to the camera
local FP_HIP = CFrame.new(0.5, -0.78, -1.55) * CFrame.Angles(0, math.rad(2), 0)
local FP_AIM = CFrame.new(0.022, -0.615, -1.05) -- eye lined up with the holo sight
-- the avatar's own arms are far too chunky this close to the camera: first person draws slim local arms
local FP_ELBOW = { Right = Vector3.new(0.8, -1.3, -0.35), Left = Vector3.new(-0.6, -1.2, -0.9) } -- camera space
local GLOVE = Color3.fromRGB(28, 29, 31)
local SLEEVE = Color3.fromRGB(74, 80, 62)
local HOLO_DOT_DIST = 1.19 -- studs in front of the eye: the sight window while aiming in first person
local RENDER_NAME = "GunCamera_" .. tool.Name
local RED = Color3.fromRGB(255, 45, 45)
local IS_STUDIO = RunService:IsStudio()

local equipped, triggerDown, aiming, reloading = false, false, false, false
local ammo = (tool:GetAttribute("Ammo") :: number?) or cfg.MagSize
local reserve = (tool:GetAttribute("Reserve") :: number?) or cfg.Reserve
local lastShot = 0
local recoil = Vector2.zero -- pending camera kick (pitch, yaw) in radians
local bloom = 0 -- extra spread from sustained fire, degrees
local reloadToken = 0
local firing: thread? = nil
local humanoid: Humanoid? = nil
local baseWalkSpeed = 16
local aimAlpha = 0 -- 0 = low ready, 1 = shouldered (smoothed)
local camOffset = Vector2.zero
local lastPoseSent = 0
local sentAiming, sentPitch, sentYaw = false, 0, 0
local kick = Vector2.zero -- gun recoil (back, pitch up), springs back to zero
local sway = Vector2.zero -- first-person weapon sway from camera turning
local lastLook: Vector3? = nil
local bobT = 0
local firstPersonToggle = false
local wasFirstPerson = false
local viewArms: Model? = nil
local cleanup: { RBXScriptConnection } = {}

-- HUD ----------------------------------------------------------------------
local gui: ScreenGui? = nil
local ammoLabel: TextLabel? = nil
local reserveLabel: TextLabel? = nil
local hitmarker: Frame? = nil

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = p
end

local function bar(parent: Instance, pos: UDim2, size: UDim2, rot: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.Rotation = rot or 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Transparency = 0.5
	s.Thickness = 1
	s.Parent = f
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, pos: UDim2, size: UDim2, maxSize: number, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = Enum.Font.GothamBold
	t.Text = text
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.TextXAlignment = align
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = t
	local s = Instance.new("UIStroke")
	s.Thickness = 1.5
	s.Transparency = 0.4
	s.Parent = t
	t.Parent = parent
	return t
end

local function updateHud()
	if ammoLabel and reserveLabel then
		ammoLabel.Text = reloading and "--" or tostring(ammo)
		ammoLabel.TextColor3 = (ammo <= math.floor(cfg.MagSize * 0.2) and not reloading) and RED or Color3.new(1, 1, 1)
		reserveLabel.Text = reloading and "RELOADING" or ("/ " .. reserve)
	end
end

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "GunHUD"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true -- so the screen centre matches the camera's aim ray
	g.DisplayOrder = 5


	-- hit marker: an X that flashes when a shot lands on a character
	local hm = Instance.new("Frame")
	hm.Name = "Hitmarker"
	hm.AnchorPoint = Vector2.new(0.5, 0.5)
	hm.Position = UDim2.fromScale(0.5, 0.5)
	hm.Size = UDim2.fromScale(0.03, 0.03)
	hm.BackgroundTransparency = 1
	hm.Visible = false
	local ar3 = Instance.new("UIAspectRatioConstraint")
	ar3.Parent = hm
	for i, p in { { 0.2, 0.2 }, { 0.8, 0.2 }, { 0.2, 0.8 }, { 0.8, 0.8 } } do
		bar(hm, UDim2.fromScale(p[1], p[2]), UDim2.new(0.35, 0, 0, 2), (i == 1 or i == 4) and 45 or -45)
	end
	hm.Parent = g

	-- ammo panel, bottom right
	local panel = Instance.new("Frame")
	panel.Name = "Ammo"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.fromScale(0.975, 0.95)
	panel.Size = UDim2.fromScale(0.17, 0.11)
	panel.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel = 0
	local ar4 = Instance.new("UIAspectRatioConstraint")
	ar4.AspectRatio = 2.6
	ar4.Parent = panel
	corner(panel, 0.18)
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 255, 255)
	st.Transparency = 0.85
	st.Thickness = 1.5
	st.Parent = panel
	local accent = Instance.new("Frame")
	accent.Position = UDim2.fromScale(0.06, 0.12)
	accent.Size = UDim2.fromScale(0.012, 0.76)
	accent.BackgroundColor3 = RED
	accent.BorderSizePixel = 0
	corner(accent, 0.5)
	accent.Parent = panel
	label(panel, tool.Name .. "  SUPPRESSED", UDim2.fromScale(0.11, 0.1), UDim2.fromScale(0.84, 0.24), 16, Enum.TextXAlignment.Left).TextTransparency = 0.35
	ammoLabel = label(panel, "", UDim2.fromScale(0.11, 0.34), UDim2.fromScale(0.42, 0.56), 52, Enum.TextXAlignment.Left)
	reserveLabel = label(panel, "", UDim2.fromScale(0.5, 0.47), UDim2.fromScale(0.45, 0.36), 26, Enum.TextXAlignment.Left)
	panel.Parent = g

	g.Parent = player:WaitForChild("PlayerGui")
	gui, hitmarker = g, hm
	updateHud()
end

local hitToken = 0
local function flashHitmarker(head: boolean)
	local hm = hitmarker
	if not hm then
		return
	end
	hitToken += 1
	local my = hitToken
	for _, b in hm:GetChildren() do
		if b:IsA("Frame") then
			b.BackgroundColor3 = head and RED or Color3.new(1, 1, 1)
		end
	end
	hm.Visible = true
	task.delay(0.12, function()
		if hitToken == my then
			hm.Visible = false
		end
	end)
end

-- Shooting -----------------------------------------------------------------
local function rayParams(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	local fx = Workspace:FindFirstChild("WeaponFx")
	if fx then
		table.insert(list, fx)
	end
	p.FilterDescendantsInstances = list
	return p
end

local function aimTarget(params: RaycastParams): Vector3
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	local r = Workspace:Raycast(ray.Origin, ray.Direction * cfg.Range, params)
	return r and r.Position or ray.Origin + ray.Direction * cfg.Range
end

local reload: () -> ()

local function fireOnce()
	if ammo <= 0 then
		Fx.sound(tool, "Empty")
		triggerDown = false
		if reserve > 0 then
			reload()
		end
		return
	end
	ammo -= 1
	updateHud()

	local params = rayParams()
	local origin = muzzle.WorldPosition
	local target = aimTarget(params)
	local dir = (target - origin).Unit
	-- random direction inside a cone (uniform over the disc)
	local spread = math.rad((aiming and cfg.AimSpread or cfg.HipSpread) + bloom) * math.sqrt(math.random())
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, math.random() * math.pi * 2) * CFrame.Angles(spread, 0, 0)).LookVector

	FireRemote:FireServer(origin, dir)

	local r = Workspace:Raycast(origin, dir * cfg.Range, params)
	local hitPos = r and r.Position or origin + dir * cfg.Range
	Fx.sound(tool, "Fire")
	Fx.muzzle(tool)
	Fx.tracer(origin, hitPos)
	if r then
		local model = r.Instance:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		local hitChar = hum ~= nil and hum.Health > 0
		Fx.impact(r.Position, r.Normal, hitChar)
		if hitChar then
			flashHitmarker(r.Instance.Name == "Head")
		end
	end

	local k = aiming and 0.6 or 1
	recoil += Vector2.new(math.rad(cfg.RecoilUp * k), math.rad((math.random() * 2 - 1) * cfg.RecoilSide * k))
	bloom = math.min(bloom + 0.22, 2.5)
	kick += Vector2.new(aiming and 0.06 or 0.1, math.rad(aiming and 1.6 or 2.8))
end

local function startFiring()
	if firing then
		return
	end
	firing = task.spawn(function()
		local interval = 60 / cfg.RPM
		while triggerDown and equipped do
			local now = os.clock()
			if not reloading and now - lastShot >= interval then
				lastShot = now
				fireOnce()
			end
			RunService.Heartbeat:Wait()
		end
		firing = nil
		-- trigger released: take the server's count again
		ammo = (tool:GetAttribute("Ammo") :: number?) or ammo
		updateHud()
	end)
end

reload = function()
	if reloading or not equipped or ammo >= cfg.MagSize or reserve <= 0 then
		return
	end
	reloading = true
	reloadToken += 1
	local my = reloadToken
	ReloadRemote:FireServer()
	Fx.sound(tool, "Reload")
	updateHud()
	GunAnim.startReload(tool, cfg.ReloadTime)
	task.delay(cfg.ReloadTime, function()
		if reloadToken ~= my then
			return
		end
		local take = math.min(cfg.MagSize - ammo, reserve)
		ammo += take
		reserve -= take
		reloading = false
		updateHud()
	end)
end

-- Server is the source of truth for ammo: resync whenever we're not mid-burst or mid-reload.
tool:GetAttributeChangedSignal("Ammo"):Connect(function()
	if not firing and not reloading then
		ammo = (tool:GetAttribute("Ammo") :: number?) or ammo
		updateHud()
	end
end)
tool:GetAttributeChangedSignal("Reserve"):Connect(function()
	if not reloading then
		reserve = (tool:GetAttribute("Reserve") :: number?) or reserve
		updateHud()
	end
end)

-- Camera / aim -------------------------------------------------------------
local function setAiming(on: boolean)
	aiming = on and equipped
	if humanoid then
		humanoid.WalkSpeed = aiming and math.min(cfg.AimWalkSpeed, baseWalkSpeed) or baseWalkSpeed
	end
end

local function camRayParams(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = player.Character and { player.Character } or {}
	return p
end

local function vmPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

local function destroyViewArms()
	local sight = tool:FindFirstChild("HoloSight") :: BasePart?
	if sight then
		sight.LocalTransparencyModifier = 0
	end
	if viewArms then
		viewArms:Destroy()
		viewArms = nil
	end
end

local function updateViewArms(handleCF: CFrame, camCF: CFrame)
	local m = viewArms
	if not m then
		m = Instance.new("Model")
		m.Name = "ViewArms"
		vmPart(m, "RightGlove", Vector3.new(0.24, 0.36, 0.28), GLOVE, Enum.Material.Fabric)
		vmPart(m, "LeftGlove", Vector3.new(0.26, 0.2, 0.4), GLOVE, Enum.Material.Fabric)
		vmPart(m, "RightSleeve", Vector3.new(0.27, 0.27, 1), SLEEVE, Enum.Material.Fabric)
		vmPart(m, "LeftSleeve", Vector3.new(0.27, 0.27, 1), SLEEVE, Enum.Material.Fabric)
		local dot = vmPart(m, "HoloDot", Vector3.new(0.016, 0.016, 0.016), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		dot.Shape = Enum.PartType.Ball
		m.Parent = Workspace.CurrentCamera
		viewArms = m
	end
	local model = m :: Model
	for _, side in { "Right", "Left" } do
		local att = handle:FindFirstChild(side .. "HandIK") :: Attachment?
		local glove = model:FindFirstChild(side .. "Glove") :: BasePart?
		local sleeve = model:FindFirstChild(side .. "Sleeve") :: BasePart?
		if att and glove and sleeve then
			local handCF = handleCF * att.CFrame
			glove.CFrame = handCF
			local wrist = handCF.Position
			local elbow = camCF:PointToWorldSpace(FP_ELBOW[side])
			local len = (elbow - wrist).Magnitude
			sleeve.Size = Vector3.new(0.27, 0.27, len + 0.1)
			sleeve.CFrame = CFrame.lookAt((wrist + elbow) / 2, elbow)
		end
	end
	-- aiming: the sight body turns see-through and its red dot sits on the line of sight
	local sight = tool:FindFirstChild("HoloSight") :: BasePart?
	if sight then
		sight.LocalTransparencyModifier = aimAlpha * 0.8
	end
	local dot = model:FindFirstChild("HoloDot") :: BasePart?
	if dot then
		dot.CFrame = camCF * CFrame.new(0, 0, -HOLO_DOT_DIST)
		dot.Transparency = aimAlpha > 0.7 and 0 or 1
	end
end

local function renderStep(dt: number)
	local cam = Workspace.CurrentCamera
	local hum = humanoid
	local char = player.Character
	if not hum or not equipped or not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = GunPose.torsoFor(char)
	local weld = handle:FindFirstChild("GunHold") :: Weld?
	local dist = (cam.CFrame.Position - cam.Focus.Position).Magnitude
	local firstPerson = dist < 1.2
	local now = os.clock()

	-- no cursor; the camera follows the mouse freely
	UserInputService.MouseIconEnabled = false
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	local alpha = math.min(1, dt * 12)
	aimAlpha += ((aiming and 1 or 0) - aimAlpha) * math.min(1, dt * 14)
	cam.FieldOfView += ((aiming and cfg.AimFov or BASE_FOV) - cam.FieldOfView) * alpha

	-- recoil: camera kick applied over a few frames, gun kick springs back
	local step = recoil * math.min(1, dt * 22)
	recoil -= step
	cam.CFrame *= CFrame.Angles(step.X, step.Y, 0)
	bloom = math.max(0, bloom - dt * 3)
	kick *= math.exp(-dt * 14)
	local kickCF = CFrame.new(0, 0, kick.X) * CFrame.Angles(kick.Y, 0, 0)

	-- third person: over-the-shoulder offset in camera space
	if not firstPerson then
		camOffset = camOffset:Lerp(aiming and AIM_OFFSET or HIP_OFFSET, alpha)
		local pull = aimAlpha * math.max(0, dist - AIM_DISTANCE)
		local from = cam.CFrame.Position
		local to = cam.CFrame:PointToWorldSpace(Vector3.new(camOffset.X, camOffset.Y, -pull))
		local hit = Workspace:Raycast(from, to - from, camRayParams())
		if hit then
			to = hit.Position - (to - from).Unit * 0.3
		end
		cam.CFrame = CFrame.new(to) * cam.CFrame.Rotation
	end

	local reloadCF = GunAnim.step(tool, torso)
	local pitch = math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1))
	local yaw = 0

	if firstPerson then
		gameSettings.RotationType = Enum.RotationType.CameraRelative
		-- sway: the gun lags a little behind fast camera turns
		local look = cam.CFrame.LookVector
		local turn = Vector2.zero
		if lastLook then
			local d = cam.CFrame:VectorToObjectSpace(lastLook)
			turn = Vector2.new(math.asin(math.clamp(d.Y, -1, 1)), math.atan2(-d.X, -d.Z))
		end
		lastLook = look
		local swayK = aiming and 0.35 or 1
		local target = Vector2.new(math.clamp(turn.X * 2.5, -0.12, 0.12), math.clamp(turn.Y * 2.5, -0.12, 0.12)) * swayK
		sway = sway:Lerp(target, math.min(1, dt * 10))
		-- bob while walking, slow breathing while still
		local speed = root and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude or 0
		bobT += dt * (speed * 0.55 + 1.2)
		local amp = math.min(speed / 16, 1) * (aiming and 0.2 or 1)
		local breathe = (aiming and 0.3 or 1) * 0.008
		local bobCF = CFrame.new(math.sin(bobT) * 0.035 * amp, -math.abs(math.cos(bobT)) * 0.03 * amp + math.sin(now * 1.6) * breathe, 0)
			* CFrame.Angles(0, 0, math.sin(bobT) * 0.02 * amp)
		local swayCF = CFrame.Angles(sway.X, sway.Y, sway.Y * 0.6)
		local lower = GunAnim.isReloading(tool) and CFrame.new(0, -0.12, 0.1) or CFrame.identity
		local vm = FP_HIP:Lerp(FP_AIM, aimAlpha) * bobCF * swayCF * lower * CFrame.new(0, 0, kick.X * 1.4) * CFrame.Angles(kick.Y * 0.8, 0, 0)
		local handleCF = cam.CFrame * vm * reloadCF
		if weld and torso then
			weld.C0 = torso.CFrame:ToObjectSpace(handleCF)
		end
		updateViewArms(handleCF, cam.CFrame)
	else
		if wasFirstPerson then
			destroyViewArms()
			lastLook = nil
		end
		-- point the gun at whatever is under the screen centre
		if torso then
			local target = aimTarget(rayParams())
			yaw, pitch = GunPose.anglesTo(torso, aimAlpha, target)
		end
		-- not aiming: the body faces where you walk and the gun swings toward the target (up to MAX_YAW).
		-- aiming or just after shooting: the body turns to face where you look.
		local faceCamera = aiming or (now - lastShot < FACE_AFTER_SHOT)
		gameSettings.RotationType = faceCamera and Enum.RotationType.CameraRelative or Enum.RotationType.MovementRelative
		if weld and torso then
			weld.C0 = GunPose.cframe(torso.Size, aimAlpha, pitch, yaw) * kickCF * reloadCF
		end
	end
	wasFirstPerson = firstPerson

	-- tell the server so everyone else sees where the gun points
	if now - lastPoseSent > 0.1 and (aiming ~= sentAiming or math.abs(pitch - sentPitch) > 0.03 or math.abs(yaw - sentYaw) > 0.03) then
		lastPoseSent, sentAiming, sentPitch, sentYaw = now, aiming, pitch, yaw
		PoseRemote:FireServer(aiming or firstPerson, pitch, yaw)
	end

	-- Studio-only test hook: set tool attribute TestCam (Vector3, character space) to film the gun
	if IS_STUDIO and root then
		local v = tool:GetAttribute("TestCam")
		if typeof(v) == "Vector3" then
			cam.CFrame = CFrame.lookAt(root.CFrame:PointToWorldSpace(v), root.CFrame:PointToWorldSpace(Vector3.new(0.6, 1.4, -1.6)))
		end
	end
end

local function toggleView()
	firstPersonToggle = not firstPersonToggle
	if firstPersonToggle then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		-- pop the camera back out to third person
		local min = player.CameraMinZoomDistance
		player.CameraMinZoomDistance = 10
		task.delay(0.1, function()
			player.CameraMinZoomDistance = min
		end)
	end
end

-- Input ---------------------------------------------------------------------
local function onAimAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		setAiming(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setAiming(false)
	end
	return Enum.ContextActionResult.Sink
end

local function onViewAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		toggleView()
	end
	return Enum.ContextActionResult.Sink
end

local function onReloadAction(_: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		reload()
	end
	return Enum.ContextActionResult.Sink
end

local function unequip()
	if not equipped then
		return
	end
	equipped = false
	triggerDown = false
	reloadToken += 1
	reloading = false
	GunAnim.stop(tool)
	setAiming(false)
	if firstPersonToggle then
		toggleView()
	end
	destroyViewArms()
	wasFirstPerson, lastLook = false, nil
	kick, sway = Vector2.zero, Vector2.zero
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	ContextActionService:UnbindAction("GunAim")
	ContextActionService:UnbindAction("GunReload")
	ContextActionService:UnbindAction("GunView")
	for _, c in cleanup do
		c:Disconnect()
	end
	table.clear(cleanup)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	gameSettings.RotationType = Enum.RotationType.MovementRelative
	local cam = Workspace.CurrentCamera
	cam.FieldOfView = BASE_FOV
	if humanoid then
		humanoid.WalkSpeed = baseWalkSpeed
	end
	if gui then
		gui:Destroy()
	end
	gui, ammoLabel, reserveLabel, hitmarker = nil, nil, nil, nil
	humanoid = nil
	aimAlpha = 0
end

tool.Equipped:Connect(function()
	local char = tool.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	equipped = true
	humanoid = hum
	baseWalkSpeed = hum.WalkSpeed
	-- the server welds the gun to the torso; drop the default hand weld locally too so it can't fight it
	local hand = (char :: Model):FindFirstChild("RightHand") or (char :: Model):FindFirstChild("Right Arm")
	if hand then
		local g = hand:FindFirstChild("RightGrip")
		if g then
			g:Destroy()
		end
		table.insert(cleanup, hand.ChildAdded:Connect(function(c)
			if c.Name == "RightGrip" then
				task.defer(c.Destroy, c)
			end
		end))
	end
	sentAiming, sentPitch, sentYaw = false, 0, 0
	GunAnim.remember(tool)
	ammo = (tool:GetAttribute("Ammo") :: number?) or ammo
	reserve = (tool:GetAttribute("Reserve") :: number?) or reserve
	buildHud()
	Fx.sound(tool, "Equip")
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, renderStep)
	ContextActionService:BindAction("GunAim", onAimAction, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("GunReload", onReloadAction, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("GunAim", "AIM")
	ContextActionService:SetTitle("GunReload", "R")
	ContextActionService:BindAction("GunView", onViewAction, true, Enum.KeyCode.V, Enum.KeyCode.ButtonR3)
	ContextActionService:SetTitle("GunView", "VIEW")
	table.insert(cleanup, hum.Died:Connect(unequip))
end)

tool.Unequipped:Connect(unequip)
tool.AncestryChanged:Connect(function()
	if not tool:IsDescendantOf(game) then
		unequip()
	end
end)

tool.Activated:Connect(function()
	if not equipped then
		return
	end
	if ammo <= 0 and not reloading then
		fireOnce() -- click + auto reload
		return
	end
	triggerDown = true
	startFiring()
end)

tool.Deactivated:Connect(function()
	triggerDown = false
end)
