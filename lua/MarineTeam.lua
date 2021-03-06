// ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
//
// lua\MarineTeam.lua
//
//    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
//                  Max McGuire (max@unknownworlds.com)
//
// This class is used for teams that are actually playing the game, e.g. Marines or Aliens.
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================

//NS2c
//Added dropped weapon tracking, slowed IP message.

Script.Load("lua/Marine.lua")
Script.Load("lua/PlayingTeam.lua")

class 'MarineTeam' (PlayingTeam)

MarineTeam.gSandboxMode = false

// How often to send the "No IPs" message to the Marine team in seconds.
local kSendNoIPsMessageRate = 45

local kCannotSpawnSound = PrecacheAsset("sound/NS2.fev/marine/voiceovers/commander/need_ip")

function MarineTeam:ResetTeam()

    local commandStructure = PlayingTeam.ResetTeam(self)
    
    self.updateMarineArmor = false

    if self.brain ~= nil then
        self.brain:Reset()
    end
    return commandStructure

end

function MarineTeam:GetTeamType()
    return kMarineTeamType
end

function MarineTeam:GetIsMarineTeam()
    return true 
end

function MarineTeam:Initialize(teamName, teamNumber)

    PlayingTeam.Initialize(self, teamName, teamNumber)
    
    self.respawnEntity = Marine.kMapName
    
    self.updateMarineArmor = false
    
    self.lastTimeNoIPsMessageSent = Shared.GetTime()

end

function MarineTeam:OnInitialized()

    PlayingTeam.OnInitialized(self)
    self:AddTeamResources(kMarineTeamIntialRes)
    
end

function MarineTeam:GetHasAbilityToRespawn()

    // Any active IPs on team? There could be a case where everyone has died and no active
    // IPs but builder bots are mid-construction so a marine team could theoretically keep
    // playing but ignoring that case for now
    local spawnclassname = ConditionalValue(CheckNS2GameMode() == kGameMode.Classic, "InfantryPortal", "CommandStation")
    local spawningStructures = GetEntitiesForTeam(spawnclassname, self:GetTeamNumber())
    
    for index, current in ipairs(spawningStructures) do
    
        if current:GetIsBuilt() and current:GetIsAlive() then
            return true
        end
        
    end        
    
    return false
    
end

function MarineTeam:OnRespawnQueueChanged()

    local spawningStructures = GetEntitiesForTeam("InfantryPortal", self:GetTeamNumber())
    
    for index, current in ipairs(spawningStructures) do
    
        if GetIsUnitActive(current) then
            current:FillQueueIfFree()
        end
        
    end        
    
end

// Clear distress flag for all players on team, unless affected by distress beaconing Observatory. 
// This function is here to make sure case with multiple observatories and distress beacons is
// handled properly.
function MarineTeam:UpdateGameMasks(timePassed)

    PROFILE("MarineTeam:UpdateGameMasks")

    local beaconState = false
    
    for obsIndex, obs in ipairs(GetEntitiesForTeam("Observatory", self:GetTeamNumber())) do
    
        if obs:GetIsBeaconing() then
        
            beaconState = true
            break
            
        end
        
    end
    
    for playerIndex, player in ipairs(self:GetPlayers()) do
    
        if player:GetGameEffectMask(kGameEffect.Beacon) ~= beaconState then
            player:SetGameEffectMask(kGameEffect.Beacon, beaconState)
        end
        
    end
    
end

local function CheckForNoIPs(self)

	PROFILE("MarineTeam:CheckForNoIPs")

    if Shared.GetTime() - self.lastTimeNoIPsMessageSent >= kSendNoIPsMessageRate and CheckNS2GameMode() == kGameMode.Classic then
    
        self.lastTimeNoIPsMessageSent = Shared.GetTime()
        if Shared.GetEntitiesWithClassname("InfantryPortal"):GetSize() == 0 then
        
            self:ForEachPlayer(function(player) StartSoundEffectForPlayer(kCannotSpawnSound, player) end)
            SendTeamMessage(self, kTeamMessageTypes.CannotSpawn)
            
        end
        
    end
    
end

local function GetArmorLevel(self)

    local armorLevels = 0
    
    local techTree = self:GetTechTree()
    if techTree then
    
        if techTree:GetHasTech(kTechId.Armor3) then
            armorLevels = 3
        elseif techTree:GetHasTech(kTechId.Armor2) then
            armorLevels = 2
        elseif techTree:GetHasTech(kTechId.Armor1) then
            armorLevels = 1
        end
    
    end
    
    return armorLevels

end

function MarineTeam:Update(timePassed)

    PROFILE("MarineTeam:Update")

    PlayingTeam.Update(self, timePassed)
    
    // Update distress beacon mask
    self:UpdateGameMasks(timePassed)
    self:UpdateDroppedWeapons()
    
    if GetGamerules():GetGameStarted() then
        CheckForNoIPs(self)
    end
    
    local armorLevel = GetArmorLevel(self)
    for index, player in ipairs(GetEntitiesForTeam("Player", self:GetTeamNumber())) do
        player:UpdateArmorAmount(armorLevel)
    end
    
end

function MarineTeam:InitTechTree()
   
   PlayingTeam.InitTechTree(self)
    
 // Misc
    self.techTree:AddUpgradeNode(kTechId.Recycle, kTechId.None, kTechId.None)
    self.techTree:AddOrder(kTechId.Defend)
    self.techTree:AddSpecial(kTechId.TwoCommandStations)
    self.techTree:AddSpecial(kTechId.ThreeCommandStations)

    // Marine builds
    self.techTree:AddBuildNode(kTechId.CommandStation,            kTechId.None,                kTechId.None)
    self.techTree:AddBuildNode(kTechId.Extractor,                 kTechId.None,                kTechId.None)
    self.techTree:AddBuildNode(kTechId.InfantryPortal,            kTechId.None,                kTechId.None)
    self.techTree:AddBuildNode(kTechId.Sentry,                    kTechId.TurretFactory,       kTechId.None)
    self.techTree:AddBuildNode(kTechId.Armory,                    kTechId.None,                kTechId.None)  
    self.techTree:AddBuildNode(kTechId.ArmsLab,                   kTechId.Armory,              kTechId.None)  
    self.techTree:AddUpgradeNode(kTechId.AdvancedArmory,          kTechId.Armory,              kTechId.None)
    self.techTree:AddBuildNode(kTechId.Observatory,               kTechId.InfantryPortal,      kTechId.None)      
    self.techTree:AddBuildNode(kTechId.PhaseGate,                 kTechId.PhaseTech,           kTechId.None)
    self.techTree:AddBuildNode(kTechId.TurretFactory,             kTechId.Armory,              kTechId.None)  
    self.techTree:AddBuildNode(kTechId.AdvancedTurretFactory,     kTechId.Armory,              kTechId.TurretFactory)
    self.techTree:AddTechInheritance(kTechId.TurretFactory,       kTechId.AdvancedTurretFactory)
    self.techTree:AddBuildNode(kTechId.SiegeCannon,               kTechId.AdvancedTurretFactory,  kTechId.None)       
    self.techTree:AddBuildNode(kTechId.PrototypeLab,              kTechId.AdvancedArmory,              kTechId.ArmsLab)        
    self.techTree:AddUpgradeNode(kTechId.Electrify,               kTechId.Extractor,               kTechId.None)
    
    // Marine Upgrades
    self.techTree:AddResearchNode(kTechId.PhaseTech,                    kTechId.Observatory,        kTechId.None)
    self.techTree:AddUpgradeNode(kTechId.AdvancedArmoryUpgrade,     kTechId.Armory,        kTechId.InfantryPortal)
    self.techTree:AddResearchNode(kTechId.HandGrenadesTech,           kTechId.Armory, kTechId.None)
    self.techTree:AddUpgradeNode(kTechId.UpgradeTurretFactory,           kTechId.Armory,              kTechId.TurretFactory) 
    self.techTree:AddResearchNode(kTechId.Armor1,                   kTechId.ArmsLab,              kTechId.None)
    self.techTree:AddResearchNode(kTechId.Weapons1,                 kTechId.ArmsLab,               kTechId.None)
    self.techTree:AddResearchNode(kTechId.Armor2,                   kTechId.Armor1,              kTechId.None)
    self.techTree:AddResearchNode(kTechId.Weapons2,                 kTechId.Weapons1,            kTechId.None)
    self.techTree:AddResearchNode(kTechId.Armor3,                   kTechId.Armor2,              kTechId.None)
    self.techTree:AddResearchNode(kTechId.Weapons3,                 kTechId.Weapons2,            kTechId.None)
    self.techTree:AddResearchNode(kTechId.CatPackTech,              kTechId.None,              kTechId.None)
    self.techTree:AddResearchNode(kTechId.JetpackTech,              kTechId.PrototypeLab, kTechId.AdvancedArmory)
    self.techTree:AddResearchNode(kTechId.HeavyArmorTech,           kTechId.PrototypeLab, kTechId.AdvancedArmory)
    //self.techTree:AddResearchNode(kTechId.ExosuitTech,              kTechId.PrototypeLab, kTechId.AdvancedArmory)
    self.techTree:AddResearchNode(kTechId.MotionTracking,           kTechId.Observatory, kTechId.None)

    // Door actions
    self.techTree:AddBuildNode(kTechId.Door, kTechId.None, kTechId.None)
    self.techTree:AddActivation(kTechId.DoorOpen)
    self.techTree:AddActivation(kTechId.DoorClose)
    self.techTree:AddActivation(kTechId.DoorLock)
    self.techTree:AddActivation(kTechId.DoorUnlock)
    
    // Assists
    self.techTree:AddTargetedActivation(kTechId.MedPack,             kTechId.None,                kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.AmmoPack,            kTechId.None,                kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.CatPack,            kTechId.CatPackTech,                kTechId.None)
    self.techTree:AddActivation(kTechId.DistressBeacon,           kTechId.Observatory)    
    self.techTree:AddTargetedEnergyActivation(kTechId.Scan,             kTechId.Observatory,         kTechId.None)

    // Weapons
    self.techTree:AddTargetedActivation(kTechId.Axe,                         kTechId.None,                kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.Pistol,                      kTechId.None,                kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.Rifle,                       kTechId.None,                kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.Shotgun,                    kTechId.Armory,         kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.GrenadeLauncher,                    kTechId.AdvancedArmory,             kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.HeavyMachineGun,                    kTechId.AdvancedArmory,             kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.Mines,          kTechId.Armory,        kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.Welder,         kTechId.Armory,        kTechId.None)
    self.techTree:AddTargetedActivation(kTechId.Jetpack,        kTechId.JetpackTech, kTechId.PrototypeLab)
    self.techTree:AddTargetedActivation(kTechId.HeavyArmor,     kTechId.HeavyArmorTech, kTechId.PrototypeLab)
    //self.techTree:AddTargetedActivation(kTechId.Exosuit,        kTechId.ExosuitTech, kTechId.PrototypeLab)
    
    self.techTree:AddMenu(kTechId.WeaponsMenu)
    
    self.techTree:SetComplete()

end

function MarineTeam:AwardResources(resAward, pointOwner)
     self:AddTeamResources(resAward)
end

function MarineTeam:SpawnInitialStructures(techPoint)

    local tower, commandStation = PlayingTeam.SpawnInitialStructures(self, techPoint)
    
    if Shared.GetCheatsEnabled() and MarineTeam.gSandboxMode then

        // Pretty dumb way of spawning two things..heh
        local origin = techPoint:GetOrigin()
        local right = techPoint:GetCoords().xAxis
        local forward = techPoint:GetCoords().zAxis
        CreateEntity( AdvancedArmory.kMapName, origin+right*3.5+forward*1.5, kMarineTeamType)
        CreateEntity( PrototypeLab.kMapName, origin+right*3.5-forward*1.5, kMarineTeamType)

    end
    
    return tower, commandStation
    
end

function MarineTeam:GetSpectatorMapName()
    return MarineSpectator.kMapName
end

function MarineTeam:UpdateDroppedWeapons()
     if self.lastdeepweaponscan == nil or self.lastdeepweaponscan + kItemStayTime < Shared.GetTime() then
        for index, weapon in ientitylist(Shared.GetEntitiesWithClassname("Weapon")) do
            if weapon and weapon:GetWeaponWorldState() and weapon.preventExpiration == nil and (Shared.GetTime() - weapon.weaponWorldStateTime) >= kItemStayTime then
                DestroyEntity(weapon)
            end
        end
        self.lastdeepweaponscan = Shared.GetTime()
     end
end

function MarineTeam:OnBought(techId)

    local listeners = self.eventListeners['OnBought']

    if listeners then

        for _, listener in ipairs(listeners) do
            listener(techId)
        end

    end

end
