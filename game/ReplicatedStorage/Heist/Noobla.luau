--!strict
-- The first heist: La Noobla Bank. Methods into the vault, scouting intel, objective, tuning.
local Noobla = {
	id = "noobla",
	name = "La Noobla Bank",
	timeLimit = 15 * 60,
	objective = { locker = 167, bonus = 25000, name = "Contenu du casier 167" },
	lockerCash = { 600, 2600 },
	bagCapacity = 5, -- lockers per money bag
	bankCallDelay = 30, -- seconds between the bank alarm and the police being called
	policeDelay = 45, -- seconds between the call and the first police squad
	drillTime = 90,
	c4Fuse = 5,
	empTime = 60,
	methods = {
		{ id = "hack", n = 1, name = "PIRATAGE", needs = "Clé de piratage Nv.1", alert = "Aucune alerte",
			desc = "Pirate le clavier SecuLock v1 de la porte du coffre. Silencieux." },
		{ id = "drill", n = 2, name = "PERCEUSE", needs = "Perceuse lourde", alert = "Banque alertée, puis la police",
			desc = "Perce la porte (90 s). Le bruit alerte la banque, qui appelle la police." },
		{ id = "c4", n = 3, name = "C4", needs = "C4 (+ corde pour le toit)", alert = "Banque + police alertées",
			desc = "Fais sauter le toit, la porte ou un des 3 murs. Un mur qui saute détruit ses casiers." },
		{ id = "card", n = 4, name = "CARTE NV.5", needs = "La carte du directeur", alert = "Aucune alerte",
			desc = "Prends la carte d'accès niveau 5 du directeur et badge à la porte du coffre." },
		{ id = "refill", n = 5, name = "REMPLISSEURS", needs = "?", alert = "?", locked = true,
			desc = "La porte s'ouvre pendant le remplissage, gardée par 2 convoyeurs. (Bientôt)" },
	},
	intel = {
		hack = { title = "Le clavier du coffre", method = "hack",
			text = "Une guichetière râle: « le technicien n'a TOUJOURS pas mis à jour le clavier du coffre, il tourne encore sous SecuLock v1 ». Une clé de piratage Nv.1 suffit. Aucune alarme." },
		drill = { title = "Facture dans la benne", method = "drill",
			text = "Dans la benne de la ruelle: « Remplacement charnière porte de coffre - acier standard classe B ». La porte peut être percée... mais une perceuse, ça s'entend." },
		c4 = { title = "Avis de travaux", method = "c4",
			text = "Panneau du hall: « Rénovation : toiture légère au-dessus de la salle forte, cloisons en brique ». Le C4 passe par le toit (avec une corde), la porte ou les 3 murs. Un mur qui saute emporte ses casiers." },
		card = { title = "Le badge du directeur", method = "card",
			text = "Le directeur, au téléphone dans le hall: « Non non, il n'y a que MOI qui ai la carte niveau 5, je la garde toujours sur moi ! » Prends-la-lui: attache-le, ou subtilise-la dans son dos." },
		refill = { title = "Le fourgon blindé", method = "refill",
			text = "Le fourgon NOOBLA TRANSFERTS: deux convoyeurs armés remplissent le coffre à heures fixes, porte grande ouverte. (Méthode bientôt disponible)" },
		locker167 = { title = "Le casier 167",
			text = "Un client dans la file: « mon casier 167 ? Mur du fond du coffre, côté ruelle. » Le casier 167 est sur le mur NORD. Si ce mur saute, le casier est détruit !" },
	},
	clueOrder = { "hack", "drill", "c4", "card", "refill", "locker167" },
}

return Noobla
