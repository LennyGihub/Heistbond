--!strict
-- Player profiles: cash, inventory counts, discovered intel. Saved in a DataStore (pcall + UpdateAsync,
-- autosave, save on leave and on shutdown). In Studio without API access it just keeps defaults.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage:WaitForChild("Heist"):WaitForChild("Items"))
local Net = require(ReplicatedStorage.Heist:WaitForChild("Net"))

export type Profile = {
	cash: number,
	inv: { [string]: number },
	intel: { [string]: boolean },
	heists: number,
	earned: number,
}

local STORE = "HeistProfile_v1"
local START_CASH = 5000

local Data = {}
local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local function fresh(): Profile
	return { cash = START_CASH, inv = table.clone(Items.START), intel = {}, heists = 0, earned = 0 }
end

local function sanitize(raw: any): Profile
	local p = fresh()
	if type(raw) ~= "table" then
		return p
	end
	if type(raw.cash) == "number" then
		p.cash = math.max(0, math.floor(raw.cash))
	end
	if type(raw.inv) == "table" then
		for id, n in raw.inv do
			if Items.byId[id] and type(n) == "number" then
				p.inv[id] = math.max(0, math.floor(n))
			end
		end
	end
	if type(raw.intel) == "table" then
		for k, v in raw.intel do
			if type(k) == "string" and v == true then
				p.intel[k] = true
			end
		end
	end
	p.heists = if type(raw.heists) == "number" then raw.heists else 0
	p.earned = if type(raw.earned) == "number" then raw.earned else 0
	return p
end

function Data.push(player: Player)
	local p = profiles[player]
	if p then
		Net.event():FireClient(player, "Profile", p)
	end
end

function Data.get(player: Player): Profile?
	return profiles[player]
end

function Data.count(player: Player, id: string): number
	local p = profiles[player]
	return p and (p.inv[id] or 0) or 0
end

function Data.add(player: Player, id: string, n: number)
	local p = profiles[player]
	if p then
		p.inv[id] = math.max(0, (p.inv[id] or 0) + n)
		Data.push(player)
	end
end

-- take n of an item; false (nothing taken) if there aren't enough
function Data.take(player: Player, id: string, n: number): boolean
	local p = profiles[player]
	if not p or (p.inv[id] or 0) < n then
		return false
	end
	p.inv[id] -= n
	Data.push(player)
	return true
end

function Data.addCash(player: Player, n: number)
	local p = profiles[player]
	if p then
		p.cash = math.max(0, p.cash + math.floor(n))
		if n > 0 then
			p.earned += math.floor(n)
		end
		Data.push(player)
	end
end

function Data.learn(player: Player, key: string): boolean
	local p = profiles[player]
	if p and not p.intel[key] then
		p.intel[key] = true
		Data.push(player)
		return true
	end
	return false
end

function Data.save(player: Player)
	local p = profiles[player]
	if not p or not loaded[player] or not store then
		return
	end
	local key = "u" .. player.UserId
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key, function()
			return p
		end)
	end)
	if not ok then
		warn("[Heist] save failed for", player.Name, err)
	end
end

local function load(player: Player)
	local raw = nil
	local ok = false
	if store then
		for _ = 1, 3 do
			ok = pcall(function()
				raw = (store :: DataStore):GetAsync("u" .. player.UserId)
			end)
			if ok then
				break
			end
			task.wait(1)
		end
	end
	if not player.Parent then
		return
	end
	profiles[player] = sanitize(raw)
	-- only save back what we really read (a failed read must not overwrite a real save with defaults)
	loaded[player] = ok
	Data.push(player)
end

function Data.init()
	for _, pl in Players:GetPlayers() do
		task.spawn(load, pl)
	end
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(pl)
		Data.save(pl)
		profiles[pl] = nil
		loaded[pl] = nil
	end)
	game:BindToClose(function()
		for _, pl in Players:GetPlayers() do
			Data.save(pl)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			for _, pl in Players:GetPlayers() do
				task.spawn(Data.save, pl)
			end
		end
	end)
end

-- wait until a player's profile exists (or they leave)
function Data.wait(player: Player): Profile?
	local t = 0
	while not profiles[player] and player.Parent and t < 15 do
		t += task.wait(0.1)
	end
	return profiles[player]
end

return Data
