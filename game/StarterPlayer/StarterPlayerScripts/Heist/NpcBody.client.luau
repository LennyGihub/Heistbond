--!strict
-- NpcBody: plays the frightened civilians' body language on this client (NpcPoses). The server only
-- says what is happening (model attributes PoseKind = up | tied | none, Stance = stand | kneel, and a
-- smoothly lowered HipHeight); every client animates it the same way, smooth and at full frame rate:
-- the flinch and hands up, the drop to the knees with the fingers locked behind the head, the trembling,
-- the breathing, the darting looks, the sobbing of a tied hostage.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcPoses = require(ReplicatedStorage:WaitForChild("Heist"):WaitForChild("NpcPoses"))

local folder = workspace:WaitForChild("NPCs")

local JOINT_PARTS = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}

type Entry = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	joints: { [string]: any },
	shin: number,
	st: NpcPoses.State,
	touched: { [string]: boolean },
}

local entries: { [Model]: Entry } = {}
local seedN = 0

local function kindOf(m: Model): string
	local pk = m:GetAttribute("PoseKind")
	if pk == "tied" then
		return "tied"
	elseif pk == "up" then
		return if m:GetAttribute("Stance") == "kneel" then "down" else "up"
	end
	return "none"
end

local function track(m: Model): Entry?
	local e = entries[m]
	if e then
		return e
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return nil
	end
	local joints = {}
	for name, partName in JOINT_PARTS do
		local part = m:FindFirstChild(partName)
		local j = part and part:FindFirstChild(name)
		if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
			joints[name] = j
		end
	end
	local ll = m:FindFirstChild("RightLowerLeg") :: BasePart?
	local ft = m:FindFirstChild("RightFoot") :: BasePart?
	seedN += 1
	e = {
		model = m,
		hum = hum,
		root = root,
		joints = joints,
		shin = (if ll then ll.Size.Y else 1.2) + (if ft then ft.Size.Y * 0.6 else 0.2),
		st = NpcPoses.new(seedN * 7.31 + (m:GetAttribute("Voice") or 0) % 97),
		touched = {},
	}
	entries[m] = e
	return e
end

local function release(e: Entry)
	for name in e.touched do
		local j = e.joints[name]
		if j and j.Parent then
			j.Transform = CFrame.identity
		end
	end
	entries[e.model] = nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function hipDrop(e: Entry): number
	local base = e.model:GetAttribute("HipBase") :: number?
	if not base then
		return 0
	end
	local ignore: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local bottom = e.root.Position.Y - e.root.Size.Y / 2
	local hit = workspace:Raycast(e.root.Position, Vector3.new(0, -(base + e.root.Size.Y / 2 + 3), 0), rayParams)
	if not hit then
		return 0
	end
	return math.clamp(base - (bottom - hit.Position.Y), 0, base)
end

-- find NPCs that are (or just were) scared
local function scan()
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and not entries[m] then
			local k = kindOf(m)
			if k ~= "none" or m:GetAttribute("Stance") == "kneel" then
				local hum = m:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					track(m)
				end
			end
		end
	end
end

scan()
folder.ChildAdded:Connect(function(m)
	if m:IsA("Model") then
		local function check()
			if not entries[m] and (kindOf(m) ~= "none" or m:GetAttribute("Stance") == "kneel") then
				track(m)
			end
		end
		m:GetAttributeChangedSignal("PoseKind"):Connect(check)
		m:GetAttributeChangedSignal("Stance"):Connect(check)
	end
end)
for _, m in folder:GetChildren() do
	if m:IsA("Model") then
		local function check()
			if not entries[m] and (kindOf(m) ~= "none" or m:GetAttribute("Stance") == "kneel") then
				track(m)
			end
		end
		m:GetAttributeChangedSignal("PoseKind"):Connect(check)
		m:GetAttributeChangedSignal("Stance"):Connect(check)
	end
end
task.spawn(function()
	while true do
		task.wait(0.5)
		scan()
	end
end)

-- after the Animator (the NPC's own idle is stopped while posed), before the frame is simulated
RunService.PreSimulation:Connect(function(dt)
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for m, e in entries do
		if not m.Parent or e.hum.Health <= 0 or not e.root.Parent then
			release(e)
			continue
		end
		if (e.root.Position - camPos).Magnitude > 220 then
			continue
		end
		local kind = kindOf(m)
		local pose = NpcPoses.sample(e.st, kind, now, dt, hipDrop(e), e.shin)
		for name, cf in pose do
			local j = e.joints[name]
			if j then
				j.Transform = cf
				e.touched[name] = true
			end
		end
		if kind == "none" and not NpcPoses.busy(e.st) then
			release(e)
		end
	end
end)
