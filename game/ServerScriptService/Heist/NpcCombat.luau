--!strict
-- Tactics for the armed units (guards, police with pistols, SWAT with M4s).
--  * Cover: a unit looks for a point around itself that the threat cannot see (standing cover behind walls
--    and pillars, crouch cover behind counters), with a peek spot next to it from where it CAN see the threat.
--    It hides there, then steps out to the peek spot, fires one or two short bursts, and goes back.
--  * Squad: all units share what any of them sees (the last known position of each crew member), only a
--    few may be out of cover at the same time (the others cover them), units advance in bounds from cover to
--    cover (never all at once), and some are sent around the flank. A unit that is hit, out of ammo or
--    wounded stays hidden longer and reloads in cover.
--  * No wall-hacks: a unit only shoots at what it sees. Blind fire exists but is rare and weak: one unit at
--    a time, after the threat was seen in the last few seconds, 14-22 s apart per unit, wide spread and
--    low damage.
local Players = game:GetService("Players")

local Nav = require(script.Parent.NpcNav)
local Lines = require(script.Parent.NpcLines)

local Combat = {}
Combat.stats = { bursts = 0, blind = 0, peeks = 0, moves = 0, maxExposed = 0 } -- debug counters
local N: any
local rng = Random.new()

local UNIT = {
	Guard = { dmg = 6, spread = 4.2, burstMin = 2, burstMax = 3, rate = 0.15, react = { 0.45, 0.85 }, speed = 12, mag = 15, reload = 2.2, peek = { 1.3, 2.1 }, hold = { 1.8, 3.6 }, engage = 24, range = 48 },
	Police = { dmg = 6, spread = 4.5, burstMin = 2, burstMax = 3, rate = 0.15, react = { 0.45, 0.85 }, speed = 12, mag = 15, reload = 2.2, peek = { 1.3, 2.1 }, hold = { 1.8, 3.6 }, engage = 24, range = 48 },
	Swat = { dmg = 7, spread = 3.3, burstMin = 3, burstMax = 5, rate = 0.09, react = { 0.3, 0.6 }, speed = 13.5, mag = 30, reload = 2.4, peek = { 1.5, 2.5 }, hold = { 1.2, 2.8 }, engage = 18, range = 75 },
} :: { [string]: any }

type Cover = { pos: Vector3, stance: string, peek: Vector3?, peekStance: string }

type Fight = {
	token: number,
	ammo: number,
	cover: Cover?,
	lastSeen: Vector3?,
	lastSeenT: number,
	seeing: boolean,
	inRange: boolean, -- seen AND close enough for this weapon
	lastHp: number,
	hurtAt: number,
	nextBlind: number,
	barkAt: number,
	holds: number,
	forward: boolean,
	role: string, -- "base" | "flank"
	firing: boolean,
	started: boolean,
	spottedOnce: number,
}

local squad = {
	known = {} :: { [Player]: { pos: Vector3, t: number } },
	exposed = {} :: { [any]: boolean },
	movers = {} :: { [any]: boolean },
	claims = {} :: { [any]: Vector3 },
	blindBy = nil :: any,
	radioAt = 0,
	dispatchAt = 0,
	lastCount = 0,
	roleAt = 0,
}

local function now(): number
	return os.clock()
end

local function alive(n: any): boolean
	return n.state == "Hostile" and n.hum.Health > 0 and n.model.Parent ~= nil
end

local function members(): { any }
	local out = {}
	for _, n in N.list do
		if n.fight and n.state == "Hostile" and n.hum.Health > 0 and n.model.Parent then
			table.insert(out, n)
		end
	end
	return out
end

local function maxExposed(count: number): number
	if count <= 2 then
		return 1
	elseif count <= 4 then
		return 2
	end
	return 3
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

------------------------------------------------------------------ rays

local function worldParams(): RaycastParams
	local p = N.eyeParams() :: RaycastParams
	local ignore = table.clone(p.FilterDescendantsInstances)
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	p.FilterDescendantsInstances = ignore
	return p
end

local function blocked(params: RaycastParams, a: Vector3, b: Vector3): boolean
	return workspace:Raycast(a, b - a, params) ~= nil
end

local function floorAt(params: RaycastParams, p: Vector3): Vector3?
	local hit = workspace:Raycast(p + Vector3.new(0, 5, 0), Vector3.new(0, -14, 0), params)
	return if hit then hit.Position else nil
end

------------------------------------------------------------------ intel and radio

local function bark(n: any, kind: string, force: boolean?)
	local f = n.fight :: Fight
	local t = now()
	if not force and (t < f.barkAt or t < squad.radioAt) then
		return
	end
	local pool = (Lines.combat :: any)[kind] :: { string }?
	if not pool then
		return
	end
	f.barkAt = t + rng:NextNumber(5, 9)
	squad.radioAt = t + 1.4
	N.speak(n, Lines.pick(pool), if n.unit == "Guard" then "angry" else "normal", true)
end

local function percept(n: any, f: Fight)
	local pt, char = N.spotCrew(n.head.Position, 260)
	f.seeing = pt ~= nil
	local U = UNIT[n.unit] or UNIT.Guard
	f.inRange = pt ~= nil and (pt - n.head.Position).Magnitude <= U.range
	if pt and char then
		local t = now()
		f.lastSeen, f.lastSeenT = pt, t
		local pl = Players:GetPlayerFromCharacter(char)
		if pl then
			squad.known[pl] = { pos = pt, t = t }
		end
		if t - f.spottedOnce > 14 then
			f.spottedOnce = t
			bark(n, "spotted")
		end
	end
	local hp = n.hum.Health
	if hp < f.lastHp - 0.5 then
		f.hurtAt = now()
		if hp < n.hum.MaxHealth * 0.5 and rng:NextNumber() < 0.4 then
			bark(n, "hit")
		end
	end
	f.lastHp = hp
end

-- dispatch / cameras / witnesses: a rough position when nobody has seen the crew for a while
local function dispatch()
	local t = now()
	if t - squad.dispatchAt < 9 then
		return
	end
	squad.dispatchAt = t
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and N.isCrew(pl) then
			local k = squad.known[pl]
			if not k or t - k.t > 12 then
				local noise = Vector3.new(rng:NextNumber(-13, 13), 0, rng:NextNumber(-13, 13))
				squad.known[pl] = { pos = root.Position + noise, t = t - 6 }
			end
		end
	end
end

-- nearest known threat position (< 40 s old) for this unit
local function threat(n: any): (Vector3?, Player?)
	local best, bp, bd = nil, nil, math.huge
	local t = now()
	for pl, k in squad.known do
		if t - k.t < 40 and pl.Parent then
			local char = pl.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and N.isCrew(pl) then
				local d = (k.pos - n.root.Position).Magnitude
				if d < bd then
					best, bp, bd = k.pos, pl, d
				end
			end
		end
	end
	return best, bp
end

------------------------------------------------------------------ cover search

local DIRS = 14

local function findCovers(n: any, f: Fight, tgt: Vector3, U: any): { Cover }
	local params = worldParams()
	local myPos = n.root.Position
	local myFloor = floorAt(params, myPos) or (myPos - Vector3.new(0, 3, 0))
	local eye = tgt + Vector3.new(0, 0.6, 0)
	local curD = (flat(myPos) - flat(tgt)).Magnitude
	-- bearing of the squad's centre as seen from the threat (flankers want another angle)
	local centre = Vector3.zero
	local cnt = 0
	for _, o in members() do
		if o ~= n then
			centre += o.root.Position
			cnt += 1
		end
	end
	local axis = if cnt > 0 then flat(centre / cnt - tgt) else flat(myPos - tgt)
	local axisU = if axis.Magnitude > 0.1 then axis.Unit else Vector3.new(0, 0, 1)
	local scored: { { c: Cover, s: number } } = {}
	local wounded = n.hum.Health < n.hum.MaxHealth * 0.4
	for _, r in { 4, 7, 11, 16, 22 } do
		for i = 0, DIRS - 1 do
			local a = i / DIRS * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local guess = myFloor + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local g = floorAt(params, guess + Vector3.new(0, myFloor.Y - guess.Y + 1, 0))
			if g and math.abs(g.Y - myFloor.Y) < 2.5 then
				local dT = (flat(g) - flat(tgt)).Magnitude
				if dT >= 5 then
					local tall = blocked(params, eye, g + Vector3.new(0, 0.5, 0)) and blocked(params, eye, g + Vector3.new(0, 2.6, 0)) and blocked(params, eye, g + Vector3.new(0, 4.4, 0))
					local low = not tall and blocked(params, eye, g + Vector3.new(0, 0.5, 0)) and blocked(params, eye, g + Vector3.new(0, 1.5, 0)) and blocked(params, eye, g + Vector3.new(0, 2.7, 0))
					if tall or low then
						local cover: Cover = { pos = g, stance = if tall then "stand" else "crouch", peek = nil, peekStance = "stand" }
						-- where can it see the threat from, right next to the cover?
						local toT = flat(tgt - g)
						if toT.Magnitude > 0.1 then
							local perp = Vector3.new(-toT.Unit.Z, 0, toT.Unit.X)
							for _, side in { 1, -1 } do
								local p = g + perp * side * 2.6
								local pg = floorAt(params, p + Vector3.new(0, g.Y - p.Y + 1, 0))
								if pg and math.abs(pg.Y - g.Y) < 1.2 and not blocked(params, g + Vector3.new(0, 1.5, 0), pg + Vector3.new(0, 1.5, 0)) and not blocked(params, pg + Vector3.new(0, 4.2, 0), eye) then
									cover.peek, cover.peekStance = pg, "stand"
									break
								end
							end
							if not cover.peek and low and not blocked(params, g + Vector3.new(0, 4.2, 0), eye) then
								cover.peek, cover.peekStance = g, "stand" -- stand up over the counter
							end
						end
						local dMe = (g - myPos).Magnitude
						local score = dMe + math.abs(dT - U.engage) * 0.7
						if f.forward then
							score += math.max(0, dT - curD) * 2.2 -- advancing: only cover that is closer
						end
						if not cover.peek then
							score += if f.forward then 8 else 60
						end
						if tall then
							score -= 3
						end
						if f.role == "flank" then
							local off = flat(g - tgt)
							if off.Magnitude > 0.1 then
								local ang = math.deg(math.acos(math.clamp(off.Unit:Dot(axisU), -1, 1)))
								score -= math.clamp(ang - 30, 0, 80) * 0.5
							end
						end
						if wounded then
							score += math.max(0, 28 - dT) * 1.5 -- wounded: stay far
						end
						for o, cpos in squad.claims do
							if o ~= n and (cpos - g).Magnitude < 3.5 then
								score += 40
							end
						end
						table.insert(scored, { c = cover, s = score })
					end
				end
			end
		end
	end
	table.sort(scored, function(a, b)
		return a.s < b.s
	end)
	local out = {}
	for i = 1, math.min(4, #scored) do
		table.insert(out, scored[i].c)
	end
	return out
end

local function coverValid(n: any, c: Cover, tgt: Vector3): boolean
	local params = worldParams()
	local eye = tgt + Vector3.new(0, 0.6, 0)
	local top = if c.stance == "stand" then 4.4 else 2.7
	return blocked(params, eye, c.pos + Vector3.new(0, top, 0)) and blocked(params, eye, c.pos + Vector3.new(0, 1.2, 0))
end

------------------------------------------------------------------ actions

local function setAim(n: any, pt: Vector3?)
	n.aimAt = pt
end

local function moveTo(n: any, f: Fight, dest: Vector3, speed: number, arrive: number?): boolean
	local token = f.token + 1
	f.token = token
	Combat.stats.moves += 1
	setAim(n, nil)
	N.setStance(n, "stand")
	return Nav.walk(n.hum, n.root, dest, {
		speed = speed,
		arrive = arrive or 2,
		timeout = 14,
		abort = function(): boolean
			if f.token ~= token or not alive(n) then
				return true
			end
			-- someone right in our face while we run: stop and fight
			return f.seeing and f.lastSeen ~= nil and (flat(f.lastSeen) - flat(n.root.Position)).Magnitude < 6
		end,
	})
end

local function burst(n: any, f: Fight, U: any, count: number, dmgMul: number, spread: number)
	f.firing = true
	Combat.stats.bursts += 1
	for _ = 1, count do
		if not alive(n) or f.ammo <= 0 then
			break
		end
		local pt = N.spotCrew(n.head.Position, U.range)
		if not pt then
			break
		end
		setAim(n, pt)
		N.fire(n, pt, U.dmg * dmgMul, spread)
		f.ammo -= 1
		task.wait(U.rate)
	end
	f.firing = false
end

local function reloadIfNeeded(n: any, f: Fight, U: any)
	if f.ammo > 0 then
		return
	end
	bark(n, "reload", true)
	setAim(n, nil)
	local t0 = now()
	while now() - t0 < U.reload and alive(n) do
		task.wait(0.15)
	end
	f.ammo = U.mag
end

-- right in front of us: stand and fight
local function closeFight(n: any, f: Fight, U: any)
	N.setStance(n, "stand")
	n.hum:MoveTo(n.root.Position)
	local t0 = now()
	while alive(n) and now() - t0 < 4 and f.seeing do
		percept(n, f)
		if f.lastSeen then
			setAim(n, f.lastSeen)
		end
		task.wait(U.react[1])
		if f.seeing then
			burst(n, f, U, rng:NextInteger(U.burstMin, U.burstMax), 1, U.spread * 1.15)
			reloadIfNeeded(n, f, U)
		end
		task.wait(rng:NextNumber(0.25, 0.6))
	end
	setAim(n, nil)
end

-- wait in cover; returns when it is time to do something else
local function hold(n: any, f: Fight, U: any, tgt: Vector3)
	local c = f.cover :: Cover
	N.setStance(n, c.stance)
	setAim(n, nil)
	n.hum:MoveTo(n.root.Position)
	local wounded = n.hum.Health < n.hum.MaxHealth * 0.4
	local dur = rng:NextNumber(U.hold[1], U.hold[2]) * (if wounded then 2 else 1)
	if now() - f.hurtAt < 2.5 then
		dur += 1.2 -- under fire: keep the head down
	end
	if (not f.seeing and f.lastSeenT < now() - 8 and (flat(tgt) - flat(n.root.Position)).Magnitude > 35) or (f.seeing and not f.inRange) then
		dur = rng:NextNumber(0.2, 0.7) -- far (out of weapon range): keep moving up
	end
	local t0 = now()
	local lastCheck = t0
	while alive(n) and now() - t0 < dur do
		percept(n, f)
		task.wait(0.15)
		if f.seeing and f.lastSeen and (flat(f.lastSeen) - flat(n.root.Position)).Magnitude < 7 then
			return -- rushed
		end
		if now() - lastCheck > 0.7 then
			lastCheck = now()
			local nt = threat(n)
			if nt and not coverValid(n, c, nt) then
				f.cover = nil -- the threat moved: this cover is useless now
				return
			end
		end
		-- rare, weak blind fire at the last place the threat was seen
		if not f.seeing and f.lastSeen and now() - f.lastSeenT < 5 and now() >= f.nextBlind and squad.blindBy == nil and f.ammo >= 4 and not f.firing and rng:NextNumber() < 0.05 then
			local dist = (f.lastSeen - n.root.Position).Magnitude
			if dist < 40 then
				squad.blindBy = n
				Combat.stats.blind += 1
				f.nextBlind = now() + rng:NextNumber(14, 22)
				bark(n, "suppress")
				local aim = f.lastSeen + Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1.5, 1.5))
				setAim(n, aim)
				f.firing = true
				for _ = 1, rng:NextInteger(2, 3) do
					if not alive(n) or f.ammo <= 0 then
						break
					end
					N.fire(n, aim, U.dmg * 0.4, 9)
					f.ammo -= 1
					task.wait(U.rate)
				end
				f.firing = false
				setAim(n, nil)
				squad.blindBy = nil
			end
		end
	end
	f.holds += 1
end

local function peek(n: any, f: Fight, U: any)
	local c = f.cover :: Cover
	squad.exposed[n] = true
	Combat.stats.peeks += 1
	do
		local cnt = 0
		for _ in squad.exposed do
			cnt += 1
		end
		Combat.stats.maxExposed = math.max(Combat.stats.maxExposed, cnt)
	end
	local wounded = n.hum.Health < n.hum.MaxHealth * 0.4
	local hp0 = n.hum.Health
	local spot = c.peek
	if spot and (spot - n.root.Position).Magnitude > 0.8 then
		moveTo(n, f, spot, U.speed * 0.8, 0.9)
	else
		N.setStance(n, "stand")
	end
	n.hum:MoveTo(n.root.Position)
	-- reaction time, then shoot what is visible
	local t0 = now()
	local react = rng:NextNumber(U.react[1], U.react[2])
	local endT = t0 + rng:NextNumber(U.peek[1], U.peek[2]) + react
	local fired = 0
	while alive(n) and now() < endT do
		percept(n, f)
		if f.inRange and f.lastSeen then
			setAim(n, f.lastSeen)
			if now() - t0 >= react and not f.firing then
				burst(n, f, U, rng:NextInteger(U.burstMin, U.burstMax), 1, U.spread)
				fired += 1
				if fired >= 2 or f.ammo <= 0 then
					break
				end
			end
		elseif now() - t0 > 0.9 then
			break -- nothing to see from here
		end
		if n.hum.Health < hp0 - 18 then
			break -- hit hard: back to cover
		end
		task.wait(0.1)
	end
	setAim(n, nil)
	-- back behind cover
	if (c.pos - n.root.Position).Magnitude > 1.2 then
		moveTo(n, f, c.pos, U.speed, 1)
	end
	squad.exposed[n] = nil
	if f.ammo <= 0 then
		N.setStance(n, c.stance)
		reloadIfNeeded(n, f, U)
	end
	if wounded then
		f.holds += 1
	end
end

------------------------------------------------------------------ the unit's brain

local function brain(n: any)
	local f = n.fight :: Fight
	local U = UNIT[n.unit] or UNIT.Guard
	f.ammo = U.mag
	n.hum.WalkSpeed = U.speed
	task.wait(rng:NextNumber(0, 0.5))
	while alive(n) do
		percept(n, f)
		local tgt = threat(n)
		if not tgt and f.lastSeen and now() - f.lastSeenT < 40 then
			tgt = f.lastSeen
		end
		if not tgt then
			dispatch()
			n.aimAt = nil
			task.wait(0.4)
			continue
		end
		-- 1. in our face: fight
		if f.seeing and f.lastSeen and (flat(f.lastSeen) - flat(n.root.Position)).Magnitude < 7 then
			closeFight(n, f, U)
			f.cover = nil
			f.forward = false
			continue
		end
		-- 2. cover: keep it, or find one (advancing in bounds when the squad is hidden)
		local c = f.cover
		if c and not coverValid(n, c, tgt) then
			f.cover = nil
			c = nil
		end
		-- bounding advance: out of weapon range, or after a few turns in cover, a unit moves up (a few at a time)
		local distT = (flat(tgt) - flat(n.root.Position)).Magnitude
		if c and ((distT > U.range - 6 and f.holds >= 1) or (f.holds >= 3 and distT > U.engage + 8)) then
			local mv = 0
			for _ in squad.movers do
				mv += 1
			end
			if mv < math.max(1, math.floor(#members() / 3)) then
				f.cover, f.holds, f.forward, c = nil, 0, true, nil
			end
		end
		if not c then
			squad.claims[n] = nil
			local options = findCovers(n, f, tgt, U)
			local moved = false
			squad.movers[n] = true
			for _, cand in options do
				squad.claims[n] = cand.pos
				if (cand.pos - n.root.Position).Magnitude < 2.4 or moveTo(n, f, cand.pos, U.speed, 1.6) then
					f.cover = cand
					moved = true
					break
				end
				if not alive(n) then
					break
				end
			end
			squad.movers[n] = nil
			f.forward = false
			if moved then
				bark(n, if f.role == "flank" then "flank" else "cover")
			else
				-- nowhere to hide: crouch where we are and see what happens
				N.setStance(n, "crouch")
				task.wait(0.6)
			end
			continue
		end
		-- 3. hide, then step out and shoot (only a few units at a time)
		hold(n, f, U, tgt)
		if not alive(n) then
			break
		end
		if f.cover then
			local exposedNow = 0
			for _ in squad.exposed do
				exposedNow += 1
			end
			local wounded = n.hum.Health < n.hum.MaxHealth * 0.4
			if f.ammo <= 0 then
				reloadIfNeeded(n, f, U)
			elseif exposedNow < maxExposed(#members()) and (not wounded or rng:NextNumber() < 0.4) then
				if f.cover.peek then
					peek(n, f, U)
				else
					f.holds += 2 -- no angle from here: move up next turn
				end
			end
		end
	end
	squad.exposed[n] = nil
	squad.movers[n] = nil
	squad.claims[n] = nil
	if squad.blindBy == n then
		squad.blindBy = nil
	end
	n.aimAt = nil
end

------------------------------------------------------------------ squad loop

function Combat.reset()
	table.clear(squad.known)
	table.clear(squad.exposed)
	table.clear(squad.movers)
	table.clear(squad.claims)
	squad.blindBy = nil
	squad.dispatchAt = 0
	squad.lastCount = 0
end

function Combat.init(npcs: any)
	N = npcs
	task.spawn(function()
		while true do
			task.wait(0.4)
			local ms = {}
			for _, n in N.list do
				if n.state == "Hostile" and n.hum.Health > 0 and n.model.Parent and (n.role == "Guard" or n.role == "Police") then
					if not n.fight then
						n.fight = {
							token = 0, ammo = 0, cover = nil, lastSeen = nil, lastSeenT = 0, seeing = false, inRange = false, lastHp = n.hum.Health,
							hurtAt = 0, nextBlind = now() + rng:NextNumber(6, 12), barkAt = 0, holds = 0, forward = true, role = "base",
							firing = false, started = false, spottedOnce = -100,
						} :: Fight
					end
					local f = n.fight :: Fight
					if not f.started then
						f.started = true
						task.spawn(brain, n)
					end
					table.insert(ms, n)
				end
			end
			-- someone went down: call it out
			if #ms < squad.lastCount and #ms > 0 then
				bark(ms[rng:NextInteger(1, #ms)], "down", true)
			end
			squad.lastCount = #ms
			-- roles: every third unit (furthest from the threat first) goes around the flank
			local t = now()
			if t - squad.roleAt > 5 and #ms >= 3 then
				squad.roleAt = t
				table.sort(ms, function(a, b)
					return a.root.Position.Z < b.root.Position.Z
				end)
				for i, n in ms do
					local f = n.fight :: Fight
					local want = if i % 3 == 0 then "flank" else "base"
					if f.role ~= want and not squad.exposed[n] then
						f.role = want
						f.cover = nil
					end
				end
			end
		end
	end)
end

return Combat
