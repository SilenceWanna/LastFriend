local UI = require("urhox-libs/UI")
local P1Content = require("p1content")
local Story2 = require("story2")
local VoicePlayer = require("voiceplayer")

local P3Evidence = {}
local config = {}
---@type Widget|nil
local layer_ = nil
local cardWidgets_ = {}
local allCompleteReported_ = false
local playing_ = false
local endingRetryPending_ = false

local identityBandSteps_ = {
    P1Content.OpeningDialog[9],
    P1Content.OpeningDialog[10],
    P1Content.OpeningDialog[11],
    P1Content.OpeningDialog[12],
    P1Content.OpeningDialog[13],
    P1Content.OpeningBDialog[2],
}

local memorySteps_ = {
    sharedPast = Story2.memory01 and Story2.memory01.steps or {},
    identityBand = identityBandSteps_,
    sleepExecution = {
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[1],
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[4],
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[5],
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[6],
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[7],
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[8],
        P1Content.MemoryEvents.P1_NEGATIVE_001.steps[9],
    },
}

local cards_ = {
    { id = "sharedPast", title = "共同经历" },
    { id = "identityBand", title = "身份遗留" },
    { id = "sleepExecution", title = "休眠执行" },
}

function P3Evidence.Configure(newConfig)
    config = newConfig
end

local function GetState()
    return config.getState and config.getState()
end

local function HasInheritedIdentityBracelet()
    local state = GetState()
    return state and state.inherited and state.inherited.identity_bracelet == true
end

local function IsCardAvailable(id)
    return id ~= "identityBand" or HasInheritedIdentityBracelet()
end

local function CanOpen()
    local state = GetState()
    if not state or not state.keys or not state.flags then return false end
    if state.flags.evidenceOpened == true then return false end
    if state.phase ~= "FREE" then return false end
    if state.keys.photo ~= true or state.keys.terminal ~= true then
        return false
    end
    if HasInheritedIdentityBracelet() and state.keys.band ~= true then
        return false
    end
    if config.isInteractionAvailable and not config.isInteractionAvailable() then
        return false
    end
    return true
end

local function IsMemoryComplete(id)
    local state = GetState()
    return state and state.memories and state.memories[id] == true
end

local function AllMemoriesComplete()
    local complete = IsMemoryComplete("sharedPast")
        and IsMemoryComplete("sleepExecution")
    if HasInheritedIdentityBracelet() then
        complete = complete and IsMemoryComplete("identityBand")
    end
    return complete
end

local function TryStartEnding()
    local state = GetState()
    local allComplete = AllMemoriesComplete()
    local result = allComplete and not playing_
        and state ~= nil and state.flags ~= nil
        and state.flags.endingStarted ~= true
        and config.startEnding ~= nil
    print("[P3 DEBUG] TryEnding"
        .. " sharedPast=" .. tostring(state and state.memories and state.memories.sharedPast)
        .. " identityBand=" .. tostring(state and state.memories and state.memories.identityBand)
        .. " sleepExecution=" .. tostring(state and state.memories and state.memories.sleepExecution)
        .. " playing=" .. tostring(playing_)
        .. " endingStarted=" .. tostring(state and state.flags and state.flags.endingStarted)
        .. " result=" .. tostring(result))
    if not allComplete or playing_ then return end
    if not state or not state.flags or state.flags.endingStarted == true then return end
    if config.startEnding then
        config.startEnding()
    end
end

local function RetryEndingNextFrame()
    if endingRetryPending_ then return end
    endingRetryPending_ = true
    if config.retryEndingNextFrame then
        config.retryEndingNextFrame(function()
            endingRetryPending_ = false
            TryStartEnding()
        end)
    else
        endingRetryPending_ = false
    end
end

local function RefreshCards()
    for i = 1, #cards_ do
        local card = cards_[i]
        local widget = cardWidgets_[card.id]
        if widget then
            local completed = IsMemoryComplete(card.id)
            local stateLabel = widget:FindById("p3EvidenceState_" .. card.id)
            if stateLabel then
                stateLabel:SetText(completed and "已完成" or "待整理")
            end
            widget:SetStyle({
                opacity = completed and 0.58 or 1,
                borderColor = completed
                    and { 100, 145, 170, 150 }
                    or { 120, 225, 255, 220 },
                backgroundColor = completed
                    and { 50, 75, 95, 80 }
                    or { 30, 100, 140, 150 },
            })
        end
    end
end

local function CompleteMemory(id)
    local state = GetState()
    if not state or not state.memories or state.memories[id] == true then
        return
    end
    state.memories[id] = true
    print("[P3] evidence memory complete: " .. tostring(id))
    if id == "identityBand" then
        state.bandLog = "疑似弦的身份手环"
    end
    RefreshCards()
    print("[P3 DEBUG] MEMORY"
        .. " sharedPast=" .. tostring(state and state.memories and state.memories.sharedPast)
        .. " identityBand=" .. tostring(state and state.memories and state.memories.identityBand)
        .. " sleepExecution=" .. tostring(state and state.memories and state.memories.sleepExecution)
        .. " endingStarted=" .. tostring(state and state.flags and state.flags.endingStarted))
    if AllMemoriesComplete() and not allCompleteReported_ then
        allCompleteReported_ = true
        print("[P3] all evidence memories complete")
        TryStartEnding()
        RetryEndingNextFrame()
    end
end

local function FormatStep(step)
    if step.narration then return step.narration end
    if step.inner then return "我｜内心：\n" .. step.inner end
    local speaker = step.speaker or step.who or ""
    return speaker .. "：\n“" .. (step.text or "") .. "”"
end

local function PlayMemorySteps(id, index)
    local steps = memorySteps_[id] or {}
    if index > #steps then
        playing_ = false
        VoicePlayer.Stop()
        P3Evidence.Hide()
        CompleteMemory(id)
        local state = GetState()
        if layer_ and state and state.phase ~= "ENDING" then
            layer_:SetVisible(true)
        end
        return
    end
    if not config.showDialog then
        playing_ = false
        VoicePlayer.Stop()
        CompleteMemory(id)
        return
    end
    -- 逐句配音：显示当前 step 时播放对应配音
    VoicePlayer.PlayStep(steps[index])
    config.showDialog("记忆", FormatStep(steps[index]), function()
        PlayMemorySteps(id, index + 1)
    end, false)
end

local function StartMemory(id)
    if playing_ or IsMemoryComplete(id) then return end
    playing_ = true
    P3Evidence.Hide()
    PlayMemorySteps(id, 1)
end

local function CreateCard(card)
    local completed = IsMemoryComplete(card.id)
    local widget = UI.Button {
        id = "p3EvidenceCard_" .. card.id,
        text = "",
        width = 220,
        height = 92,
        variant = "default",
        backgroundColor = completed and { 50, 75, 95, 80 } or { 30, 100, 140, 150 },
        borderWidth = 1,
        borderColor = completed and { 100, 145, 170, 150 } or { 120, 225, 255, 220 },
        borderRadius = 8,
        onClick = function()
            StartMemory(card.id)
        end,
        children = {
            UI.Label {
                text = card.title,
                fontSize = 18,
                fontColor = { 220, 235, 250, 255 },
                width = "100%",
                textAlign = "center",
                pointerEvents = "none",
            },
            UI.Label {
                id = "p3EvidenceState_" .. card.id,
                text = completed and "已完成" or "待整理",
                fontSize = 11,
                fontColor = completed and { 145, 170, 190, 220 } or { 135, 210, 235, 220 },
                width = "100%",
                textAlign = "center",
                marginTop = 8,
                pointerEvents = "none",
            },
        },
    }
    cardWidgets_[card.id] = widget
    return widget
end

function P3Evidence.Build()
    cardWidgets_ = {}
    allCompleteReported_ = false
    local cardChildren = {}
    for i = 1, #cards_ do
        if IsCardAvailable(cards_[i].id) then
            cardChildren[#cardChildren + 1] = CreateCard(cards_[i])
        end
    end
    layer_ = UI.Panel {
        id = "p3EvidenceLayer",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 5, 8, 14, 220 },
        pointerEvents = "auto",
        visible = false,
        children = {
            UI.Panel {
                id = "p3EvidencePanel",
                width = "78%",
                maxWidth = 760,
                padding = 28,
                gap = 18,
                backgroundColor = { 16, 23, 36, 250 },
                borderWidth = 1,
                borderColor = { 110, 200, 255, 180 },
                borderRadius = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "证据整理",
                        fontSize = 24,
                        fontColor = { 235, 242, 255, 255 },
                        textAlign = "center",
                        width = "100%",
                    },
                    UI.Label {
                        text = HasInheritedIdentityBracelet()
                            and "整理已获得的三张证据卡"
                            or "整理已获得的两张证据卡",
                        fontSize = 13,
                        fontColor = { 145, 175, 205, 220 },
                        textAlign = "center",
                        width = "100%",
                    },
                    UI.Panel {
                        id = "p3EvidenceCards",
                        width = "100%",
                        flexDirection = "column",
                        alignItems = "center",
                        gap = 12,
                        children = cardChildren,
                    },
                },
            },
        },
    }
    return layer_
end

function P3Evidence.TryOpen()
    local state = GetState()
    local interactionAvailable = config.isInteractionAvailable and config.isInteractionAvailable() or true
    local result = CanOpen()
    print("[P3 DEBUG] TryOpen"
        .. " photo=" .. tostring(state and state.keys and state.keys.photo)
        .. " band=" .. tostring(state and state.keys and state.keys.band)
        .. " terminal=" .. tostring(state and state.keys and state.keys.terminal)
        .. " phase=" .. tostring(state and state.phase)
        .. " interactionAvailable=" .. tostring(interactionAvailable)
        .. " evidenceOpened=" .. tostring(state and state.flags and state.flags.evidenceOpened)
        .. " result=" .. tostring(result))
    if not result then return false end
    state.flags.evidenceOpened = true
    state.phase = "EVIDENCE"
    print("[P3] evidence opened")
    if layer_ then
        RefreshCards()
        layer_:SetVisible(true)
    end
    return true
end

function P3Evidence.IsOpen()
    return layer_ ~= nil and layer_:IsVisible()
end

function P3Evidence.Hide()
    if layer_ then
        layer_:SetVisible(false)
    end
end

function P3Evidence.Reset()
    if layer_ then
        layer_:SetVisible(false)
    end
    layer_ = nil
    cardWidgets_ = {}
    allCompleteReported_ = false
    playing_ = false
    endingRetryPending_ = false
end

return P3Evidence
