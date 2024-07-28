ManageHunger = Class(BehaviourNode, function(self, inst, hungerPercent)
   BehaviourNode._ctor(self, "ManageHunger")
   self.inst = inst
	self.percent = hungerPercent

	-- For now, don't let wolfgang go mighty from this. Might should be in the
	-- combat section or something...
	if self.inst.prefab == "wolfgang" then

	end

	-- Hunger doesn't seem to change based on food types and tags, so just return
	-- the real value.
	self.getFoodHunger = function(food)
		return food.components.edible:GetHunger(self.inst)
	end

	-- Some players can ignore negative effects, but this isn't built into
	-- the GetHealth() function...
	self.getFoodHealth = function(food)
		if food:HasTag("monstermeat") and self.inst:HasTag("strongstomach") then return 0 end
		if food:HasTag("rawmeat") and self.inst:HasTag("strongstomach") then return 0 end
		return food.components.edible:GetHealth(self.inst)
	end

	-- Same as above...
	self.getFoodSanity = function(food)
		if food:HasTag("monstermeat") and self.inst:HasTag("strongstomach") then return 0 end
		if food:HasTag("rawmeat") and self.inst:HasTag("strongstomach") then return 0 end
		return food.components.edible:GetSanity(self.inst)
	end
end)

function ManageHunger:Debug(string)
	DebugPrint(self.inst, string)
end

-- Gets our current hunger value.
-- Has special check for wolfgang...
function ManageHunger:GetHungerPercent()
	if self.inst.prefab == "wolfgang" then
		return self.inst.components.hunger.current / TUNING.WOLFGANG_START_HUNGER
	end
	return self.inst.components.hunger:GetPercent()
end

-- Don't let wolfgang get into wimpy mode.
function ManageHunger:IsStarving()
	if self.inst.prefab == "wolfgang" then
		return self.inst.components.hunger.current <= TUNING.WOLFGANG_END_WIMPY_THRESH
	end
	return self:GetHungerPercent() <= 0.15
end

-- Returned from the ACTIONS.EAT
function ManageHunger:OnFail()
    self.pendingstatus = FAILED
end
function ManageHunger:OnSucceed()
    self.pendingstatus = SUCCESS
end

function ManageHunger:EatThisFood(food)
	local action = BufferedAction(self.inst,food,ACTIONS.EAT)
	action:AddFailAction(function() self:OnFail() end)
	action:AddSuccessAction(function() self:OnSucceed() end)
	self.action = action
	self.pendingstatus = nil
	self.inst:PushBufferedAction(action)
end


function ManageHunger:Visit()

    if self.status == READY then
		-- Don't do anything unless we are hungry enough
		local currentHunger = self:GetHungerPercent()
		if currentHunger > self.percent then
			self.status = FAILED
			return
		end

		if currentHunger < 0.3 and not self.inst.prefab == "wathgrithr" then
			self.inst.components.prioritizer:RemoveFromIgnoreList("seeds")
		elseif currentHunger > 0.7 and not self.inst.prefab == "wathgrithr" then
			self.inst.components.prioritizer:AddToIgnoreList("seeds")
		end

		-- Look for something in our inventory to eat. If we find something, go to status RUNNING
		local allFoodInInventory = self.inst.components.inventory:FindItems(function(item) return
								self.inst.components.eater:PrefersToEat(item) and
								self.getFoodHunger(item) > 0 and
								self.getFoodHealth(item) >= 0 and
								self.getFoodSanity(item) >= 0 end)

		-- if allFoodInInventory ~= nil then
		-- 	self:Debug("Current food in inventory: ")
		-- 	for k,v in ipairs(allFoodInInventory) do
		-- 		self:Debug(tostring(v))
		-- 	end
		-- 	self:Debug("------------------")
		-- end

		-- Hard to know what to eat first.
		-- Don't want to eat healing items if we aren't low on health....
		-- Also, want to eat food that will spoil sooner...

		-- Maybe, first sort by perish.
		-- Then, eat the first food that would actually provide a benefit to all 3
		-- stats.

		-- TODO: Better eating priority
		-- local function sortByPerish(food1, food2)
		-- 	local p1 = food1.components.perishable and food1.components.perishable:GetPercent() or 1
		-- 	local p2 = food2.components.perishable and food2.components.perishable:GetPercent() or 1
		-- 	if p1 == p2 then
		-- 		-- If tied for perish, sort by which gives the most hunger
		-- 		return self.getFoodHunger(food1) > self.getFoodHunger(food2)
		-- 	end
		-- 	-- Sort by the LOWEST perish percent first (will spoil sooner)
		-- 	return p1 < p2
		-- end

		-- local bestFood = nil
		-- table.sort(allFoodInInventory, sortByPerish)
		-- for k,v in pairs(allFoodInInventory) do
		-- 	-- Starting with the foods that will perish the soonest, eat the one that gives the most benefit.
		-- end
		---------------------------------------------------------------------------

		local bestFoodToEat = nil
		local missingHunger = self.inst.components.hunger.max - self.inst.components.hunger.current
		for k,v in pairs(allFoodInInventory) do
			local skip_this = false
			if self.getFoodHunger(v) > missingHunger then
				-- don't eat anything that will overfill us if we aren't starving...
				skip_this = true
			end

			if not skip_this and bestFoodToEat == nil then
				bestFoodToEat = v
			elseif not skip_this then
				self:Debug("Comparing " .. v.prefab .. " to " .. bestFoodToEat.prefab)
				if self.getFoodHunger(v) >= self.getFoodHunger(bestFoodToEat) then
					self:Debug(v.prefab .. " gives more hunger!")
					-- If it's tied, order by perishable percentage
					local newWillPerish = v.components.perishable
					local curWillPerish = bestFoodToEat.components.perishable
					if newWillPerish and not curWillPerish then
						self:Debug("...and will perish")
						bestFoodToEat = v
					elseif newWillPerish and curWillPerish and newWillPerish:GetPercent() < curWillPerish:GetPercent() then
						self:Debug("...and will perish sooner")
						bestFoodToEat = v
					else
						self:Debug("...but " .. bestFoodToEat.prefab .. " will spoil sooner so not changing")
						-- Keep the original...it will go stale before this one.
					end
				else
					-- The new food will provide less hunger. Only consider this if it is close to going stale or going
					-- really bad
					if v.components.perishable then
						-- Stale happens at .5, so we'll get things between .5 and .6
						if v.components.perishable:IsFresh() and v.components.perishable:GetPercent() < .6 then
							print(v.prefab .. " isn't better...but is close to going stale")
							bestFoodToEat = v
						-- Likewise, next phase is at .2, so get things between .2 and .3
						elseif v.components.perishable:IsStale() and v.components.perishable:GetPercent() < .3 then
							print(v.prefab .. " isn't better...but is close to going bad")
							bestFoodToEat = v
						end
					end
				end
			end
		end

		if bestFoodToEat then
			self:EatThisFood(bestFoodToEat)
			self.status = RUNNING
			return
		end



		-- We didn't find anything good. Don't eat bad food unless we're starving
		if not self:IsStarving() then
			self.status = FAILED
			return
		end

		self:Debug("We're too hungry. Check emergency reserves!")
		-- Hack: Player special stuff probably shouldnt' be sprinkled all over like this...
		if self.inst.components.souleater ~= nil then
			self:Debug("I can eat souls! Do I have any?")
			local soul = self.inst.components.inventory:FindItem(function(item) return item:HasTag("soul") end)
			if soul then
				self:EatThisFood(soul)
				self.status = RUNNING
				return
			end
		end


		allFoodInInventory = self.inst.components.inventory:FindItems(function(item) return
										self.inst.components.eater:PrefersToEat(item) and
										self.getFoodHunger(item) > 0 end)

		for k,v in pairs(allFoodInInventory) do
			local health = self.getFoodHealth(v)
			if not bestFoodToEat and (health >= 0 or (math.abs(health) < self.inst.components.health.currenthealth)) then
				bestFoodToEat = v
			elseif bestFoodToEat and (health >= 0 or (math.abs(health) < self.inst.components.health.currenthealth)) then
				if self.getFoodHunger(v) > self.getFoodHunger(bestFoodToEat) and
				   health > self.getFoodHealth(bestFoodToEat) then
						bestFoodToEat = v
				end
			end
		end

		if bestFoodToEat then
			self:EatThisFood(bestFoodToEat)
			self.status = RUNNING
			return
		end

		-- Nothing to eat!
		self.status = FAILED

    elseif self.status == RUNNING then
		if self.pendingstatus then
			self.status = self.pendingstatus
		elseif not self.action:IsValid() then
			self.status = FAILED
		end
    end
end



