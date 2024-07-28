Investigate = Class(BehaviourNode, function(self, inst, sanityTargetFn)
    BehaviourNode._ctor(self, "Investigate")
    self.inst = inst
    self.currentDirtPile = nil
    self.cancelTask = nil

    -- Called when we find the last track
    self.inst:ListenForEvent("huntbeastnearby", function(inst, data)  
        local animal = FindEntity(self.inst, 50, nil, nil, {"NOCLICK", "INLIMBO"}, {"koalefant", "spit", "warg"})
        if not animal then
            return
        end

        if animal:HasTag("spit") then
            self.inst.components.talker:Say("....ewecus")
            return
        elseif animal:HasTag("warg") then
            self.inst.components.talker:Say(".....VARG!!")
            return
        end

        -- Just make it a target...
        self.inst.components.combat:SetTarget(animal)
    
    end)
 end)

 function Investigate:DebugPrint(string)
    DebugPrint(self.inst, "Investigate: " .. string)
 end

 function Investigate:FindNext()
    local dirtpile = FindEntity(self.inst, 60, nil, {"dirtpile"}, {"NOCLICK", "INLIMBO"})
    if dirtpile ~= nil then
        return self:BuildAction(dirtpile)
    end
 end

 function Investigate:PushAction(action)
    self.action = action
    self.pendingstatus = nil
    self.inst.components.locomotor:PushAction(action, true)
 end

 function Investigate:BuildAction(dirtpile)

    local action = BufferedAction(self.inst, dirtpile, ACTIONS.ACTIVATE)
    if not action then return end

    action:AddSuccessAction(
        function()
            self:DebugPrint("SUCCESS - Finding next pile")
            local next = self:FindNext()
            if not next then
                self.pendingstatus = FAILED
                self.action = nil
                return
            else
                self:PushAction(next)
                return
            end
        end)
        
    action:AddFailAction(function() 
        self:DebugPrint("Failed doing dirtpile aciton")
        self.pendingstatus = FAILED 
        self.action = nil 
        self.currentDirtPile = nil
    end)

    self.currentDirtPile = dirtpile
    return action
 end

 function Investigate:Visit()

    if self.status == READY then
        self.pendingstatus = nil
        self.action = nil
        self.currentDirtPile = nil

        local dirtpile = FindEntity(self.inst, 40, nil, {"dirtpile"}, {"NOCLICK", "INLIMBO"})
        if not dirtpile then
            -- No dirtpile, nothing to do...
            self.status = FAILED
            return
        end

        if self.inst.brain:HostileMobNearInst(dirtpile) then 
            self.status = FAILED
            return
        end

        -- Found one, start running towards it
        local action = self:BuildAction(dirtpile)
        if action then
            self:PushAction(action)
            self.status = RUNNING
        end

    elseif self.status == RUNNING then

        if self.pendingstatus then
            self.status = self.pendingstatus
        elseif not self.action then
            self.status = FAILED
            return
        elseif not self.action:IsValid() then
            self.status = FAILED
            return
        elseif not self.inst.components.locomotor:HasDestination() and not self.reachedDestination then
            -- We get this while uncovering the dirtpile. Check 
            --self.cancelTask = self.inst:DoTaskInTime(5, function() if self.current)

            self:DebugPrint("We have no destination and we haven't reached it yet! We're stuck!")
            self.status = FAILED
            return
        end

        -- Must be running for another dirt pile or something.
        if self.currentDirtPile == nil then
            self:DebugPrint("Not looking for a dirtpile?")
            self.status = FAILED
            return
        end

        -- TODO: force run towards dirtpile? 

    end
 end



