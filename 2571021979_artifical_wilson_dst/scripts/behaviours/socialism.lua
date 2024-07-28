Socialism = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "Socialism")
   self.inst = inst

   self.sharable_things = {"log", "twigs", "cutgrass", "flint"}
   self.sharable_food = {FOODTYPE.GENERIC, FOODTYPE.MEAT, FOODTYPE.VEGGIE}
   self.needs_prefix = "Needs_"
   self.has_prefix =   "HasExtra_"

   self.last_trade_time = {}

   self.has_extra = {}
   self.needs_extra = {}
   for k,v in ipairs(self.sharable_things) do
      table.insert(self.has_extra, self.has_prefix .. v)
      table.insert(self.needs_extra, self.needs_prefix .. v)
   end

   for k,v in ipairs(self.sharable_food) do
      table.insert(self.has_extra, self.has_prefix .. v)
      table.insert(self.needs_extra, self.needs_prefix .. v)
   end

   -- Finds someone nearby that needs something.
   -- On trade fail, wont try again with the same guy for a while.
   local trade_delay = function(guy)
      local last_trade = GetTime() - (self.last_trade_time[guy] or 0)
      if last_trade <= 20 then
         --DebugPrint(self.inst, "Not trading with " .. tostring(guy) .. " again for a bit longer...")
         return false
      end
      return true
   end
   self.find_taker = function()
      return FindEntity(self.inst, 15, trade_delay, {"ArtificalWilson", "trader"}, {"ghost", "INLIMBO", "NOCLICK"}, self.needs_extra)
   end

   -- Finds someone nearby that has something
   self.find_giver = function()
      return FindEntity(self.inst, 15, trade_delay, {"ArtificalWilson", "trader"}, {"ghost", "INLIMBO", "NOCLICK"}, self.has_extra)
   end

   self.onitemget = function(inst, data)
      -- data: {item, slot, src_pos}

      DebugPrint(self.inst, "onitemget called")
      -- This should only be from us...but doesn't hurt to check I guess
      if inst ~= self.inst then return end

      -- Uhh, did we or did we not get something?
      if data.item == nil then return end

      -- Every time we pick up something edible, update our food situation
      if data.item.components.edible then
         DebugPrint(self.inst, "Got something edible... " .. tostring(data.item))
         self:CheckFood(data.item.components.edible.foodtype, 2, 10)
      else
         DebugPrint(self.inst, "Got something not edible... " .. tostring(data.item))
         self:CheckItem(data.item.prefab, 4, 10)
      end

   end

   self:OnStart()
end)

function Socialism:OnStart()
   DebugPrint(self.inst, "Socialism - on start called")
   self.inst:ListenForEvent("itemget", self.onitemget)
   self.inst:ListenForEvent("itemlose", self.onitemget)

   self.tradefailed = function(inst, data)
		local theAction = data.action or "[Unknown]"
		local theReason = data.reason or "[Unknown]"
		DebugPrint(self.inst, "Socialisim: Action: " .. theAction:__tostring() .. " failed. Reason: " .. tostring(theReason))
      self.pendingstatus = FAILED
   end

   self.inst:ListenForEvent("actionfailed", self.tradefailed)

   -- Check our current situation with items
   for k,v in ipairs(self.sharable_things) do
      self:CheckItem(v, 4, 10)
   end

   for k,v in ipairs(self.sharable_food) do
      self:CheckFood(v, 2, 10)
   end
end

function Socialism:OnStop()
   DebugPrint(self.inst, "Socialism - on stop called")
   self.inst:RemoveEventCallback("itemlose", self.onitemget)
   self.inst:RemoveEventCallback("itemget", self.onitemget)
end

-- Enables/disables flags based on the type.
-- Type should be an exact prefab
function Socialism:CheckItem(type, min, max)

   if not table.contains(self.sharable_things, type) then return end

   local min_need = min or 1
   local min_give = max or 10
   -- Do we even have the thing or not?
   -- The amount passed in is just the max that will be returned.
   -- It will return less than or equal to that number.
   local _, amount = self.inst.components.inventory:Has(type,20)


   local need = self.needs_prefix .. type
   local have = self.has_prefix .. type

   -- If we don't have any of this, add it to our needs list
   if amount < min_need then
      DebugPrint(self.inst, "I don't have enough " .. tostring(type))
      DebugPrint(self.inst, "Adding tag " .. tostring(need))
      self.inst:AddTag(need)
      self.inst:RemoveTag(have)
      return
   end

   -- We have enough of this, so make sure we aren't asking for more...
   self.inst:RemoveTag(need)

   -- If we have excess, let everyone know
   if amount > min_give then
      DebugPrint(self.inst, "I have more than enough " .. tostring(type))
      self.inst:AddTag(have)
   end

end

-- Only knows meat or not meat...
function Socialism:CheckFood(type, min, max)
   if not type or not table.contains(self.sharable_food, type) then return end

   local min_need = min or 3
   local min_give = max or 10

   local need = self.needs_prefix .. type
   local have = self.has_prefix .. type

   local food = self.inst.components.inventory:FindItems(function(item) return item.components.edible and item.components.edible.foodtype == type end) or {}

   -- If we wont ever eat this kind of food and have any, mark it available
   if #food > 0 then
      DebugPrint(self.inst, "Food at index 0 " .. tostring(food[1]))
      if not self.inst.components.eater:PrefersToEat(food[1]) then
         DebugPrint(self.inst, "We have food we'll never eat...pawn it off")
         self.inst:AddTag(have)
         self.inst:RemoveTag(need)
         return
      else
         if #food < min_need then
            self.inst:AddTag(need)
            self.inst:RemoveTag(have)
         elseif #food > min_give then
            self.inst:AddTag(have)
            self.inst:RemoveTag(need)
         end
      end
   end

   -- If we have none of this, only request it if it's something we would ever eat...
   if table.contains(self.inst.components.eater.preferseating.types, type) then
      DebugPrint(self.inst, "We don't have any food of type " .. tostring(type) .. " but we prefer to eat it!")
      self.inst:AddTag(need)
      self.inst:RemoveTag(have)
   end
end

-- Given a tag, removes the prefix.
-- Returns a boolean: has, and the extracted thing
function Socialism:StripPrefix(tag)

   local strip, count = string.gsub(tag, self.needs_prefix, "")
   if count > 0 then
      return false, strip
   end

   strip, count = string.gsub(tag, self.has_prefix, "")
   if count > 0 then
      return true, strip
   end

   return nil, nil
   -- if (tag:sub(0, #self.needs_prefix) == self.needs_prefix) then
   --    return false, tag:sub(#self.needs_prefix+1)
   -- elseif (tag:sub(0, #self.has_prefix) == self.has_prefix) then
   --    return true, tag:sub(#self.has_prefix+1)
   -- end

   -- return nil, nil
end

-- Returns true if an action was successful
function Socialism:GiveItemByNeed(need_tag, other_player)
   DebugPrint(self.inst, "Giving a thing (" .. tostring(need_tag) .. ") to " .. tostring(other_player))
   --local thing = (need_tag:sub(0, #self.needs_prefix) == self.needs_prefix) and need_tag:sub(#self.needs_prefix+1) or need_tag
   local thing = string.gsub(need_tag, self.has_prefix, "")

   local thing_to_give = nil
   if table.contains(self.sharable_food, thing) then
      thing_to_give = self.inst.components.invetory:FindItem(function(item)
         if not item.components.edible then return false end
         if item.components.edible.foodtype ~= type then return false end

         return true
      end)
      if thing_to_give == nil then
         DebugPrint(self.inst, "Couldn't find food in inventory matching " .. tostring(thing))
         self.inst:RemoveTag(self.has_prefix .. thing)
         return false
      end
   else
      thing_to_give = self.inst.components.inventory:FindItem(function(item) return item.prefab == thing end)
      if thing_to_give == nil then
         DebugPrint(self.inst, "Couldn't find item in our inventory matching " .. tostring(thing))
         -- We must have this thing set....so unset it
         self.inst:RemoveTag(self.has_prefix .. thing)
         return false
      end
   end

   -- Failsafe...what was it?
   if thing_to_give == nil then
      DebugPrint(self.inst, "Uhh, not sure what this is - " .. tostring(thing))
      return false
   end


   -- Create the give command
   local giveaction = BufferedAction(self.inst,other_player,ACTIONS.GIVETOPLAYER,thing_to_give)
   self.action = giveaction
   giveaction:AddFailAction(function(inst, reason)
      DebugPrint(self.inst, "Trade Action Failed")
      self.pendingstatus = FAILED
   end)
   giveaction:AddSuccessAction(function()
      DebugPrint(self.inst, "Trade Action Success")
      self.pendingstatus = SUCCESS
      self.last_trade_time[other_player] = 0
      self:CheckItem(thing_to_give.prefab)
      if thing_to_give.components.edible then
         self:CheckFood(thing_to_give.components.edible.foodtype)
      end
   end)
   self.inst:PushBufferedAction(giveaction)
   self.last_trade_time[other_player] = GetTime()
   DebugPrint(self.inst, "Built trade action: " .. tostring(self.action))
   return true
end

-- Share food/grass/twigs/logs with other bots that have the tags.
-- Only if we have enough...
function Socialism:Visit()

   -- If raining: wear a straw hat
   -- else, wear a flower hat.
   if self.status == READY then
      -- We don't share here
      if IsPvPEnabled() then
         self.status = FAILED
         return
      end

      self.action = nil
      self.pendingstatus = nil

      -- We only give, never ask.
      -- TODO: Maybe we stop moving to receive?
      local friend_in_need = self.find_taker()

      -- If no one is even around, nothing to consider.
      if friend_in_need == nil then
         self.status = FAILED
         return
      end

      -- There is someone around. Can we meet their needs?
      for k,v in ipairs(self.has_extra) do
         local _, thing = self:StripPrefix(v)
         if thing and friend_in_need:HasTag(self.needs_prefix .. thing) then
            if self:GiveItemByNeed(v, friend_in_need) then
               self.status = RUNNING
               return
            else
               -- Couldn't give them the thing?
               self.status = FAILED
               return
            end
         end
      end

      -- Must not have been anything they need that we have extra...
      self.status = FAILED
      return

   elseif self.status == RUNNING then
		if self.pendingstatus then
			self.status = self.pendingstatus
         return
		elseif not self.action:IsValid() then
			self.status = FAILED
		end

      if self.action ~= nil then
         --DebugPrint(self.inst, "Waiting for trade to finish...")
         local wait_time = GetTime() - self.last_trade_time[self.action.target]
         if wait_time > 2 then
            DebugPrint(self.inst, "Taking too long to trade - abort")
            self.status = FAILED
            return
         end
         return
      end
   end

   -- If we ever get here, must not be doing anything. Don't get stuck!
   self.status = FAILED
end




