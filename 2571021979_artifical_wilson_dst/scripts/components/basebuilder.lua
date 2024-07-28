local BaseBuilder = Class(function(self, inst)
   self.inst = inst

   -- Minimum distance (sqared) between bases.
   self.min_dist = 20000
   self.base_radius = 30

   -- What should be in a base?
   -- Clearly, scinece stuff.
   -- Clearly a fire pit.
   -- Chests probably....


   -- The x,y,z coordinates of each 'base'.
   -- we can tell the game to scan around these coordinates easily enough
   -- to find out what's around them.
   -- The key is a position. The value is another table describing the location.
   -- self.locaitons[pos] = {}
   self.locations = {}

   -- Populates the default info for a new location.
   -- Do not modify this value directly!!
   -- self.new_location = {
   --    -- The positoin of this location (also the key in self.locations...)
   --    pos = nil,
   --    -- The last time this was scanned for new structures
   --    lastScanTime = 0,
   --    -- Stores the physical inst of nearby structures
   --    structures = {},
   --    -- Stores a count of prefabs. structure_count["treasurechest"] = 3, etc.
   --    structure_count = {}
   -- }

   self.add_new_location = function(pos)
      self.locations[pos] = {}
      local base = self.locations[pos]
      base.pos = pos
      base.lastScanTime = 0
      base.structures = {}
      base.structure_count = {}
      return base
   end

   -- self.locations[pos].structures
   --    a list of physical structure entities.

   -- Should designate one of the bases as 'main'. This will just be a position.
   self.mainLocation = nil


   -- Listen for new build events that we do ourselves
   self.onStructureBuilt = function(inst, data)
      local pos = data.item:GetPosition()
      local base = self:GetBaseNearPos(pos)
      if not base then
         -- We build something, but not near a base. Make this a new base!
         self:DebugPrint("We build a " .. tostring(data.item) .. " but it's not near a base!")
         base = self:AddBaseLocation(pos)
      end

      -- Still no base
      if not base then
         return
      end

      -- Add this structure to the base.
      self:AddNewStructureToBase(base, data.item)
   end

   -- All structures we build will have this called.
   self.inst:ListenForEvent("buildstructure", self.onStructureBuilt)

end)

function BaseBuilder:GetDebugString()
   local string = ""
   return string
end

function BaseBuilder:PrintBase(base)
   local string = ""
   string = string .. "Current Structures: \n"
   for k,v in pairs(base.structure_count) do
      string = string .. tostring(k) .. "," .. tostring(v) .. "\n"
   end

   return string
end

-- Base is a reference to self.locations[pos]
-- struct is a new structure.
function BaseBuilder:AddNewStructureToBase(base, struct)
   -- Each structure has a unique GUID, so make sure this is actually new
   local structures = base.structures
   for _,v in ipairs(structures) do
      if struct == v then
         self:DebugPrint("Already know about this strcture " .. tostring(struct))
         return
      end
   end

   table.insert(structures, struct)

   local count = base.structure_count[struct.prefab]
   if count == nil then
      base.structure_count[struct.prefab] = 1
   else
      base.structure_count[struct.prefab] = count + 1
   end

end

function BaseBuilder:RemoveStructureFromBase(base, struct)
   table.remove(base.structures, struct)

   local count = base.structure_count[struct.prefab]
   if count == nil then
      return
   else
      base.structure_count[struct.prefab] = base.structure_count[struct.prefab] - 1
      if base.structure_count[struct.prefab] == 0 then
         base.structure_count[struct.prefab] = nil
      end
   end
end

function BaseBuilder:AddBaseLocation(pos)
   local current = self.locations[pos]
   if current ~= nil then
      self:DebugPrint("Already have a base at that location...")
      return current
   end

   -- Don't make bases too close together.
   for k,v in pairs(self.locations) do
      -- Get the difference between the passed in position and this one
      local dist = distsq(k.x, k.z, pos.x, pos.z)
      if dist <= self.min_dist then
         self:DebugPrint("Can't add new base....too close to another...")
         return v
      end
   end

   -- New base I guess!
   return self.add_new_location(pos)
end

function BaseBuilder:ScanForStructures(pos)
   local base = self.locations[pos]
   if not base then
      self:DebugPrint("Can't scan for structures at unknown base pos " .. tostring(pos))
      return
   end

   -- Get a copy of the current structures at the base.
   local currentStructures = table.unpack(base.structures)

   -- Search for new ones.
   local structures = TheSim:FindEntities(pos.x, pos.y, pos.z, self.base_radius, {"structure"}, {"INLIMBO", "NOCLICK"})

   -- For each one, add it to the base. This function will check for duplicates and ignore them.
   for k,v in ipairs(structures) do
      self:DebugPrint("Found the following structure at " .. tostring(pos) .. " " .. tostring(v))
      self:AddNewStructureToBase(base, v)
   end

   -- Now cleanup any structures that are no longer there.
   -- Compare the copied table before the update to the
   for k,v in ipairs(currentStructures) do
      if not table.contains(structures, v) then
         self:DebugPrint("The base no longer has the structure: " .. tostring(v))
         self:RemoveStructureFromBase(base, v)
      end
   end

   -- Keep track of our last scan
   base.lastScanTime = GetTime()
end

function BaseBuilder:GetBaseNearPos(pos)
   local closest_dist = self.min_dist * 2
   local closest_base = nil
   for k,v in pairs(self.locations) do

      local dist = distsq(k.x, k.z, pos.x, pos.z)
      if dist <= self.min_dist then
         if dist < closest_dist then
            closest_dist = dist
            closest_base = v
         end
      end
   end

   return closest_base
end

function BaseBuilder:DebugPrint(string)
   DebugPrint(self.inst, "BaseBuilder: " .. string)
end


function BaseBuilder:SerializeSaveInfo()

end

function BaseBuilder:DeserializeSaveInfo(data)

end

function BaseBuilder:OnSave()
   local data = {}
   data.basebuilder = self:SerializeSaveInfo()
   return data
end

function BaseBuilder:OnLoad(data)
   print("Exlorer - on load called!!!")
   if data then
       if data.basebuilder then
           print("Explorer - calling deserialize!!")
           self:DeserializeSaveInfo(data.basebuilder)
       end
   end
end

-- Called every game tick.
function BaseBuilder:OnUpdate(dt)
   if true then
      return
   end
   -- Periodically scan our bases to see what's new.
   -- Stagger these so we don't scan every base at every interval.
   -- This should make it so we only scan one base every second at most.
   local currentTime = GetTime()
   local lastUpdateTime = self.lastUpdate or 0

   if currentTime - lastUpdateTime < 1 then
      return
   end

   self.lastUpdateTime = currentTime

   local updated_one = false
   for k,v in pairs(self.locations) do
      local lastScan = currentTime - (v.lastScanTime or 0)

      -- For each base, see if there's anything new.
      -- Only update once base every update.
      -- BUT - if we have more bases than our update rate, we'll start missing
      --       some. So have an emergency check I guess. Don't think we'll
      --       ever have this many bases, but who knows.
      if not updated_one and lastScan > 30 then
         self:ScanForStructures(k)
         updated_one = true
      elseif updated_one and lastScan ~= currentTime and lastScan > 30 then
         -- lastScan will be currentTime on startup. Skip this one for now, it
         -- will be scanned next interval. Else, we've forgot to update this
         -- one...
         self:DebugPrint("This base has been ignored! Updating...")
         self:ScanForStructures(k)
         updated_one = true
      end
   end
end

return BaseBuilder