--!strict
-- Replicates who is in cover: CoverClient tells the server (CoverState remote), the server sets the
-- character attribute CoverSide (0 = not in cover, -1/1 = looking left/right) that every client uses
-- to draw the cover pose. Purely visual, so the only checks are types, a rate limit and that the
-- character is alive.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("Cover") or Instance.new("Folder")
folder.Name = "Cover"
folder.Parent = ReplicatedStorage
local remote = folder:FindFirstChild("CoverState") :: RemoteEvent?
if not remote then
	local r = Instance.new("RemoteEvent")
	r.Name = "CoverState"
	r.Parent = folder
	remote = r
end

local budget: { [Player]: { t: number, n: number } } = {}

(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, on: unknown, side: unknown)
	local now = os.clock()
	local b = budget[player]
	if not b or now - b.t > 1 then
		b = { t = now, n = 0 }
		budget[player] = b
	end
	local bb = b :: { t: number, n: number }
	bb.n += 1
	if bb.n > 20 then
		return
	end
	if typeof(on) ~= "boolean" then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	local value = 0
	if on and hum.Health > 0 then
		value = (typeof(side) == "number" and side < 0) and -1 or 1
	end
	char:SetAttribute("CoverSide", value)
end)

Players.PlayerRemoving:Connect(function(p)
	budget[p] = nil
end)
