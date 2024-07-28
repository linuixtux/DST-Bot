

-- target:PushEvent("hostileprojectile", { thrower = owner, attacker = attacker, target = target })

DodgeProjectile = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "DodgeProjectile")
   self.inst = inst

   self.projectile = nil
   self.attacker = nil

   self.handleEvent = function(inst, data)
      -- data is thrower, attacker, and target.

      if inst ~= self.inst then return end

      -- At least one of these needs to be defined
      if not data.attacker and not data.thrower then return end

      self.attacker = data.attacker or data.thrower

      self:DebugPrint(tostring(self.attacker) .. " has launched a projectile at us!")
   end

   -- This gets pushed to the target when it's fired.
   self.inst:ListenForEvent("hostileprojectile", self.handleEvent)
end)

function DodgeProjectile:DebugPrint(string)
   DebugPrint(self.inst, "DodgeProjectile: " .. string)
end

-- Most of the times, just run perpendicular to it.
-- But....which way can we even run?
-- Inputs:
--     pt - our current position
--     hp - the attacker's position
function DodgeProjectile:GetRunAngle(pt, hp)

   -- If we already calculated an angle, keep using that angle for a bit.
   if self.avoid_angle ~= nil then
       local avoid_time = GetTime() - self.avoid_time
       if avoid_time < 1 then
           return self.avoid_angle
       else
           self.avoid_time = nil
           self.avoid_angle = nil
       end
   end

   local get_offset_angle = function(offset)
      local a = self.inst:GetAngleToPoint(hp) + offset
      if a > 360 then
         a = a - 360
      end
      return a
   end

   --print(string.format("RunAway:GetRunAngle me: %s, hunter: %s, run: %2.2f", tostring(pt), tostring(hp), angle))
   local hostilesThatWay = function(pt)
       local hostiles = TheSim:FindEntities(pt.x, pt.y, pt.z, 3, nil, self.canttags, self.willfightback) or {}
       if #hostiles > 0 then
           return false
       end
       return true
   end

   -- First, look to the right. Avoid walls
   local radius = 3
   local result_offset, result_angle, deflected = FindWalkableOffset(pt, get_offset_angle(210)*DEGREES, radius, 8, true, false, hostilesThatWay, false, false)
   if result_angle == nil then
      result_offset, result_angle, deflected = FindWalkableOffset(pt, get_offset_angle(145)*DEGREES, radius, 8, true, false, hostilesThatWay, false, false)
      if result_offset == nil then
         return get_offset_angle(180)
      end
   end

   -- Convert back into degrees
   result_angle = result_angle / DEGREES
   if deflected then
       self.avoid_time = GetTime()
       self.avoid_angle = result_angle
   end
   return result_angle
end

function DodgeProjectile:Visit()

   if self.status == READY then

      -- No detected projectiles, all is well.
      if self.attacker == nil then
         self.status = FAILED
         return
      end

      -- bogey, 12 oclock...
      self.status = RUNNING


   elseif self.status == RUNNING then

      -- Only run for as long as we can find an active projectile.
      local projectile = GetClosestInstWithTag("activeprojectile", self.inst, 25)

      if not projectile or not projectile:IsValid() then
         self:DebugPrint("Projectile is gone!")
         self.attacker = nil
         self.inst.components.locomotor:Stop()
         self.status = SUCCESS
         return
      end

      -- The attacker is no longer valid. Hard to know where to run...
      if not self.attacker or not self.attacker:IsValid() then
         self:DebugPrint("Attacker is gone!")
         self.attacker = nil
         self.inst.components.locomotor:Stop()
         self.status = SUCCESS
         return
      end

      

      -- TODO: Run from the attacker, or from the projectile?? Might not matter...
      local pt = Point(self.inst.Transform:GetWorldPosition())
      local hp = Point(projectile.Transform:GetWorldPosition())

      local angle = self:GetRunAngle(pt, hp)
      
      if angle then
         self:DebugPrint("Running away from " .. tostring(projectile) .. " at angle " .. tostring(angle))
          self.inst.components.locomotor:RunInDirection(angle)
      else
         self:DebugPrint("Couldn't find a valid angle to run!!!")
         self.status = FAILED
         self.inst.components.locomotor:Stop()
      end

   end
end



