

require "brains/common_helper"

require "behaviours/chaseandattack"
require "behaviours/runaway"
require "behaviours/doaction"

require "behaviours/watchdog"
require "behaviours/customrunaway"
require "behaviours/managehunger"
require "behaviours/managehealth"
require "behaviours/managesanity"
require "behaviours/manageclothes"
require "behaviours/findandactivate"
require "behaviours/findresourceonground"
require "behaviours/findresourcetoharvest"
require "behaviours/findtreeorrock"
require "behaviours/findormakelight"
require "behaviours/selfpreservation"
require "behaviours/doscience"
require "behaviours/cookfood"
require "behaviours/manageinventory"
require "behaviours/gordonramsay"
require "behaviours/dontbeonfire"
require "behaviours/findthingtoburn"
require "behaviours/kitemaster"
require "behaviours/managesummons"
require "behaviours/maxwell"
require "behaviours/socialism"
require "behaviours/dodgeprojectile"
require "behaviours/snipemaster"
require "behaviours/investigate"
require "behaviours/managetraps"
require "behaviours/revenge"

require "brains/ai_build_helper"
require "brains/ai_combat_helper"
require "brains/ai_inventory_helper"
require "brains/ai_misc_functions"

local MIN_SEARCH_DISTANCE = 10
local MAX_SEARCH_DISTANCE = 100
local SEARCH_SIZE_STEP = 10
local RUN_AWAY_SEE_DIST = 7
local ATTACK_DIST = 10
local RUN_AWAY_STOP_DIST = 11
local CurrentSearchDistance = MIN_SEARCH_DISTANCE
local RANDOM_TALK_INTERVAL = 45

-- List of tags we shouldn't ever fight. Doesn't mean we shouldn't run from them though....
local neverfight = {"rook", "pig", "WORM_DANGER", "merm", "bishop", "beefalo", "charged", "chester", "companion", "buzzard", "ghost", "spat", "warg"}
-- List of tags we can't fight or shouldn't fight or run from
local canttags = {"INLIMBO", "notarget", "NOCLICK", "chester", "playerghost", "beehive", "mirrage"}
-- List of tags we will fight
local fight = {"hostile", "scarytoprey", "mosquito", "tallbird", "frog", "butterfly", "lightninggoat", "koalefant", "mole", "epic", "spiderden"}

-- Things to avoid at a further distance that others. Must be a tag, not a prefab name.
local longrangetags = {"bishop", "rook", "spat", "warg"}

-- TODO: Figure out enemy companions
local pvp_only = {"ArtificalWilson", "player"}

for _,v in ipairs(pvp_only) do
	if IsPvPEnabled() then
		print("PVP Enabled...")
		table.insert(fight, pvp_only)
	else
		table.insert(neverfight, pvp_only)
	end
end


-- The full list of things that will fight us should be the combination of neverfight + fight
local willfightback = {}
for _,v in ipairs(neverfight) do
	table.insert(willfightback, v)
end

for _,v in ipairs(fight) do
	table.insert(willfightback, v)
end

-- The list of things to never target is things to never fight + things we can't fight
local donttarget = {}
for _,v in ipairs(neverfight) do
	table.insert(donttarget, v)
end
for _,v in ipairs(canttags) do
	table.insert(donttarget, v)
end


-- What to gather. This is a simple FIFO. Highest priority will be first in the list.
local GATHER_LIST = {}
local function addToGatherList(_name, _prefab, _number)
	-- Group by name only. If we get a request to add something to the table with the same name and prefab type,
	-- ignore it
	for k,v in pairs(GATHER_LIST) do
		if v.prefab == _prefab and v.name == "name" then
			return
		end
	end
	-- New request for this thing. Add it.
	local value = {name = _name, prefab = _prefab, number = _number}
	table.insert(GATHER_LIST,value)
end

-- Decrement from the FIRST prefab that matches this amount regardless of name
local function decrementFromGatherList(_prefab,_number)
	for k,v in pairs(GATHER_LIST) do
		if v.prefab == _prefab then
			v.number = v.number - _number
			if v.number <= 0 then
				GATHER_LIST[k] = nil
			end
			return
		end
	end
end

local function addRecipeToGatherList(thingToBuild, addFullRecipe)
	--local recipe = GetValidRecipe(thingToBuild) -- GetRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)
    if recipe then
		local player = GLOBAL.ThePlayer
        for ik, iv in pairs(recipe.ingredients) do
			-- TODO: This will add the entire recipe. Should modify based on current inventory
			if addFullRecipe then
				print("Adding " .. iv.amount .. " " .. iv.type .. " to GATHER_LIST")
				addToGatherList(iv.type,iv.amount)
			else
				-- Subtract what we already have
				-- TODO subtract what we can make as well... (man, this is complicated)
				local hasEnough = false
				local numHas = 0
				hasEnough, numHas = player.components.inventory:Has(iv.type,iv.amount)
				if not hasEnough then
					print("Adding " .. tostring(iv.amount-numHas) .. " " .. iv.type .. " to GATHER_LIST")
					addToGatherList(iv.type,iv.amount-numHas)
				end
			end
		end
    end
end
---------------------------------------------------------------------------------


-- Makes sure we have the right tech level.
-- If we don't have a resource, checks to see if we can craft it/them
-- If we can craft all necessary resources to build something, returns true
-- else, returns false
-- Do not set recursive variable, it will be set on recursive calls
--local itemsNeeded = {}
local function CanIBuildThis(player, thingToBuild, numToBuild, recursive)

	-- Reset the table if it exists
	if player.itemsNeeded and not recursive then
		for k,v in pairs(player.itemsNeeded) do player.itemsNeeded[k]=nil end
		recursive = 0
	elseif player.itemsNeeded == nil then
		player.itemsNeeded = {}
	end

	if numToBuild == nil then numToBuild = 1 end

	--local recipe = GetValidRecipe(thingToBuild) --GetRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)

	-- Not a real thing so we can't possibly build this
	if not recipe then
		print(thingToBuild .. " is not buildable :(")
		return false
	end

	-- Quick check, do we know how to build this thing?
	if not player.components.builder:KnowsRecipe(thingToBuild) then
		-- Check if we can prototype it
		print("We don't know how to build " .. thingToBuild)
		local tech_level = player.components.builder.accessible_tech_trees
		if not CanPrototypeRecipe(recipe.level, tech_level) then
			print("...nor can we prototype it")
			return false
		else
			print("...but we can prototype it!")
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
			local canCraft = CanIBuildThis(player,iv.type,needed,recursive+1)
			if not canCraft then
				print("Need " .. tostring(needed) .. " " .. iv.type .. "s but can't make them")
				return false
			else
				-- We know the recipe to build this and have the goods. Add it to the list
				-- This should get added in the recursive case
				--table.insert(player.itemsNeeded,1,{prefab=iv.type, amount=needed, level=recursive, toMake=thingToBuild})
			end
		else
			-- We already have enough to build this resource. Add these to the list
			print("Adding " .. tostring(totalAmountNeeded) .. " of " .. iv.type .. " at level " .. tostring(recursive) .. " to the itemsNeeded list")
			table.insert(player.itemsNeeded,1,{prefab=iv.type, amount=totalAmountNeeded, level=recursive, toMake=thingToBuild, toMakeNum=numToBuild})
		end
	end

	-- We made it here, we can make this thingy
	return true
end

-- Should only be called after the above call to ensure we can build it.
local function OldBuildThis(player, thingToBuild, pos)
	--local recipe = GetValidRecipe(thingToBuild) --GetRecipe(thingToBuild)
	local recipe = GetRecipeCommon(thingToBuild)
	-- not a real thing
	if not recipe then return end

	print("BuildThis called with " .. thingToBuild)

	-- This should not be called without checking to see if we can build something
	-- we have to unlock the recipe here. It is usually done with a mouse event when a player
	-- goes to build something....so I assume if we got here, we can actually unlock the recipe
	-- Actually, Do this in the callback so we don't unlock it unless successful
	--if not player.components.builder:KnowsRecipe(thingToBuild) then
	--	print("Unlocking recipe")
	--	player.components.builder:UnlockRecipe(thingToBuild)
	--end

	-- Don't run if we're still buffer building something else
	if player.currentBufferedBuild ~= nil then
		print("Not building " .. thingToBuild .. " as we are still building " .. player.currentBufferedBuild)
		return
	end

	-- Save this. We'll catch the 'buildfinished' event and if it is this, we'll remove it.
	-- Will also remove it in watchdog
	player.currentBufferedBuild = thingToBuild

	-- TODO: Make sure the pos supplied is valid place to build this thing. If not, get a new one.
	--if pos ~= nil then
	--	local maxLoops = 5
	--	while not player.components.builder:CanBuildAtPoint(pos,thingToBuild) and maxLoops > 0 then
	--		local offset,result_angle,deflected = FindWalkableOffset(pos, angle,radius,8,true,false)
	--		maxLoops = maxLoops - 1
	--	end
	--end

	-- Called back from the MakeRecipe function...will unlock the recipe if successful
	local onsuccess = function()
		player.components.builder:UnlockRecipe(thingToBuild)
	end

	if not player.itemsNeeded or #player.itemsNeeded == 0 then
		print("itemsNeeded is empty!")
	end

	for k,v in pairs(player.itemsNeeded) do print(k,v) end

	-- TODO: Make sure we have the inventory space!
	for k,v in pairs(player.itemsNeeded) do
		-- Just go down the list. If level > 0, we need to build it
		if v.level > 0 and v.toMake then
			-- We should be able to build this...
			print("Trying to build " .. v.toMake)
			while v.toMakeNum > 0 do
				if player.components.builder:CanBuild(v.toMake) then

					local action = BufferedAction(player,nil,ACTIONS.BUILD,nil,pos,v.toMake,nil)
					player:PushBufferedAction(action)
					--player.components.locomotor:PushAction(action)
					--player.components.builder:MakeRecipe(GetRecipe(v.toMake),pos,onsuccess)
					v.toMakeNum = v.toMakeNum - 1
				else
					print("Uhh...we can't make " .. v.toMake .. "!!!")
					player.currentBufferedBuild = nil
					return
				end
			end
		end
	end

	--[[
	if player.components.builder:MakeRecipe(GetRecipe(thingToBuild),pos,onsuccess) then
		print("MakeRecipe succeeded")
	else
		print("Something is messed up. MakeRecipe failed!")
		player.currentBufferedBuild = nil
	end
	--]]


	if player.components.builder:CanBuild(thingToBuild) then
		print("We have all the ingredients...time to make " .. thingToBuild)

		local action = BufferedAction(player,player,ACTIONS.BUILD,nil,pos,thingToBuild,nil)
		print("Pushing action to build " .. thingToBuild)
		print(action:__tostring())
		--player.components.builder:MakeRecipe(thingToBuild,pos,onsuccess)
		player:PushBufferedAction(action)
	else
		print("Something is messed up. We can't make " .. thingToBuild .. "!!!")
		player.currentBufferedBuild = nil
	end

end


------------------------------------------------------------------------------------------------

local ArtificalBrain = Class(Brain, function(self, inst)
    Brain._ctor(self,inst)

	self.currentSearchDistance = MIN_SEARCH_DISTANCE
end)

function ArtificalBrain:SpawnMirrage()
	SpawnMirrage(self.inst)
end

------------------------------------------------------------
-- Helpful function...just returns a point at a random angle
-- a distance dist away.
function ArtificalBrain:GetPointNearThing(thing, dist)
	local pos = Vector3(thing.Transform:GetWorldPosition())
	if pos then
		local theta = math.random() * 2 * PI
		local radius = dist
		local offset = FindWalkableOffset(pos, theta, radius, 12, true)
		if offset then
			return pos+offset
		end
	end
end

-- Only says something when the timer is up. Whatever the next thing to be said
-- will happen.
function ArtificalBrain:SaySomething(string, minTime)
	if self.inst.components.talker == nil then return end
	-- Only say something at most RANDOM_TALK_INTERVAL seconds apart.
	-- Each SaySomething can pass their own minTime for things they want said
	-- more or less often.
	-- If something is said, it still resets the lastSayTime...
	local last_talk = minTime or RANDOM_TALK_INTERVAL
	if not self.lastSayTime then
		self.lastSayTime = 0
	end

	if (GetTime() - self.lastSayTime) > last_talk then
		self.inst.components.talker:Say(string)
		self.lastSayTime = GetTime()
	end
end

-- increments and loops the aggressiveness level of the bot.
function ArtificalBrain:NextAggressionLevel(inst)

end

-- Just copied the function. Other one will go away soon.
function ArtificalBrain:HostileMobNearInst(inst)
	-- local pos = inst.Transform:GetWorldPosition()
	-- if pos then
	-- 	return FindEntity(inst,RUN_AWAY_SEE_DIST,function(guy) return ShouldRunAway(guy, self.inst) end, nil, {"INLIMBO", "NOCLICK", "FX"}) ~= nil
	-- end
	-- return false

	local hostile = FindEntity(inst, 15,
	function(guy)

		local shouldRun = ShouldRunAway(guy, self.inst)

		-- Early check, don't compute distance to things we should never run from
		if not shouldRun then
			return false
		end

		if guy:HasTag("hive") and guy.prefab ~= "wasphive" then
			return false
		end

		if guy.prefab == "wasphive" then return true end

		for _,v in ipairs(longrangetags) do
			if guy:HasTag(v) then
				return true
			end
		end

		-- Otherwise, only check for close things.
		local pt = Point(self.inst.Transform:GetWorldPosition())
		local hp = Point(guy.Transform:GetWorldPosition())

		if distsq(hp, pt) < RUN_AWAY_SEE_DIST*RUN_AWAY_SEE_DIST then
			return shouldRun
		end

		return false
	end, nil, {"INLIMBO", "NOCLICK", "FX"})

	return hostile ~= nil

	-- local closeRange = FindEntity(inst,RUN_AWAY_SEE_DIST,function(guy) return ShouldRunAway(guy, self.inst) end, nil, {"INLIMBO", "NOCLICK", "FX"})
	-- if closeRange then
	-- 	return true
	-- end
	-- local longRange = FindEntity(inst, 15,
	-- 	function(guy)
	-- 		if guy:HasTag("hive") and guy.prefab ~= "wasphive" then
	-- 			return false
	-- 		end

	-- 		if guy.prefab == "wasphive" then return true end

	-- 		for _,v in ipairs(longrangetags) do
	-- 			if guy:HasTag(v) then
	-- 				return true
	-- 			end
	-- 		end

	-- 		return false
	-- 	end, nil, {"INLIMBO", "NOCLICK", "FX"})
	-- return longRange ~= nil
end

function ArtificalBrain:GetCurrentSearchDistance()
	--return CurrentSearchDistance
	return self.currentSearchDistance
end

function ArtificalBrain:IncreaseSearchDistance()
	--CurrentSearchDistance = math.min(MAX_SEARCH_DISTANCE,CurrentSearchDistance + SEARCH_SIZE_STEP)
	--DebugPrint(self.inst, tostring(self.inst) .. ": IncreaseSearchDistance to: " .. tostring(CurrentSearchDistance))
	local half_search = SEARCH_SIZE_STEP/2
	self.currentSearchDistance = math.min(MAX_SEARCH_DISTANCE,self.currentSearchDistance + math.random(half_search, SEARCH_SIZE_STEP+half_search))
	DebugPrint(self.inst, tostring(self.inst) .. ": IncreaseSearchDistance to: " .. tostring(self.currentSearchDistance))
end

function ArtificalBrain:ResetSearchDistance()
	--CurrentSearchDistance = MIN_SEARCH_DISTANCE
	self.currentSearchDistance = MIN_SEARCH_DISTANCE
end

local function OnPathFinder(self,data)
	print("Pathfinder has failed!")
	if data then
		if data.inst and data.inst.prefab then
			DebugPrint(self, tostring(data.inst) .. " has failed a pathfinding search")
		end
		if data.target and data.target.prefab then
			DebugPrint(self, "Adding " .. tostring(data.target) .. " GUID to ignore list")
			self.components.prioritizer:AddToIgnoreList(data.target.entity:GetGUID(), Vector3(self.Transform:GetWorldPosition()))
		end
	end

	if self.components.locomotor.isrunning then
		local rand = math.random()
		if rand > .66 then
			self.components.talker:Say("I'm too dumb to walk around this...")
		elseif rand > .33 then
			self.components.talker:Say("Stupid water...")
		end

		-- NONE OF THIS WORKS! WHY WONT HE STOP MOVING!!!
		local teleport = TeleportBehind(self, data.target, self)
		if teleport then
			DebugPrint(self, "Queuing teleport action")
			teleport.forced = true
			self.components.locomotor:Stop()
			--self.components.locomotor:KillPathSearch()
			--self.components.locomotor:SetBufferedAction(nil)
			--self.components.locomotor:PushAction(teleport, false)
			self:PushBufferedAction(teleport)

		else
			DebugPrint(self, "Attempting to stop action")

			--
			if self.components.locomotor.bufferedaction then
				DebugPrint(self, self.components.locomotor:GetDebugString())
				self.components.locomotor.bufferedaction:Fail()
			end
			self:ClearBufferedAction()
		end

		-- if self.components.locomotor.bufferedaction then
		-- 	print("Calling FAIL")
		-- 	self.components.locomotor.bufferedaction:Fail()
		-- end

		--print(self.components.locomotor:GetDebugString())

		-- self.components.locomotor:SetBufferedAction(nil)
		-- self:StopUpdatingComponent(self.components.locomotor)
		-- self.components.locomotor.wantstomoveforward = false
		-- self.components.locomotor:StopMoving()

		--self.components.locomotor:Stop()
		--self.components.locomotor.dest = nil
		--self.components.locomotor:StopMoving()
	end

    -- This will kickstart the brain.
    --self:AddTag("IsStuck")

end

local function OnActionSuccess(inst,data)
   local theAction = data.action
   -- if(inst:HasTag("debugPrint")) then
   --    print("OnActionSuccess - Action: " .. theAction:__tostring())
   -- end
   -- DebugPrint(inst, "OnActionSuccess - Action: " .. theAction:__tostring())
end

local function OnActionFailed(inst,data)
 --{action = bufferedaction, reason = reason}
   local theAction = data.action
   local theReason = data.reason or "[Unknown]"
   -- if(inst:HasTag("debugPrint")) then
   --    print("OnActionFailed - Action: " .. theAction:__tostring() .. " failed. Reason: " .. tostring(theReason))
   -- end
	DebugPrint(inst, "OnActionFailed - Action: " .. theAction:__tostring() .. " failed. Reason: " .. tostring(theReason))
end


--[[
local actionNumber = 0
local function ActionDone(self, data)
	local state = data.state
	local theAction = data.theAction

	if theAction and state then
		print("Action: " .. theAction:__tostring() .. " [" .. state .. "]")
	else
		print("Action Done")
	end

	-- Cancel the DoTaskInTime for this event
	if self.currentAction ~= nil then
		self.currentAction:Cancel()
		self.currentAction=nil
	end

	-- If we're stuck on the same action (we've never pushed any new actions)...then fix it
	if state and state == "watchdog" and theAction.action.id == self.currentBufferedAction.action.id then
		print("Watchdog triggered on action " .. theAction:__tostring())
		if data.actionNum == actionNumber then
			print("We're stuck on the same action!")
		else
			print("We've queued more actions since then...")
		end
		self:RemoveTag("DoingLongAction")
		self:AddTag("IsStuck")
		-- What about calling
		-- inst:ClearBufferedAction() ??? Maybe this will work
		-- Though, if we're just running in place, this won't fix that as we're probably trying to walk over a river
		if theAction.target then
			--self.brain:AddToIgnoreList(theAction.target.entity:GetGUID()) -- Add this GUID to the ignore list
			self.components.prioritizer:AddToIgnoreList(theAction.target.entity:GetGUID()) -- Add this GUID to the ignore list
		end
	elseif state and state == "watchdog" and theAction.action.id ~= self.currentBufferedAction.action.id then
		print("Ignoring watchdog for old action")
	end

	self:RemoveTag("DoingAction")
end
--]]

-- Make him execute a 'RunAway' action to try to fix his angle?
local function FixStuckWilson(inst)
	-- Just reset the whole behaviour tree...that will get us unstuck
	inst.brain.bt:Reset()
	inst:RemoveTag("IsStuck")
	if inst.components.locomotor.isrunning then
        inst.components.locomotor:StopMoving()
    end


end

--------------------------------------------------------------------------------
-- Go home stuff

local function HasValidHome(inst)
	--
	-- local scienceMachine = FindEntity(self.inst, 150, function(item) return item.prefab and item.prefab == "researchlab" end)
	-- if scienceMachine == nil then
	-- 	return false
	-- end

	if inst.components.homeseeker and
		inst.components.homeseeker.home and
		inst.components.homeseeker.home:IsValid() then
			local dist = inst:GetDistanceSqToPoint(inst.components.homeseeker:GetHomePos())
			--print("It is " .. dist .. " distance to home")
			return (dist < 35000)
	end

	return false
end

local function GetHomePos(inst)
    return HasValidHome(inst) and inst.components.homeseeker:GetHomePos()
end


local function AtHome(inst, distance)
	-- Am I close enough to my home position?
	if not HasValidHome(inst) then return false end
	local dist = inst:GetDistanceSqToPoint(GetHomePos(inst))
	-- TODO: See if I'm next to a science machine
	--return inst.components.builder.current_prototyper ~= nil

	-- return dist <= TUNING.RESEARCH_MACHINE_DIST
	return dist <= distance
end

local function GoHomeAction(inst)
    if  HasValidHome(inst) and not AtHome(inst, TUNING.RESEARCH_MACHINE_DIST) then
         inst.components.homeseeker:GoHome(true)
    end
end

-- Should keep track of what we build so we don't have to keep checking.
local function ListenForBuild(inst,data)
	if data and data.item.prefab == "researchlab" then
		inst.components.homeseeker:SetHome(data.item)
	elseif data and inst.currentBufferedBuild and data.item.prefab == inst.currentBufferedBuild then
		print("Finished building " .. data.item.prefab)
		inst.currentBufferedBuild = nil
	end

	-- In all cases, unlock the recipe as we apparently knew how to build this
	if not inst.components.builder:KnowsRecipe(data.item.prefab) then
		print("Unlocking recipe")
		inst.components.builder:UnlockRecipe(data.item.prefab)
	end
end

-- TODO: Move this to a behaviour node
local function FindValidHome(inst)

	if not HasValidHome(inst) and inst.components.homeseeker then

		-- Reuse a nearby science machine as a home.
		local scienceMachine = FindEntity(inst, 150, function(item) return item.prefab and item.prefab == "researchlab" end)
		if scienceMachine then
			print("Found our home!")
			inst.components.homeseeker:SetHome(scienceMachine)
			return
		end


		-- TODO: How to determine a good home.
		-- For now, it's going to be the first place we build a science machine
		if inst.components.builder:CanBuild("researchlab") then
			-- Find some valid ground near us
			local machinePos = inst.brain:GetPointNearThing(inst,3)
			if machinePos ~= nil then
				print("Found a valid place to build a science machine")
				--return SetupBufferedAction(inst, BufferedAction(inst,inst,ACTIONS.BUILD,nil,machinePos,"researchlab",nil))
				local action = BufferedAction(inst,inst,ACTIONS.BUILD,nil,machinePos,"researchlab",nil)
				inst:PushBufferedAction(action)
			else
				print("Could not find a place for a science machine")
			end
		end

	end
end


-- Find somewhere interesting to go to
local function FindSomewhereNewToGo(inst)
	-- Cheating for now. Find the closest wormhole and go there. Wilson will start running
	-- then his brain will kick in and he'll hopefully find something else to do
	local wormhole = FindEntity(inst,200,function(thing) return thing.prefab and thing.prefab == "wormhole" end)
	if wormhole then
		print("Found a wormhole!")
		inst.components.locomotor:GoToEntity(wormhole,nil,true)
		--ResetSearchDistance()
	end
end

-- Returns true only if the currently equipped item isn't a light source.
local function CanWorkAtNight(inst)
	if inst.sg:HasStateTag("busy") then return false end
	return DoesEquipSlotContain(inst, EQUIPSLOTS.HANDS, "lighter")
end

local function IsBusy(inst)
	return inst.sg:HasStateTag("busy")
end


local function OnHitFcn(inst,data)
	inst.components.combat:SetTarget(data.attacker)
	-- If not PvP, call for help from nearby bots?
	if not IsPvPEnabled() then
		inst.components.combat:ShareTarget(data.attacker, 15, function(t) return t:HasTag("ArtificalWilson") end, 10, "ArtificalWilson")
	end
end

-- Used by doscience node. It expects a table returned with
-- These really should be part of the builder component...but I'm too lazy to add them there.
function ArtificalBrain:GetSomethingToBuild()
	if self.newPendingBuild and self.newPendingBuild == true then
		self.newPendingBuild = false
		return self.pendingBuildTable
	end
end

-- Returns true if prefab is still in the queue to be built
function ArtificalBrain:CheckBuildQueued(prefab)
   if self.newPendingBuild then
      return self.pendingBuildTable.prefab == prefab
   end
   return false
end

function ArtificalBrain:SetSomethingToBuild(prefab, pos, onsuccess, onfail)
	if self.pendingBuildTable == nil then
		self.pendingBuildTable = {}
	end

	-- If this is set, it means the last build we had queued never got a chance
	-- to be called. Invoke the onfail if there was one as we are overwriting this
	-- build.
	-- TODO: Move this to the prioritizer and make it a list so we can just queue
	--       the builds...
	if self.newPendingBuild and self.newPendingBuild == true then
	  if self.pendingBuildTable.onfail then
	     self.pendingBuildTable.onfail()
	  end
	end

	self.pendingBuildTable.prefab = prefab
	self.pendingBuildTable.pos = pos
	self.pendingBuildTable.onsuccess = onsuccess
	self.pendingBuildTable.onfail = onfail
	self.newPendingBuild = true
end

function ArtificalBrain:OnStop()
	print("Stopping the brain!")
	--self.inst:RemoveEventCallback("actionDone",ActionDone)
	self.inst:RemoveEventCallback("buildstructure", ListenForBuild)
	self.inst:RemoveEventCallback("builditem",ListenForBuild)
	self.inst:RemoveEventCallback("attacked", OnHitFcn)
	self.inst:RemoveEventCallback("noPathFound", OnPathFinder)
    --self.inst:RemoveEventCallback("actionsuccess", OnActionSuccess)
	self.inst:RemoveEventCallback("performaction", OnActionSuccess)
    self.inst:RemoveEventCallback("actionfailed", OnActionFailed)
	self.inst:RemoveTag("DoingLongAction")
	self.inst:RemoveTag("DoingAction")

end

-- This isn't really used...
-- but if a component wants to know if this brain
-- is loaded...just do
-- if inst.brain.IsAILoaded ~= nil then
-- ...
function ArtificalBrain:IsAILoaded()
   self.isLoaded = true
end

-- Return a buffered action
function ArtificalBrain:GoToRandomLandmark()
	if not self.inst.components.explorer then return nil end
	local pos = self.inst.components.explorer:GetRandomLocation()
	if not pos then
		DebugPrint(self.inst, "Couldn't find a random location!")
		return nil
	end

	DebugPrint(self.inst, "Going to " .. tostring(pos))

	--local action = BufferedAction(self.inst, nil, ACTIONS.TRAILBLAZE, nil, pos)
	local action = BufferedAction(self.inst, nil, ACTIONS.WALKTO, nil, pos)
	--action.overridedest = self.inst
	--local action = BufferedAction(self.inst, nil, ACTIONS.TRAILBLAZE, nil, GLOBAL.Vector3(worldX, 0, worldY))
	DebugPrint(self.inst, "Trailblazer action: " .. tostring(action))
	return action
end


function ArtificalBrain:OnStart()
	print("Artifical Wilson - OnStart called")

	--self.inst:ListenForEvent("actionDone",ActionDone)
	self.inst:ListenForEvent("buildstructure", ListenForBuild)
	self.inst:ListenForEvent("builditem", ListenForBuild)
	self.inst:ListenForEvent("attacked", OnHitFcn)
	self.inst:ListenForEvent("noPathFound", OnPathFinder)
	--self.inst:ListenForEvent("actionsuccess", OnActionSuccess)
	self.inst:ListenForEvent("performaction", OnActionSuccess)
	self.inst:ListenForEvent("actionfailed", OnActionFailed)

	-- TODO: Make this a brain function so we can manage it dynamically
	self.inst.components.prioritizer:AddToIgnoreList("seeds")
	self.inst.components.prioritizer:AddToIgnoreList("houndstooth")
	self.inst.components.prioritizer:AddToIgnoreList("petals_evil")
	self.inst.components.prioritizer:AddToIgnoreList("poop")
	if not self.inst.prefab == "waxwell" then
		self.inst.components.prioritizer:AddToIgnoreList("nightmarefuel")
	end
	self.inst.components.prioritizer:AddToIgnoreList("marsh_tree")
	self.inst.components.prioritizer:AddToIgnoreList("marsh_bush")
	self.inst.components.prioritizer:AddToIgnoreList("tallbirdegg")
	self.inst.components.prioritizer:AddToIgnoreList("pinecone")
	self.inst.components.prioritizer:AddToIgnoreList("red_cap")
	self.inst.components.prioritizer:AddToIgnoreList("green_cap")
	self.inst.components.prioritizer:AddToIgnoreList("blue_cap")
	self.inst.components.prioritizer:AddToIgnoreList("marble")
	self.inst.components.prioritizer:AddToIgnoreList("shovel")
	self.inst.components.prioritizer:AddToIgnoreList("nitre") -- Make sure to have a brain fcn add this when ready to collect it
	self.inst.components.prioritizer:AddToIgnoreList("ash")
	self.inst.components.prioritizer:AddToIgnoreList("rabbithole")
	self.inst.components.prioritizer:AddToIgnoreList("ice") -- Will need it eventually...just not soon
	self.inst.components.prioritizer:AddToIgnoreList("cave_entrance") --We're not going down...quit letting the bats out idiot!
	self.inst.components.prioritizer:AddToIgnoreList("livinglog") -- Won't need these for a while
	self.inst.components.prioritizer:AddToIgnoreList("wetgoop")
	self.inst.components.prioritizer:AddToIgnoreList("twiggy_nut")
	self.inst.components.prioritizer:AddToIgnoreList("wobster_den")
	self.inst.components.prioritizer:AddToIgnoreList("spoiled_food")
	-- TODO: Find a way to determine if these items are on land or sea rather than ignore them statically like this...
	self.inst.components.prioritizer:AddToIgnoreList("bullkelp_plant")
	self.inst.components.prioritizer:AddToIgnoreList("bullkelp_plant_leaves")
	self.inst.components.prioritizer:AddToIgnoreList("driftwood_log")
	self.inst.components.prioritizer:AddToIgnoreList("messagebottle")
	self.inst.components.prioritizer:AddToIgnoreList("seastack")
	self.inst.components.prioritizer:AddToIgnoreList("boatfragment03")
	self.inst.components.prioritizer:AddToIgnoreList("boatfragment04")
	self.inst.components.prioritizer:AddToIgnoreList("boatfragment05")
	self.inst.components.prioritizer:AddToIgnoreList("saltstack")
	self.inst.components.prioritizer:AddToIgnoreList("moonrocknugget")
	self.inst.components.prioritizer:AddToIgnoreList("stinger")
	self.inst.components.prioritizer:AddToIgnoreList("feather_crow")
	self.inst.components.prioritizer:AddToIgnoreList("feather_robin")
	self.inst.components.prioritizer:AddToIgnoreList("feather_robin_winter")
	self.inst.components.prioritizer:AddToIgnoreList("nightmarefuel")
	self.inst.components.prioritizer:AddToIgnoreList("bugnet")
	self.inst.components.prioritizer:AddToIgnoreList("beemine")
	self.inst.components.prioritizer:AddToIgnoreList("trap")
	self.inst.components.prioritizer:AddToIgnoreList("fishingrod")
	self.inst.components.prioritizer:AddToIgnoreList("silk")

	if self.inst.prefab == "wathgrithr" then
		ATTACK_DIST = 15
		self.inst.components.prioritizer:AddToIgnoreList("berries")
		self.inst.components.prioritizer:AddToIgnoreList("berries_juicy")
		self.inst.components.prioritizer:AddToIgnoreList("carrot")
		self.inst.components.prioritizer:AddToIgnoreList("butterflywings")
		self.inst.components.prioritizer:AddToIgnoreList("acorn")
		self.inst.components.prioritizer:AddToIgnoreList("acorn_cooked")
	end

	-- If we don't have a home, find a science machine nearby to call home.
	if not HasValidHome(self.inst) then
		local scienceMachine = FindEntity(self.inst, 150, function(item) return item.prefab and item.prefab == "researchlab" end)
		if scienceMachine then
			print("Found our home!")
			self.inst.components.homeseeker:SetHome(scienceMachine)
		end
	end

	-- Things to do during the day
	local day = WhileNode( function() return IsDay() end, "IsDay",
		PriorityNode{

			-- Eat something if hunger gets below .5
			ManageHunger(self.inst, .5),

			-- If there's a touchstone nearby, activate it
			-- TODO: This doesn't make sense for dst unless we're a ghost.
			--       Sooo, add it to the IfNode maybe.
			--IfNode(function() return not IsBusy(self.inst) end, "notBusy_lookforTouchstone",
			--	FindAndActivate(self.inst, 25, "resurrectionstone")),

			-- If dead, all you can really do is look for a touchstone
			IfNode(function() return self.inst:HasTag("playerghost") end, "dead_lookforTouchstone",
				FindAndActivate(self.inst, 120, "resurrectionstone")),

			-- Find a good place to call home
			IfNode( function() return not HasValidHome(self.inst) end, "no home",
				DoAction(self.inst, function() return FindValidHome(self.inst) end, "looking for home", true)),

			Investigate(self.inst),
			--ManageTraps(self.inst),

			PriorityNode( {
			   ManageTraps(self.inst)
			},1),

			-- Collect stuff
			SelectorNode{
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
					FindResourceOnGround(self.inst, function() return self:GetCurrentSearchDistance() end)),
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goHarvest",
					FindResourceToHarvest(self.inst,  function() return self:GetCurrentSearchDistance() end)),
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goChop",
					FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.CHOP)),
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goMine",
					FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.MINE)),
				-- IfNode( function() return not IsBusy(self.inst) end, "notBusy_goSmash",
				-- 	FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.HAMMER)),
		      -- Should maybe stick around and wait for this thing to finish burning...he just
				-- kind of runs away...
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goBurn",
					FindThingToBurn(self.inst, function() return self:GetCurrentSearchDistance() end)),

				-- Finally, if none of those succeed, increase the search distance for
				-- the next loop.
				-- Want this to fail always so we don't increase to max.
				IfNode( function() return not IsBusy(self.inst) end, "nothing_to_do",
					NotDecorator(ActionNode(function() return self:IncreaseSearchDistance() end))),
			},

			-- TODO: Need a good wander function for when searchdistance is at max.
			-- IfNode(function() return not IsBusy(self.inst) and self:GetCurrentSearchDistance() >= MAX_SEARCH_DISTANCE end, "maxSearchDistance",
			-- 	FindAndActivate(self.inst, 500, "wormhole")),

			IfNode(function() return not IsBusy(self.inst) and self:GetCurrentSearchDistance() >= MAX_SEARCH_DISTANCE end, "lost_go_explore",
				DoAction(self.inst, function() return self:GoToRandomLandmark() end, "goExplore", true, 15)),

			IfNode(function() return not IsBusy(self.inst) and self:GetCurrentSearchDistance() >= MAX_SEARCH_DISTANCE end, "maxSearchDistance",
			  	FindAndActivate(self.inst, 500, "wormhole")),

				-- local function GoHomeAction(inst)
				-- 	return inst.components.homeseeker ~= nil
				-- 		and inst.components.homeseeker.home ~= nil
				-- 		and inst.components.homeseeker.home:IsValid()
				-- 		and inst.components.homeseeker.home.components.childspawner ~= nil
				-- 		and not inst.components.teamattacker.inteam
				-- 		and BufferedAction(inst, inst.components.homeseeker.home, ACTIONS.GOHOME)
				-- 		or nil
				-- end

		},.25)


	-- Do this stuff the first half of duck (or all of dusk if we don't have a home yet)
	local dusk = WhileNode( function() return IsDusk() and (not AlmostNight() or not HasValidHome(self.inst)) end, "IsDusk",
        PriorityNode{

			CookFood(self.inst,10),
			-- Make sure we eat. During the day, only make sure to stay above 50% hunger.
			ManageHunger(self.inst,.5),

			-- Find a good place to call home
			IfNode( function() return not HasValidHome(self.inst) end, "no home",
				DoAction(self.inst, function() return FindValidHome(self.inst) end, "looking for home", true)),

			Investigate(self.inst),
			--ManageTraps(self.inst),
			PriorityNode( {
			   ManageTraps(self.inst)
			},1),

			SelectorNode{

				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
					FindResourceOnGround(self.inst,  function() return self:GetCurrentSearchDistance() end)),

				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goChop",
					FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.CHOP)),

				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goHarvest",
					FindResourceToHarvest(self.inst,  function() return self:GetCurrentSearchDistance() end)),

				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goMine",
					FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.MINE)),

				-- IfNode( function() return not IsBusy(self.inst) end, "notBusy_goSmash",
				-- 	FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.HAMMER)),

				IfNode( function() return not IsBusy(self.inst) end, "nothing_to_do",
					NotDecorator(ActionNode(function() return self:IncreaseSearchDistance() end))),
			},

			-- This is super hacky.
			--IfNode(function() return not IsBusy(self.inst) and CurrentSearchDistance == MAX_SEARCH_DISTANCE end, "maxSearchDistance",
			--	DoAction(self.inst, function() return FindSomewhereNewToGo(self.inst) end, "lookingForSomewhere", true)),
			IfNode(function() return not IsBusy(self.inst) and self:GetCurrentSearchDistance() >= MAX_SEARCH_DISTANCE end, "maxSearchDistance",
				DoAction(self.inst, function() return self:GoToRandomLandmark() end, "goExplore", true, 15)),

			IfNode(function() return not IsBusy(self.inst) and self:GetCurrentSearchDistance() >= MAX_SEARCH_DISTANCE end, "maxSearchDistance",
			  	FindAndActivate(self.inst, 300, "wormhole")),
			-- No plan...just walking around
			--Wander(self.inst, nil, 20),
        },.2)

		-- Behave slightly different half way through dusk
		local dusk2 = WhileNode( function() return IsDusk() and AlmostNight() and HasValidHome(self.inst) end, "IsDusk2",
			PriorityNode{

			CookFood(self.inst,15),
			--IfNode( function() return not IsBusy(self.inst) and  self.inst.components.hunger:GetPercent() < .5 end, "notBusy_hungry",
			--	DoAction(self.inst, function() return HaveASnack(self.inst) end, "eating", true )),
			ManageHunger(self.inst,.5),

			IfNode( function() return HasValidHome(self.inst) end, "try to go home",
				DoAction(self.inst, function() return GoHomeAction(self.inst) end, "go home", true)),

			-- If we don't have a home, go about our business I guess
			-- SelectorNode{

			-- 	IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
			-- 		FindResourceOnGround(self.inst,  function() return self:GetCurrentSearchDistance() end)),

			-- 	IfNode( function() return not IsBusy(self.inst) end, "notBusy_goChop",
			-- 		FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.CHOP)),

			-- 	IfNode( function() return not IsBusy(self.inst) end, "notBusy_goHarvest",
			-- 		FindResourceToHarvest(self.inst,  function() return self:GetCurrentSearchDistance() end)),

			-- 	IfNode( function() return not IsBusy(self.inst) end, "notBusy_goMine",
			-- 		FindTreeOrRock(self.inst,  function() return self:GetCurrentSearchDistance() end, ACTIONS.MINE)),

			-- 	IfNode( function() return not IsBusy(self.inst) end, "nothing_to_do",
			-- 		NotDecorator(ActionNode(function() return self:IncreaseSearchDistance() end))),
			-- },

			-- If we don't have a home...just
				--IfNode( function() return AtHome(self.inst, 4) end, "am home",
				--	DoAction(self.inst, function() return BuildStuffAtHome(self.inst) end, "build stuff", true)),

				-- If we don't have a home, make a camp somewhere
				--IfNode( function() return not HasValidHome(self.inst) end, "no home to go",
				--	DoAction(self.inst, function() return true end, "make temp camp", true)),

				-- If we're home (or at our temp camp) start cooking some food.


		},.25)

	local night = WhileNode( function() return IsNight() end, "IsNight",
        PriorityNode{
			-- TODO: If we aren't home but we have a home, make a torch and keep running!

			CookFood(self.inst,25),

			-- Eat more at night
			ManageHunger(self.inst,.9),

			-- Collect stuff nearby.
			SelectorNode{
				-- Can pickup from ground with a torch
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goPickup",
					FindResourceOnGround(self.inst, function() return 5 end)),
				-- Can harvest with a torch
				IfNode( function() return not IsBusy(self.inst) end, "notBusy_goHarvest",
					FindResourceToHarvest(self.inst,  function() return 5 end)),
				-- Do not try to chop or mine if holding a light source in hand slot.
				IfNode( function() return not CanWorkAtNight(self.inst) end, "notBusy_goChop",
					FindTreeOrRock(self.inst,  function() return 5 end, ACTIONS.CHOP)),
				IfNode( function() return not CanWorkAtNight(self.inst) end, "notBusy_goMine",
					FindTreeOrRock(self.inst,  function() return 5 end, ACTIONS.MINE))
			},

        },.5)

	-- Taken from wilsonbrain.lua
	local RUN_THRESH = 4.5
	local MAX_CHASE_TIME = 5
	local nonAIMode = PriorityNode(
    {
    	WhileNode(function() return TheInput:IsControlPressed(CONTROL_PRIMARY) end, "Hold LMB", ChaseAndAttack(self.inst, MAX_CHASE_TIME)),
    	ChaseAndAttack(self.inst, MAX_CHASE_TIME, nil, 1),
    },0)

	local root =
        PriorityNode(
        {
			-- If any brain function decides necessary, it can add an IsStuck tag to wilson. This will cause the brain to reset.
			IfNode( function() return self.inst:HasTag("IsStuck") end, "stuck",
				DoAction(self.inst,function()
					print("Trying to fix this...")
					-- Skip ahead in search distance
					self.currentSearchDistance = 55
					return FixStuckWilson(self.inst)
				end, "alive3",true)),

			Watchdog(self.inst),

			-- -- If dead, all you can really do is look for a touchstone
			-- IfNode(function() return self.inst:HasTag("playerghost") end, "dead_lookforTouchstone",
			--  	FindAndActivate(self.inst, 120, "resurrectionstone")),

			-- If we ever get something in our overflow slot in the inventory, drop it.
			-- This will happen occationally if we try to build something we can't hold...etc.
			IfNode(function() return self.inst.components.inventory.activeitem ~= nil end, "drop_activeItem",
				DoAction(self.inst,function() local inv = self.inst.components.inventory
               				     local item = inv:GetActiveItem()
               				     if item then
               				        inv:DropItem(item,true,true)
                                end
                             end, "drop",true)),

			-- Quit standing in the fire, idiot
			--WhileNode(function() return self.inst.components.health.takingfiredamage end, "OnFire", Panic(self.inst) ),
			DontBeOnFire(self.inst),

			-- Should also check if it's dark for some other reason.
			-- Maybe also check the moon phase for full moon...
			WhileNode(function() return TimeToFindLight() end, "StayInTheLight",
			   MaintainLightSource(self.inst, 30)),

			--DodgeProjectile(self.inst),
			Revenge(self.inst),

			-- Determines if/when to fight something. This should remain above the
			-- RunAway node so we don't run from things we want to fight until
			-- necessary...
			KiteMaster(self.inst, ATTACK_DIST, 3, neverfight, canttags, fight),

			-- Should move that run_from function to just be inside the behavior...
			CustomRunAway(self.inst,
							function(myself)
								local run_from =
									FindEntity(myself, 15,
										function(guy)
											-- Ignoring distance, is this something we should even run from?
											local should_run = ShouldRunAway(guy, myself)
											if not should_run then
												return false
											end

											if guy.prefab == "wasphive" then return true end

											-- Check for long range things to avoid
											for _,v in pairs(longrangetags) do
												if guy:HasTag(v) then
													return true
												end
											end

											-- Otherwise, only check for close things.
											local pt = Point(self.inst.Transform:GetWorldPosition())
											local hp = Point(guy.Transform:GetWorldPosition())

											if distsq(hp, pt) > RUN_AWAY_SEE_DIST*RUN_AWAY_SEE_DIST then
												return false
											end

											return should_run
										end, nil, canttags)
								return run_from
						end, RUN_AWAY_SEE_DIST, RUN_AWAY_STOP_DIST, willfightback, canttags, longrangetags),

			-- Manage all things clothing (armor is managed by fighting node)
			ManageClothes(self.inst),

			-- TODO: How to allow Kitemaster and runaway the ability to manage ghost aggression all the way here?
			--       Don't want wendy to not flee when trying to summon ghost or change aggression level...
			IfNode(function() return not IsBusy(self.inst) and self.inst.prefab == "wendy" end, "notBusy_managesummons",
				ManageSummons(self.inst)),

			-- If maxwell, do maxwell type things.
			-- IfNode(function() return not IsBusy(self.inst) and self.inst.prefab == "waxwell" end, "notBusy_makefriends",
			-- 	Maxwell(self.inst)),

			-- Try to stay healthy
			IfNode(function() return not IsBusy(self.inst) end, "notBusy_heal",
				ManageHealth(self.inst,.9)),

			-- TODO: Supply a dynamic sanity function here so wilson tries to stay within the range
			IfNode(function() return not IsBusy(self.inst) end, "notBusy_sanity",
			   ManageSanity(self.inst, .9, .6)),

			-- Shoot things
			--SnipeMaster(self.inst, 15, {"prey", "butterfly", "bird"}, {"koalefant"}),

			-- TODO: Work in progress....
			-- IfNode(function() return not IsBusy(self.inst) end, "notBusy_trade",
			-- 	Socialism(self.inst)),


			-- Hunger is managed during the days/nights

			-- Prototype things whenever we get a chance
			-- Home is defined as our science machine...
			--IfNode(function() return not IsBusy(self.inst) and AtHome(self.inst) and not self.inst.currentBufferedBuild end, "atHome",
			--	DoAction(self.inst, function() return PrototypeStuff(self.inst) end, "Prototype", true)),

			-- If near a science machine, wilson will prototype stuff!
			-- Otherwise, if anything is set in the buildtable, this node will build it.
			DoScience(self.inst, function() return self:GetSomethingToBuild() end),

			-- Only do these things not very often
			PriorityNode( {
			   MasterChef(self.inst),
			   ManageInventory(self.inst),
			},2.5),



			day,
			dusk,
			dusk2,
			night

        }, .25)

    self.bt = BT(self.inst, root)
end

return ArtificalBrain