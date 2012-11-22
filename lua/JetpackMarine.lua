// ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
//
// lua\JetpackMarine.lua
//
//    Created by:   Andreas Urwalek (a_urwa@sbox.tugraz.at
//
//    Thanks to twiliteblue for initial input.
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================
Script.Load("lua/Marine.lua")
Script.Load("lua/Jetpack.lua")

class 'JetpackMarine' (Marine)

JetpackMarine.kMapName = "jetpackmarine"

JetpackMarine.kModelName = PrecacheAsset("models/marine/male/male.model")
JetpackMarine.kSpecialModelName = PrecacheAsset("models/marine/male/male_special.model")

JetpackMarine.kJetpackStart = PrecacheAsset("sound/NS2.fev/marine/common/jetpack_start")
JetpackMarine.kJetpackEnd = PrecacheAsset("sound/NS2.fev/marine/common/jetpack_end")
JetpackMarine.kJetpackPickupSound = PrecacheAsset("sound/NS2.fev/marine/common/pickup_jetpack")
local kJetpackLoop = PrecacheAsset("sound/NS2.fev/marine/common/jetpack_on")

// for animation only
JetpackMarine.kAnimFlySuffix = "_jetpack"
JetpackMarine.kAnimTakeOffSuffix = "_jetpack_takeoff"
JetpackMarine.kAnimLandSuffix = "_jetpack_land"

JetpackMarine.kJetpackNode = "JetPack"

if Server then
    Script.Load("lua/JetpackMarine_Server.lua")
elseif Client then
    Script.Load("lua/JetpackMarine_Client.lua")
end

JetpackMarine.kJetpackFuelReplenishDelay = .2

// Allow JPers to go faster in the air, but still capped
JetpackMarine.kVerticalThrustAccelerationMod = 10.0
JetpackMarine.kVerticalFlyAccelerationMod = 1.3
JetpackMarine.kJetpackAcceleration = 22
JetpackMarine.kWalkMaxSpeed = 4.0                // Four miles an hour = 6,437 meters/hour = 1.8 meters/second (increase for FPS tastes)
JetpackMarine.kRunMaxSpeed = 6.5
JetpackMarine.kFlyMaxSpeed = 8.5

JetpackMarine.kJetpackArmorBonus = kJetpackArmor
JetpackMarine.kJetpackTakeOffTime = .01

JetpackMarine.kJetpackMode = enum( {'Disabled', 'TakeOff', 'Flying', 'Landing'} )

local networkVars =
{
    // jetpack fuel is dervived from the three variables jetpacking, timeJetpackingChanged and jetpackFuelOnChange
    // time since change has the kJetpackFuelReplenishDelay subtracted if not jetpacking
    // jpFuel = Clamp(jetpackFuelOnChange + time since change * gain/loss rate, 0, 1)
    // If jetpack is currently active and affecting our movement. If active, use loss rate, if inactive use gain rate
    jetpacking = "boolean",
    // when we last changed state of jetpack
    timeJetpackingChanged = "compensated time",
    // amount of fuel when we last changed jetpacking state
    jetpackFuelOnChange = "float (0 to 1 by 0.01)",
    
    startedFromGround = "boolean",
    
    jetpackFuelRate = "float(0 to 1 by 0.01)",
    
    equipmentId = "entityid",
    jetpackMode = "enum JetpackMarine.kJetpackMode",
    
    jetpackLoopId = "entityid"
}

function JetpackMarine:OnCreate()

    Marine.OnCreate(self)
    
    self.jetpackMode = JetpackMarine.kJetpackMode.Disabled
    
    self.jetpackLoopId = Entity.invalidId
    
end

local function InitEquipment(self)

    assert(Server)
    
    self.jetpackFuelRate = kJetpackUseFuelRate    

    self.jetpackFuelOnChange = 1
    self.timeJetpackingChanged = Shared.GetTime()
    self.jetpacking = false
    
    Shared.PlaySound(self, JetpackMarine.kJetpackPickupSound)
    
    self.jetpackLoop = Server.CreateEntity(SoundEffect.kMapName)
    self.jetpackLoop:SetAsset(kJetpackLoop)
    self.jetpackLoop:SetParent(self)
    self.jetpackLoopId = self.jetpackLoop:GetId()
    
    local jetpack = CreateEntity(JetpackOnBack.kMapName, self:GetAttachPointOrigin(Jetpack.kAttachPoint), self:GetTeamNumber())
    jetpack:SetParent(self)
    jetpack:SetAttachPoint(Jetpack.kAttachPoint)
    self.equipmentId = jetpack:GetId()
    
    if GetHasTech(self, kTechId.JetpackFuelTech) then
        self:UpgradeJetpackMobility()
    end 
    
    if GetHasTech(self, kTechId.JetpackArmorTech) then
    
        local armorPercent = self.armor/self.maxArmor
        self.maxArmor = self:GetArmorAmount()
        self.armor = self.maxArmor * armorPercent
        
    end
    
end

function JetpackMarine:OnInitialized()

    // Using the Jetpack is very important. This is
    // a priority before anything else for the JetpackMarine.
    if Client then
        self:AddHelpWidget("GUIMarineJetpackHelp", 2)
    end
    
    Marine.OnInitialized(self)
    
    if Server then
       InitEquipment(self)
    end
    
end

local function DestroyFuelGUI(self)

    if Client and self.guiFuelDisplay then
    
        GetGUIManager():DestroyGUIScript(self.guiFuelDisplay)
        self.guiFuelDisplay = nil
        
    end
    
end

function JetpackMarine:OnDestroy()

    Marine.OnDestroy(self)
    
    DestroyFuelGUI(self)
    
    self.equipmentId = Entity.invalidId
    self.jetpackLoopId = Entity.invalidId
    if Server then
    
        // The children have already been destroyed.
        self.jetpackLoop = nil
        
    end
    
end

function JetpackMarine:OnKillClient()

    Marine.OnKillClient(self)
    
    DestroyFuelGUI(self)
    
end

function JetpackMarine:GetHasEquipment()
    return true
end

function JetpackMarine:GetFuel()

    local dt = Shared.GetTime() - self.timeJetpackingChanged
    local rate = -self.jetpackFuelRate
    if not self.jetpacking then
        rate = kJetpackReplenishFuelRate
        dt = math.max(0, dt - JetpackMarine.kJetpackFuelReplenishDelay)
    end
    return Clamp(self.jetpackFuelOnChange + rate * dt, 0, 1)
    
end

function JetpackMarine:GetJetpack()
    return Shared.GetEntity(self.equipmentId)
end

function JetpackMarine:OnEntityChange(oldId, newId)

    if oldId == self.equipmentId and newId then
        self.equipmentId = newId
    end

end

function JetpackMarine:GetSlowOnLand()
    return false
end

function JetpackMarine:ReceivesFallDamage()
    return false
end

function JetpackMarine:GetArmorAmount()

    local jetpackArmorBonus = 0    
    
    if GetHasTech(self, kTechId.JetpackArmorTech) then
        jetpackArmorBonus = 1
    end
    
    return Marine.GetArmorAmount(self) + JetpackMarine.kJetpackArmorBonus * jetpackArmorBonus
    
end



function JetpackMarine:HasJetpackDelay()

    if (Shared.GetTime() - self.timeJetpackingChanged > JetpackMarine.kJetpackFuelReplenishDelay) then
        return false
    end
    
    return true
    
end

function JetpackMarine:GetIsOnGround()

    if self.jetpacking then
        //return false
    end
    
    return Marine.GetIsOnGround(self)
    
end

function JetpackMarine:HandleJetpackStart()

    self.jetpackFuelOnChange = self:GetFuel()
    self.jetpacking = true
    self.timeJetpackingChanged = Shared.GetTime()
    
    self.startedFromGround = self:GetIsOnGround() or self.timeOfLastJump == Shared.GetTime()
    
    self:GetJetpack():SetIsFlying(true)
    
end

function JetpackMarine:HandleJetPackEnd()

    Shared.PlaySound(self, JetpackMarine.kJetpackEnd)
    
    if Server then
        self.jetpackLoop:Stop()
    end
    self.jetpackFuelOnChange = self:GetFuel()
    self.jetpacking = false
    self.timeJetpackingChanged = Shared.GetTime()
    self.jetpacking = false
    
    local animName = self:GetWeaponName() .. JetpackMarine.kAnimLandSuffix
    
    self:GetJetpack():SetIsFlying(false)
    
end

// needed for correct fly pose
function JetpackMarine:GetWeaponName()

    local currentWeapon = self:GetActiveWeaponName()
    
    if currentWeapon then
        return string.lower(currentWeapon)
    else
        return nil
    end
    
end

function JetpackMarine:GetMaxBackwardSpeedScalar()
    if not self:GetIsOnGround() then
        return 1
    end

    return Player.GetMaxBackwardSpeedScalar(self)
end

function JetpackMarine:UpdateJetpack(input)

    local jumpPressed = (bit.band(input.commands, Move.Jump) ~= 0)
    
    self:UpdateJetpackMode()
    
    // handle jetpack start, ensure minimum wait time to deal with sound errors
    if not self.jetpacking and (Shared.GetTime() - self.timeJetpackingChanged > 0.2) and jumpPressed and self:GetFuel()> 0 then
    
        self:HandleJetpackStart()
        
        if Server then
            self.jetpackLoop:Start()
        end
        
    end
    
    // handle jetpack stop, ensure minimum flight time to deal with sound errors
    if self.jetpacking and (Shared.GetTime() - self.timeJetpackingChanged) > 0.2 and (self:GetFuel()== 0 or not jumpPressed) then
        self:HandleJetPackEnd()
    end
    
    if Client then
    
        local jetpackLoop = Shared.GetEntity(self.jetpackLoopId)
        if jetpackLoop then
            jetpackLoop:SetParameter("fuel", self:GetFuel(), 1)
        end
        
    end

end

// required to not stick to the ground during jetpacking
/*
function JetpackMarine:ComputeForwardVelocity(input)

    // Call the original function to get the base forward velocity.
    local forwardVelocity = Marine.ComputeForwardVelocity(self, input)
    
    if self:GetIsJetpacking() then
        forwardVelocity = forwardVelocity + Vector(0, 2, 0) * input.time
    end
    
    return forwardVelocity
    
end
*/

function JetpackMarine:HandleButtons(input)

    Marine.HandleButtons(self, input)
    
    self:UpdateJetpack(input)
    
end

function JetpackMarine:GetCrouchSpeedScalar()

    if self:GetIsJetpacking() then
        return 0
    end
    
    return Player.kCrouchSpeedScalar
    
end

function JetpackMarine:GetInventorySpeedScalar()
    return 1 - (self:GetWeaponsWeight() / kJetpackWeightAssist)
end

function JetpackMarine:GoldSrc_GetMaxSpeed(possible)

    if possible then
        return JetpackMarine.kRunMaxSpeed
    end
    
    if self:GetIsDisrupted() then
        return 0
    end
    
    local maxSpeed = JetpackMarine.kRunMaxSpeed
    
    if self.movementModiferState and self:GetIsOnSurface() then
        maxSpeed = JetpackMarine.kWalkMaxSpeed
    end
    
    // GetIsOnGround is used to not lose our jetpacking speed when jump is released to lose height
    if self:GetIsJetpacking() or not self:GetIsOnGround() then
        maxSpeed = JetpackMarine.kFlyMaxSpeed
    end
    
    // Take into account our weapon inventory and current weapon. Assumes a vanilla marine has a scalar of around .8.
    local inventorySpeedScalar = self:GetInventorySpeedScalar()

    local adjustedMaxSpeed = maxSpeed * self:GetCatalystMoveSpeedModifier() * self:GetSlowSpeedModifier() * inventorySpeedScalar 
    //Print("Adjusted max speed => %.2f (without inventory: %.2f)", adjustedMaxSpeed, adjustedMaxSpeed / inventorySpeedScalar )
    
    return adjustedMaxSpeed
    
end

function JetpackMarine:GetMaxSpeed(possible)

    if possible then
        return JetpackMarine.kRunMaxSpeed
    end
    
    if self:GetIsDisrupted() then
        return 0
    end
    
    local maxSpeed = JetpackMarine.kRunMaxSpeed
    
    if self.movementModiferState and self:GetIsOnSurface() then
        maxSpeed = JetpackMarine.kWalkMaxSpeed
    end
    
    // GetIsOnGround is used to not lose our jetpacking speed when jump is released to lose height
    if self:GetIsJetpacking() or not self:GetIsOnGround() then
        maxSpeed = JetpackMarine.kFlyMaxSpeed
    end
    
    // Take into account crouching
    if self:GetCrouching() and self:GetIsOnGround() then
        maxSpeed = ( 1 - self:GetCrouchAmount() * self:GetCrouchSpeedScalar() ) * maxSpeed
    end
    
    // Take into account our weapon inventory and current weapon. Assumes a vanilla marine has a scalar of around .8.
    local inventorySpeedScalar = self:GetInventorySpeedScalar()

    local adjustedMaxSpeed = maxSpeed * self:GetCatalystMoveSpeedModifier() * self:GetSlowSpeedModifier() * inventorySpeedScalar 
    //Print("Adjusted max speed => %.2f (without inventory: %.2f)", adjustedMaxSpeed, adjustedMaxSpeed / inventorySpeedScalar )
    
    return adjustedMaxSpeed
    
end

function JetpackMarine:GetIsTakingOffFromGround()
    return self.startedFromGround and (self.timeJetpackingChanged + JetpackMarine.kJetpackTakeOffTime > Shared.GetTime())
end

function JetpackMarine:GoldSrc_AirAccelerate(velocity, time, wishdir, wishspeed, acceleration)
    if not self:GetIsJetpacking() and wishspeed > Player.kMaxAirVeer then
        wishspeed = Player.kMaxAirVeer
    end
    
    return self:GoldSrc_Accelerate(velocity, time, wishdir, wishspeed, acceleration)
end

function JetpackMarine:GetJumpHeight()
    // Don't allow full jump
    return Player.kJumpHeight * 0.5
end

function JetpackMarine:GoldSrc_Accelerate(velocity, time, wishdir, wishspeed, acceleration)
    Marine.GoldSrc_Accelerate(self, velocity, time, wishdir, wishspeed, acceleration)
    
    // Add thrust from the jetpack
    if self:GetIsJetpacking() then
        Marine.GoldSrc_Accelerate(self, velocity, time, Vector(0,1,0), 9, 4)
    end
end

function JetpackMarine:GoldSrc_GetWishVelocity(input)
    if HasMixin(self, "Stun") and self:GetIsStunned() then
        return Vector(0,0,0)
    end
    
    // goldSrc maxspeed works different than ns2 maxspeed.
    // Here is it used as an acceleration target, in ns2
    // it's seemingly used for clamping the speed
    local maxspeed = self:GoldSrc_GetMaxSpeed()

    // wishdir
    local move = GetNormalizedVector(input.move)
    move:Scale(maxspeed)
    
    // grab view angle (ignoring pitch)
    local angles = self:ConvertToViewAngles(0, input.yaw, 0)
    
    if self:GetIsOnLadder() and not self:GetIsJetpacking() then
        angles = self:ConvertToViewAngles(input.pitch, input.yaw, 0)
    end
    
    local viewCoords = angles:GetCoords() // to matrix?
    local moveVelocity = viewCoords:TransformVector(move) // get world-space move direction
    
    // Scale down velocity if moving backwards
    if input.move.z < 0 then
        moveVelocity:Scale(self:GetMaxBackwardSpeedScalar())
    end
    
    return moveVelocity
end

function JetpackMarine:ModifyVelocity(input, velocity)      

    Marine.ModifyVelocity(self, input, velocity)

    if self:GetIsJetpacking() then

        local move = GetNormalizedVector( input.move ) 
        local angles = self:ConvertToViewAngles(0, input.yaw, 0) 
        local viewCoords = angles:GetCoords()     
        local redirectDir = viewCoords:TransformVector( move )
        local deltaVelocity = redirectDir * input.time * self:GoldSrc_GetAcceleration()
        
        velocity.x = velocity.x + deltaVelocity.x
        velocity.z = velocity.z + deltaVelocity.z
        // self:GoldSrc_GetAcceleration() * 
        
        // Allow thrust up until a point. (makes sense that the player stops accelerating when
        // the rockets nozzle speed is reached)
        local maxThrustVelocity = 8.0
        if velocity.y < maxThrustVelocity then
            local addspeed = math.min(velocity.y + input.time * 27.0, maxThrustVelocity) - velocity.y
            //velocity.y = velocity.y + addspeed
        end
        

    end
    
end

function JetpackMarine:GoldSrc_GetAcceleration()
    local acceleration = 0

    if self:GetIsJetpacking() then

        acceleration = JetpackMarine.kJetpackAcceleration * 0.11
        acceleration = acceleration * self:GetInventorySpeedScalar()

    else
        acceleration = Marine.GoldSrc_GetAcceleration(self)
    end
    
    return acceleration * self:GetSlowSpeedModifier()
end

function JetpackMarine:GetAcceleration()

    local acceleration = 0

    if self:GetIsJetpacking() then

        acceleration = JetpackMarine.kJetpackAcceleration
        acceleration = acceleration * self:GetInventorySpeedScalar()

    else
        acceleration = Marine.GetAcceleration(self)
    end
    
    return acceleration * self:GetSlowSpeedModifier()
    
end

function JetpackMarine:GetCanBeDisrupted()
    return self:GetIsOnGround()
end

function JetpackMarine:UpdateJetpackMode()

    local newMode = JetpackMarine.kJetpackMode.Disabled

    if self:GetIsJetpacking() then
    
        if ((Shared.GetTime() - self.timeJetpackingChanged) < JetpackMarine.kJetpackTakeOffTime) and (( Shared.GetTime() - self.timeJetpackingChanged > 1.5 ) or self:GetIsOnGround() ) then

            newMode = JetpackMarine.kJetpackMode.TakeOff

        else

            newMode = JetpackMarine.kJetpackMode.Flying

        end
    end

    if newMode ~= self.jetpackMode then
        self.jetpackMode = newMode
    end

end

function JetpackMarine:GetJetPackMode()

    return self.jetpackMode

end

function JetpackMarine:UpgradeJetpackMobility()

    self.jetpackFuelRate = kJetpackUpgradeUseFuelRate

end

function JetpackMarine:GetIsJetpacking()
    return self.jetpacking and (self:GetFuel()> 0) and not self:GetIsDisrupted()
end

/**
 * Since Jetpack is a child of JetpackMarine, we need to manually
 * call ProcessMoveOnModel() on it so animations play properly.
 */
function JetpackMarine:ProcessMoveOnModel(input)

    local jetpack = self:GetJetpack()
    if jetpack then
        jetpack:ProcessMoveOnModel(input)
    end
    
end

function JetpackMarine:OnTag(tagName)

    PROFILE("JetpackMarine:OnTag")

    Marine.OnTag(self, tagName)
    
    if tagName == "fly_start" and self.startedFromGround then
        Shared.PlaySound(self, JetpackMarine.kJetpackStart)
    end

end

function JetpackMarine:FallingAfterJetpacking()
    return (self.timeJetpackingChanged + 1.5 > Shared.GetTime()) and not self:GetIsOnGround()
end

function JetpackMarine:OnUpdateAnimationInput(modelMixin)

    Marine.OnUpdateAnimationInput(self, modelMixin)
    
    if self:GetIsJetpacking() or self:FallingAfterJetpacking() then
        modelMixin:SetAnimationInput("move", "jetpack")
    end

end

Shared.LinkClassToMap("JetpackMarine", JetpackMarine.kMapName, networkVars)