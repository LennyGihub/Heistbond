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
}

return Config
