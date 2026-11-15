--!strict
-- What the NPCs say: names, reactions, small talk (exchanges between two people), monologues and combat
-- calls. Pure data + a picker; NpcLife / NpcCombat / Npcs decide when to use them.
local rng = Random.new()

local Lines = {}

Lines.firstF = { "Marie", "Chloé", "Inès", "Camille", "Léa", "Nadia", "Sophie", "Manon", "Julie", "Yasmine", "Emma", "Clara" }
Lines.firstM = { "Paul", "Karim", "Hugo", "Louis", "Mehdi", "Théo", "Antoine", "Lucas", "Jules", "Omar", "Victor", "Sami" }

-- single reactions, by kind then by role ("any" = fallback)
Lines.react = {
	down = {
		any = { "Ne tirez pas !", "Je suis à terre, je suis à terre !", "Je ne bouge plus !", "Prenez ce que vous voulez !", "S'il vous plaît...", "Je fais ce que vous dites !" },
		Manager = { "Pas la peine de violence, monsieur !", "Je coopère, je coopère !", "Mon badge... non, ne le prenez pas !" },
		Teller = { "J'ai une famille !", "Je n'ai appuyé sur rien, promis !", "Les caisses sont derrière moi !" },
	},
	handsUp = {
		any = { "Pitié !", "Ne tirez pas !", "Doucement, doucement !", "Je n'ai rien fait !" },
	},
	tied = {
		any = { "Mmmph !", "Aïe, ça serre !", "Pas trop fort...", "Mmmh !" },
	},
	panic = {
		any = { "AAAAH !", "Au secours !", "Il y a un braquage !", "Sortons d'ici !", "Appelez la police !" },
	},
	escapeStaff = { any = { "Au secours ! ALARME !", "Il y a des braqueurs ! Appelez la police !", "À l'aide !" } },
	escapeCustomer = { any = { "Je me sauve !", "Je ne reste pas ici !", "Laissez-moi sortir !" } },
	warnEscape = { any = { "(il jette un oeil vers la porte)", "Il ne regarde plus...", "Je vais filer...", "Psst... la porte..." } },
	shock = { any = { "Oh mon dieu !", "Qu'est-ce qui se passe ?", "Ils sont armés !", "C'est un braquage ?!", "Non non non..." } },
	witnessDeath = { any = { "Il l'a tué !", "Quelqu'un est tombé !", "Du sang !", "AAAH ! Il est mort !" } },
	cardGrab = { any = { "He ! Vos mains !", "Mon badge !" } },
	notice = { any = { "Hé, vous ! C'est interdit ici !", "Vous ne pouvez pas être là !", "Monsieur, le personnel uniquement !" } },
	alarmStaff = { any = { "ALARME !", "J'ai appuyé sur le bouton !", "Code rouge, code rouge !" } },
}

-- exchanges: { lines = { a, b, a, b ... } } between two roles (a speaks first)
Lines.chat = {
	customer_customer = {
		{ "Il fait une chaleur aujourd'hui !", "Et dire qu'il pleuvait hier.", "Moi je ne sors plus sans parapluie." },
		{ "Vous attendez depuis longtemps ?", "Dix minutes, pas plus.", "Ils ne sont que quatre guichets...", "Toujours la même histoire !" },
		{ "Vous avez vu le nouveau café en face ?", "Celui avec les gâteaux ? Délicieux !", "J'y vais dès que j'ai fini ici." },
		{ "Mon fils veut une moto...", "À son âge ? Jamais de la vie !", "C'est ce que je lui dis !" },
		{ "Ils ont encore changé les horaires.", "Je n'y comprends plus rien.", "Moi non plus, ma foi." },
		{ "Vous connaissez le casier 167 ?", "Celui du fond ? Mystère...", "On dit qu'il y a des choses précieuses dedans." },
		{ "Belle montre !", "Merci, un cadeau de ma tante.", "Elle a du goût, votre tante." },
	},
	teller_customer = {
		{ "Bonjour ! Que puis-je faire pour vous ?", "Je voudrais déposer ce chèque.", "Très bien, signez ici s'il vous plaît.", "Voilà.", "Parfait. Bonne journée !", "Merci, à vous aussi !" },
		{ "Bonjour, je vous écoute.", "Un retrait de deux cents, s'il vous plaît.", "Pièce d'identité ?", "Tenez.", "Voilà vos billets, comptez-les.", "C'est bon. Merci !" },
		{ "Bonjour monsieur, vous avez rendez-vous ?", "Non, juste un virement.", "Je m'en occupe tout de suite.", "Merci, vous êtes rapide." },
		{ "Bonjour madame, c'est pour quoi ?", "Ma carte est bloquée...", "Voyons ça. Vous avez essayé trois fois le code ?", "Peut-être quatre...", "Je vous en commande une nouvelle." },
	},
	teller_teller = {
		{ "Tu as vu la file ?", "Ne m'en parle pas...", "Pause café dans vingt minutes ?", "Si on survit jusque-là !" },
		{ "Le clavier de la porte du coffre... toujours pas mis à jour.", "Le technicien l'a promis cent fois.", "Rien ne change ici." },
		{ "Tu finis à quelle heure ?", "Dix-sept heures.", "Chanceuse. Moi dix-huit." },
		{ "Ton imprimante marche ?", "Elle bourre encore.", "Tape dessus, ça marche à tous les coups." },
		{ "Il a l'air de mauvais poil, le directeur.", "Il est toujours au téléphone.", "Au moins il nous laisse tranquilles." },
	},
	guard_teller = {
		{ "Tout va bien, mademoiselle ?", "Oui, merci. Une journée calme.", "Tant mieux, tant mieux." },
		{ "Vous voulez un café ?", "Je ne peux pas quitter mon poste...", "Je vous en rapporte un en patrouillant." },
		{ "Rien de suspect de votre côté ?", "Juste un monsieur avec un grand sac.", "Je garde l'oeil dessus." },
	},
	guard_customer = {
		{ "Bonjour madame.", "Bonjour monsieur l'agent.", "Bonne journée à vous." },
		{ "Excusez-moi, les toilettes ?", "Au fond du hall, à gauche.", "Merci beaucoup !" },
		{ "Vous cherchez quelque chose ?", "Le guichet trois.", "C'est juste là, devant vous." },
	},
	manager_teller = {
		{ "Tout se passe bien au guichet ?", "Oui monsieur, le rythme est correct.", "N'oubliez pas le rapport de caisse.", "C'est prêt, monsieur." },
		{ "Qui a laissé la porte du fond ouverte ?", "Ce n'est pas moi, monsieur !", "Bien. Que ça ne se reproduise pas." },
		{ "Rappel : la carte niveau 5 reste sur moi.", "On s'en souvient, monsieur.", "Je ne la quitte JAMAIS." },
	},
	manager_guard = {
		{ "Vigile, tout est calme ?", "Calme plat, monsieur.", "Restez vigilant. Les temps sont durs.", "Compris." },
		{ "Vérifiez la porte de service tout à l'heure.", "Entendu, monsieur.", "Et surveillez le client au sac gris.", "Je m'en occupe." },
	},
	manager_customer = {
		{ "Bonjour, je suis le directeur. Un souci ?", "Non non, tout va bien, merci.", "N'hésitez pas à demander." },
	},
	guard_guard = {
		{ "Rien à signaler ?", "Rien. Comme d'habitude.", "Un jour il se passera quelque chose...", "Ne porte pas la poisse !" },
	},
	police_police = {
		{ "Reste à couvert.", "Compris.", "On avance par bonds.", "Reçu." },
	},
}

-- idle monologues (phone calls, grumbling), by role
Lines.solo = {
	Customer = { "Allô ? Oui chérie, je suis à la banque...", "J'ai oublié mon code, encore...", "Dix minutes pour un chèque, franchement.", "Où est passé mon stylo ?", "*soupir*", "Je dois penser à acheter du pain." },
	Teller = { "Encore un chèque sans date...", "Il me faut une pause.", "Où est le tampon ?", "Sept cent douze... sept cent treize...", "*tap tap tap*" },
	Manager = { "Allô ? Oui, le coffre est sécurisé.", "Ces travaux de toiture vont me tuer.", "Seul moi détiens la carte niveau 5, ne vous en faites pas !" },
	Guard = { "Rien à signaler.", "Mes pieds...", "Poste calme, poste calme.", "Je jurerais avoir vu quelqu'un..." },
}

-- combat calls (police radio style)
Lines.combat = {
	spotted = { "Contact ! Dans le hall !", "Je le vois !", "Suspect en vue !", "Il est là, il est là !" },
	cover = { "Je prends position !", "À couvert !", "Couvrez-moi !", "Je tiens cette position." },
	advance = { "On avance !", "Je progresse !", "Bond suivant !", "Je monte à gauche !" },
	flank = { "Je contourne par la droite !", "Je le prends de flanc !", "Je passe par le côté !" },
	reload = { "Je recharge !", "Rechargement, couvrez !", "À sec !" },
	hit = { "Je suis touché !", "AÏE ! Touché !", "Il m'a eu !" },
	down = { "Agent à terre !", "Un homme à terre !", "On a perdu un agent !" },
	lost = { "Je l'ai perdu !", "Plus de contact visuel.", "Où est-il passé ?", "Il se replie !" },
	search = { "Fouillez le secteur !", "Il doit être par là.", "Ratissez la zone !" },
	coverfire = { "Je vous couvre !", "Feu de couverture !", "Go, je le tiens !" },
	rush = { "Je fonce, couvrez-moi !", "Go go go !", "Je l'aborde !" },
	suppress = { "Feu de suppression !", "Je le fixe !" },
	hostage = { "Il y a des otages !", "Attention aux civils !" },
	swat = { "Équipe d'assaut en position !", "SWAT, on entre !", "Dernière sommation... plus de sommation !" },
	police = { "Police ! Posez vos armes !", "Personne ne bouge !", "Sortez les mains en l'air !" },
}

function Lines.pick(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

function Lines.react_(kind: string, role: string): string
	local k = (Lines.react :: any)[kind]
	local l = (k and (k[role] or k.any)) :: { string }?
	if not l then
		return "..."
	end
	-- role-specific lines are mixed with the generic ones
	if k[role] and k.any and rng:NextNumber() < 0.45 then
		l = k.any
	end
	return l[rng:NextInteger(1, #l)]
end

function Lines.exchange(a: string, b: string): { string }?
	local keys = { string.lower(a) .. "_" .. string.lower(b) }
	for _, key in keys do
		local pool = (Lines.chat :: any)[key]
		if pool then
			return pool[rng:NextInteger(1, #pool)]
		end
	end
	return nil
end

function Lines.solo_(role: string): string?
	local l = (Lines.solo :: any)[role] :: { string }?
	return if l then l[rng:NextInteger(1, #l)] else nil
end

return Lines
