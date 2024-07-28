Maxwell = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "Maxwell")
   self.inst = inst

   -- Shadow friends have the tag "shadowminion"

   self.myminionsfn = function(guy)
      if not guy:HasTag("shadowminion") then return false end

      -- Only find my own minions
      return guy.components.follower.leader == self.inst
   end

   -- Keep track of what state we're in
   -- States:
   --   "ready"
   --   "dropcodex"
   --   "trysummon"
   --   "cleanup"
   self.currentstate = "ready"
   self.waitingForBuild = nil

   self.friendToMake = "shadowlumber_builder"

   self.madefriend = function(inst, data)
      if inst ~= self.inst then return end
      if self.waitingForBuild ~= nil then
         if data.item.prefab == self.waitingForBuild then
            self:Debug("We've made a friend! " .. tostring(data.item))
            self.waitingForBuild = nil
            self.pendingstatus = SUCCESS
         else
            self:Debug("We've made....something else?")
            self.waitingForBuild = nil
            self.pendingstatus = FAILED
         end
      end
   end

   self.inst:ListenForEvent("builditem", self.madefriend)
end)

function Maxwell:OnStop()

end

function Maxwell:OnFail()
   self.pendingstatus = FAILED
end

function Maxwell:OnSucceed()
   self.pendingstatus = SUCCESS
end

function Maxwell:GetNearbyFriend()
   return FindEntity(self.inst, 30, self.myminionsfn,  {"shadowminion"})
end

-- Does an action. ON success, will transition to the successState.
-- On fail, transitions to the failState
function Maxwell:DoThisAction(action, successState, failState)
	action:AddFailAction(function()
         print("Failed state - setting next state to " .. failState)
         self.currentstate = failState
         self:OnFail()
   end)
	action:AddSuccessAction(function()
         print("Success state - setting next state to " .. successState)
         self.currentstate = successState
         self:OnSucceed()
   end)

	self.action = action
	self.pendingstatus = nil
	self.inst:PushBufferedAction(action)
end

function Maxwell:GetCodexInInventory()
   return self.inst.components.inventory:FindItem(function(item) return item:HasTag("shadowmagic") end)
end

function Maxwell:DropCodex()
   local codex = self:GetCodexInInventory()
   if not codex then
      self.currentstate = "cleanup"
      self.pendingstatus = FAILED
      self.action = nil
      return false
   end

   self:DoThisAction(BufferedAction(self.inst, self.inst, ACTIONS.DROP, codex), "trysummon", "cleanup")
   return true
end

function Maxwell:Debug(string)
   DebugPrint(self.inst, string)
end

function Maxwell:PickupCodex()
   -- Don't pick one up if already have one
   if self:GetCodexInInventory() ~= nil then return false end
   local findcodexfn = function(item)
      -- Only find ones on the ground
      if item.components.inventoryitem:IsHeld() then return false end

      return item.prefab == "waxwelljournal"
   end
   local codex = FindEntity(self.inst, 20, findcodexfn, {"shadowmagic"})


   if codex == nil then
      self:Debug("Couldn't find a codex on the ground...")
      return false
   end

   self:DoThisAction(BufferedAction(self.inst, self.inst, ACTIONS.PICKUP, codex), "ready", "ready")
   return true
end


-- First, checks if we have the right materials.
-- Then, will drop the codex so the crafting tab is available.
-- Then will craft the thing.
-- Finally, pick up the codex.

function Maxwell:CanMakeFriend(type)
   -- If we don't have a codex, can't make it
   if not self.inst.components.inventory:HasItemWithTag("shadowmagic", 1) then
      self:Debug("Can't make another friend ..... already have a friend!")
      return false
   end

   -- Returns true if we have all necessary ingredients.
   return self.inst.components.builder:CanBuild(type)
end

function Maxwell:MakeFriend(type)
   if CraftItem(self.inst, type) then
      self.waitingForBuild = type
      self.status = RUNNING
   else
      self.status = FAILED
   end
end


function Maxwell:Visit()

   -- Maxwell can summon a choppy friend, a miney friend, a diggy friend, and a fighty friend.
   -- Each one costs a certain amount of max sanity to cast....
   -- Can have 4 harvesters
   -- or 1 duelist and 2 harvesters
   -- or 2 duelists and 1 harvester

   -- For now, lets try 1 choppy friend
   if self.status == READY then
      print("Maxwell - READY")
      self.currentstate = "ready"
      self.pendingstatus = nil
      self.action = nil

      local friend = self:GetNearbyFriend()

      -- TODO: Can only manage one friend for now...
      if friend ~= nil then
         self:Debug("Already have a friend!")
         print("Already have a friend")
         self.status = FAILED
         return
      end

      -- No friend, can we make one?
      -- TODO: Testing with a hard coded shadow lumberjack
      if self:CanMakeFriend(self.friendToMake) then
         print("we can make a friend!")
         if self:DropCodex() then
            self.currentstate = "dropcodex"
            self.status = RUNNING
         else
            self.status = FAILED
            return
         end
      else
         self.status = FAILED
         return
      end


   elseif self.status == RUNNING then
      print("Maxwell - running")

      -- Check if the last action we were trying is complete.
      -- If there is no pending status, make sure the current action
      -- is still valid.
		if self.pendingstatus ~= nil then
			self.status = self.pendingstatus
		elseif self.action ~= nil and not self.action:IsValid() then
         self:Debug("Maxwell - No pending status and no valid action...")
         self.action = nil
			self.status = FAILED
         return
		end

      -- If we get here and pendingstatus == nil, then we're still waiting on
      -- an action to complete. Nothing to do
      if not self.pendingstatus and self.action ~= nil then
         self:Debug("Waiting for " .. tostring(self.action))
         return
      end

      if not self.pendingstatus and self.waitingForBuild ~= nil then
         self:Debug("Waiting for friend to be done")
         return
      end

      -- If here, there's something to do. Try to do it.
      self.pendingstatus = nil
      self.action = nil

      -- Nothing going on. Do something
      -- if self.currentstate == "ready" then
      --    -- Try to drop our codex.
      --    -- DropCodex will transition us to the next state automatically.
      --    if not self:DropCodex() then
      --       -- Hmm, couldn't drop a codex....wrong state?
      --       self:Debug("Couldn't drop codex!!!")
      --       self.status = FAILED
      --       return
      --    else
      --       -- Already queued the drop action, just wait for it.
      --       return
      --    end
      -- end


      if self.currentstate == "trysummon" then
         print("Now try to make a friend")
         -- Queues the build. Waits for the builditem callback to fire.
         -- if CraftItem(self.inst, self.friendToMake ) then
         --    print("Success!")
         --    self.currentstate = "cleanup"
         --    self.waitingForBuild = self.friendToMake
         --    self.status = RUNNING
         --    return
         -- else
         --    -- Don't quit this node just yet....pick the codex back up first
         --    self.currentstate = "cleanup"
         --    self.status = RUNNING
         --    return
         -- end
         --local buildAction = BufferedAction(self.inst,self.inst,ACTIONS.BUILD,nil,nil,self.friendToMake)
      end

      -- Only thing we care about is picking up a codex on the ground
      if self.currentstate == "cleanup" then
         print("Doing cleanup state")
         if not self:PickupCodex() then
            self.status = FAILED
            return
         else
            -- pickup queued....wait for it to happen.
            self.status = RUNNING
            return
         end
      end


      -- Shouldn't get here. Means we are out of sync with the states probably.
      -- Abandon ship!
      self:Debug("Maxwell - got to end of running loop?")
      self.status = FAILED
      return

   end
end




