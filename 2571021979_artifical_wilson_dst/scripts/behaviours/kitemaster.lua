KiteMaster = Class(BehaviourNode, function(self, inst, kill_distance, max_chase_time, donttags, canttags, oneoftags)
    BehaviourNode._ctor(self, "KiteMaster")
    self.inst = inst

    self.kill_distance = kill_distance or 8

    -- Anything we target must have all of these tags
    self.musttags = nil

    -- Don't pick a fight with these things.
    --self.dontfight = {"rook", "pig", "WORM_DANGER", "merm", "bishop", "beefalo", "charged", "chester", "companion", "player", "ArtificalWilson", "hive", "spiderden", "buzzard"}
    self.dontfight = donttags or {}

    -- Ignore all potential threats with the following tags
    --self.canttags = {"INLIMBO", "notarget", "NOCLICK", "chester"}
    self.canttags = canttags or {}

    -- Combines the dontfight with canttags so we don't target these. However
    -- we still want to consider these when looking for nearby threats.
    self.donttarget = {}

    -- -- Combines the 2 tables here
    for _,v in ipairs(self.dontfight) do
        table.insert(self.donttarget, v)
    end

    for _,v in ipairs(self.canttags) do
        table.insert(self.donttarget, v)
    end

    --self:DebugPrint("Combined table: ")
    for k,v in ipairs(self.donttarget) do
        self:DebugPrint(v)
    end

    self.willfightback = {}

    -- Anything with at least one of these tags is a valid target to kill
    --self.mustoneoftags = {"hostile", "scarytoprey", "mosquito", "tallbird", "frog"}
    self.mustoneoftags = oneoftags or {}

    for _,v in ipairs(self.dontfight) do
        table.insert(self.willfightback, v)
    end

    for _,v in ipairs(self.mustoneoftags) do
        table.insert(self.willfightback, v)
    end

    -- Store this combat as a shorthand notation
    self.combat = self.inst.components.combat

    -- Some thing's we might never catch. Stop trying after some amount of time
    self.max_chase_time = max_chase_time or 5

    -- clock time we started running towards enemy
    self.startruntime = nil

    -- Keep track of previous and current targets.
    self.old_target = nil
    self.current_target = nil

    -- Queuing an attack requires forcing the locomotor to run towards the target.
    -- This flag is turned on once we've queued the attack. Essentially, once
    -- we commit, we shouldn't try to kite until after we are done with the attack.
    self.attack_queued = false

    -- clock time this was last updated
    self.lastupdatetime = 0

    -- clock time of our last attack
    self.lastattacktime = 0

    -- Forces us to commit to an attack, ignoring all kite protocols.
    self.forceAttack = false

    self.numattacks = 0

    -- Get a callback for when we hit/miss the target.
    self.onattackfn = function(inst, data)
        self:OnAttackOther(data.target)
    end


    self.enemyAttackStarted = nil

    self.onenemyattackfn = function(inst, data)
        self:DebugPrint("Enemy attack finished " .. tostring(inst))
        -- KLAUS attacks twice in one animation.
        if inst.prefab == "klaus" then
            self.attack_count = (self.attack_count or 0) + 1
            if self.attack_count < 2 then
                self:DebugPrint("KLAUS Attack # " .. tostring(self.attack_count))
                return
            end
            self:DebugPrint("KLAUS Attack # " .. tostring(self.attack_count) .. " ... finished!")
        end
        self.enemyAttackStarted = nil
        self.attack_count = nil
        -- Some mobs attack so fast that we'll never get a swing in if we don't
        -- at least force it after they attack. Without this, we might just
        -- kite forever.
        self.forceAttack = true
    end


    self.inst:ListenForEvent("onattackother", self.onattackfn)
    self.inst:ListenForEvent("onmissother", self.onattackfn)

    self.inst:ListenForEvent("actionfailed",
            function(inst,data)
                if data.action == ACTIONS.ATTACK then
                    self:DebugPrint("Attack action failed")
                    self.attack_queued = false
                    self.attackFailed = true
                end
            end)

    self.inst:ListenForEvent("doattack",
        function(inst, data)
            self:DebugPrint("Queued an attack!!!")
            self.attack_queued = true
        end)

    -- We will register 'doattack' for each of our targets to know when
    -- they are starting their attack animation.
    -- We just have to hope we can escape soon enough.
    -- NOTE - this event does not guarentee the mob goes into the attack animation.
    --        It is simply their brain telling them to attack if they can.
    --        But, if we try to wait for the attack state to start, it's probably
    --        too late to escape.
    -- NOTE2 - each mob has a unique attack timeline. One of the frames in the
    --         timeline denotes when the actual combat:DoAttack() happens.
    --         Maybe we can try to find that, but we'd have to loop through
    --         each one and maybe check to see if the  timeline.fn == self.combat.target.components.combat.DoAttack
    --         If that is true, we can get the FRAME from timeline.time.
    --         THEN - we can know how long we have exactly to escape, assuming no dropped frames.
    self.beingattackedfn = function(inst, data)
        -- data.target should be us
        if not data then return end

        if data.target and data.target ~= self.inst then return end

        --self:DebugPrint("They have started their attack against us!!!")
        -- They have stared an attack!!!
        self.enemyAttackStarted = inst
        self.attackCount = nil
    end

    -- Some mobs will never stop hunting us (hound waves, nightmare creatures if we're insane, etc).
    -- We can't really run forever...so we might just have to try to fight them?
    -- Not sure.

end)

function KiteMaster:__tostring()
    return string.format("target %s", tostring(self.inst.components.combat.target))
end

function KiteMaster:DebugPrint(string)
    DebugPrint(self.inst, "KiteMaster: " .. tostring(string))
end

function KiteMaster:OnStop()
    self.inst:RemoveEventCallback("onattackother", self.onattackfn)
    self.inst:RemoveEventCallback("onmissother", self.onattackfn)
end

-- If we have any armor, will equip the best.
-- TODO: Will only equip body slot if no backpack
function KiteMaster:EquipArmor()
    EquipBestArmor(self.inst, self.combat.target)
end

function KiteMaster:OnAttackOther(target)
    self.attack_queued = false
    self.forceAttack = false

    if target ~= self.current_target then return end

    --self:DebugPrint("OnAttackOther Called vs: " .. tostring(target))
    self.numattacks = self.numattacks + 1
    self.startruntime = nil -- reset max chase time timer
end

-- Custom attack command builder. Should only be called if CanAttack(target) is true,
-- though it will just return the FailAction if you try it otherwis.
function KiteMaster:CommandAttack()

    -- If the combat component doesn't have a valid target, nothing to do
    if not self.combat:IsValidTarget(self.combat.target) then
        self:DebugPrint("Not a valid target...")
        return
    end

    -- if self.inst.sg:HasStateTag("attack") then
    --     self:DebugPrint("Attack already happening")
    --     self.attack_queued = true
    --     return
    -- end

    self.attack_queued = true
    local target = self.inst.components.combat.target
    local action = BufferedAction(self.inst, self.inst.components.combat.target, ACTIONS.ATTACK)

    -- Both success and fail should just call the 'OnAttackOther' so we know that we are done with
    -- an attack.
    -- TODO: Could track hits/misses, etc with this.

    -- Denote that we have an attack queued
    --self:DebugPrint("Queueing attack on " .. tostring(target))
    self.attack_queued = true
    action:AddFailAction(function() self:DebugPrint("Attack failed!") self:OnAttackOther(target) self.attackFailed = true end)
    action:AddSuccessAction(function() self:OnAttackOther(target) self.attackFailed = false end)
    self.action = action

    -- Mark the attack time to now.
    self.lastattacktime = GetTime()

    -- Push the attack action
    self.inst.components.locomotor:PushAction(self.action, true)

end

-- Don't want to leave event listeners attached to all of these mobs.
-- NOTE: They get automatically cleaned up on death...so just swap here when
--       we swap targets.
function KiteMaster:ChangeTargets(old, new)
    if old == new then return end

    --self.inst:ListenForEvent("onattackother", self.onattackfn)
    --self.inst:ListenForEvent("onmissother", self.onattackfn)

    if old ~= nil then
        self.inst:RemoveEventCallback("doattack", self.beingattackedfn, old)
        self.inst:RemoveEventCallback("onattackother", self.onenemyattackfn, old)
        self.inst:RemoveEventCallback("onmissother", self.onenemyattackfn, old)
        self.old_target = old
    end

    if new ~= nil then
        self.current_target = new
        self.inst:ListenForEvent("doattack", self.beingattackedfn, new)
        self.inst:ListenForEvent("onattackother", self.onenemyattackfn, new)
        self.inst:ListenForEvent("onmissother", self.onenemyattackfn, new)
    end

    -- Now make this our combat target
    self.combat:SetTarget(new)
end

-- Calculates a run angle from pt to hp. Useful for running away.
function KiteMaster:GetRunAngle(pt, hp)
    if self.avoid_angle ~= nil then
        local avoid_time = GetTime() - self.avoid_time
        if avoid_time < 1 then
            return self.avoid_angle
        else
            self.avoid_time = nil
            self.avoid_angle = nil
        end
    end

    local angle = self.inst:GetAngleToPoint(hp) + 180 -- + math.random(30)-15
    if angle > 360 then
        angle = angle - 360
    end

    --self:DebugPrint(string.format("RunAway:GetRunAngle me: %s, hunter: %s, run: %2.2f", tostring(pt), tostring(hp), angle))

    local radius = 6

	local find_offset_fn = self.inst.components.locomotor:IsAquatic() and FindSwimmableOffset or FindWalkableOffset
	local result_offset, result_angle, deflected = find_offset_fn(pt, angle*DEGREES, radius, 8, true, false) -- try avoiding walls
    if result_angle == nil then
		result_offset, result_angle, deflected = find_offset_fn(pt, angle*DEGREES, radius, 8, true, true) -- ok don't try to avoid walls
        if result_angle == nil then
			if self.fix_overhang and not TheWorld.Map:IsAboveGroundAtPoint(pt:Get()) then
                if self.inst.components.locomotor:IsAquatic() then
                    local back_on_ocean = FindNearbyOcean(pt, 1)
				    if back_on_ocean ~= nil then
			            result_offset, result_angle, deflected = FindSwimmableOffset(back_on_ocean, math.random()*2*math.pi, radius - 1, 8, true, true)
				    end
                else
				    local back_on_ground = FindNearbyLand(pt, 1) -- find a point back on proper ground
				    if back_on_ground ~= nil then
			            result_offset, result_angle, deflected = FindWalkableOffset(back_on_ground, math.random()*2*math.pi, radius - 1, 8, true, true) -- ok don't try to avoid walls, but at least avoid water
				    end
                end
			end
			if result_angle == nil then
	            return angle -- ok whatever, just run
			end
        end
    end

    result_angle = result_angle / DEGREES
    if deflected then
        self.avoid_time = GetTime()
        self.avoid_angle = result_angle
    end
    return result_angle
end


-- Actively look for something to kill. Only finds the CLOSEST mob that is
-- safe to kill as a target.
-- Only if there are no mobs around will it try to maintain the current target.
function KiteMaster:FindATarget(search_distance)

    -- If we're crafting something, don't stop it to go kill something.
    -- The RUNAWAY node will take care of aborting building for safety.
    if self.inst.sg:HasStateTag("busy") then
        --self:DebugPrint("Busy, not looking for target")
        return nil
    end

    local closestHostile = FindEntity(self.inst, search_distance,
        function(guy)
            -- Can't target these things above a certain percent
            if guy:HasTag("shadowcreature") and not self.inst.components.sanity:IsInsane() then
                return false
            end

            if self.inst:HasTag("mirrage") and self.inst.clone_parent == guy then
                return false
            end

            if guy:HasTag("butterfly") then
                if not guy.sg then return false end
                if guy.sg:HasStateTag("landing") or guy.sg:HasStateTag("landed") then
                    return true
                end
                return false
            end

            -- We'll never catch them if they aren't asleep.
            if guy:HasTag("lightninggoat") then
                if not guy.sg then return false end
                if guy.sg:HasStateTag("sleeping") then
                    return true
                end
                return false
            end

            if guy:HasTag("mole") then
                if not guy.sg then return false end
                if guy.sg:HasStateTag("noattack") then
                    return false
                end
                return true
            end

            -- Don't willingly target spiders if they are friends
            if guy:HasTag("spider") then
                if self.inst:HasTag("spiderwhisperer") and guy.components.combat and guy.components.combat.target ~= self.inst then
                    return false
                end
            end

            if guy:HasTag("spiderden") then
                if self.inst:HasTag("spiderwhisperer") then 
                    return false
                end

                -- Don't target ones that aren't empty
                if guy.components.childspawner.childreninside > 0 then
                    return false
                end
            end
            return	self.combat:CanTarget(guy)
        end, self.musttags, self.donttarget, self.mustoneoftags)

    -- There is nothing nearby to fight. Do we already have a valid combat target
    -- from a previous run?
    if not closestHostile then
        -- return nil
        if not self.combat.target then return nil end

        if not self.combat:IsValidTarget(self.combat.target) then
            return nil
        else
            -- Stick with this target?
            closestHostile = self.combat.target
        end
    end

    if self:IsTargetSafe(closestHostile) then
        --self:DebugPrint("Found a safe target: " .. tostring(closestHostile))
        return closestHostile
    end

    return nil
end

-- Determines if we should keep the current target, switch to a new one,
-- or run away.
function KiteMaster:MaintainTarget()

    -- Either use the current target from combat node, or the one we've stored.
    local target = self.combat.target or self.current_target

    if not target then
        self:DebugPrint("Maintain what target?")
        return false
    end

    if not target:IsValid() or not target.entity:IsVisible() then return false end

    if target:HasTag("shadowcreature") and not self.inst.components.sanity:IsInsane() then
        return false
    end

    -- Don't try to chase butterflies. You'll never catch them...
    if target:HasTag("butterfly") then
        if not target.sg then return false end
        if not (target.sg:HasStateTag("landing") or target.sg:HasStateTag("landed")) then
            return false
        end
    end

    -- We can't hit flying things with normal attacks. Just ignore them
    if target.sg and target.sg:HasStateTag("flight") then
        self:DebugPrint("Can't maintain combat on flying target...")
        return false
    end

    if self:IsTargetSafe(target) then
        self.combat:SetTarget(target)
        return true
    end

    return false
end

-- Scans the area around the target to know if it's safe.
-- Safety will consider the number of hostile mobs within close
-- proximity.
-- Uses min_health (default 15) if want to make sure we make it out with
-- at least that much health (if all goes well that is)
function KiteMaster:IsTargetSafe(target, min_health)

    if not target:IsValid() then return false end

    -- If we can't be hurt, of course it's safe
    if self.inst.components.health:IsInvincible() then
        return true
    end

    -- Don't fight any mobs with long reach...we don't know how to kite them
    if target.components.combat and target.components.combat:GetAttackRange() >= 10 then
        self:DebugPrint("Ranged mob: " .. tostring(target) .. " is not safe")
        return false
    end


    local hostilePos = Vector3(target.Transform:GetWorldPosition())

    -- Before we scan the whole world for threats.....do we even have something to fight with?
    local highestDamageWeapon, is_equipped = self:GetHighestDamageWeapon(20)

    -- Don't even have a weapon to fight. This target is not safe lol.
    if not highestDamageWeapon then return false end

	-- This should include the target itself.
    -- TODO: Need to consider the attack range of these other mobs...
	local allHostiles = TheSim:FindEntities(hostilePos.x,hostilePos.y,hostilePos.z,7,self.musttags, self.canttags, self.willfightback) or {}

    local x,y,z = self.inst.Transform:GetWorldPosition()
    local allHostilesNearMe = TheSim:FindEntities(x,y,z,7,self.musttags, self.canttags, self.willfightback)

    local function findDup(p)
        for k,v in ipairs(allHostiles) do
            if p == v then return true end
        end
        return false
    end

    if allHostilesNearMe ~= nil then
        for k,v in ipairs(allHostilesNearMe) do
            if not findDup(v) then
                table.insert(allHostiles, v)
            end
        end
    end

    -- Didn't even include itself?
    if #allHostiles == 0 then return true end

    -- Returns true if the target is an actual threat. This means if it's targeting something else, then don't count it.
    -- NOTE: Don't remove the original target.
    local validThreat = function(t)
        -- Keep the original target here...only look at the surrounding friends.
        if t == target then return true end

        if self.inst:HasTag("mirrage") and t:HasTag("mirrage") then return false end

        if self.inst:HasTag("mirrage") and self.inst.clone_parent == t then
            return false
        end

        -- If we shouldn't run from it, it can't be a threat.
        -- Just because we 'should' run from it doesn't automatically make it a threat though. Consider more options.
        if not ShouldRunAway(t, self.inst) then return false end

        -- Can't even fight us.
        if not t.components.combat then return false end

        -- It has a target, but that target isn't us.
        if t.components.combat.target and t.components.combat.target ~= self.inst then return false end

        -- Don't count sleeping dudes?
        if t.sg and t.sg:HasStateTag("sleeping") then return false end

        -- Don't worry about mobs that don't protect each other (lightning goats for example).
        -- Actually, charged goats will protect other goats.
        -- Not sure a good way to determine who will help out friends. Have to check their onAttacked fn and
        -- see if they have a combat.ShareTarget() defined....
        if target.prefab == "lightninggoat" and t.prefab == "lightninggoat" and not t:HasTag("charged") then
            return false
        end

        -- Passed all the above checks, must be a valid threat.
        return true
    end

    local threats = {}
    for k,v in pairs(allHostiles) do
        if v ~= self.inst and v:IsValid() and v.entity:IsVisible() and validThreat(v) then
            table.insert(threats, v)
        end
    end

    -- TODO: Is 3+ mobs a hard limit here?
    if #threats >= 2 then
        self.inst.brain:SaySomething("Not a fair fight", 60)
        return false
    end

    -- Now determine how much damage we will take if all enemies were to hit at the same time.
    -- NOTE - doesn't count the target if we will kill it in the first swing.
    local totalDamageTaken = 0
    for k,v in pairs(threats) do
        -- Will calculate damage based on our current armor.
        local threatDamage = v.components.combat:CalcDamage(self.inst)
        if v == target then
            if v.components.health.currenthealth > highestDamageWeapon.components.weapon.damage then
                totalDamageTaken = totalDamageTaken + threatDamage
            end
        else
            totalDamageTaken = totalDamageTaken + threatDamage
        end
    end

    local ch = self.inst.components.health.currenthealth
    if (ch - totalDamageTaken) > (min_health ~= nil and min_health or 15) then
        -- We'll survive this attack.
        return true
    end

    -- Sadly, we'll take too much damage. Abort!
    return false
end

-- Returns highest damage weapon in inventory, and whether it's equipped or not.
-- Only looks for weapons at, or above the passed in damage number (20 by default)
-- return weapon, bool (equipped)
function KiteMaster:GetHighestDamageWeapon(damage)

    local highestDamageWeapon = nil
    local min_damage = damage or 20

    local allWeaponsInInventory = self.inst.components.inventory:FindItems(function(item) return
        item.components.weapon and item.components.equippable and item.components.weapon.damage > min_damage end)

    -- The above does not count equipped weapons
    local equipped = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

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

-- If weapon is passed in, will equip that weapon (saves the need to search again)
-- If weapon is nil, will look for and equp the best one.
-- Returns true if we are now holding a weapon at, or above min_damage.
-- False otherwise.
function KiteMaster:EquipBestWeapon(weapon, min_damage)

    local equipped = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

    -- Weapon is already equipped....nothing to do
    if equipped ~= nil and weapon ~= nil and equipped.prefab == weapon.prefab then
        self:DebugPrint("Best weapon (" .. weapon.prefab .. " already equipped")
        return true
    elseif weapon ~= nil then
        self.inst.components.inventory:Equip(weapon)
        return true
    end

    -- Weapon wasn't passed in, find the best one.
    local highestDamageWeapon, is_equipped = self:GetHighestDamageWeapon(min_damage)

    if highestDamageWeapon ~= nil and is_equipped then
        return true
    elseif not highestDamageWeapon then
        return false
    end

    -- Equip the best weapon
    self.inst.components.inventory:Equip(highestDamageWeapon)
    return true
end



function KiteMaster:Visit()

    -- Nothing to do if this inst doesn't have a combat component...
    if not self.combat then
        self.status = SUCCESS
        return
    end

    -- ranged weapons have the 'abouttoattack' flag set. Don't want to start moving to
    -- cancel these...
    local is_attacking = self.inst.sg and
                            (self.inst.sg:HasStateTag("attack") or self.inst.sg:HasStateTag("abouttoattack"))

    -- READY state - time to look for something to fight
    if self.status == READY then

        self.attackCount = nil

        -- Don't interrupt this
        if is_attacking then
            --self:DebugPrint("Passing to not interrupt attack")
            self.status = SUCCESS
            return
        end

        -- Make some weapons in our spare time?
        local now = GetTime()
        if now - (self.lastBuildCheck or 0) > 20 then
            self.lastBuildCheck = now
            BuildAWeapon(self.inst)
            BuildHatArmor(self.inst)
        end

        -- Looks for a target X distance away that we can safely attack.
        local target = self:FindATarget(self.kill_distance)

        if target == nil then
            self.status = FAILED
            return
        end

        if not self:EquipBestWeapon() then
            -- Something went wrong here. FindATarget already should have
            -- accounted for our weapons....so if we don't have one,
            -- what happened?!?
            --self:DebugPrint("KiteMaster - Could not equip best weapon?!?")
            self.status = FAILED
            return
        end

        -- Set this target as the current one.
        if target ~= self.current_target then
            self:DebugPrint("New target: " .. tostring(target))
            self:ChangeTargets(self.current_target, target)
        end

        self.attack_queued = false
        self.startruntime = nil
        self.lastattacktime = nil

        -- If this new target isn't valid....nothing to do.
        -- if not self.combat:IsValidTarget(self.combat.target) then
        --     self:DebugPrint("Target not valid in READY state?")
        --     self.status = FAILED
        --     return
        -- end

        if math.random() < 0.0075 then
            self.inst.brain:SaySomething("There is a man behind you", 20)
        else
            self.combat:BattleCry()
        end
        self.startruntime = GetTime()
        self.numattacks = 0
        self.status = RUNNING

    end

    if self.status == RUNNING then

        -- Makes sure we should still pursue this target
        if not self:MaintainTarget() then
            self:DebugPrint("We should not maintain this target!")
            self.status = FAILED
            self.combat:SetTarget(nil)
            self.inst.components.locomotor:Stop()
            return
        end

        if not self.combat.target or not self.combat.target:IsValid() then
            self:DebugPrint("Target is no longer valid")
            self.status = SUCCESS
            self.combat:SetTarget(nil)
            self.inst.components.locomotor:Stop()
            return
        end

        if self.combat.target.components.health and self.combat.target.components.health:IsDead() then
            self:DebugPrint("Target is dead")
            self.status = SUCCESS
            self.enemyAttackStarted = nil
            self.attackCount = nil
            self.forceAttack = false
            self.combat:SetTarget(nil)
            self.inst.components.locomotor:Stop()
            return
        end

        -- Don't interrupt the attack animation by moving...unless we interruped the last attack.
        -- In that case, force it to go through.
        if is_attacking and self.attackFailed then
            return
        end

        if not self:EquipBestWeapon() then
            -- Just in case our weapon breaks...
            self:DebugPrint("KiteMaster - Could not equip best weapon?!?")
            self.status = FAILED
            return
        end

        -- Currently teleporting
        if self.inst.sg:HasStateTag("noattack") then
            --self:DebugPrint("...teleporting")
            return
        end

        -- Finds and equips the best armor depending on the current target
        self:EquipArmor()

        -- If we're holding spiders, deploy them.
        -- TODO: Should wait until we're closer....
        if self.inst.components.inventory:HasItemWithTag("spider", 1) then
            self.inst.brain:SaySomething("YEET", 100)
            self.inst.components.inventory:DropEverythingWithTag("spider")
        end

        local dt = 0
        if self.lastupdatetime then
            dt = GetTime() - self.lastupdatetime
        end
        self.lastupdatetime = GetTime()

        -- Check if the inst in "enemyAttackStarted" was actually from our current target.
        -- If not, clear it, we'll never hear the end of the attack.
        if self.enemyAttackStarted ~= nil and self.enemyAttackStarted ~= self.current_target then
            self:DebugPrint("Tracking the wrong enemy!")
            self.enemyAttackStarted = nil
            self.attackCount = nil
        end

        -- Determine if we should run in and hit, or run back to dodge.
        local otherCombat = self.combat.target.components.combat
        local attackRange = otherCombat:GetAttackRange()
        local ar2 = attackRange * attackRange
        local hitRange = otherCombat:GetHitRange() or 1
        local hr2 = hitRange * hitRange

        -- Can the mob even attack us right now?
        local inCooldown = otherCombat:InCooldown()

        -- Just because they are our target doesn't mean we are their target. Free hits!
        local weAreTarget = otherCombat.target and (otherCombat.target == self.inst) or false

        -- How long until their next attack *could* happen.
        local timeToNextAttack = 0

        -- Figure out where to run.
        -- Towards the enemy if FreeAttack() or self.forceAttack is true.
        -- Away otherwise.
        local hp = Point(self.combat.target.Transform:GetWorldPosition())
        local pt = Point(self.inst.Transform:GetWorldPosition())
        local dsq = distsq(hp, pt)
        local angle = self.inst:GetAngleToPoint(hp)
        local r = self.inst.Physics:GetRadius() + (self.combat.target.Physics and self.combat.target.Physics:GetRadius() + .1 or 0)
        local running = self.inst.components.locomotor:WantsToRun()

        -- Calculate the bait distance. Uses physical model sizes + their attack range
        local baitDistance =  (self.combat.target.Physics and self.combat.target.Physics:GetRadius() + .1 or 0) + (ar2)
        -- Calculate the clear range (if different from attack range).
        local clearDistance = 1.5*(r*r) + (hr2) + (hr2)/2

        local safe_distance = baitDistance

        local target_sg = self.combat.target.sg

        -- Is the enemy currently attacking?
        local is_currently_attacking = (target_sg and target_sg:HasStateTag("attack")) or false

        local attempt_dodge = true

        -- If the mob attack animation has started, see if we have time to run.
        if is_currently_attacking then

            -- TODO TEMP - not sure if we need to force an attack anymore....
            --self:DebugPrint("Enemy attack animation is true " .. tostring(self.lastupdatetime))
            --self.forceAttack = false

            -- The new safe distance is relative to their hit range, not attack range.
            safe_distance = clearDistance

            --self:DebugPrint("Safe Distance: " .. tostring(safe_distance))

            -- Before bothering with any calculations, see if this player even has the ability to teleport.
            -- This will check if they are wortox with a soul, or are holding a blink staff, (or are a blink staff)
            local tp_behind = nil

            -- TODO: I think wortox teleport takes longer than this. Not sure.
            local teleport_animation_time = 10*FRAMES

            -- Don't bother runing these calculations if we already have one queued.
            if not self.tp_queued then
                tp_behind = TeleportBehind(self.inst, self.combat.target, self.inst)
            end

            if not self.tp_queued and tp_behind ~= nil and (self.lastupdatetime - (self.last_check or 0) > 2) then

                self.last_check = self.lastupdatetime

                -- Get the time until the last event in this timeline. This is typically the attack frame, or at least close.
                local time_to_last_frame = nil

                -- Klaus attacks twice in one animation....

                -- If they have a timeline index, see how long it will be until their attack.
                -- This is usually the last frame in the sequence, or at least close to it.
                -- TODO: What if they don't have a timeline?
                if target_sg.timelineindex and target_sg.currentstate.timeline and target_sg.currentstate.timeline[#target_sg.currentstate.timeline] then
                    time_to_last_frame = target_sg.currentstate.timeline[#target_sg.currentstate.timeline].time - target_sg.timeinstate
                end

                -- Not sure what their timeline is....don't try to teleport or run? Just tank it?
                if time_to_last_frame == nil then
                    time_to_last_frame = 100
                end

                -- Klaus attacks twice in one animation. Cheater!
                if self.combat.target.prefab == "klaus" then
                    -- This attack happens 11 frames prior to the last one.
                    self:DebugPrint("Adjusting attack start time for klaus")
                    time_to_last_frame = time_to_last_frame - 11*FRAMES
                else
                    -- Assume the attack will start a few frames earlier
                    time_to_last_frame = time_to_last_frame
                end





                -- Calculate how long it will take us to run away.
                -- 1) Acceleration is instant
                -- 2) Assume speed is constant based on the current check

                -- Speed might be in units of frames.
                -- So a speed of 6 would run 6 m/frame * 30 frames/second = 180 m/second.
                -- Maybe that's why they do speed * dt * 0.5? speed is in half frames?
                local speed_in_frames = self.inst.components.locomotor:GetRunSpeed() or 1
                local speed = speed_in_frames * 10
                -- Locomotor calculates run dist by speed * dt * .5. Soo, lets see how far we can run
                -- before the last frame starts.
                local run_dist = speed * time_to_last_frame
                --run_dist = run_dist * run_dist
                -- How far away are we from the safe distance
                local safe_dist = safe_distance - dsq + r*r

                --self:DebugPrint("Time Until Last Frame      " .. tostring(time_to_last_frame))
                --self:DebugPrint("Distance We can Run        " .. tostring(run_dist))
                --self:DebugPrint("Distance Away From Safety  " .. tostring(safe_dist))

                if run_dist < safe_dist and time_to_last_frame >= teleport_animation_time then
                    -- We won't escape in time, but there is enough time to queue a teleport to happen.
                    self:DebugPrint("We wont make it. Teleport time!")
                    local teleport_at_time = math.max(0, time_to_last_frame - teleport_animation_time)

                    if self.lastupdatetime - (self.last_tp or 0) > 1.5 then
                        tp_behind:AddSuccessAction(function()
                            self:DebugPrint("Teleport action success!")
                            self.tp_queued = nil
                        end)

                        tp_behind:AddFailAction(function()
                            self:DebugPrint("Teleport action failed!!!")
                            self.tp_queued = nil
                        end)

                        self.tp_queued = true
                        self.last_tp = self.lastupdatetime


                        self:DebugPrint("Queuing teleport to happen in " .. tostring(teleport_at_time) .. " seconds")
                        self.inst:DoTaskInTime(teleport_at_time,
                                    function()
                                        local currentTime = GetTime()
                                        self:DebugPrint("Teleport Callback at " .. tostring(currentTime))
                                        self.inst.components.locomotor:PushAction(tp_behind, false)
                                        self.last_tp = currentTime
                                        self.tp_queued = nil
                                    end, self.inst)

                        -- With the tp queued, don't bother running. Just keep swinging.
                        attempt_dodge = false
                    end
                elseif run_dist < safe_dist then
                    -- We wont escape and there's not time to teleport. Don't bother trying to dodge this attack?
                    -- It might cause us to remain in a bad position though we we wont get a headstart trying to esacpe.
                    self:DebugPrint("We cant TP in time and won't clear the attack!!!")
                    attempt_dodge = false
                else
                    -- We can run out just fine.
                    self:DebugPrint("We can dodge this...")
                    attempt_dodge = true
                end


            --     -- If we can clear the attack in time by running....do that.
            --     --local speed = self.inst.components.locomotor:GetRunSpeed() or 1 -- TODO: Not sure how run speed translates to frames
            --     local dist = safe_distance - dsq -- How far we have to run
            --     local time = dist / (speed*speed) -- How long it will take to run that distance
            --     self:DebugPrint("Speed:            " .. tostring(speed))
            --     self:DebugPrint("Dist:             " .. tostring(dist))
            --     self:DebugPrint("Time To Run Dist  " .. tostring(time))
            --     self:DebugPrint("Time Until Attack " .. tostring(time_to_last_frame))


            --     if time > time_to_last_frame and time_to_last_frame >= 15*FRAMES then
            --         self:DebugPrint("We wont make it. Teleport time!")
            --         -- See if we can teleport behind the attack instead of dodge it.
            --         local tp_behind = TeleportBehind(self.inst, self.combat.target, self.inst)
            --         -- Calculate the best time to teleport.
            --         -- MOST stategraphs have the attack happen at the end of the timeline.
            --         -- Thus, don't teleport too early (deerclops).
            --         if tp_behind and (self.lastupdatetime - (self.last_tp or 0) > 1.5) then
            --             tp_behind:AddSuccessAction(function() self:DebugPrint("Teleport action success!") self.tp_queued = nil end)
            --             tp_behind:AddFailAction(function() self:DebugPrint("Teleport action failed!!!") self.tp_queued = nil end)
            --             self.tp_queued = true
            --             self.last_tp = self.lastupdatetime


            --             self:DebugPrint("Queuing teleport to happen in " .. tostring(time_to_last_frame) .. " seconds")
            --             self.inst:DoTaskInTime(time_to_last_frame, function()
            --                 self.inst.components.locomotor:Stop()
            --                 self.inst.components.locomotor:PushAction(tp_behind, false)
            --                 self.last_tp = GetTime()
            --                 self.tp_queued = nil end, self.inst)

            --             --self.inst.components.locomotor:PushAction(tp_behind, false)
            --             --self:DebugPrint("Pushed teleport action: " .. tostring(tp_behind))
            --             return
            --         end
            --     elseif time > time_to_last_frame then
            --         -- We won't make it out. Don't waste time....just keep swinging.
            --         self:DebugPrint("No time to run or teleport. Just keep swinging")
            --     else
            --         self:DebugPrint("We can run out of here")
            --     end

            elseif self.tp_queued == true then
                -- already have a tp queued, keep attacking. the tp will happen.
                self:DebugPrint("Teleport queued...waiting for right moment: " .. tostring(GetTime()))
                attempt_dodge = false
            end
        else
            self.last_check = nil
        end -- is_currently_attacking



                -- This function returns true if we can attack without danger.
        -- Usually means they are in cooldown, or taunting, or eating....those types of things.
        local function FreeAttack()
            -- If we can't get hurt....just swing.
            if self.inst.components.health:IsInvincible() then
                return true
            end

            -- We've determined to not try to dodge this attack (either a tp is queued or
            -- we won't get out in time. Just keep swinging)
            if attempt_dodge == false then
                self:DebugPrint("We were told we wont make it....don't try")
                return true
            end

            -- If teleport is queued, keep swinging until it happens
            -- if self.tp_queued == true then
            --     return true
            -- end

            -- If this is true, they have started their attack. Should be running away!
            if self.enemyAttackStarted ~= nil and self.enemyAttackStarted == self.combat.target then
                --self:DebugPrint("They are attacking, not a free attack!")
                return false
            end



            -- In bot vs bot...someone has to swing first
            if self.combat.target:HasTag("ArtificalWilson") then
                if math.random() < 0.1 then
                    self.forceAttack = true
                end
            end

            -- If they are in cooldown, they can't hit us.
            if inCooldown then return true end

            -- If we aren't the target, they can't get us.
            if not weAreTarget then return true end

            if target_sg then
                -- Some taunt states aren't marked as busy (because they can rotate). So just look at state name I guess.
                local is_taunt_state = target_sg.currentstate and target_sg.currentstate.name == "taunt" or false
                if is_taunt_state then return true end
                -- Any tag flagged as busy that isn't an attack means they are doing something else.
                if target_sg:HasStateTag("busy") and not target_sg:HasStateTag("attack") then return true end
            else
                -- No stategrap for this thing? Probably fine to smash?
                return true
            end

            -- Default case: Don't assume we can smash freely
            return false
        end

        -- If they haven't started their attack, run to their attack range.
        -- If they have started their attack, run to their hit range.

        -- If we are inside the bait distance, then run away.
        -- TODO: Calculate how long it will take to get to the safe distance and compare
        --       it to the cooldown time?
        if not FreeAttack() and not self.forceAttack and (dsq <= safe_distance) then
            -- Run away from them until they attack.
            -- TODO: this will just run straight back, which is right most of the time...
            --self:DebugPrint("Kiting. Current distance: " .. tostring(dsq))
            self.inst.components.locomotor:RunInDirection(self:GetRunAngle(pt, hp))
            return
        end

        -- We've determined it's time to attack. Either the attack is forced,
        -- or we've determined we can sneak in a hit, likely due to cooldown time.
        if (running and dsq > r*r) or (not running and dsq > self.combat:CalcAttackRangeSq() ) then
            -- Run towards the beast.
            --self:DebugPrint("Time to attack!")
            self.inst.components.locomotor:GoToPoint(hp, nil, true)
        elseif not (self.inst.sg and self.inst.sg:HasStateTag("jumping")) then
            self.inst.components.locomotor:Stop()
            if self.inst.sg:HasStateTag("canrotate") then
                self.inst:FacePoint(hp)
            end
        end

        -- If we get here, check to see if we're close enough for an attack. If we are,
        -- queue it up.
        -- If we're not, nothing will happen. Just keep on running towards them.
        if self.combat:CanAttack(self.combat.target) then
            self:DebugPrint(self.combat:GetDebugString())
            self:CommandAttack()
            -- Sleep to give the attack enough time to complete
            self:Sleep(0.2)
            return
        end

        --self:Sleep(0.01)
    end
end