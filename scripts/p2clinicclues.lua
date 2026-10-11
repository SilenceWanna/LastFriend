local Story2 = require("story2")
local VoicePlayer = require("voiceplayer")

local P2ClinicClues = {}

local config_ = {}

function P2ClinicClues.Configure(config)
    config_ = config or {}
end

function P2ClinicClues.HandleClueClicked(id, ...)
end

function P2ClinicClues.HandleRestClue(id, clue)
    local p2 = config_.getState()
    P2ClinicClues.PlayRestMinorClue(id, function()
        local cur = (p2 and p2.clinicArea) or "HALL"
        config_.switchScene(cur)
    end)
end

function P2ClinicClues.HandleHearth(...)
end

function P2ClinicClues.HandleTriageRules(clue)
    local p2 = config_.getState()
    if not p2 then return end
    P2ClinicClues.PlayRestMinorClue("triageRules", function()
        p2.flags.recordViewed = true
        local cur = (p2 and p2.clinicArea) or "HALL"
        config_.switchScene(cur)
    end)
end

function P2ClinicClues.HandleNormalClinicClue(id, clue)
    local p2 = config_.getState()
    if not p2 then return end
    local flagKey = id .. "Viewed"
    local viewed = p2.flags[flagKey]
    p2.flags[flagKey] = true
    config_.showDialog(clue.title,
        clue.text .. (viewed and "\n\n（已查看，再次确认）" or ""),
        { { label = "返回诊所", variant = "primary", onClick = config_.closeDialog } })
    config_.checkClinicExploreComplete()
end

function P2ClinicClues.PlayRestMinorClue(id, onComplete)
    local p2 = config_.getState()
    if not p2 then return end
    local clue = Story2.clinic
        and Story2.clinic.restArea
        and Story2.clinic.restArea.minorClues
        and Story2.clinic.restArea.minorClues[id]
    if not clue then
        print("[DEBUG REST CLUE] unknown id=" .. tostring(id))
        if onComplete then onComplete() end
        return
    end
    local flagKey = "rest_" .. id .. "_viewed"
    -- 首次查看计数（重复点击不重复增加）
    config_.registerRestClueViewed(p2, flagKey)

    local dialogue = clue.dialogue or {}
    local idx = 1
    local total = #dialogue
    local function ShowStep()
        local step = dialogue[idx]
        if not step then
            return
        end
        local isLast = idx >= total
        local body
        local useLongDialog = false
        if step.narration then
            -- 环境描述：长文本弹窗，保留 story2.lua 中显式换行
            body = step.narration
            useLongDialog = true
        elseif step.screen then
            -- 屏幕/规章/清单文字：不配音，原样展示，保留显式换行
            body = step.screen
            useLongDialog = true
        elseif step.inner then
            -- 内心对白：普通对话框，同一行显示「我｜内心：台词」
            body = "我｜内心：" .. step.inner
        else
            body = ""
        end
        local buttons = {
            {
                label = "继续",
                variant = "primary",
                onClick = function()
                    if isLast then
                        config_.closeDialog()
                        VoicePlayer.Stop()
                        if onComplete then onComplete() end
                    else
                        idx = idx + 1
                        ShowStep()
                    end
                end,
            },
        }
        -- 逐句配音：显示当前 step 时播放对应配音（内部先 Stop 上一句，防叠音）
        VoicePlayer.PlayStep(step)
        if useLongDialog then
            config_.showRestClueDialog(clue.title or "休息区", body, buttons)
        else
            -- inner 对白使用紧凑弹窗，避免单行文本占据大块空白
            config_.showCompactDialog(clue.title or "休息区", body, buttons)
        end
    end
    ShowStep()
end

function P2ClinicClues.PlayHearthFireFlow()
    local p2 = config_.getState()
    if not p2 then return end
    local ev = Story2.clinic.restEvents and Story2.clinic.restEvents.hearth
    if p2.flags.fireLit == true then
        -- 防重复：已点燃，仅显示简短原文后返回 HEARTH（不新增角色对白）
        config_.showDialog("取暖炉", "取暖炉中的火仍在燃烧。",
            { { label = "返回休息区", variant = "primary", onClick = function()
                config_.closeDialog()
                config_.switchScene("HEARTH")
            end } })
        return
    end
    P2ClinicClues.PlayRestMinorClue("heater", function()
        -- V1.0-07N-P0：炉火成功点燃后记录状态（过程状态 / P3 可继承 / 未来对白条件）。
        p2.flags.fireLit = true
        print("[P2-HEARTH] fire lit=true")
        config_.startDialogue(ev and ev.dialogue or {}, function()
            config_.closeDialog()
            -- 关系值系统存在时 +3（AddXianTrust 为全局函数，缺省安全跳过）
            if config_.addXianTrust then
                config_.addXianTrust(3)
            end
            config_.switchScene("HEARTH")
        end, ev and ev.title or "取暖炉")
    end)
end

function P2ClinicClues.HandleOrganize(clue)
    local ev = Story2.clinic.restEvents and Story2.clinic.restEvents.organize
    local med = Story2.clinic.restEvents and Story2.clinic.restEvents.medication
    local p2 = config_.getState()
    if p2 and p2.flags and p2.flags.organizeDone == true then
        config_.showDialog(ev and ev.title or "整理药盒", ev and ev.doneText or "药盒已经整理好了。", {
            { label = "返回诊所", variant = "primary", onClick = config_.closeDialog },
        })
        return
    end
    config_.showDialog(ev and ev.title or "整理药盒", ev and ev.text or "",
        {
            { label = "继续", variant = "primary", onClick = function()
                config_.closeDialog()
                local p2ctx = config_.getState()
                local recognized = p2ctx and p2ctx.flags and p2ctx.flags.medicationsViewed == true
                local medSteps = (med and (recognized and med.steps or med.stepsUnknown)) or {}
                if medSteps and #medSteps > 0 then
                    config_.startDialogue(medSteps, function()
                        config_.closeDialog()
                        local p2next = config_.getState()
                        local cur = (p2next and p2next.clinicArea) or "HALL"
                        config_.switchScene(cur)
                    end, "弦的药盒")
                else
                    config_.closeDialog()
                    local p2next = config_.getState()
                    local cur = (p2next and p2next.clinicArea) or "HALL"
                    config_.switchScene(cur)
                end
            end },
            { label = "返回诊所", variant = "default", onClick = config_.closeDialog },
        })
end

function P2ClinicClues.HandleXianLocker(clue)
    local p2 = config_.getState()
    local lockerPath = Story2.resources
        and Story2.resources.image
        and Story2.resources.image.locker
        or nil
    config_.showClinicClueImage(lockerPath, clue.title or "弦的旧储物柜", "查看内容", function()
        print("[DEBUG P2-CABINET-FLOW] storage_callback_enter")
        config_.registerRestClueViewed(p2, "rest_xianLocker_viewed")
        local dlg = clue.dialogue or {}
        local askTitle = clue.title or "弦的旧储物柜"
        local function ReturnHearth()
            local cur = (p2 and p2.clinicArea) or "HEARTH"
            config_.switchScene(cur)
        end
        config_.showDialog(askTitle, dlg[1] and dlg[1].narration or "", {
            { label = "继续", variant = "primary", onClick = function()
                config_.closeDialog()
                config_.showDialog(askTitle, "我｜内心：" .. (dlg[2] and dlg[2].inner or ""), {
                    { label = "继续", variant = "primary", onClick = function()
                        config_.closeDialog()
                        local pageButtons
                        if p2.flags.xianLockerAsked ~= true and p2.xianConscious == "SOBER" then
                            pageButtons = {
                                { label = "不询问", variant = "default", onClick = function()
                                    config_.closeDialog()
                                    ReturnHearth()
                                end },
                                { label = "向弦求证", variant = "primary", onClick = function()
                                    config_.closeDialog()
                                    if not p2 or p2.xianConscious ~= "SOBER" then
                                        print("[P2-XIAN] interaction blocked: sedated")
                                        config_.closeDialog()
                                        ReturnHearth()
                                        return
                                    end
                                    config_.startDialogue(
                                        (Story2.xianLockerAsk and Story2.xianLockerAsk.dialogue) or {},
                                        function()
                                            local patienceBefore = p2.patienceRemaining
                                            config_.consumePatience()
                                            local triggered = config_.registerXianQuestion("xian_locker", function()
                                                config_.closeDialog()
                                                ReturnHearth()
                                            end, patienceBefore)
                                            p2.flags.xianLockerAsked = true
                                            if triggered then return end
                                            config_.closeDialog()
                                            ReturnHearth()
                                        end, askTitle)
                                end },
                            }
                        else
                            pageButtons = {
                                { label = "返回", variant = "primary", onClick = function()
                                    config_.closeDialog()
                                    ReturnHearth()
                                end },
                            }
                        end
                        config_.showDialog(askTitle, "我｜内心：" .. (dlg[3] and dlg[3].inner or ""), pageButtons)
                    end },
                })
            end },
        })
        print("[DEBUG P2-CABINET-FLOW] storage_text_dialog_requested")
    end)
end

function P2ClinicClues.HandleBackpack(clue)
    local p2 = config_.getState()
    local bag = Story2.bagEvent or {}
    local title = bag.title or "弦的背包"
    local innerSteps = bag.inner or {}
    local function ReturnHearth()
        local p = config_.getState()
        local cur = (p and p.clinicArea) or "HEARTH"
        config_.switchScene(cur)
    end
    local function ShowLastInnerWithChoice()
        local last = innerSteps[3] or {}
        local firstChoiceButtons
        if p2.flags.bagConfronted ~= true then
            firstChoiceButtons = {
                { label = "不询问", variant = "default", onClick = function()
                    config_.closeDialog()
                    ReturnHearth()
                end },
                { label = "拿漫画质问弦", variant = "primary", onClick = function()
                    config_.closeDialog()
                    local patienceBefore = p2.patienceRemaining
                    local cf = bag.confront or {}
                    local cfSteps = cf.steps or {}
                    local function ShowConfrontLast()
                        local lastConfront = cf.lastStep or {}
                        local function ShowConfrontChoices()
                            config_.showDialog(cf.title or title,
                                (lastConfront.speaker or "") .. "：\n“" .. (lastConfront.text or "") .. "”", {
                                { label = "把漫画还给弦", variant = "default", onClick = function()
                                    config_.closeDialog()
                                    config_.startDialogue(
                                        (Story2.bagEvent and Story2.bagEvent.returnComic and Story2.bagEvent.returnComic.steps) or {},
                                        function()
                                            if config_.addXianTrust then
                                                config_.addXianTrust(-3)
                                            end
                                            p2.flags.bagStarChildKnown = true
                                            p2.flags.bagConfronted = true
                                            config_.closeDialog()
                                            ReturnHearth()
                                        end, title)
                                end },
                                { label = "继续追问", variant = "primary", onClick = function()
                                    config_.closeDialog()
                                    config_.startDialogue(
                                        (Story2.bagEvent and Story2.bagEvent.pressFurther and Story2.bagEvent.pressFurther.steps) or {},
                                        function()
                                            if config_.addXianTrust then
                                                config_.addXianTrust(-6)
                                            end
                                            local furtherPatienceBefore = p2.patienceRemaining
                                            p2.patienceRemaining = math.max(0, p2.patienceRemaining - 2)
                                            p2.patienceRemaining = 0
                                            p2.flags.bagConfronted = true
                                            p2.flags.bagFamilyKnown = true
                                            local triggered = config_.registerXianQuestion("bag_press_further", function()
                                                config_.closeDialog()
                                                ReturnHearth()
                                            end, furtherPatienceBefore)
                                            if triggered then return end
                                            config_.closeDialog()
                                            ReturnHearth()
                                        end, title)
                                end },
                            })
                        end
                        if p2.flags.bagConfrontQuestionRegistered ~= true then
                            config_.consumePatience()
                            p2.flags.bagConfrontQuestionRegistered = true
                            local triggered = config_.registerXianQuestion("bag_confront", function()
                                ShowConfrontChoices()
                            end, patienceBefore)
                            if triggered then return end
                        end
                        ShowConfrontChoices()
                    end
                    config_.startDialogue(cfSteps, ShowConfrontLast, cf.title or title)
                end },
            }
        else
            firstChoiceButtons = {
                { label = "放回原处", variant = "primary", onClick = function()
                    config_.closeDialog()
                    ReturnHearth()
                end },
            }
        end
        config_.showDialog(title, "我｜内心\n" .. (last.inner or ""), firstChoiceButtons)
    end
    config_.showCompactDialog(title, bag.opening or "", {
        { label = "继续", variant = "primary", onClick = function()
            config_.closeDialog()
            local firstTwo = {}
            for i = 1, 2 do
                if innerSteps[i] then firstTwo[#firstTwo + 1] = innerSteps[i] end
            end
            config_.startDialogue(firstTwo, ShowLastInnerWithChoice, title)
        end },
    })
    local bagRoot = config_.getClinicRoot()
    local bagDialog = bagRoot and bagRoot:FindById("dialog")
    local bagBox = bagDialog and bagDialog:FindById("dialogBox")
    if bagBox then
        bagBox:SetStyle({ maxHeight = 380 })
    end
end

return P2ClinicClues
