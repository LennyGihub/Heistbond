--!strict
-- Driving heist vehicles (arcade, a bit goofy): while the local player sits in a vehicle's DriverSeat,
-- set the chassis movers from the seat's throttle/steer: speed builds up and drops smoothly, steering
-- works better at speed, the body leans into turns, the wheels spin. The server gave us network
-- ownership, so the physics runs here.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local speed = 0

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		speed = 0
		return
	end
	local veh = seat.Parent
	if not veh or not CollectionService:HasTag(veh, "HeistVehicle") then
		return
	end
	local chassis = (veh :: Model).PrimaryPart
	if not chassis then
		return
	end
	local move = chassis:FindFirstChild("Move") :: LinearVelocity?
	local turn = chassis:FindFirstChild("Turn") :: AngularVelocity?
	if not move or not turn then
		return
	end
	local maxSpeed = (veh:GetAttribute("Speed") :: number?) or 60
	local turnRate = (veh:GetAttribute("TurnRate") :: number?) or 1.8
	local throttle = (seat :: VehicleSeat).ThrottleFloat
	local steer = (seat :: VehicleSeat).SteerFloat
	-- Studio test hook: player attribute TestDrive = Vector2(throttle, steer) stands in for the keys
	local td = if RunService:IsStudio() then player:GetAttribute("TestDrive") else nil
	if typeof(td) == "Vector2" then
		throttle, steer = td.X, td.Y
	end
	-- speed with inertia (reverse is slower)
	local target = if throttle > 0 then maxSpeed * throttle elseif throttle < 0 then maxSpeed * 0.4 * throttle else 0
	local accel = if math.abs(target) > math.abs(speed) then 28 else 45
	speed += math.clamp(target - speed, -accel * dt, accel * dt)
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.01 then
		flat = flat.Unit
	end
	move.PlaneVelocity = Vector2.new(flat.X * speed, flat.Z * speed)
	-- steering grows with speed, flips in reverse
	local grip = math.clamp(math.abs(speed) / 20, 0, 1)
	local dir = if speed >= 0 then 1 else -1
	turn.AngularVelocity = Vector3.new(0, -steer * turnRate * grip * dir, 0)
	-- goofy: the body leans into turns and bobs
	local up = chassis:FindFirstChild("Upright") :: AlignOrientation?
	if up then
		local lean = math.clamp(steer * grip * 0.12, -0.15, 0.15)
		local bob = math.sin(os.clock() * 9) * 0.015 * grip
		local att = chassis:FindFirstChild("Drive") :: Attachment?
		if att then
			att.CFrame = CFrame.Angles(bob, 0, lean)
		end
	end
end)
