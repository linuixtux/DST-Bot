ManageHealth = Class(BehaviourNode, function(self, inst, healthPercent)
    BehaviourNode._ctor(self, "ManageHealth")
    self.inst = inst
	self.percent = healthPercent or .1
end)

-- Returned from the buffered actions
function ManageHealth:OnFail()
    self.pendingstatus = FAILED
end
function ManageHealth:OnSucceed()
    self.pendingstatus = SUCCESS
end

function ManageHealth:DoThisAction(action)
	action:AddFailAction(function() self:OnFail() end)
	action:AddSuccessAction(function() self:OnSucceed() end)
	self.action = action
	self.pendingstatus = nil
	self.inst:PushBufferedAction(action)
end

function ManageHealth:ReleaseSoul()
	if not self.inst.components.souleater then return false end

	if self.lastDropTime == nil then
		self.lastDropTime = 0
	end

	-- It takes a bit of time for the soul to be consumed. Don't yeet them all right away.
	if GetTime() - self.lastDropTime < 2 then return false end
	local soul = self.inst.components.inventory:FindItem(function(item) return item:HasTag("soul") end)
	if soul == nil then return false end
	--self.inst.components.inventory:DropItem(soul)
	self:DoThisAction(BufferedAction(self.inst,self.inst,ACTIONS.DROP,soul))
	self.lastDropTime = GetTime()
	return true
end

function ManageHealth:Visit()

    if self.status == READY then
		-- Don't do anything unless we are hurt
		if self.inst.components.health:GetPercent() > self.percent then
			self.status = FAILED
			return
		end

		if self:ReleaseSoul() then
			self.status = RUNNING
			return
		end

		--local healthMissing = self.inst.components.health:GetMaxWithPenalty() - self.inst.components.health.currenthealth
		local healthMissing = GetHealthMax(self.inst) - self.inst.components.health.currenthealth
		local hungerMissing = self.inst.components.hunger.max - self.inst.components.hunger.current

		-- Do we have edible food?
		local bestFood = nil
		-- If we have food that restores health, eat it
		local healthFood = self.inst.components.inventory:FindItems(function(item) return self.inst.components.eater:PrefersToEat(item) and
																						item.components.edible:GetHealth(self.inst) > 0 end)


		-- Sorts the table by comparing the healing % to the hunger %.
		-- Just because it heals for the most doesn't make it the best thing ot use.
		local function sortByHeals(it1, it2)
			local h1 = it1.components.edible:GetHealth(self.inst)
			local h2 = it2.components.edible:GetHealth(self.inst)
			local s1 = it1.components.edible:GetHunger(self.inst)
			local s2 = it2.components.edible:GetHunger(self.inst)

			local ratio1 = 1 -- 100% healing if hunger is 0 or below
			local ratio2 = 1 -- 100% healing if hunger is 0 or below
			if s1 > 0 then
				ratio1 = h1/s1
			end
			if s2 > 0 then
				ratio2 = h2/s2
			end

			if ratio1 == ratio2 then
				local p1 = it1.components.perishable and it1.components.perishable:GetPercent() or 1
				local p2 = it2.components.perishable and it2.components.perishable:GetPercent() or 1
				return p1 < p2
			end
			return ratio1 > ratio2
		end

		table.sort(healthFood, sortByHeals)
		for k,v in pairs(healthFood) do
			-- Just eat the first thing we find that has positive healing that
			-- wont overheal us.
			-- Also, don't consider eating something that provides hunger unless
			local health = v.components.edible:GetHealth(self.inst)
			local hunger = v.components.edible:GetHunger(self.inst)
			if bestFood == nil then
				-- Don't overheal
				if health <= healthMissing then
					-- It wont overheal us. Consider it good only if we wont overeat.
					-- Unless it provides a substantion amount of healing that is.
					if hunger <= hungerMissing or health >= TUNING.HEALING_MEDSMALL then
						bestFood = v
					end
				end
			end
		end
		-- Find the best food that doesn't go over and eat that.
		-- TODO: Sort by staleness
		-- for k,v in pairs(healthFood) do
		-- 	--DebugPrint(self.inst, "ManageHealth - checking food " .. tostring(v))

		-- 	-- Convert to a percent of max
		-- 	local heal = v.components.edible:GetHealth(self.inst)
		-- 	local h = heal / (GetHealthMax(self.inst) or 100)
		-- 	-- Only consider foods that heal for less than hunger if we are REALLY hurting
		-- 	local z = v.components.edible:GetHunger(self.inst) / (self.inst.components.hunger.max or 100)

		-- 	DebugPrint(self.inst, tostring(v.prefab) .. " provides " .. tostring(h) .. "h and " .. tostring(z) .. "s")

		-- 	-- h > z, this item is better used as healing
		-- 	-- or heals for more than 5 and we are really hurting
		-- 	if h > z or (h <= z and  heal >= 5 and self.inst.components.health:GetPercent() < .25) then
		-- 		if heal <= healthMissing then
		-- 			if not bestFood or (bestFood and bestFood.components.edible:GetHealth(self.inst) < heal) then
		-- 				bestFood = v
		-- 			end
		-- 		end
		-- 	end
		-- end

		if bestFood then
			self:DoThisAction(BufferedAction(self.inst,bestFood,ACTIONS.EAT))
			self.status = RUNNING
			return
		end

		-- Out of food. Do we have any other healing items?
		local healthItems = self.inst.components.inventory:FindItems(function(item) return item.components.healer end)

		local bestHealthItem = nil
		for k,v in pairs(healthItems) do
			local h = v.components.healer.health
			if h <= healthMissing then
				if not bestHealthItem or (bestHealthItem and bestHealthItem.components.healer.health < h) then
					bestHealthItem = v
				end
			end
		end

		if bestHealthItem then
			print("Healing with " .. bestHealthItem.prefab)
			self:DoThisAction(BufferedAction(self.inst,self.inst,ACTIONS.HEAL,bestHealthItem))
			self.status = RUNNING
			return
		end

		-- Nothing to heal with...oh well
		self.status = FAILED

		elseif self.status == RUNNING then
			if self.pendingstatus then
				self.status = self.pendingstatus
			elseif not self.action:IsValid() then
				self.status = FAILED
			end
		end
end



