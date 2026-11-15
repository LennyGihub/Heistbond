--!strict
-- The bank's people living their day (while nobody is a threat):
--  * customers queue at the teller windows: greeting, transaction, thanks, then wander the hall (read the
--    notice board, phone a relative, chat with someone, or go back to a window);
--  * tellers type, stamp, hum, glance around and talk to their neighbour;
--  * guards patrol, greet customers and talk to staff; the manager stops to talk when he walks by;
--  * two idle people close to each other strike up a small-talk exchange (face each other, take turns,
--    gesture) that is cut short the instant either gets scared.
--  * witnesses: when someone is taken hostage, killed or runs screaming, the people who see it react.
-- Everything here yields (task.spawn); NPC state ("Idle", "Down"...) always wins over a routine.
local CollectionService = game:GetService("CollectionService")

local Nav = require(script.Parent.NpcNav)
local Lines = require(script.Parent.NpcLines)

local Life = {}
local N: any -- the Npcs module (set by Life.init)
local rng = Random.new()

type Window = { pos: Vector3, teller: any?, occupant: any?, key: string }
local windows: { Window } = {}
local epoch = 0 -- bumped on reset so old routines stop

local function now(): number
	return os.clock()
end

local function alive(n: any): boolean
	return n.state ~= "Dead" and n.model.Parent ~= nil and n.hum.Health > 0
end

-- calm = nothing is wrong with this person right now
local function calm(n: any): boolean
	return alive(n) and n.state == "Idle" and n.meter < 0.3
end

local function free(n: any): boolean
	return calm(n) and n.busy == nil
end

local function lineTime(text: string): number
	return 0.7 + #text / 22 + 0.7
end

local function dist(a: any, b: any): number
	return (a.root.Position - b.root.Position).Magnitude
end

local function lookAround(n: any, dir: Vector3, seconds: number, abort: () -> boolean)
	local t0 = now()
	while now() - t0 < seconds and not abort() do
		Nav.faceStep(n.root, n.root.Position + dir, 0.1, 4)
		task.wait(0.1)
	end
end

------------------------------------------------------------------ conversation

-- a speaks first, then b, and so on. Returns true if every line was said.
local function converse(a: any, b: any, lines: { string }): boolean
	local prevA, prevB = a.busy, b.busy
	a.busy, b.busy = "talk", "talk"
	local function ok(): boolean
		return calm(a) and calm(b)
	end
	Nav.stop(a.hum, a.root)
	Nav.stop(b.hum, b.root)
	-- turn toward each other
	local t0 = now()
	while now() - t0 < 1.2 and ok() do
		local fa = Nav.faceStep(a.root, b.root.Position, 0.1, 7)
		local fb = Nav.faceStep(b.root, a.root.Position, 0.1, 7)
		if fa and fb then
			break
		end
		task.wait(0.1)
	end
	local done = true
	for i, text in lines do
		if not ok() then
			done = false
			break
		end
		local speaker = if i % 2 == 1 then a else b
		local listener = if i % 2 == 1 then b else a
		N.speak(speaker, text, "normal", true)
		if not speaker.gun then
			N.pose(speaker, "talk")
		end
		task.wait(0.55)
		N.pose(speaker, "none")
		Nav.faceStep(listener.root, speaker.root.Position, 0.1, 6)
		task.wait(math.max(0.2, lineTime(text) - 0.55))
	end
	if a.state == "Idle" then
		N.pose(a, "none")
	end
	if b.state == "Idle" then
		N.pose(b, "none")
	end
	a.busy = if a.busy == "talk" then prevA else a.busy
	b.busy = if b.busy == "talk" then prevB else b.busy
	local cd = now() + rng:NextNumber(25, 55)
	a.life.chatAt, b.life.chatAt = cd, cd
	return done
end

local function pairLines(a: any, b: any): ({ string }?, boolean)
	local ra, rb = string.lower(a.role), string.lower(b.role)
	local l = Lines.exchange(ra, rb)
	if l then
		return l, false
	end
	l = Lines.exchange(rb, ra)
	if l then
		return l, true -- b should speak first
	end
	return nil, false
end

local function chat(a: any, b: any)
	local lines, swap = pairLines(a, b)
	if not lines then
		return
	end
	if swap then
		converse(b, a, lines)
	else
		converse(a, b, lines)
	end
end

-- nearest free partner within `range` that shares an exchange with n
local function partnerFor(n: any, range: number): any?
	local best, bd = nil, range
	for _, o in N.list do
		if o ~= n and free(o) and o.life and (o.life.chatAt or 0) < now() then
			local d = dist(n, o)
			-- tellers only talk to other tellers (and customers at their window, handled elsewhere)
			local tellerOk = (n.role ~= "Teller" and o.role ~= "Teller") or (n.role == "Teller" and o.role == "Teller")
			if d < bd and tellerOk and (pairLines(n, o)) then
				best, bd = o, d
			end
		end
	end
	return best
end

-- block until a conversation with someone nearby is over (used by the manager's routine)
function Life.tryChat(n: any, range: number)
	if not free(n) then
		return
	end
	local p = partnerFor(n, range)
	if p then
		-- walk up to him first
		local ok = Nav.walk(n.hum, n.root, p.root.Position, {
			speed = 5.5,
			arrive = 5,
			timeout = 10,
			abort = function()
				return not calm(n) or not calm(p)
			end,
		})
		if ok and free(p) then
			chat(n, p)
		end
	end
end

------------------------------------------------------------------ places

local function hallSpot(): Vector3?
	local pts = {}
	for _, m in CollectionService:GetTagged("HeistMarker") do
		if m:IsA("BasePart") and m:GetAttribute("Role") == "Customer" and not string.find(m.Name, "Teller") and m:IsDescendantOf(workspace) then
			table.insert(pts, m.Position)
		end
	end
	if #pts == 0 then
		return nil
	end
	local base = pts[rng:NextInteger(1, #pts)]
	local p = base + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-8, 8))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { N.folder }
	local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), params)
	if not hit or N.inRestricted(hit.Position) then
		return nil
	end
	return hit.Position
end

local function marker(name: string): BasePart?
	for _, m in CollectionService:GetTagged("HeistMarker") do
		if m.Name == name and m:IsA("BasePart") and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

local function buildWindows()
	table.clear(windows)
	for i = 1, 4 do
		local m = marker("TellerCustomer" .. i)
		local t = marker("Teller" .. i)
		if m and t then
			local w: Window = { pos = m.Position, teller = nil, occupant = nil, key = tostring(i) }
			for _, n in N.list do
				if n.role == "Teller" and (n.root.Position - t.Position).Magnitude < 4 then
					w.teller = n
				end
			end
			for _, n in N.list do
				if n.role == "Customer" and (n.root.Position - m.Position).Magnitude < 3 then
					w.occupant = n
				end
			end
			table.insert(windows, w)
		end
	end
end

local function freeWindow(): Window?
	local opts = {}
	for _, w in windows do
		if not w.occupant and w.teller and free(w.teller) then
			table.insert(opts, w)
		end
	end
	return if #opts > 0 then opts[rng:NextInteger(1, #opts)] else nil
end

------------------------------------------------------------------ routines

local function typing(n: any, count: number)
	for _ = 1, count do
		if not calm(n) then
			return
		end
		N.sfx("key", n.root, 0.14, rng:NextNumber(1.6, 2.3), 28)
		task.wait(rng:NextNumber(0.12, 0.3))
	end
end

local function transaction(c: any, w: Window)
	local t = w.teller
	if not t or not free(t) then
		return
	end
	w.occupant = c
	c.busy = "window"
	-- stand facing the teller
	local t0 = now()
	while now() - t0 < 1.5 and calm(c) do
		if Nav.faceStep(c.root, t.root.Position, 0.1, 6) then
			break
		end
		task.wait(0.1)
	end
	task.wait(rng:NextNumber(0.5, 2))
	if calm(c) and calm(t) then
		local lines = Lines.exchange("teller", "customer")
		if lines then
			converse(t, c, lines)
		end
		if calm(t) then
			typing(t, rng:NextInteger(3, 6))
			N.sfx("thud", t.root, 0.12, 2.2, 25)
		end
	end
	w.occupant = nil
	if c.busy == "window" then
		c.busy = nil
	end
end

local function customerLoop(n: any, my: number)
	task.wait(rng:NextNumber(0.3, 3))
	-- customers that start at a window begin with their transaction
	for _, w in windows do
		if w.occupant == n then
			transaction(n, w)
		end
	end
	while epoch == my and alive(n) do
		if not free(n) then
			task.wait(0.6)
			continue
		end
		local abort = function(): boolean
			return epoch ~= my or not calm(n) or n.busy ~= nil
		end
		local r = rng:NextNumber()
		if r < 0.28 then
			local w = freeWindow()
			if w then
				w.occupant = n -- reserve
				n.busy = "walk"
				local ok = Nav.walk(n.hum, n.root, w.pos, { speed = 5, arrive = 1.2, timeout = 30, abort = function()
					return epoch ~= my or not calm(n)
				end })
				n.busy = nil
				if ok and calm(n) then
					transaction(n, w)
				else
					w.occupant = nil
				end
			end
		elseif r < 0.48 then
			-- go and talk to someone
			local p = partnerFor(n, 45)
			if p and n.life.chatAt < now() then
				n.busy = "walk"
				p.busy = if p.busy == nil then "walk" else p.busy
				local pRef = p
				local ok = Nav.walk(n.hum, n.root, p.root.Position, { speed = 5, arrive = 4.5, timeout = 25, abort = function()
					return epoch ~= my or not calm(n) or not calm(pRef)
				end })
				n.busy = nil
				if pRef.busy == "walk" then
					pRef.busy = nil
				end
				if ok and free(n) and free(pRef) then
					chat(n, pRef)
				end
			end
		elseif r < 0.62 then
			-- read the notice board
			local board = marker("ClueNotice")
			if board then
				n.busy = "walk"
				local ok = Nav.walk(n.hum, n.root, board.Position + board.CFrame.LookVector * 3, { speed = 4.5, arrive = 2, timeout = 30, abort = abort })
				n.busy = nil
				if ok and calm(n) then
					lookAround(n, board.Position - n.root.Position, 1.2, abort)
					N.speak(n, Lines.pick({ "Des travaux sur le toit ? Tiens...", "Encore des avis...", "Intéressant." }), "normal")
					lookAround(n, board.Position - n.root.Position, rng:NextNumber(4, 7), abort)
				end
			end
		elseif r < 0.78 then
			-- phone call
			local line = Lines.solo_("Customer")
			if line then
				N.pose(n, "phone")
				N.speak(n, line, "normal")
				for _ = 1, rng:NextInteger(4, 8) do
					if abort() then
						break
					end
					task.wait(1)
				end
				if n.state == "Idle" then
					N.pose(n, "none")
				end
			end
		else
			-- wander
			local spot = hallSpot()
			if spot then
				n.busy = "walk"
				Nav.walk(n.hum, n.root, spot, { speed = rng:NextNumber(4, 5.2), arrive = 2, timeout = 30, abort = function()
					return epoch ~= my or not calm(n) or n.busy == "talk"
				end })
				if n.busy == "walk" then
					n.busy = nil
				end
			end
		end
		-- stand around for a bit
		local wait = rng:NextNumber(3, 9)
		local t0 = now()
		while now() - t0 < wait and epoch == my and free(n) do
			task.wait(0.4)
		end
	end
end

local function tellerLoop(n: any, my: number)
	task.wait(rng:NextNumber(0.5, 4))
	local base = n.root.CFrame.LookVector
	while epoch == my and alive(n) do
		if not free(n) then
			task.wait(0.8)
			continue
		end
		local r = rng:NextNumber()
		if r < 0.5 then
			typing(n, rng:NextInteger(3, 9))
		elseif r < 0.68 then
			-- glance at the hall
			local abort = function(): boolean
				return epoch ~= my or not free(n)
			end
			local side = Vector3.new(base.Z, 0, -base.X) * rng:NextNumber(-1, 1)
			lookAround(n, base + side, rng:NextNumber(1.2, 2.2), abort)
			lookAround(n, base, 1.2, abort)
		elseif r < 0.8 then
			local line = Lines.solo_("Teller")
			if line then
				N.speak(n, line, "normal")
			end
		elseif r < 0.9 then
			N.sfx("cash", n.root, 0.1, 1.8, 22)
			task.wait(0.8)
		end
		local t0 = now()
		local wait = rng:NextNumber(2.5, 7)
		while now() - t0 < wait and epoch == my and free(n) do
			task.wait(0.4)
		end
	end
end

-- guards: patrol points (the hall for the front guard, the back area for the other)
local function patrolPoints(n: any): { Vector3 }
	local pts: { Vector3 } = {}
	local home = n.model:GetAttribute("Home")
	local homePos = if typeof(home) == "CFrame" then home.Position else n.root.Position
	if N.inRestricted(homePos) or homePos.Z > 265 then
		for _, m in CollectionService:GetTagged("HeistMarker") do
			if m:IsA("BasePart") and m:GetAttribute("Role") == "ManagerWalk" and m:IsDescendantOf(workspace) then
				table.insert(pts, m.Position)
			end
		end
	else
		for _ = 1, 6 do
			local s = hallSpot()
			if s then
				table.insert(pts, s)
			end
		end
	end
	table.insert(pts, 1, homePos)
	return pts
end

local function guardLoop(n: any, my: number)
	task.wait(rng:NextNumber(1, 5))
	local pts = patrolPoints(n)
	local i = 1
	while epoch == my and alive(n) and n.state ~= "Hostile" do
		if not free(n) then
			task.wait(0.8)
			continue
		end
		i = i % #pts + 1
		local target = pts[i]
		n.busy = "walk"
		Nav.walk(n.hum, n.root, target, { speed = 5.4, arrive = 2.5, timeout = 40, abort = function()
			return epoch ~= my or not calm(n) or n.busy == "talk" or n.state == "Hostile"
		end })
		if n.busy == "walk" then
			n.busy = nil
		end
		if free(n) then
			-- scan the room, maybe greet someone
			local abort = function(): boolean
				return epoch ~= my or not free(n)
			end
			local dir = n.root.CFrame.LookVector
			lookAround(n, dir + Vector3.new(dir.Z, 0, -dir.X) * 0.8, 1.6, abort)
			lookAround(n, dir - Vector3.new(dir.Z, 0, -dir.X) * 0.8, 1.6, abort)
			if free(n) and n.life.chatAt < now() and rng:NextNumber() < 0.5 then
				local p = partnerFor(n, 16)
				if p then
					chat(n, p)
				end
			end
			if free(n) and rng:NextNumber() < 0.2 then
				local line = Lines.solo_("Guard")
				if line then
					N.speak(n, line, "normal")
				end
			end
		end
		local t0 = now()
		local wait = rng:NextNumber(3, 8)
		while now() - t0 < wait and epoch == my and free(n) do
			task.wait(0.5)
		end
	end
end

------------------------------------------------------------------ witnesses

local function sees(from: Vector3, to: Vector3): boolean
	local hit = workspace:Raycast(from, to - from, N.eyeParams())
	return hit == nil
end

-- kind: "hostage" (someone was forced down), "death", "flee" (someone runs screaming)
function Life.witness(kind: string, src: any?, pos: Vector3)
	for _, n in N.list do
		if n ~= src and alive(n) and n.role ~= "Police" and (n.state == "Idle" or n.state == "HandsUp") then
			local d = (n.root.Position - pos).Magnitude
			local range = if kind == "flee" then 22 else 40
			if d < range and sees(n.head.Position, pos + Vector3.new(0, 2, 0)) then
				-- turn to look
				local flat = (pos - n.root.Position) * Vector3.new(1, 0, 1)
				if flat.Magnitude > 0.5 then
					n.root.CFrame = CFrame.lookAt(n.root.Position, n.root.Position + flat)
				end
				if n.role == "Guard" then
					if kind ~= "flee" then
						n.meter = math.max(n.meter, 0.9)
					end
				elseif kind == "death" then
					N.speak(n, Lines.react_("witnessDeath", n.role), "scream", true)
					N.scare(n, true)
				elseif kind == "hostage" then
					N.speak(n, Lines.react_("shock", n.role), "scared")
					n.meter = math.max(n.meter, 0.55)
					if n.bravery < 0.35 then
						N.scare(n, false)
					end
				else
					if rng:NextNumber() < 0.5 then
						N.speak(n, Lines.react_("shock", n.role), "scared")
					end
					n.meter = math.max(n.meter, 0.3)
				end
			end
		end
	end
end

------------------------------------------------------------------ start / scanner

function Life.reset()
	epoch += 1
	table.clear(windows)
end

-- called by Npcs.spawnBank once everyone exists
function Life.start()
	epoch += 1
	local my = epoch
	buildWindows()
	for _, n in N.list do
		n.life = n.life or {}
		n.life.chatAt = now() + rng:NextNumber(6, 25)
		if n.role == "Customer" then
			task.spawn(customerLoop, n, my)
		elseif n.role == "Teller" then
			task.spawn(tellerLoop, n, my)
		elseif n.role == "Guard" then
			task.spawn(guardLoop, n, my)
		end
	end
	-- neighbours chatting by chance
	task.spawn(function()
		while epoch == my do
			task.wait(2)
			for _, a in N.list do
				if epoch ~= my then
					return
				end
				if free(a) and a.life and a.life.chatAt < now() and rng:NextNumber() < a.chatty * 0.4 then
					local range = if a.role == "Teller" then 24 else 9
					local p = partnerFor(a, range)
					if p then
						task.spawn(chat, a, p)
						break
					end
				end
			end
		end
	end)
end

function Life.init(npcs: any)
	N = npcs
end

return Life
