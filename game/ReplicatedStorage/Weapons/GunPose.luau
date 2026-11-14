--!strict
-- Where a rifle sits against the body (third person). Shared by WeaponServer (replicated pose),
-- GunClient (smooth local pose) and WeaponFxListener (other players' reload animation).
-- The gun is welded to the upper torso (not the hand); arm IK puts both hands on it.
-- Both poses were solved so blocky R15 arms (about 1.9 studs from shoulder to grip) reach the
-- pistol grip AND the foregrip without the gun passing through the body.
local GunPose = {}

local GRIP = Vector3.new(0, -0.272, 0.187) -- handle-space pistol grip (same point as Handle.RightHandIK)

-- low ready (not aiming): right hand at the chest, muzzle 30 deg left and 35 deg down
local READY_GRIP = Vector3.new(0.12, 0.38, -0.82) -- torso space, for a standard 2 x 1.6 x 1 torso
local READY_ROT = CFrame.Angles(0, math.rad(30), 0) * CFrame.Angles(math.rad(-35), 0, 0)

-- aiming/shooting: body square to the target, rifle centred on the chest with the stock pressed in,
-- right hand at chest height (elbow hangs down), left hand on the front of the magazine well
local AIM_GRIP = Vector3.new(0.0, 0.48, -0.8)
GunPose.BLADE = 0
-- where the left hand holds the gun (handle space): foregrip at low ready, magazine well while aiming
GunPose.LEFT_READY = Vector3.new(0, -0.156, -0.746)
GunPose.LEFT_AIM = Vector3.new(0, -0.12, -0.5)
GunPose.MAX_YAW = math.rad(75) -- how far the gun can turn off the torso's facing

local STANDARD = Vector3.new(2, 1.6, 1)

function GunPose.torsoFor(char: Model): BasePart?
	return (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
end

-- torso-space point the gun turns around (the right hand on the grip)
function GunPose.pivot(torsoSize: Vector3, aim: number): Vector3
	return READY_GRIP:Lerp(AIM_GRIP, math.clamp(aim, 0, 1)) * (torsoSize / STANDARD)
end

-- yaw/pitch (radians) that point the gun from the pivot at a world position
function GunPose.anglesTo(torso: BasePart, aim: number, target: Vector3): (number, number)
	local d = torso.CFrame:PointToObjectSpace(target) - GunPose.pivot(torso.Size, aim)
	local yaw = math.atan2(-d.X, -d.Z)
	local pitch = math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z))
	return yaw, pitch
end

-- aim: 0 = low ready (fixed carry), 1 = shouldered and pointed by pitch/yaw (radians, +pitch = up, +yaw = left).
function GunPose.cframe(torsoSize: Vector3, aim: number, pitch: number, yaw: number?): CFrame
	local a = math.clamp(aim, 0, 1)
	local y = math.clamp(yaw or GunPose.BLADE, -GunPose.MAX_YAW, GunPose.MAX_YAW)
	local p = math.clamp(pitch, -1.3, 1.3)
	local s = torsoSize / STANDARD
	local shouldered = CFrame.new(AIM_GRIP * s) * CFrame.Angles(0, y, 0) * CFrame.Angles(p, 0, 0) * CFrame.new(-GRIP)
	local ready = CFrame.new(READY_GRIP * s) * READY_ROT * CFrame.new(-GRIP)
	return ready:Lerp(shouldered, a)
end

-- the handle's CFrame for a gun held with its pistol grip at `grip` (world) and the barrel along `look`,
-- rolled `roll` radians about the barrel (0 = upright, +pi/2 = on its side with the top to the left).
-- Used for blind fire over low cover.
function GunPose.handleAt(grip: Vector3, look: Vector3, roll: number?): CFrame
	return CFrame.lookAt(grip, grip + look) * CFrame.Angles(0, 0, roll or 0) * CFrame.new(-GRIP)
end

return GunPose
