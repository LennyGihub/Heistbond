--!strict
-- Taking cover against walls.
--  * the cover key (physical Q key = "A" on an AZERTY keyboard, gamepad Y, a COVER button on touch)
--    near a wall puts the character's back against it; pressing it again leaves cover
--  * in cover, the left/right movement keys (Q/D on AZERTY, A/D on QWERTY) slide along the wall;
--    forward/back do nothing. The character stops at the end of the wall instead of walking off it
--  * the character looks toward the side it last moved to (or was going when it took cover)
--  * low walls (from about knee to chest high): the character turns side-on with its shoulder to the
--    wall, bent forward so its head stays under the top; still it kneels, moving it walks crouched
--    (left/right turns it around). The camera rises a little so the screen centre (the crosshair) is
--    above the wall. Firing without aiming = blind fire: the gun is held up over the wall (character
--    attribute GunLift, read by GunClient) while the body stays down
--  * empty hands: palms pressed on the wall (CoverPose); with a gun the arms stay on the gun
--  * aiming (right mouse) leaves the cover pose to shoot (behind a low wall: stand up and shoot over
--    it); letting go goes back into cover if the wall is still there. Jumping leaves cover.
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
local COVER_SPEED = 4.5 -- sliding speed along the wall
local COVER_SPEED_LOW = 3.2 -- crouched behind a low wall
local WALL_RAY_H = 1.5 -- wall rays run this high above the ground (hits low walls and tall ones)
local MIN_LOW = 2.2 -- a wall lower than this (studs above the ground) is too low to hide behind
local TALL_H = 4.6 -- a wall at least this high is a tall wall (stand); lower = low wall (crouch)
local LOW_CAM_ABOVE = 1.4 -- behind a low wall the camera looks from this high above the wall's top
local BLIND_HOLD = 0.6 -- blind fire keeps the gun up this long after the trigger is released
local MUZZLE_ABOVE = 0.5 -- blind fire: the muzzle goes this far above the wall's top
local COVER_ACCEL = 30
local BACK_GAP = CoverPose.BACK_GAP -- gap between the back and the wall
local TURN_RATE = math.rad(540)
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
local lowTop: number? = nil -- world height of the low wall's top, nil = tall wall
local blindUntil = 0 -- blind firing until this time (os.clock)
local blinding = false
local gunLift = 0
local touchDist: number? = nil -- root-to-wall distance where the body touches the wall
local blockedFor = 0
local lastDist: number? = nil
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

-- low wall, side-on: distance from the root's centre to the outside of the arm on the wall side
local function sideDepth(char: Model): number
	local torso = char:FindFirstChild("UpperTorso") :: BasePart?
	local arm = char:FindFirstChild("RightUpperArm") :: BasePart?
	return (torso and torso.Size.X / 2 or 1) + (arm and arm.Size.X or 1) + 0.05
end

local function isWall(hit: RaycastResult?): boolean
	return hit ~= nil and math.abs(hit.Normal.Y) < MAX_WALL_SLOPE
end

-- height of the ground under the character (feet level)
local function groundY(char: Model, root: BasePart): number
	local hum = char:FindFirstChildOfClass("Humanoid")
	return root.Position.Y - ((hum and hum.HipHeight or 2) + root.Size.Y / 2)
end

-- where the wall rays start: the root's spot at WALL_RAY_H above the ground
local function rayOrigin(char: Model, root: BasePart): Vector3
	local p = root.Position
	return Vector3.new(p.X, groundY(char, root) + WALL_RAY_H, p.Z)
end

-- top of the wall hit at `at` (normal `n`): world height if it is a low wall, nil if it is tall
local function wallTop(params: RaycastParams, at: Vector3, n: Vector3, ground: number): number?
	local from = Vector3.new(at.X, ground + TALL_H + 0.5, at.Z) - n * 0.15
	local hit = workspace:Raycast(from, Vector3.new(0, -(TALL_H + 0.5 - WALL_RAY_H + 0.2), 0), params)
	if hit and hit.Normal.Y > 0.5 and hit.Position.Y < ground + TALL_H then
		return hit.Position.Y
	end
	return nil -- nothing above TALL_H... or we started inside a taller wall
end

-- nearest wall around the character that is high enough to hide behind:
-- returns its normal and (low wall) its top's height, or nil
local function findWall(char: Model, root: BasePart): (Vector3?, number?)
	local params = rayParams(char)
	local origin = rayOrigin(char, root)
	local ground = groundY(char, root)
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
	local b = best :: RaycastResult
	local n = flat(b.Normal)
	local top = wallTop(params, b.Position, n, ground)
	if top and top - ground < MIN_LOW then
		return nil, nil -- too low to hide behind
	end
	return n, top
end

local function setLocalAttr(char: Model, on: boolean)
	if char:GetAttribute("InCover") ~= on then
		char:SetAttribute("InCover", on)
	end
end

local function send(on: boolean)
	local key = if on then string.format("%d%s%s", side, tostring(lowTop ~= nil), tostring(blinding)) else "off"
	if key ~= lastSent then
		lastSent = key
		CoverRemote:FireServer(on, side, lowTop ~= nil, blinding)
	end
end

local function leave(why: string)
	if IS_STUDIO then
		player:SetAttribute("CoverLeft", why) -- test info: why the character left cover
	end
	inCover = false
	suspended = false
	slide = 0
	blinding, blindUntil, gunLift = false, 0, 0
	local char = player.Character
	if char then
		setLocalAttr(char, false)
		char:SetAttribute("GunLift", nil)
	end
	send(false)
end

local function enter(char: Model, root: BasePart): boolean
	local n, top = findWall(char, root)
	if not n then
		return false
	end
	normal = n
	lowTop = top
	touchDist, blockedFor, lastDist = nil, 0, nil
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
		blinding, blindUntil, gunLift = false, 0, 0
		char:SetAttribute("GunLift", nil)
		setLocalAttr(char, false)
		send(false)
	elseif not aiming and suspended then
		local n, top = findWall(char, root)
		if not n then
			leave("nowall-after-aim")
			return
		end
		normal = n
		lowTop = top
		touchDist, blockedFor, lastDist = nil, 0, nil
		suspended = false
		slide = 0
		setLocalAttr(char, true)
		send(true)
	end
	if suspended then
		return
	end

	local params = rayParams(char)
	local pos = rayOrigin(char, root)
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
	-- a low wall or a tall one here? (it can change while sliding along)
	local ground = groundY(char, root)
	local top = wallTop(params, h.Position, n, ground)
	if top and top - ground < MIN_LOW then
		lostFor += dt -- slid along to a part too low to hide behind
		if lostFor > 0.25 then
			leave("too-low")
		end
		return
	end
	lowTop = top

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
			want = dir * (lowTop and COVER_SPEED_LOW or COVER_SPEED) * math.min(1, math.abs(along))
		end
	end
	if want > slide then
		slide = math.min(want, slide + COVER_ACCEL * dt)
	else
		slide = math.max(want, slide - COVER_ACCEL * dt)
	end

	-- get the back to the wall, then stop pushing: the turned shoulders often touch it before the root
	-- reaches its ideal spot, and pushing on into that contact makes the body skid sideways. So once
	-- the body stops getting closer while pushing, that distance becomes the target.
	local ideal = if lowTop then sideDepth(char) else backDepth(char) + BACK_GAP
	if touchDist and dist < (touchDist :: number) - 0.05 then
		touchDist = math.max(dist, ideal) -- got closer (the wall changed): keep the closer spot
	end
	local err = dist - (touchDist or ideal)
	local push = 0
	if err > 0.06 then
		push = -math.min(err * 10, 8)
		-- real approach speed from the distance itself (the reported velocity keeps showing the push)
		local approach = if lastDist then ((lastDist :: number) - dist) / math.max(dt, 1e-3) else 1
		blockedFor = if approach < 0.3 then blockedFor + dt else 0
		if blockedFor > 0.2 then
			touchDist, blockedFor = dist, 0
		end
	else
		blockedFor = 0
	end
	lastDist = dist
	local vel = right * slide + normal * push
	hum.WalkSpeed = 15
	hum:Move(vel / hum.WalkSpeed, false)

	-- tall wall: back to it, face away from it. Low wall: side-on, facing along it toward `side`
	local _, cur, _ = root.CFrame:ToOrientation()
	local face = if lowTop then right * side else normal
	local target = math.atan2(-face.X, -face.Z)
	local d = (target - cur + math.pi) % (2 * math.pi) - math.pi
	local yaw = cur + math.clamp(d, -TURN_RATE * dt, TURN_RATE * dt)
	root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)

	-- blind fire: behind a low wall with a gun, the trigger (GunClient's BlockSprint) without aiming
	-- holds the gun up over the wall
	local armed = char:FindFirstChildOfClass("Tool") ~= nil
	local trigger = char:GetAttribute("BlockSprint") == true
		or (IS_STUDIO and player:GetAttribute("CoverBlindTest") == true) -- test hook: hold the trigger
	if lowTop and armed and trigger then
		blindUntil = os.clock() + BLIND_HOLD
	end
	blinding = lowTop ~= nil and armed and os.clock() < blindUntil
	-- raise the gun until its muzzle is MUZZLE_ABOVE over the wall's top (measured, so it works
	-- whatever pose the gun is in)
	local tool = char:FindFirstChildOfClass("Tool")
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle") :: Attachment?
	local wantLift = 0
	if blinding and lowTop and muzzle then
		wantLift = math.clamp(gunLift + (lowTop :: number) + MUZZLE_ABOVE - muzzle.WorldPosition.Y, 0, 3)
	end
	gunLift += (wantLift - gunLift) * math.min(1, dt * 10)
	char:SetAttribute("GunLift", if gunLift > 0.01 then gunLift else nil)

	send(true)
end
RunService:BindToRenderStep("CoverMove", Enum.RenderPriority.Input.Value + 1, step)

-- behind a low wall the camera rises a little, so the screen centre (crosshair) is above the wall
local camDrop = 0
RunService:BindToRenderStep("CoverCamera", Enum.RenderPriority.Camera.Value - 1, function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local want = 0
	if inCover and not suspended and lowTop and root then
		want = math.clamp((lowTop :: number) + LOW_CAM_ABOVE - (root.Position.Y + 1.5), 0, 2.5)
	end
	if want == 0 and camDrop == 0 then
		return
	end
	camDrop += (want - camDrop) * math.min(1, dt * 8)
	if math.abs(camDrop - want) < 0.01 then
		camDrop = want
	end
	hum.CameraOffset = Vector3.new(hum.CameraOffset.X, camDrop, hum.CameraOffset.Z)
end)

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
		-- CoverSide: 0 = not in cover, +-1 = tall wall, +-2 = low wall (sign = look side)
		local on: boolean, wantSide: number, isLow: boolean, blind: boolean
		if pl == player then
			on, wantSide, isLow, blind = inCover and not suspended, side, lowTop ~= nil, blinding
		else
			local s = char:GetAttribute("CoverSide")
			on = typeof(s) == "number" and s ~= 0
			wantSide = if on then math.sign(s :: number) else 0
			isLow = on and math.abs(s :: number) > 1.5
			blind = char:GetAttribute("CoverBlind") == true
		end
		local ps = poses[char]
		if not ps then
			if not on then
				continue
			end
			ps = { alpha = 0, side = wantSide, phase = 0, step = 0, armed = false, low = 0 } :: PoseState
			poses[char] = ps
		end
		local p = ps :: PoseState
		p.alpha += ((on and 1 or 0) - p.alpha) * math.min(1, dt * 10)
		if on then
			p.side += (wantSide - p.side) * math.min(1, dt * 8)
		end
		p.armed = char:FindFirstChildOfClass("Tool") ~= nil
		p.blind = (p.blind or 0) + ((blind and 1 or 0) - (p.blind or 0)) * math.min(1, dt * 12)
		local params = rayParams(char)
		-- where the wall really is (tall: behind the back - the twisted shoulders can keep the body off
		-- it; low: beside the body, on the look side) and how high a low wall is
		local back = flat(root.CFrame.LookVector)
		local wallDir = if isLow then root.CFrame.RightVector * (wantSide >= 0 and 1 or -1) else -back
		local ground = groundY(char, root)
		local origin = rayOrigin(char, root)
		local wallHit = workspace:Raycast(origin, wallDir * 3, params)
		p.wall = if wallHit and not isLow then wallHit.Distance else nil
		if wallHit and isLow then
			p.top = wallTop(params, wallHit.Position, -wallDir, ground) or p.top
		elseif not isLow then
			p.top = nil
		end
		p.low += ((on and isLow) and 1 - p.low or -p.low) * math.min(1, dt * 8)
		-- step cycle from the real ground speed (works the same for other players)
		local v = root.AssemblyLinearVelocity
		local moving = Vector3.new(v.X, 0, v.Z).Magnitude
		local speed = COVER_SPEED + (COVER_SPEED_LOW - COVER_SPEED) * p.low
		p.phase = (p.phase + moving * dt / CoverPose.stepLen(p.low) * math.pi * 2) % (math.pi * 2)
		p.step += (math.clamp(moving / speed, 0, 1) - p.step) * math.min(1, dt * 10)
		-- how far the wall reaches on the look side, at hand height (the lead hand stays on it)
		p.reach = nil
		if wallHit and not isLow then
			local lookDir = root.CFrame.RightVector * (p.side >= 0 and 1 or -1)
			local depth = wallHit.Distance + 0.6
			local y = if p.top then math.min(root.Position.Y + 0.5, p.top - 0.5) else root.Position.Y + 0.5
			for _, d in REACH_PROBES do
				local o = Vector3.new(root.Position.X, y, root.Position.Z) + lookDir * d
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
	lowTop, camDrop = nil, 0
	blinding, blindUntil, gunLift = false, 0, 0
	lastSent = nil
end)
