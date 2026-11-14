--!strict
-- Heavier, more realistic movement for the local character:
--  * speed builds up and dies down instead of starting/stopping instantly
--  * the body turns at a limited rate instead of snapping
--  * not aiming: the character only ever moves the way it faces, so the walk cycle never slides
--  * aiming (character attribute AimYaw, set by GunClient): face the aim, strafe freely; walking
--    backwards plays the walk cycle in reverse instead of moonwalking
--  * Rthro walk/run animations whose playback speed is set from the real ground speed every frame,
--    so the feet never slide; Left Shift sprints
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
local SPRINT_SPEED = 17 -- hold Left Shift
local AIM_SPEED = 6 -- while aiming

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
	local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and typeof(aimYaw) ~= "number"
	local maxSpeed = if typeof(aimYaw) == "number" then AIM_SPEED elseif sprinting then SPRINT_SPEED else WALK_SPEED
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
		for _, t in walkTracks(hum) do
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
end

-- right after the control module reads the keys/stick (Input priority) and before the camera
RunService:BindToRenderStep("HeavyMovement", Enum.RenderPriority.Input.Value + 1, step)

player.CharacterAdded:Connect(function(char)
	speed = 0
	strafeDir = Vector3.zero
	useRthro(char)
end)
if player.Character then
	task.spawn(useRthro, player.Character)
end
