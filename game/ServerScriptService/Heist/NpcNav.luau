--!strict
-- Walking for NPCs: pathfinding with an abort callback, so a routine can be cut short the instant the
-- NPC gets scared, tied up, or told to do something else. Shared by NpcLife, NpcCombat and the manager.
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local Nav = {}

local AGENT = { AgentRadius = 1.9, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 5 }

-- walk to `dest`. opts: speed (WalkSpeed), abort() -> true to stop, timeout seconds (default 25),
-- arrive distance (default 3). Returns true if it got there.
function Nav.walk(hum: Humanoid, root: BasePart, dest: Vector3, opts: { speed: number?, abort: (() -> boolean)?, timeout: number?, arrive: number?, maxLen: number? }?): boolean
	local o = opts or {}
	local abort = o.abort
	local arrive = o.arrive or 3
	local deadline = os.clock() + (o.timeout or 25)
	if o.speed then
		hum.WalkSpeed = o.speed
	end
	local path = PathfindingService:CreatePath(AGENT)
	local ok = pcall(function()
		path:ComputeAsync(root.Position, dest)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end
	local wps = path:GetWaypoints()
	if o.maxLen then
		local len = 0
		for i = 2, #wps do
			len += (wps[i].Position - wps[i - 1].Position).Magnitude
		end
		if len > o.maxLen then
			return false -- the way round is much longer than the straight line: not worth it
		end
	end
	for i = 2, #wps do
		local wp = wps[i]
		hum:MoveTo(wp.Position)
		local stuckSince = os.clock()
		local lastPos = root.Position
		while true do
			if (abort and abort()) or hum.Health <= 0 or not root.Parent then
				hum:MoveTo(root.Position)
				return false
			end
			local flat = (root.Position - wp.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude < (if i == #wps then arrive else 2.4) then
				break
			end
			if os.clock() > deadline then
				hum:MoveTo(root.Position)
				return false
			end
			if (root.Position - lastPos).Magnitude > 0.6 then
				lastPos = root.Position
				stuckSince = os.clock()
			elseif os.clock() - stuckSince > 2.5 then
				return false -- blocked
			end
			task.wait(0.1)
		end
	end
	return true
end

-- stop moving
function Nav.stop(hum: Humanoid, root: BasePart)
	hum:MoveTo(root.Position)
end

-- smoothly face a point (flat), call every step; returns true once facing it
function Nav.faceStep(root: BasePart, at: Vector3, dt: number, speed: number?): boolean
	local flat = (at - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then
		return true
	end
	local want = CFrame.lookAt(root.Position, root.Position + flat)
	local cur = root.CFrame
	local dot = cur.LookVector:Dot(want.LookVector)
	if dot > 0.995 then
		return true
	end
	root.CFrame = cur:Lerp(want, math.min(1, dt * (speed or 5)))
	return false
end

local _ = RunService
return Nav
