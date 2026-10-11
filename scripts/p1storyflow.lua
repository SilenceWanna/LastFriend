local P1Content = require("p1content")
local VoicePlayer = require("voiceplayer")

local P1StoryFlow = {}

local deps_ = {}
local openingIndex_ = 1
local openingActive_ = false
local recoveryIndex_ = 1
local recoveryActive_ = false
local core03Index_ = 1
local core03Active_ = false
local exhaustedIndex_ = 1
local exhaustedActive_ = false
local memoryEventIndex_ = 1
local memoryEventCurrentId_ = nil
local memoryEventActive_ = false

function P1StoryFlow.Configure(deps)
    deps_ = deps
end

local function FormatStandardStep(step)
    if step.narration then
        return step.narration
    elseif step.inner then
        return "我｜内心\n" .. step.inner
    end
    return (step.speaker or "") .. "：\n“" .. (step.text or "") .. "”"
end

local function PlayStepSequence(config)
    config.setIndex(1)
    config.setActive(true)

    local total = #config.steps
    local function ShowStep()
        local index = config.getIndex()
        local step = config.steps[index]
        if not step then
            config.setActive(false)
            return
        end

        if config.onStep then
            config.onStep(index, step)
        end

        -- 逐句配音：当前 step 显示前播放对应台词音频（无 ID / 缺资源时静默跳过，不阻断文字流程）
        VoicePlayer.PlayStep(step)

        local isLast = index >= total
        local body = config.formatStep(step)
        config.showDialog(config.title, body, {
            {
                label = isLast and config.lastLabel or config.nextLabel,
                variant = "primary",
                onClick = function()
                    if isLast then
                        config.setActive(false)
                        if config.closeOnFinish then
                            config.closeDialog()
                        end
                        -- 序列结束，停止当前配音
                        VoicePlayer.Stop()
                        if config.onFinished then
                            config.onFinished()
                        end
                    else
                        config.setIndex(index + 1)
                        ShowStep()
                    end
                end,
            },
        })
    end

    ShowStep()
end

function P1StoryFlow.StartOpening(options)
    options = options or {}
    PlayStepSequence {
        steps = P1Content.OpeningDialog,
        getIndex = function()
            return openingIndex_
        end,
        setIndex = function(index)
            openingIndex_ = index
        end,
        setActive = function(active)
            openingActive_ = active
        end,
        showDialog = deps_.showDialog,
        closeDialog = deps_.closeDialog,
        title = options.dialogTitle or "",
        nextLabel = "继续",
        lastLabel = "继续",
        closeOnFinish = true,
        formatStep = FormatStandardStep,
        onFinished = options.onComplete,
    }
end

function P1StoryFlow.PlaySteps(dialogTable, onComplete, dialogTitle)
    PlayStepSequence {
        steps = dialogTable,
        getIndex = function()
            return openingIndex_
        end,
        setIndex = function(index)
            openingIndex_ = index
        end,
        setActive = function(active)
            openingActive_ = active
        end,
        showDialog = deps_.showDialog,
        closeDialog = deps_.closeDialog,
        title = dialogTitle or "",
        nextLabel = "继续",
        lastLabel = "继续",
        closeOnFinish = true,
        formatStep = FormatStandardStep,
        onFinished = onComplete,
    }
end

function P1StoryFlow.PlayRecoveryAssist(options)
    options = options or {}
    PlayStepSequence {
        steps = P1Content.OpeningBDialog,
        getIndex = function()
            return recoveryIndex_
        end,
        setIndex = function(index)
            recoveryIndex_ = index
        end,
        setActive = function(active)
            recoveryActive_ = active
        end,
        showDialog = deps_.showDialog,
        closeDialog = deps_.closeDialog,
        title = options.dialogTitle or "",
        nextLabel = "继续",
        lastLabel = "继续",
        closeOnFinish = true,
        formatStep = FormatStandardStep,
        onFinished = deps_.onRecoveryFinished,
    }
end

function P1StoryFlow.ResetRecoveryAssist()
    recoveryIndex_ = 1
    recoveryActive_ = false
end

function P1StoryFlow.IsRecoveryAssistActive()
    return recoveryActive_
end

function P1StoryFlow.PlayCore03()
    PlayStepSequence {
        steps = P1Content.Core03Steps,
        getIndex = function()
            return core03Index_
        end,
        setIndex = function(index)
            core03Index_ = index
        end,
        setActive = function(active)
            core03Active_ = active
        end,
        showDialog = deps_.showDialog,
        title = "损坏的通讯终端",
        nextLabel = "继续",
        lastLabel = "……",
        closeOnFinish = false,
        formatStep = function(step)
            if step.narration then
                return step.narration
            end
            return step.who .. "：\n" .. step.text
        end,
        onFinished = deps_.onCore03Finished,
    }
end

function P1StoryFlow.ResetCore03()
    core03Index_ = 1
    core03Active_ = false
end

function P1StoryFlow.IsCore03Active()
    return core03Active_
end

function P1StoryFlow.PlayExhausted()
    PlayStepSequence {
        steps = P1Content.ExhaustedSteps,
        getIndex = function()
            return exhaustedIndex_
        end,
        setIndex = function(index)
            exhaustedIndex_ = index
        end,
        setActive = function(active)
            exhaustedActive_ = active
        end,
        showDialog = deps_.showDialog,
        closeDialog = deps_.closeDialog,
        title = "弦",
        nextLabel = "继续",
        lastLabel = "结束对话",
        closeOnFinish = true,
        formatStep = function(step)
            if step.narration then
                return step.narration
            end
            return step.who .. "：\n“" .. step.text .. "”"
        end,
        onStep = function(index)
            print("[DEBUG]")
            print("Exhausted Step")
            print("index=" .. tostring(index))
        end,
        onFinished = function()
            print("[DEBUG]")
            print("Exhausted Finished")
            if deps_.onExhaustedFinished then
                deps_.onExhaustedFinished()
            end
        end,
    }
end

function P1StoryFlow.ResetExhausted()
    exhaustedIndex_ = 1
    exhaustedActive_ = false
end

function P1StoryFlow.IsExhaustedActive()
    return exhaustedActive_
end

function P1StoryFlow.PlayMemoryEvent(memoryId)
    local event = P1Content.MemoryEvents[memoryId]
    if not event then
        print("[DEBUG负面记忆] 未找到 Memory Event id=" .. tostring(memoryId))
        return
    end
    if memoryEventActive_ then
        print("[DEBUG负面记忆] Memory Event 播放中，忽略重复调用 id=" .. tostring(memoryId))
        return
    end

    memoryEventCurrentId_ = memoryId
    PlayStepSequence {
        steps = event.steps,
        getIndex = function()
            return memoryEventIndex_
        end,
        setIndex = function(index)
            memoryEventIndex_ = index
        end,
        setActive = function(active)
            memoryEventActive_ = active
        end,
        showDialog = deps_.showDialog,
        closeDialog = deps_.closeDialog,
        title = "记忆",
        nextLabel = "继续",
        lastLabel = "结束记忆",
        closeOnFinish = true,
        formatStep = FormatStandardStep,
        onStep = function(index)
            print("[DEBUG]")
            print("Memory Step")
            print("index=" .. tostring(index))
        end,
        onFinished = function()
            print("[DEBUG]")
            print("Memory Finished")
            if deps_.onMemoryEventFinished then
                deps_.onMemoryEventFinished(memoryEventCurrentId_)
            end
        end,
    }
end

function P1StoryFlow.ResetMemoryEvent()
    memoryEventIndex_ = 1
    memoryEventCurrentId_ = nil
    memoryEventActive_ = false
end

function P1StoryFlow.IsMemoryEventActive()
    return memoryEventActive_
end

function P1StoryFlow.ResetOpening()
    openingIndex_ = 1
    openingActive_ = false
end

function P1StoryFlow.IsOpeningActive()
    return openingActive_
end

return P1StoryFlow
