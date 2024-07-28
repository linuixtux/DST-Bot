require "brains/ai_inventory_helper"

ManageInventory = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "ManageInventory")
   self.inst = inst
end)

-- If we ever get blueprints...learn it right away
function ManageInventory:CheckForBlueprints()
   local blueprints = self.inst.components.inventory:FindItems(function(item) return item.components.teacher ~= nil end)

   if blueprints then
      for k,v in pairs(blueprints) do
         -- Skipping the push action bs...let's just learn the damn thing
         v.components.teacher:Teach(self.inst)
      end
   end
end

function ManageInventory:CheckForMurder()
   local murderable = self.inst.components.inventory:FindItems(
      function(item)
         if item.components and item.components.health then
            return true
         elseif item.components and item.components.murderable then
            return true
         end

         return false
   end)

   for k,v in pairs(murderable) do
      -- Don't murder spiders if we are a spider
      local murder = true
      if v:HasTag("spider") and self.inst:HasTag("spiderwhisperer") then
         murder = false
      end


      if murder == true then
         local action = BufferedAction(self.inst, v, ACTIONS.MURDER)
         self.pendingstatus = nil
         self.action = action
         self.inst.components.locomotor:PushAction(action)
         self.status = RUNNING
         return
      end

   end
end

-- Plant all pinecones we pick up.
function ManageInventory:PlantTree()
   local haveseeds = self.inst.components.inventory:HasItemWithTag("deployedplant", 1)
   if not haveseeds then return end

   -- We have some number of seeds. Plant them.
   -- TODO: Keep birtchnuts for cooking?


end

-- Find nearby chests. If we find one and have something we want to store,
-- or the chest has something we want, then push the action and return true.
function ManageInventory:ChestManagement()
   -- Test - try to store refined resources?
   local have_twigs, num =  self.inst.components.inventory:Has("twigs", 10)
   if have_twigs and num >= 10 then
      return
   end
   local quantity = 10 - num
   local chest, items = FindChestWithItems(self.inst, 10, "twigs")
   if not chest then return false end

   if #items == 0 then return false end

   local success = function()
      DebugPrint(self.inst, "Chest action returned success!")
      self.pendingstatus = SUCCESS
      self.action = nil
   end

   local fail = function()
      DebugPrint(self.inst, "Chest action failed!")
      self.pendingstatus = FAILED
      self.action = nil
   end

   local getAction = BuildChestTransferAction(self.inst, chest, false, items, quantity, success, fail)
   if getAction == nil then
      return false
   end

   self.action = getAction
   self.inst.components.locomotor:PushAction(getAction, true)
   return true
end

-- Keep less important things in the backpack
function ManageInventory:BackpackManagement()

   -- If we don't have a backpack or are not standing near a chest...nothing to do.
   -- Not sure if basemanager should handle the chest part as there are probably
   -- specific places to put things. Just checking backpack here.
   -- if not IsWearingBackpack(self.inst) then
   --    self.status = FAILED
   --    return
   -- end

   -- If we aren't wearing one, see if there is one nearby. If not, maybe we should make one.
   if not IsWearingBackpack(self.inst) then
      local backpack = FindEntity(self.inst, 70, function(item) return IsItemBackpack(item) end)
      if backpack then
         -- Don't make one if there is one nearby.
         self.status = FAILED
         return
      else
         -- -- Craft one if we know how
         -- if self.inst.components.builder:KnowsRecipe("backpack") and self.inst.components.builder:CanBuild("backpack") and not self.inst.waitingForBuild then
         -- 	self.inst.waitingForBuild = "backpack"
         -- 	self.inst.brain:SetSomethingToBuild("backpack",nil,
         -- 		function() self.inst.waitingForBuild = nil end,function() self.inst.waitingForBuild = nil end)
         -- end
         BuildIfAble(self.inst, "backpack")
      end
      self.status = FAILED
      return
   end

   -- Can start getting silk and whatnot.
   -- Only do this once when we first equip a backpack. From now on, we will be able to pick up these things.
   if self.backpack_check == nil then
      self.backpack_check = true
      self.inst.components.prioritizer:RemoveFromIgnoreList("silk")
      --self.inst.components.prioritizer:RemoveFromIgnoreList("nightmarefuel")
      --self.inst.components.prioritizer:RemoveFromIgnoreList("livinglog")
   end

   local backpack = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)

   if not backpack then return end

   -- We're wearing a backpack. Put stuff in there!
   -- Loop through our inventory and put anything we can in there.
   local inv = self.inst.components.inventory
   for k=1,inv:GetNumSlots() do
      local item = inv:GetItemInSlot(k)
      if item then
         if ShouldGoInBackpack(item) then
            -- Just because it should go doesn't mean there is room. Find a slot.
            -- This fcn will return false if not successful. Should maybe
            -- do something with that return value...
            TransferItemTo(item,self.inst,backpack,true)
         end
      end
   end

   -- Loop through the backpack and move things that shouldn't go there to our inventory
   local bpInv = backpack.components.container
   for k=1, bpInv:GetNumSlots() do
      local item = bpInv:GetItemInSlot(k)
      if item then
         if not ShouldGoInBackpack(item) then
            TransferItemTo(item,backpack,self.inst,true)
            self.status = SUCCESS
            return
         end
      end
   end

end

-- Sometimes we get full of useless stuff.
-- Do something about it
function ManageInventory:FreeUpSpace()
   if not self.inst.components.inventory then
      return
   end

   if not self.inst.components.inventory:IsTotallyFull() then
      return
   end

   print("Free up space!")

   if self.inst.components.inventory:HasItemWithTag("show_spoiled", 1) then
      self.inst.components.talker:Say("YEET")
      self.inst.components.inventory:DropEverythingWithTag("show_spoiled")
   end

   self.inst.components.inventory:DropEverythingWithTag("vasedecoration")

   -- We're completely full. Lets eat some food first to make some space
   -- Just call this directly
   --self.inst.components.eater:Eat(obj)

   local allFoodInInventory = self.inst.components.inventory:FindItems(function(item) return
                        self.inst.components.eater:PrefersToEat(item) and
                        item.components.edible:GetHunger(self.inst) >= 0 and
                        item.components.edible:GetHealth(self.inst) >= 0 and
                        item.components.edible:GetSanity(self.inst) >= -TUNING.SANITY_TINY
                        -- and ((item.components.stackable and item.components.stackable:StackSize() == 1) or (not item.components.stackable))
                        end)

   print("All food in inventory: " .. tostring(allFoodInInventory) )

   --local healthMissing = self.inst.components.health:GetMaxWithPenalty() - self.inst.components.health.currenthealth
   local healthMissing = GetHealthMax(self.inst) - self.inst.components.health.currenthealth
   local hungerMissing = self.inst.components.hunger.max - self.inst.components.hunger.current
   local sanityMissing = self.inst.components.sanity.max - self.inst.components.sanity.current


   --local haveFullStack,num = self.inst.components.inventory:Has(
	--							item.prefab, item.components.stackable and item.components.stackable.maxsize or 1)

   -- Eat things in the smallest stack first.
   local sortByStacksize = function(it1, it2)
      local s1 = it1.components.stackable and it1.components.stackable:StackSize() or 1
      local s2 = it2.components.stackable and it2.components.stackable:StackSize() or 1
      return s1 < s2
   end
   table.sort(allFoodInInventory, sortByStacksize)
   -- Eat one of them!
   for k,v in pairs(allFoodInInventory) do
      print(v.prefab)
      local h = v.components.edible:GetHunger(self.inst)
      local s = v.components.edible:GetSanity(self.inst)
      local he = v.components.edible:GetHealth(self.inst)

      -- Eat something that will give us value first. Otherwise...just eat
      -- the lowest utility one
      if h >= s and h >= he and h <= hungerMissing then
         -- These actions bypass the animation...bah
         self.inst.components.eater:Eat(v)
         return
      elseif s >= h and s >= he and s <= sanityMissing then
         self.inst.components.eater:Eat(v)
         return
      elseif he >=h and he >= s and he <= healthMissing then
         self.inst.components.eater:Eat(v)
         return
      end

   end

   -- We didn't eat anything...just eat the first one
   if next(allFoodInInventory) ~= nil then
      local i,v = next(allFoodInInventory)
      -- Only eat single item things.
      local stacksize = v.components.stackable and v.components.stackable:StackSize() or 1
      if stacksize <= 4 then
         self.inst.components.eater:Eat(v)
      end
      return
   end

   -- We have no single foods. Drop something useles?


end

-- If there's a chest nearby, store stuff.
-- ....should make sure this is our own chest next to a science machine lol
-- function ManageInventory:ChestManagement()

--    local scienceMachine = FindEntity(self.inst, 10, function(item) return item.prefab and item.prefab == "researchlab" end)
--    if not scienceMachine then return end

--    local chest = FindEntity(self.inst, 10, function(item) return item.prefab and item.prefab == "treasurechest" end)
--    if not chest then return end
-- end

function ManageInventory:Visit()

   if self.status == READY then
      self.pendingstatus = nil
      self.action = nil

      -- Any one of these can return or leave the node
      -- This is kind of a mini priority
      self:CheckForBlueprints()
      --self:CheckForMurder()
      self:BackpackManagement()
      self:FreeUpSpace()

      if self:ChestManagement() then
         self.status = RUNNING
         return
      end

      self.status = FAILED
   elseif self.status == RUNNING then
      -- Should never get to this state currently.
      if self.pendingstatus then
         self.status = self.pendingstatus
         return
      elseif self.action and not self.action:IsValid() then
         self.status = FAILED
         return
      end
   end

end
