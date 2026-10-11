local P1AskController = {}

local deps_ = {}

function P1AskController.Configure(deps)
    deps_ = deps
end

function P1AskController.HandleAskClicked(id)
    local state = deps_.getAskState(id)
    if state.isSilent then
        return
    end
    if state.isAsked then
        return
    end

    print("[DEBUG询问]")
    print("id=" .. tostring(id))
    print("asked=" .. tostring(state.isAsked))
    print("xian_patience=" .. tostring(state.xianPatience))
    print("pending=" .. tostring(state.negativeMemoryPending))
    print("ready=" .. tostring(state.negativeMemoryReady))
    print("triggered=" .. tostring(state.negativeMemoryTriggered))

    local isCoreClue = deps_.isCoreClue(id)

    if isCoreClue
        and state.negativeMemoryPending
        and not state.negativeMemoryTriggered then
        print("[DEBUG]")
        print("进入 pending 分支")
        print("[DEBUG负面记忆] 统一耗尽对话播放中，忽略重复询问 id=" .. tostring(id))
        return
    end

    if isCoreClue
        and state.negativeMemoryReady
        and not state.negativeMemoryTriggered then
        print("[DEBUG负面记忆] 检测到异常 ready 状态，自动补触发 Memory Event")
        deps_.clearNegativeMemoryReady()
        deps_.triggerMemoryEvent("P1_NEGATIVE_001")
        return
    end

    if isCoreClue
        and state.negativeMemoryTriggered then
        print("[DEBUG负面记忆] Memory Event 已触发，忽略重复询问 id=" .. tostring(id))
        return
    end

    if isCoreClue
        and state.xianPatience <= 0
        and not state.negativeMemoryTriggered
        and not state.negativeMemoryPending
        and not state.negativeMemoryReady then
        print("[DEBUG]")
        print("进入 exhausted 分支")
        deps_.beginPatienceExhausted(id)
        return
    end

    if state.responseRemaining > 0 then
        if id == "terminal" then
            deps_.playCore03()
            return
        end
        deps_.playCoreDialogue(id)
        return
    end

    deps_.triggerFourthAsk()
end

return P1AskController
