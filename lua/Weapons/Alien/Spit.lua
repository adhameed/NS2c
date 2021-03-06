// ======= Copyright (c) 2003-2013, Unknown Worlds Entertainment, Inc. All rights reserved. =======
//
// lua\Weapons\Alien\Spit.lua
//
//    Created by:   Andreas Urwalek (andi@unknownworlds.com)
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/PredictedProjectile.lua")
Script.Load("lua/DamageMixin.lua")

Shared.PrecacheSurfaceShader("materials/infestation/spit_decal.surface_shader")

class 'Spit' (PredictedProjectile)

Spit.kMapName            = "spit"
Spit.kClearOnImpact = true
Spit.kClearOnEnemyImpact = true

local networkVars = { }

local kSpitLifeTime = 8

Spit.kProjectileCinematic = PrecacheAsset("cinematics/alien/gorge/dripping_slime.cinematic")
Spit.kRadius = 0.05

AddMixinNetworkVars(TeamMixin, networkVars)

function Spit:OnCreate()

    PredictedProjectile.OnCreate(self)
    
    InitMixin(self, DamageMixin)
    InitMixin(self, TeamMixin)
    
    if Server then
        self:AddTimedCallback(Spit.TimeUp, kSpitLifeTime)
    end

end

function Spit:TimeUp()

    DestroyEntity(self)
    return false
    
end

function Spit:ProcessHit(targetHit, surface, normal)
    
    if Server and self:GetOwner() ~= targetHit then
        self:DoDamage(kSpitDamage, targetHit, self:GetOrigin() + normal * kHitEffectOffset, self:GetCoords().zAxis, surface, false, false)
        if targetHit and targetHit:isa("Hive") and targetHit.OnSpitHit then
            targetHit:OnSpitHit()
        end
		GetEffectManager():TriggerEffects("spit_hit", { effecthostcoords = self:GetCoords() })
	end

    if Server then
        DestroyEntity(self) 
    end

end

function Spit:GetDeathIconIndex()
    return kDeathMessageIcon.Spit
end

function Spit:GetAbilityUsesFocus()
    return true
end

Shared.LinkClassToMap("Spit", Spit.kMapName, networkVars)