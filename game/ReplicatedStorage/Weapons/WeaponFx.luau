--!strict
-- Client-side gun effects shared by the shooter (GunClient) and everyone else (WeaponFxListener).
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.WeaponConfig)

local Fx = {}

local fxFolder: Folder? = nil
local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "WeaponFx"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function playSound(parent: Instance, id: string, volume: number, pitch: number, range: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = range
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

function Fx.sound(tool: Tool, kind: string, volumeScale: number?)
	local cfg = Config[tool.Name]
	local handle = tool:FindFirstChild("Handle")
	if not cfg or not handle then
		return
	end
	local v = volumeScale or 1
	local snd = cfg.Sounds :: any
	if kind == "Fire" then
		-- layered: soft suppressed thump + crisp action click, slight random pitch so auto fire isn't robotic
		if tool:GetAttribute("Suppressed") == false then
			-- heist gun without a silencer: a loud crack heard far away
			playSound(handle, "rbxassetid://3821795742", 0.8 * v, 1.35 + math.random() * 0.1, 400)
		else
			playSound(handle, snd.Fire, 0.9 * v, 0.94 + math.random() * 0.1, cfg.SoundRange)
		end
		playSound(handle, snd.Mech, 0.35 * v, 1.25 + math.random() * 0.1, cfg.SoundRange * 0.5)
	elseif snd[kind] then
		playSound(handle, snd[kind], 0.7 * v, 1, cfg.SoundRange * 0.5)
	end
end

local function emitterFor(att: Attachment): ParticleEmitter
	local pe = att:FindFirstChild("Smoke") :: ParticleEmitter?
	if pe then
		return pe
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	e.Enabled = false
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(15, 15)
	e.EmissionDirection = Enum.NormalId.Front
	e.LightInfluence = 1
	e.Parent = att
	local l = Instance.new("PointLight")
	l.Name = "Flash"
	l.Color = Color3.fromRGB(255, 190, 120)
	l.Range = 6
	l.Brightness = 0
	l.Shadows = false
	l.Parent = att
	return e
end

function Fx.muzzle(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	local att = handle and handle:FindFirstChild("Muzzle") :: Attachment?
	if not att then
		return
	end
	local e = emitterFor(att)
	e:Emit(2)
	local light = att:FindFirstChild("Flash") :: PointLight?
	if light then
		light.Brightness = 1.6 -- suppressed: small, dim flash
		task.delay(0.04, function()
			light.Brightness = 0
		end)
	end
end

function Fx.tracer(from: Vector3, to: Vector3)
	local dist = (to - from).Magnitude
	if dist < 1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 225, 160)
	p.Transparency = 0.55
	p.Size = Vector3.new(0.035, 0.035, math.min(dist, 14))
	-- a short streak that starts a little in front of the muzzle and travels to the target
	local dir = (to - from).Unit
	p.CFrame = CFrame.lookAt(from + dir * (p.Size.Z / 2 + 1), to)
	p.Parent = folder()
	local travel = math.max(dist - p.Size.Z, 0)
	local t = math.clamp(travel / 900, 0.03, 0.25)
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to - dir * (p.Size.Z / 2), to + dir),
		Transparency = 0.85,
	}):Play()
	Debris:AddItem(p, t + 0.02)
end

function Fx.impact(pos: Vector3, normal: Vector3, hitCharacter: boolean)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.new(0.1, 0.1, 0.1)
	a.CFrame = CFrame.lookAt(pos, pos + normal)
	a.Parent = folder()
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.EmissionDirection = Enum.NormalId.Front
	e.SpreadAngle = Vector2.new(35, 35)
	e.Speed = NumberRange.new(6, 12)
	e.Drag = 6
	e.Lifetime = NumberRange.new(0.12, 0.25)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	if hitCharacter then
		e.Color = ColorSequence.new(Color3.fromRGB(150, 20, 20))
		e.LightEmission = 0
	else
		e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120))
		e.LightEmission = 1
	end
	e.Parent = a
	e:Emit(hitCharacter and 6 or 8)
	Debris:AddItem(a, 0.5)

	if not hitCharacter then
		-- small bullet mark flush with the surface, fades out
		local mark = Instance.new("Part")
		mark.Shape = Enum.PartType.Cylinder
		mark.Anchored = true
		mark.CanCollide = false
		mark.CanQuery = false
		mark.CanTouch = false
		mark.CastShadow = false
		mark.Color = Color3.fromRGB(25, 25, 25)
		mark.Material = Enum.Material.SmoothPlastic
		mark.Size = Vector3.new(0.02, 0.14, 0.14)
		-- cylinder axis is X: point it along the normal
		mark.CFrame = CFrame.lookAt(pos + normal * 0.01, pos + normal) * CFrame.Angles(0, math.rad(90), 0)
		mark.Parent = folder()
		TweenService:Create(mark, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 6), {
			Transparency = 1,
		}):Play()
		Debris:AddItem(mark, 10.5)
	end
end

return Fx
