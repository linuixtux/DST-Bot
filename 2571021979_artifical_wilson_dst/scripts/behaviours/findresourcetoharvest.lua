FindResourceToHarvest = Class(BehaviourNode, function(self, inst, searchDistanceFn)
    BehaviourNode._ctor(self, "FindResourceToHarvest")
    self.inst = inst
	self.distance = searchDistanceFn
	self.currentTarget = nil
	self.workDone = nil
	
	self.locomotorFailed = function(inst, data)
		local theAction = data.action or "[Unknown]"
		local theReason = data.reason or "[Unknown]"
		DebugPrint(self.inst, "FindResourceToHarvest: Action: " .. theAction:__tostring() .. " failed. Reason: " .. tostring(theReason))
        self:OnFail() 
    end
	
	self.onReachDest = function(inst,data)
		local target = data.target
		if target and self.action and target == self.action.target then
			self.reachedDestination = true
		end
	end
	
	self.inst:ListenForEvent("actionfailed", self.locomotorFailed)
	self.inst:ListenForEvent("onreachdestination", self.onReachDest)

	-- If we, or someone else, harvests this thing, then we can stop. 
	-- Only checks if the callback target matches our current target. 
	self.onHarvest = function(inst, data)
		local object = data.object
		if object and object == self.currentTarget then
			self.workDone = SUCCESS
		end
	end
	self.inst:ListenForEvent("harvestsomething", self.onHarvest)
	
end)

function FindResourceToHarvest:OnStop()
	self.inst:RemoveEventCallback("actionfailed", self.locomotorFailed)
	self.inst:RemoveEventCallback("onreachdestination", self.onReachDest)
	self.inst:RemoveEventCallback("harvestsomething", self.onHarvest)
end

function FindResourceToHarvest:OnFail()
    self.pendingstatus = FAILED
end
function FindResourceToHarvest:OnSucceed()
	self.pendingstatus = SUCCESS
end

function FindResourceToHarvest:Visit()
	
    if self.status == READY then
		self.reachedDestination = nil
		self.workDone = nil
		self.currentTarget = nil
		
		local target = FindEntity(self.inst, self.distance(), function(item)

			-- Ignore things in water (for now)
			if IsInWater(item) then return false end
					
			if item.components.pickable and item.components.pickable:CanBePicked() and item.components.pickable.caninteractwith then
				local theProductPrefab = item.components.pickable.product
				if theProductPrefab == nil then
					return false
				end

				if self.inst.components.prioritizer:OnIgnoreList(item.prefab) then return false end
				
				-- If we have some of this product, it will override the isFull check
				local haveItem = self.inst.components.inventory:FindItem(function(invItem) return theProductPrefab == invItem.prefab end)
				
				if self.inst.components.prioritizer:OnIgnoreList(item.components.pickable.product) then
					return false
				end
				-- This entity is to be ignored
				if self.inst.components.prioritizer:OnIgnoreList(item.entity:GetGUID()) then return false end
				
				if self.inst.brain:HostileMobNearInst(item) then 
					--DebugPrint(self.inst, "Ignoring " .. item.prefab .. " as there is a monster by it")
					return false 
				end
				
				-- Check to see if we have a full stack of this item
				local theProduct = self.inst.components.inventory:FindItem(function(item) return (item.prefab == theProductPrefab) end)
				if theProduct then
					-- If we don't have a full stack of this...then pick it up (if not stackable, we will hold 2 of them)
					return not self.inst.components.inventory:Has(theProductPrefab,theProduct.components.stackable and theProduct.components.stackable.maxsize or 2)
				else
					-- Don't have any of this...lets get some (only if we have room)						
					return not self.inst.components.inventory:IsTotallyFull()
				end
			end
			-- Default case...probably not harvest-able. Return false.
			return false
		end, nil, {"thorny"})

		if target then
			local action = BufferedAction(self.inst,target,ACTIONS.PICK)
			action:AddFailAction(function() self:OnFail() end)
			action:AddSuccessAction(function() self:OnSucceed() end)
			self.action = action
			self.pendingstatus = nil
			self.currentTarget = target

			self.inst.components.locomotor:PushAction(action, true)
			self.inst.brain:ResetSearchDistance()
			self.status = RUNNING
			return
		end
		self.status = FAILED
		return
    elseif self.status == RUNNING then
		-- pendingStatus is a callback from the action itself. 
		if self.pendingstatus then
			self.status = self.pendingstatus
			return
		end

		-- If self.workDone - either we, or someone else, harvested the thing. Nothing to do
		if self.workDone ~= nil then
			return self.workDone
		end

		if not self.currentTarget or not self.currentTarget:IsValid() then
			DebugPrint(self.inst, "Harvest - current target is no longer valid")
			self.status = SUCCESS
			return
		end

		-- If the action is not valid, stop. 
		if not self.action:IsValid() then
			self.status = SUCCESS
		elseif not self.inst.components.locomotor:HasDestination() and not self.reachedDestination then
			DebugPrint(self.inst, "We have no destination and we haven't reached it yet! We're stuck!")
			self.status = SUCCESS
		end

		if not self.inst:GetBufferedAction() then
			DebugPrint(self.inst, "Harvest - no current buffered action???")
			self.status = SUCCESS
			return
		end

		-- Must still be walking towards the thing. Just stay in the running state. 
    end
end



