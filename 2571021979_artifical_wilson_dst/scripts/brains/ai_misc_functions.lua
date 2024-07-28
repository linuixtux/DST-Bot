function SpawnMirrage(player, at, duration)
   if not player.components.childspawner then return end

   print("SpawnMirrage function")

   local poofOnHit = function(inst, attacker, damage)
      -- Spawn some FX where we get hit
      local x, y, z = inst.Transform:GetWorldPosition()
      SpawnPrefab("wortox_portal_jumpin_fx").Transform:SetPosition(x, y, z)
      inst:Remove()
   end

   local username = player.Network:GetClientName()

   local spawn = player.components.childspawner:SpawnChild(player.components.combat.target, player.prefab)

   if not spawn then
      print("Spawn returned nil")
      return
   end

   spawn:AddTag("mirrage")
   -- Make them have the same name
   spawn:SetPrefabNameOverride(username)

   -- Give them a copy of whatever weapon/armor player is holding
   local hands = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
   local head =  player.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
   local body =  player.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)

   spawn.components.combat:SetOnHit(poofOnHit)

   -- if at ~= nil then
   --    local dest = FindNearbyLand(at, .2)
   --    if dest ~= nil then
   --       if spawn.Physics ~= nil then
   --          spawn.Physics:Teleport(dest:Get())
   --      elseif spawn.Transform ~= nil then
   --          spawn.Transform:SetPosition(dest:Get())
   --      end
   --    end
   -- end
   if at ~= nil then
      print("Moving to " .. tostring(at))
      spawn.Transform:SetPosition(at.x, at.y, at.z)
      SpawnPrefab("wortox_portal_jumpin_fx").Transform:SetPosition(at.x, at.y, at.z)
   end

   local give = function(copy)
      if copy == nil then return end
      local p = SpawnPrefab(copy.prefab)
      if p then
         spawn.components.inventory:GiveItem(p)
      end
   end

   give(hands)
   give(head)
   give(body)

   spawn:DoTaskInTime((duration or 5), function()
      poofOnHit(spawn)
   end)

   return spawn

end

function SurroundWithMirrage(player, target)
   if not player or not target then return end

   -- See how many friends we can summon, with a maximum of 5
   local numFriends = math.min(5,(player.components.childspawner.maxchildren - player.components.childspawner.numchildrenoutside))

   if numFriends == 0 then
      print("No friends to spawn")
      return
   end

   -- Divide a circle evenly
   local spacing = 360 / numFriends
   print("Each one spaced by " .. tostring(spacing))

   local phys_dist = player.Physics:GetRadius() + (target.Physics and target.Physics:GetRadius() + .1 or 0)

   local function NoHoles(pt)
		return not TheWorld.Map:IsGroundTargetBlocked(pt)
  	end


   local function GetSpawnPt(angle)
      local target_pt = target:GetPosition()
         --FindWalkableOffset(position, start_angle, radius, attempts, check_los, ignore_walls, customcheckfn, allow_water, allow_boats)
      local offset = FindWalkableOffset(target_pt, angle*DEGREES, phys_dist*2, 2, false, true, NoHoles)
      if offset ~= nil then
         target_pt.x = target_pt.x + offset.x
         target_pt.z = target_pt.z + offset.z
            return target_pt
      end

      return nil
	end

   local friends = {}
   for i=1,numFriends,1 do
      local angle = i*spacing
      local pt = GetSpawnPt(angle)
      if pt ~= nil then
         player:DoTaskInTime(.25*i, function()
            print("Spawning mirrage at point " .. tostring(pt))
            local friend = SpawnMirrage(player, pt, 4)
            if friend then
               friend.brain:Stop()
               table.insert(friends, friend)
            end
         end)
      else
         print("Couldn't find valid point for clone # " .. tostring(i))
      end
   end

   player:DoTaskInTime(3, function()
      for _,v in pairs(friends) do
         v.brain:Start()
         v.components.combat:SetTarget(target)
      end
   end)

end