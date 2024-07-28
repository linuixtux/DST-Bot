CustomRunAway = Class(BehaviourNode, function(self, inst, hunterparams, see_dist, safe_dist, runfrom, canttags, longrangetags)
    BehaviourNode._ctor(self, "CustomRunAway")
    self.safe_dist = safe_dist
    self.see_dist = see_dist
    self.hunterparams = hunterparams
    self.inst = inst

    self.runfromtags = runfrom
    self.ignoretags = canttags
    self.longrange = longrangetags
    
end)

function CustomRunAway:__tostring()
    return string.format("CustomRunAway %f from: %s", self.safe_dist, tostring(self.hunter))
end

function CustomRunAway:GetRunAngle(pt, hp)
    if self.avoid_angle ~= nil then
        local avoid_time = GetTime() - self.avoid_time
        if avoid_time < 0.5 then
            return self.avoid_angle
        else
            self.avoid_time = nil
            self.avoid_angle = nil
        end
    end

    local offset_angle = 180
    if self.hunter and (self.hunter.prefab == "rook" or self.hunter.prefab == "bishop") then
        offset_angle = 210
    end
    local angle = self.inst:GetAngleToPoint(hp) + offset_angle -- + math.random(30)-15
    if angle > 360 then
        angle = angle - 360
    end

    --print(string.format("RunAway:GetRunAngle me: %s, hunter: %s, run: %2.2f", tostring(pt), tostring(hp), angle))
    local hostilesThatWay = function(pt)
        local hostiles = TheSim:FindEntities(pt.x, pt.y, pt.z, 3, nil, self.ignoretags, self.runfromtags) or {}
        for i,v in ipairs(hostiles) do
            if v == self.inst then
                hostiles[i] = nil
            end
        end
        if #hostiles > 0 then
            --print("Not running this way....there's more hostiles")
            return false
        end

        return true
    end

    local radius = 5
	local result_offset, result_angle, deflected = FindWalkableOffset(pt, angle*DEGREES, radius, 8, true, false, hostilesThatWay) -- try avoiding walls
    if result_angle == nil then
		result_offset, result_angle, deflected = FindWalkableOffset(pt, angle*DEGREES, radius-1, 8, true, true, hostilesThatWay) -- ok don't try to avoid walls
        if result_angle == nil then
			result_offset, result_angle, deflected = FindWalkableOffset(pt, angle*DEGREES, radius-2, 8, true, true) -- ignore hostiles, fine
			if result_angle == nil then
                -- Most likely a huge lake/stream in front?
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

function CustomRunAway:Visit()
    if self.status == READY then
        -- Use the passed in funciton to return a thing we should run from.
		self.hunter = self.hunterparams(self.inst)
        if self.hunter then
            self.status = RUNNING
            DebugPrint(self.inst, "RUNNING: " .. tostring(self))
        else
            self.status = FAILED
        end

    end

    if self.status == RUNNING then
        if not self.hunter or not self.hunter:IsValid() or
        (self.hunter and self.shouldrunfn and not self.shouldrunfn(self.hunter, self.inst)) then
            self.status = FAILED
            self.inst.components.locomotor:Stop()
        else

            -- Find all scary things around us to calculate a better escape route.
            -- local x,y,z = self.inst.Transform:GetWorldPosition()
            -- local allHostiles = TheSim:FindEntities(x,y,z,self.see_dist,nil, self.canttags, self.willfightback) or {}
            -- if #allHostiles == 0 then
            --     self.status = SUCCESS
            --     return
            -- end

            -- local angle = FindEscapeRoute(self.inst, allHostiles)

            -- if angle == nil then
            --     print("Run Angle NIL - must not be anyone nearby?")
            --     self.status = SUCCESS
            --     return
            -- end

            -- Should find the closest mob every iteration
            self.hunter = self.hunterparams(self.inst)
            if not self.hunter then
                self.status = SUCCESS
                return
            end

            -- Equip armor while fleeing (unless we're running away from burning trees lol)
            if self.hunter and self.hunter.components.combat then
                EquipBestArmor(self.inst, self.hunter, false)
            end

            -- If it's night time, equip a torch so we can run away from the campfire.
            if IsNight() then
                local haveTorch = self.inst.components.inventory:FindItem(function(item) return item:HasTag("lighter") end)
			    local currentEquippedItem = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                if haveTorch and (not currentEquippedItem or (currentEquippedItem and not currentEquippedItem:HasTag("lighter"))) then
                    DebugPrint(self.inst, "Equipping torch to flee!")
                    self.inst.components.inventory:Equip(haveTorch)
                end
            end



            local pt = Point(self.inst.Transform:GetWorldPosition())
            local hp = Point(self.hunter.Transform:GetWorldPosition())

            local angle = self:GetRunAngle(pt, hp)
            if angle then
                self.inst.components.locomotor:RunInDirection(angle)
            else
                DebugPrint(self.inst, "Couldn't find a valid angle to run!!!")
                self.status = FAILED
                self.inst.components.locomotor:Stop()
            end

            -- Equip armor while fleeing (unless we're running away from burning trees lol)
            if self.hunter and self.hunter.components.combat then
                EquipBestArmor(self.inst, self.hunter)
            end

            local run_range = self.safe_dist

            -- Run extra far away from things in this list
            for _,v in pairs(self.longrange) do
                if self.hunter:HasTag(v) then
                    DebugPrint(self.inst, "Running further for long range mob " .. tostring(self.hunter))
                    run_range = self.safe_dist + 20
                elseif self.hunter.prefab == "wasphive" then
                    run_range = self.safe_dist + 20
                end
            end

            -- Override the default distance for ranged attack monsters that are targeting us.
            -- Need to at least run out of their detection distance...
            -- local run_range = self.safe_dist
            -- if self.hunter.components.combat then
            --     local attack_range = self.hunter.components.combat:GetAttackRange()
            --     if attack_range > self.see_dist then
            --         --print("Running further from ranged attacker!")
            --         run_range = self.safe_dist + attack_range
            --     elseif self.hunter.prefab == "rook" then
            --         DebugPrint(self.inst, "CustomRunAway: Avoiding ROOK")
            --         run_range = self.safe_dist + 20
            --     elseif self.hunter.prefab == "bishop" then
            --         DebugPrint(self.inst, "CustomRunAway: Avoiding bishop")
            --         run_range = self.safe_dist + 20
            --     elseif self.hunter.prefab == "spat" then
            --         run_range = self.safe_dist + 20
            --     end
            -- end

            if distsq(hp, pt) > run_range*run_range then
                self.status = SUCCESS
                self.inst.components.locomotor:Stop()
            end


        self:Sleep(1/4)
        end
    end
end
