--!strict
-- Where a rifle sits against the body (third person). Shared by WeaponServer (replicated pose),
-- GunClient (smooth local pose) and WeaponFxListener (other players' reload animation).
-- The gun is welded to the upper torso (not the hand); arm IK then puts both hands on it.
local GunPose = {}

local STOCK_Z = 1.25 -- handle-space distance from the handle centre back to the butt of the stock
GunPose.MAX_YAW = math.rad(60) -- how far the gun can swing left/right of where the body faces

function GunPose.torsoFor(char: Model): BasePart?
	return (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
end

-- torso-space point the gun rotates around (stock against the shoulder / held at the chest)
function GunPose.pivot(torsoSize: Vector3, aim: number): Vector3
	local shoulder = Vector3.new(torsoSize.X * 0.27, torsoSize.Y * 0.32, -torsoSize.Z * 0.5 - 0.05)
	local chest = Vector3.new(torsoSize.X * 0.22, torsoSize.Y * 0.1, -torsoSize.Z * 0.5 - 0.1)
	return chest:Lerp(shoulder, math.clamp(aim, 0, 1))
end

-- yaw/pitch (radians) that point the gun from the pivot at a world position
function GunPose.anglesTo(torso: BasePart, aim: number, target: Vector3): (number, number)
	local d = torso.CFrame:PointToObjectSpace(target) - GunPose.pivot(torso.Size, aim)
	local yaw = math.atan2(-d.X, -d.Z)
	local pitch = math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z))
	return yaw, pitch
end

-- aim: 0 = held at the chest, 1 = shouldered. pitch/yaw: radians (+pitch = up, +yaw = left).
function GunPose.cframe(torsoSize: Vector3, aim: number, pitch: number, yaw: number?): CFrame
	local a = math.clamp(aim, 0, 1)
	local y = math.clamp(yaw or 0, -GunPose.MAX_YAW, GunPose.MAX_YAW)
	local p = math.clamp(pitch, -1.3, 1.3)
	local back = STOCK_Z - 0.3 * (1 - a) -- at the chest the stock tucks under the arm
	return CFrame.new(GunPose.pivot(torsoSize, a))
		* CFrame.Angles(0, y, 0)
		* CFrame.Angles(p, 0, 0)
		* CFrame.new(0, 0.05 * a, -back)
end

return GunPose
