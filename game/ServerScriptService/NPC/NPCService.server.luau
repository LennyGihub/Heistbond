--!strict
-- Civilian NPCs that wander around the map (security guards: GuardService).
--  * dressed as ordinary civilians: a random mix of free Roblox-made shirts, jeans and short hair, and
--    a random skin tone (HumanoidDescription)
--  * walk with the players' Rthro walk, slower (NPCCommon)
--  * wander between random points (pathfinding, straight line if no path), pausing in between
--  * the guns' damage kills them like players; dead ones are removed after a few seconds and a new one
--    comes in.
local PathfindingService = game:GetService("PathfindingService")
local NPCCommon = require(script.Parent:WaitForChild("NPCCommon"))

local COUNT = 4 -- civilians alive at once
local CENTER = Vector3.new(0, 0, 0) -- they wander within RADIUS studs of here
local RADIUS = 55
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

local function spawnOne()
	local spot = NPCCommon.groundAt(randomPoint()) or CENTER
	local model, hum, root = NPCCommon.build(describe(), "Civilian", spot, rng:NextNumber() * math.pi * 2)
	if not model or not hum or not root then
		return
	end
	local m, h, r = model :: Model, hum :: Humanoid, root :: BasePart
	NPCCommon.animate(h, r)
	NPCCommon.onDeath(m, h, REMOVE_AFTER, RESPAWN_AFTER, spawnOne)
	task.spawn(function()
		while h.Health > 0 and m.Parent do
			task.wait(rng:NextNumber(PAUSE.Min, PAUSE.Max))
			if h.Health <= 0 or not m.Parent then
				break
			end
			local goal = NPCCommon.groundAt(randomPoint())
			if goal then
				walkTo(h, r, goal)
			end
		end
	end)
end

for _ = 1, COUNT do
	task.spawn(spawnOne)
end
