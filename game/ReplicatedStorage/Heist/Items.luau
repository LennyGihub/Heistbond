--!strict
-- Every heist item: what it is, how it shows in the inventory, and the starting stock.
-- Kinds: vehicle (spawned from the plan), weapon (a Tool in the heist), attachment (put on a weapon,
-- never used up), gear (worn), tool (a Tool, used up when used), intel (found in a heist, not stored).
-- `icon` is the drawn badge (colour + 2-3 letter code) used until image icons exist; `image` wins if set.

export type Item = {
	id: string,
	name: string,
	kind: string,
	desc: string,
	color: Color3,
	code: string,
	image: string?,
	tool: string?, -- Tool name given in the heist (weapons + usable tools)
	perHeist: number?, -- max you can bring
}

local RGB = Color3.fromRGB

local list: { Item } = {
	-- vehicles
	{ id = "van", name = "Van noir", kind = "vehicle", code = "VAN", color = RGB(40, 40, 46),
		desc = "Lent mais enorme coffre: 12 sacs." },
	{ id = "sportscar", name = "Voiture de sport", kind = "vehicle", code = "SPT", color = RGB(200, 40, 40),
		desc = "Très rapide, petit coffre: 3 sacs." },
	{ id = "armoredcar", name = "Voiture blindée", kind = "vehicle", code = "BLD", color = RGB(110, 116, 122),
		desc = "Encaisse les balles. Coffre: 6 sacs." },
	-- weapons
	{ id = "pistol", name = "Pistolet léger", kind = "weapon", code = "PST", color = RGB(70, 70, 76), tool = "Pistol",
		desc = "Discret, facile a cacher.", perHeist = 1 },
	{ id = "rifle", name = "Arme automatique lourde", kind = "weapon", code = "AUT", color = RGB(60, 66, 58), tool = "M4A1",
		desc = "M4A1. Cadence élevée.", perHeist = 1 },
	{ id = "sniper", name = "Sniper", kind = "weapon", code = "SNP", color = RGB(80, 66, 50), tool = "Sniper",
		desc = "Un tir, une cible. Bruyant.", perHeist = 1 },
	-- attachments
	{ id = "silencer", name = "Silencieux", kind = "attachment", code = "SIL", color = RGB(50, 50, 56),
		desc = "Tes tirs n'alertent plus la banque." },
	{ id = "grip", name = "Poignée verticale", kind = "attachment", code = "GRP", color = RGB(90, 76, 60),
		desc = "-35% de recul." },
	{ id = "holo", name = "Viseur holographique", kind = "attachment", code = "HOL", color = RGB(200, 50, 50),
		desc = "Visée plus précise." },
	-- gear
	{ id = "vest", name = "Veste lourde", kind = "gear", code = "VST", color = RGB(60, 80, 60),
		desc = "+60 de vie, un peu plus lent.", perHeist = 1 },
	-- usable tools
	{ id = "emp", name = "IEM", kind = "tool", code = "IEM", color = RGB(40, 120, 220), tool = "EMP",
		desc = "Coupe caméras et alarmes 60 s autour de toi." },
	{ id = "hackkey", name = "Clé de piratage Nv.1", kind = "tool", code = "HK1", color = RGB(30, 170, 80), tool = "HackKey",
		desc = "Pirate un clavier de sécurité niveau 1." },
	{ id = "c4", name = "Explosif C4", kind = "tool", code = "C4", color = RGB(220, 150, 40), tool = "C4",
		desc = "Pose-le sur une zone fragile, puis BOUM." },
	{ id = "drill", name = "Perceuse lourde", kind = "tool", code = "DRL", color = RGB(230, 190, 30), tool = "Drill",
		desc = "Perce la porte du coffre. Très bruyant." },
	{ id = "rope", name = "Corde de rappel", kind = "tool", code = "RAP", color = RGB(160, 110, 60), tool = "Rope",
		desc = "Grimpe sur un toit ou descends par un trou." },
	{ id = "zipties", name = "Zip ties", kind = "tool", code = "ZIP", color = RGB(30, 30, 30), tool = "ZipTies",
		desc = "Attache un civil qui leve les mains." },
	-- found in the heist only
	{ id = "card5", name = "Carte d'accès Nv.5", kind = "intel", code = "NV5", color = RGB(230, 180, 40), tool = "AccessCard",
		desc = "Ouvre le coffre sans alarme. Le directeur la porte." },
}

local START: { [string]: number } = {
	van = 2, sportscar = 1, armoredcar = 1,
	pistol = 10, rifle = 2, sniper = 1,
	silencer = 15, grip = 15, holo = 15,
	vest = 4, emp = 1, hackkey = 5, c4 = 4, drill = 4, rope = 20, zipties = 50,
}

local byId: { [string]: Item } = {}
local byTool: { [string]: Item } = {}
for _, it in list do
	byId[it.id] = it
	if it.tool then
		byTool[it.tool] = it
	end
end

local KIND_NAME = {
	vehicle = "VÉHICULES", weapon = "ARMES", attachment = "ACCESSOIRES", gear = "ÉQUIPEMENT",
	tool = "OUTILS", intel = "OBJETS",
}
local KIND_ORDER = { "vehicle", "weapon", "attachment", "gear", "tool" }

return {
	list = list,
	byId = byId,
	byTool = byTool,
	START = START,
	KIND_NAME = KIND_NAME,
	KIND_ORDER = KIND_ORDER,
}
