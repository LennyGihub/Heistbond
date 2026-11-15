--!strict
-- Ride (client): the crew seated in a vehicle that this client moves itself (cinematics).
--  * the local player's own character is anchored (locally: we own its physics, so the server and the
--    other players see it ride along) and placed on its seat every frame, in a seated pose;
--  * the other riders' real characters are hidden on this client and replaced by seated copies (their
--    own clients move the real ones along the same path, a little late over the network);
--  * release() puts everyone back: own character unanchored (where it is), the copies swapped for the
--    real characters.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local AA = require(Heist:WaitForChild("ActionAnim"))
local Cine = require(Heist:WaitForChild("Cine"))

local Ride = {}
Ride.__index = Ride

export type Rider = { player: Player, seat: CFrame, real: Model?, clone: Model?, anim: { stop: () -> () }? }
export type Ride = typeof(setmetatable({} :: {
	model: Model,
	riders: { Rider },
	floor: number,
	released: boolean,
	meOut: boolean,
	othersOut: boolean,
	lastHide: number,
}, Ride))

local me = Players.LocalPlayer

-- the root's height above the seat point for a seated character (hips on the seat, AA "sit" lowers the
-- hips by 1.15 from standing)
local function rootHeight(char: Model): number
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return 3
	end
	return hum.HipHeight + root.Size.Y / 2
end

local function copyOf(char: Model): Model?
	local old = char.Archivable
	char.Archivable = true
	local ok, c = pcall(function()
		return char:Clone()
	end)
	char.Archivable = old
	if not ok or not c then
		return nil
	end
	local m = c :: Model
	for _, d in m:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("ForceField") or d:IsA("BillboardGui") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
	end
	m.Name = char.Name .. "_Ride"
	m.Parent = workspace
	return m
end

-- seats: local CFrames (relative to the vehicle pivot, at seat height: Y = the seat surface)
-- hidden = true: nobody is shown riding (a closed vehicle): no copies, the own character hidden too
function Ride.new(model: Model, players: { Player }, seats: { CFrame }, hidden: boolean?): Ride
	local self = setmetatable({ model = model, riders = {}, floor = 0, released = false, meOut = false, othersOut = false, lastHide = 0 }, Ride)
	for i, p in players do
		local seat = seats[((i - 1) % #seats) + 1]
		local r: Rider = { player = p, seat = seat, real = p.Character, clone = nil, anim = nil }
		local char = p.Character
		if char then
			if p == me then
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char:FindFirstChildOfClass("Humanoid")
				if root then
					root.Anchored = true
				end
				if hum then
					hum:UnequipTools()
				end
				if hidden then
					Cine.hide(char, true)
				else
					r.anim = AA.play(char, "sit")
				end
			else
				Cine.hide(char, true)
				local c = if hidden then nil else copyOf(char)
				if c then
					r.clone = c
					r.anim = AA.play(c, "sit")
				end
			end
		end
		table.insert(self.riders, r)
	end
	self:update()
	return self
end

-- call every frame after moving the vehicle
function Ride.update(self: Ride)
	if self.released then
		return
	end
	local pivot = self.model:GetPivot()
	for _, r in self.riders do
		local body = if r.player == me then r.real else r.clone
		local root = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
		local done = if r.player == me then self.meOut else self.othersOut
		if body and root and not done then
			root.CFrame = pivot * r.seat * CFrame.new(0, rootHeight(body) - 0.05, 0)
			if r.player ~= me and r.real and os.clock() - self.lastHide > 0.5 then
				Cine.hide(r.real, true) -- late-loaded accessories
			end
		end
	end
	if os.clock() - self.lastHide > 0.5 then
		self.lastHide = os.clock()
	end
end

-- own character: back to physics (stays where it is, still seated until the pose fades)
function Ride.releaseMe(self: Ride)
	self.meOut = true
	for _, r in self.riders do
		if r.player == me and r.real then
			local root = r.real:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
			end
			if r.anim then
				r.anim.stop()
				r.anim = nil
			end
			Cine.hide(r.real, false)
		end
	end
end

-- the other riders: copies away, real characters shown
function Ride.releaseOthers(self: Ride)
	self.othersOut = true
	for _, r in self.riders do
		if r.player ~= me then
			if r.anim then
				r.anim.stop()
				r.anim = nil
			end
			if r.clone then
				r.clone:Destroy()
				r.clone = nil
			end
			if r.real and r.real.Parent then
				Cine.hide(r.real, false)
			end
		end
	end
end

function Ride.release(self: Ride)
	self:releaseMe()
	self:releaseOthers()
	self.released = true
end

return Ride
