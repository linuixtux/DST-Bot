Revenge = Class(BehaviourNode, function(self, inst)
   BehaviourNode._ctor(self, "Revenge")
   self.inst = inst

   self.target = nil

   self.teleport_counter = 0


   self.monologue = {
      { text="It didn't have to be this way", time=3},
      { text="We could have been friends", colour={1,0,0,1}, time=3.5},
      { text=".....", time=2},
      { text="There is a man behind you", colour={1,0,0,.75}, time=1.5, after=self.FindPanFlute},
   }

   -- If we find the panflute
   self.revenge = {
      {text="Remember this?", time=1, after=self.PlayFlute}
   }

   -- Error finding panflute...
   self.revenge_fail = {
      {text="No flute? Fine!", after=self.NoFlute, time=0.5}
   }

   self.taunts = {
      "Hit me",
      "Take a shot",
      "What are you waiting for?",
      "Are you scared?",
      "Come closer..."
   }

   self.avoidCounter = nil
   self.panflute = nil
end)

function Revenge:NoFlute()
   self.inst.components.talker:Say("Minions...assemble!", 5, false, true, false, {1,0,0,1})
   for i=0,4,.25 do
      self.inst:DoTaskInTime(i, function()
         SpawnMirrage(self.inst, nil, 5)
      end)
   end

   self.inst:RemoveTag("revengeMode")
   self.sequence_started = false
end

function Revenge:FindPanFlute()
   self.sequence_started = true

   -- If we already have it, use it
   if self:HasPanFlute() then
      local tp = TeleportBehind(self.inst, self.target, self.inst, 12, 0)
      self.inst:PushBufferedAction(tp)
      self.inst:DoTaskInTime(.75, function() self:NextStep() end)
      return
   end
   -- Find the panflute.
   local panflute = c_findnext("panflute")
   if not panflute then
      self:DebugPrint("Couldn't find PAN FLUTE")
      self.inst:DoTaskInTime(.2, function() self:NextStep() end)
      return
   end

   self:DebugPrint("Found " .. tostring(panflute))

   -- Teleport to panflute. Pick it up. Teleport back.
   local teleport = TeleportBehind(self.inst, panflute, self.inst, 1)
   if not teleport then
      self:DebugPrint("Couldn't teleport to panflute...")
      self.inst:DoTaskInTime(.2, function() self:NextStep() end)
      return
   end

   local original_pos = self.inst:GetPosition()
   teleport:AddSuccessAction(function()
      TheWorld:PushEvent("ms_sendlightningstrike", original_pos)
      local pickup = BufferedAction(self.inst, panflute, ACTIONS.PICKUP)
      if pickup then
         local returnhome = function(success)
            -- Success or fail, return back home.
            local tp = TeleportBehind(self.inst, self.target, self.inst, 11, 0)
            if tp then
               self.inst:PushBufferedAction(tp)
            end


            self.inst:DoTaskInTime(1, function() self:NextStep() end)
         end
         pickup:AddSuccessAction(function()
            self.inst:DoTaskInTime(1, function()
            self:DebugPrint("Picked up panflute!!")
            returnhome(true)
         end, self.inst) end)

         pickup:AddFailAction(function() self.inst:DoTaskInTime(1, function()
            self:DebugPrint("Failed picking up panflute...")
            returnhome(false)
         end, self.inst) end)

         self.inst:DoTaskInTime(1.5, function() self.inst.components.locomotor:PushAction(pickup, true) end)
      end

   end)

   self:DebugPrint("Teleporting to " .. tostring(panflute))
   self.inst:PushBufferedAction(teleport)
end

function Revenge:PlayFlute()
   local flute = self.inst.components.inventory:FindItem(function(item) return item:HasTag("flute") end)
   if not flute then return false end

   local play = BufferedAction(self.inst, nil, ACTIONS.PLAY, flute)
   if play then
      play:AddSuccessAction(function() self.inst:DoTaskInTime(3.5, function() self:Finale() end) end)
      play:AddFailAction(function()
         self.teleport_counter = self.teleport_counter - 1
         self.inst:DoTaskInTime(.25, function() self:NextStep() end)
      end)
      self.inst:PushBufferedAction(play)
   end
end

function Revenge:Finale()
   -- See if they are sleeping
   -- local target = FindEntity(self.inst, 15, nil, {"player"}, {"ArtificalWilson"})
   -- if not target then return false end
   if not self.target then return false end

   -- if not self.target.sg:HasStateTag("sleeping") then
   --    return false
   -- end

   self.inst.components.talker:Say("TIME TO DIE", 3, false, true, false, {1,0,0,1})
   SurroundWithMirrage(self.inst, self.target)

   self.inst:DoTaskInTime(6, function() self:CheckDone() end)
end

function Revenge:CheckDone()
   self.sequence_started = false
   if not self.target or not self.target:IsValid() then
      self.status = FAILED
      return
   end

   if self.target.health and self.target.components.health:IsDead() then
      self:DebugPrint("Target is dead")
      self.inst.components.talker:Say("I'm sorry...", 5, false, true, false, {0,0,1,1})
      self.inst:DoTaskInTime(2, function()
         self.status = SUCCESS
         self.target = nil
         self.inst:RemoveTag("revengeMode")
         self.combat:SetTarget(nil)
         self.inst.components.locomotor:Stop()
      end)
      return true
   end

   -- How can they be alive?
   self.inst:RemoveTag("revengeMode")
   self.status = SUCCESS
   return false
end

function Revenge:HasPanFlute()
   return self.inst.components.inventory:HasItemWithTag("flute", 1)
end

function Revenge:NextStep()

   -- If some higher brain function interrupts us, continue where we left off.
   if self.resumed ~= nil then
      self.resumed = nil
      self.inst.components.talker:Say("Now where whas I? Ah yes...", 1.5, false, true, false)
      self.inst:DoTaskInTime(1.5, function() self:NextStep() end)
      return
   end

   self.teleport_counter = self.teleport_counter + 1
   local lines = self.monologue
   local line_num = self.teleport_counter
   if self.teleport_counter > #self.monologue then
      if self:HasPanFlute() then
         lines = self.revenge
      else
         lines = self.revenge_fail
      end

      line_num = line_num - #self.monologue
   end


   local line = lines[line_num]
   if line ~= nil then
      -- script, time, noanim, force, nobroadcast, colour
      self.inst.components.talker:Say(line.text, line.time or 5, false, true, false, line.colour)
      if line.after ~= nil then
         self.inst:DoTaskInTime(line.time or 5, function() line.after(self) end)
         self.lastTaunt = GetTime()
      end
   end

end

function Revenge:DebugPrint(string)
   DebugPrint(self.inst, "Revenge: " .. string)
end

function Revenge:GetRunAngle(pt, hp)
   if self.avoid_angle ~= nil then
       local avoid_time = GetTime() - self.avoid_time
       if avoid_time < 1 then
           return self.avoid_angle
       else
           self.avoid_time = nil
           self.avoid_angle = nil
       end
   end

   local angle = self.inst:GetAngleToPoint(hp) + 180 -- + math.random(30)-15
   if angle > 360 then
       angle = angle - 360
   end

   --self:DebugPrint(string.format("RunAway:GetRunAngle me: %s, hunter: %s, run: %2.2f", tostring(pt), tostring(hp), angle))

   local radius = 6

  local find_offset_fn = self.inst.components.locomotor:IsAquatic() and FindSwimmableOffset or FindWalkableOffset
  local result_offset, result_angle, deflected = find_offset_fn(pt, angle*DEGREES, radius, 8, true, false) -- try avoiding walls
   if result_angle == nil then
     result_offset, result_angle, deflected = find_offset_fn(pt, angle*DEGREES, radius, 8, true, true) -- ok don't try to avoid walls
       if result_angle == nil then
        if self.fix_overhang and not TheWorld.Map:IsAboveGroundAtPoint(pt:Get()) then
               if self.inst.components.locomotor:IsAquatic() then
                   local back_on_ocean = FindNearbyOcean(pt, 1)
               if back_on_ocean ~= nil then
                    result_offset, result_angle, deflected = FindSwimmableOffset(back_on_ocean, math.random()*2*math.pi, radius - 1, 8, true, true)
               end
               else
               local back_on_ground = FindNearbyLand(pt, 1) -- find a point back on proper ground
               if back_on_ground ~= nil then
                    result_offset, result_angle, deflected = FindWalkableOffset(back_on_ground, math.random()*2*math.pi, radius - 1, 8, true, true) -- ok don't try to avoid walls, but at least avoid water
               end
               end
        end
        if result_angle == nil then
              return angle -- ok whatever, just run
        end
       end
   end

   result_angle = result_angle / DEGREES
   if deflected then
       self.avoid_time = GetTime()
       self.avoid_angle = result_angle
   end
   return result_angle
end



function Revenge:Visit()

   local isEnabled = function()
      return IsPvPEnabled() and self.inst:HasTag("revengeMode") and not self.inst:HasTag("AIClone")
   end

   if self.status == READY then

      -- This will continue until we no longer have this tag
      if not isEnabled() then
         self.status = FAILED
         return
      end

      self.target = nil

      -- Some higher brain function might interrupt us. We'll know because this
      -- counter wont be at 0...
      if self.teleport_counter ~= 0 then
         self.resumed = true
      end

      -- Find meatgood. Or I guess any player that isn't a bot.
      local nonAICharacter = FindEntity(self.inst, 15, function(p) return p ~= self.inst end, {"player"}, {"ArtificalWilson"})

      if not nonAICharacter then
         --self:DebugPrint("No one around")
         self.status = FAILED
         return
      end

      if not EquipBestWeapon(self.inst) then
         --self:DebugPrint("No weapon...nothing to do?")
         self.status = FAILED
         return
      end


      self.target = nonAICharacter
      -- Cancel whatever we were doing
      self.inst:ClearBufferedAction()
      self.inst.components.locomotor:Stop()


      self.status = RUNNING

   elseif self.status == RUNNING then
      -- This will continue until we no longer have this tag
      if not isEnabled() then
         self.status = FAILED
         return
      end

      local currentTime = GetTime()

      -- Don't care if he runs away, the timeout function will teleport us closer.
      if not self.target then
         self.sequence_started = false
         self.status = FAILED
         return
      end

      if not self.target or not self.target:IsValid() then
         self.sequence_started = false
         self.status = FAILED
         return
      end

      -- One way to abort....something can set this flag.
      if self.pendingstatus ~= nil then
         self.status = self.pendingstatus
         self.pendingstatus = nil
         return
      end

      -- We've started the sequence....don't interrupt
      if self.sequence_started == true then
         -- Unless something else interrupted. Then start the sequence again.
         if self.resumed ~= nil then
            self:NextStep()
         end
         return
      end

      -- If he tries to get close to us, blink away
      local hp = Point(self.target.Transform:GetWorldPosition())
      local pt = Point(self.inst.Transform:GetWorldPosition())
      local dsq = distsq(hp, pt)
      local r = self.inst.Physics:GetRadius() + (self.target.Physics and self.target.Physics:GetRadius() + .1 or 0)

      local teleport = function()

         self.avoidCounter = currentTime
         self.lastTaunt = currentTime

         local tp_behind = TeleportBehind(self.inst, self.target, self.inst, 10, math.random(1,360))
         if tp_behind ~= nil then
            self.inst:DoTaskInTime(.75, function() self.tp_queued = nil end)

            tp_behind:AddSuccessAction(function() self:NextStep() end)
            tp_behind:AddFailAction(function()
               -- What to do here. Maybe just exit the whole behavior and
               -- let it return naturally?
               self:DebugPrint("Teleport action failed?")
               self.pendingstatus = FAILED
            end)

            self.inst.components.locomotor:Stop()
			   self.inst:PushBufferedAction(tp_behind)
         else
            self:DebugPrint("Couldn't teleport?? Just run away!")
            self.inst.components.locomotor:RunInDirection(self:GetRunAngle(pt, hp))
         end
      end

      if not self.tp_queued and dsq <= 15 then
         self.tp_queued = true
         teleport()
         return
      end

      -- If they are too far away...what should we do? Taunt them?
      -- Walk towards them?
      if self.avoidCounter == nil then
         self.avoidCounter = currentTime
      end

      if self.lastTaunt == nil then
         self.lastTaunt = currentTime
      end

      if currentTime - self.lastTaunt > 3.5 then
         local taunt = self.taunts[math.random(1, #self.taunts)]
         self.inst.components.talker:Say(taunt, 3, false, true, false)
         self.lastTaunt = currentTime
      end


      -- If they wont come to us....we can to go them
      if currentTime - self.avoidCounter > 5 then
         self.tp_queued = true
         teleport()
         return
      end

   end
end



