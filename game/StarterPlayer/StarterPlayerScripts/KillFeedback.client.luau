--!strict
-- Kill confirmation: WeaponServer fires WeaponRemotes.Kill to the shooter when a shot kills someone;
-- a short white flash covers the screen.
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
