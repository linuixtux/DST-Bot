-- local function IsDST()
--    return TheSim:GetGameID() == "DST"
-- end

-- function GetHealthMax(inst)
--    if IsDST() then
--       return inst.components.health:GetMaxWithPenalty()
--    else
--       return inst.components.health:GetMaxHealth()
--    end
-- end

function IsItemBackpack(item)
   if not item then return false end
   -- Have to use the not operator to cast to true/false.
   --return item.components.equippable ~= nil and item.components.container ~= nil
   return item:HasTag("backpack")
end

function IsWearingBackpack(inst)
   if not inst.components.inventory then return false end
   local bodyslot = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
   return IsItemBackpack(bodyslot)
end

-- Finds the best equipment in inventory (matching the scenario).
-- Returns equipment (entity), is_equipped (bool).
-- Current scenarios
--    "temperature_cold"
--    "temperature_hot"
--    "wetness"
--    "sanity"
--    "armor"

-- attacker is used for armor. If not nil, will find armor best suited for the attacker (i.e. bees vs beehat, etc)
function GetBestEquipmentFor(inst, scenario, slot, attacker)

   -- Returns true if the item can be equipped in the specified slot
   local function itemCanBeIn(item, s)
      if not item then return false end
      if not item.components.equippable then return false end
      return item.components.equippable.equipslot == s
   end

   local stuff = inst.components.inventory:FindItems(function(item) return itemCanBeIn(item, slot) end) or {}
   local currentItem = inst.components.inventory:GetEquippedItem(slot)
   if currentItem ~= nil then
      table.insert(stuff, currentItem)
   end

   if #stuff == 0 then
      return nil, false
   end

   ------- Helper functions to get a specific value from an item ---------------
   local function getWaterProofValue(item)
      return item.components.waterproofer and item.components.waterproofer:GetEffectiveness() or 0
   end

   local function getInsulationValue(item, season)
      if not item.components.insulator then return 0 end
      if item.components.insulator.type == season then
         return item.components.insulator:GetInsulation()
      end
      return 0
   end

   local function getDappernessValue(item)
      -- Override for walter. His hat is the best sanity item for him. Everything
      -- else should be considered nothing.
      if inst:HasTag("pinetreepioneer") and item.prefab == "walterhat" then
         return 100
      elseif inst:HasTag("pinetreepioneer") then
         return 0
      end
      return item.components.equippable.dapperness or 0
   end

   local function getArmorValue(item)
      return GetArmorAbsorption(item, attacker)
   end

   local function getArmorDurability(item)
      if not item.components.armor then return 0 end
      return item.components.armor:GetPercent()
   end
   -----------------------------------------------------------------------------


   -------- Sort Functions -----------------------------------------------------
   local function sortalphabetical(it1, it2)
      return it1.prefab < it2.prefab
   end

   local sortbysanity = nil

   -- Sorts by waterproof. Ties goes to most dapper.
   local function sortbywaterproof(it1, it2, tiebreaker)
      local v1 = getWaterProofValue(it1)
      local v2 = getWaterProofValue(it2)
      if v1 == v2 and not tiebreaker then
         return sortbysanity(it1, it2, true)
      end
      return v1 > v2
   end

   -- Sorts by insulation. Ties go to most dapper.
   local function sortbyinsulationwinter(it1, it2, tiebreaker)
      local i1 = getInsulationValue(it1, SEASONS.WINTER)
      local i2 = getInsulationValue(it2, SEASONS.WINTER)
      if i1 == i2 and not tiebreaker then
         return sortbysanity(it1, it2, true)
      end
      return i1 > i2
   end

   local function sortbyinsulationsummer(it1, it2, tiebreaker)
      local i1 = getInsulationValue(it1, SEASONS.SUMMER)
      local i2 = getInsulationValue(it2, SEASONS.SUMMER)
      if i1 == i2 and not tiebreaker then
         return sortbysanity(it1, it2, true)
      end
      return i1 > i2
   end

   -- When used by table.sort, only it1 and it2 will be available.
   -- The 3rd parameter is so we don't do an infinite recursive tiebreaker.
   sortbysanity = function(it1, it2, tiebreaker)
      local s1 = getDappernessValue(it1)
      local s2 = getDappernessValue(it2)
      if s1 == s2 and not tiebreaker then
         if IsColdOutside() then
            return sortbyinsulationwinter(it1, it2, true)
         else
            return sortbyinsulationsummer(it1, it2, true)
         end
      end
      return s1 > s2
   end

   -- Armor should have a clear best....maybe?
   local function sortbyarmor(it1, it2, tiebreaker)
      local v1 = getArmorValue(it1)
      local v2 = getArmorValue(it2)
      if v1 == v2 and not tiebreaker then
         -- If they offer the same protection, use the more damaged one
         -- to save space in inventory
         local it1_higher_sanity = sortbysanity(it1, it2, true)
         if getDappernessValue(it1) == getDappernessValue(it2) then
            return getArmorDurability(it1) < getArmorDurability(it2)
         end
         return it1_higher_sanity
      end
      return v1 > v2
   end
   -----------------------------------------------------------------------------

   -- First, sort by what gives the highest sanity.
   -- This way, if there is a tie for some scenario, we'll default to the highest
   -- sanity one.
   table.sort(stuff, sortalphabetical)
   if scenario == "temperature_low" then
      table.sort(stuff, sortbyinsulationwinter)
   elseif scenario == "temperature_high" then
      table.sort(stuff, sortbyinsulationsummer)
   elseif scenario == "wetness" then
      table.sort(stuff, sortbywaterproof)
   elseif scenario == "sanity" then
      table.sort(stuff, sortbysanity)
   elseif scenario == "armor" then
      table.sort(stuff, sortbyarmor)
   else
      print("No valid scenario!")
      return nil, false
   end

   local key, bestItem = next(stuff)
   local is_equipped = (bestItem ~= nil and currentItem ~= nil and bestItem.prefab == currentItem.prefab)

   return bestItem, is_equipped
end

function EquipBestArmor(inst, target, drop_backpack)

   -- TODO: This is just copied from ManageClothes
   -- Returns true if the item can be equipped in the specified slot
   local head, head_equipped = GetBestEquipmentFor(inst, "armor", EQUIPSLOTS.HEAD, target)
   if head and not head_equipped then
      inst.components.inventory:Equip(head)
   end

   -- Only equip body armor if either not wearing a backpack, OR if drop_backpack override is defiend.
   local equip_body = false
   local currentBody = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
   if not currentBody then
      equip_body = true
   elseif drop_backpack and not currentBody:HasTag("backpack") then
      equip_body = true
   end


   -- Either weren't holding a backpack or the override was true. Time to equip.
   if equip_body then
      local body, body_equipped = GetBestEquipmentFor(inst, "armor", EQUIPSLOTS.BODY, target)
      if body and not body_equipped then
         inst.components.inventory:Equip(body)
      end
   end
end

-- Will maintain a list of properties/items that should/should not go into a backpack.

local notInBackpack = {}
notInBackpack["log"] = 1
notInBackpack["twigs"] = 1
notInBackpack["cutgrass"] = 1
notInBackpack["torch"] = 1


function ShouldGoInBackpack(item)
    -- Don't ever put weapons or armor in there....don't want to lose them
    -- if we equip armor and ditch backpack
    if item.components.armor or item.components.weapon then return false end

    -- Don't put essentials in there
    if notInBackpack[item.prefab] then return false end

    -- Souls cannot go in backpacks.
    if item:HasTag("soul") then return false end

    -- Don't put spiders in there, want to be able to summon them for attacks
    if item:HasTag("spider") then return false end

    -- Anything else...sure, why not
    return true
end


-- Returns true only if the item can fit in an existing stack in the inventory.
function CanFitInStack(inst,item)
   if not inst.components.inventory then return false end

   local inInv = inst.components.inventory:FindItems(function(i) return item.prefab == i.prefab end)
   for k,v in pairs(inInv) do
      if v.components.stackable then
         if not v.components.stackable:IsFull() then
            return true
         end
      end
   end
   return false
end

-- Transfers one (or all) of the item in the fromContainer to the toContainer
function TransferItemTo(item, fromInst, toInst, fullStack)

   if not item or not fromInst or not toInst then return false end

   local fromContainer = fromInst.components.inventory and fromInst.components.inventory or fromInst.components.container
   local toContainer = toInst.components.inventory and toInst.components.inventory or toInst.components.container

   if not fromContainer or not toContainer then
      print("TransferItemTo only works with type inventory or type container")
      return false
   end

   -- Don't even attempt if the toContainer is full and can't even accept a single one.
   if toContainer:IsFull() then
      local itemInDest = toContainer:FindItems(function(i) return i.prefab == item.prefab end)
      local canFitOne = false
      for k,v in pairs(itemInDest) do
         if v.components.stackable and not v.components.stackable:IsFull() then
            canFitOne = true
            break
         end
      end

      -- If we can't even get one...return false
      if not canFitOne then
         --print("Can't get one more of this thing")
         return false
      end
   end

   -- Remove it before transfer
   local theItem = item.components.inventoryitem:RemoveFromOwner(fullStack and toContainer.acceptsstacks)

   local success = false
   if theItem then
      --print("removed: " .. tostring(theItem.components.stackable and theItem.components.stackable.stacksize or 1) .. " " .. theItem.prefab .. " from " .. fromInst.prefab)
      --print("transfering to: " .. toInst.prefab)

      -- When removing something from the backpack, the game frickin remembers this.
      -- When I try to put it back in the inventory...it puts it back in the backpack. WTF mate.
      if fromInst.components.container and toInst.components.inventory then
         theItem.prevcontainer = nil
      end

      -- Passing GetScreenPosition will make the item sail across the screen all fancy like
      success = toContainer:GiveItem(theItem,nil,TheInput:GetScreenPosition(),false,false)

      -- If this failed, give it back.
      if not success then
         --print("GiveItem failed")
         fromContainer:GiveItem(theItem)
         return false
      end
   else
      --print("Couldn't find theItem")
      return false
   end

   return true
end

function GetEquippedItem(inst, slot)
   return inst.components.inventory:GetEquippedItem(slot)
end

-- Returns true if the item in the slot contains the tag
function DoesEquipSlotContain(inst, slot, tag)
   local item = GetEquippedItem(inst, slot)
   return (item and item:HasTag(tag)) or false
end

-- Returns true if it's a light source, AND it has fuel
function IsItemLightSource(inst, item)
   -- TODO
   return false
end

-- Returns a weapon in the inventory (or equipped) that is ranged.

function GetRangedWeapon(inst)
   local isRangedWeapon = function(item)
      if not item:HasTag("rangedweapon") then return false end

      if not item.components.weapon then return false end

      -- Some weapons have a projectile component. others have just a prefab name that gets spawned.
      if item.components.weapon:CanRangedAttack() then return true end

      if item.components.projectile ~= nil then return true end

      return false
   end

   -- If we're holding a ranged weapon already, just use that.
   local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
   if equipped and isRangedWeapon(equipped) then
      return equipped, true
   end

   local weapons = inst.components.inventory:FindItems(isRangedWeapon)

   -- Can have multiple...which to return? Just doing the first one
   return (weapons and weapons[1] or nil), false

end

-- Checks the given chest for a prefab.
-- Returns a list of these things.
function FindItemsInChest(player, chest, prefab)
   if not chest.components.container then return nil end
   if not chest.components.container:CanOpen() then
      DebugPrint(player, "Can't open chest " .. tostring(chest))
      return nil
   end
   return chest.components.container:FindItems(function(t) return t.prefab == prefab end)
end

-- Looks around the player with a given radius for an item in a chest.
-- Returns the chest, and an item for each slot that contains it...
function FindChestWithItems(player, radius, prefab)
   local pt = Point(player.Transform:GetWorldPosition())

   --TheSim:FindEntities(pt.x, pt.y, pt.z, 3, nil, self.canttags, self.willfightback) or {}
   local ents = TheSim:FindEntities(pt.x, pt.y, pt.z, radius, nil, {"INLIMBO", "NOCLICK"})
   local chests = {}
   for i, v in ipairs(ents) do
      if v.components and v.components.container then
         if v ~= player and v.entity:IsVisible() then
            table.insert(chests, v)
         end
      end
  end

   for k,v in pairs(chests) do
      local items = FindItemsInChest(player, v, prefab)
      if items ~= nil and #items > 0 then
         return v, items
      end
   end

   return nil, nil
end

-- Builds a buffered action which has the player gives/get the item from the chest.
-- Build a RUMMAGE action. If the RUMMAGE action succeeds, will attempt to transfer the
-- items to the player.
-- Will call the successFn once all items have been transferred.
-- Will call the failFn if anything fails.
function BuildChestTransferAction(player, chest, give, items, quantity, successFn, failFn)
   local action = BufferedAction(player, chest, ACTIONS.RUMMAGE)
   local getItems = function()

      local giver = give and player or chest
      local getter = give and chest or player

      local numGot = 0
      for k,v in pairs(items) do
         if numGot < quantity then
            DebugPrint(player, "Still need " .. tostring(quantity - numGot) .. " more")
            local numItemsInStack = (v.components and v.components.stackable and v.components.stackable:StackSize()) or 1
            local fullStack = (numItemsInStack <= (quantity - numGot)) or false
            if fullStack then
               if TransferItemTo(v, giver, getter, true) == false then
                  DebugPrint(player, "TransferItem (full stack)" .. tostring(v) .. " failed...")
                  return false
               end
               numGot = numGot + numItemsInStack
            else
               -- Transfer one at a time
               DebugPrint(player, "Transfer one at a time...")

               for num=1,numItemsInStack,1 do
                  if numGot < quantity then
                     if TransferItemTo(v, giver, getter, false) == false then
                        DebugPrint(player, "TransferItem " .. tostring(v) .. " failed...")
                     end
                     numGot = numGot + 1
                  end
               end
            end
         end
      end

      DebugPrint(player, "Finished transferring all items!")
      return true
   end

   local success = function(actionSuccess)

      if not actionSuccess and failFn ~= nil then
         DebugPrint(player, "RUMMAGE action failed....")
         failFn()
         return
      end

      if actionSuccess then
         DebugPrint(player, "RUMMAGE action success....trying to transfer items")
         if getItems() then
            if successFn ~= nil then
               successFn()
            end
         else
            if failFn ~= nil then
               failFn()
            end
         end
      end
   end

   action:AddSuccessAction(function() success(true) end)
   action:AddFailAction(function() success(false) end)

   return action
end

