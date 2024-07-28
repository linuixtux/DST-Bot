--[[ Misc functions relating to combat ]]--

require "brains/ai_build_helper"

-- Just go best to worst I guess
local weaponTierList = {
	"ruins_bat",
	"glasscutter",
	"nightsword",
	"nightstick",
	"spear_wathgrithr",
	"spear"
}

--
local headArmorTierList = {
	"ruinshat",
	"wathgrithrhat",
	"footballhat"
}

-- If we have no hat armor, will queue a build for the best it can.
function BuildHatArmor(inst)
	local allArmorInInventory = inst.components.inventory:FindItems(function(item) return
			item.components.armor and item.components.equippable and item.components.equippable.equipslot == EQUIPSLOTS.HEAD end)

	local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)



	if #allArmorInInventory == 0 and not (equipped and equipped.components.armor) then
		local canBuildHat = nil
		for k,v in ipairs(headArmorTierList) do
			if canBuildHat == nil and inst.components.builder:KnowsRecipe(v) and CanPlayerBuildThis(inst, v) then -- CanPlayerBuildThis(inst, v) then
				canBuildHat = v
			end
		end

		if canBuildHat ~= nil and inst.waitingForBuild == nil then
			BuildIfAble(inst, canBuildHat)
			-- -- TODO: Need to check if it's safe to build this. If it's not safe...then don't start!
			-- --       Maybe use what I've got...or run away to build one? No idea.
			-- inst.waitingForBuild = canBuildHat
			-- inst.brain:SetSomethingToBuild(canBuildHat,nil,
			-- 	function() inst.waitingForBuild = nil end,function() inst.waitingForBuild = nil end)

			-- Gotta wait for that spear to be built
			DebugPrint(inst, "Making a " .. tostring(canBuildHat))
			return
		end
	end

end

function BuildAWeapon(inst)

	local allWeaponsInInventory = inst.components.inventory:FindItems(function(item) return
		item.components.weapon and item.components.equippable and item.components.weapon.damage > 0 end)

	local highestDamageWeapon = nil
	-- The above does not count equipped weapons
	local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

	if equipped and equipped.components.weapon and equipped.components.weapon.damage > 0 then
		highestDamageWeapon = equipped
	end

	for k,v in pairs(allWeaponsInInventory) do
		if highestDamageWeapon == nil then
			highestDamageWeapon = v
		else
			if v.components.weapon.damage > highestDamageWeapon.components.weapon.damage then
				highestDamageWeapon = v
			end
		end
	end

	-- TODO: Consider an axe or pickaxe a valid weapon if we are under attack already!
	--       The spear condition is only if we are going to actively hunt something.

	-- We don't have a weapon...can we make one?
	-- TODO: What do we try to make? Only seeing if we can make a spear here as I don't consider an axe or
	--       a pickaxe a valid weapon. Should probably excluce
	if highestDamageWeapon == nil or (highestDamageWeapon and highestDamageWeapon.components.weapon.damage < 34) then
		local canBuildWeapon = nil
		for k,v in ipairs(weaponTierList) do
			if canBuildWeapon == nil and inst.components.builder:KnowsRecipe(v) and CanPlayerBuildThis(inst, v) then -- CanPlayerBuildThis(inst, v) then
				canBuildWeapon = v
			end
		end

		if canBuildWeapon ~= nil and inst.waitingForBuild == nil then
			-- TODO: Need to check if it's safe to build this. If it's not safe...then don't start!
			--       Maybe use what I've got...or run away to build one? No idea.
			inst.waitingForBuild = canBuildWeapon
			inst.brain:SetSomethingToBuild(canBuildWeapon,nil,
				function() inst.waitingForBuild = nil end,function() inst.waitingForBuild = nil end)

			-- Gotta wait for that spear to be built
			DebugPrint(inst, "Making a " .. tostring(canBuildWeapon))
			return
		elseif highestDamageWeapon and highestDamageWeapon.components.weapon.damage > 20 then
			--print("I'll use what I've got!")
		else
			-- Don't bother fighting with a torch or walking cane or anything dumb like that
			return
		end
	end
end

--[[
	1) Find the closest hostile mob close to me (within 30?)
		1.5) Maintain a 'do not engage' type list?
	2) Find all like mobs around that one (or maybe just all 'hostile' mobs around it)
	3) Calculate damage per second they are capabable of doing to me
	4) Calculate how long it will take me to kill with my current weapon and their health
	5) Engage if under some threshold
--]]
function GoForTheEyes(inst)

	-- If this is true, we're waiting for the spear to be built
	if inst.waitingForBuild then
		-- If the build isn't queued and we are in the idle state...something happened
		if not inst.brain:CheckBuildQueued(inst.waitingForBuild) and inst.sg:HasStateTag("idle") then
			inst.waitingForBuild = nil
		else
			-- Waiting for the brain to make this thing. Nothing to do.
			return false
		end
	end

	-- return guy:HasTag("WORM_DANGER") or guy:HasTag("guard") or guy:HasTag("hostile") or
	-- 	guy:HasTag("scarytoprey") or guy:HasTag("frog") or guy:HasTag("mosquito") or guy:HasTag("merm") or
	-- 	guy:HasTag("tallbird")

   	local closestHostile = FindEntity(inst, 8,
	   						function(guy)
								return	inst.components.combat:CanTarget(guy)
							end, nil, {"structure", "INLIMBO"}, {"hostile", "scarytoprey", "mosquito", "merm", "tallbird"})

	--local closestHostile = GetClosestInstWithTag("hostile", inst, 20)

	-- No hostile...nothing to do
	if not closestHostile then return false end

	-- If this is on the do not engage list...run the F away!
	-- TODO!

	local hostilePos = Vector3(closestHostile.Transform:GetWorldPosition())

	-- This should include the closest
	local allHostiles = TheSim:FindEntities(hostilePos.x,hostilePos.y,hostilePos.z,5,nil, {"INLIMBO", "structure"}, {"hostile", "scarytoprey", "mosquito", "merm", "tallbird"})


	-- Get my highest damage weapon I have or can make
	local allWeaponsInInventory = inst.components.inventory:FindItems(function(item) return
										item.components.weapon and item.components.equippable and item.components.weapon.damage > 0 end)

	local highestDamageWeapon = nil
	-- The above does not count equipped weapons
	local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

	if equipped and equipped.components.weapon and equipped.components.weapon.damage > 0 then
		highestDamageWeapon = equipped
	end

	for k,v in pairs(allWeaponsInInventory) do
		if highestDamageWeapon == nil then
			highestDamageWeapon = v
		else
			if v.components.weapon.damage > highestDamageWeapon.components.weapon.damage then
				highestDamageWeapon = v
			end
		end
	end

	-- TODO: Consider an axe or pickaxe a valid weapon if we are under attack already!
	--       The spear condition is only if we are going to actively hunt something.

	-- We don't have a weapon...can we make one?
	-- TODO: What do we try to make? Only seeing if we can make a spear here as I don't consider an axe or
	--       a pickaxe a valid weapon. Should probably excluce
	if highestDamageWeapon == nil or (highestDamageWeapon and highestDamageWeapon.components.weapon.damage < 34) then

		local canBuildWeapon = nil
		for k,v in ipairs(weaponTierList) do
			if canBuildWeapon == nil and CanPlayerBuildThis(inst, v) then
				canBuildWeapon = v
			end
		end

		--local canBuildSpear = CanPlayerBuildThis(inst,"spear")

	  	if canBuildWeapon ~= nil then
			-- TODO: Need to check if it's safe to build this. If it's not safe...then don't start!
			--       Maybe use what I've got...or run away to build one? No idea.
   	   		inst.waitingForBuild = canBuildWeapon
   	   		inst.brain:SetSomethingToBuild(canBuildWeapon,nil,
   	     			function() inst.waitingForBuild = nil end,function() inst.waitingForBuild = nil end)

			-- Gotta wait for that spear to be built
			DebugPrint(inst, "Making a " .. tostring(canBuildWeapon))
			return false
		-- elseif not canBuildSpear and inst.components.combat.target == nil then
		-- 	-- TODO: Rather than checking to see if we have a combat target, should make
		-- 	--       sure the closest hostile is X away so we have time to craft one.
		-- 	--       What I do not want is to just keep trying to make one while being attacked.
		-- 	--       Returning false here means we'll run away.
		-- 	--print("I don't have a good weapon and cannot make one")
		-- 	return false
		elseif highestDamageWeapon and highestDamageWeapon.components.weapon.damage > 20 then
			--print("I'll use what I've got!")
		else
			-- Don't bother fighting with a torch or walking cane or anything dumb like that
			return false
		end
	end

	if highestDamageWeapon == nil then return false end

	-- TODO: Calculate our best armor.

	-- Collect some stats about this group of dingdongs

	local totalHealth=0
	local totalWeaponSwings = 0

	-- dpsTable is ordered like so:
	--{ [min_attack_period] = sum_of_all_at_this_period,
	--  [min_attack_period_2] = ...
	--}
	-- We can calculate how much damage we'll take by summing the entire table, then adding up to the min_attack_period

	-- If they are in cooldown, do not add to damage_on_first_attack. This number is the damage taken at zero time assuming
	-- all mobs are going to hit at the exact same time.

	-- TODO: Get mob attack range and calculate how long until they are in range to attack for better estimate

	local dpsTable = {}
	local damage_on_first_attack = 0
	for k,v in pairs(allHostiles) do
		local a = v.components.combat.min_attack_period
		dpsTable[a] = (dpsTable[a] and dpsTable[a] or 0) + v.components.combat.defaultdamage

		-- If a mob is ready to attack, add this to the damage taken when entering combat
		-- (even though they probably wont attack right away)
		-- if not v.components.combat:InCooldown() then
		-- 	damage_on_first_attack = damage_on_first_attack + v.components.combat.defaultdamage
		-- end
		damage_on_first_attack = damage_on_first_attack + v.components.combat.defaultdamage

		totalHealth = totalHealth + v.components.health.currenthealth -- TODO: Apply damage reduction if any
		totalWeaponSwings = totalWeaponSwings + math.ceil(v.components.health.currenthealth / highestDamageWeapon.components.weapon.damage)
	end



	--print("Total Health of all mobs around me: " .. tostring(totalHealth))
	--print("It will take " .. tostring(totalWeaponSwings) .. " swings of my weapon to kill them all")
	--print("It takes " .. tostring(inst.components.combat.min_attack_period) .. " seconds to swing")

	-- Now, determine if we are going to engage. If so, equip a weapon and charge!

	-- How long will it take me to swing x times?
	-- If we aren't in cooldown, we can swing right away. Else, we need to add our current min_attack_period to the calc.
	--      yes, we could find the exact amount of time left for cooldown, but this will be a safe estimate
	local inCooldown = inst.components.combat:InCooldown() and 0 or 1

	local timeToKill = (totalWeaponSwings-inCooldown) * inst.components.combat.min_attack_period


	table.sort(dpsTable)

	local damageTakenInT = damage_on_first_attack
	for k,v in pairs(dpsTable) do
		if k <= timeToKill then
			damageTakenInT = damageTakenInT + v
		end
	end

	--print("It will take " .. tostring(timeToKill) .. " seconds to kill the mob. We'll take about " .. tostring(damageTakenInT) .. " damage")

	local ch = inst.components.health.currenthealth
	-- TODO: Make this a threshold
	if (ch - damageTakenInT > 10) then

		-- Just compare prefabs...we might have duplicates. no point in swapping
		if not equipped or (equipped and (equipped.prefab ~= highestDamageWeapon.prefab)) then
			inst.components.inventory:Equip(highestDamageWeapon)
		end

		-- TODO: Make armor first and equip it if possible!

		-- Set this guy as our target
		--print("Time to kill " .. closestHostile.prefab)
		inst.components.combat:SetTarget(closestHostile)
		return true
	end
end

-- Given a list of one or more things to run from, calculates an escape route.
function FindEscapeRoute(inst, thingsToRunFrom)
	if thingsToRunFrom == nil then return nil end

	if #thingsToRunFrom == 0 then return nil end

	-- Get the positions of these things and calculate an escape angle
	local angles = {}
	for k,v in pairs(thingsToRunFrom) do
	   local point = Vector3(v.Transform:GetWorldPosition())
	   if point then
		  table.insert(angles, inst:GetAngleToPoint(point))
	   end
	end

	-- Calculate the average angle towards the entities
	local x,y = 0,0
	for k,v in pairs(angles) do
		DebugPrint(inst,"Direction to things: " .. tostring(v))
	   x = x + math.cos(math.rad(v))
	   y = y + math.sin(math.rad(v))
	end

	local avg = math.deg(math.atan2(y,x))
	DebugPrint(inst,"Average direction to things: " .. tostring(avg))

	-- Now run the opposite direction of the things
	local runAngle = (avg + 180) % 360

	-- We calculated the best escape angle. Now find the true escape angle that wont run into walls or stuff
	local offset, resultAngle = FindWalkableOffset(inst:GetPosition(), runAngle, 5, 12, true)

	-- There was nowhere in this direction we could run! Run towards the things?
	if not resultAngle then
	   resultAngle = avg
	end

	return resultAngle
end

--------------------------------------------------

-- Returns true if we should run away from the given 'guy'
function ShouldRunAway(guy, player)

	if not guy or not guy.prefab then return false end
	if guy == player then return false end

	-- Don't run from anything in our inventory (i.e. killer bees in our inventory)
	if guy.components.inventoryitem and guy.components.inventoryitem.owner then
		return false
	end

	-- Don't ever run from one of our followers
	if guy.components.follower and guy.components.follower.leader == player then
		return false
	end

	-- Not scared of anything as a ghost
	if player:HasTag("playerghost") then return false end

	if guy:HasTag("ghost") and player:HasTag("ghostlyfriend") then return false end
	if guy:HasTag("abigail") and not IsPvPEnabled() then return false end

	-- These are usually filtered by FindEntity, but just in case...
	if guy:HasTag("notarget") then return false end
	if guy:HasTag("INLIMBO") then return false end
	if guy:HasTag("NOCLICK") then return false end

	-- Don't run from dead players or things
	if guy:HasTag("playerghost") then return false end
	if guy.components.health and guy.components.health:IsDead() then
		return false
	end

	--print("--------- THE GUY ------ " .. tostring(guy))

	if (guy:HasTag("ArtificalWilson") or guy:HasTag("player")) and IsPvPEnabled() then
		-- Only run if the guy is holding a weapon
		local weapon = guy.components.inventory and guy.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or nil
		if weapon == nil then return false end
		if weapon and (weapon.components.weapon == nil or weapon.components.weapon.damage < 20) then return false end
		return true
	end

	-- If wearing spider hat...or are webber, don't run
	if (guy:HasTag("spider") or guy:HasTag("spiderden")) and player:HasTag("spiderwhisperer") then
		return false
	end

	-- Should we run from anything that is targeting us?
	-- The KiteMaster node is running above this one, so this shouldn't
	-- kick us out of that node in combat.
	-- It's more of a failsafe for not correctly marking a mob as hostile.

	-- It is used in "HostileMobNearInst", but in that case, the monster
	-- shouldn't be targeting us, so this should be fine.
	if guy.components.combat and guy.components.combat.target ~= nil
	        and guy.components.target == player then
		return true
	end

	-- Wilson apparently gets scared by his own shadow
	-- Also, don't get scared of chester too...
	if guy:HasTag("player") or guy:HasTag("companion") then
		return false
	end

	-- Don't run from these guys when not insane
	if guy:HasTag("shadowcreature") and not player.components.sanity:IsInsane() then
		return false
	end

	-- HostileTest is apparently a function that tests if something is hostile to this player.
	if player.HostileTest ~= nil then
		if player:HostileTest(guy) then
			return true
		end
	end

	-- Player monsters need to run from pigs and catcoons
	-- if player:HasTag("playermonster") then
	-- 	if guy:HasTag("pig") then return true end
	-- 	if guy:HasTag("catcoon") then return true end
	-- end

	-- -- Wurt doesn't need to run from merms
	-- if player:HasTag("playermerm") then
	-- 	if guy:HasTag("merm") then return false end
	-- end

	-- if guy:HasTag("pig") then
	-- 	if player and player:HasTag("monster") then return true end
	-- 	if player and player:HasTag("playermerm") then return true end
	-- 	if not guy:HasTag("guard") then return false end
	-- end

	-- Giants, treeguards, etc. RUN!
	if guy:HasTag("epic") then return true end

	-- Run away from beefalo/penguins when makin babies
	if guy.components.mood and guy.components.mood:IsInMood() then
		return true
	end

	-- Angry worker bees don't have any special tag...so check to see if it's spring
	-- Also make sure .IsSpring is not nil (if no RoG, this will not be defined)
	-- if guy:HasTag("worker") and TheWorld.state.season == "spring" then
	-- 	return true
	-- end

	if guy:HasTag("worker") and GetCurrentSeason() == SEASONS.SPRING then
		return true
	end


	-- Run away from things that are on fire and don't try to harvest things in fire.
	-- Then again, if a firehound ends up being on fire...we won't run away from it. lol...
	-- TODO: Fix this at some point. Leaving here becuase I don't see that happening ever.
	if guy:HasTag("fire") and not player:HasTag("pyromaniac") then

		-- Any prefab that has the name 'fire' or 'torch' in it is probably safe...
		local i = string.find(guy.prefab,"fire")
		local j = string.find(guy.prefab,"torch")
		if i or j then
			return false
		end

		local dsq = player:GetDistanceSqToInst(guy)
		if dsq > 15 then
			return false
		end
		--print("Ahh! " .. guy.prefab .. " is on fire! KEEP AWAY!")
		return true
	end

	-- Don't run from worms still underground
	if guy:HasTag("WORM_DANGER") and guy.sg and guy.sg:HasStateTag("idle") then return false end

	return guy:HasTag("WORM_DANGER") or guy:HasTag("guard") or guy:HasTag("hostile") or
		guy:HasTag("scarytoprey") or guy:HasTag("frog") or guy:HasTag("mosquito") or guy:HasTag("merm") or
		guy:HasTag("tallbird") or guy:HasTag("charged") or guy:HasTag("spat") or guy:HasTag("warg") or guy:HasTag("koalefant")

end

-- Returns a BufferedAction to blink
function TeleportBehind(player, target, invitem, distance, angle)

	if not target then
		return
	end


	-- If wortox is using cheats, do the quick teleport.
	-- Else, use a soul.
	if not invitem or not (invitem.components and invitem.components.blinkstaff) then
		-- No item was passed in, or it was, but isn't a blink staff. Can't teleport....
		-- unless they are wortox
		if not player.components.inventory:Has("wortox_soul", 1) then
			--DebugPrint(player, "This player can't teleport!")
			return
		end

		-- The action will consume the soul for us. This has to be nil.
		invitem = nil
	end

	-- Only wortox (with a soul) or a blink staff can do this.
	-- Since only wortox can carry a soul, should be valid to check if they have one
	-- if not (player.components.inventory:Has("wortox_soul", 1) or
	-- 	 	not invitem or not (invitem.components and invitem.components.blinkstaff)) then
	-- 		--DebugPrint(player, "This player can't teleport")
	-- 		return
	-- end

	local target_pt = target:GetPosition()

	local target_facing = (target:GetRotation() or 0) * DEGREES
	local target_search = target_facing + (angle or 180)

	--local r = player.Physics:GetRadius() + (target.Physics and target.Physics:GetRadius() + .1 or 0)

	if target_search > 360 then
		target_search = target_search - 360
   end

	local phys_dist = player.Physics:GetRadius() + (target.Physics and target.Physics:GetRadius() + .1 or 0)

   local function NoHoles(pt)
		return not TheWorld.Map:IsGroundTargetBlocked(pt)
  	end

	target_pt.y = 0

	local function GetTPPoint()
		for r = phys_dist, 2*phys_dist, .1 do
			local offset = FindWalkableOffset(target_pt, target_search*RADIANS, r+(distance or 0), 2, false, true, NoHoles)
			if offset ~= nil then
				target_pt.x = target_pt.x + offset.x
				target_pt.z = target_pt.z + offset.z
					return target_pt
			end
		end
	end

	local target_pos = GetTPPoint()

	if not target_pos then
		DebugPrint(player, "Could not find valid TP point")
		return
	end


	local faceangle = player:GetAngleToPoint(target_pt.x, target_pt.y, target_pt.z) + 180

	-- Found a spot. Do it.
	local action = BufferedAction(player, nil, ACTIONS.BLINK, invitem, target_pos, nil, nil, false, faceangle)
	return action
end

function GetHighestDamageWeapon(player, damage)

	local highestDamageWeapon = nil
	local min_damage = damage or 20

	local allWeaponsInInventory = player.components.inventory:FindItems(function(item) return
		 item.components.weapon and item.components.equippable and item.components.weapon.damage > min_damage end)

	-- The above does not count equipped weapons
	local equipped = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

	if equipped and equipped.components.weapon and equipped.components.weapon.damage > min_damage then
	  highestDamageWeapon = equipped
  end

	for k,v in pairs(allWeaponsInInventory) do
	  if highestDamageWeapon == nil then
		  highestDamageWeapon = v
	  else
		  if v.components.weapon.damage > highestDamageWeapon.components.weapon.damage then
			  highestDamageWeapon = v
		  end
	  end
  end

	-- Couldn't find one...
	if highestDamageWeapon == nil then
		 return nil, false
	end

	-- Returns the highestDamage weapon and whether we have it (or a copy of) equipped.
	return highestDamageWeapon, (equipped and (highestDamageWeapon.prefab == equipped.prefab) or false)
end

function EquipBestWeapon(player, weapon, min_damage)

	local equipped = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

	-- Weapon is already equipped....nothing to do
	if equipped ~= nil and weapon ~= nil and equipped.prefab == weapon.prefab then
		 DebugPrint(player, "Best weapon (" .. weapon.prefab .. " already equipped")
		 return true
	elseif weapon ~= nil then
		player.components.inventory:Equip(weapon)
		return true
	end

	-- Weapon wasn't passed in, find the best one.
	local highestDamageWeapon, is_equipped = GetHighestDamageWeapon(player, min_damage)

	if highestDamageWeapon ~= nil and is_equipped then
		 return true
	elseif not highestDamageWeapon then
		 return false
	end

	-- Equip the best weapon
	player.components.inventory:Equip(highestDamageWeapon)
	return true
end