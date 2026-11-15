--!strict
-- Heist remotes. The server creates them; clients wait for them.
--   Request (RemoteFunction): client -> server actions, returns (ok, message/data)
--   Event   (RemoteEvent):    server -> client pushes: ("Profile", p), ("Plan", plan), ("Toast", text, kind),
--                             ("Intel", key), ("HackStart", token, steps), ("Results", summary), ("Fx", kind, ...)
-- Live heist state is in attributes on ReplicatedStorage.HeistState (Phase, EndTime, BankAlert, ...).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local function get(name: string, class: string): Instance
	local folder = ReplicatedStorage:FindFirstChild("HeistRemotes")
	if RunService:IsServer() then
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "HeistRemotes"
			folder.Parent = ReplicatedStorage
		end
		local r = (folder :: Instance):FindFirstChild(name)
		if not r then
			r = Instance.new(class)
			r.Name = name
			r.Parent = folder
		end
		return r :: Instance
	end
	return ReplicatedStorage:WaitForChild("HeistRemotes"):WaitForChild(name)
end

function Net.request(): RemoteFunction
	return get("Request", "RemoteFunction") :: RemoteFunction
end

function Net.event(): RemoteEvent
	return get("Event", "RemoteEvent") :: RemoteEvent
end

function Net.state(): Folder
	local s = ReplicatedStorage:FindFirstChild("HeistState")
	if RunService:IsServer() and not s then
		s = Instance.new("Folder")
		s.Name = "HeistState"
		s.Parent = ReplicatedStorage
	end
	return (s or ReplicatedStorage:WaitForChild("HeistState")) :: Folder
end

return Net
