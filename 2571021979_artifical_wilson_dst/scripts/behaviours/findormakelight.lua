MaintainLightSource = Class(BehaviourNode, function(self, inst, searchDistance)
    BehaviourNode._ctor(self, "MaintainLightSource")
    self.inst = inst
	self.distance = searchDistance
	self.waitingForBuild = nil
	self.buildTime = nil

	-- This is the distance wilson will run towards the light. This is not the distance
	-- he will stay to the light.
	self.safe_distance = 2

	self.buildItem = function(inst, data)
		-- Only care about stuff we build
		if inst ~= self.inst then return end
		-- We weren't expecting a build....
		if self.waitingForBuild == nil then return end

		-- Note - buildstructure doesn't have prototyper in the data.
		--  item = prod, recipe = recipe, skin = skin, prototyper = self.current_prototyper

		if data.item.prefab == self.waitingForBuild then
			self:DebugPrint("We've made a " .. self.waitingForBuild)
			--self.waitingForBuild = nil
			self.pendingstatus = SUCCESS
		else
			-- TODO: What if we're making a multi-tier build? We will have to
			--       craft sub components, so....
			--       For now, assume everything is a single build in this node I guess...
			self:DebugPrint("uhhh, we made....something else? " .. data.item.prefab)
			--self.waitingForBuild = nil
			self.pendingstatus = FAILED
		end
	end


	self.inst:ListenForEvent("builditem", self.buildItem)
	self.inst:ListenForEvent("buildstructure", self.buildItem)
end)

function MaintainLightSource:DebugPrint(string)
	DebugPrint(self.inst, string)
end

function MaintainLightSource:OnActionFail()
	self.pendingstatus = FAILED
end

function MaintainLightSource:OnActionSucceed()
	self.pendingstatus = SUCCESS
end

-- Given a lightsource or a prefab, will return true if this is a valid light source
local function IsValidLightSource(light)
	local parent = light.entity:GetParent()
	if parent ~= nil then
		if parent.prefab == "firepit" or parent.prefab == "campfire" or parent.prefab == "torch" then
			return true
		end
		return false
	end

	-- Apparently torchfire doesn't have a parent. It is its own thing. It just follows the torch around lol.
	if light.prefab and light.prefab == "firepit" or light.prefab == "campfire" or light.prefab == "torchfire" then
		return true
	end

	return false
end

function MaintainLightSource:Visit()

-- 0) Are we near a light source? If yes...nothing to do.
-- 1) Are we near a firepit? If we are, add fuel if needed.
-- 2) Are we not near a firepit? Make a campfire.
-- 3) If we can't make a campfire...make a torch!
-- 4) If we can't make a torch...uhhh, find some light asap!

    if self.status == READY then
		self.currentLightSource = nil
		self.runningTowardsLight = false

		local x,y,z = self.inst.Transform:GetWorldPosition()
        local ents = TheSim:FindEntities(x,y,z, self.distance, {"lightsource"})

		-- Find the closest valid light source near us
		local source = nil
		for k,v in pairs(ents) do
			if not source and IsValidLightSource(v) then
				source = v
			end
		end

		if source then
			-- Get the safety distance according to the lightsource
			-- Only run towards it if the current light value where I'm standing is 0
			if self.inst.LightWatcher:GetLightValue() < TUNING.SANITY_LOW_LIGHT*2 then
    		    self:DebugPrint("It's too dark!")
                self.currentLightSource = source
                self.runningTowardsLight = true
                self.inst.components.locomotor:RunInDirection(
                    self.inst:GetAngleToPoint(Point(source.Transform:GetWorldPosition())))
                -- Run towards the light!
                self.status = RUNNING
                return
			end

			-- If it's a firepit or campfire, make sure there's enough fuel in it.
			local parent = source.entity:GetParent()
			if parent then
				if parent.components.fueled and parent.components.fueled:GetPercent() < .25 then
					self.currentLightSource = parent
					self.status = RUNNING
					return
				end
			else
				-- This lightsource has no parent? Whatever...it's good enough for me
				self.status = FAILED
				return
			end

			-- All is well. Nothing to do.
			self.status = FAILED
			return
		end

		-- Not near a light source currently. Are we next to an unlit firepit?
		local firepit = GetClosestInstWithTag("campfire", self.inst, self.distance)
		if firepit then
			self:DebugPrint("No lightsource nearby...but there's an unlit firepit!")
			-- Set this as the current source. The running node will take care of
			-- adding more fuel (and walking towards it).
			-- Don't return here, just move straight to running node.
			self.currentLightSource = firepit
			self.status = RUNNING
			source = firepit
		end

		-- Nothing nearby! Fix this asap.
		if not source then
			-- If i'm holding a torch, good enough I guess.
			local currentEquippedItem = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
			self:DebugPrint("Currently holding: " .. tostring(currentEquippedItem))
			if currentEquippedItem then
				if currentEquippedItem.Light or currentEquippedItem:HasTag("lighter") then
					-- See if it needs more fuel
					if currentEquippedItem.components and currentEquippedItem.components.fueled then
						if currentEquippedItem.components.fueled:GetPercent() > .2 then
							self:DebugPrint("Currently holding a light source with enough fuel")
							self.status = SUCCESS
							return
						end
					else
						self:DebugPrint("Currently holding a light source with infinite fuel?")
						self.status = SUCCESS
						return
					end
				end
				-- self:DebugPrint("Currentling holding: " .. tostring(currentEquippedItem))
				-- if currentEquippedItem.Light then
				-- 	self:DebugPrint("This thing identifies as a light...?")
				-- 	self.status = FAILED
				-- 	return
				-- end
				-- if currentEquippedItem:HasTag("lighter") then
				-- 	self:DebugPrint("This thing has lighter tag...")
				-- 	self.status = FAILED
				-- 	return
				-- end
			end

			self:DebugPrint("No light nearby!!!")
			-- Shit...better find one.
			self.status = RUNNING
		end
	end

    if self.status == RUNNING then

		if self.runningTowardsLight then
			--print("Running towards light")
			-- Uhh, the light has vanished. Return
			-- SUCCESS so we restart the brain loop asap.
			if self.currentLightSource == nil then
				self.status = SUCCESS
				return
			end

			if self.currentLightSource and self.currentLightSource.Light then
				local intensity = self.currentLightSource.Light:GetIntensity() or 0
				if intensity == 0 then
					self:DebugPrint("The light has gone away!")
					self.currentLightSource = nil
					self.runningTowardsLight = false
					self.status = FAILED
					return
				end
			elseif self.currentLightSource and not self.currentLightSource.Light then
				self:DebugPrint("This doesn't have a Light component? " .. tostring(self.currentLightSource))
			end

			-- Keep running until we are in the TUNING.SANITY_HIGH_LIGHT field
			if self.inst.LightWatcher:GetLightValue() >= math.max(TUNING.SANITY_LOW_LIGHT,TUNING.SANITY_HIGH_LIGHT/3) then
			    self.inst.components.locomotor:Stop()
                self.runningTowardsLight = false
                self.status = SUCCESS
                return
            else
   				-- Keep running towards the light.
   				-- Set the locomotor to run again incase something interrupted it. This
   				-- is important, dammit!
   				self.inst.components.locomotor:RunInDirection(
						self.inst:GetAngleToPoint(Point(self.currentLightSource.Transform:GetWorldPosition())))
				self.status = RUNNING
				return
			end
		end

		-- If we're waiting for a build, nothing to do
		if self.waitingForBuild ~= nil and self.pendingstatus == nil then
			--self:DebugPrint("Waiting for " .. tostring(self.waitingForBuild) .. " to be built")
			if self.buildTime then
				if GetTime() - self.buildTime > 4 then
					self:DebugPrint("Build timeout! Abort!")
					self.waitingForBuild = nil
					self.buildTime = nil
					self.status = FAILED
					return
				end
			end
			self.status = RUNNING
			return
		end

		-- If pendingstatus is FAILED, built failed.
		if self.waitingForBuild ~= nil and self.pendingstatus == FAILED then
			self:DebugPrint("Our build failed!!!")
			self.pendingstatus = nil
			self.waitingForBuild = nil
			self.status = FAILED
			return
		end

		-- The thing we were building is finally complete
		if self.waitingForBuild ~= nil and self.pendingstatus == SUCCESS then
			self:DebugPrint("Yay, build done!")
			local buildRecipe = self.waitingForBuild
			self.waitingForBuild = nil

			self:DebugPrint("I built " .. buildRecipe)

			self.pendingstatus = nil

			-- If we were making a torch, equip it right now.
			if buildRecipe and buildRecipe == "torch" then
				-- If our inventory was full, this will probably go into the overflow slot
				local haveTorch = self.inst.components.inventory:FindItem(function(item) return item.prefab == "torch" end)
				if haveTorch then
					self.inst.components.inventory:Equip(haveTorch)
					self.status = SUCCESS
					return
				end
				-- Wait...torch finished building and we don't have a torch? We must have had a full inventory and dropped it!
				-- Drop something and pick it up
				local torchOnGround = FindEntity(self.inst, 5, function(item) return item.prefab == "torch" end)
				if torchOnGround then
					self:DebugPrint("Stupid full inventory")
					self.inst.components.inventory:DropItem(self.inst.components.inventory:GetItemInSlot(7), true)
					-- Drop whatever is in our hands and pick up that torch

					--self.inst.components.inventory:DropItem(self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS))
					local action = BufferedAction(self.inst, torchOnGround, ACTIONS.PICKUP)
					action:AddSuccessAction(function() self:OnActionSucceed() end)
					action:AddFailAction(function() self:OnActionFail() end)
					self.inst.components.locomotor:PushAction(action, true)
					self.status = RUNNING

					return
				end

				-- WTF!!! We built one, and it has vanished????
				self:DebugPrint("We built a torch and can't find it!!!")
				self.status = FAILED
				return
			end

			-- Must have been our firepit/campfire. Yay!
			self.status = SUCCESS
			return
		end

		-- Waiting for a build to succeed...nothing to do
		-- if self.currentBuildAction and self.pendingstatus == nil then
		-- 	print("Waiting for build to finish...")
		-- 	-- In a rare case, we will be waiting for an action, but our stategraph
		-- 	-- says we aren't doing anything. This isn't right! We've failed!
		-- 	if self.inst.sg:HasStateTag("idle")then
		-- 		print("FindOrMakeLight: SG: ---------- \n " .. tostring(self.inst.sg))
		-- 		self.status = FAILED
		-- 		return
		-- 	end

		-- 	self.status = RUNNING
		-- 	return
		-- end

		-- Uhh...our build failed! Do we just try again?
		-- if self.currentBuildAction and self.pendingstatus == FAILED then
		-- 	print("Our build failed!!!")
		-- 	self.pendingstatus = nil
		-- 	self.currentBuildAction = nil
		-- 	self.status = RUNNING
		-- 	return
		-- end

		-- The build finished! If it was a torch, equip the torch
		-- if self.currentBuildAction and self.pendingstatus == SUCCESS then
		-- 	print("Yay, build done!")
		-- 	local buildRecipe = self.currentBuildAction.recipe
		-- 	print("I built " .. buildRecipe)

		-- 	self.currentBuildAction = nil
		-- 	self.pendingstatus = nil

		-- 	if buildRecipe and buildRecipe == "torch" then
		-- 		-- If our inventory was full, this will probably go into the overflow slot
		-- 		local haveTorch = self.inst.components.inventory:FindItem(function(item) return item.prefab == "torch" end)
		-- 		if haveTorch then
		-- 			self.inst.components.inventory:Equip(haveTorch)
		-- 			self.status = SUCCESS
		-- 			return
		-- 		end
		-- 		-- Wait...torch finished building and we don't have a torch? We must have had a full inventory and dropped it!
		-- 		-- Drop something and pick it up
		-- 		local torchOnGround = FindEntity(self.inst, 5, function(item) return item.prefab == "torch" end)
		-- 		if torchOnGround then
		-- 			print("Stupid full inventory")
		-- 			self.inst.components.inventory:DropItem(self.inst.components.inventory:GetItemInSlot(7), true)
		-- 			-- Drop whatever is in our hands and pick up that torch

		-- 			--self.inst.components.inventory:DropItem(self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS))
		-- 			local action = BufferedAction(self.inst, torchOnGround, ACTIONS.PICKUP)
		-- 			action:AddSuccessAction(function() self:OnActionSucceed() end)
		-- 			action:AddFailAction(function() self:OnActionFail() end)
		-- 			self.inst.components.locomotor:PushAction(action, true)
		-- 			self.status = RUNNING

		-- 			return
		-- 		end

		-- 		-- WTF!!! We built one, and it has vanished. This is fucked up!
		-- 		self.status = FAILED
		-- 		return
		-- 	end

		-- 	-- Must have been our firepit. Yay!
		-- 	self.status = SUCCESS
		-- 	return
		-- end

		-- Finally, check to see if we ever got that stupid torch
		-- if self.pendingstatus and self.pendingstatus == SUCCESS then
		-- 	self.status = SUCCESS
		-- 	self.pendingstatus = nil
		-- 	self.currentBuildAction = nil
		-- 	return
		-- end

		self.currentBuildAction = nil
		self.pendingstatus = nil

		-- If there was a lightsource defined, go manage it.
		if self.currentLightSource then
			-- There was a light source. It must need fuel or something.
			if self.currentLightSource.components.fueled and self.currentLightSource.components.fueled:GetPercent() <= .25 then

				-- Find fuel to add to the fire
				local allFuelInInv = self.inst.components.inventory:FindItems(function(item)
												 return item.components.fuel and
														not item.components.armor and
														item.prefab ~= "livinglog" and
														self.currentLightSource.components.fueled:CanAcceptFuelItem(item) end)

				local bestFuel = nil
				for k,v in pairs(allFuelInInv) do
					-- TODO: This is a bit hackey...but really, logs are #1
					if v.prefab == "log" then
						local action = BufferedAction(self.inst, self.currentLightSource, ACTIONS.ADDFUEL, v)
						self.inst.components.locomotor:PushAction(action,true)
						-- Keep running in case we need to add more
						self.status = RUNNING
						return
					else
						bestFuel = v
					end
				end

				-- Don't add this other burnable stuff unless the fire is looking really sad.
				-- TODO: Always save enough to make a torch. i.e....don't throw in our last grass or sticks!!
				if bestFuel and self.currentLightSource.components.fueled:GetPercent() < .15 then
					self:DebugPrint("Adding emergency reserves")
					local action = BufferedAction(self.inst,self.currentLightSource,ACTIONS.ADDFUEL,bestFuel)
					self.inst.components.locomotor:PushAction(action,true)
					-- Return true to come back here and make sure all is still good
					self.status = RUNNING
					return
				end

				-- We apparently have no more fuel to add. Let it burn a bit longer before executing
				-- the emergency plan.
				if self.currentLightSource.components.fueled:GetPercent() > .05 then
					-- Return false to let the brain continue to other actions rather than
					-- to keep checking
					self.status = FAILED
					return
				end

			elseif self.currentLightSource.components.fueled and self.currentLightSource.components.fueled:GetPercent() > .25 then
				-- We've added enough fuel!
				self.status = SUCCESS
				return
			else
				self:DebugPrint("Current lightsource doesn't take fuel...")
				self.status = FAILED
				return
			end

		else
			-- There was no nearby firepit or campfire. Should I make one?
			local checkBuild = function(item)
				if self.inst.components.builder:IsBuildBuffered(item) then return true end
				return self.inst.components.builder:CanBuild(item)
			end

			local makeFire = nil
			-- Only make a firepit next to a science machine
			if checkBuild("firepit") then
				local scienceMachine = FindEntity(self.inst, 10, function(item) return item.prefab and item.prefab == "researchlab" end)
				if scienceMachine then
					makeFire = "firepit"
				end
			end

			-- No science machine for a firepit...how about a regular fire....
			if makeFire == nil and checkBuild("campfire") then
				makeFire = "campfire"
			end

			if makeFire ~= nil then
				self:DebugPrint("I should make a fire")
				-- Don't build one too close to burnable things.
				-- TODO: This should be a while loop until we find a valid spot
				local burnable = FindEntity(self.inst,3,function(thing) return thing ~= self.inst
															and not self.inst.components.inventory:FindItem(
																function(invItem) return thing == invItem end)
															end, {"burnable"})
				local pos = nil

				-- Lol, this will just build 4 away from the closest burnable thing. Could be by another
				-- burnable thing....
				if burnable then
					self:DebugPrint("Don't want to build campfire too close to " .. burnable.prefab)
					pos = self.inst.brain:GetPointNearThing(burnable,4)
				end

				-- local action = BufferedAction(self.inst,nil,ACTIONS.BUILD,nil,pos,makeFire,nil,1)
				-- -- Track this build action!
				-- action:AddFailAction(function() self:OnActionFail() end)
				-- action:AddSuccessAction(function() self:OnActionSucceed() end)

				-- -- Need to push this to the locomotor so we walk to the right position
				-- self.currentBuildAction = action
				-- self.inst.components.locomotor:PushAction(action, true);
				self.waitingForBuild = makeFire
				if CraftStructure(self.inst, makeFire, pos or self.inst:GetPosition(), self.inst:GetRotation()) then
					self.buildTime = GetTime()
					self.status = RUNNING
					return
				else
					self:DebugPrint("Could not craft " .. makeFire .. "!!!")
					self.waitingForBuild = nil
					self.status = FAILED
					-- Keep going....maybe something below can save us
				end

			else
				self:DebugPrint("Can't make a campfire or firepit I guess...")
			end

			-- There's no light and we can't make a campfire. How about a torch?
			self:DebugPrint("Do I have a torch?!?")
			local haveTorch = self.inst.components.inventory:FindItem(function(item) return item:HasTag("lighter") end)
			local currentEquippedItem = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)

			-- Already holding a torch...nothing else to do
			if currentEquippedItem and currentEquippedItem:HasTag("lighter") then
				self.status = SUCCESS
				return
			end

			if haveTorch == nil then
				self:DebugPrint("I don't have a torch! Can I make one????")
				-- Need to make one!
				if self.inst.components.builder:CanBuild("torch") then

					if CraftItem(self.inst, "torch") then
						self.waitingForBuild = "torch"
						self.buildTime = GetTime()
						self.status = RUNNING
					else
						self.status = FAILED
					end
					return
				end
			else
				self:DebugPrint("Sure do!")
				-- Equip the torch
				self.inst.components.inventory:Equip(haveTorch)
				self.status = SUCCESS
				return
			end


			-- -- We already have a torch. Equip it.
			-- local currentEquippedItem = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
			-- local currentItemIsNotTorch = currentEquippedItem == nil or not currentEquippedItem:HasTag("lighter")
			-- print(tostring(haveTorch))
			-- print(tostring(currentEquippedItem))
			-- if haveTorch and currentItemIsNotTorch then
			-- 	self.inst.components.inventory:Equip(haveTorch)
			-- 	self.status = SUCCESS
			-- 	return
			-- end

			-- If we're here...well, shit. Not sure what to do. We looked for nearby light...we
			-- tried to make light...we're screwed.

			-- Just run to the closest thing that is considered a light source
			local target = GetClosestInstWithTag("lightsource", self.inst, 50)
			if target then
				-- Get the safety distance according to the lightsource
				-- Only run towards it if the current light value where I'm standing is 0
				if self.inst.LightWatcher:GetLightValue() < TUNING.SANITY_LOW_LIGHT then
					self.inst.components.talker:Say("EMERGENCY PROTOCOL ACTIVATED!")
					self.currentLightSource = target
					self.runningTowardsLight = true
					self.inst.components.locomotor:RunInDirection(
						self.inst:GetAngleToPoint(Point(target.Transform:GetWorldPosition())))
					-- Run towards the light!
					self.status = RUNNING
					return
				end
			end

			-- I'm all out of ideas...
			self:DebugPrint("This is how i die")
			self.status = FAILED
			return

		end -- end if/else currentLightSource

    end -- end status == RUNNING
end



