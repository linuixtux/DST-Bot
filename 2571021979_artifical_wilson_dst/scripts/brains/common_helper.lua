function IsDST()
   if TheSim ~= nil and TheSim:GetGameID() == "DST" then
      return true
   else
      return false
   end
end

-- GetMaxHealth function changed between versions
function GetHealthMax(inst)
   if IsDST() then
      return inst.components.health:GetMaxWithPenalty()
   else
      return inst.components.health:GetMaxHealth()
   end
end

-- GetRecipe function changed between versions
function GetRecipeCommon(prefab)
	if IsDST() then
		return GetValidRecipe(prefab)
	else
		return GetRecipe(prefab)
	end
end

-- There is no GetAbsorption for DS
function GetArmorAbsorption(armor, attacker)
   if armor == nil then return 0 end
   if armor.components.armor == nil then return 0 end
   if IsDST() then
      return armor.components.armor:GetAbsorption(attacker) or 0
   else
      return armor.components.armor.absorb_percent or 0
   end

   return 0
end

-- Clock and Season specific stuff...
function IsDay()
   if IsDST() then
      return TheWorld.state.isday or TheWorld.state.isfullmoon
   else
      return GetClock():IsDay()
   end
end

function IsDusk()
   if IsDST() then
      return TheWorld.state.isdusk
   else
      return GetClock():IsDusk()
   end
end

function IsNight()
   if IsDST() then
      return TheWorld.state.isnight and not TheWorld.state.isfullmoon
   else
      return GetClock():IsNight()
   end
end

function AlmostNight()
   if IsDST() then
      return IsDusk() and TheWorld.state.timeinphase > 0.75
   else
      local clock = GetClock()
      return IsDusk() and (clock:GetTimeLeftInEra() < clock:GetDuskTime()/4)
   end
end

function TimeToFindLight()
   if IsDST() then
      return IsNight() or (IsDusk() and (TheWorld.state.timeinphase > 0.95))
   else
      local clock = GetClock()
      return IsNight() or (IsDusk() and (clock:GetTimeLeftInEra() < clock:GetDuskTime()/32))
   end
end

function GetCurrentSeason()
   if IsDST() then
      return TheWorld.state.season
   else
      return GetSeasonManager():GetSeason()
   end
end

function GetCurrentTemperature()
   if IsDST() then
      return TheWorld.state.temperature
   else
      return GetSeasonManager().current_temperature
   end
end

-- Returns true if outdoor temp is <= the insulation threshold values
function IsColdOutside()
   return GetCurrentTemperature() <= 34
end


function IsPvPEnabled()
   if IsDST() and TheNet ~= nil then
      return TheNet:GetPVPEnabled()
   else
      return false
   end
end

function IsInWater(thing)
   if thing == nil then return false end

   if IsDST() then
      return thing:IsOnOcean()
   else
      return thing:GetIsOnWater()
   end
end

-- Only print thins to the console for select players...
function DebugPrint(inst, string)
   if not inst:HasTag("AIDebugPrint") then return end
   print(string)
end