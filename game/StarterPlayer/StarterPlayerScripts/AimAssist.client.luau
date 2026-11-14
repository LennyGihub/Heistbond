--!strict
-- Aim assist: when you start aiming (GunClient sets the character attribute Aiming), the crosshair
-- locks onto the head of the NPC (CollectionService tag "NPC") nearest the screen centre - within
-- LOCK_ANGLE of where you look, in range and in sight - and follows it while you keep aiming.
-- It lets go when you stop aiming, the target dies, or it stays out of sight for a moment.
-- Works by turning the camera (right after the camera scripts, before GunClient adds its shoulder
-- offset and recoil); the screen centre is the crosshair.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()

local LOCK_ANGLE = math.rad(25) -- only heads this close to where you look can be grabbed
local RANGE = 180 -- studs
local SNAP_RATE = 18 -- how fast the camera swings onto the head (higher = snappier)
local LOST_AFTER = 0.5 -- seconds out of sight before letting go

local target: Model? = nil
local wasAiming = false
local lostFor = 0
local finalCamPos: Vector3? = nil -- where the camera really ended up last frame (after the offsets)

local function headOf(m: Model): BasePart?
	local hum = m:FindFirstChildOfClass("Humanoid")
	local head = m:FindFirstChild("Head")
	if hum and hum.Health > 0 and head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function visible(from: Vector3, head: BasePart, model: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local fx = workspace:FindFirstChild("WeaponFx")
	if fx then
		table.insert(ignore, fx)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(from, head.Position - from, params)
	return hit == nil or hit.Instance:IsDescendantOf(model)
end

local function acquire(cam: Camera): Model?
	local from = finalCamPos or cam.CFrame.Position
	local look = cam.CFrame.LookVector
	local best: Model? = nil
	local bestAngle = LOCK_ANGLE
	for _, m in CollectionService:GetTagged("NPC") do
		if m:IsA("Model") then
			local head = headOf(m)
			if head then
				local to = head.Position - from
				if to.Magnitude < RANGE then
					local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
					if ang < bestAngle and visible(from, head, m) then
						best, bestAngle = m, ang
					end
				end
			end
		end
	end
	return best
end

RunService:BindToRenderStep("AimAssist", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local char = player.Character
	local cam = workspace.CurrentCamera
	if not char or not cam then
		return
	end
	local aiming = char:GetAttribute("Aiming") == true and char:FindFirstChildOfClass("Tool") ~= nil
	if aiming and not wasAiming then
		target = acquire(cam)
		lostFor = 0
		if IS_STUDIO then
			player:SetAttribute("AimAssistInfo", if target then "acquired" else "none in reach")
		end
	elseif not aiming then
		target = nil
	end
	wasAiming = aiming
	local t = target
	if not t then
		return
	end
	local head = headOf(t)
	if not head or not t.Parent then
		target = nil
		return
	end
	local from = finalCamPos or cam.CFrame.Position
	if visible(from, head, t) then
		lostFor = 0
	else
		lostFor += dt
		if lostFor > LOST_AFTER then
			target = nil
			return
		end
	end
	-- turn the camera so the crosshair (screen centre, from where the camera really ends up) sits on the head
	local want = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + (head.Position - from).Unit)
	local a = math.min(1, dt * SNAP_RATE)
	cam.CFrame = cam.CFrame:Lerp(want, a)
	if IS_STUDIO then -- test info: what is locked and how far off the crosshair still is (degrees)
		local off = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot((head.Position - from).Unit), -1, 1)))
		player:SetAttribute("AimAssistInfo", string.format("%s %.2f", t.Name, off))
	end
end)

-- remember where the camera ends up once every script has moved it
RunService:BindToRenderStep("AimAssistRecord", Enum.RenderPriority.Camera.Value + 6, function()
	local cam = workspace.CurrentCamera
	if cam then
		finalCamPos = cam.CFrame.Position
	end
end)

player.CharacterAdded:Connect(function()
	target, wasAiming = nil, false
end)
