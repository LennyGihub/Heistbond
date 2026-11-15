--!strict
-- Plays other players' gun effects (sound, flash, tracer, impact) and reload animation that the server relays.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Weapons = ReplicatedStorage:WaitForChild("Weapons")
local Config = require(Weapons:WaitForChild("WeaponConfig"))
local Fx = require(Weapons:WaitForChild("WeaponFx"))
local GunAnim = require(Weapons:WaitForChild("GunAnim"))
local GunPose = require(Weapons:WaitForChild("GunPose"))
local Shot = ReplicatedStorage:WaitForChild("WeaponRemotes"):WaitForChild("Shot") :: RemoteEvent

local function playReload(tool: Tool)
	local cfg = Config[tool.Name]
	if not cfg or GunAnim.isReloading(tool) then
		return
	end
	GunAnim.startReload(tool, cfg.ReloadTime)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local char = tool.Parent
		local handle = tool:FindFirstChild("Handle")
		local weld = handle and handle:FindFirstChild("GunHold") :: Weld?
		local torso = char and char:IsA("Model") and GunPose.torsoFor(char)
		if not weld or not torso then
			GunAnim.stop(tool)
			conn:Disconnect()
			return
		end
		-- rebuild the server's pose for this gun, then add the reload tilt on top
		local aim = tool:GetAttribute("PoseAim") == true and 1 or 0
		local pitch = (tool:GetAttribute("PosePitch") :: number?) or 0
		local yaw = (tool:GetAttribute("PoseYaw") :: number?) or 0
		local tilt = GunAnim.step(tool, torso)
		weld.C0 = GunPose.cframe(torso.Size, aim, pitch, yaw) * tilt
		if not GunAnim.isReloading(tool) then
			conn:Disconnect()
		end
	end)
end

Shot.OnClientEvent:Connect(function(tool: any, kind: any, hitPos: any, normal: any, hitChar: any)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return
	end
	if kind == "Reload" then
		playReload(tool) -- GunAnim plays every step's sound
		return
	end
	if kind ~= "Fire" or typeof(hitPos) ~= "Vector3" or typeof(normal) ~= "Vector3" then
		return
	end
	Fx.sound(tool, "Fire")
	Fx.muzzle(tool)
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle") :: Attachment?
	if muzzle then
		Fx.tracer(muzzle.WorldPosition, hitPos)
	end
	Fx.impact(hitPos, normal, hitChar == true)
end)
