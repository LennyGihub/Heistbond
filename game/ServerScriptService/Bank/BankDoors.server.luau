--!strict
-- BankDoors: every Model tagged "BankDoor" (built by ServerStorage.Builders.AtlasBankBuilder) opens and
-- closes with its ProximityPrompt. Each child Model named "Leaf" carries attributes Closed (CFrame,
-- hinge pivot when closed) and OpenAngle (radians around the hinge). Door attributes:
--   Open (bool, set by this script), Locked (bool, refuse to open), TweenTime (seconds, default 0.6).
-- Other scripts can open/close a door by setting its "WantOpen" attribute.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

type LeafInfo = { closed: CFrame, open: CFrame, value: CFrameValue }

local function setup(door: Instance)
	if not door:IsA("Model") or door:GetAttribute("DoorReady") then
		return
	end
	local prompt = door:FindFirstChild("DoorPrompt", true)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		return
	end
	door:SetAttribute("DoorReady", true)
	local leaves: { LeafInfo } = {}
	for _, c in door:GetChildren() do
		if c:IsA("Model") and c.Name == "Leaf" then
			local closed = c:GetAttribute("Closed")
			local ang = c:GetAttribute("OpenAngle")
			if typeof(closed) == "CFrame" and type(ang) == "number" then
				local v = Instance.new("CFrameValue")
				v.Value = closed
				local leafModel = c
				v.Changed:Connect(function(cf: CFrame)
					leafModel:PivotTo(cf)
				end)
				table.insert(leaves, { closed = closed, open = closed * CFrame.Angles(0, ang, 0), value = v })
			end
		end
	end
	local isOpen = false
	local busy = false
	local function set(open: boolean)
		if busy or open == isOpen then
			return
		end
		if open and door:GetAttribute("Locked") then
			return
		end
		busy = true
		isOpen = open
		door:SetAttribute("Open", open)
		prompt.ActionText = if open then "Close" else "Open"
		local t = door:GetAttribute("TweenTime")
		local dur = if type(t) == "number" then t else 0.6
		local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		for _, l in leaves do
			TweenService:Create(l.value, info, { Value = if open then l.open else l.closed }):Play()
		end
		task.delay(dur, function()
			busy = false
		end)
	end
	prompt.Triggered:Connect(function()
		set(not isOpen)
	end)
	door:GetAttributeChangedSignal("WantOpen"):Connect(function()
		set(door:GetAttribute("WantOpen") == true)
	end)
end

for _, d in CollectionService:GetTagged("BankDoor") do
	setup(d)
end
CollectionService:GetInstanceAddedSignal("BankDoor"):Connect(setup)
