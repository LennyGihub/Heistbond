--!strict
-- The two driving cinematics (client), both driven by the server with a shared start time:
--   intro(data)   the crew's black van leaves the hideout, the crew rides in the back, the van turns
--                 onto the bank street and parks; the side door slides open and the crew steps out, and
--                 the camera glides into the normal game camera behind the player.
--   escape(data)  6 seconds: the getaway vehicle tears off, police cars chase it down the street (one
--                 spins out), it drifts into the hideout road, the police overshoot, it slides into the
--                 garage and the door rolls down. Players who stay behind just see it race away.
-- The vehicles are the server's own models, moved by every client locally (anchored parts keep a local
-- CFrame until the server changes them); they end exactly where the server puts them.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heist = ReplicatedStorage:WaitForChild("Heist")
local Cine = require(Heist:WaitForChild("Cine"))
local Meta = require(Heist:WaitForChild("CineMeta"))
local CrewVan = require(Heist:WaitForChild("CrewVan"))
local Ride = require(Heist:WaitForChild("Ride"))
local AA = require(Heist:WaitForChild("ActionAnim"))

local C = {}
local me = Players.LocalPlayer
local RGB = Color3.fromRGB
local V3 = Vector3.new
local CF = CFrame.new

local SND = {
	diesel = "rbxassetid://108016481446629",
	engineHigh = "rbxassetid://105415983274029",
	screech = "rbxassetid://8763693960",
	skid = "rbxassetid://109487442763183",
	slideDoor = "rbxassetid://140296030450157",
	garage = "rbxassetid://92927494450042",
	brake = "rbxassetid://109856529704837",
	crash = "rbxassetid://8125594257",
	siren = "rbxassetid://9056622054",
	carDoor = "rbxassetid://121381393291287",
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function smooth(x: number): number
	return Cine.smooth(x)
end

------------------------------------------------------------------ paths

type Path = { pts: { Vector3 }, cum: { number }, len: number }

-- a polyline through `corners`, each inner corner rounded with radius r (quadratic curve)
local function makePath(corners: { Vector3 }, r: number): Path
	local pts: { Vector3 } = { corners[1] }
	for i = 2, #corners - 1 do
		local a, b, c = corners[i - 1], corners[i], corners[i + 1]
		local d0 = (b - a).Unit
		local d1 = (c - b).Unit
		local rr = math.min(r, (b - a).Magnitude * 0.45, (c - b).Magnitude * 0.45)
		local p0, p2 = b - d0 * rr, b + d1 * rr
		for k = 0, 12 do
			local t = k / 12
			table.insert(pts, p0:Lerp(b, t):Lerp(b:Lerp(p2, t), t))
		end
	end
	table.insert(pts, corners[#corners])
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return { pts = pts, cum = cum, len = cum[#cum] }
end

-- position and heading at distance s
local function pathAt(p: Path, s: number): (Vector3, Vector3)
	s = math.clamp(s, 0, p.len)
	for i = 2, #p.pts do
		if s <= p.cum[i] or i == #p.pts then
			local seg = p.cum[i] - p.cum[i - 1]
			local f = if seg > 0 then (s - p.cum[i - 1]) / seg else 0
			local a, b = p.pts[i - 1], p.pts[i]
			local dir = b - a
			return a:Lerp(b, f), if dir.Magnitude > 1e-4 then dir.Unit else Vector3.zAxis
		end
	end
	return p.pts[#p.pts], Vector3.zAxis
end

-- a smoothed heading (looks a little ahead so turns are gradual)
local function pathCF(p: Path, s: number): CFrame
	local pos = pathAt(p, s)
	local ahead = pathAt(p, s + 3)
	local behind = pathAt(p, s - 3)
	local dir = ahead - behind
	if dir.Magnitude < 1e-3 then
		local _, d = pathAt(p, s)
		dir = d
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	return CFrame.lookAt(pos, pos + dir)
end

-- distance travelled at time t: accelerate for ta, cruise, brake for td, total D, arriving at len
local function profile(len: number, D: number, ta: number, td: number, t: number): (number, number)
	local v = len / (D - ta / 2 - td / 2)
	if t <= 0 then
		return 0, 0
	elseif t < ta then
		return 0.5 * v / ta * t * t, v * t / ta
	elseif t < D - td then
		return v * ta / 2 + v * (t - ta), v
	elseif t < D then
		local r = D - t
		return len - 0.5 * v / td * r * r, v * r / td
	end
	return len, 0
end

------------------------------------------------------------------ wheels

type Spinner = { part: BasePart, rel: CFrame }
local function spinners(m: Model): { Spinner }
	local out = {}
	local pivot = m:GetPivot()
	for _, d in m:GetDescendants() do
		-- only free parts: moving a part welded into the vehicle would move the whole vehicle
		if d:IsA("BasePart") and (d:GetAttribute("Spin") or d.Name == "Wheel" or d.Name == "Hub") and #d:GetJoints() == 0 then
			table.insert(out, { part = d, rel = pivot:ToObjectSpace(d.CFrame) })
		end
	end
	return out
end

local function placeWithWheels(m: Model, cf: CFrame, spins: { Spinner }, angle: number)
	m:PivotTo(cf)
	for _, s in spins do
		s.part.CFrame = cf * s.rel * CFrame.Angles(-angle, 0, 0)
	end
end

------------------------------------------------------------------ fx

local function smoke(at: Vector3, n: number, size: number?)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/smoke_main.dds"
	p.Color = ColorSequence.new(RGB(225, 222, 215))
	p.Size = NumberSequence.new(size or 3, (size or 3) * 3)
	p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	p.Lifetime = NumberRange.new(1.2, 2.2)
	p.Speed = NumberRange.new(2, 6)
	p.SpreadAngle = Vector2.new(70, 70)
	p.Rate = 0
	p.Parent = a
	p:Emit(n)
	Debris:AddItem(a, 4)
end

local function loopSound(id: string, parent: Instance, vol: number, pitch: number?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = vol
	s.PlaybackSpeed = pitch or 1
	s.RollOffMaxDistance = 300
	s.RollOffMinDistance = 12
	s.Parent = parent
	s:Play()
	return s
end

------------------------------------------------------------------ police cars (client only)

local function policeCar(): (Model, { BasePart })
	local m = Instance.new("Model")
	m.Name = "CinePolice"
	local function p(name: string, size: Vector3, off: CFrame, col: Color3, mat: Enum.Material?): Part
		local q = Instance.new("Part")
		q.Name = name
		q.Size = size
		q.CFrame = off
		q.Color = col
		q.Material = mat or Enum.Material.SmoothPlastic
		q.Anchored = true
		q.CanCollide = false
		q.CanQuery = false
		q.CanTouch = false
		q.TopSurface = Enum.SurfaceType.Smooth
		q.BottomSurface = Enum.SurfaceType.Smooth
		q.Parent = m
		return q
	end
	local WHITE, BLACK = RGB(240, 240, 242), RGB(25, 25, 30)
	p("Body", V3(7.2, 1.8, 15), CF(0, 1.9, 0), WHITE)
	p("DoorsL", V3(0.06, 1.2, 6.4), CF(-3.62, 2.0, 0.2), BLACK)
	p("DoorsR", V3(0.06, 1.2, 6.4), CF(3.62, 2.0, 0.2), BLACK)
	p("Hood", V3(7.0, 0.3, 4.2), CF(0, 2.85, -5.2), BLACK)
	local cab = p("Cabin", V3(6.4, 1.8, 6.6), CF(0, 3.7, 0.8), RGB(30, 40, 50), Enum.Material.Glass)
	cab.Transparency = 0.3
	p("Roof", V3(6.2, 0.25, 4.6), CF(0, 4.65, 0.9), WHITE)
	p("Bar", V3(4.4, 0.35, 0.9), CF(0, 4.95, 0.6), RGB(40, 40, 45))
	local red = p("LightRed", V3(1.9, 0.4, 0.8), CF(-1.1, 5.15, 0.6), RGB(255, 30, 30), Enum.Material.Neon)
	local blue = p("LightBlue", V3(1.9, 0.4, 0.8), CF(1.1, 5.15, 0.6), RGB(30, 90, 255), Enum.Material.Neon)
	for _, l in { red, blue } do
		local pl = Instance.new("PointLight")
		pl.Range = 22
		pl.Brightness = 3
		pl.Color = l.Color
		pl.Parent = l
	end
	p("Bumper", V3(7.4, 0.7, 0.6), CF(0, 1.2, -7.6), BLACK)
	p("Push", V3(4.0, 1.4, 0.4), CF(0, 2.0, -7.9), BLACK, Enum.Material.Metal)
	for sx = -1, 1, 2 do
		p("Headlight", V3(1.2, 0.5, 0.1), CF(sx * 2.5, 2.2, -7.55), RGB(255, 250, 220), Enum.Material.Neon)
		p("Taillight", V3(1.2, 0.5, 0.1), CF(sx * 2.5, 2.2, 7.55), RGB(220, 30, 30), Enum.Material.Neon)
		for _, z in { -4.6, 4.4 } do
			local w = p("Wheel", V3(1.0, 2.5, 2.5), CF(sx * 3.4, 1.25, z), RGB(20, 20, 20), Enum.Material.Rubber)
			w.Shape = Enum.PartType.Cylinder
		end
	end
	local word = p("Word", V3(0.05, 0.6, 4), CF(3.65, 2.9, 0.2), WHITE)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Right
	g.CanvasSize = Vector2.new(400, 60)
	g.Parent = word
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = "POLICE"
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = RGB(30, 60, 160)
	t.Parent = g
	m.WorldPivot = CFrame.identity
	m.Parent = workspace
	return m, { red, blue }
end

local function flash(lights: { BasePart }, t: number)
	local on = math.floor(t * 7) % 2 == 0
	lights[1].Transparency = if on then 0 else 0.85
	lights[2].Transparency = if on then 0.85 else 0
	for i, l in lights do
		local pl = l:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Enabled = (i == 1) == on
		end
	end
end

------------------------------------------------------------------ the opening: van to the bank

-- data = { t0 = server time, van = Model, riders = { userId }, park = CFrame }
function C.intro(data: any)
	local van = data.van :: Model
	if not van or not van.Parent then
		return
	end
	local t0 = data.t0 :: number
	local M = Meta.intro
	local riders: { Player } = {}
	local myIndex = 1
	for i, uid in data.riders do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			table.insert(riders, p)
			if p == me then
				myIndex = #riders
			end
		end
	end
	local seats = {}
	for _, s in CrewVan.SEATS do
		table.insert(seats, CF(0, CrewVan.BENCH_TOP, 0) * s)
	end
	local path = makePath(Meta.introPath, 16)
	local spins = spinners(van)
	local park = data.park :: CFrame
	local function vanAt(t: number): (CFrame, number)
		local s, v = profile(path.len, M.drive, 1.6, 1.9, t)
		local cf = pathCF(path, s)
		-- body: nose up when it pulls away, dips when it brakes, leans in the turn, road bumps
		local accel = if t < 1.6 then 1 elseif t > M.drive - 1.9 and t < M.drive then -1 else 0
		local settle = if t >= M.drive then math.exp(-(t - M.drive) * 5) * math.sin((t - M.drive) * 14) * -0.6 else 0
		local ahead = pathCF(path, s + 6)
		local turn = cf.LookVector:Cross(ahead.LookVector).Y
		local bump = math.noise(t * 3.1, 0.3) * 0.012 * math.min(v / 40, 1)
		local tilt = CFrame.Angles(math.rad(accel * 1.6 + settle) + bump, 0, math.rad(-turn * 30) + bump * 0.6)
		if t >= M.drive then
			cf = park
		end
		return CF(0, 0, 0) * cf * tilt, s
	end
	Cine.begin()
	Cine.fade(Color3.new(0, 0, 0), 0, 0)
	local ride = Ride.new(van, riders, seats)
	local engine = loopSound(SND.diesel, van:FindFirstChild("Hood") or van, 0.45, 0.9)
	local wheelAngle = 0
	local lastS = 0
	local released = false
	local doorOpened = false
	local function T(): number
		return serverNow() - t0
	end
	RunService:BindToRenderStep("IntroVan", Enum.RenderPriority.Camera.Value - 5, function()
		local t = T()
		local cf, s = vanAt(math.min(t, M.drive + 1))
		wheelAngle += (s - lastS) / 1.4
		lastS = s
		placeWithWheels(van, cf, spins, wheelAngle)
		ride:update()
		local v = select(2, profile(path.len, M.drive, 1.6, 1.9, t))
		engine.PlaybackSpeed = 0.85 + math.min(v / 60, 1) * 0.45
		if t >= M.door and not doorOpened then
			doorOpened = true
			Cine.sound(SND.slideDoor, van:FindFirstChild("SideDoor") or van, 0.8, 1, 120)
		end
		if doorOpened then
			CrewVan.setDoor(van, smooth((t - M.door) / 0.75))
		end
	end)
	-- wait for the shared start
	while T() < 0 do
		task.wait()
	end
	Cine.fade(Color3.new(0, 0, 0), 1, 0.9)
	-- A: low on the hideout road, the van pulls out and roars past
	local camA = V3(-161.5, 2.4, 118)
	Cine.shot(2.4, function(u)
		local p = van:GetPivot().Position + V3(0, 3, 0)
		return CFrame.lookAt(camA + V3(0, u * 0.6, 0), p), 52 + u * 10
	end)
	task.wait(math.max(0, 2.4 - T()))
	-- B: inside the cargo bay, the crew on the benches, swaying with the road
	Cine.shot(2.5, function(u)
		local pv = van:GetPivot()
		local hand = CFrame.Angles(math.noise(T() * 1.3, 1) * 0.02, math.noise(T() * 1.1, 2) * 0.025, math.noise(T() * 0.9, 3) * 0.02)
		-- from the back corner, high: the left bench in three-quarter view, the cab beyond
		return CFrame.lookAt(pv:PointToWorldSpace(V3(2.6, 6.6, 8.1 - u * 0.5)), pv:PointToWorldSpace(V3(-1.6, 3.6, -1.2))) * hand, 70
	end)
	task.wait(math.max(0, 4.9 - T()))
	-- C: tracking alongside on the bank street, the bank behind
	Cine.shot(2.2, function(u)
		local pv = van:GetPivot()
		return CFrame.lookAt(pv:PointToWorldSpace(V3(-10 - u * 2, 2.4, -15 + u * 6)), pv:PointToWorldSpace(V3(1, 3.5, 3))), 58
	end)
	task.delay(0.5, function()
		Cine.title("LA NOOBLA BANK", 1.8)
	end)
	task.wait(math.max(0, 7.1 - T()))
	-- D: on the bank's sidewalk: the van brakes in and stops
	Cine.sound(SND.brake, van:FindFirstChild("Hood") or van, 0.5, 1, 160)
	local camD = park:PointToWorldSpace(V3(13, 4.2, -11))
	Cine.shot(1.6, function(u)
		return CFrame.lookAt(camD + V3(0, -u * 0.4, 0), van:GetPivot():PointToWorldSpace(V3(4, 3.2, 0))), 50
	end)
	task.wait(math.max(0, M.swap - T()))
	-- the copies of the other riders give way to the real characters (inside, door still shut)
	ride:releaseOthers()
	task.wait(math.max(0, M.door - 0.05 - T()))
	-- E: the side door slides open; the crew steps out onto the sidewalk
	Cine.shot(1.2, function(u)
		local pv = park
		return CFrame.lookAt(pv:PointToWorldSpace(V3(11 - u * 1.5, 3.6, -6.5 + u)), pv:PointToWorldSpace(V3(3.5, 3.6, -0.5))), 52
	end, 0.4)
	task.wait(math.max(0, M.out - T()))
	ride:releaseMe()
	engine:Destroy()
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spread = (myIndex - 1) % 4
	local inside = park:PointToWorldSpace(CrewVan.EXIT_INSIDE + V3(0, 0, (spread - 1.5) * 0.7))
	local outside = park:PointToWorldSpace(CrewVan.EXIT_OUTSIDE + V3(spread * 0.6, 0, (spread - 1.5) * 2.6))
	local toBank = park:VectorToWorldSpace(V3(1, 0, 0))
	if char and root then
		task.spawn(function()
			Cine.walk(char, V3(inside.X, root.Position.Y, inside.Z), 10, 1.4)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Jump = true
			end
			Cine.walk(char, V3(outside.X, root.Position.Y, outside.Z), 14, 1.8)
			Cine.face(char, outside + toBank * 10, 0.3)
		end)
	end
	-- F: follow the player out, ending where the game camera sits (behind, looking at the bank)
	local wait = M.len - 1.0 - T()
	Cine.shot(math.max(0.5, wait), function(u)
		local r = (me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?) or root
		local at = if r then r.Position else outside
		local k = smooth(u)
		local side = park:PointToWorldSpace(V3(11, 3.4, -6)):Lerp(outside - toBank * 7 + V3(0, 3.8, 0), k)
		return CFrame.lookAt(side, (at + V3(0, 1.5, 0)):Lerp(at + toBank * 12 + V3(0, 2.5, 0), k)), 52 + 18 * k
	end, 0.3)
	task.wait(math.max(0, M.len - 1.0 - T()))
	RunService:UnbindFromRenderStep("IntroVan")
	ride:release()
	released = true
	Cine.finish(1.0)
	local _ = released
end

-- after the crew got out, the van drives off east and away (every client, locally)
function C.vanLeave(data: any)
	local van = data.van :: Model
	if not van or not van.Parent then
		return
	end
	local t0 = data.t0 :: number
	local start = van:GetPivot()
	local spins = spinners(van)
	local angle = 0
	CrewVan.setDoor(van, 0)
	local snd = loopSound(SND.diesel, van:FindFirstChild("Hood") or van, 0.4, 1.0)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not van.Parent then
			conn:Disconnect()
			return
		end
		local t = serverNow() - t0
		local d = 0.5 * 14 * math.max(t, 0) ^ 2
		angle = d / 1.4
		placeWithWheels(van, start * CF(0, 0, -d), spins, angle)
		snd.PlaybackSpeed = 0.9 + math.min(t / 4, 1) * 0.4
		if t > 7 then
			conn:Disconnect()
			snd:Destroy()
		end
	end)
end

------------------------------------------------------------------ the getaway (6 s)

-- seats in a heist vehicle, as local CFrames at seat height
local function vehicleSeats(veh: Model): { CFrame }
	local pivot = veh:GetPivot()
	local out = {}
	for _, n in { "DriverSeat", "Passenger" } do
		for _, s in veh:GetChildren() do
			if s.Name == n and s:IsA("BasePart") then
				table.insert(out, pivot:ToObjectSpace(s.CFrame * CF(0, s.Size.Y / 2, 0)))
			end
		end
	end
	local chassis = veh.PrimaryPart
	local L = if chassis then chassis.Size.Z else 14
	for i = 0, 5 do
		table.insert(out, CF((i % 2) * 2.4 - 1.2, 1.4, L / 4 + math.floor(i / 2) * 1.6) * CFrame.Angles(0, if i % 2 == 0 then -math.pi / 2 else math.pi / 2, 0))
	end
	return out
end

-- data = { t0, veh = Model, riders = { userId }, final = CFrame }
function C.escape(data: any)
	local veh = data.veh :: Model
	if not veh or not veh.Parent then
		return
	end
	local t0 = data.t0 :: number
	local LEN = Meta.escape.len
	local riders: { Player } = {}
	local riding = false
	for _, uid in data.riders do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			table.insert(riders, p)
			if p == me then
				riding = true
			end
		end
	end
	local start = veh:GetPivot()
	local h = math.clamp(start.Position.Y, 0.8, 3) -- the vehicle's own ride height
	local final = data.final :: CFrame
	local spins = spinners(veh)
	local fwd = Vector3.new(start.LookVector.X, 0, start.LookVector.Z).Unit
	local function T(): number
		return serverNow() - t0
	end
	-- where the vehicle is at time t (cuts between the phases happen on camera cuts)
	local street = makePath({ V3(80, h, 163), V3(-170, h, 163), V3(-170, h, 112) }, 34)
	local streetLen = street.len
	local function vehAt(t: number): CFrame
		if t < 1.35 then
			-- tears off from where it was parked
			local d = 0.5 * 34 * t * t
			local wob = math.sin(t * 22) * math.max(0, 0.7 - t) * 0.05
			return CFrame.lookAt(start.Position, start.Position + fwd) * CF(0, 0, -d) * CFrame.Angles(math.rad(2.5) * math.min(t * 3, 1), wob, 0)
		elseif t < 4.95 then
			-- the street run and the drift into the hideout road
			local u = (t - 1.35) / (4.95 - 1.35)
			local s = streetLen * (u * 0.82 + 0.18 * u * u)
			local cf = pathCF(street, s)
			-- drift: the tail swings out through the corner
			local corner = math.clamp((s - (streetLen - 80)) / 60, 0, 1)
			local drift = math.sin(corner * math.pi) * math.rad(28)
			return cf * CFrame.Angles(0, drift, math.rad(-4) * math.sin(corner * math.pi))
		end
		-- down the hideout road into the garage, braking hard
		local u = math.clamp((t - 4.95) / 0.75, 0, 1)
		local k = 1 - (1 - u) * (1 - u)
		local from = final * CF(0, 0, 62) -- 62 studs up the road behind it
		local p = from.Position:Lerp(final.Position, k)
		local dip = if u >= 1 then math.exp(-(t - 5.7) * 6) * math.sin((t - 5.7) * 16) * 0.04 else -math.rad(1.5) * u
		return CFrame.lookAt(p, p + final.LookVector) * CFrame.Angles(dip, 0, 0)
	end

	local engine = loopSound(SND.engineHigh, veh.PrimaryPart or veh, 0.55, 1.0)
	local wheelA = 0
	local ride: any = nil
	local hidden = false
	local police: { { model: Model, lights: { BasePart }, lag: number, lane: number, spin: boolean } } = {}
	local siren: Sound? = nil

	if riding then
		Cine.begin()
		ride = Ride.new(veh, riders, vehicleSeats(veh), true)
	else
		for _, p in riders do
			if p.Character then
				Cine.hide(p.Character, true)
			end
		end
	end
	Cine.sound(SND.screech, veh.PrimaryPart or veh, 0.8, 1, 220)
	smoke(start:PointToWorldSpace(V3(0, -0.6, 5)), 18, 3)

	RunService:BindToRenderStep("EscapeRide", Enum.RenderPriority.Camera.Value - 5, function(dt)
		local t = T()
		if t > LEN + 0.2 then
			return
		end
		if not riding then
			if t < 1.35 then
				placeWithWheels(veh, vehAt(t), spins, wheelA)
				wheelA += dt * 30
			elseif not hidden then
				hidden = true
				Cine.hide(veh, true)
			end
			return
		end
		placeWithWheels(veh, vehAt(t), spins, wheelA)
		wheelA += dt * (if t < 5.7 then 40 else 0)
		ride:update()
		-- the police: behind on the street, then they overshoot the turn and are lost
		if t >= 1.35 and t < 4.95 then
			local u = (t - 1.35) / (4.95 - 1.35)
			local s = streetLen * (u * 0.82 + 0.18 * u * u)
			for _, pc in police do
				local ps = s - pc.lag
				local cf: CFrame
				if ps < streetLen - 92 then
					cf = pathCF(street, math.max(ps, 0)) * CF(pc.lane, 0, 0)
				else
					-- straight on past the corner
					local over = ps - (streetLen - 92)
					local base = pathCF(street, streetLen - 92) * CF(pc.lane, 0, 0)
					cf = base * CF(0, 0, -over * 1.05)
				end
				if pc.spin then
					local k = math.clamp((t - 2.55) / 0.9, 0, 1)
					if k > 0 then
						cf = cf * CF(k * 9, 0, k * 6) * CFrame.Angles(0, k * k * math.rad(200), 0)
					end
				end
				pc.model:PivotTo(cf * CF(0, -h + 0.1, 0))
				flash(pc.lights, t + pc.lag * 0.01)
			end
		end
		engine.PlaybackSpeed = if t < 5.7 then 0.95 + math.min(t / 1.4, 1) * 0.35 else 0.8
	end)

	if not riding then
		-- the others: it tears off and is gone; it reappears in the garage when the server puts it there
		task.wait(math.max(0, LEN + 0.15 - T()))
		RunService:UnbindFromRenderStep("EscapeRide")
		engine:Destroy()
		Cine.hide(veh, false)
		for _, p in riders do
			if p.Character then
				Cine.hide(p.Character, false)
			end
		end
		return
	end

	-- police cars come in for the street run
	for i, spec in { { 24, -3.6, false }, { 40, 3.4, true }, { 58, -2.2, false } } do
		local m, lights = policeCar()
		m:PivotTo(CF(0, -300, 0))
		table.insert(police, { model = m, lights = lights, lag = spec[1], lane = spec[2], spin = spec[3] })
		if i == 1 then
			siren = loopSound(SND.siren, m:FindFirstChild("Bar") or m, 0.6, 1)
		end
	end

	-- S1: low at the front quarter: it launches past the camera
	-- beside its path, well ahead: it launches toward the lens and roars past on the right
	local camS1 = CFrame.lookAt(start.Position, start.Position + fwd):PointToWorldSpace(V3(-9.5, 1.4, -30))
	Cine.shot(1.35, function(u)
		return CFrame.lookAt(camS1, veh:GetPivot().Position + V3(0, 1.5, 0)), 56 - u * 6
	end)
	task.wait(math.max(0, 1.35 - T()))
	-- S2: tracking just ahead of it down the street, the police lights behind
	Cine.shake(0.15, 0.5)
	Cine.shot(2.25, function(u)
		local pv = veh:GetPivot()
		Cine.shake(0.06, 1)
		return CFrame.lookAt(pv:PointToWorldSpace(V3(-7.5 + u * 2, 2.6, -16 + u * 3)), pv:PointToWorldSpace(V3(0, 1.8, 10))), 64
	end)
	task.delay(1.15, function()
		local pc = police[2]
		if pc then
			Cine.sound(SND.screech, pc.model:FindFirstChild("Body") or pc.model, 0.7, 0.9, 200)
			task.delay(0.6, function()
				Cine.sound(SND.crash, pc.model:FindFirstChild("Body") or pc.model, 0.8, 1, 260)
				smoke(pc.model:GetPivot().Position + V3(0, 2, 0), 20, 4)
			end)
		end
	end)
	task.wait(math.max(0, 3.6 - T()))
	-- S3: high and wide over the corner: the drift, the police blow past
	Cine.sound(SND.skid, veh.PrimaryPart or veh, 0.7, 1.1, 260)
	Cine.shot(1.35, function(u)
		local p = veh:GetPivot().Position
		return CFrame.lookAt(V3(-132 - u * 6, 36, 206), p:Lerp(V3(-170, 0, 150), 0.3)), 50
	end)
	task.delay(0.55, function()
		smoke(veh:GetPivot():PointToWorldSpace(V3(0, -0.5, 5)), 25, 4)
	end)
	task.wait(math.max(0, 4.95 - T()))
	-- S4: inside the garage: it slides in, brakes, the roller door slams down
	if siren then
		TweenService:Create(siren, TweenInfo.new(1.2), { Volume = 0.1 }):Play()
	end
	for _, pc in police do
		pc.model:Destroy()
	end
	table.clear(police)
	local door = Instance.new("Part")
	door.Name = "CineGarageDoor"
	door.Anchored = true
	door.CanCollide = false
	door.CanQuery = false
	door.Size = V3(33, 16, 0.5)
	door.Color = RGB(150, 150, 158)
	door.Material = Enum.Material.CorrodedMetal
	door.CFrame = CF(-170, 24, 29.4)
	door.Parent = workspace
	for i = 1, 7 do
		local rib = Instance.new("Part")
		rib.Anchored = true
		rib.CanCollide = false
		rib.CanQuery = false
		rib.Size = V3(33, 0.2, 0.6)
		rib.Color = RGB(120, 120, 128)
		rib.CFrame = door.CFrame * CF(0, -8 + i * 2, 0)
		rib.Parent = door
		local w = Instance.new("WeldConstraint")
		w.Part0 = door
		w.Part1 = rib
		w.Parent = rib
	end
	Cine.sound(SND.brake, veh.PrimaryPart or veh, 0.7, 1.05, 200)
	Cine.shot(1.2, function(u)
		return CFrame.lookAt(V3(-176 + u * 1.5, 5.5, -19), veh:GetPivot().Position:Lerp(V3(-170, 6, 30), 0.35) + V3(0, 1.5, 0)), 60
	end)
	task.wait(math.max(0, 5.2 - T()))
	Cine.sound(SND.garage, door, 0.9, 1.2, 200)
	TweenService:Create(door, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CF(-170, 8, 29.4) }):Play()
	task.delay(0.55, function()
		Cine.shake(0.5, 5)
	end)
	task.wait(math.max(0, 5.75 - T()))
	Cine.fade(Color3.new(0, 0, 0), 0, 0.3)
	task.wait(math.max(0, LEN - T()))
	Cine.title("EN SÉCURITÉ !", 0.7)
	-- wait for the server to put everyone in the garage, then back to the game
	task.wait(math.max(0, LEN + 0.35 - T()))
	RunService:UnbindFromRenderStep("EscapeRide")
	engine:Destroy()
	if siren then
		siren:Destroy()
	end
	ride:release()
	local char = me.Character
	local spot = data.spots and data.spots[tostring(me.UserId)]
	if char and typeof(spot) == "Vector3" then
		char:PivotTo(CFrame.lookAt(spot, spot + V3(0, 0, 1)))
	end
	task.wait(0.6)
	door:Destroy()
	Cine.finish(0.05)
	Cine.fade(Color3.new(0, 0, 0), 1, 0.8)
	local _ = AA
end

return C
