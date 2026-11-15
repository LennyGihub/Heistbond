--!strict
-- Plays what the server asks for: body animations on any player's character ("Act", userId, name,
-- target) and the acting player's own cinematics ("Cine", kind, spot). Also the keypad typing pose
-- while the hack mini-game runs (shared.hackAnim(on) is called by HeistClient).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local Net = require(Heist:WaitForChild("Net"))
local AA = require(Heist:WaitForChild("ActionAnim"))
local Cine = require(Heist:WaitForChild("Cine"))
local Cinematics = require(Heist:WaitForChild("Cinematics"))
local CineRides = require(Heist:WaitForChild("CineRides"))

local player = Players.LocalPlayer

Net.event().OnClientEvent:Connect(function(kind: any, a: any, b: any, c: any)
	if kind == "Act" and type(a) == "number" and type(b) == "string" then
		local pl = Players:GetPlayerByUserId(a)
		local char = pl and pl.Character
		if char and b == "_stop" then
			AA.stopAll(char)
		elseif char then
			AA.play(char, b, { target = if typeof(c) == "CFrame" then c else nil })
		end
	elseif (kind == "Intro" or kind == "Escape" or kind == "VanLeave") and type(a) == "table" then
		local fn = if kind == "Intro" then CineRides.intro elseif kind == "Escape" then CineRides.escape else CineRides.vanLeave
		task.spawn(function()
			local ok, err = pcall(fn, a)
			if not ok then
				warn("[Cine]", kind, err)
				pcall(function()
					game:GetService("RunService"):UnbindFromRenderStep("IntroVan")
					game:GetService("RunService"):UnbindFromRenderStep("EscapeRide")
				end)
				Cine.finish(0.3)
			end
		end)
	elseif kind == "Cine" and type(a) == "string" then
		local fn = (Cinematics :: any)[a]
		if type(fn) == "function" then
			task.spawn(function()
				local ok, err = pcall(fn, b, c)
				if not ok then
					warn("[Cine]", a, err)
					Cine.finish(0.3)
				end
			end)
		end
	end
end)

local hackHandle: { stop: () -> () }? = nil
;(shared :: any).hackAnim = function(on: boolean)
	if hackHandle then
		hackHandle.stop()
		hackHandle = nil
	end
	local char = player.Character
	if on and char then
		hackHandle = AA.play(char, "hackType")
	end
end
