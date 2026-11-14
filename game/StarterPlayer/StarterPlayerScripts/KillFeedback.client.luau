--!strict
-- Hit feedback on screen:
--  * kill confirmation: WeaponServer fires WeaponRemotes.Kill to the shooter when a shot kills someone;
--    a short white flash covers the screen
--  * getting hit: whenever your health drops, a short red flash (stronger for bigger hits)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("WeaponRemotes")
local KillRemote = remotes:WaitForChild("Kill") :: RemoteEvent

local FLASH_START = 0.6 -- transparency at the flash's peak (1 = invisible)
local FLASH_TIME = 0.3 -- seconds to fade out

local gui = Instance.new("ScreenGui")
gui.Name = "KillFlash"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BorderSizePixel = 0
flash.BackgroundTransparency = 1
flash.Parent = gui

local tween: Tween? = nil
KillRemote.OnClientEvent:Connect(function()
	if tween then
		tween:Cancel()
	end
	flash.BackgroundTransparency = FLASH_START
	local t = TweenService:Create(flash, TweenInfo.new(FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween = t
	t:Play()
end)

-- getting hit: red flash
local hurt = Instance.new("Frame")
hurt.Name = "Hurt"
hurt.Size = UDim2.fromScale(1, 1)
hurt.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
hurt.BorderSizePixel = 0
hurt.BackgroundTransparency = 1
hurt.Parent = gui
local hurtTween: Tween? = nil

local function watch(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		local lost = last - h
		last = h
		if lost <= 0 then
			return
		end
		if hurtTween then
			hurtTween:Cancel()
		end
		hurt.BackgroundTransparency = math.clamp(0.85 - lost / 60, 0.55, 0.85)
		local t = TweenService:Create(hurt, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		hurtTween = t
		t:Play()
	end)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end
