FindAndActivate = Class(BehaviourNode, function(self, inst, searchDistance, thingToActivate)
    BehaviourNode._ctor(self, "FindAndActivate")
    self.inst = inst
	self.distance = searchDistance
	self.thingToActivate = thingToActivate
	self.searchfn = function(thing) return thing.prefab == thingToActivate end
	self.target = nil
	self.action = ACTIONS.ACTIVATE

	if self.thingToActivate == "resurrectionstone" then
		if IsDST() then
			self.searchfn = function(stone) 
				if stone.prefab ~= "resurrectionstone" then return false end
				DebugPrint(self.inst, "Checking to see if we've used this touchstone")
				local used = (self.inst.components.touchstonetracker and not 
								self.inst.components.touchstonetracker:IsUsed(stone))
								or true
				if used then
					DebugPrint(self.inst, "We've apparently used this touchstone before...")
				end
			end
			self.action = ACTIONS.HAUNT
		else
			self.searchfn = function(item) 
								return item.prefab == self.thingToActivate and
								item.components.activatable and 
								item.components.activateable.inactive 
							end
			self.action = ACTIONS.ACTIVATE
		end
	end

	-- Hard coded? 
	if self.thingToActivate == "wormhole" then
		self.searchfn = function(item) return item.prefab == self.thingToActivate end
		self.action = ACTIONS.JUMPIN
	end
end)

-- Returned from the actions
function FindAndActivate:OnFail()
	print("Failed to activate thingy")
    self.pendingstatus = FAILED
end
function FindAndActivate:OnSucceed()
    self.pendingstatus = SUCCESS
end

function FindThingToActivate()

end

function FindAndActivate:Visit()

    if self.status == READY then
		-- Find the 'thingToActivate' within the search distance supplied.
		local target = FindEntity(self.inst, self.distance, self.searchfn)

		if target then
			print("Found thing to actiavte: " .. target.prefab)
			local action = BufferedAction(self.inst,target,self.action)
			action:AddFailAction(function() self:OnFail() end)
			action:AddSuccessAction(function() self:OnSucceed() end)
			self.action = action
			self.pendingstatus = nil
			self.inst.components.locomotor:PushAction(action, true)
			self.status = RUNNING
			self.inst.brain:ResetSearchDistance()
			return
		end

		DebugPrint(self.inst, "...no touchstone around")
		
		self.status = FAILED
		
    elseif self.status == RUNNING then
		if self.pendingstatus then
			self.status = self.pendingstatus
		elseif not self.action:IsValid() then
			self.status = FAILED
		end
    end
end



