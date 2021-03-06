//    
// lua\CoreMoveMixin.lua
// Consolidated gldsrce style movement logic.

Script.Load("lua/Mixins/BaseMoveMixin.lua")

CoreMoveMixin = CreateMixin( CoreMoveMixin )
CoreMoveMixin.type = "CoreMoveMixin"

CoreMoveMixin.expectedMixins =
{
    BaseMove = "Give basic method to handle player or entity movement"
}

CoreMoveMixin.expectedCallbacks =
{
    GetMaxSpeed = "Returns MaxSpeed of moveable entity.",
	GetAcceleration = "Gets the acceleration amount for this entity.",
	GetGroundFriction = "Gets the base ground friction applied to entity.",
	GetJumpVelocity = "Gets the jumping velocity increase for this entity.",
	PerformsVerticalMove = "If pitch should be considered when calculating velocity.",
	GetMaxAirVeer = "Maximum amount of velocity change midair.",
	GetCrouchShrinkAmount = "Amount the entity shrinks when crouching.",
	GetCanCrouch = "If the entity can crouch.",
	GetSlowOnLand = "If the entity should be slowed on land.",
	GetClimbFrictionForce = "Friction when climbing ladder.",
	GetMaxBackwardSpeedScalar = "Maximum backpeddling speed scalar.",
	GetIsOnSurface = "Used for overriding OnGround.",
	OnTakeFallDamage = "For taking applicable fall damage.",
	GetIsForwardOverrideDesired = "Allows children to alter forward override state."
}

CoreMoveMixin.optionalCallbacks =
{
    PreUpdateMove = "Allows children to update state before the update happens.",
	ModifyVelocity = "Allows children to update state after new velocity is calculated, but before position is updated.",
	OnPositionUpdated = "Allows children to update state after new position is calculated.",
    PostUpdateMove = "Allows children to update state after the update happens.",
	OnGroundOverride = "Allows children to override onGround status.",
	GetDistanceToGround = "Allows children to override ground distance check.",
	OnGroundChanged = "Allows children to update on a ground state change.",
	AdjustGravityForce = "Allows children to adjust the force of gravity.",
	OverrideWishVelocity = "Allows children to override wishvelocity.",
	OverrideJump = "Allows children to override jump handling.",
	OnJump = "Allows children to update state after a jump."
}

CoreMoveMixin.networkVars =
{
    onGround = "compensated boolean",
    timeLastOnGround = "private time",
    timeTouchedGround = "private time",
    jumpHandled = "private compensated boolean",
    timeOfLastJump = "private time",
    jumping = "compensated boolean",
    onLadder = "compensated boolean",
    crouching = "compensated boolean",
    timeOfCrouchChange = "compensated time",
    lastimpact = "interpolated float (0 to 1 by 0.01)",
}

local kNetPrecision = 1/128
local kMaxDeltaTime = 0.07
local kOnGroundDistance = 0.1
local kMaxSpeedClampPerJump = 3.0
local kBunnyJumpMaxSpeedFactor = 1.7
local kCrouchAnimationTime = 0.4
local kCrouchSpeedScalar = 0.6
local kSlowOnLandScalar = 0.33
local kLandGraceTime = 0.1
local kMinimumJumpTime = 0.05
local kStopSpeed = 2.0
local kStepHeight = 0.5
local kStopSpeedScalar = 2
local kDownSlopeFactor = math.tan( math.rad(45) ) // Stick to ground on down slopes up to 45 degrees

function CoreMoveMixin:__initmixin()
    self.onGround = true
    self.timeLastOnGround = 0
    self.timeTouchedGround = 0
    self.onLadder = false
    self.jumping = false
    self.jumpHandled = false
    self.timeOfLastJump = 0
    self.crouching = false
    self.timeOfCrouchChange = 0
    self.lastimpact = 0
end

function CoreMoveMixin:GetStepHeight()
    return kStepHeight
end

function CoreMoveMixin:GetStopSpeed()
    return kStopSpeed
end
 
function CoreMoveMixin:GetCanStepOver(entity)
    return false
end

function CoreMoveMixin:GetCanStep()
    return true
end

function CoreMoveMixin:GetLastInput()
    return self.latestinput
end

function CoreMoveMixin:SetLastInput(input)
    self.latestinput = input
end

function CoreMoveMixin:GetIsJumping()
    return self.jumping
end

function CoreMoveMixin:SetIsJumping(Jumping)
    self.jumping = Jumping
end

function CoreMoveMixin:GetIsJumpHandled()
    return self.jumpHandled
end

function CoreMoveMixin:SetIsJumpHandled(Jumped)
    self.jumpHandled = Jumped
end

function CoreMoveMixin:GetLandedRecently()
    return self.timeTouchedGround + kLandGraceTime > Shared.GetTime()
end

function CoreMoveMixin:GetIsOnGround()
    if self.OnGroundOverride then
        return self:OnGroundOverride(self.onGround)
    end
    return self.onGround
end

function CoreMoveMixin:GetLastJumpTime()
    return self.timeOfLastJump
end

function CoreMoveMixin:GetWithinJumpWindow()
    return self.timeOfLastJump + kMinimumJumpTime > Shared.GetTime()
end

function CoreMoveMixin:UpdateLastJumpTime()
    self.timeOfLastJump = Shared.GetTime()
end

function CoreMoveMixin:GetLastImpactForce()
    return self.lastimpact
end

function CoreMoveMixin:SetIsOnGround(onGround)
    self.onGround = onGround
end

local function SplineFraction(value, scale)
    value = scale * value
    local valueSq = value * value
    
    // Nice little ease-in, ease-out spline-like curve
    return 3.0 * valueSq - 2.0 * valueSq * value
end

function CoreMoveMixin:GetCrouchAmount()  
    local crouchScalar = ConditionalValue(self.crouching, 1, 0)
    if self.lastcrouchamountcalc == Shared.GetTime() then
        return self.lastcrouchamount
    end
    if self.timeOfCrouchChange > 0 then
		local crouchtime = Shared.GetTime() - self.timeOfCrouchChange
        if(self.crouching) then
            crouchScalar = SplineFraction(crouchtime / kCrouchAnimationTime, 1.0)
        else
            if crouchtime >= (kCrouchAnimationTime * 0.5) then
                crouchScalar = 0
            else
                crouchScalar = SplineFraction(1.0 - (crouchtime / (kCrouchAnimationTime * 0.5)), 1.0)
            end
        end
    end
    self.lastcrouchamountcalc = Shared.GetTime()
    self.lastcrouchamount = crouchScalar
    return crouchScalar
end

function CoreMoveMixin:GetCrouching()
    return self.crouching
end

function CoreMoveMixin:GetIsOnLadder()
    return self.onLadder
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

local function UpdateJumpLand(self, velocity)

    // If we landed this frame
    if self.jumping then
        self.jumping = false
        if self.OnJumpLand then
            self:OnJumpLand(self:GetLastImpactForce())
        end
        if self:GetSlowOnLand(velocity) then
            self:AddSlowScalar(kSlowOnLandScalar)
            velocity:Scale(kSlowOnLandScalar)
        end
    end
    
end

local function UpdateFallDamage(self, previousVelocity)
	if math.abs(previousVelocity.y) > kFallDamageMinimumVelocity then
		local damage = math.max(0, math.abs(previousVelocity.y * kFallDamageScalar) - kFallDamageMinimumVelocity * kFallDamageScalar)
		self:OnTakeFallDamage(damage)
	end
end

local function UpdateOnGroundState(self, previousVelocity, velocity)
    
    local onGround = false
    onGround = GetIsCloseToGround(self, self.GetDistanceToGround and self:GetDistanceToGround() or kOnGroundDistance)
    if onGround then
        self.timeLastOnGround = Shared.GetTime()
        if not self.onGround then
            self.timeTouchedGround = Shared.GetTime()
            self.lastimpact = math.min(math.abs(previousVelocity.y / 10), 1)
            UpdateJumpLand(self, velocity)
            UpdateFallDamage(self, previousVelocity)
        end
    end
    if onGround ~= self.onGround then
        self.onGround = onGround
		if self.OnGroundChanged then
			self:OnGroundChanged()
		end
    end
    
end

local function ApplyHalfGravity(self, input, velocity, time)
	local gforce = self:GetGravityForce(input)
	if self.AdjustGravityForce then
		gforce = self:AdjustGravityForce(input, gforce)
	end
	velocity.y = velocity.y + gforce * time * 0.5
end

local function GetWishVelocity(self, input)

    if self.OverrideWishVelocity then
        return self:OverrideWishVelocity(input)
    end

    local maxspeed = self:GetMaxSpeed()
    
    if input.move.z < 0 then
        maxspeed = maxspeed * self:GetMaxBackwardSpeedScalar()
    end
    
    // Override forward input to allow greater ease of use if set.
    if not self.forwardModifier and input.move.z > 0 and input.move.x ~= 0 and self:GetIsForwardOverrideDesired() then
        input.move.z = 0
    end

    // wishdir
    local move = GetNormalizedVector(input.move)
    move:Scale(maxspeed)
    
    // grab view angle (ignoring pitch)
    local angles = self:ConvertToViewAngles(0, input.yaw, 0)
    
    if self:PerformsVerticalMove() then
        angles = self:ConvertToViewAngles(input.pitch, input.yaw, 0)
    end
    
    local viewCoords = angles:GetCoords() // to matrix?
    local moveVelocity = viewCoords:TransformVector(move) // get world-space move direction
    
    return moveVelocity
end

local function ApplyFriction(self, input, velocity, time)

    if self:GetIsOnSurface() or self:GetIsOnLadder() then
	
        // Calculate speed
        local speed = velocity:GetLength()
        
        if speed < 0.0001 then
            return velocity
        end
        
        local friction = self:GetGroundFriction()
        if self:GetIsOnLadder() then
            friction = self:GetClimbFrictionForce()
        end
        
        local stopspeed = self:GetStopSpeed()
        // Try bleeding at accelerated value when no inputs
        if input.move.x == 0 and input.move.y == 0 and input.move.z == 0 then
            stopspeed = stopspeed * kStopSpeedScalar
        end
        // Bleed off some speed, but if we have less than the bleed
		//  threshhold, bleed the theshold amount.
        local control = (speed < stopspeed) and stopspeed or speed
        
        // Add the amount to the drop amount.
        local drop = control * friction * time
        
        // scale the velocity
        local newspeed = speed - drop
        if newspeed < 0 then
            newspeed = 0
        end
        
        // Determine proportion of old speed we are using.
        newspeed = newspeed / speed
        
        // Adjust velocity according to proportion.
        velocity:Scale(newspeed)
		
    end
	
end

local function Accelerate(self, velocity, time, wishdir, wishspeed, acceleration)
    // Determine veer amount    
    local currentspeed = velocity:DotProduct(wishdir)
    
    // See how much to add
    local addSpeed = wishspeed - currentspeed

    // If not adding any, done.
    if addSpeed <= 0.0 then
        return velocity
    end
    
    // Determine acceleration speed after acceleration
    local accelspeed = acceleration * wishspeed * time
    
    // Cap it
    if accelspeed > addSpeed then
        accelspeed = addSpeed
    end
    
    wishdir:Scale(accelspeed)
    
    // Add to velocity
    velocity:Add(wishdir)
    
    return velocity
end

local function AirAccelerate(self, velocity, time, wishdir, wishspeed, acceleration)
    if wishspeed > self:GetMaxAirVeer() then
        wishspeed = self:GetMaxAirVeer()
    end
    return Accelerate(self, velocity, time, wishdir, wishspeed, acceleration)
end

local function DoStepMove(self, input, velocity, time)
    
    local oldOrigin = Vector(self:GetOrigin())
    local oldVelocity = Vector(velocity)
    local success = false
    local stepAmount = 0
    
    // step up at first
    self:PerformMovement(Vector(0, self:GetStepHeight(), 0), 1)
    stepAmount = self:GetOrigin().y - oldOrigin.y
    // do the normal move
    local startOrigin = Vector(self:GetOrigin())
    local completedMove, hitEntities, averageSurfaceNormal = self:PerformMovement(velocity * time, 3, velocity, true)
    local horizMoveAmount = (startOrigin - self:GetOrigin()):GetLengthXZ()
    
    if completedMove then
        // step down again
        local completedMove, hitEntities, averageSurfaceNormal = self:PerformMovement(Vector(0, -stepAmount - horizMoveAmount * kDownSlopeFactor, 0), 1)
        
        local onGround, normal = GetIsCloseToGround(self, 0.15)
        
        if onGround then
            success = true
        end

    end    
        
    // not succesful. fall back to normal move
    if not success then
    
        self:SetOrigin(oldOrigin)
        VectorCopy(oldVelocity, velocity)
        self:PerformMovement(velocity * time, 3, velocity, true)
        
    end

    return success

end

local function CollisionEnabledPositionUpdate(self, input, velocity, time)
    local oldVelocity = Vector(velocity)
    local stepAllowed = self.onGround and self:GetCanStep()
    local didStep = false
    local stepAmount = 0
    local hitObstacle = false

    // check if we are allowed to step:
    local completedMove, hitEntities, averageSurfaceNormal = self:PerformMovement(velocity * time * 2, 3, nil, false)

    if stepAllowed and hitEntities then
    
        for i = 1, #hitEntities do
            if not self:GetCanStepOver(hitEntities[i]) then
            
                hitObstacle = true
                stepAllowed = false
                break
                
            end
        end
    
    end
    
    if not stepAllowed then
    
        if hitObstacle then
            velocity.y = oldVelocity.y
        end
        
        self:PerformMovement(velocity * time, 3, velocity, true)
        
    else        
        didStep, stepAmount = DoStepMove(self, input, velocity, time)            
    end
    
    if self.OnPositionUpdated then
        self:OnPositionUpdated(self:GetOrigin() - self.prevOrigin, stepAllowed, input, velocity)
    end
end

local function UpdatePosition(self, input, velocity, time)
    
    if self.controller then
		CollisionEnabledPositionUpdate(self, input, velocity, time)        
    end
    
end

//Movement Modifiers -Ladders, Jumping, Crouching etc.
function CoreMoveMixin:SetIsOnLadder(onLadder, ladderEntity)
    self.onLadder = onLadder
end

local function PreventMegaBunnyJumping(self, velocity)
    local maxscaledspeed = kBunnyJumpMaxSpeedFactor * self:GetMaxSpeed()
    
    if maxscaledspeed > 0.0 then
       local spd = velocity:GetLength()
        
        if spd > maxscaledspeed then
            local fraction = (maxscaledspeed / (maxscaledspeed + Clamp(spd - maxscaledspeed, 0, kMaxSpeedClampPerJump)))
            velocity:Scale(fraction)
        end
    end
end

local function CheckSpaceAboveForJump(self)

    local startPoint = self:GetOrigin() + Vector(0, self:GetExtents().y, 0)
    local endPoint = startPoint + Vector(0, 0.5, 0)
    local trace = Shared.TraceCapsule(startPoint, endPoint, 0.1, self:GetExtents().y, CollisionRep.Move, PhysicsMask.Movement, EntityFilterOne(self))
    
    return trace.fraction == 1
    
end

local function GetCanJump(self)
    return self:GetIsOnGround() and CheckSpaceAboveForJump(self)
end

local function HandleJump(self, input, velocity)

    if bit.band(input.commands, Move.Jump) ~= 0 and not self:GetIsJumpHandled() then
    
        if self.OverrideJump then
            self:OverrideJump(input, velocity)
        else
            if GetCanJump(self) then
            
                PreventMegaBunnyJumping(self, velocity)
                self:GetJumpVelocity(input, velocity)
                
                self:UpdateLastJumpTime()
                self:SetIsOnGround(false)
                self:SetIsJumping(true)
                
                if self.OnJump then
                    self:OnJump()
                end
                
                if self:GetJumpMode() == kJumpMode.Repeating then
                    self:SetIsJumpHandled(false)
                else
                    self:SetIsJumpHandled(true)
                end
                
            elseif self:GetJumpMode() == kJumpMode.Default then
            
                self:SetIsJumpHandled(true)
                
            end
        end
        
    end
    
end

local function UpdateCrouchState(self, input, time)
	local crouchDesired = bit.band(input.commands, Move.Crouch) ~= 0	
    if crouchDesired == self.crouching then
		//If enough time has passed, clear time.
		if self.timeOfCrouchChange > 0 and self.timeOfCrouchChange + kCrouchAnimationTime < Shared.GetTime() then
			self.timeOfCrouchChange = 0
		end
        return
    end
   
    if not crouchDesired then
        
        // Check if there is room for us to stand up.
        self.crouching = crouchDesired
        self:UpdateControllerFromEntity()
        
        if self:GetIsColliding() then
            self.crouching = true
            self:UpdateControllerFromEntity()
        else
            self.timeOfCrouchChange = Shared.GetTime()
        end
        
    elseif self:GetCanCrouch() then
        self.crouching = crouchDesired
        self.timeOfCrouchChange = Shared.GetTime()
        self:UpdateControllerFromEntity()
    end
end

local function CheckFullPrecisionOrigin(self)
    if self.fullPrecisionOrigin then
        local orig = self:GetOrigin()
        local delta = orig:GetDistance(self.fullPrecisionOrigin)
        if delta < kNetPrecision then
            // Origin has lost some precision due to network rounding, use full precision
            self:SetOrigin(self.fullPrecisionOrigin);
        //else
            // the change must be due to an external event, so don't use the fullPrecision            
            //Log("%s: external origin change, %s -> %s (%s)", self, netPrec, orig, delta)
        end
    end
    self.prevOrigin = Vector(self:GetOrigin())
end

local function UpdateFullPrecisionOrigin(self)
    self.fullPrecisionOrigin = Vector(self:GetOrigin())
end

// Update origin and velocity from input.
function CoreMoveMixin:UpdateMove(input)

    local runningPrediction = Shared.GetIsRunningPrediction()
    local previousVelocity = self:GetVelocity()
    local time = input.time //math.min(input.time, kMaxDeltaTime)
    
    CheckFullPrecisionOrigin(self)    
    
    if self.PreUpdateMove then
        self:PreUpdateMove(input, runningPrediction)
    end
    
    // Note: Using self:GetVelocity() anywhere else in the movement code may lead to buggy behavior.
    local velocity = Vector(previousVelocity)
    
    // If we were on ground at the end of last frame, zero out vertical velocity while
    // calling GetIsOnGround, as to not trip it into thinking you're in the air when moving
    // on curved surfaces
    if self:GetIsOnGround() then
        velocity.y = 0
    end
    
    local wishdir = GetWishVelocity(self, input)
    local wishspeed = wishdir:Normalize()
    
    // Modifiers
    HandleJump(self, input, velocity)
    UpdateCrouchState(self, input, time)
    
    // Apply first half of the gravity
    ApplyHalfGravity(self, input, velocity, time)
    
    // Run friction
    ApplyFriction(self, input, velocity, time)
    
    // Accelerate
    if self:GetIsOnSurface() then
        Accelerate(self, velocity, time, wishdir, wishspeed, self:GetAcceleration())
    else
        AirAccelerate(self, velocity, time, wishdir, wishspeed, self:GetAcceleration())
    end
    
    // Apply second half of the gravity
    ApplyHalfGravity(self, input, velocity, time)
    
    if self.ModifyVelocity then
        self:ModifyVelocity(input, velocity, time)
    end
    
    UpdatePosition(self, input, velocity, time)
    
    if not self:GetWithinJumpWindow() then //Accounts for high moverates
        UpdateOnGroundState(self, previousVelocity, velocity)
    end
   
    // Store new velocity
    self:SetVelocity(velocity)
    
    if self.PostUpdateMove then
        self:PostUpdateMove(input, runningPrediction)
    end
	
    self:SetLastInput(input)
    UpdateFullPrecisionOrigin(self)
    
end