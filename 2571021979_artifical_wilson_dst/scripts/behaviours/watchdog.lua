Watchdog = Class(BehaviourNode, function(self, inst, sanityTargetFn)
    BehaviourNode._ctor(self, "Watchdog")
    self.inst = inst

    self.lastDistance = nil
    self.lastPoint = nil
    self.lastAction = nil

    self.lastUpdateTime = GetTime()
    self.checkInterval = 2

 end)

 function Watchdog:DebugPrint(string)
    DebugPrint(self.inst, "Watchdog: " .. string)
 end

 function Watchdog:Visit()

    if self.status == READY then
        self.runCounter = 0
        -- Lookup the current action we are doing
        local bufferedAction = self.inst:GetBufferedAction()

        if bufferedAction == nil then
            self.lastAction = nil
            self.status = FAILED
            return
        end

        --local is_running = self.inst.sg:HasStateTag("running")
        local is_running = self.inst.components.locomotor:WantsToRun()

        if not is_running then
            self.status = FAILED
            return
        end

        if GetTime() - self.lastUpdateTime < self.checkInterval then
            self.status = FAILED
            return
        end

        -- New action from last check...
        if bufferedAction ~= self.lastAction then
            self:DebugPrint("Different action? Old Action: " .. tostring(self.lastAction))
            self.lastAction = bufferedAction
            self.lastDistance = nil
            self.lastPoint = nil
        end

        self:DebugPrint("Current Action: " .. tostring(bufferedAction))

        -- local target_position = Point(combat.target.Transform:GetWorldPosition())
        -- local facing_point = target_position
        -- local me = Point(self.inst.Transform:GetWorldPosition())

        -- local dsq = distsq(target_position, me)

        -- local running = self.inst.components.locomotor:WantsToRun()

        -- Mark this time
        local tmp_update_time = self.lastUpdateTime or 0
        self.lastUpdateTime = GetTime()
        local destpos = nil

        if bufferedAction.target ~= nil then
            destpos = bufferedAction.target:GetPosition()
        else
            destpos = bufferedAction:GetActionPoint()
        end

        if destpos == nil then
            self:DebugPrint("There is no position for this action???")
            self.status = FAILED
            return
        end

        -- First reading for this action. Just mark the current disstance and be done
        if self.lastDistance == nil then
            self.lastDistance = self.inst:GetDistanceSqToPoint(destpos)
            self.lastPoint = self.inst:GetPosition()
            --self:DebugPrint("Current Distance To Action: " .. tostring(self.lastDistance))
            self.status = FAILED
            return
        end


        -- Last distance was defined. Check we have changed
        local currentDistance = self.inst:GetDistanceSqToPoint(destpos)
        local diff = math.abs(self.lastDistance - currentDistance)
        local currentDistFromLastPoint = self.inst:GetDistanceSqToPoint(self.lastPoint)
        --self:DebugPrint("Difference in distance from last check: " .. tostring(diff))
        local timediff = self.lastUpdateTime - tmp_update_time
        self:DebugPrint("We ran " .. tostring(diff) .. " in " .. tostring(timediff) .. " seconds")

        self.lastDistance = currentDistance
        self.lastPoint = self.inst:GetPosition()

        -- We haven't moved nearly anywhere since the last check....something is wrong
        if diff < 2 and currentDistFromLastPoint < 5 then

            --self:DebugPrint("I think we're stuck....")
            local angle = self.inst:GetAngleToPoint(destpos)
            self.runAngle = angle + 150 + math.random(1,10)
            self.inst.components.locomotor:Stop()
            self.status = RUNNING

        else
            self.status = FAILED
            return
        end

    elseif self.status == RUNNING then
        self:DebugPrint("Running in random direction - " .. tostring(self.runAngle))
        self.inst.brain:SaySomething("Activating complex avoidance system")
        self.inst.components.locomotor:RunInDirection(self.runAngle)
        self:Sleep(.35)

        self.runCounter = self.runCounter + 1

        if self.runCounter >= 4 then
            self.status = SUCCESS
            return
        end

    end
 end



