--!strict
-- The crew's plan (one per server, everyone can edit it): entry method, vehicles (kind, spot, arrival
-- time), map notes, and each player's own loadout. The plan never blocks anything during the heist:
-- it only decides which vehicles arrive when, what everyone carries and what notes are shown.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Heist = ReplicatedStorage:WaitForChild("Heist")
local Items = require(Heist:WaitForChild("Items"))
local Noobla = require(Heist:WaitForChild("Noobla"))
local Net = require(Heist:WaitForChild("Net"))
local Data = require(script.Parent:WaitForChild("Data"))

export type Vehicle = { id: number, kind: string, x: number, z: number, t: number, by: number, byName: string }
export type Pin = { id: number, floor: string, x: number, z: number, text: string, color: number, byName: string }
export type Weapon = { kind: string, silencer: boolean, grip: boolean, holo: boolean }
export type Loadout = { weapons: { Weapon }, items: { [string]: number }, vest: boolean }

local Plan = {}
local state = {
	method = "",
	vehicles = {} :: { Vehicle },
	pins = {} :: { Pin },
	loadouts = {} :: { [string]: Loadout },
}
local nextId = 1
local MAX_VEHICLES = 6
local MAX_PINS = 30
local MAX_WEAPONS = 2

local function defaultLoadout(): Loadout
	return {
		weapons = { { kind = "pistol", silencer = true, grip = false, holo = false } },
		items = { zipties = 4, hackkey = 1 },
		vest = false,
	}
end

function Plan.get(): any
	return state
end

function Plan.loadout(player: Player): Loadout
	local key = tostring(player.UserId)
	if not state.loadouts[key] then
		state.loadouts[key] = defaultLoadout()
	end
	return state.loadouts[key]
end

function Plan.broadcast()
	Net.event():FireAllClients("Plan", state)
end

function Plan.reset()
	state.method = ""
	state.vehicles = {}
	state.pins = {}
	Plan.broadcast()
end

-- vehicles of a kind that `player` already put in the plan
local function used(player: Player, kind: string): number
	local n = 0
	for _, v in state.vehicles do
		if v.by == player.UserId and v.kind == kind then
			n += 1
		end
	end
	return n
end

-- outside the bank's footprint and not on the roof
local function validSpot(x: number, z: number): boolean
	if x ~= x or z ~= z or math.abs(x) > 400 or math.abs(z) > 500 then
		return false
	end
	local bank = workspace:FindFirstChild("NooblaBank")
	local rootCf = bank and bank:GetAttribute("Root")
	if typeof(rootCf) == "CFrame" then
		local lp = rootCf:PointToObjectSpace(Vector3.new(x, 0, z))
		if math.abs(lp.X) < 86 and math.abs(lp.Z) < 66 then
			return false
		end
	end
	return true
end

local function num(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v then
		return nil
	end
	return math.clamp(v, lo, hi)
end

-- one plan edit. Returns ok, message
function Plan.edit(player: Player, op: any, a: any, b: any, c: any, d: any): (boolean, string?)
	local phase = Net.state():GetAttribute("Phase")
	if phase == "Heist" then
		return false, "Le braquage a déjà commencé !"
	end
	if op == "method" then
		if a == "" then
			state.method = ""
		else
			local ok = false
			for _, m in Noobla.methods do
				if m.id == a and not m.locked then
					ok = true
				end
			end
			if not ok then
				return false, "Méthode inconnue."
			end
			local p = Data.get(player)
			if not (p and p.intel[a]) then
				return false, "Fais d'abord des repérages pour découvrir cette méthode."
			end
			state.method = a
		end
	elseif op == "addVehicle" then
		local kind = a
		local it = Items.byId[kind]
		local x, z, t = num(b, -400, 400), num(c, -500, 500), num(d, 0, Noobla.timeLimit)
		if not it or it.kind ~= "vehicle" or not x or not z or not t then
			return false, "Véhicule invalide."
		end
		if #state.vehicles >= MAX_VEHICLES then
			return false, "Maximum " .. MAX_VEHICLES .. " véhicules dans le plan."
		end
		if used(player, kind) >= Data.count(player, kind) then
			return false, "Tu n'as plus de " .. it.name .. " disponible."
		end
		if not validSpot(x, z) then
			return false, "Place le véhicule dehors, pas dans la banque."
		end
		table.insert(state.vehicles, { id = nextId, kind = kind, x = x, z = z, t = math.floor(t), by = player.UserId, byName = player.DisplayName })
		nextId += 1
	elseif op == "moveVehicle" or op == "timeVehicle" or op == "removeVehicle" then
		for i, v in state.vehicles do
			if v.id == a then
				if op == "removeVehicle" then
					table.remove(state.vehicles, i)
				elseif op == "timeVehicle" then
					local t = num(b, 0, Noobla.timeLimit)
					if t then
						v.t = math.floor(t)
					end
				else
					local x, z = num(b, -400, 400), num(c, -500, 500)
					if x and z and validSpot(x, z) then
						v.x, v.z = x, z
					else
						return false, "Place le véhicule dehors, pas dans la banque."
					end
				end
				break
			end
		end
	elseif op == "addPin" then
		local x, z = num(b, -400, 400), num(c, -500, 500)
		local col = num(d, 1, 6)
		if (a ~= "ground" and a ~= "roof") or not x or not z or not col then
			return false, "Note invalide."
		end
		if #state.pins >= MAX_PINS then
			return false, "Trop de notes sur le plan."
		end
		table.insert(state.pins, { id = nextId, floor = a, x = x, z = z, text = "", color = math.floor(col), byName = player.DisplayName })
		nextId += 1
	elseif op == "pinText" or op == "removePin" then
		for i, pin in state.pins do
			if pin.id == a then
				if op == "removePin" then
					table.remove(state.pins, i)
				elseif type(b) == "string" then
					pin.text = string.sub(b, 1, 80)
				end
				break
			end
		end
	elseif op == "loadout" then
		-- a = { weapons = {...}, items = {...}, vest = bool } from the client: rebuilt and checked here
		if type(a) ~= "table" then
			return false, "Équipement invalide."
		end
		local lo: Loadout = { weapons = {}, items = {}, vest = false }
		local need: { [string]: number } = {}
		if type(a.weapons) == "table" then
			for _, w in a.weapons do
				if #lo.weapons >= MAX_WEAPONS then
					break
				end
				if type(w) == "table" and Items.byId[w.kind] and Items.byId[w.kind].kind == "weapon" then
					local nw = { kind = w.kind, silencer = w.silencer == true, grip = w.grip == true, holo = w.holo == true }
					table.insert(lo.weapons, nw)
					need[w.kind] = (need[w.kind] or 0) + 1
					for _, att in { "silencer", "grip", "holo" } do
						if (nw :: any)[att] then
							need[att] = (need[att] or 0) + 1
						end
					end
				end
			end
		end
		if type(a.items) == "table" then
			for id, n in a.items do
				local it = Items.byId[id]
				if it and it.kind == "tool" and type(n) == "number" and n > 0 then
					lo.items[id] = math.min(math.floor(n), 20)
					need[id] = lo.items[id]
				end
			end
		end
		lo.vest = a.vest == true
		if lo.vest then
			need.vest = 1
		end
		for id, n in need do
			if Data.count(player, id) < n then
				return false, "Pas assez de: " .. Items.byId[id].name
			end
		end
		state.loadouts[tostring(player.UserId)] = lo
	else
		return false, "?"
	end
	Plan.broadcast()
	return true, nil
end

function Plan.init()
	Players.PlayerRemoving:Connect(function(pl)
		for i = #state.vehicles, 1, -1 do
			if state.vehicles[i].by == pl.UserId then
				table.remove(state.vehicles, i)
			end
		end
		state.loadouts[tostring(pl.UserId)] = nil
		Plan.broadcast()
	end)
end

return Plan
