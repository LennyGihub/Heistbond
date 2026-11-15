--!strict
-- NPC voices. Roblox has no speech synthesis, so each NPC "talks" Animal-Crossing style: a short blip per
-- syllable, pitched by the vowel, with its own base pitch, speed, timbre and wobble. The server picks a
-- voice index per NPC (model attribute "Voice") and fires ("Say", model, text, mood) at the clients; the
-- client script NpcVoice draws the speech bubble and plays the blips.
export type Voice = {
	name: string,
	pitch: number, -- base PlaybackSpeed of the blip
	rate: number, -- syllables per second multiplier
	base: string, -- Sfx id used as the blip ("pop", "key", "boing", "beep")
	wobble: number, -- random pitch drift per syllable
	radio: boolean, -- police radio filter
	deep: boolean?, -- low voice (men, guards)
}

local Voices = {}

Voices.list = {
	-- 1-6: high / medium voices (tellers, customers)
	{ name = "Fluette", pitch = 1.95, rate = 1.15, base = "pop", wobble = 0.10, radio = false },
	{ name = "Pimbêche", pitch = 1.7, rate = 0.95, base = "key", wobble = 0.05, radio = false },
	{ name = "Douce", pitch = 1.5, rate = 0.85, base = "pop", wobble = 0.06, radio = false },
	{ name = "Pétillante", pitch = 1.35, rate = 1.25, base = "boing", wobble = 0.12, radio = false },
	{ name = "Posée", pitch = 1.2, rate = 0.9, base = "key", wobble = 0.04, radio = false },
	{ name = "Mezzo", pitch = 1.05, rate = 1.0, base = "pop", wobble = 0.08, radio = false },
	-- 7-12: lower voices
	{ name = "Jovial", pitch = 0.92, rate = 1.1, base = "boing", wobble = 0.09, radio = false, deep = true },
	{ name = "Bonhomme", pitch = 0.82, rate = 0.95, base = "pop", wobble = 0.05, radio = false, deep = true },
	{ name = "Grave", pitch = 0.7, rate = 0.85, base = "key", wobble = 0.04, radio = false, deep = true },
	{ name = "Basse", pitch = 0.6, rate = 0.8, base = "pop", wobble = 0.03, radio = false, deep = true },
	{ name = "Tonnerre", pitch = 0.52, rate = 0.75, base = "boing", wobble = 0.03, radio = false, deep = true },
	{ name = "Nasillard", pitch = 1.12, rate = 1.3, base = "beep", wobble = 0.07, radio = false },
	-- 13-16: cops on the radio
	{ name = "Agent A", pitch = 0.88, rate = 1.15, base = "key", wobble = 0.05, radio = true, deep = true },
	{ name = "Agent B", pitch = 1.05, rate = 1.05, base = "pop", wobble = 0.05, radio = true },
	{ name = "Agent C", pitch = 0.74, rate = 1.0, base = "key", wobble = 0.04, radio = true, deep = true },
	{ name = "Agent D", pitch = 1.22, rate = 1.2, base = "beep", wobble = 0.05, radio = true },
} :: { Voice }

-- groups the server draws from (indices into the list)
Voices.groups = {
	Teller = { 1, 2, 3, 4, 5, 6 },
	Customer = { 1, 2, 3, 4, 5, 6, 7, 8, 12 },
	CustomerF = { 1, 2, 3, 4, 5, 6 },
	CustomerM = { 7, 8, 12, 9, 10, 11 },
	Manager = { 9, 10 },
	Guard = { 7, 8, 9, 11 },
	Police = { 13, 14, 15, 16 },
	Swat = { 13, 15, 14, 16 },
}

-- the player's own shouts
Voices.player = { name = "Joueur", pitch = 0.8, rate = 1.1, base = "pop", wobble = 0.06, radio = false, deep = true } :: Voice

-- soft tonal blips (marimba / pluck notes from the Creator Store) instead of percussive pops
Voices.bases = {
	pop = "rbxassetid://97005650217537", -- marimba
	boing = "rbxassetid://124909201153662", -- marimba (rounder)
	key = "rbxassetid://8206935822", -- pluck
	beep = "rbxassetid://126130663615387", -- cartoon pluck
}

-- vowel -> pitch multiplier: notes of a major pentatonic scale, so the babble stays pleasant
Voices.vowel = { a = 1.0, e = 1.25, i = 1.5, o = 0.84, u = 0.75, y = 1.125 }

return Voices
