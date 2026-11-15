--!strict
-- Heist entry point: wires the modules together and answers the client's requests.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Heist"):WaitForChild("Net"))

local Data = require(script.Parent:WaitForChild("Data"))
local Plan = require(script.Parent:WaitForChild("Plan"))
local Tools = require(script.Parent:WaitForChild("Tools"))
local Npcs = require(script.Parent:WaitForChild("Npcs"))
local Run = require(script.Parent:WaitForChild("Run"))

Net.state()
Net.event()
local Request = Net.request()

Data.init()
Plan.init()
Tools.init()
Npcs.init()
Run.init()

local last: { [Player]: number } = {}

Request.OnServerInvoke = function(player: Player, action: any, a: any, b: any, c: any, d: any, e: any): (boolean, any)
	if type(action) ~= "string" then
		return false, nil
	end
	-- light flood protection
	local t = os.clock()
	if (last[player] or 0) > t - 0.05 then
		return false, "Doucement !"
	end
	last[player] = t
	if action == "Profile" then
		return true, Data.wait(player)
	elseif action == "Plan" then
		return true, Plan.get()
	elseif action == "PlanEdit" then
		return Plan.edit(player, a, b, c, d, e)
	elseif action == "StartScout" then
		return Run.startScout(player)
	elseif action == "LeaveScout" then
		Run.leaveScout(player)
		return true, nil
	elseif action == "StartHeist" then
		return Run.startHeist(player)
	elseif action == "HackResult" then
		Run.hackResult(player, a, b)
		return true, nil
	elseif action == "Throw" then
		Run.throw(player, a)
		return true, nil
	elseif action == "Abandon" then
		Run.abandon(player)
		return true, nil
	elseif action == "Test" and RunService:IsStudio() then
		-- Studio-only test hooks for scripted playtests
		if a == "learn" then
			for _, k in { "hack", "drill", "c4", "card", "refill", "locker167" } do
				Data.learn(player, k)
			end
			return true, "learned"
		elseif a == "trigger" then
			-- b = a ProximityPrompt (or a part holding one + its name in c)
			local pp = if typeof(b) == "Instance" and b:IsA("ProximityPrompt") then b elseif typeof(b) == "Instance" then b:FindFirstChild(c or "", true) else nil
			if not pp or not pp:IsA("ProximityPrompt") then
				return false, "no prompt"
			end
			Run.trigger(pp, player)
			Npcs.trigger(pp, player)
			return true, pp:GetFullName()
		elseif a == "tp" and typeof(b) == "Vector3" then
			local char = player.Character
			if char then
				char:PivotTo(CFrame.new(b))
			end
			return true, nil
		elseif a == "tpveh" and typeof(b) == "Vector3" then
			local f = workspace:FindFirstChild("HeistVehicles")
			local v = f and f:GetChildren()[c or 1] :: Model?
			if v then
				v:PivotTo(CFrame.new(b))
				return true, v.Name
			end
			return false, "no vehicle"
		elseif a == "npcs" then
			local out = {}
			for _, n in Npcs.list do
				table.insert(out, n.model.Name .. "=" .. n.state .. string.format("(%.1f)", n.meter))
			end
			return true, table.concat(out, ", ")
		elseif a == "kill" then
			for _, n in Npcs.list do
				if n.role == b then
					n.hum.Health = 0
				end
			end
			return true, nil
		end
		return false, "?"
	end
	return false, "?"
end

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)
