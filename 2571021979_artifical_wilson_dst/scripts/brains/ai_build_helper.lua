--require "widgets/widgetutil"
-- Copied straight from widgetutil.lua
-- function CanPrototypeRecipe(recipetree, buildertree)
--     for k,v in pairs(recipetree) do
--         if buildertree[tostring(k)] and recipetree[tostring(k)] and
--         recipetree[tostring(k)] > buildertree[tostring(k)] then
--                 return false
--         end
--     end
--     return true
-- end

function CanPrototypeRecipe(recipetree, buildertree)
	for k, v in pairs(recipetree) do
		 local v1 = buildertree[tostring(k)]
		 if v ~= nil and v1 ~= nil and v > v1 then
			  return false
		 end
	end
	return true
end

-- used for crafting inventory items (torch, spear, etc)
function CraftItem(player, thingToBuild)

	--local recipe = GetValidRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)
	if recipe == nil then
		DebugPrint(player, "No valid recipe for " .. thingToBuild .. "??")
		return false
	end
	--player.components.builder:MakeRecipeFromMenu(recipe)
	player.replica.builder:MakeRecipeFromMenu(recipe)
	return true
end

function CraftStructure(player, thingToBuild, pos, rot)
	--local recipe = GetValidRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)
	DebugPrint(player, "CraftStructure: trying to build a " .. thingToBuild)
	if recipe == nil then
		DebugPrint(player, "No valid recipe for " .. thingToBuild .. "??")
		return false
	end

	player.replica.builder:BufferBuild(thingToBuild)

	local pt = pos or player:GetPosition()
	local r = rot or player:GetRotation()

	-- Now find a valid point for this damn thing close to the original position
	-- Start with double our build model size, then search from there?
	-- This also only starts in the direction we are facing, which could be pretty
	-- random...
	local start_radius = 2*player.Physics:GetRadius()
	local final_position = pt
	for radius = start_radius, 8*start_radius, start_radius do
		-- TODO: Add custom build restrictions? (i.e. not near flamable, etc)
		DebugPrint(player, "Finding walkable offset at radius " .. tostring(radius) .. " from " .. tostring(pt))
		local valid_offset, check_angle, deflected = FindWalkableOffset(pt, r, radius, 8, false, false,
					function(new_pt)
						local can_build = player.replica.builder:CanBuildAtPoint(new_pt, recipe, r)
						DebugPrint(player, "Checking new point: " .. tostring(new_pt) .. " : " .. tostring(can_build))
						return can_build
					end, false, false)
		if valid_offset ~= nil then
			final_position = pt + valid_offset
			break
		end
	end

	if final_position == nil then
		DebugPrint(player, "Could not find a valid place to build " .. thingToBuild .. "!!!")
		return false
	end

	player.replica.builder:MakeRecipeAtPoint(recipe, final_position, r, nil)
	return true
end

-- Equips and returns the thing equipped
-- thingToEquip can either be a function, or a prefab name
function FindAndEquipItem(player, equip_slot, thingToEquip)

	local testfn = nil
	if type(thingToEquip) == "string" then
		testfn = function(item) return item and item.prefab == thingToEquip and item.components.equippable end
	else
		testfn = function(item) return item.components.equippable and thingToEquip(item) end
	end

	-- See if it was already equipped
	local equipped = player.replica.inventory:GetEquippedItem(equip_slot)
	if equipped ~= nil and testfn(equipped) then
		return true, equipped
	end

	-- It's not equipped, check the inventory for one
	local item = player.replica.inventory:FindItem(testfn)
	if item == nil then
		DebugPrint(player, "Couldn't find any item in inventory that matches criteria...")
		return false, nil
	end

	-- We have one, try to equip it.
	player.replica.inventory:Equip(item)


	-- It wasn't already equipped, find one in the inventory.
	item = player.replica.components.inventory:FindItem(function(thing) return thing.components.equippable and thing.prefab == thingToEquip and ((testfn and testfn(thing)) or true) end)

	if item ~= nil then
		DebugPrint(player, "Found right item in inventory. Equipping " .. tostring(thingToEquip))
	end
end

-- Makes sure we have the right tech level.
-- If we don't have a resource, checks to see if we can craft it/them
-- If we can craft all necessary resources to build something, returns true
-- else, returns false
-- Do not set recursive variable, it will be set on recursive calls
-- If you want this built, have the Crafting behaviour do it
function CanPlayerBuildThis(player, thingToBuild, numToBuild, recursive)

	-- If we already have one buffered, of course we can build it.
	if player.components.builder:IsBuildBuffered(thingToBuild) then
		return true
	end
	-- Reset the table if it exists
	if player.itemsNeeded and not recursive then
		for k,v in pairs(player.itemsNeeded) do player.itemsNeeded[k]=nil end
		recursive = 0
	elseif player.itemsNeeded == nil then
		player.itemsNeeded = {}
	end

	if recursive == nil then
		recursive = 0
	end

	if numToBuild == nil then numToBuild = 1 end

	--local recipe = GetValidRecipe(thingToBuild) -- GetRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)

	-- Not a real thing so we can't possibly build this
	if not recipe then
		--DebugPrint(player, thingToBuild .. " is not craftable")
		return false
	end

	if player.components.builder.freebuildmode then
		--DebugPrint(player, "Free Build Mode Enabled....don't bother checking")
		return true
	end

	--DebugPrint(player, "Checking to see if we can build " .. thingToBuild)

	-- Quick check, do we know how to build this thing?
	if not player.components.builder:KnowsRecipe(thingToBuild) then
		-- Check if we can prototype it
		--DebugPrint(player, "We don't know recipe for " .. thingToBuild)
		local tech_level = player.components.builder.accessible_tech_trees
		if not CanPrototypeRecipe(recipe.level, tech_level) then
			--DebugPrint(player, "...nor can we prototype it")
			return false
		else
			--DebugPrint(player, "...but we can prototype it!")
		end
	end

	-- For each ingredient, check to see if we have it. If not, see if it's creatable
	for ik,iv in pairs(recipe.ingredients) do
		local hasEnough = false
		local numHas = 0
		local totalAmountNeeded = math.ceil(iv.amount*numToBuild)
		hasEnough, numHas = player.components.inventory:Has(iv.type,totalAmountNeeded)

		-- Subtract things already reserved from numHas
		for i,j in pairs(player.itemsNeeded) do
			if j.prefab == iv.type then
				numHas = math.max(0,numHas - 1)
			end
		end

		-- If we don't have or don't have enough for this ingredient, see if we can craft some more
		if numHas < totalAmountNeeded then
			local needed = totalAmountNeeded - numHas
			-- Before checking, add the current numHas to the table so the recursive
			-- call doesn't consider them valid.
			-- Make it level 0 as we already have this good.
			if numHas > 0 then
				table.insert(player.itemsNeeded,1,{prefab=iv.type,amount=numHas,level=0})
			end
			-- Recursive check...can we make this ingredient
			local canCraft = CanPlayerBuildThis(player,iv.type,needed,recursive+1)
			if not canCraft then
				--DebugPrint(player, "Need " .. tostring(needed) .. " " .. iv.type .. " but can't craft them!")
				return false
			else
				-- We know the recipe to build this and have the goods. Add it to the list
				-- This should get added in the recursive case
				--table.insert(player.itemsNeeded,1,{prefab=iv.type, amount=needed, level=recursive, toMake=thingToBuild})
			end
		else
			-- We already have enough to build this resource. Add these to the list
			--DebugPrint(player, "Adding " .. tostring(totalAmountNeeded) .. " of " .. iv.type .. " at level " .. tostring(recursive) .. " to the itemsNeeded list")
			table.insert(player.itemsNeeded,1,{prefab=iv.type, amount=totalAmountNeeded, level=recursive, toMake=thingToBuild, toMakeNum=numToBuild})
		end
	end

	-- We made it here, we can make this thingy
	return true
end

-- Returns a list of one or more buffered actions.
-- Attaches the onSuccess action only to the final thing wanting to be built
-- Attaches the onFail action to every action.
-- The best way to use this is to have a BehaviourNode run through the queued list until
-- the onSuccess callback is triggered.

-- Returns nil if there were no actions generated
function GenerateBufferedBuildOrder(player, thingToBuild, pos, onSuccess, onFail)
	local bufferedBuildList = {}
	--local recipe = GetValidRecipe(thingToBuild) --GetRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)
	-- not a real thing
	if not recipe then return end

	--print("GenerateBufferedBuildOrder called with " .. thingToBuild)

	-- generate a callback fn for successful build
	local unlockRecipe = function()
	   if not player.components.builder:KnowsRecipe(thingToBuild) then
		    player.components.builder:UnlockRecipe(thingToBuild)
		end
	end

	if not player.itemsNeeded or #player.itemsNeeded == 0 then
		DebugPrint(player, "itemsNeeded is empty!")
		-- This should always be called first.
		-- If the table doesn't exist, generate it for them
		if not CanPlayerBuildThis(player, thingToBuild) then
			return
		end
	end

	--for k,v in pairs(player.itemsNeeded) do print(k,v) end
	-- Calculate the required inventory space to make this thing.
	-- Drop everything not needed to craft it just to make sure?

	-- TODO: Make sure we have the inventory space!
	local canFitInInventory = true
	local emptySlotsNeeded = 0

	for k,v in pairs(player.itemsNeeded) do
		-- Just go down the list. If level > 0, we need to build it
		if v.level > 0 and v.toMake then
			-- It's assumed that we can build this. They shouldn't have called this
			-- function otherwise! Can't test here as we might not have all of the
			-- refined resources yet.

			-- Check to see if we have one of these already. If we do, make sure we can hold
			-- all of the new ones we will be making.
			local matchingItem = player.components.inventory:FindItem(function(t) return t.prefab == v.toMake end)
			if matchingItem then
				local canHoldAll = player.components.inventory:CanAcceptCount(matchingItem, v.toMakeNum)
				if not canHoldAll then
					-- Just overflow into a new slot
					emptySlotsNeeded = emptySlotsNeeded + 1
				end
			else
				-- It's assumed that any empty slot will be sufficient to hold all of these....
				emptySlotsNeeded = emptySlotsNeeded + 1
			end

			while v.toMakeNum > 0 do

				local rot = player:GetRotation()
				local skin_index = nil
				local action = BufferedAction(player,nil,ACTIONS.BUILD,nil, pos or player:GetPosition(),v.toMake,0, nil, rot)

				----------- For DST - need the callback defined in the action
				-- action.preview_cb = function()
				-- 	SendRPCToServer(RPC.MakeRecipeAtPoint, recipe.rpc_id, action.pos.local_pt.x, action.pos.local_pt.z, rot, skin_index, action.pos.walkable_platform, action.pos.walkable_platform ~= nil)
				-- end
				--player.components.locomotor:PreviewAction(action, true)

				if onFail then
					action:AddFailAction(function() onFail() end)
				end
				-- Add the recipe unlock success action
				action:AddSuccessAction(unlockRecipe)

				DebugPrint(player, "Adding action " .. action:__tostring() .. " to bufferedBuildList")
				table.insert(bufferedBuildList, action)
				v.toMakeNum = v.toMakeNum - 1
			end
		end
	end

	-- Make sure we have enough empty slots to make this stuff first.
	local emptySlots = 0
	for k = 1, player.components.inventory.maxslots do
		local v = player.components.inventory.itemslots[k]
		if v == nil then
			emptySlots = emptySlots + 1
		end
	end

	-- TODO: Yeet things on the ground to make room? how would I know if
	--       the slot contained something we needed though...
	if emptySlots < emptySlotsNeeded then
		DebugPrint(player, "Aborting build - not enough empty slots!")
		return nil
	end


	-- Finally, queue the final resource for build.
	local action = BufferedAction(player,player,ACTIONS.BUILD,nil,pos,thingToBuild,1)
	if onFail then
		action:AddFailAction(onFail)
	end
	if onSuccess then
		action:AddSuccessAction(onSuccess)
	end
	-- Also add the success action for unlocking the recipe
	action:AddSuccessAction(unlockRecipe)
	table.insert(bufferedBuildList,action)

	return bufferedBuildList

end

function BuildIfAble(player, prefab)
	if player.waitingForBuild then return false end
	if not player.components.builder:KnowsRecipe(prefab) then return false end

	if CanPlayerBuildThis(player, prefab) then
		player.waitingForBuild = prefab
		player.brain:SetSomethingToBuild(prefab,nil,
						function() player.waitingForBuild = nil end,function() player.waitingForBuild = nil end)
		return true
	end
	-- if not player.waitingForBuild and player.components.builder:KnowsRecipe(prefab) and player.components.builder:CanBuild(prefab) then
	-- 	player.waitingForBuild = prefab
	-- 	player.brain:SetSomethingToBuild(prefab,nil,
	-- 					function() player.waitingForBuild = nil end,function() player.waitingForBuild = nil end)
	-- end
	return false
end