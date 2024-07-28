SnipeMaster = Class(BehaviourNode, function(self, inst, kill_distance, onehitkill, aggro)
    BehaviourNode._ctor(self, "SnipeMaster")
    self.inst = inst
    -- Store this combat as a shorthand notation
    self.combat = self.inst.components.combat

    self.ranged_target = nil

    self.kill_distance = kill_distance or 12

    self.weapon = nil

    -- All ranged enemies MUST have all of these tags
    self.musttags = nil

    -- All ranged enemies MUST NOT have any of these tags
    self.canttags = {"INLIMBO", "NOCLICK", "structure"}

    self.onehittags = onehitkill
    self.aggrotags = aggro


    -- This behavior will shoot at things from a safe distance.
    -- Will only target things in the onehitkill tags if a single hit would kill it. 
    -- Will only target things in the aggro tags if we currently aren't in combat. 

    -- TODO: Create a group of things we try to kill with multiple shots? 


    -- Queuing an attack requires forcing the locomotor to run towards the target.
    -- This flag is turned on once we've queued the attack. Essentially, once
    -- we commit, we shouldn't try to kite until after we are done with the attack.
    self.attack_queued = false


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

end)

-- projectile is a string and doesn't have damage until launched...
function SnipeMaster:GetDamageOfAmmo(ammo)
    if string.find(ammo, "slingshotammo_rock") then
        return TUNING.SLINGSHOT_AMMO_DAMAGE_ROCKS
    elseif string.find(ammo, "slingshotammo_gold") then
        return TUNING.SLINGSHOT_AMMO_DAMAGE_GOLD
    elseif string.find(ammo, "slingshotammo_marble") then
        return TUNING.SLINGSHOT_AMMO_DAMAGE_MARBLE
    end

    return 0
end

function SnipeMaster:__tostring()
    return string.format("target %s", tostring(self.inst.components.combat.target))
end

function SnipeMaster:DebugPrint(string)
    DebugPrint(self.inst, "SnipeMaster: " .. tostring(string))
end

function SnipeMaster:OnStop()

end

function SnipeMaster:OnRangedAttack(target, hit)
    -- Our ranged attack either hit or missed. 
end

-- Custom attack command builder. Should only be called if CanAttack(target) is true,
-- though it will just return the FailAction if you try it otherwis.
function SnipeMaster:CommandAttack()

    -- If the combat component doesn't have a valid target, nothing to do
    if not self.combat:IsValidTarget(self.combat.target) then
        self:DebugPrint("Not a valid target...")
        return
    end

    self.attack_queued = true
    local target = self.inst.components.combat.target
    local action = BufferedAction(self.inst, self.inst.components.combat.target, ACTIONS.ATTACK, self.weapon)
    self:DebugPrint("Queueing attack on " .. tostring(target))

    action:AddFailAction(function() 
        self:DebugPrint("Attack failed!") 
        self.attack_queued = false
    end)

    action:AddSuccessAction(function() 
        self:DebugPrint("Attack success!") 
        self.attack_queued = false
    end)

    self.action = action

    -- Push the attack action
    self.inst.components.locomotor:PushAction(self.action, true)
end


-- Actively look for something to kill. Only finds the CLOSEST mob that is
-- safe to kill as a target.
function SnipeMaster:FindATarget(search_distance, weapon)

    -- If we're crafting something, don't stop it to go kill something.
    -- The RUNAWAY node will take care of aborting building for safety.
    if self.inst.sg:HasStateTag("busy") then
        return nil
    end

    if not weapon then return nil end
    --if not weapon.components.projectile then return nil end

    -- this is a prefab name
    local projectile = weapon.components.weapon.projectile

    --self:DebugPrint("Current weapon: " .. tostring(weapon))
    --self:DebugPrint("Current Projectile: " .. tostring(projectile))

    local weaponDamage = weapon.components.weapon.damage or 0
    if weaponDamage == 0 and projectile then
        --self:DebugPrint("Looking up damage based on ammo type")
        weaponDamage = self:GetDamageOfAmmo(projectile)
    end

    local weaponRange = weapon.components.weapon.attackrange or 0

    local searchRange = search_distance + weaponRange

    --self:DebugPrint("Looking for something to shoot with " .. tostring(weaponDamage) .. " health or less...")

    local onehit = FindEntity(self.inst, searchRange,
        function(guy)
            if not guy.components.health then return false end

            -- Ignore things we can't even target
            if not self.combat:CanTarget(guy) then return false end

            -- Returns true if the damage is >= current health
            return guy.components.health.currenthealth <= weaponDamage
        end, self.musttags, self.canttags, self.onehittags)

    -- If there is something we can one hit kill, just target that
    if onehit ~= nil then
        self:DebugPrint("We can kill " .. tostring(onehit) .. " in one hit!")
        return onehit
    end

    local aggro = FindEntity(self.inst, searchRange,
        function(guy)

            -- Can't target these things above a certain percent
            if guy:HasTag("shadowcreature") and not self.inst.components.sanity:IsInsane() then
                return false
            end

            -- Don't willingly target spiders if they are friends 
            if guy:HasTag("spider") then
                if self.inst:HasTag("spiderwhisperer") and guy.components.combat.target ~= self.inst then
                    return false
                end
            end

            -- This guy is already coming for us...
            if guy.components.combat.target == self.inst then
                return false
            end

            return self.combat:CanTarget(guy)

        end, self.musttags, self.canttags, self.aggrotags)

    -- Whether we found something or not, just return the potential target. 
    return aggro
end

function SnipeMaster:SetTarget(target)
    self.ranged_target = target
    self.combat:SetTarget(target)
end

function SnipeMaster:Visit()

    -- Nothing to do if this inst doesn't have a combat component...
    if not self.combat then
        self.status = FAILED
        return
    end

    -- READY state means we've found a new target to kill.
    if self.status == READY then

        -- On each visit - we shouldn't have a target selected already. 
        self.ranged_target = nil

        -- Currently we only pull aggro or kill with ranged. 
        -- On a vist, don't do anything if we already have a combat target
        if self.combat.target ~= nil then
            self.status = FAILED
            return
        end

        -- If we have a ranged weapon and are not currently in combat, find something to snipe
        local ranged, equipped = GetRangedWeapon(self.inst)
        if not ranged then
            --self:DebugPrint("No ranged weapon in inventory...")
            self.status = FAILED
            return
        end

        -- We have a ranged weapon and aren't in combat. Find something to shoot. 
        local target = self:FindATarget(self.kill_distance, ranged)

        -- Nothing we want to shoot.
        if target == nil then
            self.status = FAILED
            return
        end

        -- We found somethign to shoot. Equip the weapon if it's not already
        if not equipped then
            self.inst.components.inventory:Equip(ranged)
        end

        -- Set this target as the current target
        self:SetTarget(target)
        self.status = RUNNING
    end

    if self.status == RUNNING then
        -- Get in ranged (based on the current equipped weapon). 
        -- Then shoot. 
       

        -- Weapon might be out of ammo, or something.
        -- If we aren't holding a valid ranged weapon, then stop running. 
        local weapon, equipped = GetRangedWeapon(self.inst)
        if not weapon or not equipped then 
            self.status = SUCCESS
            self:SetTarget(nil)
            self.inst.components.locomotor:Stop()
            return
        end

        -- If our target doesn't match our ranged target, abort
        if not self.combat.target or (self.combat.target ~= self.ranged_target) then
            self:DebugPrint("Ranged target doesn't match current target!!")
            self.status = FAILED
            self.ranged_target = nil
            self.inst.components.locomotor:Stop()
            return
        end

        -- Now validate the target is still a valid thing to hunt
        if not self.combat.target or not self.combat.target:IsValid() then
            self:DebugPrint("Target is no longer valid")
            self.status = SUCCESS
            self:SetTarget(nil)
            self.inst.components.locomotor:Stop()
            return
        end

        if self.combat.target.components.health and self.combat.target.components.health:IsDead() then
            self:DebugPrint("Target is dead")
            self.status = SUCCESS
            self:SetTarget(nil)
            self.inst.components.locomotor:Stop()
            return
        end

        -- Finally, make sure the target isn't coming towards us. 
        -- If it is, it means we aggroed it already...so, yay
        if self.combat.target.components.combat.target == self.inst then
            self:DebugPrint("Target is mad!")
            self.status = SUCCESS
            self.ranged_target = nil
            return
        end

        -- Don't interrupt the attack animation. 
        if self.inst.sg:HasStateTag("attack") or self.inst.sg:HasStateTag("abouttoattack") then
            return
        end


        local hp = Point(self.combat.target.Transform:GetWorldPosition())
        local pt = Point(self.inst.Transform:GetWorldPosition())
        local dsq = distsq(hp, pt)
        local angle = self.inst:GetAngleToPoint(hp)
        local r = self.inst.Physics:GetRadius() + (self.combat.target.Physics and self.combat.target.Physics:GetRadius() + .1 or 0)
        local running = self.inst.components.locomotor:WantsToRun()

        -- Get to within range of the weapon to start the attack. 
        if (running and dsq > r*r) or (not running and dsq > (self.combat:CalcAttackRangeSq()-2*r) ) then
            -- Run towards the beast.
            self:DebugPrint("Getting within range to target...")
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
            self:Sleep(0.5)
            return
        end

        self:Sleep(0.01)

    end
end