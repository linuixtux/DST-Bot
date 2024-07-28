local Explorer = Class(function(self, inst)
   self.inst = inst

   self.scan_range = 30
   self.scan_interval = 2.5

   -- Will be an array with a prefab as the key
   -- Each entry can have multiple positions.
   -- locations["home"] = {
   --   {x, y, z},
   --   {x, y, z},
   -- }
   -- Can either get a random one, or....probably more useful, the closest one.
   self.locations = {}

   -- landmarks are stored by prefab name. These are the tags that should pair down
   -- the prefabs.
   -- These aren't required, but helps keep the search space down.
   self.landmarkTags = {"beefalo", "king", "multiplayer_portal", "resurrectionstone", "prototyper", "wormhole"}

   -- tag - the thing to find
   -- multiple - keep track of multiple ones
   -- min_dist - only record multiples if they are outside of min_dist from the others. (this is dstsq)
   self.landmarkOpts = {}
   self.landmarkOpts["beefalo"] =            {multiple = true, min_dist = 20000}
   self.landmarkOpts["pigking"] =            {multiple = false}
   self.landmarkOpts["multiplayer_portal"] = {multiple = false}
   self.landmarkOpts["resurrectionstone"] =  {multiple = true, min_dist = 1000}
   self.landmarkOpts["scienceprototyper"] =  {multiple = true, min_dist = 10000}
   self.landmarkOpts["magicprototyper"] =    {multiple = true, min_dist = 10000}
   self.landmarkOpts["wormhole"] =           {multiple = true, min_dist = 1000}


   -- Remove any stored touchstones as they can only be used once.
   self.inst:ListenForEvent("usedtouchstone", function(inst, touchstone)
      if inst ~= self.inst then return end
      if not self.locations[touchstone.prefab] then return end
      self:DebugPrint("We used a touchstone - removing it from saved locations!")
      self:ForgetLocation(touchstone.prefab, touchstone:GetPosition())
   end)
	self:StartUpdate()
end)

function Explorer:DebugPrint(string)
   DebugPrint(self.inst, "Explorer: " .. string)
end

function Explorer:GetDebugString()
   local str = ""
   for k,v in pairs(self.locations) do
      for kk,vv in pairs(v) do
         str = str..string.format("%s: %s ", k, tostring(vv))
      end
   end
   return str
end

-- Just adds the new entry to the list.
function Explorer:RememberLocation(name, pos)

   -- Currently only track explicit things...
   local opts = self.landmarkOpts[name]
   if not opts then return end

   -- Only tracking one of these...don't bother looking for more
   if not opts.multiple and self.locations[name] ~= nil then
      return
   end

   -- Tracking multiple of these. Verify this one is outside the min range.
   if self.locations[name] == nil then
      self.locations[name] = {}
   end

   local locdata = self.locations[name]
   local valid_entry = true
   for k,v in pairs(locdata) do
      -- Calculate the distance from passed in point and stored point
      local dist = distsq(v.x, v.z, pos.x, pos.z)
      if dist <= (opts.min_dist or 10000) then
         self:DebugPrint("Too close to another " .. name .. " (" .. tostring(dist) .. ")")
         valid_entry = false
      end
   end

   -- This one was too close to a previous one. Not adding again.
   if not valid_entry then return end

   -- Add it
   table.insert(locdata, pos)
end

function Explorer:GetLocation(name)
   return self.locations[name]
end

-- Returns a point (x,y,z) of the closest thing we are tracking.
-- nil if we haven't found one of those yet
function Explorer:GetClosestLocation(name)
   if not self.locations[name] then return nil end

   local closest = nil
   for k,v in self.locations[name] do
      if closest == nil then
         closest = v
      else
         local dist_to_new = self.inst:GetDistanceSqToPoint(v)
         local dist_to_closest = self.inst:GetDistanceSqToPoint(closest)
         if dist_to_new < dist_to_closest then
            closest = v
         end
      end
   end

   return closest
end

-- Gets a random one of the saved locations (if more than one).
function Explorer:GetRandomLocation(name)

   local randomname = function()
      local t = {}
      for k,_ in pairs(self.locations) do
         table.insert(t, k)
      end
      if #t > 0 then
         return t[math.random(1,#t)]
      end
   end

   if name == nil then
      name = randomname()
   end

   if not name then return nil end

   DebugPrint(self.inst, "Random location - " .. tostring(name))

   if not self.locations[name] then return nil end
   return self.locations[name][math.random(#(self.locations[name]))]
end

function Explorer:ForgetLocation(name, pos)
   if pos == nil then
      self.locations[name] = nil
      return
   end

   -- Has to be an exact position...
   for k,v in pairs(self.locations[name]) do
      if v == pos then
         self:DebugPrint("Removing saved location (" .. tostring(v) .. ") for " .. tostring(name))
         self.locations[name][k] = nil
         return
      end
   end
end

function Explorer:SerializeLocations()
   local locs = {}
      for k,v in pairs(self.locations) do
         for kk,vv in pairs(v) do
            table.insert(locs, {name = k, x = vv.x, y = vv.y, z = vv.z})
         end
      end
   return locs
end

function Explorer:DeserializeLocations(data)
   for k,v in pairs(data) do
         print("Explorer - re-adding saved locaiton " .. tostring(v.name))
         self:RememberLocation(v.name, Vector3(v.x, v.y, v.z))
   end
end

function Explorer:OnSave()
   local data = {}
   data.locations = self:SerializeLocations()
   return data
end

function Explorer:OnLoad(data)
   print("Exlorer - on load called!!!")
   if data then
       if data.locations then
           print("Explorer - calling deserialize!!")
           self:DeserializeLocations(data.locations)
       end
   end
end

-- Schedules itself to run periodically rather than every game tick
function Explorer:StartUpdate()
   if not self.task then
      self.task = self.inst:DoPeriodicTask(self.scan_interval, function() self:ScanForLandmarks() end)
   end
end

function Explorer:ScanForLandmarks()

   -- Returns true if this is something we even want to track.
   local want_to_track = function(landmark)

      -- Only track prefabs defined in the opts.
      local opts = self.landmarkOpts[landmark.prefab]
      if not opts then return false end

      -- For touch stones, only want to record it if it's one we can use
      if self.inst.components.touchstonetracker and landmark.prefab == "resurrectionstone" then
         return not self.inst.components.touchstonetracker:IsUsed(landmark)
      end

      -- Since we filtered by tags, defaults to true.
      return true
   end

   -- local landmark = FindEntity(self.inst, self.scan_range, want_to_track, nil, {"INLIMBO", "NOCLICK"}, self.landmarkTags)
   -- if not landmark then return end
   -- self:DebugPrint("Found a landmark! " .. tostring(landmark))
   -- self:RememberLocation(landmark.prefab, landmark:GetPosition())

   local x, y, z = self.inst.Transform:GetWorldPosition()
   --print("FIND", inst, radius, musttags and #musttags or 0, canttags and #canttags or 0, mustoneoftags and #mustoneoftags or 0)
   local ents = TheSim:FindEntities(x, y, z, self.scan_range, nil, {"INLIMBO", "NOCLICK"}, self.landmarkTags) -- or we could include a flag to the search?
   for i, v in ipairs(ents) do
       if v ~= self.inst and v.entity:IsVisible() and (want_to_track == nil or want_to_track(v, self.inst)) then
            self:DebugPrint("Found a landmark! " .. tostring(v))
            self:RememberLocation(v.prefab, v:GetPosition())
       end
   end
end


return Explorer