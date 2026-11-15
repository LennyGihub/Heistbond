--!strict
-- Speech bubbles and voice blips for the NPCs. The server fires ("Say", model, text, mood) on the heist
-- event; here the text types itself out above the speaker's head and a blip plays for each syllable.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local Net = require(Heist:WaitForChild("Net"))
local Sfx = require(Heist:WaitForChild("Sfx"))
local Voices = require(Heist:WaitForChild("Voices"))

local RGB = Color3.fromRGB
local rng = Random.new()
local MAX_DIST = 85

local MOODS: { [string]: { text: Color3, bg: Color3, vol: number, pitch: number, shake: number } } = {
	normal = { text = RGB(27, 42, 53), bg = RGB(250, 250, 250), vol = 0.5, pitch = 1, shake = 0 },
	scared = { text = RGB(20, 70, 140), bg = RGB(220, 238, 255), vol = 0.55, pitch = 1.18, shake = 1 },
	scream = { text = RGB(200, 20, 20), bg = RGB(255, 232, 228), vol = 0.9, pitch = 1.3, shake = 2 },
	angry = { text = RGB(150, 50, 0), bg = RGB(255, 238, 205), vol = 0.8, pitch = 0.9, shake = 1 },
	whisper = { text = RGB(90, 90, 96), bg = RGB(232, 232, 236), vol = 0.22, pitch = 0.95, shake = 0 },
	radio = { text = RGB(190, 255, 200), bg = RGB(24, 34, 30), vol = 0.6, pitch = 1, shake = 0 },
}

local speaking: { [Model]: { gui: BillboardGui, stop: boolean } } = {}

local function blipSound(parent: Instance, voice: Voices.Voice): Sound
	local s = Instance.new("Sound")
	s.SoundId = Sfx.ID[voice.base] or Sfx.ID.pop
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 60
	s.Parent = parent
	if voice.radio then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = -40
		eq.MidGain = 6
		eq.HighGain = -25
		eq.Parent = s
		local d = Instance.new("DistortionSoundEffect")
		d.Level = 0.35
		d.Parent = s
	end
	return s
end

local function speak(model: Model, text: string, moodName: string)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head or not head:IsDescendantOf(workspace) then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and (head.Position - cam.CFrame.Position).Magnitude > MAX_DIST then
		return
	end
	local mood = MOODS[moodName] or MOODS.normal
	local idx = model:GetAttribute("Voice")
	local voice: Voices.Voice = if type(idx) == "number" and Voices.list[idx] then Voices.list[idx] else Voices.player
	local shift = model:GetAttribute("VoiceShift")
	local shiftN: number = if type(shift) == "number" then shift else 1
	if voice.radio and moodName == "normal" then
		mood = MOODS.radio
	end

	local prev = speaking[model]
	if prev then
		prev.stop = true
		prev.gui:Destroy()
	end

	local lines = math.max(1, math.ceil(#text * 8.2 / 210))
	local w = math.clamp(#text * 8.2 + 30, 90, 240)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Speech"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(w, lines * 19 + 16)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DIST
	gui.Parent = head
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = mood.bg
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local st = Instance.new("UIStroke")
	st.Thickness = 2.5
	st.Color = RGB(27, 42, 53)
	st.Parent = bg
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -14, 1, -8)
	label.Position = UDim2.fromOffset(7, 4)
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.TextWrapped = true
	label.TextSize = 16
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextColor3 = mood.text
	label.Parent = bg
	local entry = { gui = gui, stop = false }
	speaking[model] = entry

	task.spawn(function()
		local pool = { blipSound(head, voice), blipSound(head, voice), blipSound(head, voice) }
		local turn = 0
		local perChar = 1 / (24 * voice.rate)
		local base = gui.StudsOffset
		for i = 1, #text do
			if entry.stop or not gui.Parent then
				break
			end
			label.MaxVisibleGraphemes = i
			local ch = string.lower(string.sub(text, i, i))
			local vowel = Voices.vowel[ch]
			if (vowel or i % 3 == 0) and ch ~= " " then
				turn = turn % #pool + 1
				local s = pool[turn]
				s:Stop()
				s.TimePosition = 0
				s.Volume = mood.vol * (0.8 + rng:NextNumber() * 0.4)
				s.PlaybackSpeed = voice.pitch * shiftN * mood.pitch * (vowel or 1.0) * (1 + (rng:NextNumber() - 0.5) * 2 * voice.wobble)
				s:Play()
				task.delay(0.13 / voice.rate, function()
					s:Stop()
				end)
			end
			if mood.shake > 0 then
				gui.StudsOffset = base + Vector3.new(rng:NextNumber(-0.06, 0.06) * mood.shake, rng:NextNumber(-0.05, 0.05) * mood.shake, 0)
			end
			task.wait(if ch == " " then perChar * 0.6 else perChar)
		end
		gui.StudsOffset = base
		label.MaxVisibleGraphemes = -1
		for _, s in pool do
			Debris:AddItem(s, 0.5)
		end
		if not entry.stop then
			task.wait(1.0 + #text * 0.035)
			if not entry.stop then
				gui:Destroy()
				if speaking[model] == entry then
					speaking[model] = nil
				end
			end
		end
	end)
end

Net.event().OnClientEvent:Connect(function(kind: any, model: any, text: any, mood: any)
	if kind == "Say" and typeof(model) == "Instance" and model:IsA("Model") and type(text) == "string" then
		speak(model, text, if type(mood) == "string" then mood else "normal")
	end
end)

local _ = Players
