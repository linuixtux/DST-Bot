ManageSummons = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "ManageSummons")
   self.inst = inst

   self.currentHat = nil

   self.onWorkDone = function(inst, data)
      self.workDone = SUCCESS
   end


   -- This whole thing is very wendy specific....but whatever. make it generic
   self.summonitem = function(item)
      if not item.components.summoningitem then return false end
      return true
   end

   -- Can be set by other nodes. If this doesn't match the current ghost
   -- personality, will invoke the change
   self.make_aggressive = false

end)

function ManageSummons:OnStop()

end

function ManageSummons:SummonFailed()
   self.pendingstatus = FAILED
end

function ManageSummons:SummonSucceed()
   self.pendingstatus = SUCCESS
end

function ManageSummons:Summon(item)
   local action = BufferedAction(self.inst,nil,ACTIONS.CASTSUMMON,item)
   self.action = action
   self.pendingstatus = nil
   action:AddFailAction(function() self:SummonFailed() end)
   action:AddSuccessAction(function() self:SummonSucceed() end)
   self.inst:PushBufferedAction(action)
   self.status = RUNNING
end

function ManageSummons:ChangeAggression(item)
   local action = BufferedAction(self.inst,self.inst,ACTIONS.COMMUNEWITHSUMMONED,item)
   self.action = action
   self.pendingstatus = nil
   action:AddFailAction(function() self:SummonFailed() end)
   action:AddSuccessAction(function() self:SummonSucceed() end)
   self.inst:PushBufferedAction(action)
   self.status = RUNNING
end

function ManageSummons:GetSummonItem()
   return self.inst.components.inventory:FindItem(self.summonitem)
end

-- Wendy can make the ghost aggressive or passive...
function ManageSummons:MakeAggressve(item)
   self.make_aggressive = true
end

function ManageSummons:MakePassive(item)
   self.make_aggressive = false
end




-- This node doesn't make clothes. Should just add them to the priority list...
-- This just equips whatever we have that is the best.
function ManageSummons:Visit()

   -- If raining: wear a straw hat
   -- else, wear a flower hat.
   if self.status == READY then

      -- See if we have any summon things in inventory

      local summon_item = self:GetSummonItem()

      -- No summon item, nothing to do
      if not summon_item then
         self.status = FAILED
         return
      end

      -- See if we need to change the aggressiveness
      if self.inst:HasTag("ghostfriend_summoned") then
         if self.make_aggressive == true and not self.inst:HasTag("has_aggressive_follower") then
            self:ChangeAggression(summon_item)
            return
         elseif self.make_aggressive == false and self.inst:HasTag("has_aggressive_follower") then
            self:ChangeAggression(summon_item)
            return
         else
            -- Already have a ghost and it's in the right state....nothing to do.
            self.status = FAILED
            return
         end
      end

      -- Can summon, and no ghost, try to summon
      self:Summon(summon_item)


   elseif self.status == RUNNING then
		if self.pendingstatus then
			self.status = self.pendingstatus
		elseif not self.action:IsValid() then
			self.status = FAILED
		end
   end
end




