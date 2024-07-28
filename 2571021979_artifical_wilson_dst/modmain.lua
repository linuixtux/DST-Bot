local function IsDST()
    return GLOBAL.TheSim:GetGameID() == "DST"
end

local function GetWorld()
    if IsDST() then
        return GLOBAL.TheWorld
    else
        return GLOBAL.GetWorld()
    end
end

local function AddPlayerPostInit(fn)
	if IsDST() then
		env.AddPrefabPostInit("world", function(wrld)
			-- wrld:ListenForEvent("playeractivated", function(wrld, player)
			-- 	print("PLAYER ACTIVATED")
			-- 	print(tostring(wrld))
			-- 	print(tostring(player))
			-- 	print(tostring(GLOBAL.ThePlayer))
			-- 	if player == GLOBAL.ThePlayer or GLOBAL.TheWorld.ismastersim then
			-- 		print("New Player: " .. tostring(player))
			-- 		fn(player)
			-- 	end
			-- end)

			-- Wait for the network to set the player owner.
			local onSetOwner = function(player)
				print("onSetOwner called for " .. tostring(player))
				if player == GLOBAL.ThePlayer then
					print("Player == GLOBAL.ThePlayer")
					fn(player)
				elseif GLOBAL.TheWorld.ismastersim then
					print("Is Master Sim")
					fn(player)
				end
			end

			wrld:ListenForEvent("ms_playerspawn", function(wrld, player)
				-- print("player spawned: " .. tostring(player))
				-- print(tostring(wrld))
				-- print("Is Master Sim " .. tostring(GLOBAL.TheWorld.ismastersim))
				-- if player == GLOBAL.ThePlayer or GLOBAL.TheWorld.ismastersim then
				-- 	--print("Master sim - calling post init fn")
				-- 	fn(player)
				-- 	print("DONE")
				-- else
				-- 	print("Not player or NOT MASTER SIM...")
				-- end
				player:ListenForEvent("setowner", onSetOwner)
			end)
		end)
	else
		env.AddPlayerPostInit(function(player)
			fn(player)
		end)
	end
end

--local ArtificalWilsonEnabled = false
local DebugTag = "AIDebugPrint"

Assets = {
    Asset("IMAGE", "images/map_circle.tex"),
    Asset("ATLAS", "images/map_circle.xml"),
}

AddMinimapAtlas("images/map_circle.xml")

-- Stole this from flingomatic range check mod...
PrefabFiles =
{
   "range"
}


AddBrainPostInit("artificalwilson",ArtificalWilson)

AddModRPCHandler(modname, "SetSelfAI", function(player)
    if player then
		print("Enabling Artificial Wilson")

		--player:AddTag("AIDebugPrint")
		local brain = GLOBAL.require "brains/artificalwilson"

		if not player.components.basebuilder then
			player:AddComponent("basebuilder")
		end
		if not player.components.follower then
			player:AddComponent("follower")
		end
		if not player.components.homeseeker then
			player:AddComponent("homeseeker")
		end
		if not player.components.chef then
			player:AddComponent("chef")
		end
		if not player.components.prioritizer then
			player:AddComponent("prioritizer")
		end
		if not player.components.explorer then
			player:AddComponent("explorer")
		end

		local godmode = GetModConfigData("CheatMode") or nil
		if godmode== "enabled" and not player.components.blinkstaff then
			player:AddComponent("blinkstaff")
			player.components.blinkstaff:SetFX("sand_puff_large_front", "sand_puff_large_back")
			--player.components.blinkstaff.onblinkfn = onblink
		end


		if not player:HasTag("ArtificalWilson") then
			player:AddTag("ArtificalWilson")
		end

		local function isPlayerAdmin(player)	
			for k, v in pairs(GLOBAL.TheNet:GetClientTable()) do		
				if v.userid == player.userid then
					return true
				end
			end
			return false
		end

		local loglevel = GetModConfigData("LogLevel") or nil
		if loglevel ~= nil and loglevel ~= "none" and isPlayerAdmin(player) then
			print("Adding debug tag to admin player: " .. tostring(player))
			player:AddTag(loglevel)
		end

		player:SetBrain(brain)
		player:RestartBrain()
		player.components.talker:Say("Systems enabled")
    end
end)

AddModRPCHandler(modname, "SetSelfNormal", function(player)
	if player then
		print("Disabling Artificial Wilson")
		local brain = GLOBAL.require "brains/wilsonbrain"
		player:SetBrain(brain)
		player:RestartBrain()

		if player:HasTag("ArtificalWilson") then
			player:RemoveTag("ArtificalWilson")
		end

		player.components.talker:Say("Manual Override Enabled")
	end
end)

local AddCloneSpawner = function(player)

	print("AddCloneSpwner for " .. tostring(player))
	local max_per_player = GetModConfigData("MaxClones") or 15
	print("Max Clones Per Player: " .. tostring(max_per_player))


	local revengemode = GetModConfigData("Revenge")
	if revengemode == "enabled" then
		player:AddTag("revengeMode")
		if not player.components.blinkstaff then
			player:AddComponent("blinkstaff")
			player.components.blinkstaff:SetFX("sand_puff_large_front", "sand_puff_large_back")
		end
	end

	if player.components.childspawner == nil then
		local username = player.Network:GetClientName()
		print("Adding spawner component")
		player:AddComponent("childspawner")
		player.components.childspawner.childname = "wilson" -- Default name if none provided
		player.components.childspawner:SetMaxChildren(max_per_player)
		player.components.childspawner.OnUpdate = function(self, dt) 
			local missing = self.maxchildren - (self.childreninside + self.numchildrenoutside)
			if missing > 0 then
				self:AddChildrenInside(missing)
			end
			return 
		end 
		player.components.childspawner.spawnoffscreen = true

		-- What to do when a clone dies
		local cloneDied = function(player, child)
			--print("Clone died: " .. tostring(child))

			local cloneDeath = GetModConfigData("CloneDeath")

			if child and cloneDeath == "remove" then

				-- Give it time to die, drop inventory, etc.
				player:DoTaskInTime(5, function()
					if child:IsValid() then
						child:Remove()
					end
				end)
			end

			if not player.components.childspawner:IsFull() then
				player.components.childspawner:AddChildrenInside(1)
			end

		end

		player.components.childspawner:SetOnChildKilledFn(cloneDied)

		-- Callback for when the child is spawned
		local spawnchildfn = function(spawner, child)
			if spawner.spawned_clones == nil then
				spawner.spawned_clones = {}
			end

			if child.components.skinner ~= nil and GLOBAL.IsRestrictedCharacter(child.prefab) then
				child.components.skinner:SetSkinMode("normal_skin")
			end

			--local x, y, z = child.Transform:GetWorldPosition()
      	--GLOBAL.SpawnPrefab("wortox_portal_jumpin_fx").Transform:SetPosition(x, y, z)

			-- The the server to keep the brain running at all times
			child.entity:SetCanSleep(false)

			local ex_fns = GLOBAL.require "prefabs/player_common_extensions"
			local inv_item_list = (GLOBAL.TUNING.GAMEMODE_STARTING_ITEMS[GLOBAL.TheNet:GetServerGameMode()] or GLOBAL.TUNING.GAMEMODE_STARTING_ITEMS.DEFAULT)[string.upper(child.prefab)]
			ex_fns.GivePlayerStartingItems(child, inv_item_list, {})

			child:AddTag("AIClone")
			child.clone_parent = spawner

			local brain = GLOBAL.require "brains/artificalwilson"
			if not child.components.follower then
				child:AddComponent("follower")
			end
			if not child.components.homeseeker then
				child:AddComponent("homeseeker")
			end
			if not child.components.chef then
				child:AddComponent("chef")
			end
			if not child.components.prioritizer then
				child:AddComponent("prioritizer")
			end

			if not child:HasTag("ArtificalWilson") then
				child:AddTag("ArtificalWilson")
			end

			-- This might tell the server to keep the area around this thing alive
			if not child.components.areaaware then
				child:AddComponent("areaaware")
				child.components.areaaware:SetUpdateDist(.45)
			end


			child:AddComponent("named")
			--friend.components.named.possiblenames = GLOBAL.STRINGS.PIGNAMES
			local names = {}
			for k,v in ipairs(GLOBAL.STRINGS.PIGNAMES) do
				v = v .. " (" .. username .. ")"
				table.insert(names, v)
			end
			child.components.named.possiblenames = names
			child.components.named:PickNewName()

			-- Remove their OnLongUpdate function for hunger and sanity for now so when
			-- the game reloads them (player gets close) they don't just die
			if child.components.hunger then
				child.components.hunger.LongUpdate = function(dt) return end
			end

			if child.components.sanity then
				child.components.sanity.LongUpdate = function(dt) return end
			end

			child:SetBrain(brain)
			child:RestartBrain()
			table.insert(spawner.spawned_clones, child)

			-- player_common says "handled in a special way". But this way doesn't seem to work for
			-- spawned friends....

			-- OK, they persist! But they don't come back as AI....
			--child.persists = true
		end

		player.components.childspawner:SetSpawnedFn(spawnchildfn)
		-- As fun as it is to be home, don't make me their home. They have to find their own home...
		player.components.childspawner:SetOnTakeOwnershipFn(function(spawner, child) child.components.homeseeker:SetHome(nil) end)

	end

	-- local currentSave = player.OnSave

	-- player.OnSave = function(inst, data)
	-- 	print("Player - OnSave called!!")
	-- 	currentSave(inst, data)
	-- 	data.ai_enabled = player:HasTag("ArtificalWilson")
	-- end

end

AddModRPCHandler(modname, "SpawnClone", function(player)
	if player then
		print("Spawning a clone")
		local username = player.Network:GetClientName()

		-- TODO: These should be here!??!?!
		if not player.components.childspawner then
			print("Player: " .. tostring(player) .. " is missing childspawner component")
			AddCloneSpawner(player)
		end

		if not player.components.basebuilder then
			player:AddComponent("basebuilder")
		end

		if not player.components.explorer then
			player:AddComponent("explorer")
		end

		local godmode = GetModConfigData("CheatMode") or nil
		if godmode == "enabled" and not player.components.blinkstaff then
			player:AddComponent("blinkstaff")
			player.components.blinkstaff:SetFX("sand_puff_large_front", "sand_puff_large_back")
			--player.components.blinkstaff.onblinkfn = onblink
		end

		--local max_per_player = GetModConfigData("MaxClones") or 15
		--print("Max Clones Per Player: " .. tostring(max_per_player))

		local clonetype = GetModConfigData("CloneType")
		local random_prefab = player.prefab

		if clonetype == "clone" then
			random_prefab = player.prefab
		elseif clonetype == "random" then
			-- Pick a random character to spawn
			local valid_chars = GLOBAL.ExceptionArrays(GLOBAL.DST_CHARACTERLIST, GLOBAL.MODCHARACTEREXCEPTIONS_DST)
			random_prefab = valid_chars[math.random(#valid_chars)]
		else
			random_prefab = clonetype
		end

		-- Make a new friend!
		if player.components.childspawner.numchildrenoutside >= player.components.childspawner.maxchildren then
			player.components.talker:Say("Clone Limit Reached!")
			print("Total Children: " .. tostring(player.components.childspawner:NumChildren()))
		else
			player.components.childspawner:SpawnChild(nil, random_prefab)
		end

	end
end)

local function MakeClickableBrain(self, owner)

	local BrainBadge = self
   BrainBadge:SetClickable(true)

    -- Make the brain pulse for a cool effect
	local x = 0
	local darker = true
	local function BrainPulse(self)
		if not darker then
			x = x+.1
			if x >=1 then
				darker = true
				x = 1
			end
		else
			x = x-.1
			if x <=.5 then
				darker = false
				x = .5
			end
		end

		BrainBadge.anim:GetAnimState():SetMultColour(x,x,x,1)
		self.BrainPulse = self:DoTaskInTime(.15, BrainPulse)
	end

	BrainBadge.OnMouseButton = function(self,button,down,x,y)
		if button == 1001 and down == true then
			print("Spawning a clone")
			SendModRPCToServer(MOD_RPC[modname]["SpawnClone"])
			return
		end
		if down == true then
			if owner == nil then
				print("No owner? Trying ThePlayer")
				if GLOBAL.ThePlayer == nil then
					print("No owner and no ThePlayer?!?!?")
					print("Not sure what to do...")
					return
				else
					owner = GLOBAL.ThePlayer
				end
			end
			if owner:HasTag("ArtificalWilson") then
				owner.BrainPulse:Cancel()
				BrainBadge.anim:GetAnimState():SetMultColour(1,1,1,1)

				if GLOBAL.Profile ~= nil then
					-- Revert movement prediction to its original state
					owner:EnableMovementPrediction(GLOBAL.Profile:GetMovementPredictionEnabled())
				end

				SendModRPCToServer(MOD_RPC[modname]["SetSelfNormal"])
				--ArtificalWilsonEnabled = false
			else
				BrainPulse(owner)
				-- If movement prediction is enabled, turn it off.
				owner:EnableMovementPrediction(false)
				--EnableMovementPrediction(owner, GLOBAL.Profile:GetMovementPredictionEnabled())
				SendModRPCToServer(MOD_RPC[modname]["SetSelfAI"])
				--ArtificalWilsonEnabled = true
			end
		end
	end
end
AddClassPostConstruct("widgets/sanitybadge", MakeClickableBrain)


local distsq = GLOBAL.distsq

local function LocomotorMod(self,dt)

	local DOZE_OFF_TIME = 2
	local PATHFIND_PERIOD = 1
	local PATHFIND_MAX_RANGE = 40
	local STATUS_CALCULATING = 0
	local STATUS_FOUNDPATH = 1
	local STATUS_NOPATH = 2
	local NO_ISLAND = 127
	local ARRIVE_STEP = .15
	local INVALID_PLATFORM_ID = "INVALID PLATFORM"

	---------------- TRAILBLAZER STUFF HERE -------------------------------
	---------------------------------------------------------------------------------------------------------
	-- Cleans up the locomotor if necessary
	local CleanupLocomotorNow = function()
		self:Stop()
		GLOBAL.ThePlayer:EnableMovementPrediction(false)
	end

	-- Cleans up the locomotor if necessary
	local CleanupLocomotorLater = function(self)
		-- Cleanup later to avoid rubber-banding
		self.trailblazerCleanupLater = true
		-- Do not clean up now
		self.trailblazerCleanupClear = nil

		-- Cleanup, but only if the locomotor is not pathfinding
		killTask = function()
			if self.dest == nil then
				if self.trailblazerCleanupLater == true then
			  		CleanupLocomotorNow()
				end
		  	else
				GLOBAL.ThePlayer:DoTaskInTime(1.5, killTask)
		  	end
		end

		GLOBAL.ThePlayer:DoTaskInTime(1.5, killTask)
	end

	-- Clear Override
	local _Clear = self.Clear
	self.Clear = function(self)
		if self.trailblazerCleanupClear then
		  CleanupLocomotorLater(self)
		else
		  _Clear(self)
		end
	end

	-- PreviewAction Override
	local _PreviewAction = self.PreviewAction
	self.PreviewAction = function(self, bufferedaction, run, try_instant)
		if bufferedaction == nil then
			return false
		end
		if bufferedaction.action == GLOBAL.ACTIONS.TRAILBLAZE then
			self.throttle = 1
			_Clear(self)
			self:Trailblaze(bufferedaction.pos, bufferedaction, run, disablePM)
		else
			return _PreviewAction(self, bufferedaction, run, try_instant)
		end
	end

	-- PushAction Override
	local _PushAction = self.PushAction
	self.PushAction = function(self, bufferedaction, run, try_instant)
		if bufferedaction == nil then
		  	return
		end
		if bufferedaction.action == GLOBAL.ACTIONS.TRAILBLAZE then

			self.throttle = 1
			local success, reason = bufferedaction:TestForStart()
			if not success then
				self.inst:PushEvent("actionfailed", { action = bufferedaction, reason = reason })
				return
			end
			_Clear(self)
			self:Trailblaze(bufferedaction.pos, bufferedaction, run)
			if self.inst.components.playercontroller ~= nil then
				self.inst.components.playercontroller:OnRemoteBufferedAction()
			end
		else
		  	return _PushAction(self, bufferedaction, run, try_instant)
		end
	end

	-- Navigate to entity (Fix speedmult)
	local _GoToEntity = self.GoToEntity
	self.GoToEntity = function(self, inst, bufferedaction, run)
		self.arrive_step_dist = ARRIVE_STEP
		_GoToEntity(self, inst, bufferedaction, run)
	end

	-- Navigate to point (Fix speedmult)
	local _GoToPoint = self.GoToPoint
	self.GoToPoint = function(self, pt, bufferedaction, run, overridedest)
		self.arrive_step_dist = ARRIVE_STEP
		_GoToPoint(self, pt, bufferedaction, run, overridedest)
	end

	-- Concurrent processing
	local trailblazer = GLOBAL.require("components/trailblazer")
	local trailblazerProcess = function(self, dest, run)
		-- Path is not nil, process!
		if self.trailblazePath ~= nil then
			-- If path is finished
			if trailblazer.processPath(self.trailblazePath, 250) then
				-- If pathfinding was successful
				if self.trailblazePath.nativePath.steps ~= nil then

					-- Populate pathfinding variables
					self.dest = dest
					self.throttle = 1

					self.arrive_step_dist = ARRIVE_STEP * self:GetSpeedMultiplier()
					self.wantstorun = run

					self.path = {}
					self.path.steps = self.trailblazePath.nativePath.steps
					self.path.currentstep = 2
					self.path.handle = nil

					self.wantstomoveforward = true

					-- Register deferred cleanup if necessary
					if self.trailblazerCleanup == true then

						-- Cleanup on destination reached
						self.inst:ListenForEvent("onreachdestination", function() CleanupLocomotorLater(self) end)

						-- Cleanup if the path gets cleared (user strays)
						self.trailblazerCleanupClear = true

						-- Cleanup scheduled, do not cleanup now
						self.trailblazerCleanup = nil
					end

					self:StartUpdatingInternal()

				-- If pathfinding was unsuccessful
				else
					self.inst:PushEvent("noPathFound", {inst=self.inst, target=(self.dest and self.dest.inst or dest)})
					self:Stop()
				end
				self.trailblazePath = nil
			end
		end

		-- Path is no longer wanted (or may be complete)
		if self.trailblazePath == nil then
			self.inst:PushEvent("pathfinderComplete", {inst=self.inst, target=(self.dest and self.dest.inst or dest)})
			self.trailblazeTask:Cancel()
				self.trailblazeTask = nil

			if self.trailblazerCleanup then
				CleanupLocomotorNow()
			end
		end
	end

	-- Pathfind via custom algorithm
	self.Trailblaze = function(self, pt, bufferedaction, run, disablePM)
		local dest = {}
		if GLOBAL.CurrentRelease.GreaterOrEqualTo( ReleaseID.R08_ROT_TURNOFTIDES ) then
		  	dest = GLOBAL.Dest(bufferedaction.overridedest, nil, bufferedaction)
		else
		  	dest = GLOBAL.Dest(bufferedaction.overridedest, pt)
		end

		--dest = GLOBAL.Dest()

		print("Trailblaze - Dest: " .. tostring(dest))

		if self.trailblazeTask ~= nil then
			self.trailblazeTask:Cancel()
			self.trailblazeTask = nil
		end

		local p0 = GLOBAL.Vector3(self.inst.Transform:GetWorldPosition())
		local p1 = GLOBAL.Vector3(dest:GetPoint())

		self.trailblazePath = trailblazer.requestPath(p0, p1, self.pathcaps)
		self.trailblazeTask = self.inst:DoPeriodicTask(0, function() trailblazerProcess(self, dest, run) end)
	end
	-------------------------------------------------------------------------------------------------------------


 	self.OnUpdate = function(self,dt)
		if self.hopping then
			self:UpdateHopping(dt)
			return
		end

		if not self.inst:IsValid() then
			--Print(VERBOSITY.DEBUG, "OnUpdate INVALID", self.inst.prefab)
			self:ResetPath()
			self:StopUpdatingInternal()
			return
		end

		if self.enablegroundspeedmultiplier then
			local x, y, z = self.inst.Transform:GetWorldPosition()
			local tx, ty = GetWorld().Map:GetTileCoordsAtPoint(x, 0, z)
			if tx ~= self.lastpos.x or ty ~= self.lastpos.y then
				self:UpdateGroundSpeedMultiplier()
				self.lastpos = { x = tx, y = ty }
			end
		end

		--Print(VERBOSITY.DEBUG, "OnUpdate", self.inst.prefab)
		if self.dest then
			--Print(VERBOSITY.DEBUG, "    w dest")
			if not self.dest:IsValid() or (self.bufferedaction and not self.bufferedaction:IsValid()) then
				self:Clear()
				return
			end

			if self.inst.components.health and self.inst.components.health:IsDead() then
				self:Clear()
				return
			end

			local destpos_x, destpos_y, destpos_z = self.dest:GetPoint()
			local mypos_x, mypos_y, mypos_z = self.inst.Transform:GetWorldPosition()

			local reached_dest, invalid
			if self.bufferedaction ~= nil and
				self.bufferedaction.action == GLOBAL.ACTIONS.ATTACK and
				self.inst.replica.combat ~= nil then

				local dsq = distsq(destpos_x, destpos_z, mypos_x, mypos_z)
				local run_dist = self:GetRunSpeed() * dt * .5
				reached_dest = dsq <= math.max(run_dist * run_dist, self.arrive_dist * self.arrive_dist)
				if not reached_dest then
					reached_dest, invalid = self.inst.replica.combat:CanAttack(self.bufferedaction.target)
				end
			elseif self.bufferedaction ~= nil
				and self.bufferedaction.action.customarrivecheck ~= nil then
				reached_dest, invalid = self.bufferedaction.action.customarrivecheck(self.inst, self.dest)
			else
				local dsq = distsq(destpos_x, destpos_z, mypos_x, mypos_z)
				local run_dist = self:GetRunSpeed() * dt * .5
				reached_dest = dsq <= math.max(run_dist * run_dist, self.arrive_dist * self.arrive_dist)
			end

			if invalid then
				self:Stop()
				self:Clear()
			elseif reached_dest then
				--Print(VERBOSITY.DEBUG, "REACH DEST")
				self.inst:PushEvent("onreachdestination", { target = self.dest.inst, pos = GLOBAL.Point(destpos_x, destpos_y, destpos_z) })
				if self.atdestfn ~= nil then
					self.atdestfn(self.inst)
				end

				if self.bufferedaction ~= nil and self.bufferedaction ~= self.inst.bufferedaction then
					if self.bufferedaction.target ~= nil and self.bufferedaction.target.Transform ~= nil and not self.bufferedaction.action.skip_locomotor_facing then
						self.inst:FacePoint(self.bufferedaction.target.Transform:GetWorldPosition())
					elseif self.bufferedaction.invobject ~= nil and not self.bufferedaction.action.skip_locomotor_facing then
						local act_pos = self.bufferedaction:GetActionPoint()
						if act_pos ~= nil then
							self.inst:FacePoint(act_pos:Get())
						end
					end
					if self.ismastersim then
						self.inst:PushBufferedAction(self.bufferedaction)
					else
						self.inst:PreviewBufferedAction(self.bufferedaction)
					end
				end
				self:Stop()
				self:Clear()
			else
				--Print(VERBOSITY.DEBUG, "LOCOMOTING")
				if self:WaitingForPathSearch() then
					local pathstatus = GetWorld().Pathfinder:GetSearchStatus(self.path.handle)
					--Print(VERBOSITY.DEBUG, "HAS PATH SEARCH", pathstatus)
					if pathstatus ~= STATUS_CALCULATING then
						--Print(VERBOSITY.DEBUG, "PATH CALCULATION complete", pathstatus)
						if self.inst:HasTag(DebugTag) then print("PATH CALC COMPLETE " .. tostring(pathstatus)) end
                        if self.inst:HasTag(DebugTag) then print("STATUS_FOUNDPATH = " .. tostring(STATUS_FOUNDPATH)) end
						if pathstatus == STATUS_FOUNDPATH then
							--Print(VERBOSITY.DEBUG, "PATH FOUND")
							if self.inst:HasTag(DebugTag) then print("PATH FOUND") end
							local foundpath = GetWorld().Pathfinder:GetSearchResult(self.path.handle)
							if foundpath then
								--Print(VERBOSITY.DEBUG, string.format("PATH %d steps ", #foundpath.steps))
								if self.inst:HasTag(DebugTag) then print(string.format("PATH %d steps ", #foundpath.steps)) end

								if #foundpath.steps > 2 then
									self.path.steps = foundpath.steps
									self.path.currentstep = 2

									-- for k,v in ipairs(foundpath.steps) do
									--     Print(VERBOSITY.DEBUG, string.format("%d, %s", k, tostring(Point(v.x, v.y, v.z))))
									-- end

								else
									--Print(VERBOSITY.DEBUG, "DISCARDING straight line path")
									self.path.steps = nil
									self.path.currentstep = nil
								end
							else
								--Print(VERBOSITY.DEBUG, "EMPTY PATH")
								if self.inst:HasTag(DebugTag) then print("EMPTY PATH") end
								GetWorld().Pathfinder:KillSearch(self.path.handle)
								self.path.handle = nil
								self.inst:PushEvent("noPathFound", {inst=self.inst, target=self.dest.inst, pos=GLOBAL.Point(destpos_x, destpos_y, destpos_z)})
							end
						else
							if pathstatus == nil then
								--Print(VERBOSITY.DEBUG, string.format("LOST PATH SEARCH %u. Maybe it timed out?", self.path.handle))
								if self.inst:HasTag(DebugTag) then print(string.format("LOST PATH SEARCH %u. Maybe it timed out?", self.path.handle)) end
							else
								--Print(VERBOSITY.DEBUG, "NO PATH")
								if self.inst:HasTag(DebugTag) then print("NO PATH - pushing noPathFound") end
                        		GetWorld().Pathfinder:KillSearch(self.path.handle)
                        		self.path.handle = nil
                        		self.inst:PushEvent("noPathFound", {inst=self.inst, target=self.dest.inst, pos=GLOBAL.Point(destpos_x, destpos_y, destpos_z)})
							end
						end

						--TheWorld.Pathfinder:KillSearch(self.path.handle)
						--self.path.handle = nil
						if self.path and self.path.handle then
                     		GetWorld().Pathfinder:KillSearch(self.path.handle)
                     		self.path.handle = nil
                  		end
					end
				end

				if not self.inst.sg or self.inst.sg:HasStateTag("canrotate") then
					--Print(VERBOSITY.DEBUG, "CANROTATE")
					local facepos_x, facepos_y, facepos_z = destpos_x, destpos_y, destpos_z

					if self.path and self.path.steps and self.path.currentstep < #self.path.steps then
						--Print(VERBOSITY.DEBUG, "FOLLOW PATH")
						--if self.inst:HasTag(DebugTag) then print("Following path") end
						local step = self.path.steps[self.path.currentstep]
						local steppos_x, steppos_y, steppos_z = step.x, step.y, step.z

						--Print(VERBOSITY.DEBUG, string.format("CURRENT STEP %d/%d - %s", self.path.currentstep, #self.path.steps, tostring(steppos)))
						if self.inst:HasTag(DebugTag) then
							local steppos = GLOBAL.Point(steppos_x, steppos_y, steppos_z)
							--print(string.format("CURRENT STEP %d/%d - %s", self.path.currentstep, #self.path.steps, tostring(steppos)))
						end

						local step_distsq = distsq(mypos_x, mypos_z, steppos_x, steppos_z)
						if step_distsq <= (self.arrive_step_dist)*(self.arrive_step_dist) then
							self.path.currentstep = self.path.currentstep + 1

							if self.path.currentstep < #self.path.steps then
								step = self.path.steps[self.path.currentstep]
								steppos_x, steppos_y, steppos_z = step.x, step.y, step.z

								--Print(VERBOSITY.DEBUG, string.format("NEXT STEP %d/%d - %s", self.path.currentstep, #self.path.steps, tostring(steppos)))
								if self.inst:HasTag(DebugTag) then
									local steppos = GLOBAL.Point(steppos_x, steppos_y, steppos_z)
									print(string.format("NEXT STEP %d/%d - %s", self.path.currentstep, #self.path.steps, tostring(steppos)))
								end
							else
								--Print(VERBOSITY.DEBUG, string.format("LAST STEP %s", tostring(destpos)))
								if self.inst:HasTag(DebugTag) then
									local destpos = GLOBAL.Point(destpos_x, destpos_y, destpos_z)
									print(string.format("LAST STEP %s", tostring(destpos)))
								end
								steppos_x, steppos_y, steppos_z = destpos_x, destpos_y, destpos_z
							end
						end
						facepos_x, facepos_y, facepos_z = steppos_x, steppos_y, steppos_z
					end

					local x,y,z = self.inst.Physics:GetMotorVel()
					if x < 0 then
						--Print(VERBOSITY.DEBUG, "SET ROT", facepos)
						local angle = self.inst:GetAngleToPoint(facepos_x, facepos_y, facepos_z)
						self.inst.Transform:SetRotation(180 + angle)
					else
						--Print(VERBOSITY.DEBUG, "FACE PT", facepos)
						self.inst:FacePoint(facepos_x, facepos_y, facepos_z)
					end
				end

				self.wantstomoveforward = self.wantstomoveforward or not self:WaitingForPathSearch()
			end
		end

		local should_locomote = false
		if (self.ismastersim and not self.inst:IsInLimbo()) or not (self.ismastersim or self.inst:HasTag("INLIMBO")) then
			local is_moving = self.inst.sg ~= nil and self.inst.sg:HasStateTag("moving")
			local is_running = self.inst.sg ~= nil and self.inst.sg:HasStateTag("running")
			--'not' is being used below as a cast-to-boolean operator
			should_locomote =
				(not is_moving ~= not self.wantstomoveforward) or
				(is_moving and (not is_running ~= not self.wantstorun))
		end

		if should_locomote then
			self.inst:PushEvent("locomote")
		elseif not self.wantstomoveforward and not self:WaitingForPathSearch() then
			--if self.inst:HasTag(DebugTag) then print("Dont want to move and not waiting for path...") end
			self:ResetPath()
			self:StopUpdatingInternal()
		end

		local cur_speed = self.inst.Physics:GetMotorSpeed()
		if cur_speed > 0 then

			if self.allow_platform_hopping and (self.bufferedaction == nil or not self.bufferedaction.action.disable_platform_hopping) then

				local mypos_x, mypos_y, mypos_z = self.inst.Transform:GetWorldPosition()

				local destpos_x, destpos_y, destpos_z
				destpos_y = 0

				local rotation = self.inst.Transform:GetRotation() * GLOBAL.DEGREES
				local forward_x, forward_z = math.cos(rotation), -math.sin(rotation)

				local dest_dot_forward = 0

				local map = GetWorld().Map
				local my_platform = map:GetPlatformAtPoint(mypos_x, mypos_z)

				if self.dest and self.dest:IsValid() then
					destpos_x, destpos_y, destpos_z = self.dest:GetPoint()
					local dest_dir_x, dest_dir_z = GLOBAL.VecUtil_Normalize(destpos_x - mypos_x, destpos_z - mypos_z)
					dest_dot_forward = GLOBAL.VecUtil_Dot(dest_dir_x, dest_dir_z, forward_x, forward_z)
					local dist = GLOBAL.VecUtil_Length(destpos_x - mypos_x, destpos_z - mypos_z)
					if dist <= 1.5 then
						local other_platform = map:GetPlatformAtPoint(destpos_x, destpos_z)
						if my_platform == other_platform then
							dest_dot_forward = 1
						end
					end

				end

				local hop_distance = self:GetHopDistance(self:GetSpeedMultiplier())

				local forward_angle_span = 0.1
				if dest_dot_forward <= 1 - forward_angle_span then
					destpos_x, destpos_z = forward_x * hop_distance + mypos_x, forward_z * hop_distance + mypos_z
				end

				local other_platform = map:GetPlatformAtPoint(destpos_x, destpos_z)

				local can_hop = false
				local hop_x, hop_z, target_platform, blocked
				local too_early_top_hop = self.time_before_next_hop_is_allowed > 0
				if my_platform ~= other_platform and not too_early_top_hop then

					can_hop, hop_x, hop_z, target_platform, blocked = self:ScanForPlatform(my_platform, destpos_x, destpos_z, hop_distance)
				end

				if not blocked then
					if can_hop then
						self.last_platform_visited = my_platform

						self:StartHopping(hop_x, hop_z, target_platform)
					elseif self.inst.components.amphibiouscreature ~= nil and other_platform == nil and not self.inst.sg:HasStateTag("jumping") then
						local dist = self.inst:GetPhysicsRadius(0) + 2.5
						local _x, _z = forward_x * dist + mypos_x, forward_z * dist + mypos_z
						if my_platform ~= nil then
							local temp_x, temp_z, temp_platform = nil, nil, nil
							can_hop, temp_x, temp_z, temp_platform, blocked = self:ScanForPlatform(nil, _x, _z, hop_distance)
						end

						if not can_hop and self.inst.components.amphibiouscreature:ShouldTransition(_x, _z) then
							-- If my_platform ~= nil, we already ran the "is blocked" test as part of ScanForPlatform.
							-- Otherwise, run one now.
							if (my_platform ~= nil and not blocked) or
									not self:TestForBlocked(mypos_x, mypos_z, forward_x, forward_z, self.inst:GetPhysicsRadius(0), dist * 1.41421) then -- ~sqrt(2); _x,_z are a dist right triangle so sqrt(dist^2 + dist^2)
								self.inst:PushEvent("onhop", {x = _x, z = _z})
							end
						end
					end
				end

				if (not can_hop and my_platform == nil and target_platform == nil and not self.inst.sg:HasStateTag("jumping")) and self.inst.components.drownable ~= nil and self.inst.components.drownable:ShouldDrown() then
					self.inst:PushEvent("onsink")
				end

			else
				local speed_mult = self:GetSpeedMultiplier()
				local desired_speed = self.isrunning and self:RunSpeed() or self.walkspeed
				if self.dest and self.dest:IsValid() then
					local destpos_x, destpos_y, destpos_z = self.dest:GetPoint()
					local mypos_x, mypos_y, mypos_z = self.inst.Transform:GetWorldPosition()
					local dsq = distsq(destpos_x, destpos_z, mypos_x, mypos_z)
					if dsq <= .25 then
						speed_mult = math.max(.33, math.sqrt(dsq))
					end
				end

				self.inst.Physics:SetMotorVel(desired_speed * speed_mult, 0, 0)
			end
		end

		self.time_before_next_hop_is_allowed = math.max(self.time_before_next_hop_is_allowed - dt, 0)
	end
end


AddComponentPostInit("locomotor", LocomotorMod)


local function ReallyFull(self)

    self.IsTotallyFull = function()
        local invFull = self:IsFull()
        local overFull = true
        if self.overflow then
            if self.overflow.components.container then
                overFull = self.overflow.components.container:IsFull()
            end
        end
        return not not invFull and not not overFull
    end

end

AddComponentPostInit("inventory", ReallyFull)


local function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end



local function SayEgg(self, script, time, noanim, force, nobroadcast, colour)

	-- Copy the current Say function
	self.OriginalSay = self.Say

	self.Say = function(self, script, time, noanim, force, nobroadcast, colour)

		if self.lastSayEgg == nil then
			self.lastSayEgg = 0
		end

		-- Only some of the time
		local chanceSwap = math.random() < 0.0075 and (self.inst ~= nil and self.inst:HasTag("ArtificalWilson"))
		local lastOverride = GLOBAL.GetTime() - self.lastSayEgg
		if not chanceSwap or lastOverride <= 5 then
			self.OriginalSay(self, script, time, noanim, force, nobroadcast, colour)
			return
		end

		-- Override time
		if type(script) == "string" then
			script = "Egg"
		else
			-- Only override single line things? Could just say egg for the whole thing...
			if #script == 1 and script[1].message ~= nil then
				script[1].message = "Egg"
			end
		end

		-- If we say egg, say it to everyone always
		nobroadcast = false

		self.lastSayEgg = GLOBAL.GetTime()
		self.OriginalSay(self, script, time, noanim, force, nobroadcast, colour)
	end
end

AddComponentPostInit("talker", SayEgg)



--------------------------------------------------------------------------------------------------
-- local phud_custombadge= GLOBAL.require "widgets/partybadge"
-- local phud_xpos = (-100)
-- local phud_ypos = (120)


-- local layout = 0
-- local positional = 0

-- if positional==0 then -- standard with minimap
-- 	phud_xpos= (-100)
-- 	phud_ypos= (-70)
-- elseif positional==1 then --extra large minimap
-- 	phud_xpos= (-650)
-- 	phud_ypos= (50)
-- else--no minimap
-- 	phud_xpos= (-100)
-- 	phud_ypos= (120)
-- end

-- --local scale=_G
-- --constructor for badge array
-- local function onstatusdisplaysconstruct(self)

-- 	self.badgearray = {}
-- 	local max_per_player = GetModConfigData("MaxClones") or 15

-- 		--instance badges for players.
-- 	for i = 1, max_per_player, 1 do
-- 		print("Adding badgearray for potential clone " .. tostring(i))
-- 		self.badgearray[i]=self:AddChild(phud_custombadge(self,self.owner))

-- 		if layout==0 then
-- 			--complicated spagetti for a  properly aligned 2x3 grid
-- 			self.badgearray[i]:SetPosition(phud_xpos+(35*(-i-i%2)) ,phud_ypos-110+(110*(-i%2)),0)

-- 		else
-- 			--top centered
-- 			self.badgearray[i]:SetPosition(phud_xpos+(-70*i),phud_ypos,0)
-- 		end
-- 	end

-- 	self.owner.UpdateBadgeVisibility = function()
-- 		for i = 1, max_per_player, 1 do
-- 			self.badgearray[i]:HideBadge()
-- 			--self.badgearray[i]:ShowBadge()

-- 		end
-- 		--local clones = self.owner.components.childspawner and self.owner.components.childspawner.childrenoutside or {}
-- 		--local num_clones = GLOBAL.GetTableSize(clones)
-- 		local clones = self.owner.spawned_clones or {}
-- 		print("Childspawner found: " .. tostring(self.owner.components.childspawner ~= nil))
-- 		print("UpdateBadgeVisibility - there are " .. tostring(#clones) .. " to update...")
-- 		for i, v in ipairs(clones) do
-- 			print("Adding clone: " .. tostring(v))
-- 			local isdead = (v.customisdead and v.customisdead:value() or false)

-- 			print("Player "..tostring(i).." Should be dead "..tostring(isdead).." ")
-- 			if isdead==true then
-- 				self.badgearray[i]:ShowDead()
-- 			else
-- 				self.badgearray[i]:ShowBadge()
-- 			end

-- 		end
-- 	end


-- 	--call upon any player healthdelta
-- 	self.owner.UpdateBadges= function()
-- 		--update badges
-- 		--local clones = self.owner.components.childspawner and self.owner.components.childspawner.childrenoutside or {}
-- 		--local num_clones = GLOBAL.GetTableSize(clones)
-- 		local clones = self.owner.spawned_clones or {}
-- 		print("Updating badges. There are " .. tostring(#clones) .. " clones")
-- 		for i, v in ipairs(clones) do
-- 			print("Updating badge for " .. tostring(v))
-- 			local percent = v.customhpbadgepercent and (v.customhpbadgepercent:value())/100 or 0
-- 			local max = v.customhpbadgemax and v.customhpbadgemax:value() or 0
-- 			local debuff = v.customhpbadgedebuff and v.customhpbadgedebuff:value() or 0
-- 			self.badgearray[i]:SetPercent(percent,max,debuff)
-- 			self.badgearray[i]:SetName(v:GetDisplayName())
-- 		end
-- 		GLOBAL.ThePlayer.UpdateBadgeVisibility()
-- 	end
-- end

-- -- Apply function on construction of class statusdisplays
-- AddClassPostConstruct("widgets/statusdisplays", onstatusdisplaysconstruct)

-- --server functions
-- local function onhealthdelta(inst, data)
-- 	print("onhealthdelta for " .. tostring(inst))
-- 	--get health of char
-- 	local setpercent = data.newpercent and data.newpercent or 0
-- 	inst.customhpbadgepercent:set(math.floor(setpercent * 100+0.5))--potatoey rounding to push shorts
-- 	--get max health of char
-- 	inst.customhpbadgemax:set(inst.components.health.maxhealth)
-- 	--get debuff of char health
-- 	inst.customhpbadgedebuff:set(inst.components.health:GetPenaltyPercent())

-- end

-- local function ondeath(inst,data)
-- 	print("Event: "..inst:GetDisplayName().." died")
-- 	inst.customisdead:set(true)
-- end

-- local function onrespawn(inst,data)
-- 	print("Event: "..inst:GetDisplayName().." respawned")
-- 	inst.customisdead:set(false)
-- end

-- local function ontimerdone(inst, data)
-- 	local clones = inst.components.childspawner and inst.components.childspawner.childrenoutside or {}
-- 	for i, v in ipairs(clones) do
-- 		--inst.customisdead:set(false)
-- 		if v:HasTag('playerghost') then
-- 			v.customisdead:set(true)
-- 		end
-- 	end

-- end

-- --network functions


-- -- When somebody's health changes, it triggers the badges health update
-- local function oncustomhpbadgedirty(inst)
-- 	GLOBAL.ThePlayer.UpdateBadges()
-- end

-- --when someone dies or revives, it triggers badge visibility toggle
-- local function ondeathdeltadirty(inst)
-- 	GLOBAL.ThePlayer.UpdateBadges()
-- end

-- local function ondisconnectdirty(inst)
-- 	GLOBAL.ThePlayer.UpdateBadges()
-- end

-- local function customhppostinit(inst)
-- 	-- Net variable that stores between 0-255; more info in netvars.lua
-- 	-- GUID of entity, unique identifier of variable, event pushed when variable changes
-- 	-- Event is pushed to the entity it refers to, server and client side wise

-- 	print("custom hp postinit for " .. tostring(inst))

-- 	inst.customhpbadgepercent = GLOBAL.net_byte(inst.GUID, "customhpbadge.percent", "customhpbadgedirty")
-- 	inst.customhpbadgemax = GLOBAL.net_byte(inst.GUID,"customhpbadge.max","customhpbadgedirty")
-- 	inst.customhpbadgedebuff = GLOBAL.net_byte(inst.GUID,"customhpbadge.debuff","customhpbadgedirty")
-- 	inst.customisdead = GLOBAL.net_bool(inst.GUID,"customhpbadge.isdead","ondeathdeltadirty")

-- 	-- Server (master simulation) reacts to health and changes the net variable
-- 	if GLOBAL.TheWorld.ismastersim then
-- 		inst:ListenForEvent("healthdelta", onhealthdelta)
-- 		inst:ListenForEvent("respawnfromghost", onrespawn)
-- 		inst:ListenForEvent("death", ondeath)
-- 		--inst:ListenForEvent("playerexited",ondisconnect,GLOBAL.TheWorld)

-- 		inst.components.health:DoDelta(0)

-- 		--the below is just awful never do this unless you like dissapointing 7k subscribers but like w/e uuggghhhh
-- 		--inst:AddComponent("timer")
-- 		--inst:ListenForEvent("timerdone", ontimerdone)
-- 		--inst.components.timer:StartTimer("",1)

-- 	end

-- 	-- Dedicated server is dummy player, only players hosting or clients have the badges
-- 	-- Only them react to the event pushed when the net variable changes
-- 	if not GLOBAL.TheNet:IsDedicated() then
-- 		inst:ListenForEvent("customhpbadgedirty", oncustomhpbadgedirty)
-- 		inst:ListenForEvent("ondeathdeltadirty", ondeathdeltadirty)

-- 	end
-- end
-- -- Apply function on player entity post initialization
-- AddPlayerPostInit(customhppostinit)

-- local function TeamStatusOverride(self, owner)

-- 	self.OnUpdate = function(self, dt)
-- 		--print("Team status override")
-- 		local prev_num_bars = #self.healthbars

-- 		local player_listing = self.owner.spawned_clones or {}

-- 		print("number of clones: " .. tostring(#player_listing))

-- 		while #self.healthbars > #player_listing do
-- 			self.healthbars[#self.healthbars]:Kill()
-- 			table.remove(self.healthbars, #self.healthbars)
-- 		end

-- 		while #self.healthbars < #player_listing do
-- 			table.insert(self.healthbars, self:AddChild(TeammateHealthBadge(self.owner)))
-- 		end

-- 		local respositioning = false
-- 		for i, bar in ipairs(self.healthbars) do
-- 			if bar.userid ~= player_listing[i].userid then
-- 				bar:SetPlayer(player_listing[i])
-- 				respositioning = true
-- 			end
-- 			if bar._cached_isshowingpet ~= bar:IsShowingPet() then
-- 				bar._cached_isshowingpet = bar:IsShowingPet()
-- 				respositioning = true
-- 			end
-- 		end

-- 		if respositioning == true then
-- 			self:RespostionBars()
-- 		end

-- 		if prev_num_bars ~= #self.healthbars and #self.healthbars > 0 then
-- 			if #self.healthbars - 1 > 0 then
-- 				self.healthbars[#self.healthbars - 1].anim:GetAnimState():Show("stick")
-- 			end
-- 			self.healthbars[#self.healthbars].anim:GetAnimState():Hide("stick")
-- 		end
-- 	end
-- end

-- AddClassPostConstruct("widgets/teamstatusbars", TeamStatusOverride)

-- local function ShowTeamStatus(self, owner)
-- 	local TeamStatusBars = require("widgets/teamstatusbars")
-- 	print("Adding team status bar post construct...")
-- 	self.teamstatus = self.topleft_root:AddChild(TeamStatusBars(self.owner))
-- end
-- AddClassPostConstruct("widgets/controls", ShowTeamStatus)

-- Seeing if adding these in post init will actually preserve save/loading

-- These are the save/load functions for friends. Player data is saved in a different way....

local MakeInstAI = function(bot)
	local brain = GLOBAL.require "brains/artificalwilson"
	bot:SetBrain(brain)
	bot:RestartBrain()
end
local SaveAIData = function(inst, data)
	data.ai_enabled = inst:HasTag("ArtificalWilson")
end

local LoadAIData = function(inst, data)
	if data.ai_enabled == nil then
		print("ai_enabled wasn't set....")
	end

	if data.ai_enabled == true then
		MakeInstAI(inst)
	end
end


AddPlayerPostInit(function(player) if player.components.explorer == nil then player:AddComponent("explorer") end  end)
AddPlayerPostInit(function(player) if player.components.basebuilder == nil then player:AddComponent("basebuilder") end end)
AddPlayerPostInit(AddCloneSpawner)
AddAction("TRAILBLAZE", "Travel via Trailblaze", function(act) end)


GLOBAL.c_GiveDebugItems = function()
	GLOBAL.c_give("log", 20)
	GLOBAL.c_give("cutgrass", 40)
	GLOBAL.c_give("twigs", 40)
	GLOBAL.c_give("goldnugget", 20)
	GLOBAL.c_give("rocks", 20)
	GLOBAL.c_give("berries", 20)
	-- 8 stacks of berries here
	GLOBAL.c_give("berries_cooked", 40*8)
end