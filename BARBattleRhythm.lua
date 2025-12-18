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
-- STATE / UI
--------------------------------------------------------------------------------

local fontSize = 14

local ecoLabel = "Initialising…"
local rhythmColor = {0.8, 0.85, 0.9, 1}

local phaseLabel = "—"
local phaseColor = {0.9, 0.9, 0.9, 1}
local currentPhaseKey = "opening"

-- Readiness / lens
local readinessText = ""
local readinessWhyText = ""
local readinessColor = {0.85, 0.9, 1, 1}
local readinessWhyColor = {0.8, 0.85, 1, 1}

local lensText = ""
local lensColor = {0.85, 0.9, 1, 1}

-- Per-resource arrow + color
local eArrow, mArrow = "→", "→"
local eArrowColor = {1,1,1,1}
local mArrowColor = {1,1,1,1}

local myTeamID = Spring.GetMyTeamID()

--------------------------------------------------------------------------------
-- ECONOMY (raw + smoothed)
--------------------------------------------------------------------------------

local eCur,eMax,eInc,eExp = 0,0,0,0
local mCur,mMax,mInc,mExp = 0,0,0,0
local ePct,mPct = 0,0

local eNetRaw, mNetRaw = 0,0
local eNetEMA, mNetEMA = 0,0
local EMA_ALPHA_BASE = 0.25

--------------------------------------------------------------------------------
-- COUNTS / FLAGS
--------------------------------------------------------------------------------

local windCount = 0
local constructorCount = 0
local constructionTurretCount = 0
local buildPowerCount = 0

-- converters detected by stats
local converterCount = 0
local t1ConverterCount = 0
local t2ConverterCount = 0
local t3ConverterCount = 0

local mexCount = 0
local mexUpgradedCount = 0
local t2BuilderCount = 0

local radarCount = 0
local reactorCount = 0
local afusCount = 0

local factoryCount = 0
local t1FactoryCount = 0
local t2FactoryCount = 0
local t3FactoryCount = 0

local hasT1Factory = false
local hasT2Factory = false
local hasT3Factory = false
local buildingT2Factory = false
local seenT2Factory = false
local t2FinishedTime = -999

-- intent/project flags
local bigProjectBuilding = false
local bigSpendBuilding = false
local anyFactoryBuilding = false

-- idle factories
local factoryIdleSince = {}    -- [unitID] = time when became idle
local idleFactoryCount = 0

--------------------------------------------------------------------------------
-- LISTS
--------------------------------------------------------------------------------

local milestones = {}
local todo = {}

local function Clear(t)
    for i = #t, 1, -1 do t[i] = nil end
end

local function Add(t, text, color, status)
    t[#t+1] = { text = text, color = color, status = status }
end

local function SetPhase(key, label)
    currentPhaseKey = key
    phaseLabel = label
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

local function IsTech2(ud)
    local t = ud.customParams and ud.customParams.techlevel
    return t == "2" or t == 2
end

local function IsTech3(ud)
    local t = ud.customParams and ud.customParams.techlevel
    return t == "3" or t == 3
end

local function IsWind(ud)
    if ud.windGenerator and ud.windGenerator > 0 then return true end
    return ud.name and ud.name:lower():find("wind")
end

local function IsAFUS(ud)
    return ud.name and ud.name:lower():find("afus")
end

local function IsReactor(ud)
    if not ud.name then return false end
    local n = ud.name:lower()
    return n:find("fusion") or n:find("reactor")
end

local function IsUnitComplete(uid)
    local _, _, _, _, buildProgress = Spring.GetUnitHealth(uid)
    if buildProgress == nil then
        return not Spring.GetUnitIsBeingBuilt(uid)
    end
    return buildProgress >= 0.999
end

-- Radar building ONLY
local function IsRadarUnit(ud)
    if not ud then return false end
    if (ud.radarRadius and ud.radarRadius > 0) then return true end
    if (ud.radarDistance and ud.radarDistance > 0) then return true end
    if ud.name then
        local n = ud.name:lower()
        if n:find("radar") then return true end
        if n:find("armrad") or n:find("corrad") then return true end
    end
    return false
end

-- Converter detection by actual conversion stats (energy upkeep -> metal make)
local function IsConverterBuilding(ud)
    if not ud or not ud.isBuilding then return false end
    local em = ud.energyUpkeep or 0
    local mm = ud.metalMake or 0
    return (em > 0.01) and (mm > 0.0001)
end

local function ConverterTier(ud)
    if IsTech3(ud) then return 3 end
    if IsTech2(ud) then return 2 end
    return 1
end

local function PhaseTimingColor(phaseKey, gameTimeSec)
    local targets = {
        opening  = 90,   -- 1:30
        t1Bridge = 210,  -- 3:30
        tech     = 300,  -- 5:00
        t2       = 480,  -- 8:00
        t3       = 660,  -- 11:00
        endgame  = nil,
    }

    local tEnd = targets[phaseKey]
    if not tEnd then return {0.9,0.9,0.9,1} end

    local delta = gameTimeSec - tEnd
    if delta <= 0 then return {0.6,1,0.6,1} end
    if delta <= 60 then return {1,0.95,0.45,1} end
    if delta <= 120 then return {1,0.75,0.35,1} end
    return {1,0.35,0.35,1}
end

--------------------------------------------------------------------------------
-- ECON UPDATE
--------------------------------------------------------------------------------

local function UpdateEconomy(projectActive)
    local alpha = EMA_ALPHA_BASE
    if projectActive then alpha = 0.40 end -- faster response during big spends

    eCur,eMax,eInc,eExp = Spring.GetTeamResources(myTeamID,"energy")
    mCur,mMax,mInc,mExp = Spring.GetTeamResources(myTeamID,"metal")

    ePct = (eMax>0) and eCur/eMax or 0
    mPct = (mMax>0) and mCur/mMax or 0

    eNetRaw = eInc - eExp
    mNetRaw = mInc - mExp

    eNetEMA = eNetEMA + alpha * (eNetRaw - eNetEMA)
    mNetEMA = mNetEMA + alpha * (mNetRaw - mNetEMA)
end

--------------------------------------------------------------------------------
-- FACTORY IDLE DETECTION
--------------------------------------------------------------------------------

local function FactoryIsActive(uid)
    local buildTarget = Spring.GetUnitIsBuilding(uid)
    if buildTarget then return true end

    if Spring.GetFullBuildQueue then
        local q = Spring.GetFullBuildQueue(uid)
        if q and next(q) ~= nil then return true end
    end

    return false
end

--------------------------------------------------------------------------------
-- UNIT SCAN
--------------------------------------------------------------------------------

local function UpdateUnits()
    windCount,constructorCount,constructionTurretCount = 0,0,0
    converterCount,t1ConverterCount,t2ConverterCount,t3ConverterCount = 0,0,0,0
    mexCount,mexUpgradedCount,t2BuilderCount = 0,0,0
    radarCount,reactorCount,afusCount = 0,0,0
    factoryCount,t1FactoryCount,t2FactoryCount,t3FactoryCount = 0,0,0,0

    hasT1Factory,hasT2Factory,hasT3Factory = false,false,false
    buildingT2Factory = false

    bigProjectBuilding = false
    bigSpendBuilding = false
    anyFactoryBuilding = false

    idleFactoryCount = 0
    local now = Spring.GetGameSeconds()

    for _,uid in ipairs(Spring.GetTeamUnits(myTeamID)) do
        local ud = UnitDefs[Spring.GetUnitDefID(uid)]
        if ud then
            local complete = IsUnitComplete(uid)
            local beingBuilt = not complete

            -- Factories
            if ud.isFactory then
                factoryCount = factoryCount + 1
                if beingBuilt then anyFactoryBuilding = true end

                if IsTech3(ud) then
                    t3FactoryCount = t3FactoryCount + 1
                    if complete then hasT3Factory = true end
                    if beingBuilt then bigProjectBuilding = true end
                elseif IsTech2(ud) then
                    t2FactoryCount = t2FactoryCount + 1
                    if beingBuilt then
                        buildingT2Factory = true
                        bigProjectBuilding = true
                    else
                        hasT2Factory = true
                        if not seenT2Factory then
                            seenT2Factory = true
                            t2FinishedTime = now
                        end
                    end
                else
                    t1FactoryCount = t1FactoryCount + 1
                    hasT1Factory = true
                end

                if complete then
                    local active = FactoryIsActive(uid)
                    if active then
                        factoryIdleSince[uid] = nil
                    else
                        if not factoryIdleSince[uid] then factoryIdleSince[uid] = now end
                        if (now - factoryIdleSince[uid]) > 10 then
                            idleFactoryCount = idleFactoryCount + 1
                        end
                    end
                end
            end

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

            -- Wind
            if IsWind(ud) then windCount = windCount + 1 end

            -- Mex
            if ud.extractsMetal and ud.extractsMetal > 0 then
                mexCount = mexCount + 1
                if IsTech2(ud) then mexUpgradedCount = mexUpgradedCount + 1 end
            end

            -- Radar building ONLY
            if complete and ud.isBuilding and IsRadarUnit(ud) then
                radarCount = radarCount + 1
            end

            -- Converters by stats
            if complete and IsConverterBuilding(ud) then
                converterCount = converterCount + 1
                local tier = ConverterTier(ud)
                if tier == 1 then t1ConverterCount = t1ConverterCount + 1
                elseif tier == 2 then t2ConverterCount = t2ConverterCount + 1
                else t3ConverterCount = t3ConverterCount + 1 end
            end

            -- Power spine projects
            if IsAFUS(ud) then
                if beingBuilt then bigProjectBuilding = true end
                if complete then afusCount = afusCount + 1 end
            elseif IsReactor(ud) then
                if beingBuilt then bigProjectBuilding = true end
                if complete then reactorCount = reactorCount + 1 end
            end

            -- Broader project awareness: big metal-cost building being built
            if beingBuilt and ud.isBuilding then
                local cost = ud.metalCost or 0
                if cost >= 600 then
                    bigSpendBuilding = true
                end
            end
        end
    end

    buildPowerCount = constructorCount + constructionTurretCount
end

--------------------------------------------------------------------------------
-- PHASE LOGIC
--------------------------------------------------------------------------------

local function UpdatePhase(t)
    if factoryCount == 0 then
        SetPhase("opening","Opening — Establish production (0:00–1:30)")
        return
    end

    if (not hasT2Factory) and (not buildingT2Factory) then
        SetPhase("t1Bridge","T1 Bridge — Stabilise & expand (1:30–3:30)")
        return
    end

    if buildingT2Factory or (seenT2Factory and t < t2FinishedTime + 20) then
        SetPhase("tech","Tech Window — Secure T2 (~3:30–5:00)")
        return
    end

    if hasT2Factory and not hasT3Factory then
        if (reactorCount > 0 or afusCount > 0) then
            SetPhase("t3","T3 Transition — Eco spine online (8:00–11:00)")
        else
            SetPhase("t2","T2 Spike — Upgrade mex & convert eco (5:00–8:00)")
        end
        return
    end

    if hasT3Factory then
        SetPhase("endgame","Endgame — Convert eco into power")
        return
    end
end

--------------------------------------------------------------------------------
-- RHYTHM ARROWS (smoothed + intent-aware)
--------------------------------------------------------------------------------

local function ArrowFrom(netEMA, pct, intentSpend)
    local upT = 3
    local flatT = -2
    if intentSpend then flatT = -8 end

    if netEMA > upT then return "↑","good" end
    if netEMA > flatT then return "→","ok" end
    if pct > 0.15 then
        return intentSpend and "↘" or "↓", intentSpend and "ok" or "warn"
    end
    return "↓↓","danger"
end

local function ColorForState(state)
    if state == "good" then return {0.7,1,0.7,1} end
    if state == "ok" then return {0.9,0.9,0.9,1} end
    if state == "warn" then return {1,0.8,0.4,1} end
    return {1,0.35,0.35,1}
end

local function UpdateRhythm(projectActive)
    local intentSpend = projectActive and (ePct > 0.35)
    local conversionLikely = (converterCount > 0) and (mNetEMA > 0) and (eNetEMA < 0) and (ePct > 0.2)

    local eA, eState = ArrowFrom(eNetEMA, ePct, intentSpend)
    local mA, mState = ArrowFrom(mNetEMA, mPct, false)

    eArrow, mArrow = eA, mA
    eArrowColor = ColorForState(eState)
    mArrowColor = ColorForState(mState)

    local label = "Stable Eco"
    local crashing = (eState=="danger") or (mState=="danger")
    local tight = (eState=="warn") or (mState=="warn")

    if crashing then
        label = "Crashing Eco"
    elseif conversionLikely and tight then
        label = "Converting — Watch Energy"
    elseif intentSpend and tight then
        label = "Project Spend — Hold Steady"
    elseif tight then
        label = "Leaning Tight Eco"
    end

    ecoLabel = label
    rhythmColor = crashing and {1,0.3,0.3,1}
              or tight and {1,0.75,0.35,1}
              or {0.6,1,0.6,1}
end

--------------------------------------------------------------------------------
-- HYBRID BUFFER MODEL (percent OR absolute) + READINESS + WHY
--------------------------------------------------------------------------------

local function ReadinessLabelAndColor(score)
    if score >= 75 then return "Safe window", {0.7,1,0.7,1} end
    if score >= 55 then return "Almost", {1,0.95,0.45,1} end
    return "Prep", {1,0.75,0.35,1}
end

local function WhyFromContrib(contrib, penaltyText, tag)
    if penaltyText and penaltyText ~= "" then
        return "Why: " .. penaltyText
    end

    local lowestKey = "eBuf"
    local lowestVal = contrib.eBuf

    local function chk(k, v)
        if v < lowestVal then lowestVal = v; lowestKey = k end
    end

    chk("mBuf", contrib.mBuf)
    chk("eTrend", contrib.eTrend)
    chk("mTrend", contrib.mTrend)

    if lowestKey == "eBuf" then
        return ("Why: Energy buffer low (%s)"):format(tag or "buffer")
    elseif lowestKey == "mBuf" then
        return ("Why: Metal buffer low (%s)"):format(tag or "buffer")
    elseif lowestKey == "eTrend" then
        return ("Why: Energy trend negative (%.1f/s)"):format(eNetEMA)
    else
        return ("Why: Metal trend negative (%.1f/s)"):format(mNetEMA)
    end
end

-- Converts percent+raw into a 0..1 buffer score, and returns a helpful tag string
local function HybridBufScore(pct, cur, pctFloor, pctSpan, rawFloor, rawSpan)
    local pScore = clamp((pct - pctFloor) / pctSpan, 0, 1)
    local rScore = clamp((cur - rawFloor) / rawSpan, 0, 1)
    local score = (pScore > rScore) and pScore or rScore

    local tag
    local pctTxt = ("%d%%"):format(math.floor(pct*100 + 0.5))
    local rawTxt = ("%d"):format(math.floor(cur + 0.5))

    -- Explain which branch is saving you (premium feel)
    if rScore > pScore then
        tag = ("raw %s (storage high)"):format(rawTxt)
    else
        tag = ("pct %s"):format(pctTxt)
    end

    return score, tag
end

-- Metal-aware weights (T2):
-- Ebuf 0.30 / Mbuf 0.30 / Etrend 0.20 / Mtrend 0.20
local function ReadinessForT2(projectActive)
    -- Hybrid thresholds tuned for early/midgame:
    -- Energy: consider "okay" if >=20% OR >=4000 raw
    -- Metal:  consider "okay" if >=15% OR >=200 raw
    local eBuf, eTag = HybridBufScore(ePct, eCur, 0.20, 0.50, 4000, 8000) -- 4k..12k ramps
    local mBuf, mTag = HybridBufScore(mPct, mCur, 0.15, 0.55, 200, 450)   -- 200..650 ramps

    local eTrend = clamp((eNetEMA + 8) / 16, 0, 1)
    local mTrend = clamp((mNetEMA + 4) / 10, 0, 1)

    local penalty = 0
    local penaltyText = ""
    local whyTag = ("E %s / M %s"):format(eTag, mTag)

    -- During active project builds, tighten “safe window”
    if projectActive then
        penalty = penalty + 8
        if penaltyText == "" then penaltyText = "Project in progress — protect buffers" end
    end

    -- Buildpower spike penalty
    if buildPowerCount >= 6 and (ePct < 0.35 and eCur < 6000 or eNetEMA < -2) then
        penalty = penalty + 15
        penaltyText = ("Buildpower spike risk (%d builders)"):format(buildPowerCount)
    end

    -- Raw metal crash guard (catches EMA lag)
    if projectActive and (mPct < 0.12 or mCur < 120 or mNetRaw < -6) then
        penalty = penalty + 20
        penaltyText = "Metal crash risk during build"
    end

    local score = 100 * (0.30*eBuf + 0.30*mBuf + 0.20*eTrend + 0.20*mTrend) - penalty
    score = clamp(score, 0, 100)

    local label, col = ReadinessLabelAndColor(score)
    local why = WhyFromContrib({eBuf=eBuf, mBuf=mBuf, eTrend=eTrend, mTrend=mTrend}, penaltyText, whyTag)

    return math.floor(score + 0.5), label, col, why
end

local function ReadinessForT3(projectActive)
    -- Hybrid thresholds for late midgame:
    -- Energy: >=25% OR >=8000 raw
    -- Metal:  >=20% OR >=450 raw
    local eBuf, eTag = HybridBufScore(ePct, eCur, 0.25, 0.55, 8000, 14000) -- 8k..22k
    local mBuf, mTag = HybridBufScore(mPct, mCur, 0.20, 0.60, 450, 900)    -- 450..1350

    local eTrend = clamp((eNetEMA + 10) / 20, 0, 1)
    local mTrend = clamp((mNetEMA + 5) / 12, 0, 1)

    local penalty = 0
    local penaltyText = ""
    local whyTag = ("E %s / M %s"):format(eTag, mTag)

    local energyRich = (ePct > 0.60) or (eNetEMA > 6) or (eCur > 12000)
    local metalPressure = (mPct < 0.35) or (mNetEMA < -3) or (mCur < 350)

    if projectActive then
        penalty = penalty + 6
        if penaltyText == "" then penaltyText = "Project in progress — avoid over-commit" end
    end

    -- Converter readiness: if energy is rich & metal pressured, want converters before T3
    if energyRich and metalPressure and t2ConverterCount < 4 then
        penalty = penalty + 12
        penaltyText = ("Need more T2 converters (%d/4)"):format(t2ConverterCount)
    end

    -- Upgrade readiness: T3 without upgraded mex is usually a trap
    if mexUpgradedCount < 3 then
        penalty = penalty + 10
        if penaltyText == "" then
            penaltyText = ("Need more upgraded mex (%d/3)"):format(mexUpgradedCount)
        end
    end

    local spine = (reactorCount > 0 or afusCount > 0) and 1 or 0
    local spineBonus = spine * 6

    -- Slightly more metal-weighted:
    -- Ebuf 0.28 / Mbuf 0.34 / Etrend 0.18 / Mtrend 0.20
    local score = 100 * (0.28*eBuf + 0.34*mBuf + 0.18*eTrend + 0.20*mTrend) + spineBonus - penalty
    score = clamp(score, 0, 100)

    local label, col = ReadinessLabelAndColor(score)
    local why = WhyFromContrib({eBuf=eBuf, mBuf=mBuf, eTrend=eTrend, mTrend=mTrend}, penaltyText, whyTag)

    return math.floor(score + 0.5), label, col, why
end

--------------------------------------------------------------------------------
-- LENS (Boom / Pressure / Balanced)
--------------------------------------------------------------------------------

local function UpdateLens()
    local boom = (mexCount >= 6) and (buildPowerCount >= 4) and (idleFactoryCount == 0)
    local pressure = (mexCount <= 5) and (factoryCount >= 1) and (buildPowerCount <= 3)

    if boom then
        lensText = "Lens: Boom (eco lead) — spend into upgrades/tech"
        lensColor = {0.75,0.95,1,1}
    elseif pressure then
        lensText = "Lens: Pressure (tempo) — keep factory queued"
        lensColor = {1,0.9,0.35,1}
    else
        lensText = "Lens: Balanced — keep tempo & prep next window"
        lensColor = {0.85,0.9,1,1}
    end
end

--------------------------------------------------------------------------------
-- GUIDANCE (Milestones + Todo + Prep fallback + slider/storage + idle + buildpower)
--------------------------------------------------------------------------------

local function UpdateGuidance(projectActive)
    Clear(milestones)
    Clear(todo)

    local t = Spring.GetGameSeconds()
    phaseColor = PhaseTimingColor(currentPhaseKey, t)
    UpdateLens()

    local function done(cond) return cond and "done" or nil end

    -- Phase-scoped buildpower milestones (ranges, eco-gated)
    local function AddBuildpowerMilestones()
        if currentPhaseKey == "opening" then
            Add(milestones, "Buildpower: 2+ builders", nil, done(buildPowerCount >= 2))
        elseif currentPhaseKey == "t1Bridge" then
            Add(milestones, "Buildpower: 3–4 builders", nil, done(buildPowerCount >= 3))
        elseif currentPhaseKey == "t2" then
            Add(milestones, "Buildpower: 5–7 builders OR 1 CT", nil, done(buildPowerCount >= 5 or constructionTurretCount >= 1))
        elseif currentPhaseKey == "t3" then
            Add(milestones, "Buildpower: 6+ builders OR 2 CT (eco dependent)", nil, done(buildPowerCount >= 6 or constructionTurretCount >= 2))
        end
    end

    -- Milestones (phase-scoped)
    if currentPhaseKey == "opening" then
        Add(milestones,"Get first factory online (Bot Lab)",nil,done(hasT1Factory))
        Add(milestones,"Secure 2–4 mex",nil,done(mexCount >= 2))
        Add(milestones,"Wind online (5+)",nil,done(windCount >= 5))
        AddBuildpowerMilestones()
        Add(milestones,"Next Phase: T1 Bridge","hint")
    elseif currentPhaseKey == "t1Bridge" then
        Add(milestones,"4+ mex secured",nil,done(mexCount >= 4))
        Add(milestones,"Radar coverage (radar building)",nil,done(radarCount >= 1))
        AddBuildpowerMilestones()
        Add(milestones,"Next Phase: Tech Window (T2)","hint")
    elseif currentPhaseKey == "tech" then
        Add(milestones,"T2 Factory started",nil,done(buildingT2Factory or hasT2Factory))
        Add(milestones,"T2 Factory completed",nil,done(hasT2Factory))
        Add(milestones,"Next Phase: T2 Spike","hint")
    elseif currentPhaseKey == "t2" then
        Add(milestones,"T2 Factory",nil,done(hasT2Factory))
        Add(milestones,"T2 Builder (T2 constructor)",nil,done(t2BuilderCount >= 1))
        Add(milestones,"3+ mex upgraded",nil,done(mexUpgradedCount >= 3))
        AddBuildpowerMilestones()
        Add(milestones,"Next Phase: T3 Transition","hint")
    elseif currentPhaseKey == "t3" then
        Add(milestones,"Eco spine: Fusion/AFUS online",nil,done((reactorCount > 0 or afusCount > 0)))
        Add(milestones,"T2 eco stable (no crashing)",nil,done(ePct > 0.2 and mPct > 0.2))
        AddBuildpowerMilestones()
        Add(milestones,"Next Phase: Endgame","hint")
    else
        Add(milestones,"T3 online (if/when built)",nil,done(hasT3Factory))
        Add(milestones,"Spend eco into production",nil,nil)
        Add(milestones,"Next Phase: —","hint")
    end

    local function AllMilestonesDone()
        for _,m in ipairs(milestones) do
            if m.color ~= "hint" and m.status ~= "done" then return false end
        end
        return true
    end

    -- Todo = ASAP (max 6, since we now include readiness-related “blocked by” more often)
    local function AddASAP(text, color)
        if #todo < 6 then Add(todo, text, color) end
    end

    local energySafe    = (ePct > 0.30 or eCur > 4500) and (eNetEMA >= -1)
    local energyDipping = (eNetEMA < -6) or (ePct < 0.18 and eCur < 2500)
    local energyCrash   = (ePct < 0.10 and eCur < 1200) and (eNetEMA < -10)

    local metalLow      = (mPct < 0.35) or (mCur < 220)
    local metalPressure = metalLow or (mNetEMA < -3) or (mNetRaw < -5)

    local energyRich    = (ePct > 0.60) or (eNetEMA > 6) or (eCur > 9000)
    local energyWasted  = (ePct > 0.90) and (eNetEMA > 4)

    -- Readiness lines (with “Why”)
    readinessText, readinessWhyText = "", ""

    if currentPhaseKey == "t1Bridge" or currentPhaseKey == "tech" then
        local score, label, col, why = ReadinessForT2(projectActive)
        if projectActive then
            readinessText = ("T2 Build: IN PROGRESS — %d (%s)"):format(score, label)
        else
            readinessText = ("T2 Readiness: %d — %s"):format(score, label)
        end
        readinessWhyText = why
        readinessColor = col
        readinessWhyColor = {0.8, 0.85, 1, 1}
    elseif currentPhaseKey == "t2" or currentPhaseKey == "t3" then
        local score, label, col, why = ReadinessForT3(projectActive)
        if projectActive and (anyFactoryBuilding or bigSpendBuilding) then
            readinessText = ("T3 Prep: PROJECT ACTIVE — %d (%s)"):format(score, label)
        else
            readinessText = ("T3 Readiness: %d — %s"):format(score, label)
        end
        readinessWhyText = why
        readinessColor = col
        readinessWhyColor = {0.8, 0.85, 1, 1}
    end

    -- Emergency
    if energyCrash then
        AddASAP("Emergency: Energy crashing — stop stacking builds", "block")
        AddASAP("Blocked by: Energy crash (finish power / wind first)", "block")
        return
    end

    -- Metal crash guard during projects (fixes “safe then hard crash”)
    if projectActive and (mPct < 0.12 or mCur < 120 or mNetRaw < -6) then
        AddASAP("CRITICAL: Metal crash during project — stop assisting", "block")
        AddASAP("Fix: convert E→M (slider / converters) or pause queues", "warn")
        -- continue (don’t return), so other useful items can appear too
    end

    -- Eco comfort gate
    local ecoComfort = (ePct > 0.25 or eCur > 3000) and (mPct > 0.20 or mCur > 160) and (eNetEMA > -8)

    -- Idle factories (only if eco is comfortable)
    if ecoComfort and idleFactoryCount > 0 then
        AddASAP(("Idle factory detected (%d) → queue units"):format(idleFactoryCount), "warn")
    end

    -- Slider / conversion / storage guidance (smart preference)
    if energyWasted then
        if (metalPressure or projectActive or currentPhaseKey == "tech" or currentPhaseKey == "t3") then
            if converterCount <= 0 then
                AddASAP("Energy overflowing + metal pressure → build converters", "good")
            else
                AddASAP("Energy overflowing → adjust conversion slider → more Metal", "good")
                if (currentPhaseKey == "t2" or currentPhaseKey == "t3" or currentPhaseKey == "endgame") and t2ConverterCount < 4 then
                    AddASAP("Scale T2 converters (avoid metal choke)", "warn")
                elseif (currentPhaseKey == "t1Bridge") and t1ConverterCount < 2 then
                    AddASAP("Add 1–2 T1 converters (smooth T2 start)", "warn")
                end
            end
        else
            AddASAP("Energy overflowing → build energy storage (stop waste)", "warn")
        end
    end

    if energyDipping and converterCount > 0 then
        AddASAP("Energy dipping → adjust conversion slider → less Metal (save Energy)", "warn")
    end

    -- Buildpower Todo triggers (eco-gated)
    -- Add buildpower when you're clearly floating / upgrades feel slow
    if ecoComfort and not projectActive then
        local floatingMetal = (mPct > 0.60) or (mNetEMA > 2)
        local floatingEnergy = (ePct > 0.70) or (eNetEMA > 6) or (eCur > 12000)

        if (floatingMetal or (floatingEnergy and metalPressure)) then
            if currentPhaseKey == "t1Bridge" and buildPowerCount < 4 then
                AddASAP("Floating eco → add buildpower (1 constructor)", "good")
            elseif (currentPhaseKey == "t2" or currentPhaseKey == "t3") and (constructionTurretCount < 1 and buildPowerCount < 6) then
                AddASAP("Spending slow → build 1 Construction Turret", "good")
            end
        end
    end

    -- Warn about buildpower spike risk when tight (prevents stalls)
    if (buildPowerCount >= 6) and (energyDipping or eNetRaw < -6) then
        AddASAP("Buildpower spike risk → stop assisting / pause extra builders", "warn")
    end

    -- Phase-critical guidance + blocked-by consistency
    if currentPhaseKey == "opening" then
        if not hasT1Factory then AddASAP("Build T1 Bot Lab NOW", "warn") end
        if windCount < 5 then AddASAP("Build Wind (aim 5+)", "warn") end
        if mexCount < 2 then AddASAP("Capture mex (2+)", "warn") end

    elseif currentPhaseKey == "t1Bridge" then
        if mexCount < 4 then AddASAP("Expand: secure 4+ mex", "warn") end
        if radarCount < 1 then AddASAP("Build radar building (awareness)", "warn") end

        -- If metal tight + energy rich, prefer conversion
        if metalLow and energyRich then
            if converterCount == 0 then
                AddASAP("Metal tight + energy rich → build T1 converters", "good")
            else
                AddASAP("Metal tight → adjust conversion slider → more Metal", "good")
            end
        end

        -- Prep guidance if everything is done
        if #todo == 0 and AllMilestonesDone() then
            if not energySafe then
                AddASAP("Prep T2: add power buffer", "prep")
                AddASAP("Blocked by: Energy dipping", "block")
            else
                AddASAP("Prep T2: bank metal (convert if needed)", "prep")
            end
            if buildPowerCount >= 6 and (energyDipping or eNetEMA < -2) then
                AddASAP("Prep T2: stop stacking buildpower (stall risk)", "prep")
            else
                AddASAP("Prep T2: add 1 builder (tempo)", "prep")
            end
        end

    elseif currentPhaseKey == "tech" then
        if not (buildingT2Factory or hasT2Factory) then
            if energySafe and not energyDipping and not metalPressure then
                AddASAP("Start T2 Factory (safe window)", "good")
            else
                AddASAP("Prep T2 Factory", "warn")
                if energyDipping then AddASAP("Blocked by: Energy dipping", "block") end
                if metalPressure then AddASAP("Blocked by: Metal too low (bank/convert)", "block") end
            end
        else
            if metalPressure then
                AddASAP("Protect metal: reduce assisting / convert E→M", "warn")
            end
            if energyDipping then
                AddASAP("Stabilise: pause extra builds to finish T2", "warn")
                AddASAP("Blocked by: Energy dipping", "block")
            else
                AddASAP("Finish T2 clean (avoid hard stall)", "good")
            end
        end

    elseif currentPhaseKey == "t2" then
        if t2BuilderCount < 1 then
            AddASAP("Get a T2 constructor ASAP", "warn")
            AddASAP("Blocked by: Need T2 factory online", (hasT2Factory and "prep" or "block"))
        end
        if mexUpgradedCount < 3 then AddASAP("Upgrade mex (aim 3+)", "warn") end

        if metalPressure and energyRich then
            if t2ConverterCount < 4 then AddASAP("Prep T3: build T2 converters (aim 4+)", "good") end
            if converterCount > 0 then AddASAP("Prep T3: adjust conversion slider → more Metal", "good") end
        end

    elseif currentPhaseKey == "t3" then
        if (reactorCount == 0 and afusCount == 0) then
            if energySafe and not energyDipping and not metalPressure then
                AddASAP("Start Fusion/AFUS (safe window)", "good")
            else
                AddASAP("Prep Fusion/AFUS", "warn")
                if energyDipping then AddASAP("Blocked by: Energy dipping", "block") end
                if metalPressure then AddASAP("Blocked by: Metal too low (convert/bank)", "block") end
            end
        end

        if metalPressure and energyRich and (t2ConverterCount < 6) then
            AddASAP("Scale T2 converters (feed T3 soon)", "good")
        end

    else
        if metalPressure and energyRich then
            AddASAP("Metal tight: add converters before big spends", "warn")
            AddASAP("Adjust conversion slider → more Metal", "good")
        elseif ecoComfort and idleFactoryCount > 0 then
            AddASAP("Endgame: keep factories queued (tempo)", "warn")
        else
            AddASAP("Spend eco into production (avoid floating)", "good")
        end
    end

    -- Prep fallback if Todo empty + on track + milestones done
    local onTrack = (phaseColor[1] > 0.55 and phaseColor[2] > 0.9)
    if (#todo == 0) and onTrack and AllMilestonesDone() then
        local function AddPREP(text)
            if #todo < 3 then Add(todo, "Prep: " .. text, "prep") end
        end

        if currentPhaseKey == "opening" then
            AddPREP("keep wind climbing (buffer for expansion)")
            AddPREP("secure extra mex if safe")
        elseif currentPhaseKey == "t2" then
            AddPREP("prepare T3: converters + mex upgrades + buildpower")
            AddPREP("avoid idle factories (keep tempo)")
        elseif currentPhaseKey == "t3" then
            AddPREP("stabilise eco spine before huge queues")
            AddPREP("scale converters so metal doesn’t choke endgame")
        else
            AddPREP("keep spending — eco idle is lost tempo")
        end
    end
end

--------------------------------------------------------------------------------
-- DRAW (centered + colored arrows + readiness + WHY + lens)
--------------------------------------------------------------------------------

function widget:DrawScreen()
    local vsx,vsy = Spring.GetViewGeometry()
    local cx = vsx * 0.5
    local y = vsy * 0.86
    local line = fontSize * 1.25

    -- Rhythm base line
    local prefix = "Rhythm: " .. ecoLabel .. " — "
    local baseLine = prefix .. "E " .. eArrow .. "  M " .. mArrow

    gl.Color(rhythmColor)
    gl.Text(baseLine, cx, y, fontSize*1.6, "oc")

    -- overlay colored arrows (approx)
    local totalW = gl.GetTextWidth(baseLine) * (fontSize*1.6)
    local xLeft = cx - (totalW * 0.5)
    local wPrefix = gl.GetTextWidth(prefix) * (fontSize*1.6)

    local xE = xLeft + wPrefix + gl.GetTextWidth("E ") * (fontSize*1.6)
    local xM = xLeft + wPrefix + gl.GetTextWidth("E " .. eArrow .. "  M ") * (fontSize*1.6)

    gl.Color(eArrowColor)
    gl.Text(eArrow, xE, y, fontSize*1.6, "o")

    gl.Color(mArrowColor)
    gl.Text(mArrow, xM, y, fontSize*1.6, "o")

    y = y - line*1.2

    -- Phase
    gl.Color(phaseColor[1], phaseColor[2], phaseColor[3], phaseColor[4])
    gl.Text("Phase: "..phaseLabel, cx, y, fontSize*1.15, "oc")
    y = y - line

    -- Readiness
    if readinessText ~= "" then
        gl.Color(readinessColor[1], readinessColor[2], readinessColor[3], readinessColor[4])
        gl.Text(readinessText, cx, y, fontSize*1.05, "oc")
        y = y - line*0.95

        if readinessWhyText ~= "" then
            gl.Color(readinessWhyColor[1], readinessWhyColor[2], readinessWhyColor[3], readinessWhyColor[4])
            gl.Text(readinessWhyText, cx, y, fontSize*0.98, "oc")
            y = y - line
        else
            y = y - line*0.4
        end
    end

    -- Lens line
    if lensText ~= "" then
        gl.Color(lensColor[1], lensColor[2], lensColor[3], lensColor[4])
        gl.Text(lensText, cx, y, fontSize*1.02, "oc")
        y = y - line*1.2
    else
        y = y - line*0.6
    end

    -- Milestones header
    gl.Color(0.75, 0.9, 1, 1)
    gl.Text("Milestones", cx, y, fontSize*1.12, "oc")
    y = y - line

    for _,m in ipairs(milestones) do
        local r,g,b = 1,1,1
        if m.status=="done" then r,g,b = 0.6,1,0.6
        elseif m.color=="hint" then r,g,b = 0.8,0.85,1 end
        gl.Color(r,g,b,1)
        gl.Text((m.status=="done" and "✓ " or "• ")..m.text, cx, y, fontSize*1.02, "oc")
        y = y - line
    end

    y = y - line*0.5

    -- Todo header
    gl.Color(1, 0.9, 0.35, 1)
    gl.Text("Todo (ASAP / Prep)", cx, y, fontSize*1.12, "oc")
    y = y - line

    for _,t in ipairs(todo) do
        local r,g,b = 1,1,1
        if t.color=="good" then r,g,b=0.7,1,0.7
        elseif t.color=="warn" then r,g,b=1,0.8,0.4
        elseif t.color=="block" then r,g,b=1,0.5,0.5
        elseif t.color=="prep" then r,g,b=0.75,0.9,1 end
        gl.Color(r,g,b,1)
        gl.Text("• "..t.text, cx, y, fontSize*1.05, "oc")
        y = y - line
    end
end

--------------------------------------------------------------------------------
-- UPDATE LOOP
--------------------------------------------------------------------------------

function widget:GameFrame(f)
    if f % 30 ~= 0 then return end -- ~1s

    -- projectActive computed from last unit scan; do quick prediction using cached flags too
    local projectActive = buildingT2Factory or anyFactoryBuilding or bigSpendBuilding or bigProjectBuilding

    UpdateEconomy(projectActive)
    UpdateUnits()

    -- recompute with fresh unit scan (more accurate for this tick)
    projectActive = buildingT2Factory or anyFactoryBuilding or bigSpendBuilding or bigProjectBuilding

    UpdatePhase(Spring.GetGameSeconds())
    UpdateRhythm(projectActive)
    UpdateGuidance(projectActive)
end
