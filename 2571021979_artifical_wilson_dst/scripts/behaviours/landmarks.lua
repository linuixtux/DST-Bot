Landmarks = Class(BehaviourNode, function(self, inst, searchDist)
   BehaviourNode._ctor(self, "Landmarks")
   self.inst = inst

   self.searchDist = searchDist

   self.scanIntervalSeconds = 5
   self.lastScanTime = 0

   -- Tags of things to look for.
   self.landmarkTags = {"beefalo", "king", "multiplayer_portal"}

end)

function Landmarks:DebugPrint(string)
   DebugPrint(self.inst, "Landmarks: " .. string)
end

-- Constantly monitors the area around the player looking for landmarks.
-- Doesn't ever go into the running state....probably not a good candidate for
-- a behavior node. Could just be its own component with an OnUpdate really....
function Landmarks:Visit()

   if self.status == READY then

      -- Only scan periodically
      if GetTime() - self.lastScanTime < self.scanIntervalSeconds then
         self.status = FAILED
         return
      end

      self.lastScanTime = GetTime()

      -- Returns true if the landmark hasn't been recorded yet.
      local unique_landmark = function(landmark)
         return self.inst.components.knownlocations:GetLocation(landmark) == nil
      end

      local landmark = FindEntity(self.inst, self.searchDist, unique_landmark, nil, {"INLIMBO", "NOCLICK"}, self.landmarkTags)

      if not landmark then
         self.status = FAILED
         return
      end

      -- Found a new landmark....remember it
      self:DebugPrint("Found a landmark! " .. tostring(landmark))
      self.inst.components.knownlocations:RememberLocation(landmark.prefab, landmark:GetPosition(), true)


      self.status = FAILED
      return

   elseif self.status == RUNNING then
      -- This one doesn't have a running state
      self.status = FAILED
      return
   end
end



