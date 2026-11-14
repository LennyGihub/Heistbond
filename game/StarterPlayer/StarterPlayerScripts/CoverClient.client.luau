--!strict
-- Taking cover against walls.
--  * the cover key (physical Q key = "A" on an AZERTY keyboard, gamepad Y, a COVER button on touch)
--    near a wall puts the character's back against it; pressing it again leaves cover
--  * in cover, the left/right movement keys (Q/D on AZERTY, A/D on QWERTY) slide along the wall;
--    forward/back do nothing. The character stops at the end of the wall instead of walking off it
--  * the character looks toward the side it last moved to (or was going when it took cover)
--  * empty hands: palms pressed on the wall (CoverPose); with a gun the arms stay on the gun
--  * aiming (right mouse) leaves the cover pose to shoot; letting go goes back into cover if the wall
--    is still there. Jumping leaves cover.
-- HeavyMovement steps aside while the character attribute InCover is true (this script then moves
-- and turns the character). Other players see the pose through the replicated attribute CoverSide.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local CoverPose = require(ReplicatedStorage:WaitForChild("Cover"):WaitForChild("CoverPose") :: ModuleScript)
local CoverRemote = ReplicatedStorage:WaitForChild("Cover"):WaitForChild("CoverState") :: RemoteEvent

local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()
local UP = Vector3.yAxis

local FIND_RANGE = 4.5 -- how far (studs, from the body's centre) a wall can be to take cover
local COVER_SPEED = 5 -- sliding speed along the wall
local COVER_ACCEL = 30
local BACK_GAP = CoverPose.BACK_GAP -- gap between the back and the wall
local TURN_RATE = math.rad(540)
local SIDESTEP_LEN = 1.6 -- studs per sidestep cycle
local MAX_WALL_SLOPE = 0.35 -- |normal.Y| above this is a floor/ramp, not a wall
local REACH_PROBES = { 2.6, 2.2, 1.8, 1.5, 1.25, 1.0 } -- where to look for the end of the wall
local EDGE_STOP = 1.25 -- stop sliding when the wall ends this far to the side (shoulder at the corner)

-- local state
local inCover = false -- the player wants to be in cover (stays true while aiming out of it)
local suspended = false -- out of the pose for now (aiming)
local normal = Vector3.zAxis -- wall normal, pointing away from the wall
local side = 1 -- +1 = look to the character's right, -1 = left
local slide = 0 -- current speed along the wall (+ = toward the character's right)
local lostFor = 0
local airFor = 0
local lastSent: string? = nil

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-4 and f.Unit or Vector3.zero
end

local function rayParams(char: Model): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { char }
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(ignore, cam)
	end
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = true
	return p
end

-- distance from the root's centre to its back (the torso's half depth)
local function backDepth(char: Model): number
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso.Size.Z / 2
	end
	return 0.5
end

local function isWall(hit: RaycastResult?): boolean
	return hit ~= nil and math.abs(hit.Normal.Y) < MAX_WALL_SLOPE
end

-- nearest wall around the character that is at least chest high
local function findWall(char: Model, root: BasePart): (Vector3?, Vector3?)
	local params = rayParams(char)
	local origin = root.Position
	local best: RaycastResult? = nil
	local look = flat(root.CFrame.LookVector)
	for i = 0, 23 do
		local a = i * math.pi * 2 / 24
		local d = CFrame.fromAxisAngle(UP, a):VectorToWorldSpace(look)
		local hit = workspace:Raycast(origin, d * FIND_RANGE, params)
		if hit and isWall(hit) and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	if not best then
		return nil, nil
	end
	local n = flat(best.Normal)
	-- tall enough: the wall must also be there at chest height
	local chest = workspace:Raycast(origin + Vector3.new(0, 1.2, 0), -n * (FIND_RANGE + 1), params)
	if not isWall(chest) then
		return nil, nil
	end
	return n, best.Position
end

local function setLocalAttr(char: Model, on: boolean)
	if char:GetAttribute("InCover") ~= on then
		char:SetAttribute("InCover", on)
	end
end

local function send(on: boolean)
	local key = on and tostring(side) or "off"
	if key ~= lastSent then
		lastSent = key
		CoverRemote:FireServer(on, side)
	end
end

local function leave(why: string)
	if IS_STUDIO then
		player:SetAttribute("CoverLeft", why) -- test info: why the character left cover
	end
	inCover = false
	suspended = false
	slide = 0
	local char = player.Character
	if char then
		setLocalAttr(char, false)
	end
	send(false)
end

local function enter(char: Model, root: BasePart): boolean
	local n = findWall(char, root)
	if not n then
		return false
	end
	normal = n
	-- look the way the character was going: its velocity, else where it faced
	local right = normal:Cross(UP)
	local v = flat(root.AssemblyLinearVelocity)
	local ref = v.Magnitude > 0 and v or flat(root.CFrame.LookVector)
	local d = ref:Dot(right)
	if math.abs(d) > 0.1 then
		side = d > 0 and 1 or -1
	end
	inCover = true
	suspended = false
	slide = 0
	lostFor = 0
	airFor = 0
	setLocalAttr(char, true)
	send(true)
	return true
end

local function toggle()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then
		return
	end
	if IS_STUDIO then
		player:SetAttribute("CoverLeft", "toggle in=" .. tostring(inCover) .. " susp=" .. tostring(suspended))
	end
	if inCover then
		leave("key")
	else
		enter(char, root)
	end
end

ContextActionService:BindAction("Cover", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("Cover", "COVER")

-- movement in cover, right after the control module has read the keys (same slot as HeavyMovement)
local function step(dt: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not inCover then
		return
	end
	if not char or not hum or not root or hum.Health <= 0 or hum.Sit or hum.PlatformStand then
		leave("dead")
		return
	end
	-- jumping leaves cover; so does falling for a moment (walked off a ledge)
	local st = hum:GetState()
	airFor = if st == Enum.HumanoidStateType.Freefall then airFor + dt else 0
	if hum.Jump or st == Enum.HumanoidStateType.Jumping or airFor > 0.3 then
		leave("jump")
		return
	end

	-- aiming: step out of cover to shoot, come back when the aim is released
	local aiming = char:GetAttribute("Aiming") == true
	if aiming and not suspended then
		suspended = true
		setLocalAttr(char, false)
		send(false)
	elseif not aiming and suspended then
		local n = findWall(char, root)
		if not n then
			leave("nowall-after-aim")
			return
		end
		normal = n
		suspended = false
		slide = 0
		setLocalAttr(char, true)
		send(true)
	end
	if suspended then
		return
	end

	local params = rayParams(char)
	local pos = root.Position
	local hit = workspace:Raycast(pos, -normal * (FIND_RANGE + 0.5), params)
	if not isWall(hit) then
		lostFor += dt
		if lostFor > 0.25 then
			leave("lost-wall")
		end
		return
	end
	lostFor = 0
	local h = hit :: RaycastResult
	-- follow gently curved walls; corners sharper than ~60 degrees end the slide (edge check below)
	local n = flat(h.Normal)
	if n:Dot(normal) > 0.5 then
		normal = flat(normal:Lerp(n, math.min(1, dt * 10)))
	end
	local right = normal:Cross(UP)
	local dist = (pos - h.Position):Dot(normal)

	-- left/right input along the wall (camera-relative, so the key that points that way on screen)
	local input = hum.MoveDirection
	local along = input:Dot(right)
	if IS_STUDIO then
		local t = player:GetAttribute("CoverAlong") -- test hook: -1..1 fake input along the wall
		if typeof(t) == "number" then
			along = t
		end
	end
	local want = 0
	if math.abs(along) > 0.3 then
		local dir = along > 0 and 1 or -1
		side = dir -- look the way you last moved
		-- end of the wall: is there still wall a bit further along?
		local probe = pos + right * dir * EDGE_STOP
		local ahead = workspace:Raycast(probe, -normal * (dist + 1.2), params)
		if isWall(ahead) then
			want = dir * COVER_SPEED * math.min(1, math.abs(along))
		end
	end
	if want > slide then
		slide = math.min(want, slide + COVER_ACCEL * dt)
	else
		slide = math.max(want, slide - COVER_ACCEL * dt)
	end

	-- stay pressed against the wall
	local err = dist - (backDepth(char) + BACK_GAP)
	local push = math.clamp(-err * 10, -8, 8)
	local vel = right * slide + normal * push
	hum.WalkSpeed = 15
	hum:Move(vel / hum.WalkSpeed, false)

	-- back to the wall: face away from it
	local _, cur, _ = root.CFrame:ToOrientation()
	local target = math.atan2(-normal.X, -normal.Z)
	local d = (target - cur + math.pi) % (2 * math.pi) - math.pi
	local yaw = cur + math.clamp(d, -TURN_RATE * dt, TURN_RATE * dt)
	root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)

	send(true)
end
RunService:BindToRenderStep("CoverMove", Enum.RenderPriority.Input.Value + 1, step)

-- pose of every character in cover (after the animations, before physics)
type PoseState = CoverPose.State
local poses: { [Model]: PoseState } = setmetatable({}, { __mode = "k" }) :: any

RunService.Stepped:Connect(function(_, dt)
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not char or not root then
			continue
		end
		local on: boolean, wantSide: number
		if pl == player then
			on, wantSide = inCover and not suspended, side
		else
			local s = char:GetAttribute("CoverSide")
			on = typeof(s) == "number" and s ~= 0
			wantSide = if on then s :: number else 0
		end
		local ps = poses[char]
		if not ps then
			if not on then
				continue
			end
			ps = { alpha = 0, side = wantSide, phase = 0, step = 0, armed = false } :: PoseState
			poses[char] = ps
		end
		local p = ps :: PoseState
		p.alpha += ((on and 1 or 0) - p.alpha) * math.min(1, dt * 10)
		if on then
			p.side += (wantSide - p.side) * math.min(1, dt * 8)
		end
		-- sidestep from the real sliding speed (works the same for other players)
		local v = root.AssemblyLinearVelocity
		local sideways = math.abs(v:Dot(root.CFrame.RightVector))
		p.phase = (p.phase + sideways * dt / SIDESTEP_LEN * math.pi * 2) % (math.pi * 2)
		p.step += (math.clamp(sideways / COVER_SPEED, 0, 1) - p.step) * math.min(1, dt * 10)
		p.armed = char:FindFirstChildOfClass("Tool") ~= nil
		-- where the wall really is behind the back (the twisted shoulders can keep the body off it)
		local back = flat(root.CFrame.LookVector)
		local wallHit = workspace:Raycast(root.Position, -back * 2.5, rayParams(char))
		p.wall = if wallHit then wallHit.Distance else nil
		-- how far the wall reaches on the look side, at hand height (the lead hand stays on it)
		p.reach = nil
		if wallHit then
			local params = rayParams(char)
			local lookDir = root.CFrame.RightVector * (p.side >= 0 and 1 or -1)
			local depth = wallHit.Distance + 0.6
			for _, d in REACH_PROBES do
				local o = root.Position + lookDir * d + Vector3.new(0, 0.5, 0)
				if workspace:Raycast(o, -back * depth, params) then
					p.reach = if d == REACH_PROBES[1] then nil else d
					break
				end
				p.reach = d
			end
		end
		if p.alpha < 0.002 and not on then
			poses[char] = nil
			continue
		end
		CoverPose.apply(char, p)
	end
end)

-- Studio-only test hooks (player attributes): CoverCmd "toggle" presses the cover key;
-- CoverCam (Vector3, character space) films the character from that point
if IS_STUDIO then
	player:GetAttributeChangedSignal("CoverCmd"):Connect(function()
		if player:GetAttribute("CoverCmd") == "toggle" then
			player:SetAttribute("CoverCmd", nil)
			toggle()
		end
	end)
	RunService:BindToRenderStep("CoverTestCam", Enum.RenderPriority.Camera.Value + 5, function()
		local v = player:GetAttribute("CoverCam")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if typeof(v) == "Vector3" and root then
			workspace.CurrentCamera.CFrame = CFrame.lookAt(root.CFrame:PointToWorldSpace(v), root.Position + Vector3.new(0, 0.6, 0))
		end
	end)
end

player.CharacterAdded:Connect(function()
	inCover, suspended, slide = false, false, 0
	lastSent = nil
end)
