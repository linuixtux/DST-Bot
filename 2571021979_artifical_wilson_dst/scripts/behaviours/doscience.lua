require "brains/ai_build_helper"

local TechTree = require("techtree")

-- getBuildFn should return a table with the following
--    thingToBuild
--    pos or nil
--    onsuccess or nil
--    onfail or nil
-- Finally, the getBuildFn should clear the return value so it is nil next pass.
DoScience = Class(BehaviourNode, function(self, inst, getBuildFn)
    BehaviourNode._ctor(self, "DoScience")
    self.inst = inst
	self.getThingToBuildFn = getBuildFn
	self.bufferedBuildList = nil
	self.buildStatus = nil
	self.waitingForBuild = nil

	-- Updated from a listenEvent for when we stand next to a prototyper.
	-- This is an array of ALL tech trees we have available at the moment,
	-- as well as their current level.
	-- i.e. SCIENCE can have 3 levels....magic can be lvl 2 or lvl 3, etc.
	-- We don't really care what level we're at here. All we are doing is
	-- listening for a CHANGE in techtrees. When a change happens, we can run
	-- through all things we want to build and see if we can prototype it.

	-- Once something is prototyped, we don't care about tech tree levels anymore.
	self.currentTechLevel = deepcopy(TECH.NONE)

	-- Is set when the final build is complete
	self.onSuccess = function()
		self.buildStatus = SUCCESS
		if self.buildTable and self.buildTable.onsuccess then
			self.buildTable.onsuccess()
		end
	end

	self.onFail = function()
		self.buildStatus = FAILED
		if self.buildTable and self.buildTable.onfail then
			self.buildTable.onfail()
		end
	end


	self.techTreeChangedFn = function(inst, data)
		-- Data looks to be 'level', which should be the machine we are closest to.
		-- This means we'll have to make the bot go walk to each one to see if they
		-- can build something.
		-- It also means we can do a single pass to prototype everything we need.
		self:DebugPrint("Got Tech Tree Changed Callback!")

		if data.level ~= nil then
			self:DebugPrint("Data: " .. tostring(data))
			self.currentTechLevel = data.level
		else
			self:DebugPrint("Data was nil???")
		end
	end

	-- Pushed from "Builder" component whenever a tech tree changes.
	-- This 'might' be when we enter range, leave range, stand next to another, etc.
	self.inst:ListenForEvent("techtreechange", self.techTreeChangedFn)
end)

function DoScience:DebugPrint(string)
	DebugPrint(self.inst, tostring(string))
end

function DoScience:PushNextAction()


	if self.bufferedBuildList then
		-- Grab the action and remove it from the list
		local action = table.remove(self.bufferedBuildList,1)

		if not action then
			self:DebugPrint("PushNextAction: action empty")
			-- The list is empty.
			self.buildListEmpty = true
			return
		end

		self:DebugPrint("PushNextAction: " .. action:__tostring())


      	-- Have the buffered action schedule the next one
		action:AddSuccessAction(function() self.inst:DoTaskInTime(.2,self:PushNextAction()) end)
		self.waitingForBuild = true

		---- DST - use preview action
		self.inst.components.locomotor:PushAction(action, true)
		--self.inst.components.locomotor:PreviewAction(action, true)

		--print("PushNextAction: done")
	end
end

-- This is the order to build things.
local BUILD_PRIORITY = {
		"spear",
		"backpack",
		"firepit",
		"cookpot",
		"researchlab2",
		"tophat",
		"footballhat",
		"icebox"
}

-- The BUILD_PRIORITY contains the index into the build info table
-- which stores the important info. Otherwise you cannot control
-- the table ordering.
-- Not all builds need build_info populated. This table will just contain
-- extra info for the build, like position to build it.
-- example entry would be:
-- "spear" = {pos=nil, someValue=x, otherInfo=y}
-- then you would loop over BUILD_PRIORITY and use that
-- index to get the build_info
local build_info = { }



-- What I want this to do:
-- This node should just keep track of prototyping things.
-- Other nodes can push requests for what to prototype, and we'll do it when
-- we can.
-- What should happen:
--
function DoScience:Visit()

    if self.status == READY then
		-- These things should not exist in the READY state. Clear them
		self.buildListEmpty = nil
		self.buildStatus = nil
		self.bufferedBuildList = nil
		self.waitingForBuild = nil
		self.buildTable = nil

		-- Any node can push a request to the brain to have something built.
		-- Only problem with this is....that node either better not go to the
		-- running state, or it better be a lower priority.

		-- Some other nodes has something they want built.
		if self.getThingToBuildFn ~= nil then
			self.buildTable = self.getThingToBuildFn()

			if self.buildTable and self.buildTable.prefab then
				local toBuild = self.buildTable.prefab
				--local recipe = GetRecipe(toBuild)
				--local recipe = GetValidRecipe(toBuild)
				local recipe = GetRecipeCommon(toBuild)

				if not recipe then
					self:DebugPrint("Cannot build " .. toBuild .. " as it doesn't have a recipe")
					if self.buildTable.onfail then
						self.buildTable.onfail()
					end
					self.status = FAILED
					return
				else
					if not self.inst.components.builder:KnowsRecipe(toBuild) then
						-- Add it to the prototype list.
						if BUILD_PRIORITY[toBuild] == nil then
							self:DebugPrint("Don't know how to build " .. toBuild .. "...adding to build table")
							table.insert(BUILD_PRIORITY,1,toBuild)
							build_info[toBuild] = {pos=self.buildTable.pos}
							--local build_info = {pos=self.buildTable.pos, onsuccess=self.buildTable.onsuccess, onfail=self.buildTable.onfail}
							--self.inst.components.prioritizer:AddToBuildList(toBuild,build_info)
						end
						if self.buildTable.onfail then
							self.buildTable.onfail()
						end
						self.status = FAILED
						return
					else
						-- We know HOW to craft it. Can we craft it?
						if CanPlayerBuildThis(self.inst,toBuild) then
							self.bufferedBuildList = GenerateBufferedBuildOrder(self.inst,toBuild,self.buildTable.pos,self.onSuccess, self.onFail)
							-- We apparnetly know how to make this thing. Let's try!
							if self.bufferedBuildList ~= nil then
								self:DebugPrint("Attempting to build " .. toBuild)
								self.status = RUNNING
								self:PushNextAction()
								return
							end
						else
							-- Don't have enough resources to build this.
							self:DebugPrint("Don't have enough resources to make " .. toBuild)
							if self.buildTable.onfail then
								self.buildTable.onfail()
							end
							self.status = FAILED
							return
						end
					end
				end
			end
			-- If buildThing doesn't return something, just do our normal stuff.
		end

		local prototyper = self.inst.components.builder.current_prototyper;
		if not prototyper then
			--print("Not by a science machine...nothing to do")
			self.status = FAILED
			return
		end

		--print("Standing next to " .. prototyper.prefab .. " ...what can I build...")

		local tech_level = self.inst.components.builder.accessible_tech_trees
		local currentTime = GetTime()
		for k,v in pairs(BUILD_PRIORITY) do
			-- Looking for things we can prototype
			--local recipe = GetValidRecipe(v) --GetRecipe(v)
			local recipe = GetRecipeCommon(v)

			-- If not nil, will contain useful info like 'where' to build this now
			if not build_info[v] then
				build_info[v] = {}
			end
			local buildinfo = build_info[v]

			local check_build = true
			if buildinfo ~= nil and buildinfo.lastCheckTime ~= nil then
				if currentTime - buildinfo.lastCheckTime < 60 then
					--self:DebugPrint("Not checking " .. tostring(v) .. " again so soon")
					check_build = false
				end
			end

			if buildinfo ~= nil then
				buildinfo.lastCheckTime = currentTime
			end

			-- This node only cares about things to prototype. If we know the recipe,
			-- ignore it.
			if check_build and not self.inst.components.builder:KnowsRecipe(v) then

				-- Will check our inventory for all items needed to build this
				if CanPrototypeRecipe(recipe.level,tech_level) and CanPlayerBuildThis(self.inst,v) then
					-- Will push the buffered event to build this thing
					local pos = buildinfo and buildinfo.pos or self.inst.brain:GetPointNearThing(self.inst,5)--Vector3(self.inst.Transform:GetWorldPosition())
					self.bufferedBuildList = GenerateBufferedBuildOrder(self.inst,v,pos,self.onSuccess, self.onFail)
					-- We apparnetly know how to make this thing. Let's try!
					if self.bufferedBuildList ~= nil then
						self:DebugPrint("Attempting to build " .. v)
						self.status = RUNNING
						self:PushNextAction()
						return
					end
				end
			end -- end KnowsRecipe
			-- Don't know how to build this. Check the next thing
		end
		-- Either list is empty or we can't building anything. Nothing to do
		--print("There's nothing we know how to build")
		self.status = FAILED
		return

    elseif self.status == RUNNING then
		if self.waitingForBuild then

			-- If this is set, the buffered list is done (either by error or successfully).
			-- Nothing left to do.
			if self.buildStatus then
				self:DebugPrint("Build status has returned : " .. tostring(self.buildStatus))
				self.status = self.buildStatus
				return
			end

			-- We tried to schedule the next command and it was empty.
			if self.buildListEmpty then
				-- If this isn't set, something is really messed up.
				if not self.buildStatus then
					self:DebugPrint("Something went wrong!")
					self.status = FAILED
					return
				end
			end

			-- If our current buffered action is nil and we are in the idle state...something
			-- interrupted us. Just leave the node!
         if self.inst:GetBufferedAction() == nil and self.inst.sg:HasStateTag("idle") then
            self:DebugPrint("DoScience: SG: ---------- \n " .. tostring(self.inst.sg))
            self.status = FAILED
            return
         end

			-- Waiting for the build to complete
			--print("Waiting for current build action to complete")
			self.status = RUNNING
			return
		end

	end
end