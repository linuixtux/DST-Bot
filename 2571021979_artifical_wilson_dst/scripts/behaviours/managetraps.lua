ManageTraps = Class(BehaviourNode, function(self, inst, sanityTargetFn)
    BehaviourNode._ctor(self, "ManageTraps")
    self.inst = inst


    self.buildItem = function(inst, data)
		if self.waitingForBuild ~= nil then
			if data.item.prefab == self.waitingForBuild then
				DebugPrint(self.inst, "We've made a " .. self.waitingForBuild)
				self.waitingForBuild = nil
                self.pendingstatus = SUCCESS
			else
				DebugPrint(self.inst, "uhhh, we made....something else? " .. data.item.prefab)
				self.waitingForBuild = nil
                self.pendingstatus = FAILED
			end
		end
	end
	self.inst:ListenForEvent("builditem", self.buildItem)
 end)

 function ManageTraps:DebugPrint(string)
    DebugPrint(self.inst, "ManageTraps: " .. string)
 end

 function ManageTraps:CheckForMurder()
    local murderable = self.inst.components.inventory:FindItems(
       function(item)
          if item.components and item.components.health then
             return true
          elseif item.components and item.components.murderable then
             return true
          end

          return false
    end)

    for k,v in pairs(murderable) do
       -- Don't murder spiders if we are a spider
       local murder = true
       if v:HasTag("spider") and self.inst:HasTag("spiderwhisperer") then
          murder = false
       end


       if murder == true then
            local action = BufferedAction(self.inst, v, ACTIONS.MURDER)
            action:AddSuccessAction(
                function()
                    self.pendingstatus = SUCCESS
                    self.action = nil
                end)

            action:AddFailAction(function()
                self.pendingstatus = FAILED
                self.action = nil
            end)

            self.pendingstatus = nil
            self.action = action
            self.inst.components.locomotor:PushAction(action)
            self.status = RUNNING
            return
       end

    end
 end

 function ManageTraps:BuildAction(trap)

    local action = BufferedAction(self.inst, trap, ACTIONS.CHECKTRAP)
    if not action then return end

    action:AddSuccessAction(
        function()
            self:DebugPrint("Got the trap!")
            self.pendingstatus = SUCCESS
            self.action = nil
        end)

    action:AddFailAction(function()
        self:DebugPrint("Failed doing trap action")
        self.pendingstatus = FAILED
        self.action = nil

    end)

    return action
 end

 function ManageTraps:BuildPlaceAction(hole, trap)
    if not hole then return nil end

    local pt = hole:GetPosition()
    local gotohole = BufferedAction(self.inst, nil, ACTIONS.DROP, trap, pt)

    gotohole:AddSuccessAction(
        function()
            self:DebugPrint("deploying trap")
            self.pendingstatus = SUCCESS
            self.action = nil
            self.hole = nil
        end)

    gotohole:AddFailAction(function()
        self:DebugPrint("Failed placing TRAP")
        self.pendingstatus = FAILED
        self.action = nil
        self.hole = nil
    end)

    --local gotohole = BufferedAction(self.inst, nil, ACTIONS.WALKTO, nil, pt)
    -- gotohole:AddSuccessAction(
    --     function()
    --         local action = BufferedAction(self.inst, nil, ACTIONS.DROP, trap, pt)
    --         action:AddSuccessAction(
    --             function()
    --                 self:DebugPrint("deploying trap")
    --                 self.pendingstatus = SUCCESS
    --                 self.action = nil
    --                 self.hole = nil
    --             end)

    --         action:AddFailAction(function()
    --             self:DebugPrint("Failed placing TRAP")
    --             self.pendingstatus = FAILED
    --             self.action = nil
    --             self.hole = nil
    --         end)

    --         self.inst.components.locomotor:PushAction(action, true)
    -- end)

    -- gotohole:AddFailAction(function()
    --     self:DebugPrint("Failed walking to hole")
    --     self.pendingstatus = FAILED
    --     self.action = nil
    --     self.hole = nil
    -- end)

    return gotohole
 end

 function ManageTraps:Visit()

    if self.status == READY then
        self.pendingstatus = nil
        self.action = nil

        -- if self.waitingForBuild ~= nil then
        --     self.status = FAILED
        --     return
        -- end

        self:CheckForMurder()

        -- if self.action ~= nil then
        --     self.status = FAILED
        --     return
        -- end

        self.waitingForBuild = nil

        local x, y, z = self.inst.Transform:GetWorldPosition()

        -- Find all traps around me.
        local traps = TheSim:FindEntities(x,y,z,25,{"trap"},{"INLIMBO", "NOCLICK"})

        local triggered = {}
        for k,v in ipairs(traps) do
            if v:HasTag("trapsprung") then
                table.insert(triggered, v)
            end
        end

        -- If there is a triggered trap, go get the thing inside
        if #triggered > 0 and not self.inst.components.inventory:IsTotallyFull() then
            local action = self:BuildAction(triggered[1])
            if action then
                self:DebugPrint("Going to harvest " .. tostring(triggered[1]))
                self.action = action
                self.inst.components.locomotor:PushAction(action, true)
                self.status = RUNNING
                return
            end
        end

        -- if we got here, there must not have been a triggered trap.
        -- If there are any rabbit holes around, then go make a trap

        local rabbithole = FindEntity(self.inst, 15, function(thing)

            if thing.prefab ~= "rabbithole" then
                return false
            end

            if thing.iscollapsed == true then
                return false
            end

            local alreadyTrapped = FindEntity(thing, 5, nil, {"trap"})

            if alreadyTrapped ~= nil then
                --self:DebugPrint("Hole already has a trap")
                return false
            end

            return true
        end, nil, {"NOCLICK", "INLIMBO"})

        if not rabbithole then
            self.status = FAILED
            return
        end

        -- Found a hole without a trap. Make a trap
        self.hole = rabbithole

        -- make a trap (if don't have one)
        if not self.inst.components.inventory:Has("trap", 1) then
            -- Don't use all of our reserves for this...
            if not (self.inst.components.inventory:Has("cutgrass", 16) and self.inst.components.inventory:Has("twigs", 8)) then
                --self:DebugPrint("Short on supplies....not making trap")
                self.status = FAILED
                return
            end
            if not self.inst.components.inventory:IsTotallyFull() and self.inst.components.builder and self.inst.components.builder:CanBuild("trap") then

                if CraftItem(self.inst, "trap") then
                    --self:DebugPrint("Building a trap")
                    self.waitingForBuild = "trap"
                    self.status = RUNNING
                else
                    self.status = FAILED
                end
                return
            else
                -- TODO: Add the recipe to the gather list? They should already be there...
                --addRecipeToGatherList(thingToBuild,false)
                -- cant build the right tool
                self.status = FAILED
                return
            end
        else

            local trap = self.inst.components.inventory:FindItem(function(t) return t.prefab == "trap" end)
            if not trap then
                self:DebugPrint("Still don't have a trap???")
                self.status = FAILED
                return
            end

            local action = self:BuildPlaceAction(self.hole, trap)
            if action ~= nil then
                --self:DebugPrint("Walking to hole " .. tostring(self.hole))
                self.action = action
                self.inst.components.locomotor:PushAction(action, true)
                self.status = RUNNING
                return
            end

        end

        self.status = FAILED
        return

    elseif self.status == RUNNING then

        if self.pendingstatus then
            self.status = self.pendingstatus
            return
        elseif not self.action and not self.waitingForBuild then
            self:DebugPrint("No action???")
            self.status = FAILED
            return
        elseif self.action and not self.action:IsValid() then
            self:DebugPrint("Action is not valid...")
            self.status = FAILED
            return
        elseif not self.action and self.inst.components.locomotor:HasDestination() and not self.reachedDestination then
            --self:DebugPrint("We have no destination and we haven't reached it yet! We're stuck!")
            self.status = FAILED
            return
        end

        if self.waitingForBuild then
            --self:DebugPrint("Waiting for trap to be built...")
            -- Waiting for a trap to be built...nothing to do
            if self.inst.sg:HasStateTag("doing") then
                self.status = RUNNING
                return
            else
                self:DebugPrint("Waiting for build...but don't have busy tag??")
                self.waitingForBuild = nil
                self.action = nil
                self.status = FAILED
                return
            end
        end

        local action = self.inst:GetBufferedAction()
        if action and action == self.action then
            --self:DebugPrint("Still doing our action!")
            return
        elseif action and action ~= self.action then
            self:DebugPrint("We're doing something....just not this....")
            self.status = FAILED
            return
        elseif not action then
            self:DebugPrint("No action? Are we stuck?")
            self.status = FAILED
            return
        end

        if not self.inst.sg:HasStateTag("busy") then
            self:DebugPrint("Reached the end and we aren't busy??")
            self.status = FAILED
            return
        end
        -- self:DebugPrint("Reached end of running??")
        -- self.status = FAILED
        return
    end
 end



