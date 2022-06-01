--[[
This is a snippet of code from a module in my game Ragdoll WT: Remastered.
It creates an explosion that can damage, ragdoll, and destroy limbs of other players.
You can test it out in game by using an explosive throwable on the dummy.
--]]

--Defining constants
local SMOKE_LIFETIME = 8
local SMOKE_LIFETIME_DIVISOR = 15
local EXPLOSION_SOUND_DIVISOR = 3
local SMOKE_EMIT_MULTIPLIER = 2
local RAGDOLL_DISTANCE_DIVISOR = 2
local RAGDOLL_TIME_DIVISOR = 15
local RAGDOLL_TIME_MAX = 10
local DAMAGE_MULTIPLIER = 2.5
local KNOCKBACK_SPEED_MULTIPLIER = 1.25
local BLUR_STRENGTH_DIVISOR = 10
local EXPLOSION_SHAKE_INTENSITY_DIVISOR = 40
local EXPLOSION_SHAKE_MAXRANGE_MULTIPLIER = 3
local EXPLOSION_SHAKE_DURATION_DIVISOR = 20
local EXPLOSION_POWER_LIMB_DESTROY_MIN = 50

function SM:CreateExplosion(position, power, owner, ownerItem, immunePlayer) --Variables for the explosion. owner, ownerItem, and immunePlayer are all optional.
	task.spawn(function() --Using task.spawn so it does not yield to create the explosion
		--Set up all variables
		local Explosion = ServerStorage.Attacks.Explosion:Clone()
		local Hitbox = Explosion.ExplosionHitbox
		local ExplosionSound = Hitbox.Explosion
		local SmokePart = Explosion.ExplosionSmokeVisual
		local Smoke = SmokePart.Smoke
		local BlastGui = Explosion.ExplosionBlastVisual.ExplosionBlastGui
		local BlastImage = BlastGui.BlastImage
		
		local tweening = TweenInfo.new(.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 0, false, 0)
		local properties = {Size = UDim2.new(power * 2, 0, power * 2, 0)}
		local BlastExpand = ServerTweenService:GetTweenObject(BlastGui, tweening, properties)
		
		local properties = {ImageTransparency = 1}
		local BlastFade = ServerTweenService:GetTweenObject(BlastImage, tweening, properties)
		
		--Set position of explosion and parent to workspace
		Explosion:PivotTo(CFrame.new(position))
		Hitbox.Size = Vector3.new(power, power, power)
		SmokePart.Size = Vector3.new(power, power, power)
		local CALC_SMOKE_LIFETIME_1, CALC_SMOKE_LIFETIME_2 = power / SMOKE_LIFETIME, (power / SMOKE_LIFETIME + power / SMOKE_LIFETIME / SMOKE_LIFETIME_DIVISOR)
		Smoke.Lifetime = NumberRange.new(CALC_SMOKE_LIFETIME_1, CALC_SMOKE_LIFETIME_2)
		ExplosionSound.Volume = power / EXPLOSION_SOUND_DIVISOR
		Debris:AddItem(Explosion, (CALC_SMOKE_LIFETIME_1 + CALC_SMOKE_LIFETIME_2) + ExplosionSound.TimeLength)
		Explosion.Parent = workspace
		
		local immuneChar
		if immunePlayer then
			immuneChar = immunePlayer.Character
		end
		local hitList = {}
		--This for loop using the Spatial Query API to check for any players within the blast hitbox, and damaging them accordingly.
		for _,v in pairs(workspace:GetPartsInPart(Hitbox)) do
			if v.Parent:FindFirstChild("Humanoid") and not SM:IsLimbDestroyed(v) and not table.find(hitList, v.Parent) and not v.Parent:FindFirstChildWhichIsA("ForceField") and v.Parent ~= immuneChar then
				local char = v.Parent
				local hitPlayer = Players:GetPlayerFromCharacter(char)
				local humanoid = char.Humanoid
				local hrp = char.HumanoidRootPart
				local ragdoll = false
				local stunTime = power / RAGDOLL_TIME_DIVISOR
				local distance = (Hitbox.Position - hrp.Position).Magnitude
				--This makes sure that the explosion cannot hit you through walls, unless you are too close. This blasting through walls is dependent on explosion power.
				local raycastParams = RaycastParams.new()
				raycastParams.FilterDescendantsInstances = {v.Parent}
				raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
				raycastParams.CollisionGroup = "OnlyDefault"
				local rayOrigin = Hitbox.Position
				local rayDirection = (v.Position - Hitbox.Position).Unit*distance
				local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
				if raycastResult and distance > power/5 then --Go to next player limb in table if cannot go through wall.
					continue
				end
				table.insert(hitList, v.Parent) --Add character to table so it is not checked for again and only damages the character once.
				
				local ragdollRadius = power / RAGDOLL_DISTANCE_DIVISOR
				if distance <= ragdollRadius then
					ragdoll = true
				end
				
				local maxDamage = power * DAMAGE_MULTIPLIER * SM:GetDmgMultiplier(char)
				local damage = maxDamage - (distance / power * maxDamage)
				if owner then
					SM:SetKillerName(owner, char)
				end
				if ownerItem then
					SM:SetKillerItem(ownerItem, char)
				end
				SM:SetDeathCause("Exploded", char)
				humanoid:TakeDamage(damage)
				SM:Scream(char)
				if humanoid.Health <= 0 then
					ragdoll = true
				end
				
				--If the explosion has determined that the character will ragdoll, this if statement will run, doing many things.
				if ragdoll == true then
					SM:Ragdoll(true, char)
					SM:AddRagdollTime(stunTime, char)
					local KNOCKBACK_SPEED = power * KNOCKBACK_SPEED_MULTIPLIER
					local MAGNITUDE_CALC = (Hitbox.Position - hrp.Position).Magnitude
					local CALC_KNOCKBACK_VELOCITY
					if MAGNITUDE_CALC ~= 0 then
						CALC_KNOCKBACK_VELOCITY = (Hitbox.Position - hrp.Position).Unit * KNOCKBACK_SPEED * -1
					else
						CALC_KNOCKBACK_VELOCITY = (Vector3.new(0.0001, 0.0001, 0.0001)).Unit * KNOCKBACK_SPEED * -1
					end
					--First the knockback is created using a different function in the module.
					SM:CreateKnockback(char.HumanoidRootPart.KnockbackAttachment, CALC_KNOCKBACK_VELOCITY)
					--If the explosion is powerful enough, it will explode a limb off. Explosions cannot explode both legs off or the Right Arm.
					if power >= 50 then
						if humanoid.Health > 0 then
							local destroyableLimbs = {}
							table.insert(destroyableLimbs, char["Left Arm"])
							table.insert(destroyableLimbs, char["Right Leg"])
							table.insert(destroyableLimbs, char["Left Leg"])
							for i,v in pairs(destroyableLimbs) do
								if SM:IsLimbDestroyed(v) then
									table.remove(destroyableLimbs, i)
								end
							end
							if #destroyableLimbs ~= 0 then
								local randomLimb = destroyableLimbs[math.random(1, #destroyableLimbs)]
								if (randomLimb.Name == "Left Leg" or randomLimb.Name == "Right Leg") and (not SM:IsLimbDestroyed(char["Right Leg"]) and not SM:IsLimbDestroyed(char["Left Leg"])) then
									local cutLimb = SM:DestroyLimb(randomLimb)[randomLimb.Name]
									local KnockbackAttachment = Instance.new("Attachment")
									KnockbackAttachment.Parent = cutLimb
									local CALC_KNOCKBACK_VELOCITY = (Hitbox.Position - cutLimb.Position).Unit * KNOCKBACK_SPEED * -1
									SM:CreateKnockback(KnockbackAttachment, CALC_KNOCKBACK_VELOCITY)
								elseif randomLimb.Name == "Left Arm" then
									local cutLimb = SM:DestroyLimb(randomLimb)[randomLimb.Name]
									local KnockbackAttachment = Instance.new("Attachment")
									KnockbackAttachment.Parent = cutLimb
									local CALC_KNOCKBACK_VELOCITY = (Hitbox.Position - cutLimb.Position).Unit * KNOCKBACK_SPEED * -1
									SM:CreateKnockback(KnockbackAttachment, CALC_KNOCKBACK_VELOCITY)
								end
							end
						else
							for _,v in pairs(char:GetChildren()) do
								if v:IsA("Part") then
									local cutLimb = SM:DestroyLimb(v)
									if cutLimb ~= nil then
										cutLimb = cutLimb[v.Name]
									else
										continue
									end
									local KnockbackAttachment = Instance.new("Attachment")
									KnockbackAttachment.Parent = cutLimb
									local CALC_LIMB_KNOCKBACK_VELOCITY
									local MAGNITUDE_CALC = (Hitbox.Position - cutLimb.Position).Magnitude
									if MAGNITUDE_CALC ~= 0 then
										CALC_LIMB_KNOCKBACK_VELOCITY = (Hitbox.Position - cutLimb.Position).Unit * KNOCKBACK_SPEED * -1
									else
										CALC_LIMB_KNOCKBACK_VELOCITY = (Vector3.new(0.0001, 0.0001, 0.0001)).Unit * KNOCKBACK_SPEED * -1
									end
									SM:CreateKnockback(KnockbackAttachment, CALC_LIMB_KNOCKBACK_VELOCITY)
								end
							end
						end
					end
				end
				--Send Blur event to player so they have a visual for when they are hit by an explosion.
				if hitPlayer then
					RemoteEvent:FireClient(hitPlayer, "Blur", power / BLUR_STRENGTH_DIVISOR, stunTime)
				end
			end
		end
		--Send a shake to all players dependent on distance from explosion.
		RemoteEvent:FireAllClients("DistanceShake", Hitbox.Position, power / EXPLOSION_SHAKE_INTENSITY_DIVISOR, power * EXPLOSION_SHAKE_MAXRANGE_MULTIPLIER, power / EXPLOSION_SHAKE_DURATION_DIVISOR)
		--Finally, play all explosion visuals after the damage to characters is dealt with.
		ExplosionSound:Play()
		BlastExpand:Play()
		BlastFade:Play()
		task.wait(.1)
		Smoke:Emit(power * SMOKE_EMIT_MULTIPLIER)
	end)
end
