--!strict
-- Civilian NPCs that wander around the map.
--  * dressed as ordinary civilians: a random mix of free Roblox-made shirts, jeans and short hair, and
--    a random skin tone (HumanoidDescription)
--  * walk with the same Rthro walk as players, slower (WALK_SPEED); the walk's playback speed follows
--    their real ground speed so the feet don't slide. Idle animation when they stop.
--  * wander between random points (pathfinding, straight line if no path), pausing in between
--  * tagged "NPC" (CollectionService) in workspace.NPCs; the guns' damage kills them like players.
--    Dead ones are removed after a few seconds and a new one comes in.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local COUNT = 6 -- civilians alive at once
local CENTER = Vector3.new(0, 0, 0) -- they wander within RADIUS studs of here
local RADIUS = 55
local WALK_SPEED = 4.5 -- players walk at 8
local WALK_ANIM = "rbxassetid://2510202577" -- Rthro walk (the players' walk)
local WALK_STRIDE = 6.3 -- studs/s it covers at 1x playback (same value as HeavyMovement)
local IDLE_ANIM = "rbxassetid://507766388" -- default R15 idle
local PAUSE = NumberRange.new(1.5, 5) -- seconds standing still between walks
local REMOVE_AFTER = 5 -- seconds a dead civilian stays
local RESPAWN_AFTER = 6 -- seconds before a replacement walks in

-- free Roblox-made catalog items (AvatarEditorService:SearchCatalog, creator Roblox, price 0)
local SHIRTS = {
	144076436, -- Grey Striped Shirt with Denim Jacket
	382537702, -- Teal Shirt
	398635081, -- Blue Plaid Shirt
	144076358, -- Blue and Black Motorcycle Shirt
	398633584, -- Denim Jacket with White Hoodie
	382538295, -- Guitar Tee with Black Jacket
}
local PANTS = {
	382537569, -- Black Jeans
	398633812, -- Black Jeans with White Shoes
	144076760, -- Dark Green Jeans
	382538503, -- Black Jeans with Sneakers
	398634487, -- Beautiful You Jeans
}
local HAIR = {
	6993758617, -- Short and Sleek - Brown
	7193401217, -- Short Fringe - Black
	7193452166, -- Short Curls - Black
	9243992729, -- Short and Sleek - Black
	9243976603, -- Short Fringe - Brown
	7193419595, -- Side Part - Brown
	9244010432, -- Curly Fade - Brown
	7193437847, -- Medium Middle Part - Brown
}
local SKINS = {
	Color3.fromRGB(255, 220, 190),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 105, 75),
	Color3.fromRGB(110, 72, 50),
}

local rng = Random.new()
local folder = workspace:FindFirstChild("NPCs") or Instance.new("Folder")
folder.Name = "NPCs"
folder.Parent = workspace

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function describe(): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.Shirt = pick(SHIRTS)
	d.Pants = pick(PANTS)
	d.HairAccessory = tostring(pick(HAIR))
	local skin = pick(SKINS)
	d.HeadColor, d.TorsoColor = skin, skin
	d.LeftArmColor, d.RightArmColor, d.LeftLegColor, d.RightLegColor = skin, skin, skin, skin
	return d
end

local function randomPoint(): Vector3
	local a = rng:NextNumber() * math.pi * 2
	local r = math.sqrt(rng:NextNumber()) * RADIUS
	return CENTER + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- ground height below a point (nil = nothing there)
local function groundAt(p: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(p + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position or nil
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

-- walk to `goal`: along a path if one is found, else straight. Returns when there or stuck.
local function walkTo(hum: Humanoid, root: BasePart, goal: Vector3)
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)
	local points: { Vector3 } = {}
	if ok and path.Status == Enum.PathStatus.Success then
		for _, w in path:GetWaypoints() do
			table.insert(points, w.Position)
		end
	else
		points = { goal }
	end
	for _, p in points do
		if hum.Health <= 0 or not root.Parent then
			return
		end
		hum:MoveTo(p)
		local reached = false
		local conn = hum.MoveToFinished:Connect(function(r)
			reached = r
		end)
		local t0 = os.clock()
		while not reached and hum.Health > 0 and os.clock() - t0 < 8 do
			if (Vector3.new(p.X, root.Position.Y, p.Z) - root.Position).Magnitude < 1.2 then
				break
			end
			task.wait(0.1)
		end
		conn:Disconnect()
		if not reached and os.clock() - t0 >= 8 then
			return -- stuck: give up on this goal
		end
	end
end

local spawnOne: () -> ()

local function live(npc: Model, hum: Humanoid, root: BasePart)
	local walk = loadTrack(hum, WALK_ANIM, Enum.AnimationPriority.Movement)
	local idle = loadTrack(hum, IDLE_ANIM, Enum.AnimationPriority.Idle)
	idle:Play(0.3)
	-- feet match the ground: walk playback speed from the real ground speed
	local animConn = RunService.Heartbeat:Connect(function()
		if hum.Health <= 0 then
			return
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
		animConn:Disconnect()
		walk:Stop(0.1)
		idle:Stop(0.1)
		task.delay(REMOVE_AFTER, function()
			npc:Destroy()
		end)
		task.delay(RESPAWN_AFTER, spawnOne)
	end)
	task.spawn(function()
		while hum.Health > 0 and npc.Parent do
			task.wait(rng:NextNumber(PAUSE.Min, PAUSE.Max))
			if hum.Health <= 0 or not npc.Parent then
				break
			end
			local goal = groundAt(randomPoint(), { folder })
			if goal then
				walkTo(hum, root, goal)
			end
		end
	end)
end

spawnOne = function()
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(describe(), Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("[NPCService] could not build a civilian:", npc)
		return
	end
	local model = npc :: Model
	model.Name = "Civilian"
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	-- players' own animation script isn't needed: animations are played here, on the server
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	hum.WalkSpeed = WALK_SPEED
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local spot = groundAt(randomPoint(), { folder }) or CENTER
	model:PivotTo(CFrame.new(spot + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.1, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0))
	CollectionService:AddTag(model, "NPC")
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil) -- the server moves them: smooth for everyone
	end)
	live(model, hum, root)
end

for _ = 1, COUNT do
	task.spawn(spawnOne)
end
