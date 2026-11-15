--!strict
-- Server side of the action animations and cinematics. The server decides WHEN things happen (the
-- charge appears, the loot pops out); the clients play the body animation / the cinematic and are told
-- with the "Act" and "Cine" events. The acting player is locked (character attribute Acting, read by
-- HeavyMovement) and protected (ForceField) while it lasts; whatever weapon was in hand is put away
-- and back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local Net = require(Heist:WaitForChild("Net"))
local AA = require(Heist:WaitForChild("ActionAnim"))
local Meta = require(Heist:WaitForChild("CineMeta"))

local Actions = {}
Actions.Meta = Meta

-- play `name` on pl's character for everybody (or everybody else)
function Actions.act(pl: Player, name: string, target: CFrame?, exceptSelf: boolean?)
	local ev = Net.event()
	for _, p in Players:GetPlayers() do
		if not (exceptSelf and p == pl) then
			ev:FireClient(p, "Act", pl.UserId, name, target)
		end
	end
end

local function lock(pl: Player, seconds: number, protect: boolean): (Model?, Humanoid?, Tool?)
	local c = pl.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not c or not hum or hum.Health <= 0 or c:GetAttribute("Acting") then
		return nil, nil, nil
	end
	c:SetAttribute("Acting", true)
	local held = c:FindFirstChildOfClass("Tool")
	if held then
		hum:UnequipTools()
	end
	local ff: ForceField? = nil
	if protect then
		ff = Instance.new("ForceField")
		ff.Visible = false
		ff.Parent = c
	end
	task.delay(seconds, function()
		if ff then
			ff:Destroy()
		end
		if c.Parent then
			c:SetAttribute("Acting", nil)
			local bp = pl:FindFirstChild("Backpack")
			if held and bp and held.Parent == bp and hum.Health > 0 then
				hum:EquipTool(held)
			end
		end
	end)
	return c, hum, held
end

-- a short action: locks the player for its length and yields until `effectAt` seconds in.
-- Returns false if it could not start (dead, already busy) or the player died meanwhile.
function Actions.run(pl: Player, name: string, effectAt: number, target: CFrame?): boolean
	local c, hum = lock(pl, AA.dur(name) + 0.05, false)
	if not c or not hum then
		return false
	end
	Actions.act(pl, name, target)
	task.wait(effectAt)
	return c.Parent ~= nil and hum.Health > 0
end

-- a cinematic for the acting player (the others see the action itself). Returns false if it could not
-- start. Does not yield: the caller waits for Meta[kind].effectAt.
function Actions.cine(pl: Player, kind: string, spot: Instance, others: string?, target: CFrame?): boolean
	local meta = (Meta :: any)[kind]
	local c, hum = lock(pl, meta.len + 0.2, true)
	if not c or not hum then
		return false
	end
	Net.event():FireClient(pl, "Cine", kind, spot)
	if others then
		Actions.act(pl, others, target, true)
	end
	return true
end

return Actions
