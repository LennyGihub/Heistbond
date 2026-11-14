--!strict
-- Heavier, more realistic movement for the local character:
--  * speed builds up and dies down instead of starting/stopping instantly
--  * the body turns at a limited rate instead of snapping
--  * not aiming: the character only ever moves the way it faces, so the walk cycle never slides
--  * aiming (character attribute AimYaw, set by GunClient): face the aim, strafe freely; walking
--    backwards plays the walk cycle in reverse instead of moonwalking
--  * Rthro walk/run animations whose playback speed is set from the real ground speed every frame,
--    so the feet never slide; Left Shift sprints
--  * Ctrl (gamepad B) toggles a sneaky crouch-walk: slower, its own animation, a crouched idle when still
--  * custom jump (timed to the real time in the air) and a landing absorb
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local TURN_RATE = math.rad(320) -- turning speed while walking (radians per second)
local TURN_RATE_AIM = math.rad(480)
local TURN_RATE_IDLE = math.rad(360) -- turning on the spot
local ACCEL = 20 -- studs/s^2 to build up speed
local DECEL = 32 -- studs/s^2 to slow down
local SHARP_TURN_SPEED = 0.35 -- speed kept while turning more than ~90 degrees

local WALK_SPEED = 8 -- heavier, realistic walking pace (Roblox default is 16)
local SPRINT_SPEED = 15 -- hold Left Shift
local AIM_SPEED = 6 -- while aiming
local SNEAK_SPEED = 4 -- Ctrl toggles sneaking

-- Roblox's official Rthro walk/run, and how much ground each covers per 1x playback (measured in Studio:
-- the stance foot's backward travel), so the playback speed can match the real ground speed exactly
local WALK_ANIM = "rbxassetid://2510202577"
local RUN_ANIM = "rbxassetid://2510198475"
local WALK_STRIDE = 6.3 -- studs/s at 1x (tuned in Studio for the least foot slip)
local RUN_STRIDE = 6.5
-- custom run (replaces the Rthro run when present): ReplicatedStorage.Animations.Run (Animation with the
-- published id) - or, in Studio playtests only, the unpublished clip ReplicatedStorage.Animations.RunClip.
-- Its ground speed at 1x is stored as the attribute Stride on whichever one is used.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IS_STUDIO = RunService:IsStudio()
local runStride = RUN_STRIDE
local ContextActionService = game:GetService("ContextActionService")
local sneaking = false
local sneakTrack: AnimationTrack? = nil
local sneakIdleTrack: AnimationTrack? = nil
local jumpTrack: AnimationTrack? = nil
local landTrack: AnimationTrack? = nil
local sneakStride = 1.67
local RUN_BLEND_FROM, RUN_BLEND_TO = 11, 15 -- ground speeds where walk blends into run

local speed = 0 -- current ground speed (studs/s)
local strafeDir = Vector3.zero -- smoothed move direction while aiming

local function angleDiff(a: number, b: number): number
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function useRthro(char: Model)
	local animate = char:WaitForChild("Animate", 10)
	if not animate then
		return
	end
	local walk = animate:FindFirstChild("walk")
	local run = animate:FindFirstChild("run")
	local w = walk and walk:FindFirstChildOfClass("Animation")
	local r = run and run:FindFirstChildOfClass("Animation")
	if w then
		w.AnimationId = WALK_ANIM
	end
	if r then
		r.AnimationId = RUN_ANIM
		runStride = RUN_STRIDE
		local anims = ReplicatedStorage:FindFirstChild("Animations")
		local custom = anims and anims:FindFirstChild("Run")
		local clip = anims and anims:FindFirstChild("RunClip")
		if custom and custom:IsA("Animation") and custom.AnimationId ~= "" then
			r.AnimationId = custom.AnimationId
			runStride = (custom:GetAttribute("Stride") :: number?) or RUN_STRIDE
		elseif IS_STUDIO and clip and clip:IsA("KeyframeSequence") then
			r.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(clip)
			runStride = (clip:GetAttribute("Stride") :: number?) or RUN_STRIDE
		end
	end
end

-- custom animations: the published Animations.<slot> (Animation with an id), or in Studio playtests the
-- unpublished clip Animations.<slot>Clip
local function loadTrack(animator: Animator, slotName: string, priority: Enum.AnimationPriority, looped: boolean): (AnimationTrack?, number?)
	local anims = ReplicatedStorage:FindFirstChild("Animations")
	if not anims then
		return nil, nil
	end
	local slot = anims:FindFirstChild(slotName)
	local clip = anims:FindFirstChild(slotName .. "Clip")
	local id: string? = nil
	local stride: number? = nil
	if slot and slot:IsA("Animation") and slot.AnimationId ~= "" then
		id = slot.AnimationId
		stride = slot:GetAttribute("Stride") :: number?
	elseif IS_STUDIO and clip and clip:IsA("KeyframeSequence") then
		id = KeyframeSequenceProvider:RegisterKeyframeSequence(clip)
		stride = clip:GetAttribute("Stride") :: number?
	end
	if not id then
		return nil, nil
	end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local track = animator:LoadAnimation(a)
	track.Priority = priority
	track.Looped = looped
	return track, stride
end

local function loadSneak(char: Model)
	sneakTrack, sneakIdleTrack, jumpTrack, landTrack = nil, nil, nil, nil
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local animator = hum and hum:WaitForChild("Animator", 10) :: Animator?
	if not hum or not animator then
		return
	end
	-- sneaking sits above the walk/run (Movement) so it fully replaces the walk
	local stride
	sneakTrack, stride = loadTrack(animator, "Sneak", Enum.AnimationPriority.Action, true)
	sneakStride = stride or sneakStride
	sneakIdleTrack = loadTrack(animator, "SneakIdle", Enum.AnimationPriority.Action, true)
	-- jump/land sit above sneaking too
	jumpTrack = loadTrack(animator, "Jump", Enum.AnimationPriority.Action2, false)
	landTrack = loadTrack(animator, "Land", Enum.AnimationPriority.Action2, false)

	local h = hum :: Humanoid
	h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			if landTrack then
				landTrack:Stop(0.05)
			end
			local jt = jumpTrack
			if jt then
				-- time in the air for this jump, so the clip ends as the feet touch down
				local g = math.max(workspace.Gravity, 1)
				local v = h.UseJumpPower and h.JumpPower or math.sqrt(2 * g * h.JumpHeight)
				local air = math.max(2 * v / g, 0.2)
				local len = jt.Length > 0 and jt.Length or 0.55
				jt:Play(0.05)
				jt:AdjustSpeed(len / air)
			end
		elseif new == Enum.HumanoidStateType.Landed then
			local jt = jumpTrack
			if jt and jt.IsPlaying then
				jt:Stop(0.1)
			end
			if landTrack and jt then
				landTrack:Play(0.05)
				landTrack:AdjustSpeed(1.4)
			end
		end
	end)
end

ContextActionService:BindAction("Sneak", function(_, state)
	if state == Enum.UserInputState.Begin then
		sneaking = not sneaking
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl, Enum.KeyCode.ButtonB)
ContextActionService:SetTitle("Sneak", "SNEAK")

local function walkTracks(hum: Humanoid): { AnimationTrack }
	local out = {}
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in animator:GetPlayingAnimationTracks() do
			local n = string.lower(t.Name)
			if string.find(n, "walk") or string.find(n, "run") then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function step(dt: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hum or not root or hum.Health <= 0 or hum.Sit or hum.PlatformStand then
		return
	end
	hum.AutoRotate = false

	-- what the player is asking for this frame (the control module has just set it)
	local input = hum.MoveDirection
	local want = Vector3.new(input.X, 0, input.Z)
	local mag = math.min(want.Magnitude, 1)
	local wantDir = mag > 0.01 and want.Unit or Vector3.zero
	local _, cur, _ = root.CFrame:ToOrientation()

	local aimYaw = char:GetAttribute("AimYaw")
	local targetYaw = cur
	local rate = TURN_RATE
	-- AimYaw = which way to face (aiming, or first person); Aiming = actually aiming (slower).
	-- Sprint: Left Shift, not aiming, not holding the trigger (BlockSprint), and when the facing is
	-- locked (first person) only while moving mostly forward.
	local aiming = char:GetAttribute("Aiming") == true
	local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		and not aiming
		and char:GetAttribute("BlockSprint") ~= true
	if sprinting and typeof(aimYaw) == "number" and mag > 0.01 then
		sprinting = wantDir:Dot(Vector3.new(-math.sin(aimYaw), 0, -math.cos(aimYaw))) > 0.7
	end
	if sprinting then
		sneaking = false -- sprinting stands you back up
	end
	local maxSpeed = if sneaking then (aiming and math.min(AIM_SPEED, SNEAK_SPEED) or SNEAK_SPEED)
		elseif aiming then AIM_SPEED
		elseif sprinting then SPRINT_SPEED
		else WALK_SPEED
	char:SetAttribute("Sneaking", sneaking)
	hum.WalkSpeed = SPRINT_SPEED -- the cap; the actual speed is set through Move's magnitude below
	local targetSpeed = maxSpeed * mag
	local moveDir: Vector3

	if typeof(aimYaw) == "number" then
		-- aiming: face the aim, move in the input direction (smoothed)
		targetYaw = aimYaw
		rate = TURN_RATE_AIM
		strafeDir = strafeDir:Lerp(wantDir, math.min(1, dt * 8))
		moveDir = strafeDir.Magnitude > 0.01 and strafeDir.Unit or Vector3.zero
	else
		strafeDir = Vector3.zero
		if mag > 0.01 then
			targetYaw = math.atan2(-wantDir.X, -wantDir.Z)
		end
		rate = speed < 1 and TURN_RATE_IDLE or TURN_RATE
		-- slow down while the body is still turning toward a very different direction
		local off = math.abs(angleDiff(targetYaw, cur))
		if mag > 0.01 then
			targetSpeed *= math.clamp(math.cos(off), SHARP_TURN_SPEED, 1)
		end
		moveDir = Vector3.zero -- set from the new facing below
	end

	-- turn at a limited rate
	local d = angleDiff(targetYaw, cur)
	local newYaw = cur + math.clamp(d, -rate * dt, rate * dt)
	root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, newYaw, 0)
	if typeof(aimYaw) ~= "number" then
		moveDir = Vector3.new(-math.sin(newYaw), 0, -math.cos(newYaw)) -- always walk where we face
	end

	-- build up / bleed off speed
	if targetSpeed > speed then
		speed = math.min(targetSpeed, speed + ACCEL * dt)
	else
		speed = math.max(targetSpeed, speed - DECEL * dt)
	end
	if moveDir.Magnitude < 0.01 then
		speed = math.max(0, speed - DECEL * dt)
	end
	char:SetAttribute("Sprinting", sprinting and speed > WALK_SPEED + 1)
	local ws = math.max(hum.WalkSpeed, 0.01)
	hum:Move(moveDir * math.clamp(speed / ws, 0, 1), false)

	-- feet match the ground: blend walk/run and set their playback speed from the real ground speed.
	-- (Animate sets its own values on Running events; this runs every frame after and wins.)
	local v = root.AssemblyLinearVelocity
	local ground = Vector3.new(v.X, 0, v.Z).Magnitude
	if ground > 0.5 then
		local facing = Vector3.new(-math.sin(newYaw), 0, -math.cos(newYaw))
		local dir = ground > 0 and Vector3.new(v.X, 0, v.Z).Unit or facing
		local backwards = typeof(aimYaw) == "number" and dir:Dot(facing) < -0.3
		local sign = backwards and -1 or 1
		local runW = math.clamp((ground - RUN_BLEND_FROM) / (RUN_BLEND_TO - RUN_BLEND_FROM), 0, 1)
		if sneakTrack then
			sneakTrack:AdjustSpeed(sign * ground / sneakStride)
		end
		for _, t in walkTracks(hum) do
			-- above the avatar's own Core "mood" animation, which would otherwise half-hold the arms
			if t.Priority ~= Enum.AnimationPriority.Movement then
				t.Priority = Enum.AnimationPriority.Movement
			end
			local isRun = string.find(string.lower(t.Name), "run") ~= nil
			local stride = isRun and runStride or WALK_STRIDE
			if IS_STUDIO then -- live tuning in playtests: player attributes WalkStride / RunStride
				local o = player:GetAttribute(isRun and "RunStride" or "WalkStride")
				if typeof(o) == "number" and o > 0 then
					stride = o
				end
			end
			t:AdjustSpeed(sign * ground / stride)
			t:AdjustWeight(math.max(isRun and runW or (1 - runW), 0.001))
		end
	end

	-- sneaking: the sneak walk while moving, the crouched sneak idle while still
	local st, it = sneakTrack, sneakIdleTrack
	local moving = ground > 0.5
	if st then
		if sneaking and (moving or not it) then
			if not st.IsPlaying then
				st:Play(0.3)
			end
			if not moving then
				st:AdjustSpeed(0) -- no idle clip: hold the crouch
			end
		elseif st.IsPlaying then
			st:Stop(0.3)
		end
	end
	if it then
		if sneaking and not moving then
			if not it.IsPlaying then
				it:Play(0.3)
			end
		elseif it.IsPlaying then
			it:Stop(0.3)
		end
	end
end

-- right after the control module reads the keys/stick (Input priority) and before the camera
RunService:BindToRenderStep("HeavyMovement", Enum.RenderPriority.Input.Value + 1, step)

player.CharacterAdded:Connect(function(char)
	speed = 0
	strafeDir = Vector3.zero
	sneaking = false
	useRthro(char)
	loadSneak(char)
end)
if player.Character then
	task.spawn(useRthro, player.Character)
	task.spawn(loadSneak, player.Character)
end
