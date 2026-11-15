--!strict
-- Timings shared by the server and the client for the cinematics: when the real effect happens
-- (seconds after the cinematic starts) and how long the cinematic lasts.
local Noobla = require(script.Parent:WaitForChild("Noobla"))

local Meta = {
	c4 = { effectAt = 4.75, len = 4.75 + Noobla.c4Fuse + 1.3 },
	drill = { effectAt = 3.35, len = 7.4 },
	card = { effectAt = 3.7, len = 7.2 },
	hack = { effectAt = 3.0, len = 6.4 },
	rope = { effectAt = 1.2, len = 2.0 },
	-- opening: the van drives from the hideout to the bank (drive), stops, the crew gets out
	intro = { len = 11.4, drive = 8.0, swap = 8.35, door = 8.75, out = 9.25 },
	-- getaway: 6 seconds from the bank to the hideout garage
	escape = { len = 6.1 },
}

-- where the crew's van parks in front of the bank (pivot = ground under the van's middle, facing +X)
Meta.introPark = CFrame.new(96, 0.1, 176) * CFrame.Angles(0, -math.pi / 2, 0)
-- the van's road: out of the hideout, up its road, right onto the bank street, to the parking spot
Meta.introPath = { Vector3.new(-170, 0.1, 44), Vector3.new(-170, 0.1, 176), Vector3.new(96, 0.1, 176) }
-- the getaway vehicle's final place in the hideout garage (chassis pivot, nose in)
Meta.garage = CFrame.lookAt(Vector3.new(-170, 1.7, 12), Vector3.new(-170, 1.7, 0))
-- where the riders stand once home (around the vehicle, inside the escape zone)
Meta.garageSpots = {
	Vector3.new(-161, 3.5, 8), Vector3.new(-179, 3.5, 8), Vector3.new(-161, 3.5, 16), Vector3.new(-179, 3.5, 16),
	Vector3.new(-161, 3.5, 22), Vector3.new(-179, 3.5, 22), Vector3.new(-165, 3.5, 24), Vector3.new(-175, 3.5, 24),
}

return Meta
