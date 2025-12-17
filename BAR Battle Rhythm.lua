--------------------------------------------------------------------------------
-- BAR: Battle Rhythm
-- Coaching Widget (Public Release)
-- Author: JoozBrorg
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name      = "BAR: Battle Rhythm",
        desc      = "Coaching Widget (Public Release)",
        author    = "JoozBrorg",
        date      = "2025",
        license   = "GPLv2",
        layer     = 0,
        enabled   = true
    }
end

--------------------------------------------------------------------------------
-- Locals
--------------------------------------------------------------------------------

local fontSize = 14
local rhythmText = "Rhythm: Initialising…"
local rhythmColor = {0.8,0.9,1,1}
local tipText = nil

local myTeamID = Spring.GetMyTeamID()

-- Economy
local eCur,eMax,eInc,eExp = 0,0,0,0
local mCur,mMax,mInc,mExp = 0,0,0,0
local ePct,mPct = 0,0

-- Counts / State
local windCount = 0

local constructorCount = 0
local constructionTurretCount = 0
local buildPowerCount = 0

local converterCount = 0
local t2ConverterCount = 0

local mexCount = 0
local mexUpgradedCount = 0
local t2BuilderCount = 0

local radarCount = 0

-- Power buildings (best-effort name heuristic)
local reactorCount = 0
local afusCount = 0
local buildingReactor = false
local buildingAFUS = false

-- Factories & tempo
local factoryCount = 0
local idleFactoryCount = 0
local lowQueueFactoryCount = 0

-- Production
local hasT1Factory = false
local hasT2Factory = false
local hasT3Factory = false
local buildingT2Factory = false
local t2FinishedTime = -999

local todos = {}

-- Internal safety
local lastErrorTime = -999
local errorCooldown = 5 -- seconds

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function SafeUnitDef(uid)
    local udid = Spring.GetUnitDefID(uid)
    if not udid then return nil end
    return UnitDefs[udid]
end

local function ClearTodos()
    for k in pairs(todos) do todos[k] = nil end
end

local function IsTech2(ud)
    local tech = ud.customParams and ud.customParams.techlevel
    return (tech == "2" or tech == 2)
end

local function IsTech3(ud)
    local tech = ud.customParams and ud.customParams.techlevel
    return (tech == "3" or tech == 3)
end

local function LooksLikeUpgradedMex(ud)
    if IsTech2(ud) then return true end
    if not ud.name then return false end
    local n = ud.name
    if n:find("moho") then return true end
    if n:find("t2") and n:find("mex") then return true end
    if n:find("mex") and (n:find("up") or n:find("adv") or n:find("mo")) then return true end
    return false
end

local function IsReactorByName(name)
    if not name then return false end
    local n = name
    if n:find("fusion") then return true end
    if n:find("reactor") then return true end
    return false
end

local function IsAFUSByName(name)
    if not name then return false end
    local n = name
    if n:find("afus") then return true end
    if n:find("advfusion") then return true end
    if n:find("advancedfusion") then return true end
    if n:find("advanced_fusion") then return true end
    if n:find("advancedfusionreactor") then return true end
    return false
end

local function IsT2ConverterByName(name)
    if not name then return false end
    local n = name
    if n:find("converter") and (n:find("adv") or n:find("t2") or n:find("improved")) then
        return true
    end
    return false
end

local function SafeEcho(msg)
    local now = Spring.GetGameSeconds()
    if (now - lastErrorTime) >= errorCooldown then
        Spring.Echo("[BAR: Battle Rhythm] " .. tostring(msg))
        lastErrorTime = now
    end
end

-- Returns: isIdle, isLowQueue
-- - isIdle: not building AND no queued cmds
-- - isLowQueue: currently building but queue is empty (single-queue playstyle)
local function GetFactoryQueueState(uid)
    local okB, buildingUnitID = pcall(Spring.GetUnitIsBuilding, uid)
    local isBuilding = (okB and buildingUnitID ~= nil)

    local okQ, q = pcall(Spring.GetCommandQueue, uid, 2)
    local qLen = 0
    if okQ and type(q) == "table" then
        qLen = #q
    end

    local isIdle = (not isBuilding) and (qLen == 0)
    local isLowQueue = isBuilding and (qLen == 0)

    return isIdle, isLowQueue
end

--------------------------------------------------------------------------------
-- Economy
--------------------------------------------------------------------------------

local function UpdateEconomy()
    eCur,eMax,eInc,eExp = Spring.GetTeamResources(myTeamID, "energy")
    mCur,mMax,mInc,mExp = Spring.GetTeamResources(myTeamID, "metal")

    ePct = (eMax > 0) and (eCur / eMax) or 0
    mPct = (mMax > 0) and (mCur / mMax) or 0
end

--------------------------------------------------------------------------------
-- Unit Scan (SAFE)
--------------------------------------------------------------------------------

local function UpdateUnitCounts()
    windCount = 0

    constructorCount = 0
    constructionTurretCount = 0
    buildPowerCount = 0

    converterCount = 0
    t2ConverterCount = 0

    mexCount = 0
    mexUpgradedCount = 0
    t2BuilderCount = 0

    radarCount = 0

    reactorCount = 0
    afusCount = 0
    buildingReactor = false
    buildingAFUS = false

    factoryCount = 0
    idleFactoryCount = 0
    lowQueueFactoryCount = 0

    hasT1Factory = false
    hasT2Factory = false
    hasT3Factory = false
    buildingT2Factory = false

    local units = Spring.GetTeamUnits(myTeamID)
    if not units then return end

    for i = 1, #units do
        local uid = units[i]
        local ud = SafeUnitDef(uid)
        if ud then
            -- Builders
            if ud.isBuilder and not ud.isFactory then
                if ud.isBuilding then
                    constructionTurretCount = constructionTurretCount + 1
                else
                    constructorCount = constructorCount + 1
                end
                if IsTech2(ud) then
                    t2BuilderCount = t2BuilderCount + 1
                end
            end

            -- Factories
            if ud.isFactory then
                factoryCount = factoryCount + 1

                if IsTech3(ud) then
                    hasT3Factory = true
                elseif IsTech2(ud) then
                    if Spring.GetUnitIsBeingBuilt(uid) then
                        buildingT2Factory = true
                    else
                        if not hasT2Factory then
                            t2FinishedTime = Spring.GetGameSeconds()
                        end
                        hasT2Factory = true
                    end
                else
                    hasT1Factory = true
                end

                if not Spring.GetUnitIsBeingBuilt(uid) then
                    local isIdle, isLowQueue = GetFactoryQueueState(uid)
                    if isIdle then
                        idleFactoryCount = idleFactoryCount + 1
                    elseif isLowQueue then
                        lowQueueFactoryCount = lowQueueFactoryCount + 1
                    end
                end
            end

            -- Mex
            if ud.extractsMetal and ud.extractsMetal > 0 then
                mexCount = mexCount + 1
                if LooksLikeUpgradedMex(ud) then
                    mexUpgradedCount = mexUpgradedCount + 1
                end
            end

            -- Name-based
            if ud.name then
                local n = ud.name

                if n:find("wind") then windCount = windCount + 1 end
                if n:find("radar") then radarCount = radarCount + 1 end

                if n:find("converter") then
                    converterCount = converterCount + 1
                    if IsT2ConverterByName(n) or IsTech2(ud) then
                        t2ConverterCount = t2ConverterCount + 1
                    end
                end

                if IsAFUSByName(n) then
                    afusCount = afusCount + 1
                    if Spring.GetUnitIsBeingBuilt(uid) then buildingAFUS = true end
                elseif IsReactorByName(n) then
                    reactorCount = reactorCount + 1
                    if Spring.GetUnitIsBeingBuilt(uid) then buildingReactor = true end
                end
            end
        end
    end

    buildPowerCount = constructorCount + constructionTurretCount
end

--------------------------------------------------------------------------------
-- Core Logic
--------------------------------------------------------------------------------

local function UpdateRhythm()
    ClearTodos()
    local gameTime = Spring.GetGameSeconds()

    -- Net flows (important for conversion slider)
    local eNet = eInc - eExp
    local mNet = mInc - mExp

    -- Eco states (conversion-safe)
    local energyVeryLow = (eCur <= 150) or (eMax > 0 and eCur <= eMax * 0.03)
    local energyStall   = energyVeryLow and (eNet < -5)

    local energyFloating = (ePct > 0.80) and (eNet > 0)
    local energyComfort  = (eNet >= 0) and (ePct >= 0.20)

    local metalLow = (mPct < 0.35)
    local metalOk  = (mPct >= 0.35 and mPct < 0.65)

    -- Spend signals
    local metalSpendRatio  = (mInc > 0) and (mExp / mInc) or 0
    local floatingHard  = (mPct > 0.85) or (ePct > 0.90)
    local underSpending = (metalSpendRatio < 0.70) and (mInc >= 20)

    local idleFactories = (idleFactoryCount >= 1)
    local lowQueueFactories = (lowQueueFactoryCount >= 1)

    -- Project / tech stress
    local techStressT2 =
        (buildingT2Factory or (hasT2Factory and gameTime < t2FinishedTime + 30)) and
        (eNet < 0) and
        (ePct < 0.45)

    local buildingBigPower = (buildingReactor or buildingAFUS)
    local projectStress =
        buildingBigPower and (eNet < 0) and (ePct < 0.45) and (not energyStall)

    --------------------------------------------------------------------------
    -- Eco gates (your request)
    -- ecoComfort: allow low-queue reminders (gentle)
    -- ecoDominant: push aggressive pressure (hard coaching)
    --------------------------------------------------------------------------

    local ecoComfort =
        (eNet >= 0) and
        (energyComfort) and
        (mPct >= 0.25)

    local ecoDominant =
        (eNet >= 5) and
        (mNet >= 2) and
        (ePct >= 0.55) and
        (mPct >= 0.55) and
        (mInc >= 20)

    --------------------------------------------------------------------------
    -- HARD FAIL
    --------------------------------------------------------------------------

    if energyStall then
        rhythmText = "Rhythm: Broken — Energy stall"
        rhythmColor = {1,0.25,0.25,1}
        todos["energy"] = "Emergency: stop extra builds / quick wind (if needed)"
        tipText = "Hard stall = fix energy first (conversion slider can drain storage)."
        return
    end

    --------------------------------------------------------------------------
    -- SMART STRESS
    --------------------------------------------------------------------------

    if projectStress then
        rhythmText = "Rhythm: Project Stress — Power build draining"
        rhythmColor = {1,0.65,0.25,1}
        if buildingAFUS then
            todos["proj"] = "Finish AFUS (pause extra drains if needed)"
            tipText = "Dip is normal while AFUS builds. Don’t panic-build wind unless it becomes a hard stall."
        else
            todos["proj"] = "Finish reactor/fusion (pause extra drains if needed)"
            tipText = "Let backbone power complete; avoid stacking drains."
        end
        return
    end

    if techStressT2 then
        rhythmText = "Rhythm: Tech Stress — Energy dipping"
        rhythmColor = {1,0.65,0.25,1}
        todos["tech"] = "Stabilise: pause builds OR add 2–3 wind"
        tipText = "T2 strained eco — stabilise before continuing."
        return
    end

    --------------------------------------------------------------------------
    -- OPENING
    --------------------------------------------------------------------------

    if not hasT2Factory and not hasT1Factory and gameTime > 45 then
        rhythmText = "Rhythm: Opening — Establish production"
        rhythmColor = {0.55,0.85,1,1}
        todos["t1"] = "Build T1 Bot Lab"
        tipText = "Production enables everything."
        return
    end

    --------------------------------------------------------------------------
    -- T2 SPIKE: MEX UPGRADES
    --------------------------------------------------------------------------

    local targetUpgrades = 2
    if mexCount >= 6 then targetUpgrades = 3 end
    if mexCount >= 8 then targetUpgrades = 4 end
    local maxTarget = math.min(targetUpgrades, mexCount)

    if hasT2Factory and t2BuilderCount >= 1 and mexCount >= 3 and mexUpgradedCount < maxTarget then
        rhythmText = "Rhythm: Spike — Upgrade mex"
        rhythmColor = {0.7,1,0.9,1}
        todos["mex"] = "Upgrade mex with T2 builder ("..mexUpgradedCount.."/"..maxTarget..")"
        tipText = "First T2 builder priority: mex upgrades = strong metal growth."
        return
    end

    --------------------------------------------------------------------------
    -- TEMPO REMINDER (ecoComfort): low queue only
    --------------------------------------------------------------------------

    if ecoComfort and lowQueueFactories and (factoryCount > 0) and (not buildingBigPower) then
        rhythmText = "Rhythm: Tempo — Queue ahead"
        rhythmColor = {0.9,1,0.6,1}
        todos["lowq"] = "Low queue ("..lowQueueFactoryCount..") — queue 2–3 units ahead"
        tipText = "Single-queue is fine early; when eco is comfy, keep production smooth."
        -- Note: we don't return here if you're dominant; dominance block below will override with stronger coaching
        -- But for normal comfy eco, this is the right gentle nudge.
        if not ecoDominant then
            return
        end
    end

    --------------------------------------------------------------------------
    -- AGGRESSIVE PRESSURE (ecoDominant): push spend + pressure
    --------------------------------------------------------------------------

    if ecoDominant and (idleFactories or underSpending or floatingHard) and (factoryCount > 0) and (not buildingBigPower) then
        rhythmText = "Rhythm: Pressure — Spend your eco"
        rhythmColor = {1,0.9,0.35,1}

        if idleFactories then
            todos["idlefac"] = "Factory idle ("..idleFactoryCount..") — queue units NOW"
        else
            todos["spend"] = "You’re dominant — ramp unit production & pressure"
        end

        if lowQueueFactories then
            todos["lowq"] = "Queue 3–5 units ahead (reduce attention tax)"
        end

        if hasT2Factory then
            tipText = "Convert advantage into pressure: rally forward, poke expansions, deny mex."
        else
            tipText = "Spend now: units + map control beats sitting on stockpiles."
        end

        -- If energy is floating but metal is low/ok: suggest T2 converters (metal throughput)
        if hasT2Factory and energyFloating and (metalLow or metalOk) then
            local wantT2Conv = (mInc >= 60) and 4 or 2
            if t2ConverterCount < wantT2Conv then
                todos["t2conv"] = "Build T2 converters ("..t2ConverterCount.."/"..wantT2Conv..")"
            end
        end

        return
    end

    --------------------------------------------------------------------------
    -- STABLE / T3 STATE
    --------------------------------------------------------------------------

    if hasT3Factory then
        rhythmText = "Rhythm: T3 Online — Endgame tempo"
        rhythmColor = {0.9,0.7,1,1}
        tipText = "T3 online — convert eco into endgame units."
        todos["now"] = "Current focus: spend + pressure, converters if metal tight, buildpower if slow."
    else
        rhythmText = "Rhythm: Stable — Plan"
        rhythmColor = {0.75,1,0.75,1}
        tipText = nil
    end

    local suggested = 0

    -- 1) Metal bottleneck fix: T2 converters when energy is floating
    if suggested < 3 and hasT2Factory and energyFloating and (metalLow or metalOk) then
        local wantT2Conv = 2
        if mInc >= 60 then wantT2Conv = 4 end

        if t2ConverterCount < wantT2Conv then
            todos["t2conv"] = "Build T2 converters ("..t2ConverterCount.."/"..wantT2Conv..")"
            if not tipText then tipText = "You have spare energy — convert it into metal throughput." end
            suggested = suggested + 1
        end
    end

    -- 2) Buildpower (constructors/turrets)
    local wantBuildpower = 3
    if hasT2Factory and gameTime > 600 then wantBuildpower = 4 end
    if hasT2Factory and gameTime > 900 then wantBuildpower = 5 end
    if hasT3Factory and gameTime > 900 then wantBuildpower = math.max(wantBuildpower, 5) end

    if suggested < 3 and buildPowerCount < wantBuildpower and energyComfort and mInc >= 18 then
        todos["bp"] = "Add buildpower (constructors/turrets) ("..buildPowerCount.."/"..wantBuildpower..")"
        if not tipText then
            if radarCount == 0 or mexCount < 5 then
                tipText = "Prefer CONSTRUCTORS while expanding/scouting."
            else
                tipText = "Prefer CONSTRUCTION TURRETS if holding ground."
            end
        end
        suggested = suggested + 1
    end

    -- 3) Power backbone suggestion (DON'T suggest if AFUS exists AND energy is floating)
    local energyActuallyTight = (eNet < 0) and (ePct < 0.35)
    local alreadyPowerRich = (afusCount >= 1)

    if suggested < 3 and hasT2Factory and (not alreadyPowerRich) and (not energyFloating) and energyActuallyTight then
        todos["power"] = "Add T2 power backbone (reactor/fusion → AFUS later)"
        tipText = tipText or "If power is tight, backbone power beats extra wind midgame."
        suggested = suggested + 1
    end

    -- 4) T3 timing — only if T3 is NOT online
    local t3Ready =
        (not hasT3Factory) and
        hasT2Factory and
        (mInc >= 80) and
        (eNet >= 0) and
        (ePct >= 0.55) and
        (mexUpgradedCount >= math.min(3, mexCount)) and
        (buildPowerCount >= 4)

    if suggested < 3 and t3Ready then
        todos["t3"] = "Start T3 Lab now (safe window)"
        tipText = "You’re in a tech window — start T3 while your eco is strong."
        suggested = suggested + 1
    end

    -- Fallback menu if nothing triggered
    if suggested == 0 and not hasT3Factory then
        tipText = tipText or "Pick a win path: pressure, expand mex, or tech."
        if hasT2Factory then
            todos["menu1"] = "Option: keep factories producing (don’t float)"
            todos["menu2"] = "Option: T2 converters if metal feels tight"
            todos["menu3"] = "Option: start T3 if eco is huge + you can defend"
        else
            todos["menu0"] = "Option: prepare for T2 (energy buffer + buildpower)"
        end
    end
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------

function widget:DrawScreen()
    if not rhythmText then return end

    local vsx,vsy = Spring.GetViewGeometry()

    gl.Color(rhythmColor)
    gl.Text(rhythmText, vsx*0.5, vsy*0.80, fontSize*1.45, "oc")

    if tipText then
        gl.Color(0.9,0.95,1,1)
        gl.Text(tipText, vsx*0.5, vsy*0.75, fontSize*1.1, "oc")
    end

    local y = vsy*0.71
    for id,text in pairs(todos) do
        local r,g,b = 1,1,1
        if id == "energy" then r,g,b = 1,0.4,0.4 end
        if id == "tech" or id == "proj" then r,g,b = 1,0.7,0.4 end
        if id == "t1" then r,g,b = 0.6,0.85,1 end
        if id == "mex" then r,g,b = 0.7,1,0.9 end
        if id == "bp" then r,g,b = 0.9,0.95,0.6 end
        if id == "power" then r,g,b = 0.6,0.85,1 end
        if id == "t2conv" then r,g,b = 0.4,0.8,1 end
        if id == "t3" then r,g,b = 0.9,0.7,1 end
        if id == "idlefac" or id == "spend" then r,g,b = 1,0.9,0.35 end
        if id == "lowq" then r,g,b = 0.9,1,0.6 end
        if id == "now" then r,g,b = 0.9,0.7,1 end
        if id:find("menu") then r,g,b = 0.85,1,0.85 end

        gl.Color(r,g,b,1)
        gl.Text("• "..text, vsx*0.42, y, fontSize*1.1, "o")
        y = y - fontSize*1.3
    end
end

--------------------------------------------------------------------------------
-- Update (HARDENED)
--------------------------------------------------------------------------------

local function SafeTick()
    UpdateEconomy()
    UpdateUnitCounts()
    UpdateRhythm()
end

function widget:GameFrame(f)
    if f % 30 ~= 0 then return end

    local ok, err = pcall(SafeTick)
    if not ok then
        SafeEcho("Error: " .. tostring(err))
        rhythmText = "Rhythm: Error — check console/log"
        rhythmColor = {1,0.35,0.35,1}
        tipText = "A Lua error occurred. Message printed to console."
        ClearTodos()
    end
end
