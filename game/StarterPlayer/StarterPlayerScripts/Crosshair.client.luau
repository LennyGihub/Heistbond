--!strict
-- Crosshair: a small white dot (dark outline) at the centre of the screen while a gun is in hand.
-- Shots go where the screen centre points (GunClient), so the dot is exactly the aim point. Hidden
-- while aiming down the sight in first person (the sight has its own reticle).
-- Behind low cover CoverClient raises the camera, which puts the dot above the wall for blind fire.
-- Guns with the tool attribute NoCrosshair (the sniper) show no dot.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.IgnoreGuiInset = true -- centre of the whole viewport, same as the camera ray GunClient shoots along
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.new(1, 1, 1)
dot.BorderSizePixel = 0
dot.Visible = false
dot.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = dot
local outline = Instance.new("UIStroke")
outline.Color = Color3.new(0, 0, 0)
outline.Thickness = 1.5
outline.Transparency = 0.35
outline.Parent = dot

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local cam = workspace.CurrentCamera
	local head = char and char:FindFirstChild("Head") :: BasePart?
	local tool = char and char:FindFirstChildOfClass("Tool")
	-- guns marked NoCrosshair (the sniper) have no sight at the hip; their scope has its own reticle
	local armed = tool ~= nil and tool:GetAttribute("NoCrosshair") ~= true
	local firstPerson = head ~= nil and cam ~= nil and (cam.CFrame.Position - head.Position).Magnitude < 1.5
	local sighted = firstPerson and char ~= nil and char:GetAttribute("Aiming") == true
	dot.Visible = armed and not sighted
end)
