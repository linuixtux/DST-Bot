ManageClothes = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "ManageClothes")
   self.inst = inst

   self.currentHat = nil

   self.onWorkDone = function(inst, data)
      self.workDone = SUCCESS
   end

   self.bestHats = {
      "eyebrellahat",
      "tophat"
   }

   self.inst:ListenForEvent("workfinished", self.onWorkDone)
end)

function ManageClothes:OnStop()
   self.inst:RemoveEventCallback("workfinished", self.onWorkDone)
end

function ManageClothes:BuildSucceed()
  self.pendingBuildStatus = SUCCESS
end
function ManageClothes:BuildFailed()
  self.pendingBuildStatus = FAILED
end

-- Looks in inventory to see if already have right clothing item to equip.
function ManageClothes:FindAndEquipClothes(clothes)
   local equiped = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
   if equiped and equiped.prefab == clothes then
      return true, equiped
   else
      local clothing = self.inst.components.inventory:FindItem(function(item) return item.prefab == clothes end)
      if clothing then
         print("equipping " .. clothes)
         self.inst.components.inventory:Equip(clothing)
         return true, clothing
      end
   end

   return false, nil
end

-- Depending on what we have in inventory, figures out the best things to wear.
-- Should depend on temperature, combat, sanity, etc.

function ManageClothes:WhatToWear()
   local headwear = nil
   local bodywear = nil
   local handwear = nil

   local scenario = nil
   if TheWorld.state.temperature <= 15 then
      scenario = "temperature_low"
   elseif TheWorld.state.temperature >= 50 then
      scenario = "temperature_high"
   elseif TheWorld.state.israining then
      scenario = "wetness"
   else
      -- Default to being the most sane?
      scenario = "sanity"
   end

   -- Headwear is fully dynamic
   headwear = GetBestEquipmentFor(self.inst, scenario, EQUIPSLOTS.HEAD)

   -- Bodywear depends on if we have a backpack on. Don't ditch that.
   local currentBody = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
   if currentBody and currentBody:HasTag("backpack") then
      bodywear = currentBody
   else
      bodywear = GetBestEquipmentFor(self.inst, scenario, EQUIPSLOTS.BODY)
   end

   -- TODO: Worry about hand stuff later
   --handwear = GetBestEquipmentFor(self.inst, scenario, EQUIPSLOTS.HANDS)

   -- next returns the next element in a table (in this case, first)
   return headwear, bodywear, nil
end



-- This node doesn't make clothes. Should just add them to the priority list...
-- This just equips whatever we have that is the best.
function ManageClothes:Visit()

   -- If raining: wear a straw hat
   -- else, wear a flower hat.
   if self.status == READY then

      -- Given what we have, what is the best thing to wear?
      local head, body, hand = self:WhatToWear()

      if head ~= nil then
         local isequipped,_ = self:FindAndEquipClothes(head.prefab)
         if isequipped then
            self.status = FAILED
         end
      end

      if body ~= nil then
         local isequipped,_ = self:FindAndEquipClothes(body.prefab)
         if isequipped then
            self.status = FAILED
         end
      end

      if hand ~= nil then
         local isequipped,_ = self:FindAndEquipClothes(hand.prefab)
         if isequipped then
            self.status = FAILED
         end
      end

      -- TODO: The original code just made 2 different hats depending on the weather.
      --       Sooo, if we don't have any hatwear, just keep doing that.
      if head ~= nil then
         self.status = FAILED
         return
      end

      local equipped = false
      local hat = nil

      -- For walter, wear this hat almost always...
      if self.inst:HasTag("pinetreepioneer") then
         hat = "walterhat"
      end

      if TheWorld.state.israining and not hat then
         hat = "strawhat"
      elseif not hat then
         hat = "tophat"
      end

      if not hat then 
         self.status = FAILED
         return
      end

      self.currentHat = hat

      -- The right hat is already equipped...nothing to do.
      equipped, hat = self:FindAndEquipClothes(self.currentHat)
      if equipped then
         --print("Right hat already equipped")
         self.status = FAILED
         return
      end

      -- Not equipped....can I make the right hat?
      -- Make sure we have room for it!
      -- TODO: Drop something else? Or just wait?
      if self.inst.components.inventory:IsTotallyFull() then
         --print("Cant make hat - inventory full")
         self.status = FAILED
         return
      end

      -- See if we can even make the hat we want
      if self.currentHat ~= nil and self.inst.components.builder and self.inst.components.builder:KnowsRecipe(self.currentHat) and self.inst.components.builder:CanBuild(self.currentHat) then
         print("I can build a hat!")
         local buildAction = BufferedAction(self.inst,self.inst,ACTIONS.BUILD,nil,nil,self.currentHat,nil)
         self.action = buildAction
         self.pendingBuildStatus = nil
         buildAction:AddFailAction(function() self:BuildFailed() end)
         buildAction:AddSuccessAction(function() self:BuildSucceed() end)
         self.inst:PushBufferedAction(buildAction)
         self.status = RUNNING
      else
         self.status = FAILED
         return
      end

   elseif self.status == RUNNING then
      -- Wait here for the build to finish
      if self.action.action == ACTIONS.BUILD then
         if self.pendingBuildStatus then
            if self.pendingBuildStatus == FAILED then
               self.status = FAILED
               return
            else
               -- Tool has been built. Equip it and queue the action
               local equiped, hat = self:FindAndEquipClothes(self.currentHat)
               if equiped then
                  self.currentHat = nil
                  self.status = SUCCESS
                  return
               end
            end
         end

         -- Still waiting on that hat
         self.status = RUNNING
         return
      end
   end
end




