--!strict
-- Weapon stats + sounds. Keyed by the Tool's name. Change sound ids here to swap them.
export type Sounds = {
	Fire: string, -- main suppressed shot
	Mech: string, -- bolt/action click layered on each shot
	Reload: string,
	Empty: string, -- dry fire click
	Equip: string,
}

export type Weapon = {
	Damage: number,
	HeadMultiplier: number,
	RPM: number, -- rounds per minute (automatic)
	MagSize: number,
	Reserve: number, -- spare rounds on spawn
	Range: number,
	HipSpread: number, -- degrees
	AimSpread: number, -- degrees while aiming
	ReloadTime: number,
	RecoilUp: number, -- degrees of camera kick per shot
	RecoilSide: number,
	AimFov: number,
	AimWalkSpeed: number,
	SoundRange: number, -- how far other players hear it (suppressed = short)
	Sounds: Sounds,
	Label: string?, -- name on the ammo HUD (default: "<tool name>  SUPPRESSED")
	-- aiming looks through a scope (GunClient): field of view range for the mouse-wheel zoom, the
	-- starting zoom, and the overlay picture
	Scope: { MinFov: number, MaxFov: number, StartFov: number, Image: string }?,
}

local Config: { [string]: Weapon } = {
	M4A1 = {
		Damage = 26,
		HeadMultiplier = 2,
		RPM = 780,
		MagSize = 30,
		Reserve = 120,
		Range = 600,
		HipSpread = 1.4,
		AimSpread = 0.25,
		ReloadTime = 2.1,
		RecoilUp = 0.75,
		RecoilSide = 0.3,
		AimFov = 50,
		AimWalkSpeed = 10,
		SoundRange = 110,
		Sounds = {
			Fire = "rbxassetid://90908536337383",
			Mech = "rbxassetid://72166668675269",
			Reload = "rbxassetid://122308398024498",
			Empty = "rbxassetid://107122763048148",
			Equip = "rbxassetid://78157229382345",
		},
	},
	-- light pistol (heist loadout): built from the M4A1 rig with a blocky pistol body
	Pistol = {
		Damage = 20,
		HeadMultiplier = 2.2,
		RPM = 420,
		MagSize = 15,
		Reserve = 60,
		Range = 350,
		HipSpread = 1.8,
		AimSpread = 0.45,
		ReloadTime = 1.5,
		RecoilUp = 1.1,
		RecoilSide = 0.35,
		AimFov = 58,
		AimWalkSpeed = 12,
		SoundRange = 90,
		Label = "PISTOLET",
		Sounds = {
			Fire = "rbxassetid://90908536337383",
			Mech = "rbxassetid://72166668675269",
			Reload = "rbxassetid://122308398024498",
			Empty = "rbxassetid://107122763048148",
			Equip = "rbxassetid://78157229382345",
		},
	},
	-- bolt-action sniper: no sight at the hip (and wild there), a zooming scope when aiming
	Sniper = {
		Damage = 100,
		HeadMultiplier = 2,
		RPM = 40, -- one shot every 1.5 s (bolt)
		MagSize = 5,
		Reserve = 25,
		Range = 2000,
		HipSpread = 8,
		AimSpread = 0,
		ReloadTime = 3.2,
		RecoilUp = 4,
		RecoilSide = 1,
		AimFov = 40,
		AimWalkSpeed = 4,
		SoundRange = 400,
		Label = "SNIPER RIFLE",
		Scope = { MinFov = 2.5, MaxFov = 20, StartFov = 9, Image = "rbxassetid://1598134910" },
		Sounds = {
			Fire = "rbxassetid://3821795742", -- the Roblox weapons kit sniper
			Mech = "rbxassetid://72166668675269",
			Reload = "rbxassetid://3821795168",
			Empty = "rbxassetid://107122763048148",
			Equip = "rbxassetid://78157229382345",
		},
	},
}

return Config
