--!strict
-- Studio-only hooks for scripted playtests (tools/studio.py luau Client ...). A test script runs in its
-- own VM and the Studio test tool resets the camera type when its call returns, so tests steer the
-- real client through player attributes instead:
--   TestCam (CFrame)      hold the camera there (Scriptable) until TestCam is cleared
--   TestCamFollow (Vector3) camera at this offset from the character, looking at its chest
--   TestCall (string)     run shared.testCalls[name]() in the real client (set to "" after)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local player = Players.LocalPlayer
;(shared :: any).testCalls = (shared :: any).testCalls or {}

RunService:BindToRenderStep("HeistTestCam", Enum.RenderPriority.Last.Value, function()
	local cf = player:GetAttribute("TestCam")
	local follow = player:GetAttribute("TestCamFollow")
	local cam = workspace.CurrentCamera
	if typeof(cf) == "CFrame" then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cf
	elseif typeof(follow) == "Vector3" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = CFrame.lookAt(root.CFrame:PointToWorldSpace(follow), root.Position + Vector3.new(0, 0.8, 0))
		end
	end
end)

local wasHeld = false
player:GetAttributeChangedSignal("TestCam"):Connect(function()
	local held = player:GetAttribute("TestCam") ~= nil
	if wasHeld and not held then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end
	wasHeld = held
end)
player:GetAttributeChangedSignal("TestCamFollow"):Connect(function()
	if player:GetAttribute("TestCamFollow") == nil and player:GetAttribute("TestCam") == nil then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end
end)

player:GetAttributeChangedSignal("TestCall"):Connect(function()
	local name = player:GetAttribute("TestCall")
	if type(name) ~= "string" or name == "" then
		return
	end
	player:SetAttribute("TestCall", "")
	local fn = (shared :: any).testCalls[name]
	if fn then
		task.spawn(fn)
	else
		warn("[TestHooks] no test call", name)
	end
end)
