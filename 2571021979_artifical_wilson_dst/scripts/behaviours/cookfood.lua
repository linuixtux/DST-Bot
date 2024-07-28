CookFood = Class(BehaviourNode, function(self, inst, cookDistance)
    BehaviourNode._ctor(self, "CookFood")
    self.inst = inst
    self.distance = cookDistance

    -- Validates that a cooker is usable by this inst
    self.validcooker = function(cooker)
        if cooker == nil then return false end
        -- Only some characters know how to cook on these...
        if cooker:HasTag("dangerouscooker") and not self.inst:HasTag("expertchef") then return false end
        -- Not sure why it would have a cooker tag but no cooker component...
        if cooker.components.cooker == nil then return false end
        -- Don't try to cook on things that require fuel but are empy
        if cooker.components.fueled ~= nil and cooker.components.fueled:IsEmpty() then return false end
        -- Don't try cooking in lava if you aren't fireproof...
        if cooker:HasTag("lava") and not self.inst:HasTag("pyromaniac") then return false end

        -- Valid place to cook
        return true
    end
end)

-- Returned from the buffered actions
function CookFood:OnFail()
    self.pendingstatus = FAILED
end
function CookFood:OnSucceed()
    self.pendingstatus = SUCCESS
end


function CookFood:Visit()

    if self.status == READY then
        -- Only do something if near a cooking source.
        -- TODO: Maybe make a cooking source in some situations?
        -- local cooker = GetClosestInstWithTag("campfire",self.inst,self.distance)
        -- if not cooker then
        --     self.status = FAILED
        --     return
        -- end

        -- Prefer cooking on a cooker in the inventory


        local cooker = FindEntity(self.inst, self.distance, self.validcooker, {"cooker"}, {"INLIMBO", "NOCLICK"})
        if not cooker then
            self.status = FAILED
            return
        end

        -- Find something we can cook
        local cookableFood = self.inst.components.inventory:FindItem(function(item)
                    -- Don't cook this unless we have free space in our inventory or this is a single
                    -- item or the product is in our inventory
                    if not item.components.cookable then return false end
                    local has,numfound = self.inst.components.inventory:Has(item.prefab,1)
                    local theProduct = self.inst.components.inventory:FindItem(function(result) return result.prefab == item.components.cookable.product end)
                    local canFillStack = false
                    if theProduct then
                        canFillStack = not self.inst.components.inventory:Has(
                                    item.components.cookable.product,theProduct.components.stackable.maxsize)
                    end
                    if not self.inst.components.inventory:IsTotallyFull() or numfound == 1 or (theProduct and canFillStack) then
                        return true
                    end

                    return false
             end)

        -- Nothing to cook!
        if not cookableFood then
            self.status = FAILED
            return
        else
            local action = BufferedAction(self.inst,cooker,ACTIONS.COOK,cookableFood)
            action:AddFailAction(function() self:OnFail() end)
            action:AddSuccessAction(function() self:OnSucceed() end)
            self.action = action
            self.pendingstatus = nil
            self.inst.components.locomotor:PushAction(action,true)
            self.status = RUNNING
            return
        end


        -- Dunno how we got here...but we failed
        self.status = FAILED

    elseif self.status == RUNNING then
        if self.pendingstatus then
            self.status = self.pendingstatus
        elseif not self.action:IsValid() then
            self.status = FAILED
        end
    end

end