// ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
//
// lua\Fade.lua
//
//    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
//                  Max McGuire (max@unknownworlds.com)
//
// Role: Surgical striker, harassment
//
// The Fade should be a fragile, deadly-sharp knife. Wielded properly, it's force is undeniable. But
// used clumsily or without care will only hurt the user. Make sure Fade isn't better than the Skulk 
// in every way (notably, vs. Structures). To harass, he must be able to stay out in the field
// without continually healing at base, and needs to be able to use blink often.
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================

//NS2c
//Modified for goldsource movement, also made most vars local

Script.Load("lua/Utility.lua")
Script.Load("lua/Weapons/Alien/SwipeBlink.lua")
Script.Load("lua/Weapons/Alien/Metabolize.lua")
Script.Load("lua/Weapons/Alien/AcidRocket.lua")
Script.Load("lua/Alien.lua")
Script.Load("lua/Mixins/CameraHolderMixin.lua")
Script.Load("lua/DissolveMixin.lua")
Script.Load("lua/Weapons/PredictedProjectile.lua")

class 'Fade' (Alien)

Fade.kMapName = "fade"

Fade.kModelName = PrecacheAsset("models/alien/fade/fade.model")
local kViewModelName = PrecacheAsset("models/alien/fade/fade_view.model")
local kFadeAnimationGraph = PrecacheAsset("models/alien/fade/fade.animation_graph")

Shared.PrecacheSurfaceShader("models/alien/fade/fade.surface_shader")

if Server then
    Script.Load("lua/Fade_Server.lua")
end

Fade.XZExtents = .4
Fade.YExtents = .85

local kViewOffsetHeight = 1.7
local kMass = 76 // 50 // ~350 pounds
local kMaxSpeed = 4.5
local kMaxBlinkSpeed = 16 // ns1 fade blink is (3x maxSpeed) + celerity
local kWalkSpeed = 2
local kCrouchedSpeed = 1.8
local kBlinkImpulseForce = 85
local kFadeBlinkAutoJumpGroundDistance = 0.25

local networkVars =
{
    etherealStartTime = "private time",
    etherealEndTime = "private time",
    
    // True when we're moving quickly "through the ether"
    ethereal = "boolean"
}

AddMixinNetworkVars(CameraHolderMixin, networkVars)
AddMixinNetworkVars(DissolveMixin, networkVars)

function Fade:OnCreate()

    InitMixin(self, CameraHolderMixin, { kFov = kFadeFov })
    
    Alien.OnCreate(self)
    
    InitMixin(self, DissolveMixin)
    InitMixin(self, PredictedProjectileShooterMixin)
    
    if Server then
        self.isBlinking = false
    end
    
    self.etherealStartTime = 0
    self.etherealEndTime = 0
    self.ethereal = false
    
end

function Fade:OnInitialized()

    Alien.OnInitialized(self)
    
    self:SetModel(Fade.kModelName, kFadeAnimationGraph)
    
    if Client then
    
        self:AddHelpWidget("GUIFadeBlinkHelp", 2)
        
    end
    
end

function Fade:GetHeadAttachpointName()
    return "fade_tongue2"
end

function Fade:PreCopyPlayerData()
    self:SetIsVisible(true)
end

function Fade:GetBaseArmor()
    return kFadeArmor
end

function Fade:GetBaseHealth()
    return kFadeHealth
end

function Fade:GetArmorFullyUpgradedAmount()
    return kFadeArmorFullyUpgradedAmount
end

function Fade:ModifyCrouchAnimation(crouchAmount)    
    return Clamp(crouchAmount * (1 - ( (self:GetVelocityLength() - kMaxSpeed) / (kMaxSpeed * 0.5))), 0, 1)
end

/*function Fade:GetExtentsCrouchShrinkAmount()
    return ConditionalValue(self:GetIsOnGround() or not self:GetPreventCrouchExtents(), Player.GetExtentsCrouchShrinkAmount(self), 0)
end*/

function Fade:GetMaxViewOffsetHeight()
    return kViewOffsetHeight
end

function Fade:GetViewModelName()
    return kViewModelName
end

function Fade:GetPlayerControllersGroup()
    return PhysicsGroup.BigPlayerControllersGroup
end

function Fade:GetIsForwardOverrideDesired()
    return not self:GetIsBlinking() and not self:GetIsOnGround()
end

function Fade:OnTakeFallDamage()
end

function Fade:GetMaxSpeed(possible)

    if possible then
        return kMaxSpeed
    end
    
    local maxSpeed = kMaxSpeed
        
    if self.movementModiferState and self:GetIsOnSurface() then
        maxSpeed = kWalkSpeed
    end
    
    if self:GetCrouching() and self:GetCrouchAmount() == 1 and self:GetIsOnSurface() and not self:GetLandedRecently() then
        maxSpeed = kCrouchedSpeed
    end
        
    return maxSpeed + self:GetMovementSpeedModifier()
end

function Fade:GetMass()
    return kMass 
end

function Fade:GetIsBlinking()
    return self.ethereal and self:GetIsAlive()
end

function Fade:OnBlink()
    self:SetIsOnGround(false)
    self:SetIsJumping(true)
    self.ethereal = true
    self:TriggerEffects("blink_out")
end

local function GetIsCloseToGround(self, distance)
        
    local onGround = false
    local normal = Vector()
    local completedMove, hitEntities = nil

    if self.controller ~= nil then
        // Try to move the controller downward a small amount to determine if
        // we're on the ground.
        local offset = Vector(0, -distance, 0)
        // need to do multiple slides here to not get traped in V shaped spaces
        completedMove, hitEntities, normal = self:PerformMovement(offset, 3, nil, false)
        
        if normal and normal.y >= 0.5 then
            return true
        end
    end

    return false
    
end

function Fade:ModifyVelocity(input, velocity, deltaTime)

    PROFILE("Fade:ModifyVelocity")

    if self:GetIsBlinking() then
    
        // Blink impulse
        local zAxis = self:GetViewCoords().zAxis
        velocity:Add( zAxis * kBlinkImpulseForce * deltaTime )
        
        if self:GetIsOnGround() or GetIsCloseToGround(self, kFadeBlinkAutoJumpGroundDistance) then
            self:GetJumpVelocity(input, velocity)
        end
        
        // Cap groundspeed
        local groundspeed = velocity:GetLengthXZ()
        local maxspeed = kMaxBlinkSpeed + self:GetMovementSpeedModifier()
        local oldYvelocity = Clamp(velocity.y, (-1 * maxspeed), maxspeed)
        
        if groundspeed > maxspeed then
            velocity:Scale(maxspeed / groundspeed)
        end
        
        velocity.y = oldYvelocity
        
        self:DeductAbilityEnergy(kBlinkPulseEnergyCost)
        
        if self:GetEnergy() < kBlinkPulseEnergyCost then
            self:OnBlinkEnd()
        end
        
    end
    
end

function Fade:PostUpdateMove(input, runningPrediction)

    if self:GetIsBlinking() then
        self:SetIsJumping(true)
        self:SetIsOnGround(false)
    end
    
end

function Fade:OnBlinkEnd()
    if self:GetIsOnGround() then
        self:SetIsJumping(false)
    end
    self.ethereal = false
    self:TriggerEffects("blink_in")
end

local kFadeEngageOffset = Vector(0, 0.6, 0)
function Fade:GetEngagementPointOverride()
    return self:GetOrigin() + kFadeEngageOffset
end

function Fade:GetEngagementPointOverride()
    return self:GetOrigin() + Vector(0, 0.8, 0)
end

Shared.LinkClassToMap("Fade", Fade.kMapName, networkVars, true)