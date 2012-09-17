//
// lua\TurretMixin.lua

Script.Load("lua/FunctionContracts.lua")

TurretMixin = CreateMixin( TurretMixin )
TurretMixin.type = "Turret"

// This is needed so alien structures can be cloaked, but not marine structures
TurretMixin.expectedCallbacks =
{
    OnPowerOn = "called on power active",
    OnPowerOff = "called on power loss",
}

TurretMixin.optionalCallbacks =
{
}

TurretMixin.networkVars =
{
    powered = "boolean"
}

function TurretMixin:__initmixin()
    self.powered = false
    self.requiresupgtf = false
    self.tfId = nil
end

function TurretMixin:SetRequiresAdvanced()
    self.requiresupgtf = true
end

function TurretMixin:GetRequiresAdvanced()
    return self.requiresupgtf
end

function TurretMixin:GetIsPowered()
    return self.powered
end

if Server then

    local function RemoveTurret(self)
        if self.tfId ~= nil then
            local tfac = Shared.GetEntity(self.tfId)
            if tfac then
                tfac:RemoveConsumer(self)
            end
        end
    end

    local function FindNewTF(self, tfac)
    
        local turretfactories = GetEntitiesWithMixin("TurretFactory")
        Shared.SortEntitiesByDistance(self:GetOrigin(), turretfactories)
        for index, turretfac in ipairs(turretfactories) do
            local toTarget = turretfac:GetOrigin() - self:GetOrigin()
            local distanceToTarget = toTarget:GetLength()
            if distanceToTarget < kRoboticsFactoryAttachRange and GetIsUnitActive(turretfac) then
                if self.requiresupgtf and turretfac:GetTechId() == kTechId.ARCRoboticsFactory or not self.requiresupgtf then
                    if tfac == nil or (tfac ~= nil and turretfac ~= tfac) then
                        return turretfac
                    end
                end
            end
        end
        
    end

    local function CheckForTF(self, tfac)
                
        local tf = FindNewTF(self, tfac)
        if tf then
            if not self.powered then
                tf:AddConsumer(self)
                self.powered = true
                self.tfId = tf:GetId()           
                if self.OnPowerOn then
                    self:OnPowerOn()
                end
            elseif tf:GetId() ~= self.tfId then
                self.tfId = tf:GetId()
                tf:AddConsumer(self)     
            end
        else
            if self.powered then
                self.powered = false
                self.tfId = Entity.invalidId         
                if self.OnPowerOff then
                    self:OnPowerOff()
                end
            end
        end        
    end

    function TurretMixin:OnConstructionComplete()
        CheckForTF(self)
        if self.powered then
            self:TriggerEffects("deploy")     
        end 
    end
    
    function TurretMixin:OnTurretFactoryDestroyed(tfac)
        CheckForTF(self, tfac)        
    end
    
    function TurretMixin:OnTurretFactoryCompleted()
        CheckForTF(self)        
    end
    
    function TurretMixin:OnRecycled()
        RemoveTurret(self)
    end
    
    function TurretMixin:OnKill()
        RemoveTurret(self)
    end

    function TurretMixin:OnDestroy()
        RemoveTurret(self)
    end
    
elseif Client then


end

function TurretMixin:OnUpdateAnimationInput(modelMixin)

    PROFILE("TurretFactoryMixin:OnUpdateAnimationInput")
    modelMixin:SetAnimationInput("powered", self:GetIsPowered())
    
end