FindTreeOrRock = Class(BehaviourNode, function(self, inst, searchDistanceFn, actionType)
    BehaviourNode._ctor(self, "FindTreeOrRock")
    self.inst = inst
	self.distance = searchDistanceFn
	self.actionType = actionType
	self.currentTarget = nil
	self.waitingForBuild = nil
	self.reachedDestination = false

	-- Locomotor will tell is if pathfinder failed. 
	-- Should be able to use this to stop the action. 
	self.locomotorFailed = function(inst, data)
		local theAction = data.action or "[Unknown]"
		local theReason = data.reason or "[Unknown]"
		DebugPrint(self.inst, "FindTreeOrRock: Action: " .. theAction:__tostring() .. " failed. Reason: " .. tostring(theReason))
        self:OnFail() 
    end
	self.inst:ListenForEvent("actionfailed", self.locomotorFailed)
	
	-- Likewise, pathfinder will tell us if it arrived, but 
	-- this doesn't seem to be useful for anything. Maybe 
	-- to stop a timer? 
	self.onReachDest = function(inst,data)
		local target = data.target
		if target and self.action and target == self.action.target then
			self.reachedDestination = true
		end
	end
	self.inst:ListenForEvent("onreachdestination", self.onReachDest)

	-- Every time we build something, this callback will fire. 
	-- If we are waiting for a build, we can use this to know when
	-- that specific thing is built. 
	-- TODO: Currently will abandon everything if something other than
    --       what we were waiting for is built. Maybe this is OK as it 
	--       will be caught in the RUNNING section and restart? 
	self.buildItem = function(inst, data)
		if self.waitingForBuild ~= nil then
			if data.item.prefab == self.waitingForBuild then
				DebugPrint(self.inst, "We've made a " .. self.waitingForBuild)
				self.waitingForBuild = nil
			else
				DebugPrint(self.inst, "uhhh, we made....something else? " .. data.item.prefab)
				self.waitingForBuild = nil
			end
		end
	end
	self.inst:ListenForEvent("builditem", self.buildItem)
	
	-- finishedwork is called when a workable item has no more work left. This could be from anyone. 
	-- workfinished passes the worker as the data, so we can see if it was us that did it. 
	self.onWorkDone = function(inst, data)
		-- finishedwork data has target and action. 
		-- Check to see if the target matches our current target. 
		-- TODO: Compare it to our action? For CHOP/MINE, I think it's fine to assume it will
		--       only be this....
		if self.currentTarget == nil then
			return
		end
		DebugPrint(self.inst, "finished work callback: " .. tostring(inst))
		DebugPrint(self.inst, "  ...current target" .. tostring(self.currentTarget))
		DebugPrint(self.inst, "  ...finshed target" .. tostring(data.target))
		if data and data.target == self.currentTarget then
			self.workDone = SUCCESS
		elseif data and data.target ~= self.currentTarget then
			DebugPrint(self.inst, "Ignoring finishedwork for different target: " .. tostring(data.target) )
			DebugPrint(self.inst, "Current target: " .. tostring(self.currentTarget))
		end

	end
	self.inst:ListenForEvent("finishedwork", self.onWorkDone)
	---self.inst:ListenForEvent("workfinished", self.onWorkDone)
end)

function FindTreeOrRock:OnStop()
	self.inst:RemoveEventCallback("finishedwork", self.onWorkDone)
	self.inst:RemoveEventCallback("builditem", self.buildItem)
	self.inst:RemoveEventCallback("onreachdestination", self.onReachDest)
end

function FindTreeOrRock:OnFail()
    self.pendingstatus = FAILED
end
function FindTreeOrRock:OnSucceed()
	self.pendingstatus = SUCCESS
end

function FindTreeOrRock:BuildSucceed()
	self.pendingBuildStatus = SUCCESS
end
function FindTreeOrRock:BuildFailed()
	self.pendingBuildStatus = FAILED
end

-- Does a lookup of a gien thing to extract the loot table. 
-- Currently assumes everything is 100% chance...
local function getLootFromTable(inst)
    if not inst.components.lootdropper then return end
    
    local loot = {}
    -- Only add the prefab once. Don't care about counting.
    local function insertLoot(prefab)
        if loot[prefab] == nil then
            loot[prefab] = 1
        end
    end
    

    -- Let's assume everything has a 100% chance
    -- to drop right now.
    if inst.components.lootdropper.chanceloottable then
        local loot_table = LootTables[inst.components.lootdropper.chanceloottable]
        if loot_table then
            for i, entry in ipairs(loot_table) do
                local prefab = entry[1]
                local chance = entry[2] -- Not using for now
                insertLoot(prefab)
            end
        end
    end
    
    if inst.components.lootdropper.loot then
        for k,v in pairs(inst.components.lootdropper.loot) do
            insertLoot(v)
        end
    end
       
    return loot
end

-- TODO: This is different between DS and DST. 
--       What is a good way to reuse the same function? 
function FindTreeOrRock:SetupActionWithTool(target, tool)
	local action = BufferedAction(self.inst, target, self.actionType, tool)
	if action ~= nil then
		action:AddFailAction(function() end)
	end
	self.action = action

	--------------- DS ----------------------
	--print("Setting up action with tool - " .. tostring(action))
	self.inst.components.locomotor:PushAction(action, true)

	--------------- DST ---------------------
	-- DST requires a preview_cb to be defined in the action. I think this is what gets called when
	-- the server acks our action request? 
	-- NVM - brain only exists on server
    --self.action.preview_cb = function() self:RemoteActionButton(self.action, false) end
    --self.inst.components.locomotor:PreviewAction(self.action, true)
end

function FindTreeOrRock:FindAndEquipRightTool()
	-- Get the right tool
	local equipped = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
	local alreadyEquipped = false
	local tool = nil

	-- Check if already holding the right tool for the job
	if equipped and equipped.components.tool and equipped.components.tool:CanDoAction(self.actionType) then
		return true, equipped
	else
		-- Not holding one...do we have on already in our inventory? 
		tool = self.inst.components.inventory:FindItem(function(item) return item.components.equippable and 
								item.components.tool and item.components.tool:CanDoAction(self.actionType) end)
	end
	if tool then
		if not alreadyEquipped then
			DebugPrint(self.inst, "Found right tool in inventory. Equipping " .. tostring(tool))
			self.inst.components.inventory:Equip(tool)
			return true, tool
		end
	else
		--print("Don't have a tool that can " .. tostring(self.actionType.id))
	end
	return false, nil
end


function FindTreeOrRock:Visit()
	-- READY is the idle state. Look for something to chop/mine. 
    if self.status == READY then
		self.workDone = nil
		self.currentTarget = nil
		self.pendingstatus = nil
		self.waitingForBuild = nil

		local target = FindEntity(self.inst, self.distance(), function(item)

			-- Ignore things in the water
			if IsInWater(item) then return false end

			if not item.components.workable then return false end
			if item.components.workable:GetWorkAction() ~= self.actionType then return false end
			if not item.components.workable:CanBeWorked() then return false end

			-- Stumps somehow show up as choppable still and he freaks out. 
			if item:HasTag("stump") then return false end
			-- Don't chop/mine renewable resources (twiggy trees)
			if item:HasTag("renewable") then return false end

			-- Item probably in the water. Ignore it. 
			if item:HasTag("ignorewalkableplatforms") then return false end
			
			-- Ignore some things
			if self.inst.components.prioritizer:OnIgnoreList(item.prefab) then return false end
			if self.inst.components.prioritizer:OnIgnoreList(item.entity:GetGUID()) then return false end

			-- Don't go near things with hostile dudes. 
			-- TODO: Need to ignore things with a mob in the path or something. Not sure what to do yet. 
			if self.inst.brain:HostileMobNearInst(item) then
				--DebugPrint(self.inst, "Ignoring " .. item.prefab .. " as there is something spooky by it")
				return false 
			end
			
			-- Some prefabs modify their loot table dynamically depending on their condition (burnt trees).
			-- There's no good way to tell if it will drop a special loot in the code.
			if item:HasTag("tree") and item:HasTag("burnt") then
				-- Charcoal!
				local invFull = self.inst.components.inventory:IsTotallyFull()
				if not invFull then
					return true
				end
				
				local ch = self.inst.components.inventory:FindItem(function(i) return i.prefab == "charcoal" end)
				if invFull and not ch then
					return false
				elseif invFull and ch then
					return not ch.components.stackable:IsFull()
				end
			end
			
			-- Only do work on this item if it will drop something we want
			local itemLoot = getLootFromTable(item)
			if not itemLoot then return false end
			
			
			for k,v in pairs(itemLoot) do
				-- If we aren't ignoring this type of loot.
				-- TODO: I don't want to cut down a tree for the acorns only...but I also don't 
				--       want to add them to the ignore list as I want them.
				--       This is kinda hacky.
				if  not self.inst.components.prioritizer:OnIgnoreList(k) and k ~= "acorn" then
					local itemInInv = self.inst.components.inventory:FindItem(function(i) return i.prefab == k end)
					-- If we don't have one and not full, pick it up!
					if not itemInInv and not self.inst.components.inventory:IsTotallyFull() then
						return true
					end
					
					-- Else, if we have one...make sure we want it
					local canStack = itemInInv and itemInInv.components.stackable and not itemInInv.components.stackable:IsFull()
					if canStack then 
						return true 
					end
			    end
			end
			
            -- This is nothing that I want
			return false
		end)
		
		-- Found something to mine/chop. 
		if target then
    		self.currentTarget = target
			local haveRightTool, tool = self:FindAndEquipRightTool()

			-- We are holding the right tool or have one in inventory
			if haveRightTool then
				self.currentTarget = target
				self:SetupActionWithTool(target, tool)
				self.inst.brain:ResetSearchDistance()
				self.status = RUNNING
				return
			else
				-- Can we craft one? 
				--print("Can I craft something to " .. tostring(self.actionType.id))
				local thingToBuild = nil
				if self.actionType == ACTIONS.CHOP then
					thingToBuild = "axe"
				elseif self.actionType == ACTIONS.MINE then
					thingToBuild = "pickaxe"
				elseif self.actionType == ACTIONS.HAMMER then
					thingToBuild = "hammer"
				end
				
				-- Make sure we have room for it! 
				-- TODO: Drop something else? Or just wait? 
				if self.inst.components.inventory:IsTotallyFull() then
					DebugPrint(self.inst, "No room in inventory!")
					self.status = FAILED
					return
				end
				
				-- Axe and pickaxe are always level 1...so we don't need to do a more intense check here. Just see if 
				-- we have the resources and craft it.
				if thingToBuild and self.inst.components.builder and self.inst.components.builder:CanBuild(thingToBuild) then
					
					if CraftItem(self.inst, thingToBuild) then
						self.waitingForBuild = thingToBuild
						self.status = RUNNING
					else 
						self.status = FAILED
					end
					return
				else
					-- TODO: Add the recipe to the gather list? They should already be there...
					--addRecipeToGatherList(thingToBuild,false)
					-- cant build the right tool
					self.status = FAILED
					return
				end
			end
		end

		-- No target, or no tool, etc etc...nothing to do
		self.status = FAILED
		return

    elseif self.status == RUNNING then

		-- We did it!
		if self.workDone ~= nil and self.workDone == SUCCESS then
			self.status = SUCCESS
			return
		end

		-- Waiting for the tool to be built. Be patient. 
		-- TODO: Add a timer? 
		if self.waitingForBuild ~= nil then
			-- print("Still waiting for " .. self.waitingForBuild)
			self.status = RUNNING
			return
		end

		-- Make sure the target is still valid. 
        if not self.currentTarget then
            self.status = SUCCESS
            return
        elseif self.currentTarget and not self.currentTarget.components.workable then
            self.status = SUCCESS
            return
        end

		-- If we got here, the target is still there, and we "should" have a valid tool. 
		-- Queue up another action. 

		local equiped, tool = self:FindAndEquipRightTool()
		if self.currentTarget and equiped then
			-- Make sure the thing is still there before doing it again
			if not tool.components.tool:CanDoAction(self.currentTarget.components.workable:GetWorkAction()) then
				-- We probably killed it. Return success.
				self.currentTarget = nil
				self.status = SUCCESS
				return
			else 
				-- Still good. Keep going
				self:SetupActionWithTool(self.currentTarget, tool)
				self.status = RUNNING

				-- Make sure nothing has happened
				-- if not self.action:IsValid() then
				-- 	print("FindTreeOrRock - Something has gone wrong")
				-- 	self.status = FAILED
				-- end

						-- If the action is not valid, stop. 
				if not self.action:IsValid() then
					self.status = FAILED
				elseif not self.inst.components.locomotor:HasDestination() and not self.reachedDestination then
					DebugPrint(self.inst, "We have no destination and we haven't reached it yet! We're stuck!")
					self.status = FAILED
				end

				return
			end
		else
			DebugPrint(self.inst, "Either no more target, or no tool...")
			self.status = SUCCESS
			return
		end

		-- IF we get here...must have been done? Log this - shouldn't happen. 
		DebugPrint(self.inst, "FindTreeOrRock - hit the end?")
		self.status = SUCCESS
    end
end



