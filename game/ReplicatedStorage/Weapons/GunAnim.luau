--!strict
-- Procedural reload animation, played on every client (own gun and other players' guns).
-- Moves the left hand's IK target (Handle.LeftHandIK), carries the magazine in that hand,
-- and tilts the gun. Call GunAnim.step every frame while a reload is active.
local GunAnim = {}

type Rest = { left: CFrame, mag: CFrame }
type Active = { start: number, duration: number }

local rest: { [Tool]: Rest } = setmetatable({}, { __mode = "k" }) :: any
local active: { [Tool]: Active } = setmetatable({}, { __mode = "k" }) :: any

-- left-hand path, as a fraction of the reload time. "gun" = handle space, "body" = torso space.
local GRAB = Vector3.new(-0.02, -0.75, -0.16) -- bottom of the magazine
local KEYS: { { any } } = {
	{ 0.00, "rest" },
	{ 0.12, "gun", GRAB },
	{ 0.25, "gun", Vector3.new(-0.02, -1.55, 0.0) }, -- old mag pulled out
	{ 0.42, "body", Vector3.new(-0.55, -1.05, -0.55) }, -- stowed in the left hip pouch
	{ 0.50, "body", Vector3.new(-0.55, -1.05, -0.55) }, -- new mag grabbed
	{ 0.68, "gun", Vector3.new(-0.02, -1.35, -0.12) }, -- lined up under the mag well
	{ 0.78, "gun", GRAB }, -- seated
	{ 0.86, "gun", Vector3.new(-0.24, 0.12, 0.08) }, -- slap the bolt release
	{ 1.00, "rest" },
}
local MAG_IN_HAND = { 0.12, 0.78 }
local MAG_HIDDEN = { 0.42, 0.5 }

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function parts(tool: Tool): (BasePart?, Attachment?, Weld?, BasePart?)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		return nil, nil, nil, nil
	end
	return handle,
		handle:FindFirstChild("LeftHandIK") :: Attachment?,
		handle:FindFirstChild("MagWeld") :: Weld?,
		tool:FindFirstChild("Magazine") :: BasePart?
end

local function restOf(tool: Tool): Rest?
	local r = rest[tool]
	if r then
		return r
	end
	local _, left, magWeld = parts(tool)
	if not left or not magWeld then
		return nil
	end
	r = { left = left.CFrame, mag = magWeld.C0 }
	rest[tool] = r
	return r
end

function GunAnim.remember(tool: Tool)
	restOf(tool)
end

function GunAnim.startReload(tool: Tool, duration: number)
	if restOf(tool) then
		active[tool] = { start = os.clock(), duration = duration }
	end
end

function GunAnim.isReloading(tool: Tool): boolean
	return active[tool] ~= nil
end

function GunAnim.stop(tool: Tool)
	active[tool] = nil
	local r = rest[tool]
	local _, left, magWeld, mag = parts(tool)
	if r and left and magWeld then
		left.CFrame = r.left
		magWeld.C0 = r.mag
	end
	if mag then
		mag.LocalTransparencyModifier = 0
	end
end

-- Advance the animation; returns the gun's extra tilt (handle space) for this frame.
function GunAnim.step(tool: Tool, torso: BasePart?): CFrame
	local a = active[tool]
	if not a then
		return CFrame.identity
	end
	local t = (os.clock() - a.start) / a.duration
	if t >= 1 then
		GunAnim.stop(tool)
		return CFrame.identity
	end
	local r = rest[tool]
	local handle, left, magWeld, mag = parts(tool)
	if not r or not handle or not left or not magWeld then
		return CFrame.identity
	end

	local function keyPos(k: { any }): Vector3
		if k[2] == "rest" then
			return r.left.Position
		elseif k[2] == "body" and torso then
			return handle.CFrame:PointToObjectSpace(torso.CFrame:PointToWorldSpace(k[3]))
		end
		return k[3]
	end
	local pos = r.left.Position
	for i = 1, #KEYS - 1 do
		local k0, k1 = KEYS[i], KEYS[i + 1]
		if t >= k0[1] and t <= k1[1] then
			local f = smooth((t - k0[1]) / math.max(k1[1] - k0[1], 1e-3))
			pos = keyPos(k0):Lerp(keyPos(k1), f)
			break
		end
	end
	left.CFrame = CFrame.new(pos) * r.left.Rotation

	if t > MAG_IN_HAND[1] and t < MAG_IN_HAND[2] then
		magWeld.C0 = CFrame.new(pos + (r.mag.Position - GRAB)) * r.mag.Rotation
	else
		magWeld.C0 = r.mag
	end
	if mag then
		mag.LocalTransparencyModifier = (t > MAG_HIDDEN[1] and t < MAG_HIDDEN[2]) and 1 or 0
	end

	-- tilt the gun toward the reloading hand, then back
	local w = smooth(t / 0.15) * (1 - smooth((t - 0.85) / 0.15))
	return CFrame.new(-0.08 * w, 0.12 * w, 0.1 * w) * CFrame.Angles(math.rad(12) * w, 0, math.rad(28) * w)
end

return GunAnim
