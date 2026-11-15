--!strict
-- Shared by NPCService (civilians) and GuardService (security guards): building an R15 NPC from a
-- HumanoidDescription, the walk/idle animations (the players' Rthro walk, its playback speed following
-- the real ground speed so the feet don't slide), and a ground check.
-- Every NPC lives in workspace.NPCs and is tagged "NPC" (AimAssist, cover rays use these).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local NPCCommon = {}

NPCCommon.WALK_SPEED = 4.5 -- players walk at 8
local WALK_ANIM = "rbxassetid://2510202577" -- Rthro walk (the players' walk)
local WALK_STRIDE = 6.3 -- studs/s it covers at 1x playback (same value as HeavyMovement)
local IDLE_ANIM = "rbxassetid://507766388" -- default R15 idle

local folder = workspace:FindFirstChild("NPCs") or Instance.new("Folder")
folder.Name = "NPCs"
folder.Parent = workspace
NPCCommon.folder = folder

-- ground point below `p` (ignoring NPCs), or nil
function NPCCommon.groundAt(p: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(p + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position or nil
end

-- a new NPC from a description, standing at `spot` (ground point) facing `yaw`, in workspace.NPCs
function NPCCommon.build(desc: HumanoidDescription, name: string, spot: Vector3, yaw: number): (Model?, Humanoid?, BasePart?)
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("[NPC] could not build", name, npc)
		return nil, nil, nil
	end
	local model = npc :: Model
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local animate = model:FindFirstChild("Animate") -- animations are played by the server here
	if animate then
		animate:Destroy()
	end
	hum.WalkSpeed = NPCCommon.WALK_SPEED
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:PivotTo(CFrame.new(spot + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.1, 0)) * CFrame.Angles(0, yaw, 0))
	CollectionService:AddTag(model, "NPC")
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil) -- the server moves them: smooth for everyone
	end)
	return model, hum, root
end

local function loadTrack(hum: Humanoid, id: string, priority: Enum.AnimationPriority): AnimationTrack
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local a = Instance.new("Animation")
	a.AnimationId = id
	local t = (animator :: Animator):LoadAnimation(a)
	t.Priority = priority
	t.Looped = true
	return t
end

-- walk while moving (speed matched to the ground speed), idle while still; stops on death
function NPCCommon.animate(hum: Humanoid, root: BasePart)
	local walk = loadTrack(hum, WALK_ANIM, Enum.AnimationPriority.Movement)
	local idle = loadTrack(hum, IDLE_ANIM, Enum.AnimationPriority.Idle)
	idle:Play(0.3)
	local model = hum.Parent
	local conn = RunService.Heartbeat:Connect(function()
		-- a posed NPC (hostage on its knees, crouched behind cover, hands up) has its joints set by the
		-- script: the idle animation would be composed on top of that and spoil the pose
		if model and model:GetAttribute("NoAnim") then
			if idle.IsPlaying then
				idle:Stop(0.1)
			end
			if walk.IsPlaying then
				walk:Stop(0.1)
			end
			return
		end
		if not idle.IsPlaying then
			idle:Play(0.3)
		end
		local v = root.AssemblyLinearVelocity
		local ground = Vector3.new(v.X, 0, v.Z).Magnitude
		if ground > 0.4 then
			if not walk.IsPlaying then
				walk:Play(0.25)
			end
			walk:AdjustSpeed(ground / WALK_STRIDE)
		elseif walk.IsPlaying then
			walk:Stop(0.3)
		end
	end)
	hum.Died:Connect(function()
		conn:Disconnect()
		walk:Stop(0.1)
		idle:Stop(0.1)
	end)
end

-- remove the body a while after death, and call `respawn` a while after that
function NPCCommon.onDeath(model: Model, hum: Humanoid, removeAfter: number, respawnAfter: number, respawn: () -> ())
	hum.Died:Connect(function()
		task.delay(removeAfter, function()
			model:Destroy()
		end)
		task.delay(respawnAfter, respawn)
	end)
end

return NPCCommon
