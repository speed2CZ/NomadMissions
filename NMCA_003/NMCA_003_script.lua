------------------------------
-- Nomads Campaign - Mission 3
--
-- Author: speed2
------------------------------
local Buff = import('/lua/sim/Buff.lua')
local Cinematics = import('/lua/cinematics.lua')
local CustomFunctions = import('/maps/NMCA_003/NMCA_003_CustomFunctions.lua')
local Objectives = import('/lua/SimObjectives.lua')
local M1AeonAI = import('/maps/NMCA_003/NMCA_003_M1AeonAI.lua')
local M2AeonAI = import('/maps/NMCA_003/NMCA_003_M2AeonAI.lua')
local M3AeonAI = import('/maps/NMCA_003/NMCA_003_M3AeonAI.lua')
local M4AeonAI = import('/maps/NMCA_003/NMCA_003_M4AeonAI.lua')
local OpStrings = import('/maps/NMCA_003/NMCA_003_strings.lua')
local PingGroups = import('/lua/ScenarioFramework.lua').PingGroups
local ScenarioFramework = import('/lua/ScenarioFramework.lua')
local ScenarioPlatoonAI = import('/lua/ScenarioPlatoonAI.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')
local TauntManager = import('/lua/TauntManager.lua')
local Weather = import('/lua/weather.lua')
   
----------
-- Globals
----------
ScenarioInfo.Player1 = 1
ScenarioInfo.Aeon = 2
ScenarioInfo.Crashed_Ship = 3
ScenarioInfo.Aeon_Neutral = 4
ScenarioInfo.Crystals = 5
ScenarioInfo.Player2 = 6
ScenarioInfo.Player3 = 7

ScenarioInfo.OperationScenarios = {
    M1 = {
        Events = {
            {
                CallFunction = function() M1AirAttack() end,
            },
            --{
            --    CallFunction = function() M1LandAttack() end,
            --},
            {
                CallFunction = function() M1NavalAttack() end,
            },
        },
    },
    M2 = {
        Bases = {
            {
                CallFunction = function(location)
                    M2AeonAI.AeonM2NorthBaseAI(location)
                end,
                Types = {'WestNaval', 'SouthNaval'},
            },
            {
                CallFunction = function(location)
                    M2AeonAI.AeonM2SouthBaseAI(location)
                end,
                Types = {'NorthNaval', 'SouthNaval'},
            },
        },
    },
    M3 = {
        Events = {
            {
                CallFunction = function() M3AeonAI.M3sACUMainBase() end,
                Delay = 180,
            },
            {
                CallFunction = function() M3sACUM2Northbase() end,
                Delay = 180,
            },
        },
    },
    M4 = {
        Bases = {
            {
                CallFunction = function(location)
                    ForkThread(M4TMLOutpost, location)
                end,
                Types = {'North', 'Centre', 'South', 'None'}
            },
        },
    },
}

---------
-- Locals
---------
local Crystals = ScenarioInfo.Crystals
local Aeon = ScenarioInfo.Aeon
local Aeon_Neutral = ScenarioInfo.Aeon_Neutral
local Crashed_Ship = ScenarioInfo.Crashed_Ship
local Player1 = ScenarioInfo.Player1
local Player2 = ScenarioInfo.Player2
local Player3 = ScenarioInfo.Player3

local Difficulty = ScenarioInfo.Options.Difficulty

local LeaderFaction
local LocalFaction

-- Max HP the ship can be regenerated to, increased by reclaiming the crystals
local ShipMaxHP = 3000
local CrystalBonuses = {
    { -- Crystal 1
        maxHP = 6480,
        addHP = 2500,
    },
    { -- Crystal 2
        maxHP = 9220,
        addHP = 2200,
        addProduction = {
            energy = 300,
            mass = 15,
        },
    },
    { -- Crystal 3
        maxHP = 13100,
        addHP = 3000,
    },
    { -- Crystal 4
        maxHP = 16560,
        addHP = 2400,
    },
    { -- Crystal 5
        maxHP = 20000,
        addHP = 2500,
    },
}

-- Mass that has to be send to the destroyer fleet to launch the nukes in the last part of the mission
local MassRequiredForNukes = 80000

-- How long should we wait at the beginning of the NIS to allow slower machines to catch up?
local NIS1InitialDelay = 2

-----------------
-- Taunt Managers
-----------------
local AeonM1TM = TauntManager.CreateTauntManager('AeonTM', '/maps/NMCA_003/NMCA_003_strings.lua')
local NicholsTM = TauntManager.CreateTauntManager('NicholsTM', '/maps/NMCA_003/NMCA_003_strings.lua')

--------
-- Debug
--------
local Debug = false
local SkipNIS1 = false
local SkipNIS2 = false
local SkipNIS3 = false

-----------
-- Start up
-----------
function OnPopulate(self)
    ScenarioUtils.InitializeScenarioArmies()
    LeaderFaction, LocalFaction = ScenarioFramework.GetLeaderAndLocalFactions()

    Weather.CreateWeather()
    
    ----------
    -- Aeon AI
    ----------
    M1AeonAI.AeonM1BaseAI()

    -- Extra resources outside of the base
    ScenarioUtils.CreateArmyGroup('Aeon', 'M1_Aeon_Extra_Resources_D' .. Difficulty)

    -- Walls
    ScenarioUtils.CreateArmyGroup('Aeon', 'M1_Walls')

    -- Refresh build restriction in support factories and engineers
    ScenarioFramework.RefreshRestrictions('Aeon')

    -- Initial Patrols
    -- Air Patrol
    local platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M1_Initial_Air_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolRoute({v}, ScenarioPlatoonAI.GetRandomPatrolRoute(ScenarioUtils.ChainToPositions('M1_Aeon_Base_Air_Patrol_Chain')))
    end

    -- Land patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M1_Initial_Land_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolRoute({v}, ScenarioUtils.ChainToPositions('M1_Aeon_Base_Land_Patrol_Chain'))
    end
    
    -------------
    -- Objectives
    -------------
    -- Civilian town, Damage the UEF buildings a bit
    local units = ScenarioUtils.CreateArmyGroup('Aeon_Neutral', 'M1_Civilian_Town')
    for _, v in units do
        if EntityCategoryContains(categories.UEF, v) then
            v:AdjustHealth(v, Random(300, 700) * -1)
        end
    end

    -- Admin Center
    ScenarioInfo.M1_Admin_Centre = ScenarioInfo.UnitNames[Aeon_Neutral]['M1_Admin_Centre']
    ScenarioInfo.M1_Admin_Centre:SetCustomName('Administrative Centre')

    -- Crystals, spawn then and make sure they'll survive until the objective
    ScenarioInfo.M1ShipParts = ScenarioUtils.CreateArmyGroup('Crystals', 'M1_Crystals')
    for _, v in ScenarioInfo.M1ShipParts do
        v:SetReclaimable(false)
        v:SetCanTakeDamage(false)
        v:SetCapturable(false)
    end

    -- Crashed Ship
    --ScenarioInfo.CrashedShip = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Crashed_Ship')
    ScenarioInfo.CrashedShip = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Crashed_Cruiser')
    ScenarioInfo.CrashedShip:SetCustomName('Crashed Ship')
    ScenarioInfo.CrashedShip:SetReclaimable(false)
    ScenarioInfo.CrashedShip:SetCapturable(false) 
    ScenarioInfo.CrashedShip:SetHealth(ScenarioInfo.CrashedShip, 2250)
    -- Adjust the position
    local pos = ScenarioInfo.CrashedShip:GetPosition()
    --ScenarioInfo.CrashedShip:SetPosition({pos[1], pos[2] - 4.5, pos[3]}, true)
    ScenarioInfo.CrashedShip:StopRotators()
    local thread = ForkThread(ShipHPThread)
    ScenarioInfo.CrashedShip.Trash:Add(thread)

    if Debug then
        ScenarioInfo.CrashedShip:SetCanBeKilled(false)
    end

    -- Wreckages
    ScenarioUtils.CreateArmyGroup('Crystals', 'M1_Wrecks', true)
end

function OnStart(self)
    -- Set Unit Restrictions
    ScenarioFramework.AddRestrictionForAllHumans(
        categories.TECH3 +
        categories.EXPERIMENTAL +
        categories.xnl0209 + -- Nomads Field Engineer
        categories.xnb2208 + -- Nomads TML
        categories.xnb2303 + -- Nomads T2 Arty
        categories.xnb4204 + -- Nomads TMD
        categories.xnb4202 + -- Nomads T2 Shield
        categories.xns0202 + -- Nomads Cruiser
        categories.xns0102 + -- Nomads Railgun boat

        categories.uab2108 + -- Aeon TML
        categories.uab2303 + -- Aeon T2 Arty
        categories.uab4201 + -- Aeon TMD
        categories.uab4202 + -- Aeon T2 Shield
        categories.uas0202 + -- Aeon Cruiser
        categories.xas0204   -- Aeon Sub Hunter
    )

    ScenarioFramework.RestrictEnhancements({
        -- Allowed: AdvancedEngineering, Capacitator, GunUpgrade, RapidRepair, MovementSpeedIncrease
        'IntelProbe',
        'IntelProbeAdv',
        'DoubleGuns',
        'RapidRepair',
        'ResourceAllocation',
        'PowerArmor',
        'T3Engineering',
        'OrbitalBombardment',
        'OrbitalBombardmentHeavy'
    })

    -- Set Unit Cap
    ScenarioFramework.SetSharedUnitCap(1000)

    -- Set Army Colours, 4th number for hover effect
    local colors = {
        ['Player1'] = {{225, 135, 62}, 5},
        ['Player2'] = {{189, 183, 107}, 4},
        ['Player3'] = {{255, 255, 165}, 13},
    }
    local tblArmy = ListArmies()
    for army, color in colors do
        if tblArmy[ScenarioInfo[army]] then
            ScenarioFramework.SetArmyColor(ScenarioInfo[army], unpack(color[1]))
            ScenarioInfo.ArmySetup[army].ArmyColor = color[2]
        end
    end
    ScenarioFramework.SetAeonColor(Aeon)
    SetArmyColor('Crashed_Ship', 255, 191, 128)
    SetArmyColor('Aeon_Neutral', 16, 86, 16)

    -- Bigger unit cap for Aeon if players decide to turtle too much
    SetArmyUnitCap(Aeon, 1500)

    -- Set playable area
    ScenarioFramework.SetPlayableArea('M1_Area', false)

    -- Initialize camera
    if not SkipNIS1 then
        Cinematics.CameraMoveToMarker('Cam_M1_Intro_1')
    end

    ForkThread(IntroMission1NIS)
end

-----------
-- End Game
-----------
function PlayerDeath(commander)
    ScenarioFramework.PlayerDeath(commander, OpStrings.PlayerDies1)
end

function ShipDeath()
    ScenarioFramework.PlayerDeath(ScenarioInfo.CrashedShip, OpStrings.ShipDestroyed)
end

function PlayerWin()
    ForkThread(
        function()
            ScenarioFramework.FlushDialogueQueue()
            while ScenarioInfo.DialogueLock do
                WaitSeconds(0.2)
            end

            ScenarioInfo.M1P1:ManualResult(true) -- Complete protect ship objective

            WaitSeconds(2)

            if not ScenarioInfo.OpEnded then
                ScenarioFramework.EndOperationSafety({ScenarioInfo.CrashedShip})
                ScenarioInfo.OpComplete = true

                Cinematics.EnterNISMode()
                WaitSeconds(2)

                -- TODO PlayerWin2 when Aeon ACU is left alive
                ScenarioFramework.Dialogue(OpStrings.PlayerWin1, nil, true)
                Cinematics.CameraMoveToMarker('Cam_Final_1', 3)


                ForkThread(
                    function()
                        WaitSeconds(1)
                        ScenarioInfo.CrashedShip:TakeOff()
                        WaitSeconds(3)
                        ScenarioInfo.CrashedShip:StartRotators()
                    end
                )

                WaitSeconds(3)

                Cinematics.CameraMoveToMarker('Cam_Final_2', 5)

                WaitSeconds(1)

                Cinematics.CameraMoveToMarker('Cam_Final_3', 4)

                KillGame()
            end
        end
    )
end

function KillGame()
    UnlockInput()
    local secondary = Objectives.IsComplete(ScenarioInfo.M1S1) and
                      Objectives.IsComplete(ScenarioInfo.M2S1) and
                      Objectives.IsComplete(ScenarioInfo.M3S1) and
                      Objectives.IsComplete(ScenarioInfo.M4S1)
    local bonus = Objectives.IsComplete(ScenarioInfo.M1B1) and
                  Objectives.IsComplete(ScenarioInfo.M1B2) and
                  Objectives.IsComplete(ScenarioInfo.M1B3) and
                  Objectives.IsComplete(ScenarioInfo.M2B1) and
                  Objectives.IsComplete(ScenarioInfo.M2B2) and
                  Objectives.IsComplete(ScenarioInfo.M4B1)
    ScenarioFramework.EndOperation(ScenarioInfo.OpComplete, ScenarioInfo.OpComplete, secondary, bonus)
end

------------
-- Mission 1
------------
function IntroMission1NIS()
    local function SpawnPlayers(armyList)
        ScenarioInfo.PlayersACUs = {}
        local i = 1

        while armyList[ScenarioInfo['Player' .. i]] do
            ScenarioInfo['Player' .. i .. 'CDR'] = ScenarioFramework.SpawnCommander('Player' .. i, 'ACU', 'Warp', true, true, PlayerDeath)
            table.insert(ScenarioInfo.PlayersACUs, ScenarioInfo['Player' .. i .. 'CDR'])
            WaitSeconds(1)

            -- Move the orbital frigate over the water
            local ship = ScenarioInfo['Player' .. i .. 'CDR'].OrbitalUnit
            if ship then
                IssueClearCommands({ship})
                IssueMove({ship}, ScenarioUtils.MarkerToPosition('Player' .. i .. '_Frigate_Destination'))
            end
            i = i + 1
        end
    end

    local tblArmy = ListArmies()

    if not SkipNIS1 then
        -- Gets player number and joins it to a string to make it refrence a camera marker e.g Player1_Cam N.B. Observers are called nilCam
        local strCameraPlayer = tostring(tblArmy[GetFocusArmy()])
        local CameraMarker = strCameraPlayer .. '_Cam'

        -- Vision over the crashed ship
        local VisMarker2 = ScenarioFramework.CreateVisibleAreaLocation(36, 'VizMarker_2', 0, ArmyBrains[Player1])
        
        -- Intro Cinematic
        Cinematics.EnterNISMode()

        WaitSeconds(NIS1InitialDelay)

        local Scouts = ScenarioUtils.CreateArmyGroup('Player1', 'Scouts_1')
        -- The scout we're gonna follow with the cam, it will die when WE want it to die! ... so making it invincible for now
        -- It can take damage and all the pain, but can't die just yet. Cruel world full of suffering ("maniacal laugh")
        ScenarioInfo.Scout1 = Scouts[1]
        ScenarioInfo.Scout1:SetCanBeKilled(false)
        IssueMove(Scouts, ScenarioUtils.MarkerToPosition('M1_Aeon_Base_Marker'))

        -- "We're under fire" dialogue, trigger by one scout dying
        ScenarioFramework.CreateUnitDestroyedTrigger(
            function()
                ScenarioFramework.Dialogue(OpStrings.M1Intro2, nil, true)
            end,
            Scouts[2]
        )

        -- "Beginning the search for the ship"
        ScenarioFramework.Dialogue(OpStrings.M1Intro1, nil, true)
        WaitSeconds(0.5)

        Cinematics.CameraThirdPerson(ScenarioInfo.Scout1, 0.5, 60, 5, 2)

        -- Aproaching this marker of doom will murder the scout, creating new vision radius before the scout dies to see what's going on as it crashes down
        ScenarioFramework.CreateUnitToMarkerDistanceTrigger(
            function()
                ScenarioInfo.VizMarker1 = ScenarioFramework.CreateVisibleAreaLocation(42, ScenarioInfo.Scout1:GetPosition(), 0, ArmyBrains[Player1])
                ScenarioInfo.Scout1:SetCanBeKilled(true)
                ScenarioInfo.Scout1:Kill() 
            end,
            ScenarioInfo.Scout1,
            'M1_Aeon_Base_Marker',
            20
        )

        while not ScenarioInfo.Scout1.Dead do
            WaitSeconds(0.1)
        end
        
        Cinematics.CameraMoveToMarker('Cam_M1_Intro_2', 5)

        -- Other two scouts that will find the crashed ship, then patrol aroud it
        local Scouts2 = ScenarioUtils.CreateArmyGroup('Player1', 'Scouts_2')
        IssueMove(Scouts2, ScenarioUtils.MarkerToPosition('Scout_Move_1'))
        IssueMove(Scouts2, ScenarioUtils.MarkerToPosition('Scout_Move_2'))
        ScenarioFramework.GroupPatrolChain(Scouts2, 'M1_Player1_Scout_Patrol_Chain')

        WaitSeconds(3)

        -- "Shit has to be somewhere around here"
        ScenarioFramework.Dialogue(OpStrings.M1Intro3, nil, true)

        Cinematics.CameraTrackEntities(Scouts2, 60, 1)
        WaitSeconds(8)

        -- "Found the ship"
        ScenarioFramework.Dialogue(OpStrings.M1Intro4, nil, true)

        -- Cam on the crashed ship
        Cinematics.CameraMoveToMarker('Cam_M1_Intro_3', 2)
        WaitSeconds(2)

        -- Spawn Players
        ForkThread(SpawnPlayers, tblArmy)

        Cinematics.CameraMoveToMarker(CameraMarker, 2)
        WaitSeconds(3)

        -- No more vision over the enemy base
        ScenarioInfo.VizMarker1:Destroy()

        Cinematics.ExitNISMode()
    else
        -- Spawn Players
        ForkThread(SpawnPlayers, tblArmy)
    end

    IntroMission1()
end

function IntroMission1()
    ScenarioInfo.MissionNumber = 1

    -- Give initial resources to the AI
    local num = {2000, 3500, 5000}
    ArmyBrains[Aeon]:GiveResource('MASS', num[Difficulty])
    ArmyBrains[Aeon]:GiveResource('ENERGY', 8000)

    -- Rainbow effect for crystals
    ForkThread(RainbowEffect)

    -- "Aeons are attacking, defend the ship", assign objectives
    ScenarioFramework.Dialogue(OpStrings.M1PostIntro, StartMission1, true)
end

function StartMission1()
    -----------------------------------------------
    -- Primary Objective - Protect the crashed ship
    -----------------------------------------------
    ScenarioInfo.M1P1 = Objectives.Protect(
        'primary',
        'incomplete',
        OpStrings.M1P1Title,
        OpStrings.M1P1Description,
        {
            Units = {ScenarioInfo.CrashedShip},
        }
    )
    ScenarioInfo.M1P1:AddResultCallback(
        function(result)
            if not result then
                ShipDeath()
            end
        end
    )

    ----------------------------------------
    -- Primary Objective - Destroy Aeon Base
    ----------------------------------------
    ScenarioInfo.M1P2 = Objectives.CategoriesInArea(
        'primary',
        'incomplete',
        OpStrings.M1P2Title,
        OpStrings.M1P2Description,
        'killorcapture',
        {
            --MarkArea = true,
            Requirements = {
                {
                    Area = 'M1_Aeon_South_Base',
                    Category = categories.FACTORY + categories.ENGINEER,
                    CompareOp = '<=',
                    Value = 0,
                    ArmyIndex = Aeon,
                },
            },
        }
    )
    ScenarioInfo.M1P2:AddResultCallback(
        function(result)
            if result then
                ScenarioFramework.Dialogue(OpStrings.M1AeonBaseDestroyed, nil, true)
            end
        end
    )

    -- Reminder
    ScenarioFramework.CreateTimerTrigger(M1P2Reminder1, 600)

    ---------------------------------------------------
    -- Bonus Objective - Capture Aeon Construction Unit
    ---------------------------------------------------
    ScenarioInfo.M1B1 = Objectives.ArmyStatCompare(
        'bonus',
        'incomplete',
        OpStrings.M1B1Title,
        OpStrings.M1B1Description,
        'capture',
        {
            Armies = {'HumanPlayers'},
            StatName = 'Units_Active',
            CompareOp = '>=',
            Value = 1,
            Category = categories.AEON * categories.CONSTRUCTION,
            Hidden = true,
        }
    )
    ScenarioInfo.M1B1:AddResultCallback(
        function(result)
            if result then
                ScenarioFramework.Dialogue(OpStrings.M1AeonUnitCaptured)
            end
        end
    )

    -- Setup taunts and dialogues
    SetupNicholsM1Warnings()
    SetupAeonM1Taunts()

    -----------
    -- Triggers
    -----------
    -- Capture Admin Building Objective once seen
    ScenarioFramework.CreateArmyIntelTrigger(M1SecondaryObjective, ArmyBrains[Player1], 'LOSNow', false, true, categories.CIVILIAN, true, ArmyBrains[Aeon_Neutral])

    for _, player in ScenarioInfo.HumanPlayers do
        -- Players see the dead UEF Base (make sure the orbital frigate wont trigger it)
        ScenarioFramework.CreateAreaTrigger(M1UEFBaseDialogue, 'M1_UEF_Base_Area', categories.ALLUNITS - categories.xno0001, true, false, ArmyBrains[player])
    end

    -- Unlock T2 shield
    ScenarioFramework.CreateTimerTrigger(M1ShieldUnlock, 180)

    -- Sending engineers to player's position
    ScenarioFramework.CreateTimerTrigger(M1EnginnersDrop, 250)

    -- Attack from the west
    local delay = {23, 20, 17}
    ScenarioFramework.CreateTimerTrigger(M1AttackFromWest, delay[Difficulty] * 60)

    -- Annnounce the mission name after few seconds
    WaitSeconds(8)
    ScenarioFramework.SimAnnouncement(OpStrings.OPERATION_NAME, 'mission by The \'Mad Men')
end

function M1SecondaryObjective()
    ScenarioFramework.Dialogue(OpStrings.M1SecondaryObjective)

    ---------------------------------------------------------------
    -- Secondary Objective - Capture the Aeon administrative centre
    ---------------------------------------------------------------
    ScenarioInfo.M1S1 = Objectives.Capture(
        'secondary',
        'incomplete',
        OpStrings.M1S1Title,
        OpStrings.M1S1Description,
        {
            Units = {ScenarioInfo.M1_Admin_Centre},
            FlashVisible = true,
        }
    )
    ScenarioInfo.M1S1:AddResultCallback(
        function(result)
            if result then
                -- TODO: Decide what bonus to give player for this.
                ScenarioFramework.Dialogue(OpStrings.M1SecondaryDone)
            else
                ScenarioFramework.Dialogue(OpStrings.M1SecondaryFailed)
            end
        end
   )

   -- Reminder
    ScenarioFramework.CreateTimerTrigger(M1S1Reminder, 600)
end

function M1UEFBaseDialogue()
    if not ScenarioInfo.M1UEFDialoguePlayed then
        ScenarioInfo.M1UEFDialoguePlayed = true
        ScenarioFramework.Dialogue(OpStrings.M1UEFBaseDialogue)
    end
end

function M1ShieldUnlock()
    local function Unlock()
        ScenarioFramework.RemoveRestrictionForAllHumans(categories.xnb4202 + categories.uab4202, true)

        -------------------------------------------------
        -- Bonus Objective - Build a shield over the ship
        -------------------------------------------------
        ScenarioInfo.M1B2 = Objectives.CategoriesInArea(
            'bonus',
            'incomplete',
            OpStrings.M1B2Title,
            OpStrings.M1B2Description,
            'build',
            {
                Hidden = true,
                Requirements = {
                    {
                        Area = 'M1_Shield_Area',
                        Category = categories.SHIELD * categories.TECH2 * categories.STRUCTURE,
                        CompareOp = '>=',
                        Value = 1,
                        Armies = {'HumanPlayers'},
                    },
                },
            }
        )
        ScenarioInfo.M1B2:AddResultCallback(
            function(result)
                if result then
                    ScenarioFramework.Dialogue(OpStrings.M1ShieldConstructed)
                end
            end
        )
    end

    -- First play the dialogue, then unlock
    ScenarioFramework.Dialogue(OpStrings.M1ShieldUnlock, Unlock, true)
end

function M1EnginnersDrop()
    ScenarioFramework.Dialogue(OpStrings.M1Enginners1, nil, true)

    WaitSeconds(45)

    ScenarioFramework.Dialogue(OpStrings.M1Enginners2, nil, true)

    ScenarioInfo.M1Engineers = {}

    -- Drop the engineers, start repairing the ship
    for i = 1, 4 do
        ForkThread(function(i)
            local transport = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Transport' .. i)
            local engineer = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Engineer' .. i)
            table.insert(ScenarioInfo.M1Engineers, engineer)

            ScenarioFramework.AttachUnitsToTransports({engineer}, {transport})
            IssueTransportUnload({transport}, ScenarioUtils.MarkerToPosition('Drop_Marker_'.. i))

            while engineer and not engineer:IsDead() and engineer:IsUnitState('Attached') do
                WaitSeconds(3)
            end

            IssueMove({engineer}, ScenarioUtils.MarkerToPosition('Move_Marker_'.. i))
            IssueRepair({engineer}, ScenarioInfo.CrashedShip)

            WaitSeconds(3)
            ScenarioFramework.GiveUnitToArmy(transport, 'Player1')
            WaitSeconds(3)

            M1RepairingShip()
        end, i)
    end

    -- Wait one seconds for the engineers to spawn and assign a bonus objective to protect them
    WaitSeconds(1)

    --------------------------------------
    -- Bonus Objective - Protect engineers
    --------------------------------------
    ScenarioInfo.M1B3 = Objectives.Protect(
        'bonus',
        'incomplete',
        OpStrings.M1B3Title,
        OpStrings.M1B3Description,
        {
            Units = ScenarioInfo.M1Engineers,
            MarkUnits = false,
            Hidden = true,
        }
    )
end

function M1RepairingShip()
    if not ScenarioInfo.ShipBeingRepaired then
        ScenarioInfo.ShipBeingRepaired = true
        ScenarioFramework.Dialogue(OpStrings.M1Enginners3, nil, true)

        WaitSeconds(10)
        ScenarioFramework.Dialogue(OpStrings.M1ShipPartsObjective, M1ShipPartsObjective, true)
    end
end

function M1ShipPartsObjective()
    -- Debug check to prevent running the same code twice when skipping through the mission
    if ScenarioInfo.MissionNumber ~= 1 then
        return
    end

    -- Allow reclaiming of the crystals
    for _, v in ScenarioInfo.M1ShipParts do
        v:SetReclaimable(true)
    end

    ---------------------------------------------
    -- Primary Objective - Reclaim the ship parts
    ---------------------------------------------
    ScenarioInfo.M1P3 = CustomFunctions.Reclaim(
        'primary',
        'incomplete',
        OpStrings.M1P3Title,
        OpStrings.M1P3Description,
        {
            Units = ScenarioInfo.M1ShipParts,
            NumRequired = 5,
        }
    )
    ScenarioInfo.M1P3:AddProgressCallback(
        function(current, total)
            ShipPartReclaimed(current)

            if current == 1 then
                ScenarioFramework.Dialogue(OpStrings.FirstShipPartReclaimed, nil, true)
            elseif current == 2 then
                -- Resource bonus
                if ScenarioInfo.MissionNumber == 1 then
                    -- Expand the map
                    ScenarioFramework.Dialogue(OpStrings.SecondShipPartReclaimed1, IntroMission2, true)
                else
                    ScenarioFramework.Dialogue(OpStrings.SecondShipPartReclaimed2, nil, true)
                end
            elseif current == 3 then
                ScenarioFramework.Dialogue(OpStrings.ThirdShipPartReclaimed, nil, true)
            elseif current == 4 then
                -- Orbital Frigate Bombardment
                ForkThread(SetUpBombardmentPing, true)

                ScenarioFramework.Dialogue(OpStrings.FourthShipPartReclaimed, nil, true)
            end
        end
    )
    ScenarioInfo.M1P3:AddResultCallback(
        function(result)
            if result then
                -- Finish objective to protect the engineers repairing the ship
                if ScenarioInfo.M1B3.Active then
                    ScenarioInfo.M1B3:ManualResult(true)
                end

                if ScenarioInfo.MissionNumber == 2 then
                    -- Warn about attack and expand the map
                    ScenarioFramework.Dialogue(OpStrings.AllShipPartReclaimed1, M2AttackWarning, true)
                else
                    ScenarioFramework.Dialogue(OpStrings.AllShipPartReclaimed2, nil, true)
                end
            end
        end
    )

    -- Reminder
    ScenarioFramework.CreateTimerTrigger(M1P3Reminder1, 20*60)
end

function M1AttackFromWest()
    -- Debug check to prevent running the same code twice when skipping through the mission
    if ScenarioInfo.MissionNumber ~= 1 then
        return
    end
    -- Randomly pick the attack, "false" will start it right away
    ChooseRandomEvent(false)

    -- Wait few minutes and expand the map if it hasn't yet
    WaitSeconds(7*60)

    if ScenarioInfo.MissionNumber == 1 then
        -- When the timer runs out, expand the map even
        ScenarioFramework.Dialogue(OpStrings.M1MapExpansion, IntroMission2, true)
    end
end

function M1AirAttack()
    local platoon = nil
    local num = 0
    local quantity = {}

    -- Air attack
    -- Warn player the attack is coming
    ScenarioFramework.Dialogue(OpStrings.M1AirAttack)

    -- Basic air attack
    for i = 1, 3 do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Air_Attack_' .. i .. '_D' .. Difficulty, 'AttackFormation', 2 + Difficulty)
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M1_Aeon_Air_Attack_West_Chain_' .. i)
    end

    -- Sends combat fighters if players has more than [20, 25, 30] air fighters
    num = ScenarioFramework.GetNumOfHumanUnits(categories.AIR * categories.MOBILE - categories.SCOUT)
    quantity = {20, 25, 30}
    if num > quantity[Difficulty] then
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Air_SwiftWinds_D' .. Difficulty, 'AttackFormation', 2 + Difficulty)
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M1_Aeon_Air_Attack_West_Chain_2')
    end

    -- Sends air attack on destroyers if player has more than [2, 3, 4]
    local destroyers = ScenarioFramework.GetListOfHumanUnits(categories.DESTROYER)
    num = table.getn(destroyers)
    quantity = {2, 3, 4}
    if num > 0 then
        if num > quantity[Difficulty] then
            num = quantity[Difficulty]
        end
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Air_Destroyer_Counter_D' .. Difficulty, 'GrowthFormation', 1 + Difficulty)
            IssueAttack(platoon:GetPlatoonUnits(), destroyers[i])
            ScenarioFramework.PlatoonPatrolChain(platoon, 'M1_Aeon_Naval_Atttack_Chain')
        end
    end

    -- Sends [1, 2, 3] Mercies at players' ACUs
    for _, v in ScenarioInfo.PlayersACUs do
        if not v:IsDead() then
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Air_ACU_Counter_D' .. Difficulty, 'NoFormation', 5)
            IssueAttack(platoon:GetPlatoonUnits(), v)
            IssueAggressiveMove(platoon:GetPlatoonUnits(), ScenarioUtils.MarkerToPosition('Player1'))
        end
    end
end

function M1LandAttack()
    -- TODO: Decide if we want a land/hover/drops attack type as well
    local platoon = nil

    -- Land attack
    -- Warn player the attack is coming
    ScenarioFramework.Dialogue(OpStrings.M1LandAttack)
end

function M1NavalAttack()
    -- Naval attack
    -- Warn player the attack is coming
    ScenarioFramework.Dialogue(OpStrings.M1NavalAttack)

    -- First move ships to the map, then patrol, to make sure they won't shoot from off-map

    -- Destroyers
    local platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Destroyers_D' .. Difficulty, 'AttackFormation', 2 + Difficulty)
    platoon:MoveToLocation(ScenarioUtils.MarkerToPosition('M1_Destroyer_Entry'), false)
    ScenarioFramework.PlatoonPatrolChain(platoon, 'M1_Aeon_Destroyer_Chain')

    -- Cruiser, only on medium and high difficulty
    if Difficulty >= 2 then
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Cruiser_D' .. Difficulty, 'AttackFormation', 1 + Difficulty)
        platoon:MoveToLocation(ScenarioUtils.MarkerToPosition('M1_Frigate_Entry_2'), false)
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M1_Aeon_Frigate_Chain_2')
    end

    -- Frigates
    for i = 1, Difficulty do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M1_Frigates_' .. i, 'AttackFormation', Difficulty)
        platoon:MoveToLocation(ScenarioUtils.MarkerToPosition('M1_Frigate_Entry_' .. i), false)
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M1_Aeon_Frigate_Chain_' .. i)
    end
end

------------
-- Mission 2
------------
function IntroMission2()
    ScenarioFramework.FlushDialogueQueue()
    while ScenarioInfo.DialogueLock do
        WaitSeconds(0.2)
    end

    -- Debug check to prevent running the same code twice when skipping through the mission
    if ScenarioInfo.MissionNumber ~= 1 then
        return
    end
    ScenarioInfo.MissionNumber = 2

    ----------
    -- Aeon AI
    ----------
    -- North and South base, using random pick for choosing naval factory location
    ChooseRandomBases()

    -- Extra resources outside of the bases
    ScenarioUtils.CreateArmyGroup('Aeon', 'M2_Aeon_Extra_Resources_D' .. Difficulty)

    -- Walls
    ScenarioUtils.CreateArmyGroup('Aeon', 'M2_Walls')

    -- Refresh build restriction in support factories and engineers
    ScenarioFramework.RefreshRestrictions('Aeon')

    -- Patrols
    -- North
    -- Air base patrol
    local platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Aeon_North_Base_Air_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolRoute({v}, ScenarioPlatoonAI.GetRandomPatrolRoute(ScenarioUtils.ChainToPositions('M2_Aeon_North_Base_Air_Patrol_Chain')))
    end

    -- Naval base patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_North_Naval_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M2_Aeon_North_Base_Naval_Defense_Chain')
    end

    -- Sub Hunters around the island
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_SubmarineHunters_4_D' .. Difficulty, 'AttackFormation')
    ScenarioFramework.PlatoonPatrolChain(platoon, 'M2_Aeon_SubHunter_Full_Chain')


    -- South
    -- Air base patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Aeon_South_Base_Air_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolRoute({v}, ScenarioPlatoonAI.GetRandomPatrolRoute(ScenarioUtils.ChainToPositions('M2_Aeon_South_Base_Air_Patrol_Chain')))
    end

    -- Land base patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_South_Land_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M2_Aeon_South_Base_Land_Patrol_Chain')
    end

    -- Naval base patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_South_Naval_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M2_Aeon_South_Base_Naval_Defense_Chain')
    end


    -- Middle
    -- Submarine hunters, 3 groups of {2, 3, 4}
    for i = 1, 3 do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_SubmarineHunters_' .. i .. '_D' .. Difficulty, 'AttackFormation')
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M2_Aeon_SubHunter_Mid_Chain')
    end

    -- Torpedo bombers
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_Torpedo_Bombers_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M2_Aeon_SubHunter_Mid_Chain')
    end

    -- South
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M2_Init_SubmarineHunters_5_D' .. Difficulty, 'AttackFormation')
    ScenarioFramework.PlatoonPatrolChain(platoon, 'M2_Aeon_SubHunter_South_Chain')

    -------------
    -- Objectives
    -------------
    -- Crystals, spawn then and make sure they'll survive until the objective
    ScenarioInfo.M2Crystals = ScenarioUtils.CreateArmyGroup('Crystals', 'M2_Crystals')
    for _, v in ScenarioInfo.M2Crystals do
        v:SetCanTakeDamage(false)
        v:SetCapturable(false)
    end

    -- Wreckages
    ScenarioUtils.CreateArmyGroup('Crystals', 'M2_Wrecks', true)

    -- Give initial resources to the AI
    local num = {10000, 14000, 18000}
    ArmyBrains[Aeon]:GiveResource('MASS', num[Difficulty])
    ArmyBrains[Aeon]:GiveResource('ENERGY', 30000)

    IntroMission2NIS()
end

function IntroMission2NIS()
    -- Playable area
    ScenarioFramework.SetPlayableArea('M2_Area', true)

    if not SkipNIS2 then
        Cinematics.EnterNISMode()
        Cinematics.SetInvincible('M1_Area')

        -- Visible locations
        -- Show crystal positons
        ScenarioFramework.CreateVisibleAreaLocation(5, ScenarioInfo.M2Crystals[1]:GetPosition(), 1, ArmyBrains[Player1])
        ScenarioFramework.CreateVisibleAreaLocation(20, ScenarioInfo.M2Crystals[2]:GetPosition(), 1, ArmyBrains[Player1])
        ScenarioFramework.CreateVisibleAreaLocation(5, ScenarioInfo.M2Crystals[3]:GetPosition(), 1, ArmyBrains[Player1])
        -- Aeon base
        local VizMarker1 = ScenarioFramework.CreateVisibleAreaLocation(50, 'M2_Viz_Marker_1', 0, ArmyBrains[Player1])

        local fakeMarker1 = {
            ['zoom'] = FLOAT(35),
            ['canSetCamera'] = BOOLEAN(true),
            ['canSyncCamera'] = BOOLEAN(true),
            ['color'] = STRING('ff808000'),
            ['editorIcon'] = STRING('/textures/editor/marker_mass.bmp'),
            ['type'] = STRING('Camera Info'),
            ['prop'] = STRING('/env/common/props/markers/M_Camera_prop.bp'),
            ['orientation'] = VECTOR3(-3.14159, 1.19772, 0),
            ['position'] = ScenarioInfo.Player1CDR:GetPosition(),
        }
        Cinematics.CameraMoveToMarker(fakeMarker1, 0)

        ScenarioFramework.Dialogue(OpStrings.M2Intro1, nil, true)
        WaitSeconds(5)

        ScenarioFramework.Dialogue(OpStrings.M2Intro2, nil, true)
        Cinematics.CameraMoveToMarker('Cam_M2_Intrro_1', 4)
        WaitSeconds(1)

        ScenarioFramework.Dialogue(OpStrings.M2Intro3, nil, true)
        Cinematics.CameraMoveToMarker('Cam_M2_Intrro_2', 3)
        WaitSeconds(2)

        Cinematics.CameraMoveToMarker('Cam_M2_Intrro_3', 3)
        WaitSeconds(1)

        VizMarker1:Destroy()

        -- Remove intel on the Aeon base on high difficulty
        if Difficulty >= 3 then
            ScenarioFramework.ClearIntel(ScenarioUtils.MarkerToPosition('M2_Viz_Marker_1'), 60)
        end

        Cinematics.SetInvincible('M1_Area', true)
        Cinematics.ExitNISMode()
    end

    ScenarioFramework.Dialogue(OpStrings.M2PostIntro, StartMission2, true)
end

function StartMission2()
    -- Add ship parts to the objective
    ScenarioInfo.M1P3:AddTargetUnits(ScenarioInfo.M2Crystals)

    ---------------------------------------------
    -- Secondary Objective - Destroy 2 Aeon bases
    ---------------------------------------------
    ScenarioInfo.M1S1 = Objectives.CategoriesInArea(
        'secondary',
        'incomplete',
        OpStrings.M2S1Title,
        OpStrings.M2S1Description,
        'killorcapture',
        {
            Requirements = {
                {
                    Area = 'M2_Aeon_North_Base',
                    Category = categories.FACTORY + categories.ENGINEER + categories.CONSTRUCTION,
                    CompareOp = '<=',
                    Value = 0,
                    ArmyIndex = Aeon
                },
                {
                    Area = 'M2_Aeon_South_Base',
                    Category = categories.FACTORY + categories.ENGINEER + categories.CONSTRUCTION,
                    CompareOp = '<=',
                    Value = 0,
                    ArmyIndex = Aeon
                },
            },
        }
    )
    ScenarioInfo.M1S1:AddProgressCallback(
        function(current, total)
            if current == 1 then
                ScenarioFramework.Dialogue(OpStrings.M2OneBaseDestroyed)
            end
        end
    )
    ScenarioInfo.M1S1:AddResultCallback(
        function(result)
            if result then
                ScenarioFramework.Dialogue(OpStrings.M2BasesDestroyed)
            end
        end
    )

    ---------------------------------
    -- Bonus Objective - Kill T2 Subs
    ---------------------------------
    local num = {40, 60, 80}
    ScenarioInfo.M2B1 = Objectives.ArmyStatCompare(
        'bonus',
        'incomplete',
        OpStrings.M2B1Title,
        LOCF(OpStrings.M2B1Description, num[Difficulty]),
        'kill',
        {
            Armies = {'HumanPlayers'},
            StatName = 'Enemies_Killed',
            CompareOp = '>=',
            Value = num[Difficulty],
            Category = categories.xas0204,
            Hidden = true,
        }
    )

    -- Triggers
    -- Start naval attacks from the south base if the first Aeon base naval factories are destroyed
    ScenarioFramework.CreateAreaTrigger(M2SouthBaseNavalAttacks, 'M1_Aeon_Naval_Area', categories.FACTORY * categories.NAVAL, true, true, ArmyBrains[Aeon])

    -- Complete bonus objective to shoot down engie drop if player kills the south base before it can send the engineers
    ScenarioFramework.CreateAreaTrigger(M2BonusObjectiveSkipped, 'M2_Aeon_South_Base', categories.FACTORY + categories.ENGINEER + categories.CONSTRUCTION, true, true, ArmyBrains[Aeon])

    -- Unlock Rail Boat
    ScenarioFramework.CreateTimerTrigger(M2RailBoatUnlock, 2*60)

    -- Build engineers drop for bonus objective
    ScenarioFramework.CreateTimerTrigger(M2AeonAI.AeonM2SouthBaseEngineerDrop, 5*60)

    -- Warn player to hurry up
    ScenarioFramework.CreateTimerTrigger(M2Dialogue, 7*60)

    -- Look at the Aeon ACU building a base
    ScenarioFramework.CreateTimerTrigger(M2EnemyACUNIS, 8*60)

    -- Unlock T2 Arty
    ScenarioFramework.CreateTimerTrigger(M2T2ArtyUnlock, 11*60)

    -- Dialogue, Aeon going after the ship parts
    ScenarioFramework.CreateTimerTrigger(M2CaptureShipPart, 12*60)

    -- Continue to the third part of the mission
    local delay = {24, 21, 18}
    ScenarioFramework.CreateTimerTrigger(M2AttackWarning, delay[Difficulty]*60)
end

function M2SouthBaseNavalAttacks()
    M2AeonAI.AeonM2SouthBaseStartNavalAttacks()
end

function M2RailBoatUnlock()
    local function Unlock()
        ScenarioFramework.RemoveRestrictionForAllHumans(categories.xns0102 + categories.xas0204, true)
    end

    -- First play the dialogue, then unlock
    ScenarioFramework.Dialogue(OpStrings.M2RailBoatUnlock, Unlock, true)
end

function M2Dialogue()
    -- We're detecting increasing enemy activity
    ScenarioFramework.Dialogue(OpStrings.M2Dialogue)
end

function M2T2ArtyUnlock()
    local function Unlock()
        ScenarioFramework.RemoveRestrictionForAllHumans(categories.xnb2303 + categories.uab2303, true)
    end

    -- First play the dialogue, then unlock
    ScenarioFramework.Dialogue(OpStrings.M2T2ArtyUnlock, Unlock, true)
end

function M2DropEngineersPlatoonFormed(platoon)
    local units = platoon:GetPlatoonUnits()
    local engineers = {}

    for _, v in units do
        if EntityCategoryContains(categories.ENGINEER, v) then
            table.insert(engineers, v)
        end
    end

    --[[ -- TODO: Decide if we want to wait for the engineers to be loaded in the transport
    local attached = false
    for _, v in engineers do
        while not attached and v and not v:IsDead() do
            if v:IsUnitState('Attached') then
                attached = true
                break
            end
            WaitSeconds(.5)
        end
    end

    if not attached then
        LOG('All engineers died')
        return
    end
    --]]
    -- Make sure the engies won't get built again
    ArmyBrains[Aeon]:PBMRemoveBuilder('OSB_Child_EngineerAttack_T2Engineers_Aeon_M2_AeonOffMapEngineers')

    ---------------------------------------
    -- Bonus Objective - Kill Engineer Drop
    ---------------------------------------
    ScenarioInfo.M2B2 = Objectives.Kill(
        'bonus',
        'incomplete',
        OpStrings.M2B2Title,
        OpStrings.M2B2Description,
        {
            Units = engineers,
            MarkUnits = false,
            Hidden = true,
        }
    )
    ScenarioInfo.M2B2:AddResultCallback(
        function(result)
            if result then
                ScenarioInfo.M2EngineersKilled = true
                ScenarioFramework.Dialogue(OpStrings.M2EngieDropKilled)
            end
        end
    )

    local function BonusObjFail(unit)
        if ScenarioInfo.M2B2.Active then
            ScenarioInfo.M2B2:ManualResult(false)
        end
        unit:Destroy()
    end

    -- If units get to this marker, player didnt shot it down
    for _, v in units do
        ScenarioFramework.CreateUnitToMarkerDistanceTrigger(BonusObjFail, v, 'M2_Aeon_Engineers_Drop_Marker', 60)
    end
end

function M2BonusObjectiveSkipped()
    -- In case player kills the south base before the engineer drop even happens
    if not ScenarioInfo.M2B2 then
        ------------------------------------------
        -- Bonus Objective - Prevent Engineer Drop
        ------------------------------------------
        ScenarioInfo.M2B2 = Objectives.Basic(
            'bonus',
            'complete',
            OpStrings.M2B2Title,
            OpStrings.M2B2Description,
            Objectives.GetActionIcon('kill'),
            {}
        )

        ScenarioInfo.M2EngineersKilled = true
    end
end

function M2EnemyACUNIS()
    ScenarioFramework.FlushDialogueQueue()
    while ScenarioInfo.DialogueLock do
        WaitSeconds(0.2)
    end

    -- Debug check to prevent running the same code twice when skipping through the mission
    if ScenarioInfo.MissionNumber ~= 2 then
        return
    end

    ScenarioFramework.Dialogue(OpStrings.M2ACUNIS1, nil, true)

    WaitSeconds(5)

    -- Factory and some pgens
    local units = ScenarioUtils.CreateArmyGroup('Aeon', 'M2_Aeon_NIS_Base')
    for _, v in units do
        if EntityCategoryContains(categories.FACTORY, v) then
            IssueBuildFactory({v}, 'ual0105', 2)
        end
    end

    -- ACU to build some stuff
    local unit = ScenarioFramework.EngineerBuildUnits('Aeon', 'Aeon_ACU', 'Mex_To_Built', 'Fac_To_Built')

    Cinematics.SetInvincible('M2_Area')
    ScenarioFramework.SetPlayableArea('M3_Area', false)
    WaitSeconds(.1)
    Cinematics.EnterNISMode()

    local VizMarker1 = ScenarioFramework.CreateVisibleAreaLocation(20, unit:GetPosition(), 0, ArmyBrains[Player1])

    WaitSeconds(2)

    Cinematics.CameraMoveToMarker('Cam_M2_ACU_1', 0)
    ScenarioFramework.Dialogue(OpStrings.M2ACUNIS2, nil, true)

    WaitSeconds(2)

    Cinematics.CameraMoveToMarker('Cam_M2_ACU_2', 7)

    WaitSeconds(2)

    VizMarker1:Destroy()
    Cinematics.CameraMoveToMarker('Cam_M2_Intrro_3', 0)
    Cinematics.ExitNISMode()
    Cinematics.SetInvincible('M2_Area', true)
    ScenarioFramework.SetPlayableArea('M2_Area', false)

    -- Cleanup, destroy the offmap units, the base will get spawned later
    for _, v in GetUnitsInRect(ScenarioUtils.AreaToRect('M3_Aeon_Main_Base_Area')) do
        v:Destroy()
    end

    WaitSeconds(1)

    -- ACU
    M3AeonAI.AeonM3MainBaseAI()

    ScenarioInfo.M3AeonACU = ScenarioFramework.SpawnCommander('Aeon', 'Aeon_ACU', 'Warp', 'AeonACUName', true, false, -- TODO: Name for the ACU
        {'AdvancedEngineering', 'Shield', 'HeatSink'})
    ScenarioInfo.M3AeonACU:SetAutoOvercharge(true)
    ScenarioInfo.M3AeonACU:SetVeterancy(1 + Difficulty)

    -- So mass for the AI to build the base faster
    local num = {8000, 10000, 12000}
    ArmyBrains[Aeon]:GiveResource('MASS', num[Difficulty])
end

function M2CaptureShipPart()
    ScenarioFramework.Dialogue(OpStrings.M2ACUSectionCapture)
end

function M2AttackWarning()
    if not ScenarioInfo.M2AttackWarningPlayed then
        ScenarioInfo.M2AttackWarningPlayed = true
        -- Warn about the attack from the north and get into M3
        ScenarioFramework.Dialogue(OpStrings.M2AttackWarning, IntroMission3, true)
    end
end

------------
-- Mission 3
------------
function IntroMission3()
    ScenarioFramework.FlushDialogueQueue()
    while ScenarioInfo.DialogueLock do
        WaitSeconds(0.2)
    end

    -- Debug check to prevent running the same code twice when skipping through the mission
    if ScenarioInfo.MissionNumber ~= 2 then
        return
    end
    ScenarioInfo.MissionNumber = 3

    ----------
    -- Aeon AI
    ----------
    -- Main Base
    M3AeonAI.SpawnGate()

    -- Start attacks
    M3AeonAI.StartAttacks()

    -- Research Base
    ScenarioUtils.CreateArmyGroup('Aeon', 'M3_Aeon_Research_Base_D' .. Difficulty)

    -- Walls
    ScenarioUtils.CreateArmyGroup('Aeon', 'M3_Walls')

    -- Patrols
    -- North Island
    if Difficulty >= 2 then
        -- Cruisers
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Aeon_North_Cruisers_D' .. Difficulty, 'GrowthFormation')
    end

    -- Submarines around the north island
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Aeon_North_Sub_Patrol_D' .. Difficulty, 'AttackFormation')
    ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_North_Island_Naval_Patrol_Chain')

    ------------
    -- Objective
    ------------
    ScenarioInfo.M3ResearchBuildings = ScenarioUtils.CreateArmyGroup('Aeon', 'M3_Research_Buildings_D' .. Difficulty)

    -- Wreckages
    ScenarioUtils.CreateArmyGroup('Crystals', 'M3_Wrecks', true)

    -- Give initial resources to the AI
    local num = {6000, 8000, 10000}
    ArmyBrains[Aeon]:GiveResource('MASS', num[Difficulty])
    ArmyBrains[Aeon]:GiveResource('ENERGY', 30000)

    -- Cunter attack
    M3CounterAttack()

    IntroMission3NIS()
end

function M3CounterAttack()
    -- All the units that need to be killed to finish the objective
    ScenarioInfo.M3CounterAttackUnits = {}

    local quantity = {}
    local trigger = {}
    local platoon
    local crashedShipPos = ScenarioInfo.CrashedShip:GetPosition()

    local function AddUnitsToObjTable(platoon)
        for _, v in platoon:GetPlatoonUnits() do
            if not EntityCategoryContains(categories.TRANSPORTATION + categories.SCOUT + categories.SHIELD, v) then
                table.insert(ScenarioInfo.M3CounterAttackUnits, v)
            end
        end
    end

    --------
    -- Drops
    --------
    for i = 1, 2 do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Aeon_Drops_Counter_' .. i, 'AttackFormation')
        ScenarioFramework.PlatoonAttackWithTransports(platoon, 'M3_Aeon_CA_Landing_Chain_' .. i, 'M3_Aeon_CA_Drop_Attack_Chain_' .. i, true)
        AddUnitsToObjTable(platoon)
    end

    -------------
    -- Amphibious
    -------------
    for i = 1, 3 do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Aeon_Amph_Attack_' .. i .. '_D' ..  Difficulty, 'GrowthFormation')
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_Main_Base_Base_Amphibious_Chain_' .. i)
        AddUnitsToObjTable(platoon)
    end
    
    ------
    -- Air
    ------
    for i = 1, 3 do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Air_Counter_' ..  i, 'GrowthFormation')
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_Main_Base_Air_Attack_Chain_' .. i)
        AddUnitsToObjTable(platoon)
    end

    -- sends gunships and strats at mass extractors up to 4, 6, 8 if < 500 units, up to 6, 8, 10 if >= 500 units
    local extractors = ScenarioFramework.GetListOfHumanUnits(categories.MASSEXTRACTION)
    local num = table.getn(extractors)
    quantity = {4, 6, 8}
    if num > 0 then
        if ScenarioFramework.GetNumOfHumanUnits(categories.ALLUNITS - categories.WALL) < 500 then
            if num > quantity[Difficulty] then
                num = quantity[Difficulty]
            end
        else
            quantity = {6, 8, 10}
            if num > quantity[Difficulty] then
                num = quantity[Difficulty]
            end
        end
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Aeon_Adapt_Mex_Gunships_D' .. Difficulty, 'GrowthFormation')
            IssueAttack(platoon:GetPlatoonUnits(), extractors[i])
            IssueAggressiveMove(platoon:GetPlatoonUnits(), crashedShipPos)
            AddUnitsToObjTable(platoon)

            local guard = ScenarioUtils.CreateArmyGroup('Aeon', 'M3_Aeon_Adapt_GunshipGuard')
            IssueGuard(guard, platoon:GetPlatoonUnits()[1])
        end
    end

    -- sends T2 gunships at every other shield, up to [2, 4, 10]
    quantity = {2, 4, 10}
    local shields = ScenarioFramework.GetListOfHumanUnits(categories.SHIELD * categories.STRUCTURE)
    num = table.getn(shields)
    if num > 0 then
        num = math.ceil(num/2)
        if num > quantity[Difficulty] then
            num = quantity[Difficulty]
        end
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_Adapt_T2Gunship', 'GrowthFormation', 5)
            IssueAttack(platoon:GetPlatoonUnits(), shields[i])
            IssueAggressiveMove(platoon:GetPlatoonUnits(), crashedShipPos)
            AddUnitsToObjTable(platoon)
        end
    end

    -- sends swift winds if player has more than [60, 50, 40] planes, up to 12, 1 group per 10, 8, 6
    num = ScenarioFramework.GetNumOfHumanUnits(categories.AIR * categories.MOBILE)
    quantity = {60, 50, 40}
    trigger = {10, 8, 6}
    if num > quantity[Difficulty] then
        num = math.ceil(num/trigger[Difficulty])
        if(num > 12) then
            num = 12
        end
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_Adapt_Swifts_D' .. Difficulty, 'GrowthFormation', 5)
            ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_Main_Base_Air_Attack_Chain_' .. Random(1, 3))
            AddUnitsToObjTable(platoon)
        end
    end

    -- sends swift winds if player has torpedo gunships, up to 10, 18, 26
    local torpGunships = ScenarioFramework.GetListOfHumanUnits(categories.xna0203)
    num = table.getn(torpGunships)
    quantity = {10, 18, 26}
    if num > 0 then
        if num > quantity[Difficulty] then
            num = quantity[Difficulty]
        end
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_Adapt_TorpGunshipHunt', 'GrowthFormation', 5)
            IssueAttack(platoon:GetPlatoonUnits(), torpGunships[i])
            ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_CA_Default_Air_Patrol_Chain')
            AddUnitsToObjTable(platoon)
        end
    end

    -- sends torpedo bombers if player has more than [14, 12, 10] T2 naval, up to 6, 8, 10 groups
    local T2Naval = ScenarioFramework.GetListOfHumanUnits(categories.NAVAL * categories.MOBILE * categories.TECH2)
    num = table.getn(T2Naval)
    quantity = {6, 8, 10}
    trigger = {14, 12, 10}
    if num > trigger[Difficulty] then
        if num > quantity[Difficulty] then
            num = quantity[Difficulty]
        end
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_Adapt_TorpBombers', 'GrowthFormation', 5)
            IssueAttack(platoon:GetPlatoonUnits(), T2Naval[i])
            IssueAggressiveMove(platoon:GetPlatoonUnits(), crashedShipPos)
            ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_CA_Default_Air_Patrol_Chain')
            AddUnitsToObjTable(platoon)
        end
    end

    --------
    -- Naval
    --------
    for i = 1, 2 do
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M3_Aeon_CA_Naval_Attack_' ..  i, 'GrowthFormation')
        ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_Main_Base_Naval_Attack_Chain_' .. i)
        AddUnitsToObjTable(platoon)
    end
    
    -- sends either destroyer or sub hunter on player's T2 units, up to 4, 7, 10 if players have more than 10 units
    local T2Naval = ScenarioFramework.GetListOfHumanUnits(categories.NAVAL * categories.MOBILE * categories.TECH2)
    num = table.getn(T2Naval) - 10
    quantity = {4, 7, 10}
    if num > 0 then
        if num > quantity[Difficulty] then
            num = quantity[Difficulty]
        end
        for i = 1, num do
            if Random(1,3) == 1 then -- Higher chance to get destroyer
                platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_CA_SubHunters', 'AttackFormation', 1 + Difficulty)
            else
                platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_CA_Destroyers', 'AttackFormation', 1 + Difficulty)
            end
            IssueAttack(platoon:GetPlatoonUnits(), T2Naval[i])
            ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_CA_Default_Air_Patrol_Chain')
            AddUnitsToObjTable(platoon)
        end
    end

    -- sends 1 cruiser for every 70, 60, 50 air units
    local air = ScenarioFramework.GetListOfHumanUnits(categories.AIR * categories.MOBILE)
    num = table.getn(air)
    quantity = {70, 60, 50}
    if num > quantity[Difficulty] then
        num = math.ceil(num/quantity[Difficulty])
        for i = 1, num do
            platoon = ScenarioUtils.CreateArmyGroupAsPlatoonVeteran('Aeon', 'M3_Aeon_CA_Cruiser', 'AttackFormation', 1 + Difficulty)
            ScenarioFramework.PlatoonPatrolChain(platoon, 'M3_Aeon_Main_Base_Naval_Attack_Chain_' .. Random(1, 2))
            AddUnitsToObjTable(platoon)
        end
    end
end

function IntroMission3NIS()
    ScenarioFramework.SetPlayableArea('M3_Area', true)

    if not SkipNIS3 then
        Cinematics.EnterNISMode()

        ScenarioFramework.Dialogue(OpStrings.M3Intro1, nil, true)
        WaitSeconds(1)

        -- Vision for NIS location
        local VisMarker1 = ScenarioFramework.CreateVisibleAreaLocation(40, 'VizMarker_3', 0, ArmyBrains[Player1])
        local VisMarker2 = ScenarioFramework.CreateVisibleAreaLocation(50, 'VizMarker_4', 0, ArmyBrains[Player1])
        local VisMarker3 = ScenarioFramework.CreateVisibleAreaLocation(50, 'VizMarker_5', 0, ArmyBrains[Player1])

        --Cinematics.CameraTrackEntity(ScenarioInfo.UnitNames[Aeon]['M3_NIS_Unit_1'], 30, 3)
        
        Cinematics.CameraMoveToMarker('Cam_M3_Intro_1', 4)

        WaitSeconds(2)

        --Cinematics.CameraTrackEntity(ScenarioInfo.UnitNames[Aeon]['M3_NIS_Unit_2'], 30, 2)
        ScenarioFramework.Dialogue(OpStrings.M3Intro2, nil, true)
        Cinematics.CameraMoveToMarker('Cam_M3_Intro_2', 4)

        WaitSeconds(2)

        Cinematics.CameraMoveToMarker('Cam_M3_Intro_3', 2)

        VisMarker1:Destroy()
        VisMarker2:Destroy()
        VisMarker3:Destroy()

        WaitSeconds(1)

        Cinematics.ExitNISMode()
    end

    StartMission3()
end

function StartMission3()
    ScenarioFramework.Dialogue(OpStrings.M3PostIntro, nil, true)

    --------------------------------------------
    -- Primary Objective - Defeat Counter Attack
    --------------------------------------------
    ScenarioInfo.M3P1 = Objectives.KillOrCapture(
        'primary',
        'incomplete',
        OpStrings.M3P1Title,
        OpStrings.M3P1Description,
        {
            Units = ScenarioInfo.M3CounterAttackUnits,
            MarkUnits = false,
        }
    )
    ScenarioInfo.M3P1:AddResultCallback(
        function(result)
            if result then
                ScenarioFramework.Dialogue(OpStrings.M3CounterAttackDefeated, M3MapExpansion, true)
            end
        end
    )

    ChooseRandomEvent()

    -----------
    -- Triggers
    -----------
    -- Objective to locate Data Centre
    ScenarioFramework.CreateTimerTrigger(M3LocateDataCentres, 30)

    -- Unlock RAS
    ScenarioFramework.CreateTimerTrigger(M3RASUnlock, 2*60)

    -- Secondary objective to kill Aeon ACU
    ScenarioFramework.CreateArmyIntelTrigger(M3SecondaryKillAeonACU, ArmyBrains[Player1], 'LOSNow', false, true, categories.COMMAND, true, ArmyBrains[Aeon])

    -- Base Triggers
    -- Add Land factories to the main base
    ScenarioFramework.CreateTimerTrigger(M3AeonAI.AddLandFactories, 3*60)

    -- Add Air factories to the main base
    ScenarioFramework.CreateTimerTrigger(M3AeonAI.AddAirFactories, 6*60)

    -- Add defenses to the main base on medium and hard difficulty
    if Difficulty >= 2 then
        ScenarioFramework.CreateTimerTrigger(M3AeonAI.AddDefenses, 9*60)
    end

    -- Add Naval factories to the main base
    ScenarioFramework.CreateTimerTrigger(M3AeonAI.AddNavalFactories, 12*60)

    -- Add reesources to the main base on high difficulty
    if Difficulty >= 3 then
        ScenarioFramework.CreateTimerTrigger(M3AeonAI.AddResources, 15*60)
    end
end

function M3LocateDataCentres()
    ScenarioFramework.Dialogue(OpStrings.M3LocateDataCentres, nil, true)

    -----------------------------------------
    -- Primary Objective - Locate Data Centre
    -----------------------------------------
    ScenarioInfo.M3P2 = Objectives.Locate(
        'primary',
        'incomplete',
        OpStrings.M3P2Title,
        OpStrings.M3P2Description,
        {
            Units = ScenarioInfo.M3ResearchBuildings,
        }
    )
    ScenarioInfo.M3P2:AddResultCallback(
        function(result)
            if result then
                -- Different dialogue for Intel fleet scouting it for player
                if ScenarioInfo.IntelFrigate then
                    ScenarioFramework.Dialogue(OpStrings.M3IntelSpotsDataCentres, M3MapExpansion, true)
                else
                    ScenarioFramework.Dialogue(OpStrings.M3DataCentresSpotted, M3MapExpansion, true)
                end
            end
        end
    )

    -- Reminder
    ScenarioFramework.CreateTimerTrigger(M3P2Reminder, 8*60)

    -- Continue to the last part of the mission, 10min should be enough to send some scouts
    ScenarioFramework.CreateTimerTrigger(M3IntelFleetShowsUp, 12*60)
end

function M3RASUnlock()
    ScenarioFramework.Dialogue(OpStrings.M3RASUnlock)
    ScenarioFramework.RestrictEnhancements({
        -- Allowed: AdvancedEngineering, Capacitator, GunUpgrade, RapidRepair, MovementSpeedIncrease, ResourceAllocation
        'IntelProbe',
        'IntelProbeAdv',
        'DoubleGuns',
        'RapidRepair',
        'PowerArmor',
        'T3Engineering',
        'OrbitalBombardment',
        'OrbitalBombardmentHeavy'
    })
end

function M3sACUM2Northbase()
    ScenarioInfo.M3sACU = ScenarioFramework.SpawnCommander('Aeon', 'M3_Aeon_sACU', 'Gate', false, false, false,
        {'EngineeringFocusingModule', 'ResourceAllocation'})

    local platoon = ArmyBrains[Aeon]:MakePlatoon('', '')
    ArmyBrains[Aeon]:AssignUnitsToPlatoon(platoon, {ScenarioInfo.M3sACU}, 'Support', 'AttackFormation')

    ScenarioFramework.PlatoonMoveChain(platoon, 'M3_Aeon_sACU_Move_Chain')

    local function AddsACUToBase()
        local platoon = ScenarioInfo.M3sACU.PlatoonHandle
        platoon:StopAI()
        platoon.PlatoonData = {
            BaseName = 'M2_Aeon_North_Base',
            LocationType = 'M2_Aeon_North_Base',
        }
        platoon:ForkAIThread(import('/lua/AI/OpAI/BaseManagerPlatoonThreads.lua').BaseManagerSingleEngineerPlatoon)
    end

    ScenarioFramework.CreateUnitToMarkerDistanceTrigger(AddsACUToBase, ScenarioInfo.M3sACU, 'M2_Aeon_North_Base_Marker', 15)
end

function M3SecondaryKillAeonACU()
    ScenarioFramework.Dialogue(OpStrings.M3Secondary)

    ----------------------------------------
    -- Secondary Objective - Defeat Aeon ACU
    ----------------------------------------
    ScenarioInfo.M3S1 = Objectives.Kill(
        'secondary',
        'incomplete',
        OpStrings.M3S1Title,
        OpStrings.M3S1Description,
        {
            Units = {ScenarioInfo.M3AeonACU},
        }
    )
    ScenarioInfo.M3S1:AddResultCallback(
        function(result)
            if result then
                ScenarioFramework.Dialogue(OpStrings.M3SecondaryDone)

                -- Disable the main base
                M3AeonAI.DisableBase()
            end
        end
    )

    -- Reminder
    ScenarioFramework.CreateTimerTrigger(M3S1Reminder1, 15*60)
end

function M3IntelFleetShowsUp()
    -- Player takes too long, so the Intel Fleet shows up to save the day and locate the data centres
    if not ScenarioInfo.M3P2.Active then
        return
    end

    ScenarioFramework.Dialogue(OpStrings.M3IntelFleetShowsUp, nil, true)

    -- Spawn the Intel Frigate
    ScenarioInfo.IntelFrigate = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Intel_Frigate')
    IssueMove({ScenarioInfo.IntelFrigate}, ScenarioUtils.MarkerToPosition('Intel_Frigate_Destination'))
    -- Wait for it to move on the map
    WaitSeconds(10)

    -- Launch Intel Probe
    ScenarioFramework.Dialogue(OpStrings.M3IntelLaunchesProbes, nil, true)
    for i = 1, 4 do
        ScenarioInfo.IntelFrigate:LaunchProbe(ScenarioUtils.MarkerToPosition('M3_Probe_Marker_' .. i), 'IntelProbeAdvanced', {Lifetime = 60})
        WaitSeconds(1.5)
    end
end

function M3MapExpansion()
    if Objectives.IsComplete(ScenarioInfo.M3P1) and Objectives.IsComplete(ScenarioInfo.M3P2) then
        -- Different dialogues if the Intel fleet is on the map, it has better intel capabilities, so you dont have to wait that long.
        if ScenarioInfo.IntelFrigate then
            WaitSeconds(5)
            ScenarioFramework.Dialogue(OpStrings.M3MapExpansionIntel, IntroMission4, true)
        else
            WaitSeconds(20)
            ScenarioFramework.Dialogue(OpStrings.M3MapExpansion, IntroMission4, true)
        end
    end
end

------------
-- Mission 4
------------
function IntroMission4()
    ScenarioFramework.FlushDialogueQueue()
    while ScenarioInfo.DialogueLock do
        WaitSeconds(0.2)
    end

    -- Debug check to prevent running the same code twice when skipping through the mission
    if ScenarioInfo.MissionNumber ~= 3 then
        return
    end
    ScenarioInfo.MissionNumber = 4

    ----------
    -- Aeon AI
    ----------
    -- North Research Base
    M4AeonAI.AeonM4ResearchBaseNorthAI()

    -- South Research Base, if player didn't catch the transport in M2, else just Research buildings with few defenses
    if not ScenarioInfo.M2EngineersKilled then
        M4AeonAI.AeonM4ResearchBaseSouthAI()
    else
        ScenarioUtils.CreateArmyGroup('Aeon', 'M4_Aeon_Research_Base_South_D' .. Difficulty)
    end

    -- East Research Base
    ScenarioUtils.CreateArmyGroup('Aeon', 'M4_Aeon_Research_Base_East_D' .. Difficulty)

    -- TML Outposts, location picked randomly
    ChooseRandomBases()

    -- Start building the Tempest
    M4BuildTempest()

    -- Extra resources outside of the bases
    ScenarioUtils.CreateArmyGroup('Aeon', 'M4_Aeon_Extra_Resources_D' .. Difficulty)

    -- Walls
    ScenarioUtils.CreateArmyGroup('Aeon', 'M4_Walls')

    -- Refresh build restriction in support factories and engineers
    ScenarioFramework.RefreshRestrictions('Aeon')

    -- Expand the map, no cinematics in this part
    ScenarioFramework.SetPlayableArea('M4_Area', true)

    -- Wreckages
    ScenarioUtils.CreateArmyGroup('Crystals', 'M4_Wrecks', true)

    ----------
    -- Patrols
    ----------
    local patrol = nil
    -- East
    -- Land patrol around the buildings
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_East_Base_Land_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M4_Aeon_East_Base_Land_Defense_Chain')
    end

    -- Destroyers and Cruisers
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_East_Base_Naval_Patrol_Ships_D' .. Difficulty, 'GrowthFormation')
    ScenarioFramework.PlatoonPatrolChain(platoon, 'M4_Aeon_East_Base_Naval_Patrol_Chain')

    -- T2 subs
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_East_Base_Naval_Patrol_Subs_D' .. Difficulty, 'AttackFormation')
    ScenarioFramework.PlatoonPatrolChain(platoon, 'M4_Aeon_East_Base_Naval_Patrol_Chain')

    -- North Base
    -- Air base patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_North_Base_Air_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolRoute({v}, ScenarioPlatoonAI.GetRandomPatrolRoute(ScenarioUtils.ChainToPositions('M4_Aeon_North_Base_Air_Defense_Chain')))
    end

    -- Naval patrol
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_North_Base_Naval_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M4_Aeon_North_Base_Naval_Defense_Chain')
    end

    -- Tempest support, patrols around the base until the tempest is finished or killed
    ScenarioInfo.M4TempestNavalSupportPlatoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_Tempest_Support_D' .. Difficulty, 'AttackFormation')
    for _, v in ScenarioInfo.M4TempestNavalSupportPlatoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M4_Aeon_North_Base_Naval_Defense_Chain')
    end

    -- South
    -- If players didn't catch the transpor, set up some patrols around
    if not ScenarioInfo.M2EngineersKilled then
        -- Naval patrol
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_South_Naval_Patrol_D' .. Difficulty, 'NoFormation')
        for _, v in platoon:GetPlatoonUnits() do
            ScenarioFramework.GroupPatrolChain({v}, 'M4_Aeon_South_Base_Naval_Defense_Chain')
        end

        -- Land patrol
        platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_South_Land_Patrol_D' .. Difficulty, 'NoFormation')
        for _, v in platoon:GetPlatoonUnits() do
            ScenarioFramework.GroupPatrolRoute({v}, ScenarioPlatoonAI.GetRandomPatrolRoute(ScenarioUtils.ChainToPositions('M4_Aeon_South_Base_Land_Patrol_Chain')))
        end
    end

    -- Overall
    -- Air patrol over half of the map
    platoon = ScenarioUtils.CreateArmyGroupAsPlatoon('Aeon', 'M4_Aeon_Air_Patrol_D' .. Difficulty, 'NoFormation')
    for _, v in platoon:GetPlatoonUnits() do
        ScenarioFramework.GroupPatrolChain({v}, 'M4_Aeon_Air_Patrol_Chain')
    end

    ------------
    -- Objective
    ------------
    ScenarioInfo.M4ResearchBuildings = ScenarioUtils.CreateArmyGroup('Aeon', 'M4_Research_Buildings_D' .. Difficulty)

    -- Give initial resources to the AI
    local num = {10000, 12000, 14000}
    ArmyBrains[Aeon]:GiveResource('MASS', num[Difficulty])
    ArmyBrains[Aeon]:GiveResource('ENERGY', 30000)

    -- Dialogue choice for either kill or capture the buildings
    ScenarioFramework.Dialogue(OpStrings.M4PlayersChoice, M4ScenarioChoice, true)
end

function M4TMLOutpost(location)
    local units = {}
    local dialogue = OpStrings.M4TechUnlock1

    if location == 'North' then
        units = ScenarioUtils.CreateArmyGroup('Aeon', 'M4_TML_Outpost_North_D' .. Difficulty)
    elseif location == 'Centre' then
        units = ScenarioUtils.CreateArmyGroup('Aeon', 'M4_TML_Outpost_Centre_D' .. Difficulty)
    elseif location == 'South' then
        units = ScenarioUtils.CreateArmyGroup('Aeon', 'M4_TML_Outpost_South_D' .. Difficulty)
    elseif location == 'None' then
        -- Unlock dialogue without a warning as there's no TML outpost
        dialogue = OpStrings.M4TechUnlock2
    end

    WaitSeconds(45)
    ScenarioFramework.Dialogue(dialogue)

    -- Unlock TML/TMD
    ScenarioFramework.RemoveRestrictionForAllHumans(
        categories.xnb2208 + -- Nomads TML
        categories.xnb4204 + -- Nomads TMD
        categories.uab2108 + -- Aeon TML
        categories.uab4201,  -- Aeon TMD
        true
    )

    local delay = {150, 120, 90}
    WaitSeconds(delay[Difficulty])

    for _, v in units do
        if v and not v:IsDead() and EntityCategoryContains(categories.TACTICALMISSILEPLATFORM, v) then
            local plat = ArmyBrains[Aeon]:MakePlatoon('', '')
            ArmyBrains[Aeon]:AssignUnitsToPlatoon(plat, {v}, 'Attack', 'NoFormation')
            plat:ForkAIThread(plat.TacticalAI)
            WaitSeconds(4)
        end
    end
end

function M4ScenarioChoice()
    local dialogue = CreateDialogue(OpStrings.M4ChoiceTitle, {OpStrings.M4ChoiceKill, OpStrings.M4ChoiceCapture}, 'right')
    dialogue.OnButtonPressed = function(self, info)
        dialogue:Destroy()
        if info.buttonID == 1 then
            -- Build the gate
            ScenarioInfo.M4PlayersPlan = 'kill'
            ScenarioFramework.Dialogue(OpStrings.M4DestroyDataCentre, StartMission4, true)
        else
            -- Use Charis' gate
            ScenarioInfo.M4PlayersPlan = 'capture'
            ScenarioFramework.Dialogue(OpStrings.M4CaptureDataCentre, StartMission4, true)
        end
    end

    WaitSeconds(30)

    -- Remind player to pick the plan
    if not ScenarioInfo.M4PlayersPlan then
        ScenarioFramework.Dialogue(OpStrings.M4ChoiceReminder, nil, true)
    else
        return
    end

    WaitSeconds(15)

    -- If player takes too long, continue with the mission
    if not ScenarioInfo.M4PlayersPlan then
        dialogue:Destroy()
        ScenarioInfo.M4PlayersPlan = 'kill'
        ScenarioFramework.Dialogue(OpStrings.M4ForceChoice, StartMission4, true)
    end
end

function StartMission4()
    if ScenarioInfo.M4PlayersPlan == 'kill' then
        -------------------------------------------------
        -- Primary Objective - Destroy Research Buildings
        -------------------------------------------------
        ScenarioInfo.M4P1 = Objectives.CategoriesInArea(
            'primary',
            'incomplete',
            OpStrings.M4P1TitleKill,
            OpStrings.M4P1DescriptionKill,
            'kill',
            {
                MarkUnits = true,
                MarkArea = true,
                Requirements = {
                    {
                        Area = 'M3_Aeon_Research_Base_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '<=',
                        Value = 0,
                        ArmyIndex = Aeon,
                    },
                    {
                        Area = 'M4_Aeon_Research_Base_North_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '<=',
                        Value = 0,
                        ArmyIndex = Aeon,
                    },
                    {
                        Area = 'M4_Aeon_Research_Base_East_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '<=',
                        Value = 0,
                        ArmyIndex = Aeon,
                    },
                    {
                        Area = 'M4_Aeon_Research_Base_South_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '<=',
                        Value = 0,
                        ArmyIndex = Aeon,
                    },
                },
            }
        )
        ScenarioInfo.M4P1:AddProgressCallback(
            function(current, total)
                -- Don't use these dialogues if we're nuking the targets
                if not ScenarioInfo.M4NukesLaunched then
                    if current == 1 then
                        if not ScenarioInfo.M3AeonACU.Dead then
                            ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyed1)
                        else
                            ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyedACUDead1)
                        end
                    elseif current == 2 then
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyed2)
                    elseif current == 3 then
                        if not ScenarioInfo.M3AeonACU.Dead then
                            ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyed3)
                        else
                            ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyedACUDead3)
                        end
                    end
                end
            end
        )
        ScenarioInfo.M4P1:AddResultCallback(
            function(result)
                if result then
                    -- Different dialogue when we nuke the centres and when we kill them the normal way
                    if ScenarioInfo.M4NukesLaunched then
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentresNuked, nil, true)
                    elseif not ScenarioInfo.M3AeonACU.Dead then
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyed4, nil, true)
                    else
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreDestroyedACUDead4, nil, true)
                    end
                end
            end
        )

        -- Offer player to nuke the target bases with enough mass provided
        ScenarioFramework.CreateTimerTrigger(M4NukeOption, 40)

    elseif ScenarioInfo.M4PlayersPlan == 'capture' then
        -- Fill the required number of structures as it differs based on difficulty
        local objTbl = {
            ['M3_Aeon_Research_Base_Area'] = 0,
            ['M4_Aeon_Research_Base_North_Area'] = 0,
            ['M4_Aeon_Research_Base_East_Area'] = 0,
            ['M4_Aeon_Research_Base_South_Area'] = 0,
        }
        for area, count in objTbl do
            local units = ArmyBrains[Aeon]:GetListOfUnits(categories.CIVILIAN, false)
            objTbl[area] = table.getn(units)

            -- Make sure the civilian structures won't die as we want to capture them
            for _, unit in units do
                SetUnitInvincible(unit)
                -- And also that it won't die once it's captured!
                ScenarioFramework.CreateUnitCapturedTrigger(nil, SetUnitInvincible, unit)
            end
        end

        -------------------------------------------------
        -- Primary Objective - Capture Research Buildings
        -------------------------------------------------
        ScenarioInfo.M4P1 = Objectives.CategoriesInArea(
            'primary',
            'incomplete',
            OpStrings.M4P1TitleCapture,
            OpStrings.M4P1DescriptionCapture,
            'capture',
            {
                MarkUnits = true,
                MarkArea = true,
                Requirements = {
                    {
                        Area = 'M3_Aeon_Research_Base_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '>=',
                        Value = objTbl['M3_Aeon_Research_Base_Area'],
                        Armies = {'HumanPlayers'},
                    },
                    {
                        Area = 'M4_Aeon_Research_Base_North_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '>=',
                        Value = objTbl['M4_Aeon_Research_Base_North_Area'],
                        Armies = {'HumanPlayers'},
                    },
                    {
                        Area = 'M4_Aeon_Research_Base_East_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '>=',
                        Value = objTbl['M4_Aeon_Research_Base_East_Area'],
                        Armies = {'HumanPlayers'},
                    },
                    {
                        Area = 'M4_Aeon_Research_Base_South_Area',
                        Category = categories.CIVILIAN,
                        CompareOp = '>=',
                        Value = objTbl['M4_Aeon_Research_Base_South_Area'],
                        Armies = {'HumanPlayers'},
                    },
                },
            }
        )
        ScenarioInfo.M4P1:AddProgressCallback(
            function(current, total)
                if current == 1 then
                    if not ScenarioInfo.M3AeonACU.Dead then
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreCaptured1)
                    else
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreCapturedACUDead1)
                    end
                elseif current == 2 then
                    ScenarioFramework.Dialogue(OpStrings.M4DataCentreCaptured2)
                elseif current == 3 then
                    if not ScenarioInfo.M3AeonACU.Dead then
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreCaptured3)
                    else
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreCapturedACUDead3)
                    end
                end
            end
        )
        ScenarioInfo.M4P1:AddResultCallback(
            function(result)
                if result then
                    if not ScenarioInfo.M3AeonACU.Dead then
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreCaptured4, nil, true)
                    else
                        ScenarioFramework.Dialogue(OpStrings.M4DataCentreCapturedACUDead4, nil, true)
                    end
                end
            end
        )

        -- Free intel on the bases form the Intel fleet
        ScenarioFramework.CreateTimerTrigger(M4IntelOnDataCentres, 15)
    end

    -- Objective group to handle winning, research buildings and reclaiming ship parts
    ScenarioInfo.M4Objectives = Objectives.CreateGroup('M4Objectives', PlayerWin)
    ScenarioInfo.M4Objectives:AddObjective(ScenarioInfo.M4P1)
    if ScenarioInfo.M1P3.Active then
        ScenarioInfo.M4Objectives:AddObjective(ScenarioInfo.M1P3)
    end

    -- Reminder
    ScenarioFramework.CreateTimerTrigger(M4P1Reminder1, 15*60)

    -----------
    -- Triggers
    -----------
    -- Secondary objective to kill Tempest
    ScenarioFramework.CreateArmyIntelTrigger(M4SecondaryKillTempest, ArmyBrains[Player1], 'LOSNow', false, true, categories.uas0401, true, ArmyBrains[Aeon])

    ScenarioFramework.CreateTimerTrigger(M4UnlockFiendEngie, 7*60)
end

function M4IntelOnDataCentres()
    -- Spawn the Intel frigate if we don't have it yet
    if not ScenarioInfo.IntelFrigate then
        ScenarioFramework.Dialogue(OpStrings.M4IntelFleetShowsUp)

        -- Spawn the Intel Frigate
        ScenarioInfo.IntelFrigate = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Intel_Frigate')
        IssueMove({ScenarioInfo.IntelFrigate}, ScenarioUtils.MarkerToPosition('Intel_Frigate_Destination'))
        -- Wait for it to move on the map
        WaitSeconds(10)
    end

    -- Launch Intel Probes
    -- TODO: OpStrings.M4IntelLaunchesProbes more logic for different types of probes
    ScenarioFramework.Dialogue(OpStrings.M4IntelLaunchesAdvancedProbes)
    for i = 1, 4 do
        ScenarioInfo.IntelFrigate:LaunchProbe(ScenarioUtils.MarkerToPosition('M4_Probe_Marker_' .. i), 'IntelProbeAdvanced', {Lifetime = 9999}) -- TODO: Remove Lifetime once it's supported
        WaitSeconds(1.5)
    end
end

function M4NukeOption()
    -- Announce the option from the destroyer fleet to nuke the data cantres for the player
    ScenarioFramework.Dialogue(OpStrings.M4NukeOffer, nil, true)

    -- Create the nuke launcher offmap, stop it from building missiles and load it with goodies right away!
    ScenarioInfo.M4NukeLauncher = ScenarioUtils.CreateArmyUnit('Crashed_Ship', 'Nuke_Launcher')
    IssueStop({ScenarioInfo.M4NukeLauncher})
    ScenarioInfo.M4NukeLauncher:GiveNukeSiloAmmo(4)

    local sentMass = 0

    local dialogue = CreateDialogue(LOCF(OpStrings.NukeDialog, sentMass, MassRequiredForNukes), {OpStrings.NukeSendMassBtn}, 'right')
    dialogue.OnButtonPressed = function(self, info)
        -- Take away the mass
        local massTaken = ArmyBrains[info.presser]:TakeResource('Mass', ArmyBrains[info.presser]:GetEconomyStored('Mass'))
        sentMass = sentMass + massTaken

        -- If it's not enough yet, update the dialog
        if sentMass < MassRequiredForNukes then
            dialogue:SetText(LOCF(OpStrings.NukeDialog, math.floor(sentMass), MassRequiredForNukes))
        else
            -- Once we have enough mass, remove the dialog, pack the mass tightly and send it away!
            dialogue:Destroy()
            M4LaunchNukes()
        end
    end
end

function M4LaunchNukes()
    ScenarioFramework.Dialogue(OpStrings.M4NukesLaunched, nil, true)

    ScenarioInfo.M4NukesLaunched = true

    for i = 1, 4 do
        IssueNuke({ScenarioInfo.M4NukeLauncher}, ScenarioUtils.MarkerToPosition('M4_Nuke_Marker_' .. i))
    end
end

function M4UnlockFiendEngie()
    local function Unlock()
        ScenarioFramework.RemoveRestrictionForAllHumans(categories.xnl0209, true)
    end

    -- First play the dialogue, then unlock
    ScenarioFramework.Dialogue(OpStrings.M4FieldEngieUnlock, Unlock)
end

function M4BuildTempest()
    -- Makes the Tempest take 24, 16, 8 minutes to build
    local multiplier = {0.5, 1, 2}

    BuffBlueprint {
        Name = 'Op3M4EngBuildRate',
        DisplayName = 'Op3M4EngBuildRate',
        BuffType = 'AIBUILDRATE',
        Stacks = 'REPLACE',
        Duration = -1,
        EntityCategory = 'ENGINEER',
        Affects = {
            BuildRate = {
                Add = 0,
                Mult = multiplier[Difficulty],
            },
        },
    }

    local engineer = ScenarioUtils.CreateArmyUnit('Aeon', 'M4_Engineer')
    -- Apply buff here
    Buff.ApplyBuff(engineer, 'Op3M4EngBuildRate')

    -- Trigger to kill the Tempest if the engineer dies
    ScenarioFramework.CreateUnitDestroyedTrigger(M4EngineerDead, engineer)

    ScenarioInfo.M4TempestEngineer = engineer

    local platoon = ArmyBrains[Aeon]:MakePlatoon('', '')
    platoon.PlatoonData = {}
    platoon.PlatoonData.NamedUnitBuild = {'M4_Tempest'}
    platoon.PlatoonData.NamedUnitBuildReportCallback = M4TempestBuildProgressUpdate
    platoon.PlatoonData.NamedUnitFinishedCallback = M4TempestFinishBuild

    ArmyBrains[Aeon]:AssignUnitsToPlatoon(platoon, {engineer}, 'Support', 'None')

    platoon:ForkAIThread(ScenarioPlatoonAI.StartBaseEngineerThread)
end

function M4EngineerDead(unit)
    local tempest = unit.UnitBeingBuilt
    if tempest and not tempest:IsDead() then
        tempest:Kill()
    end
end

local LastUpdate = 0
function M4TempestBuildProgressUpdate(unit, eng)
    if unit:IsDead() then
        return
    end

    if not unit.UnitPassedToScript then
        unit.UnitPassedToScript = true
        M4TempestStarted(unit)
    end

    local fractionComplete = unit:GetFractionComplete()
    if math.floor(fractionComplete * 100) > math.floor(LastUpdate * 100) then
        LastUpdate = fractionComplete
        M4TempestBuildPercentUpdate(math.floor(LastUpdate * 100))
    end
end

function M4TempestStarted(unit)
    ScenarioInfo.M4Tempest = unit

    ----------------------------------------------------------
    -- Bonus Objective - Destroy Tempest before it's completed
    ----------------------------------------------------------
    ScenarioInfo.M4B1 = Objectives.Kill(
        'bonus',
        'incomplete',
        OpStrings.M4B1Title,
        OpStrings.M4B1Description,
        {
            Units = {unit},
            MarkUnits = false,
            Hidden = true,
        }
    )
    ScenarioInfo.M4B1:AddResultCallback(
        function(result)
            if result then
                ScenarioInfo.M4TempestKilledUnfinished = true

                -- Dialogue that the tempest is killed and launch the naval attack at the player
                ScenarioFramework.Dialogue(OpStrings.M4TempestKilledUnfinished, M4LaunchTempestAttack)
            end
        end
    )
end

function M4TempestBuildPercentUpdate(percent)
    if percent == 25 and ScenarioInfo.M4TempestObjectiveAssigned and not ScenarioInfo.M4Tempest25Dialogue then
        ScenarioInfo.M4Tempest25Dialogue = true
        ScenarioFramework.Dialogue(OpStrings.M4Tempest25PercentDone)
    elseif percent == 50 and ScenarioInfo.M4TempestObjectiveAssigned and not ScenarioInfo.M4Tempest50Dialogue then
        ScenarioInfo.M4Tempest50Dialogue = true
        ScenarioFramework.Dialogue(OpStrings.M4Tempest50PercentDone)
    elseif percent == 75 and ScenarioInfo.M4TempestObjectiveAssigned and not ScenarioInfo.M4Tempest75Dialogue then
        ScenarioInfo.M4Tempest75Dialogue = true
        ScenarioFramework.Dialogue(OpStrings.M4Tempest75PercentDone)
    elseif percent == 90 and ScenarioInfo.M4TempestObjectiveAssigned and not ScenarioInfo.M4Tempest90Dialogue then
        ScenarioInfo.M4Tempest90Dialogue = true
        ScenarioFramework.Dialogue(OpStrings.M4Tempest90PercentDone)
    end
end

function M4SecondaryKillTempest()
    if ScenarioInfo.M4TempestObjectiveAssigned then
        return
    end
    ScenarioInfo.M4TempestObjectiveAssigned = true

    local dialogue = OpStrings.M4TempestSpottedUnfinished
    local description = OpStrings.M4S1Description1

    -- Different dialogue and mission description if the tempest is finished
    if not ScenarioInfo.M4B1.Active then
        dialogue = OpStrings.M4TempestBuilt
        description = OpStrings.M4S1Description2
    end

    ScenarioFramework.Dialogue(dialogue)
    
    ----------------------------------------
    -- Secondary Objective - Destroy Tempest
    ----------------------------------------
    ScenarioInfo.M4S1 = Objectives.Kill(
        'secondary',
        'incomplete',
        OpStrings.M4S1Title,
        description,
        {
            Units = {ScenarioInfo.M4Tempest},
        }
    )
    ScenarioInfo.M4S1:AddResultCallback(
        function(result)
            if result then
                if not ScenarioInfo.M4TempestKilledUnfinished then
                    if not ScenarioInfo.M3AeonACU.Dead then
                        ScenarioFramework.Dialogue(OpStrings.M4TempestKilled1)
                    else
                        ScenarioFramework.Dialogue(OpStrings.M4TempestKilled2)
                    end
                end
            end
        end
    )
end

function M4TempestFinishBuild(tempest)
    if not tempest or tempest.Dead then
        return
    end

    if ScenarioInfo.M4B1.Active then
        ScenarioInfo.M4B1:ManualResult(false)
    end

    -- If the secondary objective is assigned already, inform player that the Tempest is done
    if ScenarioInfo.M5S1.Active then
        if not ScenarioInfo.M3AeonACU.Dead then
            ScenarioFramework.Dialogue(OpStrings.M4Tempest100PercentDone1)
        else
            ScenarioFramework.Dialogue(OpStrings.M4Tempest100PercentDone2)
        end
    end

    M4SecondaryKillTempest()

    ForkThread(M4LaunchTempestAttack, tempest)
end

function M4LaunchTempestAttack(tempest)
    if ScenarioInfo.M4TempestAttackLaunched then
        return
    end
    ScenarioInfo.M4TempestAttackLaunched = true

    if tempest and not tempest.Dead then
        local platoon = ArmyBrains[Aeon]:MakePlatoon('', '')
        ArmyBrains[Aeon]:AssignUnitsToPlatoon(platoon, {tempest}, 'Attack', 'None')

        ScenarioFramework.PlatoonPatrolChain(platoon, 'M4_Aeon_North_Base_Naval_Attack_Chain_1')
    end

    -- Wait a bit before sending in the navy, since the tempest moves slowly.
    WaitSeconds(30)

    -- Check if the platoon wasn't killed yet
    local allDead = true
    for _, unit in ScenarioInfo.M4TempestNavalSupportPlatoon:GetPlatoonUnits() do
        if not unit.Dead then
            allDead = false
            break
        end
    end

    if allDead then
        return
    end

    -- Guard the tempest and if it gets killed, continue the attack on players
    ScenarioInfo.M4TempestNavalSupportPlatoon:Stop()
    ScenarioInfo.M4TempestNavalSupportPlatoon:AggressiveMoveToLocation(ScenarioUtils.MarkerToPosition('M1_Aeon_Land_Atttack_3'))
end

------------
-- Reminders
------------
function M1P2Reminder1()
    if ScenarioInfo.M1P2.Active then
        ScenarioFramework.Dialogue(OpStrings.M1AeonBaseReminder1)

        ScenarioFramework.CreateTimerTrigger(M1P2Reminder2, 600)
    end
end

function M1P2Reminder2()
    if ScenarioInfo.M1P2.Active then
        ScenarioFramework.Dialogue(OpStrings.M1AeonBaseReminder2)
    end
end

function M1P3Reminder1()
    if ScenarioInfo.M1P3.Active then
        ScenarioFramework.Dialogue(OpStrings.ShipPartReminder1)

        ScenarioFramework.CreateTimerTrigger(M1P3Reminder2, 20*60)
    end
end

function M1P3Reminder2()
    if ScenarioInfo.M1P3.Active then
        ScenarioFramework.Dialogue(OpStrings.ShipPartReminder2)

        ScenarioFramework.CreateTimerTrigger(M1P3Reminder3, 20*60)
    end
end

function M1P3Reminder3()
    if ScenarioInfo.M1P3.Active then
        ScenarioFramework.Dialogue(OpStrings.ShipPartReminder3)
    end
end

function M1S1Reminder()
    if ScenarioInfo.M1S1.Active then
        ScenarioFramework.Dialogue(OpStrings.M1SecondaryReminder)

        ScenarioFramework.CreateTimerTrigger(M1S1Reminder2, 600)
    end
end

function M1S1Reminder2()
    if ScenarioInfo.M1S1.Active then
        ScenarioFramework.Dialogue(OpStrings.M1SecondaryReminder2)
    end
end

function M3P2Reminder()
    if ScenarioInfo.M3P2.Active then
        ScenarioFramework.Dialogue(OpStrings.M3LocateDataCentresReminder)
    end
end

function M3S1Reminder1()
    if ScenarioInfo.M3S1.Active then
        ScenarioFramework.Dialogue(OpStrings.M3SecondaryReminder1)

        ScenarioFramework.CreateTimerTrigger(M3S1Reminder2, 15*60)
    end
end

function M3S1Reminder2()
    if ScenarioInfo.M3S1.Active then
        ScenarioFramework.Dialogue(OpStrings.M3SecondaryReminder2)
    end
end

function M4P1Reminder1()
    if ScenarioInfo.M4P1.Active then
        ScenarioFramework.Dialogue(OpStrings.M4DataCentreReminder1)

        ScenarioFramework.CreateTimerTrigger(M4P1Reminder2, 20*60)
    end
end

function M4P1Reminder2()
    if ScenarioInfo.M4P1.Active then
        ScenarioFramework.Dialogue(OpStrings.M4DataCentreReminder2)
    end
end

--------------------------
-- Taunt Manager Dialogues
--------------------------
function SetupNicholsM1Warnings()
    -- Enemy units approaching
    NicholsTM:AddAreaTaunt('M1AeonAttackWarning', 'M1_UEF_Base_Area', categories.ALLUNITS - categories.SCOUT - categories.ENGINEER, ArmyBrains[Aeon])
    -- TODO: better system for this
    -- Ship damaged to x
    NicholsTM:AddDamageTaunt('M1ShipDamaged', ScenarioInfo.CrashedShip, .90)
    NicholsTM:AddDamageTaunt('M1ShipHalfDead', ScenarioInfo.CrashedShip, .95)
    NicholsTM:AddDamageTaunt('M1ShipAlmostDead', ScenarioInfo.CrashedShip, .98)
end

function SetupAeonM1Taunts()
    -- Aeon spots Nomads
    AeonM1TM:AddIntelCategoryTaunt('M1AeonIntroduction', ArmyBrains[Aeon], ArmyBrains[Player1], categories.ALLUNITS - categories.xno0001)
    -- After losing first few units, "automated defenses should hold"
    AeonM1TM:AddUnitsKilledTaunt('M1AeonMessage1', ArmyBrains[Aeon], categories.MOBILE, 15)
    -- Some small talk when first Aeon defenses are destroyed
    AeonM1TM:AddUnitsKilledTaunt('M1AeonMessage2', ArmyBrains[Aeon], categories.STRUCTURE * categories.DEFENSE, 3)
end

function SetupAeonM2Taunts()
end

function SetupAeonM3Taunts()
end

-------------------
-- Custom Functions
-------------------
-- Changes army color of the crystals
function RainbowEffect()
    local i = 1
    local frequency = math.pi * 2 / 255

    while not ScenarioInfo.OpEnded do
        WaitSeconds(0.1)

        if i >= 255 then i = 255 end

        local red   = math.sin(frequency * i + 2) * 127 + 128
        local green = math.sin(frequency * i + 0) * 127 + 128
        local blue  = math.sin(frequency * i + 4) * 127 + 128

        SetArmyColor('Crystals', red, green, blue)

        if i >= 255 then i = 1 end

        i = i + 1
    end
end

--- Handles reclaimed crystals
-- Adds max and current HP, resource production and other bonuses
function ShipPartReclaimed(number)
    local tbl = CrystalBonuses[number]

    -- Increase HP
    ShipMaxHP = tbl.maxHP
    ScenarioInfo.CrashedShip:AdjustHealth(ScenarioInfo.CrashedShip, tbl.addHP)

    -- Add resource production
    if tbl.addProduction then
        ScenarioInfo.CrashedShip:SetProductionPerSecondEnergy(tbl.addProduction.energy)
        ScenarioInfo.CrashedShip:SetProductionPerSecondMass(tbl.addProduction.mass)
    end
end

-- Monitors Ships health and adjusts it depending on the mission progress
function ShipHPThread()
    local ship = ScenarioInfo.CrashedShip
    local originalMaxHP = ScenarioInfo.CrashedShip:GetMaxHealth()

    while true do
        if ShipMaxHP == originalMaxHP then
            return
        end

        local hp = ScenarioInfo.CrashedShip:GetHealth()
        if hp > ShipMaxHP then
            ship:SetHealth(ship, ShipMaxHP)
        end

        WaitSeconds(.1)
    end
end

function SetUpBombardmentPing(skipDialogue)
    if not skipDialogue then
        ScenarioFramework.Dialogue(OpStrings.BombardmentReady)
    end

    -- Set up attack ping for players
    ScenarioInfo.AttackPing = PingGroups.AddPingGroup(OpStrings.BombardmentTitle, nil, 'attack', OpStrings.BombardmentDescription)
    ScenarioInfo.AttackPing:AddCallback(CallBombardement)
end

function CallBombardement(location)
    -- Random dialogue to confirm the target
    ScenarioFramework.Dialogue(OpStrings['BombardmentCalled' .. Random(1, 3)])

    ScenarioInfo['Player1CDR'].OrbitalUnit:LaunchOrbitalStrike(location, true)

    ScenarioInfo.AttackPing:Destroy()

    ScenarioFramework.CreateTimerTrigger(SetUpBombardmentPing, 5*60)
end

function SetUnitInvincible(unit)
    unit:SetCanTakeDamage(false)
    unit:SetCanBeKilled(false)
    unit:SetReclaimable(false)
end

-- Functions for randomly picking scenarios
function ChooseRandomBases()
    local data = ScenarioInfo.OperationScenarios['M' .. ScenarioInfo.MissionNumber].Bases

    if not ScenarioInfo.MissionNumber then
        error('*RANDOM BASE: ScenarioInfo.MissionNumber needs to be set.')
    elseif not data then
        error('*RANDOM BASE: No bases specified for mission number: ' .. ScenarioInfo.MissionNumber)
    end

    for _, base in data do
        local num = Random(1, table.getn(base.Types))

        base.CallFunction(base.Types[num])
    end
end

function ChooseRandomEvent(useDelay, customDelay)
    local data = ScenarioInfo.OperationScenarios['M' .. ScenarioInfo.MissionNumber].Events
    local num = ScenarioInfo.MissionNumber

    if not num then
        error('*RANDOM EVENT: ScenarioInfo.MissionNumber needs to be set.')
    elseif not data then
        error('*RANDOM EVENT: No events specified for mission number: ' .. num)
    end
    
    -- Randomly pick one event
    local function PickEvent(tblEvents)
        local availableEvents = {}
        local event

        -- Check available events
        for _, event in tblEvents do
            if not event.Used then
                table.insert(availableEvents, event)
            end
        end

        -- Pick one, mark as used
        local num = table.getn(availableEvents)

        if num ~= 0 then
            local event = availableEvents[Random(1, num)]
            event.Used = true

            return event
        else
            -- Reset availability and try to pick again
            for _, event in tblEvents do
                event.Used = false
            end
            
            return PickEvent(tblEvents)
        end
    end

    local event = PickEvent(data)

    ForkThread(StartEvent, event, num, useDelay, customDelay)
end

function StartEvent(event, missionNumber, useDelay, customDelay)
    if useDelay or useDelay == nil then
        local waitTime = customDelay or event.Delay -- Delay passed as a function parametr can over ride the delay from the OperationScenarios table
        local Difficulty = ScenarioInfo.Options.Difficulty

        if type(waitTime) == 'table' then
            WaitSeconds(waitTime[Difficulty])
        else
            WaitSeconds(waitTime)
        end
    end

    -- Check if the mission didn't end while we were waiting
    if ScenarioInfo.MissionNumber ~= missionNumber then
        return
    end

    event.CallFunction()
end

------------------
-- Debug Functions
------------------
function OnCtrlF3()
    ForkThread(M4ScenarioChoice)
end

function OnCtrlF4()
    if ScenarioInfo.MissionNumber == 1 then
        M1ShipPartsObjective()
        ForkThread(IntroMission2)
    elseif ScenarioInfo.MissionNumber == 2 then
        if not ScenarioInfo.M3AeonACU then
            ForkThread(M2EnemyACUNIS)
        else
            ForkThread(IntroMission3)
        end
    elseif ScenarioInfo.MissionNumber == 3 then
        ForkThread(IntroMission4)
    end
end

function OnShiftF3()
    ForkThread(M4NukeOption)
end

function OnShiftF4()
    for _, v in ArmyBrains[Aeon]:GetListOfUnits(categories.ALLUNITS - categories.WALL, false) do
        v:Kill()
    end
end

