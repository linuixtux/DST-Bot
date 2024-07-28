local Badge = require "widgets/badge"
local UIAnim = require "widgets/uianim"
local Text = require "widgets/text"
local Image = require "widgets/image"

local function OnEffigyDeactivated(inst)
    if inst.AnimState:IsCurrentAnimation("deactivate") then
        inst.widget:Hide()
    end
end

local PartyBadge = Class(Badge, function(self, owner)
    Badge._ctor(self, "health", owner)

    -- instance the health debuff coverup
    self.topperanim = self.underNumber:AddChild(UIAnim())
    self.topperanim:GetAnimState():SetBank("effigy_topper")
    self.topperanim:GetAnimState():SetBuild("effigy_topper")
    self.topperanim:GetAnimState():PlayAnimation("anim")
    self.topperanim:SetClickable(false)

    -- instance hp up/down arrow
    self.sanityarrow = self.underNumber:AddChild(UIAnim())
    self.sanityarrow:GetAnimState():SetBank("sanity_arrow")
    self.sanityarrow:GetAnimState():SetBuild("sanity_arrow")
    self.sanityarrow:GetAnimState():PlayAnimation("neutral")
    self.sanityarrow:SetClickable(false)

    --Hide the original frame since it is now overlapped by the topperanim
    self.anim:GetAnimState():Hide("frame")

    self.dead = self:AddChild(Image("images/hud.xml", "tab_arcane.tex"))
    self.dead:SetPosition(-10, 0, 0)	
    self.dead:SetScale(0.7)

    self.name = self:AddChild(Text(BODYTEXTFONT, 20))
    self.name:SetHAlign(ANCHOR_MIDDLE)
    self.name:SetPosition(0, 40, 0)
    self.name:SetString("--")


end)

function PartyBadge:SetName(namestring)
    self.name:SetString(namestring)
end
-- updates hud, val= current hp percent(undebuffed), max = max hp, penalty =current hp penalty percent
function PartyBadge:SetPercent(val, max, penaltypercent)
    
    Badge.SetPercent(self, val, max)
    penaltypercent = penaltypercent or 0
    self.topperanim:GetAnimState():SetPercent("anim", penaltypercent)
end

-- hide entire badge
function PartyBadge:HideBadge()
	self.anim:Hide()
	self.sanityarrow:Hide()
	self.topperanim:Hide()
    self.name:Hide()
    self.dead:Hide()
    self:Hide()
end

--show entire badge
function PartyBadge:ShowBadge()
    self:Show()
	self.anim:Show()
	self.sanityarrow:Show()
	self.topperanim:Show()
    self.name:Show()
	self.anim:GetAnimState():Hide("frame")
    self.dead:Hide()
end

function PartyBadge:ShowDead()
    self:Show()
    self.anim:Hide()
    self.sanityarrow:Hide()
    self.topperanim:Hide()
    self.name:Show()
    self.dead:Show()
end



return PartyBadge
