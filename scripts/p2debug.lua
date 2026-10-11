-- ============================================================================
-- scripts/p2debug.lua
-- P2 开发入口与可选流程自测。正式剧情与资源加载不依赖本模块中的自测逻辑。
-- ============================================================================

local P2Debug = {}

-- 保留现有开发入口行为；发布前由项目负责人统一关闭。
DEBUG_FORCE_P2_ENTRY = false
DEBUG_P2_TEST = true

-- 按需开启的流程自测开关。
DEBUG_P2_POWER_TEST = false
DEBUG_P2_TERMINAL_TEST = false
DEBUG_P2_CABINET_TEST = false
DEBUG_P2_CLINIC_EXPLORE_TEST = false
DEBUG_P2_CLINIC_EVENT_TEST = false
DEBUG_P2_FINAL_CHOICE_TEST = false
DEBUG_P2_FINAL_RESULT_TEST = false
DEBUG_P2_ENDING_TEST = false

local function IsEnabled(name)
    return rawget(_G, name) == true
end

local function DriveClinicExploration(context)
    context.onClinicClueClicked("power")
    context.restorePower()
    context.onClinicClueClicked("power")
    context.onClinicClueClicked("terminal")
    context.openTerminalFiles()
    context.onClinicClueClicked("cabinet")
    context.openMedicationRecords()
    context.onClinicClueClicked("bed")
    context.onClinicClueClicked("record")
end

local function LogResult(prefix, state)
    print(prefix
        .. " choice=" .. tostring(state.result and state.result.choice)
        .. " leaveNow=" .. tostring(state.flags.leaveNowSelected)
        .. " stayDawn=" .. tostring(state.flags.stayDawnSelected)
        .. " resultReady=" .. tostring(state.flags.resultReady == true))
end

function P2Debug.RunClinicSelfTests(context)
    local p2 = context.getState()
    if not p2 then return end

    if IsEnabled("DEBUG_P2_POWER_TEST") then
        print("[DEBUG P2] power self test START")
        context.onClinicClueClicked("power")
        context.restorePower()
        context.onClinicClueClicked("power")
        print("[DEBUG P2] powerRestored=" .. tostring(p2.flags.powerRestored == true))
    end

    if IsEnabled("DEBUG_P2_TERMINAL_TEST") then
        print("[DEBUG P2] terminal self test START")
        context.onClinicClueClicked("terminal")
        context.restorePower()
        context.onClinicClueClicked("terminal")
        context.openTerminalFiles()
        print("[DEBUG P2] terminalRecordsViewed="
            .. tostring(p2.flags.terminalRecordsViewed == true))
    end

    if IsEnabled("DEBUG_P2_CABINET_TEST") then
        print("[DEBUG P2] cabinet self test START")
        context.onClinicClueClicked("cabinet")
        context.restorePower()
        context.onClinicClueClicked("cabinet")
        context.openMedicationRecords()
        print("[DEBUG P2] medicationsViewed="
            .. tostring(p2.flags.medicationsViewed == true))
    end

    if IsEnabled("DEBUG_P2_CLINIC_EXPLORE_TEST")
        or IsEnabled("DEBUG_P2_CLINIC_EVENT_TEST") then
        print("[DEBUG P2] clinic exploration self test START")
        DriveClinicExploration(context)
        print("[DEBUG P2] clinicExploreComplete="
            .. tostring(p2.flags.clinicExploreComplete == true)
            .. " eventTriggered="
            .. tostring(p2.flags.clinicExploreEventTriggered == true))
    end

    if IsEnabled("DEBUG_P2_FINAL_CHOICE_TEST") then
        print("[DEBUG P2] final choice self test START")
        DriveClinicExploration(context)
        context.prepareFinalChoice()
        context.onFinalChoiceSelected("leave_now")
        LogResult("[DEBUG P2] final choice", p2)
    end

    if IsEnabled("DEBUG_P2_FINAL_RESULT_TEST") then
        print("[DEBUG P2] final result self test START")
        DriveClinicExploration(context)
        context.prepareFinalChoice()
        context.onFinalChoiceSelected("leave_now")
        LogResult("[DEBUG P2] leave_now", p2)

        context.initP2State()
        context.buildClinicScene()
        local nextState = context.getState()
        DriveClinicExploration(context)
        context.prepareFinalChoice()
        context.onFinalChoiceSelected("stay_dawn")
        LogResult("[DEBUG P2] stay_dawn", nextState)
    end

    if IsEnabled("DEBUG_P2_ENDING_TEST") then
        print("[DEBUG P2] ending self test START")
        DriveClinicExploration(context)
        context.prepareFinalChoice()
        context.onFinalChoiceSelected("leave_now")
        context.endP2()
        print("[DEBUG P2] runstateP2Completed="
            .. tostring(context.getRunState().chapters.P2.completed == true))
    end
end

return P2Debug
