require "brains/ai_inventory_helper"

FindResourceOnGround = Class(BehaviourNode, function(self, inst, searchDistanceFn)
    BehaviourNode._ctor(self, "FindResourceOnGround")
    self.inst = inst
	self.distance = searchDistanceFn
	self.currentTarget = nil
	self.workDone = nil

	self.locomotorFailed = function(inst, data)
		local theAction = data.action or "[Unknown]"
		local theReason = data.reason or "[Unknown]"
		DebugPrint(self.inst, "FindResourceOnGround: Action: " .. theAction:__tostring() .. " failed. Reason: " .. tostring(theReason))
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

	self.onPickup = function(inst, data)
		-- Not sure we care who picked up this item.
		-- inst should be the item itself...I think
		if self.currentTarget == nil then
			return
		end

		if data.item == self.currentTarget then
			self.workDone = SUCCESS
		end
	end
	self.inst:ListenForEvent("onpickupitem", self.onPickup)
end)

function FindResourceOnGround:OnStop()
	self.inst:RemoveEventCallback("actionfailed", self.locomotorFailed)
	self.inst:RemoveEventCallback("onreachdestination", self.onReachDest)
	--self.inst:RemoveEventCallback("onpickupitem", self.onPickup)
end

function FindResourceOnGround:OnFail()
	--print(self.action:__tostring() .. " failed!")
    self.pendingstatus = FAILED
end
function FindResourceOnGround:OnSucceed()
	--print(self.action:__tostring() .. " complete!")
	self.pendingstatus = SUCCESS
end


function FindResourceOnGround:SetupAction(target)
	self.currentTarget = target
	self.pendingstatus = nil
	self.workDone = nil
	local action = BufferedAction(self.inst, self.currentTarget, ACTIONS.PICKUP)
	action:AddFailAction(function() self:OnFail() end)
    action:AddSuccessAction(function() self:OnSucceed() end)
	self.action = action

	------------------ DS -------------------------
	self.inst.components.locomotor:PushAction(action, true)

	------------------ DST ------------------------
	--self.action.preview_cb = function() self:RemoteActionButton(self.action, true) end
    --self.inst.components.locomotor:PreviewAction(self.action, true)
end

function FindResourceOnGround:LookForItem(dist)

	local target = FindEntity(self.inst, dist, function(item)

		if not item or not item.prefab then return false end

		-- Ignore things in the water (for now)
		if IsInWater(item) then return false end

		-- Quit picking up 'dug_grass' and the likes`
		if string.match(item.prefab, "dug_") then
			return false
		end

		-- Don't pick up food we aren't going to eat.
		-- TODO: This will make them not pick up gears if not wx, etc.
		--       Need a way to filter things that just aren't useful...
		-- if item.components.edible ~= nil and self.inst.components.eater ~= nil then
		-- 	if not self.inst.components.eater:PrefersToEat(item) then
		-- 		return false
		-- 	end
		-- end
		--if item.components.edible and item.components.edible.foodtype == FOODTYPE.BERRY

		-- Don't return true on anything up here. Only false returns valid or you'll go for
		-- something prematurely (like stuff floating in the middle of the ocean)
		if self.inst.components.prioritizer:OnIgnoreList(item.prefab) or self.inst.components.prioritizer:OnIgnoreList(item.entity:GetGUID()) then
			return false
		end

		-- Don't pick up anything that is heavy. Those require special care to drop in the right place...
		if item:HasTag("heavy") then return false end

		-- Item probably in the water. Ignore it.
		if item:HasTag("ignorewalkableplatforms") then return false end

		-- Ignore backpack (covered above)
		if IsItemBackpack(item) then return false end

		-- Ignore these dang trinkets
		if item.prefab and string.find(item.prefab, "trinket") then return false end
		-- We won't need these thing either.
		if item.prefab and string.find(item.prefab, "teleportato") then return false end

		if item.prefab and string.find(item.prefab, "bedroll_") then return false end
		-- Until we know how to use them, just leave them on the ground
		if item.prefab and string.find(item.prefab, "staff") then return false end

		if item.prefab and string.find(item.prefab, "blowdart_") then return false end

		-- Allows us to harvest flowers, but not pick up petals after dropping them
		if item.prefab == "petals" then
			return false
		end

		-- Ignore things near scary dudes
		if self.inst.brain:HostileMobNearInst(item) then
			--print("Ignoring " .. item.prefab .. " as there is something scary near it")
			return false
		end

		if item:HasTag("spider") then
			if not self.inst:HasTag("spiderwhisperer") then return false end
			if item.sg and not item.sg:HasStateTag("sleeping") then return false end
		end

		local haveFullStack,num = self.inst.components.inventory:Has(
								item.prefab, item.components.stackable and item.components.stackable.maxsize or 1)

		-- If we have a full stack of this, ignore it.
			-- exeption, if we have another stack of this...then I guess we can collect
			-- multiple stacks of it
		local canFitInStack = false
		if num > 0 and haveFullStack then
			--print("Already have a full stack of : " .. item.prefab)
			if CanFitInStack(self.inst,item) then
				DebugPrint(self.inst, "But it can fit in a stack")
				canFitInStack = true
			else
				if item:HasTag("spider") and not self.inst.components.inventory:IsTotallyFull() then
					DebugPrint(self.inst, "We can always use more friends")
					return true
				end
				-- We don't need more of this thing right now.
				--print("We don't need anymore of these")
				return false
			end
		end

		if num == 0 and self.inst.components.inventory:IsTotallyFull() then
			return false
		end

		if item.components.inventoryitem and
			item.components.inventoryitem.canbepickedup and
			not item.components.inventoryitem:IsHeld() and
			item:IsOnValidGround() and
			not item:HasTag("prey") and
			not item:HasTag("bird") then
				return true
		end
	end, nil, {"NOCLICK", "INLIMBO", "FX", "sketch"})

	return target
end

function FindResourceOnGround:Visit()
    if self.status == READY then
        self.reachedDestination = nil
		self.currentTarget = nil
		self.workDone = nil
		self.pendingStatus = nil

        -- If we aren't wearing a backpack and there is one closeby...go get it
        -- This should find all types of backpacks
        -- Note, we can't carry multiple backpacks, so if we have one in our
        -- inventory, it is equipped
        --local function isBackpack(item)
        --    if not item then return false end
        --    -- Have to use the not operator to cast to true/false.
        --    return not not item.components.equippable and not not item.components.container
        --end

        --local bodyslot = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)

        if not IsWearingBackpack(self.inst) then
            local backpack = FindEntity(self.inst, 100, function(item) return IsItemBackpack(item) end)
            if backpack then
					self:SetupAction(backpack)
					self.status = RUNNING
					return
				else
				-- -- Craft one if we know how
				-- if self.inst.components.builder:KnowsRecipe("backpack") and self.inst.components.builder:CanBuild("backpack") and not self.inst.waitingForBuild then
				-- 	self.inst.waitingForBuild = "backpack"
				-- 	self.inst.brain:SetSomethingToBuild("backpack",nil,
				-- 		function() self.inst.waitingForBuild = nil end,function() self.inst.waitingForBuild = nil end)
				-- end
					-- if self.action == nil then
					-- 	BuildIfAble(self.inst, "backpack")
					-- end
            end
        end

		local target = self:LookForItem(self.distance())

		if target then
			self:SetupAction(target)
			self.inst.brain:ResetSearchDistance()
			self.status = RUNNING
			return
		end

		-- Nothing within distance!
		self.status = FAILED
		return

    elseif self.status == RUNNING then

		-- pendingstatus will return when the action is done.
		-- workDone will let us know if the item is picked up by anyone...so we don't keep running towards
		-- things picked up by someone else
		if self.pendingstatus == SUCCESS or self.workDone == SUCCESS then
			-- While we're already here, find something next to this one we should pick up
			self.currentTarget = nil
			local target = self:LookForItem(5)
			if target then
				self:SetupAction(target)
				self.status = RUNNING
				return
			else
				self.status = SUCCESS
				return
			end
		end

		-- If we (or someone else) picked up the item, this will be set.
		if self.workDone ~= nil then
			DebugPrint(self.inst, "Work Done - nothing to do")
			self.status = self.workDone
			return
		end

		-- Sometimes we don't get a callback because we picked something up too fast.
		if self.currentTarget == nil then
			self.status = SUCCESS
			return
		end

		-- Make sure action is still valid and we aren't stuck...
		if not self.action:IsValid() then
			self.status = SUCCESS
			return
		elseif not self.inst.components.locomotor:HasDestination() and not self.reachedDestination then
			DebugPrint(self.inst, "We have no destination and we haven't reached it yet! We're stuck!")
			self.status = SUCCESS
			return
		end

		-- Still running....just be patient
    end
end



