-- ============================================================================
-- scripts/p2controller.lua
-- 《零点之后》第二关「雪线诊所」P2 剧情控制器
--
-- 职责：统一编排 P2 的隧道、诊所、最终抉择与结算流程，
--       具体交互委托给场景、终端、药柜等功能模块。
--       会话态统一通过 P2Context.Get() 取得。
-- ============================================================================

local P2Controller = {}
local config = {}

function P2Controller.Configure(newConfig)
    config = newConfig
end

local Story2 = require("story2")
local P2Context = require("p2context")
local UI = require("urhox-libs/UI")
local BGMPlayer = require("bgmplayer")
local RunState = require("runstate")
local P2State = require("p2state")
local P2Debug = require("p2debug")
local P2Cabinet = require("p2cabinet")
local VoicePlayer = require("voiceplayer")
local P2Terminal = require("p2terminal")
local P2ClinicClues = require("p2clinicclues")
local P2FinalFlow = require("p2finalflow")
local P2SceneUI = require("p2sceneui")
local ScanFX = require("scanfx")
local ScanStatus = require("scanstatus")
-- (V1.0-04E-C2) p2controller 现已承载 BuildP2Scene 等 P2 场景/UI 工厂全局函数。

-- 模块级 P2 UI 根（隧道 / 诊所场景）。声明于此，确保 BuildP2Scene 及其之后的
-- RefreshP2EnterClinicButton 等函数都引用同一个局部变量（避免被更早定义的函数
-- 当作 nil 全局变量解析，导致 FindById 找不到按钮）。
local p2Root_ = nil
-- 与 p2Root_ 同理：p2ClinicRoot_ 在文件下方（BuildP2ClinicScene 中）赋值，
-- 但诊所模块通过配置回调读取它；提升到模块级声明，确保药柜密码窗使用当前活动根。
local p2ClinicRoot_ = nil
---@type function|nil
local OpenP2DialogueRecords = nil
---@type function
local OpenP2ClinicTerminalFiles
---@type boolean
local p2ScanMode_ = false
---@type table
local p2ScanHotspots_ = {}
---@type function
local ResetP2ScanState

-- ----------------------------------------------------------------------------
-- 隧道批次（V1.0-04D-B1 迁移自 main.lua，函数名/参数/逻辑/print 文本/Story2 调用/
-- Dialog 调用保持原样；仅把 GetP2() 改为 P2Context.Get()）
-- 注意：以下函数定义为全局（与 main 中原有全局函数一致），以便 EnterP2 / 按钮回调
-- 以裸名方式继续调用，无需改动任何调用点。
-- ----------------------------------------------------------------------------

-- P2 已播放对话记录：只登记正式的 speaker/text 台词，不登记旁白、inner、系统提示、线索说明或按钮文字。
-- 每次连续对白播放对应一个片段；片段内部保存多句台词，dialogRecordIds 负责逐句去重。
local function BuildP2DialogueSegmentId(steps, sourceId)
    if sourceId then
        return tostring(sourceId)
    end
    local parts = {}
    for i = 1, #steps do
        local step = steps[i]
        parts[#parts + 1] = table.concat({
            tostring(step.speaker or ""),
            tostring(step.text or ""),
            tostring(step.narration or ""),
            tostring(step.inner or ""),
        }, "\n")
    end
    return "p2_segment:" .. table.concat(parts, "\n|\n")
end

local function AppendP2DialogueRecord(step, dialogueId, segmentId)
    local p2 = P2Context.Get()
    if not p2 or not step or not step.speaker or not step.text
        or step.speaker == "系统广播" then
        return
    end
    p2.dialogRecords = p2.dialogRecords or {}
    p2.dialogRecordIds = p2.dialogRecordIds or {}

    local recordId = dialogueId
        or (step.audioIds and step.audioIds[1])
        or (tostring(step.speaker) .. "\n" .. tostring(step.text))
    local blockId = segmentId or recordId
    if not p2.dialogRecordIds[recordId] then
        local record
        for i = 1, #p2.dialogRecords do
            if p2.dialogRecords[i].id == blockId then
                record = p2.dialogRecords[i]
                break
            end
        end
        if not record then
            record = { id = blockId, lines = {} }
            p2.dialogRecords[#p2.dialogRecords + 1] = record
        end
        record.lines[#record.lines + 1] = {
            id = recordId,
            speaker = step.speaker,
            text = step.text,
        }
        p2.dialogRecordIds[recordId] = true
    end
end

-- P2 统一逐页对白播放器；仅在实际显示页面时记录 speaker/text 台词。
local function StartP2Dialogue(steps, onComplete, dialogTitle, sourceId)
    local index = 1
    local total = #steps
    local segmentId = BuildP2DialogueSegmentId(steps, sourceId)
    local function ShowStep()
        local step = steps[index]
        if not step then return end
        local body
        if step.narration then
            body = step.narration
        elseif step.inner then
            body = "我｜内心：" .. step.inner
        else
            body = step.speaker .. "：\n“" .. step.text .. "”"
        end
        -- 逐句配音：显示当前 step 时播放对应配音（VoicePlayer 内部先 Stop 上一句，防叠音）
        VoicePlayer.PlayStep(step)
        ShowDialog(dialogTitle or "", body, {
            {
                label = "继续",
                variant = "primary",
                onClick = function()
                    if index >= total then
                        CloseDialog()
                        -- 结束：停止当前配音，避免残留
                        VoicePlayer.Stop()
                        if onComplete then onComplete() end
                    else
                        index = index + 1
                        ShowStep()
                    end
                end,
            },
        })
        if step.speaker and step.text then
            local lineId = (step.audioIds and step.audioIds[1])
                or (segmentId .. ":" .. tostring(index))
            AppendP2DialogueRecord(step, lineId, segmentId)
        end
    end
    if total == 0 then
        if onComplete then onComplete() end
    else
        ShowStep()
    end
end

function PlayP2Opening()
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] PlayP2Opening: p2State_ not initialized")
        return
    end
    print("[DEBUG P2] >>> PlayP2Opening() phase=" .. tostring(p2.phase)
          .. " trust=" .. tostring(p2.initialTrust))
    -- 复用 P1 已验证的连续对白播放器（StartOpeningDialogue 零修改）
    -- 对白数据驱动自 Story2.openingDialog（结构与 P1_OPENING_DIALOG 100% 对齐）
    -- 末句 onComplete：开场对白结束 → 进入扶住微选择（SCENE01 完整事件）
    -- 隧道阶段对白：标题用「隧道」（不污染 P1 的「废弃休眠区」默认标题）
    StartP2Dialogue(Story2.openingDialog, function()
        CloseDialog()
        ShowP2SupportChoice()
    end, "隧道")
end

-- ----------------------------------------------------------------------------
-- P2 SCENE01 微选择：接受弦扶住 / 推开弦
-- 按钮样式与 P1 Recovery A/B/C/D 完全一致（variant = "default"）。
-- 两分支最终都汇入 ContinueP2OpeningAfterSupport()（播放 postMemoryDialog：……弦。段 → 自由调查）。
-- 区别：接受帮助先经 Memory01 + 回到现实(returnDialog)；推开弦跳过 Memory01 与回到现实，直接汇入。
-- ----------------------------------------------------------------------------
function ShowP2SupportChoice()
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] ShowP2SupportChoice: P2 state not found")
        return
    end
    ShowDialog("隧道", "弦扶住了你。", {
        {
            label = "A：接受弦扶住",
            variant = "default",
            onClick = function()
                print("[DEBUG HELP CHOICE] acceptHelp")
                p2.flags.acceptHelp = true
                CloseDialog()
                -- A 路线：关系值 +2，播放"弦扶住了我"旁白后进入 Memory01（含记忆画面）
                if type(AddXianTrust) == "function" then
                    AddXianTrust(2)
                end
                StartP2Dialogue(Story2.supportAcceptDialog, function()
                    CloseDialog()
                    print("[DEBUG HELP CONTINUE] acceptHelp=true nextFunction=PlayP2Memory01")
                    PlayP2Memory01()
                end, "隧道")
            end,
        },
        {
            label = "B：推开弦",
            variant = "default",
            onClick = function()
                print("[DEBUG HELP CHOICE] pushAway")
                p2.flags.acceptHelp = false
                CloseDialog()
                -- B 路线：播放"我自己能走"对白，关系值 -3，
                -- 跳过记忆画面，直接进入记忆之后的开头流程（返回现实 → postMemoryDialog → 自由调查）。
                if type(AddXianTrust) == "function" then
                    AddXianTrust(-3)
                end
                StartP2Dialogue(Story2.supportRejectDialog, function()
                    CloseDialog()
                    print("[DEBUG HELP CONTINUE] acceptHelp=false nextFunction=PlayP2Memory01 (shared MEMORY 01)")
                    PlayP2Memory01()
                end, "隧道")
            end,
        },
    })
end

-- ----------------------------------------------------------------------------
-- P2 MEMORY 01 播放器（V1.0 P2 第五批；本批参数化）
-- 数据格式与 P1 MemoryEvents[id].steps 完全一致（speaker/text 或 narration 单步）。
-- 不复制 TriggerMemoryEvent、不修改 P1 Memory 系统；仅在此复用同格式播放，末步回退现实。
-- 参数化（本批新增，向后兼容）：
--   PlayP2Memory01()                            → 与原行为 100% 一致（Memory01 固定 steps + 默认返回逻辑）
--   PlayP2Memory01(customSteps, onComplete)     → 播放自定义 steps；仅替换最终完成回调
--   · customSteps 缺省 → 仍使用 Story2.memory01.steps（文本/顺序/演出不变）
--   · onComplete  缺省 → 仍执行原完成逻辑（CloseDialog → PlayP2ReturnDialogue → postMemoryDialog）
--   · 自定义 steps 使用同一套记忆视觉（ShowDialog("记忆", …)），不新增全局记忆状态
-- ----------------------------------------------------------------------------
function PlayP2Memory01(customSteps, onComplete)
    local p2 = P2Context.Get()
    -- steps：优先自定义，缺省回落到原 Memory01 固定数据
    local steps = customSteps or ((Story2.memory01 and Story2.memory01.steps) or {})
    -- finish：默认完成回调 = 原有「返回现实」链路；自定义回调完全替换之
    local finish = onComplete or function()
        PlayP2ReturnDialogue()
    end
    local idx = 1
    local total = #steps
    local segmentId = customSteps
        and BuildP2DialogueSegmentId(steps, nil)
        or "memory01"
    if total == 0 then
        finish()
        return
    end
    local function ShowStep()
        local step = steps[idx]
        if not step then return end
        local isLast = idx >= total
        local body
        if step.narration then
            body = step.narration
        else
            body = (step.speaker or "") .. "：\n“" .. (step.text or "") .. "”"
        end
        if step.speaker and step.text then
            local lineId = step.audioIds and step.audioIds[1]
                or (segmentId .. ":" .. tostring(idx))
            AppendP2DialogueRecord(step, lineId, segmentId)
        end
        -- 逐句配音：显示当前 step 时播放对应配音（内部先 Stop 上一句，防叠音）
        VoicePlayer.PlayStep(step)
        ShowDialog("记忆", body, {
            {
                label = isLast and "返回现实" or "继续",
                variant = "primary",
                onClick = function()
                    if isLast then
                        CloseDialog()
                        VoicePlayer.Stop()
                        finish()
                    else
                        idx = idx + 1
                        ShowStep()
                    end
                end,
            },
        })
        -- MEMORY 02B 长文本页局部增高（本批）：仅自定义 steps 生效，Memory01 默认播放不受影响；
        -- 仿药柜/背包先例，仅抬高当前实例 dialogBox maxHeight，不改全局 ShowDialog 默认样式。
        if customSteps then
            local memRoot = p2ClinicRoot_ or p2Root_
            local memDlg = memRoot and memRoot:FindById("dialog")
            local memBox = memDlg and memDlg:FindById("dialogBox")
            if memBox then
                memBox:SetStyle({ maxHeight = 380 })
            end
        end
    end
    ShowStep()
end

-- ----------------------------------------------------------------------------
-- P2 返回现实对白：播放 Story2.returnDialog，结束后接入 postMemoryDialog。
-- ----------------------------------------------------------------------------
-- P2 返回现实桥接 + 后续同行对白汇合点
-- ContinueP2OpeningAfterSupport：播放 postMemoryDialog（……弦。段，含 P2-S01-ZERO-001/XIAN-001/002），
-- 结束后进入自由调查。两分支（接受帮助/推开弦）均先汇入同一个 Memory01，再经过返回现实和此处汇合。
-- PlayP2Memory01 默认完成回调会播放 returnDialog，然后继续到本函数。
function ContinueP2OpeningAfterSupport()
    StartP2Dialogue(Story2.postMemoryDialog, function()
        CloseDialog()
        FinishP2Opening()
    end, "隧道")
end

-- P2 返回现实对白：播放 Story2.returnDialog（回到现实桥接），结束后接入 postMemoryDialog。
function PlayP2ReturnDialogue()
    StartP2Dialogue(Story2.returnDialog, function()
        CloseDialog()
        ContinueP2OpeningAfterSupport()
    end, "隧道")
end

-- ----------------------------------------------------------------------------
-- P2 SCENE01 收尾：结束 Opening，开启第二关自由调查。
-- 本批仅做流程收口，不放剧情 / 对白 / Memory / Timer；
-- 后续 HUD、系统提示、章节标题等统一在此扩展。
-- ----------------------------------------------------------------------------
function FinishP2Opening()
    print("[DEBUG P2] >>> FinishP2Opening() 开启第二关自由调查")
    -- 隧道自由调查由 PlayP2Tunnel() 的 tunnelExplorationStarted=true 驱动，
    -- 不再在此播放 scene02Dialog，也不再自动调用 EnterP2Clinic()。
    -- 玩家停留在隧道自由调查，待双条件达成播放暴风雪广播、解锁「进入诊所」后主动点击进入。
    CloseDialog()
end

-- ----------------------------------------------------------------------------
-- P2 调查开始系统提示（V1.0 P2 第十批）
-- 系统 UI：标题"系统"，正文提示调查开始与暴风雪封锁剩余时间；按钮"开始调查"。
-- 不写对白、不播放剧情；点击后进入调查入口。倒计时本批不实现。
-- ----------------------------------------------------------------------------
function ShowP2InvestigationStart()
    ShowDialog("系统", "诊所调查开始。\n暴风雪封锁剩余时间：\n03:00", {
        {
            label = "开始调查",
            variant = "primary",
            onClick = function()
                CloseDialog()
                StartP2Investigation()
            end,
        },
    })
end

-- ----------------------------------------------------------------------------
-- P2 自由调查入口（V1.0 P2 第六批统一）
-- 启动诊所调查 180 秒倒计时（P2 独立状态，复用 P2Context.Get()）。
-- 防重复：已启动则不重置剩余时间，只保证 Update 已订阅。
-- ----------------------------------------------------------------------------
---@type integer
local p2LastDisplayedSecs_ = -1

function StartP2Investigation()
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] StartP2Investigation: P2 state not found")
        return
    end
    -- 防"Timer 诈尸"：仅在「尚未开始 且 尚未归零 且 第一阶段未结束」时启动 180 秒。
    -- 归零后 clinicTimerStarted=false，但 clinicTimeUpHandled/clinicPhaseOneComplete 仍为 true，
    -- 故不会错误重置回 180。
    if (not p2.clinicTimerStarted)
       and (p2.clinicTimeUpHandled ~= true)
       and (p2.clinicPhaseOneComplete ~= true) then
        p2.clinicTimeRemaining = 180
        p2.clinicTimerStarted = true
        p2.clinicTimeUpHandled = false
        p2LastDisplayedSecs_ = -1
        -- V1.0 P2 新批次B：倒计时标签仅在「诊所调查阶段」显示。
        -- StartP2Investigation 在隧道阶段被调用（点击"开始调查"时 phase 仍为 TUNNEL），
        -- 此处不在此显示标签，避免隧道误显；标签可见性统一由 RefreshP2Investigation 控管。
        print("[P2 Timer] Started 180s")
    end
    CreateP2Investigation()
end

-- P2 倒计时显示刷新（仅在整秒变化时更新文本，避免每帧重设）
local function FormatP2Countdown(secs)
    secs = math.max(0, math.ceil(secs))
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%02d:%02d", m, s)
end

local function RefreshP2CountdownLabel(secs)
    local shown = math.ceil(secs)
    if shown == p2LastDisplayedSecs_ then return end
    p2LastDisplayedSecs_ = shown
    local root = UI.GetRoot()
    local label = root and root:FindById("p2CountdownLabel")
    if label then
        label:SetText(FormatP2Countdown(secs))
    end
end

-- 隧道分支每秒节流打印用累加器（仅 DEBUG）
---@type number
local p2DebugUpdateAccum_ = 0

local P2_DEBUG_STATUS_PANEL = false

-- TEMP DEBUG：P2 实时状态面板（发布前删除或将开关设为 false）
local function CreateP2DebugStatusPanel()
    return UI.Panel {
        id = "p2DebugStatusPanel",
        width = 180, height = 72,
        position = "absolute", top = 50, right = 16,
        padding = 8,
        backgroundColor = { 12, 16, 24, 210 },
        borderWidth = 1, borderColor = { 100, 120, 150, 180 }, borderRadius = 6,
        pointerEvents = "box-none",
        children = {
            UI.Label {
                id = "p2DebugStatusTitle",
                text = "TEMP DEBUG",
                width = "100%", height = 20,
                fontSize = 12,
                fontColor = { 180, 210, 255, 255 },
            },
            UI.Label {
                id = "p2DebugTrustLabel",
                text = "弦好感：-",
                width = "100%", height = 20,
                fontSize = 12,
                fontColor = { 235, 235, 245, 255 },
            },
            UI.Label {
                id = "p2DebugPatienceLabel",
                text = "弦耐心：-",
                width = "100%", height = 20,
                fontSize = 12,
                fontColor = { 235, 235, 245, 255 },
            },
        },
    }
end

local function UpdateP2DebugPanel()
    if not P2_DEBUG_STATUS_PANEL then return end
    local p2 = P2Context.Get()
    if not p2 then return end
    local root = UI.GetRoot()
    local trustLabel = root and root:FindById("p2DebugTrustLabel")
    local patienceLabel = root and root:FindById("p2DebugPatienceLabel")
    if trustLabel then
        trustLabel:SetText("弦好感：" .. tostring(GetXianTrust()))
    end
    if patienceLabel then
        patienceLabel:SetText("弦耐心：" .. tostring(p2.patienceRemaining))
    end
end

-- P2 更新驱动（V1.0 P2 第十一批）：仅订阅一次，递减诊所倒计时。
-- 不修改 P1 HandleUpdate；Dialog 打开时暂停扣时。
---@param eventType string
---@param eventData UpdateEventData
function HandleP2Update(eventType, eventData)
    local p2 = P2Context.Get()
    if not p2 then return end
    UpdateP2DebugPanel()

    -- V1.0 P2 新批次：隧道自由调查双条件计时（与诊所 03:00 Timer 完全独立）。
    -- 仅在隧道阶段、未解锁诊所、广播尚未触发时累计时间；触发后不再计时。
    if p2.phase == "TUNNEL"
       and p2.tunnelExplorationStarted == true
       and p2.clinicEntryUnlocked ~= true
       and p2.blizzardBroadcastTriggered ~= true then
        local tdt = eventData["TimeStep"]:GetFloat()
        -- 仅在 Dialog 关闭时累计时间（Dialog 打开时暂停，与诊所 Timer 行为一致）
        local troot = UI.GetRoot()
        local tdialog = troot and troot:FindById("dialog")
        local dialogVisible = (tdialog and tdialog:IsVisible()) or false
        if not dialogVisible then
            p2.tunnelElapsed = p2.tunnelElapsed + tdt
        end
        -- 双条件：完成任意 2 个调查点 或 自由调查经过 25 秒
        if (p2.tunnelInvestigatedCount >= 2) or (p2.tunnelElapsed >= 25) then
            -- 标记待播放，等待当前 Dialog 关闭后再播放（避免打断正在展示的线索）
            p2.blizzardBroadcastPending = true
        end
        -- 若当前 Dialog 已关闭且已满足条件 → 立即播放暴风雪广播
        if p2.blizzardBroadcastPending == true
           and not dialogVisible then
            FireP2TunnelBlizzard()
        end

        -- 每秒节流打印隧道分支状态（仅 DEBUG，不影响逻辑）
        p2DebugUpdateAccum_ = p2DebugUpdateAccum_ + tdt
        if p2DebugUpdateAccum_ >= 1.0 then
            p2DebugUpdateAccum_ = 0
            print(
                "[DEBUG TUNNEL UPDATE]"
                .. " phase=" .. tostring(p2.phase)
                .. " started=" .. tostring(p2.tunnelExplorationStarted)
                .. " count=" .. tostring(p2.tunnelInvestigatedCount)
                .. " elapsed=" .. tostring(p2.tunnelElapsed)
                .. " pending=" .. tostring(p2.blizzardBroadcastPending)
                .. " triggered=" .. tostring(p2.blizzardBroadcastTriggered)
                .. " dialogVisible=" .. tostring(dialogVisible)
            )
        end
    end

    if p2.clinicTimerStarted ~= true then return end
    if p2.clinicTimeUpHandled == true then return end
    if p2.flags.foodEventActive == true then return end
    if p2.clinicPhaseOneComplete == true then return end
    if p2.xianReturnEventPlaying == true then return end
    if p2.flags.finalTreatmentShown == true then return end
    if p2.flags.finalChoiceReady == true or p2.flags.finalChoiceSelected == true then return end

    local patienceRemaining = p2.patienceRemaining
    local patienceExhausted = patienceRemaining <= 0
    if patienceExhausted and p2.flags.patienceTimerForcedLogged ~= true then
        p2.flags.patienceTimerForcedLogged = true
        print("[P2-TIMER] patience exhausted, dialog no longer pauses timer")
    end

    -- 耐心耗尽后，普通调查/对白 Dialog 不再暂停主倒计时。
    local root = UI.GetRoot()
    local dialog = root and root:FindById("dialog")
    local dialogVisible = dialog and dialog:IsVisible()
    local shouldPauseForDialog = dialogVisible and not patienceExhausted
    if shouldPauseForDialog then
        return
    end

    -- V1.0 P2 本批：EAT_LATER 隐藏衰竭倒计时（10 秒；仅在场景主界面无任何弹窗时实时递减）
    -- 弹窗打开（调查文本 / 对白 / 确认窗 / 搜身详情 / 最终处理等）期间保持剩余值暂停；
    -- 归零时若弹窗仍开着，保持 0 并延迟到弹窗关闭后的下一次 Update 再执行 collapse（防叠加）。
    if p2.flags.exhaustionActive == true
        and p2.flags.exhaustionCollapsed ~= true
        and p2.flags.foodConsumed ~= true
        and p2.flags.foodEventActive ~= true
        and p2.flags.clinicPhaseOneComplete ~= true
        and p2.flags.finalTreatmentShown ~= true then
        local exhaustionRoot = UI.GetRoot()
        local exhaustionDialog = exhaustionRoot and exhaustionRoot:FindById("dialog")
        local exhaustionDialogVisible = exhaustionDialog and exhaustionDialog:IsVisible()
        if not exhaustionDialogVisible then
            local exdt = eventData["TimeStep"]:GetFloat()
            local ex = math.max(0, (p2.flags.exhaustionRemaining or 0) - exdt)
            p2.flags.exhaustionRemaining = ex
            if ex <= 3 and ex > 0 and p2.flags.exhaustionWarningPlayed ~= true then
                p2.flags.exhaustionWarningPlayed = true
                print(string.format("[P2-FOOD] exhaustion warning remaining=%d", math.ceil(ex)))
            end
            if ex <= 0 then
                p2.flags.exhaustionActive = false
                p2.flags.exhaustionCollapsed = true
                p2.flags.zeroStable = false
                p2.clinicPhaseOneComplete = true   -- 锁定调查入口
                p2.clinicTimerStarted = false
                p2.clinicTimeUpHandled = true
                print("[P2-FOOD] exhaustion collapsed")
                if p2.flags.foodChoice == "REFUSE" then
                    print("[P2-FOOD] collapse choice=REFUSE ending=xianLeaves")
                end
                p2.flags.forceEndingId = "xianLeaves"
                p2.flags.exhaustionOutcome = "XIAN_LEAVES"
                p2.flags.medicalProxy = false
                p2.flags.zeroStable = false
                CloseDialog()
                local collapseSteps = (Story2.foodEvent and Story2.foodEvent.collapse
                    and Story2.foodEvent.collapse.steps) or {}
                StartP2Dialogue(collapseSteps, function()
                    local morningSteps = (Story2.foodEvent and Story2.foodEvent.collapseNextMorning
                        and Story2.foodEvent.collapseNextMorning.steps) or {}
                    StartP2Dialogue(morningSteps, function()
                        p2.result = p2.result or {}
                        p2.result.endingId = "xianLeaves"
                        p2.result.endingTitle = "弦离开零"
                        p2.result.choice = p2.flags.foodChoice or "EAT_LATER"
                        p2.result.choiceResult = "零在衰竭后失去意识。"
                        p2.flags.resultReady = true
                        p2.checkpoint = "P2_FINAL_CHOICE_SELECTED"
                        if p2.flags.exhaustionEndingPlayed ~= true then
                            p2.flags.exhaustionEndingPlayed = true
                            PlayP2EndingSequence("xianLeaves", function()
                                if p2.flags.exhaustionEndHandled ~= true then
                                    p2.flags.exhaustionEndHandled = true
                                    EndP2()
                                end
                            end)
                        end
                    end, "营养罐头")
                end, "意识消退")
                return
            end
        end
    end

    -- V1.0 P2 本批：剩余 90 秒首次触发【弦返回并递给零营养罐头】（一次性；收口/最终处理后不再触发）
    if p2.clinicTimeRemaining <= 90
        and p2.clinicTimeRemaining > 0
        and p2.flags.foodEventTriggered ~= true
        and p2.flags.foodChoice == nil
        and p2.flags.clinicPhaseOneComplete ~= true
        and p2.flags.finalTreatmentShown ~= true then
        StartP2FoodEvent()
        return
    end

    local dt = eventData["TimeStep"]:GetFloat()
    p2.clinicTimeRemaining = math.max(0, p2.clinicTimeRemaining - dt)
    RefreshP2CountdownLabel(p2.clinicTimeRemaining)

    if p2.clinicTimeRemaining <= 0 then
        if p2.clinicTimeUpHandled == false then
            p2.clinicTimeUpHandled = true
            p2.clinicTimerStarted = false
            OnP2ClinicTimeUp()
        end
    end
end

-- V1.0 P2 新批次：隧道双条件达成后播暴风雪广播 + 弦两句对白，并解锁“进入诊所”。
-- 仅播放一次（blizzardBroadcastTriggered 守卫）；不修改诊所 03:00 Timer / 任何线索 / Dialog 公共系统。
function FireP2TunnelBlizzard()
    local p2 = P2Context.Get()
    if not p2 then return end
    if p2.blizzardBroadcastTriggered == true then return end
    print("[DEBUG TUNNEL BLIZZARD] CALLED")
    p2.blizzardBroadcastTriggered = true
    p2.blizzardBroadcastPending = false
    p2.clinicEntryUnlocked = true

    print("[DEBUG P2 BLIZZARD] FireP2TunnelBlizzard called")

    local b = (Story2.tunnel and Story2.tunnel.blizzard) or {}

    StartP2Dialogue(b, function()
        -- 播放完毕：保持“进入诊所”按钮可见，由玩家主动点击进入诊所。
        print("[DEBUG P2 BLIZZARD] dialogue complete, unlock clinic")
        RefreshP2EnterClinicButton()
    end, "隧道")
end

-- V1.0 P2 新批次：根据 clinicEntryUnlocked 刷新隧道“进入诊所”按钮可见性。
-- 广播前隐藏，广播后显示；玩家主动点击才进入诊所（不自动跳转）。
function RefreshP2EnterClinicButton()
    local p2 = P2Context.Get()
    if not p2 or p2.clinicEntryUnlocked ~= true then
        return
    end

    local root = p2Root_
    if not root then
        print("[DEBUG P2 BLIZZARD] p2Root_ missing")
        return
    end

    local btn = root:FindById("p2_obj_clinic")
    if not btn then
        print("[DEBUG P2 BLIZZARD] clinic button not found in p2Root_")
        return
    end

    btn:SetVisible(true)

    print("[DEBUG P2 BLIZZARD] clinic button visible")
end

-- P2 倒计时归零 → 弦返回事件（V1.0 P2 第十二批）
-- 锁定第一阶段调查入口并播放弦返回剧情，结束接 FinishP2ClinicPhaseOne 收口。
function OnP2ClinicTimeUp()
    print("[P2 Timer] Time Up")
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] OnP2ClinicTimeUp: P2 state not found")
        return
    end
    if p2.clinicPhaseOneComplete == true then
        return
    end
    -- 归零状态位（与 HandleP2Update 中设置保持一致，防重复）
    p2.clinicTimerStarted = false
    p2.clinicTimeUpHandled = true
    p2.xianReturnEventPlaying = true
    -- 倒计时结束后直接收口，避免插入与正式剧情无关的过渡页。
    FinishP2ClinicPhaseOne()
end

-- P2 第一阶段调查收口（V1.0 P2 第十二批）
-- 仅完成第一阶段结算，不进入第二阶段 / 不切场景 / 不开启新 Timer / 不接结局。
function FinishP2ClinicPhaseOne()
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] FinishP2ClinicPhaseOne: P2 state not found")
        return
    end
    p2.xianReturnEventPlaying = false
    p2.clinicPhaseOneComplete = true
    -- 保持 clinicTimerStarted=false / clinicTimeUpHandled=true（归零已处理）
    print("[P2 Clinic] Phase One Complete")
    CloseDialog()
    -- TEMP DEBUG：第一阶段收口关闭对话后的对话层状态（发布前删除）
    LogP2DialogState("phase_one_closed")
    -- V1.0 P2 本批：弦返回事件结束后，按镇静条件决定最终处理或直接进入结局 A。
    if p2.flags.exhaustionOutcome == "XIAN_LEAVES"
        or p2.flags.forceEndingId == "xianLeaves" then
        p2.result = p2.result or {}
        p2.result.endingId = "xianLeaves"
        p2.result.endingTitle = "弦离开零"
        p2.flags.resultReady = true
        PlayP2EndingSequence("xianLeaves", function()
            EndP2()
        end)
    elseif p2.hasSedative == true and p2.hasSyringe == true and p2.xianConscious == "SOBER" then
        print("[P2-FINAL-TREATMENT] enter from time up")
        PrepareP2FinalTreatment()
    else
        if p2.flags.scene06Played == true then return end
        p2.flags.scene06Played = true
        local scene06Steps = {
            { title = "离开诊所", speaker = "系统广播", text = "外部暴风雪强度下降。", audioIds = { "P2-PA-003" } },
            { title = "离开诊所", speaker = "系统广播", text = "红色预警解除。", audioIds = { "P2-PA-004" } },
            { title = "离开诊所", speaker = "系统广播", text = "当前区域仍存在低温及能见度风险。", audioIds = { "P2-PA-005" } },
            { title = "离开诊所", narration = "弦开始收拾物资。" },
            { title = "离开诊所", speaker = "弦", text = "雪小了。", audioIds = { "P2-S06-XIAN-001" } },
            { title = "离开诊所", speaker = "弦", text = "我们可以走了。", audioIds = { "P2-S06-XIAN-002" } },
        }
        StartP2Dialogue(scene06Steps, function()
            p2.result = p2.result or {}
            p2.result.choice = "leave_now"
            p2.result.choiceResult = "跟弦离开"
            p2.result.endingId = "trustXian"
            p2.result.endingTitle = "相信弦，与弦同行"
            p2.flags.resultReady = true
            if p2.flags.trustXianEndingPlayed == true then return end
            p2.flags.trustXianEndingPlayed = true
            PlayP2EndingSequence("trustXian", function()
                if p2.flags.trustXianEndHandled == true then return end
                p2.flags.trustXianEndHandled = true
                EndP2()
            end)
        end)
    end
end

-- 注意：P2 不再单独订阅 Update（函数引用 / 字符串两种形式均实测不会触发 handler）。
-- 由统一主循环 HandleUpdate 每帧调用 HandleP2Update。

-- ----------------------------------------------------------------------------
-- P2 调查按钮工厂入口。
-- ----------------------------------------------------------------------------
function CreateP2Investigation()
    print("[DEBUG]")
    print("Create P2 Investigation")
    -- 第一阶段收口 / 弦返回事件播放中：锁定入口，不再生成调查按钮
    local p2 = P2Context.Get()
    if p2 and (p2.xianReturnEventPlaying == true or p2.clinicPhaseOneComplete == true) then
        print("[DEBUG P2] CreateP2Investigation: 第一阶段已结束，锁定入口")
        return
    end
    -- 真正重建调查按钮（始终含诊室电脑；仅未通电时含应急电源）
    RefreshP2Investigation()
end

-- ----------------------------------------------------------------------------
-- P2 线索点击处理（V1.0 P2 第八批）
-- 本批只做到 Inspect：读取 Story2.clues[id]，ShowDialog 展示 title + inspect，按钮"关闭"。
-- 不做 Ask / FinishDialog / 调查次数 / 状态变化 / 问答。
-- ----------------------------------------------------------------------------
function OnP2ClueClicked(id)
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] OnP2ClueClicked: P2 state not found")
        return
    end
    -- 第一阶段收口 / 弦返回事件播放中：锁定入口，不再进入调查
    if p2 and (p2.xianReturnEventPlaying == true or p2.clinicPhaseOneComplete == true) then
        ShowDialog("调查", "第一阶段调查已经结束。", {
            { label = "关闭", variant = "primary", onClick = CloseDialog },
        })
        return
    end
    local clue = Story2.clues and Story2.clues[id]
    if not clue then
        print("[DEBUG P2] OnP2ClueClicked: 未找到线索 id=" .. tostring(id))
        return
    end
    -- 诊室电脑：双状态热点（V1.0 P2 第十四批）
    -- 通电前显示设备检查对白；通电后进入电脑文件和设备记录。
    -- 注意：电脑热点不写入 p2Asked_/不锁定，允许重复查看（状态由 powerRestored 决定）。
    if id == "computer" then
        if p2.flags.powerRestored == true then
            -- 通电后：KEY04 进入文件列表（V1.0 P2 第十五批）
            ShowDialog(clue.title or "诊室电脑", "电脑已经启动。\n桌面上只有三个文件。", {
                {
                    label = "查看电脑文件",
                    variant = "primary",
                    onClick = function()
                        CloseDialog()
                        ShowP2ComputerFiles()
                    end,
                },
                {
                    label = "查看设备记录",
                    variant = "default",
                    onClick = function()
                        CloseDialog()
                        OpenP2ClinicTerminalFiles()
                    end,
                },
                { label = "返回调查", variant = "default", onClick = CloseDialog },
            })
            return
        end
        -- 通电前：展示 inspect + "检查电脑"（播放 3 句 inner 对白）
        ShowDialog(clue.title or "诊室电脑", clue.inspect or "", {
            {
                label = "检查电脑",
                variant = "primary",
                onClick = function()
                    CloseDialog()
                    StartP2Dialogue(clue.dialogue, function()
                        CloseDialog()
                        p2.flags.visited_clinic_computer = true
                        RefreshP2Investigation()
                    end)
                end,
            },
            { label = "返回调查", variant = "default", onClick = CloseDialog },
        })
        return
    end
    -- KEY03 应急电源：未恢复时显示 inspect + "接通电源"；已恢复则防重复，仅提示已调查
    if id == "power" then
        if p2.flags.powerRestored == true then
            ShowDialog(clue.title or "应急电源", "电源已经恢复，诊所已通电。", {
                { label = "关闭", variant = "primary", onClick = CloseDialog },
            })
            return
        end
        ShowDialog(clue.title or "应急电源", clue.inspect or "", {
            {
                label = "接通电源",
                variant = "primary",
                onClick = function()
                    CloseDialog()
                    PlayP2PowerRestore()
                end,
            },
            { label = "关闭", variant = "default", onClick = CloseDialog },
        })
        return
    end
    -- KEY02 药柜流程由 p2cabinet.lua 负责，controller 仅保留正式入口桥接。
    if id == "cabinet" then
        P2Cabinet.Open(clue)
        return
    end
    ShowDialog(clue.title or "线索", clue.inspect or "", {
        { label = "关闭", variant = "primary", onClick = CloseDialog },
    })
end

-- ----------------------------------------------------------------------------
-- P2 药柜流程已迁移至 p2cabinet.lua；controller 仅保留入口桥接。
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- P2 KEY03 应急电源恢复对白播放（V1.0 P2 第十三批）
-- 复用 StartOpeningDialogue 播放 Story2.clues.power.dialogue；结束置 powerRestored 并刷新调查。
-- ----------------------------------------------------------------------------
function PlayP2PowerRestore()
    StartP2Dialogue(Story2.clues.power.dialogue, function()
        CloseDialog()
        -- 复用既有 P2 通电状态位（与 RestoreP2Power 同义，不新增重复状态）
        local p2 = P2Context.Get()
        if p2 then
            p2.flags.powerRestored = true
            p2.flags.visited_clinic_power = true
        end
        RefreshP2Investigation()
    end)
end

-- ----------------------------------------------------------------------------
-- P2 调查按钮刷新（V1.0 P2 第十四批：真实实现）
-- 在当前 UI Root 内维护一个 P2 专属容器 id="p2InvestigationButtons"：
--   · 容器存在则仅清空其内部由 P2 生成的调查按钮（不碰背景/倒计时/Dialog/标题等其它 UI）；
--   · 容器不存在则新建（pointerEvents="none"，让点击穿透到下层桌面）。
-- 然后按状态重建：始终含「诊室电脑」，仅未通电时含「应急电源」。
-- 防重复：先清空容器再重建，因此无论被调用多少次都只有一份按钮。
-- 阶段锁定：第一阶段收口 / 弦返回事件播放中 —— 不生成任何调查按钮（保持空容器）。
-- ----------------------------------------------------------------------------
function RefreshP2Investigation()
    local p2 = P2Context.Get()
    local root = UI.GetRoot()
    if not p2 or not root then
        print("[DEBUG P2] RefreshP2Investigation: 状态或 UI Root 不可用，跳过")
        return
    end

    -- 找到或创建 P2 专属调查按钮容器（仅该容器内的子节点会被本函数管理）
    -- 两个 P2 场景（隧道 / 诊所）已在 BuildP2Scene / BuildP2ClinicScene 中预置该容器；
    -- 此处仅兜底：若当前 Root 缺失则创建，并插入到 dialog 之前，保证 Dialog 渲染层级最高。
    local container = root:FindById("p2InvestigationButtons")
    if not container then
        container = UI.Panel {
            id = "p2InvestigationButtons",
            width = "100%", height = "100%",
            position = "absolute",
            left = 0, top = 0,
            backgroundColor = { 0, 0, 0, 0 },
            pointerEvents = "box-none",
            visible = false,
            children = {},
        }
        -- 插入到 dialog 所在位置之前（dialog 通常是最后一个 child）
        local insertAt = #(root.children or {})
        local children = root.children or {}
        for i, c in ipairs(children) do
            if c == root:FindById("dialog") then
                insertAt = i
                break
            end
        end
        root:InsertChild(container, insertAt)
    end

    -- V1.0 P2 第二十六批：调查按钮只在「诊所第一阶段调查激活」期间显示。
    -- 隧道阶段 / 倒计时未启动 / 弦返回事件播放中 / 第一阶段已收口 —— 一律隐藏，不做跨场景残留。
    local active = p2.phase == "CLINIC"
        and p2.clinicTimerStarted == true
        and p2.xianReturnEventPlaying ~= true
        and p2.clinicPhaseOneComplete ~= true
    if not active then
        container:SetVisible(false)
        RefreshP2SearchHotspots()
        print("[DEBUG P2] RefreshP2Investigation: 非诊所第一阶段调查期，隐藏调查按钮")
        return
    end
    container:SetVisible(true)

    -- 仅清空该容器内由 P2 生成的调查按钮；禁止清空整个 P2 Root
    container:ClearChildren()

    -- 诊室电脑 / 应急电源 / 锁住的药柜 仅属于医务室（CLINIC）；
    -- 休息区大厅(HALL)与取暖炉近景(HEARTH)不得创建或显示，避免跨层重复挂载。
    local inInfirmary = p2.clinicArea == "CLINIC"

    -- 始终生成「诊室电脑」按钮（通电前/后由点击分支切换内容，文本也随状态变化）
    if inInfirmary then
    local computerText = "COMPUTER"
    if p2.flags.powerRestored == true then
        computerText = "COMPUTER"
    end
    local computerBtn = UI.Button {
        id = "p2_obj_computer",
        text = "",
        width = 120, height = 90,
        position = "absolute",
        left = "24%", top = "36%",
        variant = "default",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 1, borderColor = { 0, 0, 0, 0 }, borderRadius = 10,
        boxShadow = false,
        fontSize = 15,
        onClick = function(self) OnP2ClueClicked("computer") end,
    }
    container:AddChild(P2SceneUI.AttachStaticFeedback(
        computerBtn,
        computerText,
        true,
        p2.flags.visited_clinic_computer == true
    ))
    end

    -- 仅未通电时生成「应急电源」按钮（KEY03）；通电后该按钮消失；仅医务室
    if inInfirmary and p2.flags.powerRestored ~= true then
        local powerBtn = UI.Button {
            id = "p2_obj_power",
            text = "",
            width = 120, height = 90,
            position = "absolute",
            left = "38%", top = "44%",
            variant = "default",
            backgroundColor = { 0, 0, 0, 0 },
            borderWidth = 1, borderColor = { 0, 0, 0, 0 }, borderRadius = 10,
            boxShadow = false,
            fontSize = 15,
            onClick = function(self) OnP2ClueClicked("power") end,
        }
        container:AddChild(P2SceneUI.AttachStaticFeedback(
            powerBtn,
            "POWER",
            true,
            p2.flags.visited_clinic_power == true
        ))
    end

    -- KEY02 药柜（四位数字密码锁，V1.0 P2 第二十批 + 本批修复）：
    -- 药柜为机械数字密码锁，不依赖诊所供电，也无需先查看其它线索。
    -- 仅医务室(CLINIC)显示，避免与休息区/近景层重复挂载；不再检查 powerRestored / readDiary。
    if inInfirmary then
        local cabinetBtn = UI.Button {
            id = "p2_obj_cabinet",
            text = "",
            width = 120, height = 90,
            position = "absolute",
            left = "66%", top = "44%",
            variant = "default",
            backgroundColor = { 0, 0, 0, 0 },
            borderWidth = 1, borderColor = { 0, 0, 0, 0 }, borderRadius = 10,
            boxShadow = false,
            fontSize = 15,
            onClick = function(self) OnP2ClueClicked("cabinet") end,
        }
        container:AddChild(P2SceneUI.AttachStaticFeedback(
            cabinetBtn,
            "CABINET",
            true,
            p2.flags.visited_clinic_cabinet == true
        ))
    end

    -- 固定功能入口由 BuildP2Scene 创建；诊所场景复用同一节点配置并置于公共根同级。

    -- V1.0 P2 新批次B：倒计时标签仅在「诊所第一阶段调查激活」期间显示，
    -- 隧道阶段 / 倒计时未启动 / 弦返回事件 / 第一阶段收口 —— 一律隐藏（隧道绝对不显示）。
    local cdLabel = root:FindById("p2CountdownLabel")
    if cdLabel then
        if active then
            cdLabel:SetText(FormatP2Countdown(p2.clinicTimeRemaining or 180))
            cdLabel:SetVisible(true)
        else
            cdLabel:SetVisible(false)
        end
    end

    print("[P2] RefreshP2Investigation done. computer=" .. tostring(p2.flags.powerRestored == true))
end

-- P2 诊所电脑文件控制已迁移至 p2terminal.lua；controller 保留条件与桥接入口。
function ShowP2ComputerFiles()
    P2Terminal.OpenClinicFiles()
end

-- P2 隧道阶段（V0.7-02 实现）：设置阶段 / 检查点
function PlayP2Tunnel()
    local p2 = P2Context.Get()
    if not p2 then return end
    p2.phase = "TUNNEL"
    p2.checkpoint = "P2_TUNNEL_START"
    -- V1.0 P2 新批次：隧道自由调查计时/计数启动（刷新进入时重置双条件状态）。
    -- 与诊所 03:00 Timer 完全独立；不显示隧道倒计时 UI。
    p2.tunnelExplorationStarted = true
    p2.tunnelInvestigatedCount = 0
    p2.tunnelElapsed = 0
    p2.blizzardBroadcastTriggered = false
    p2.blizzardBroadcastPending = false
    p2.clinicEntryUnlocked = false
    print("[DEBUG P2] >>> PlayP2Tunnel() phase=TUNNEL checkpoint=P2_TUNNEL_START")
    -- 音乐任务2：P2 隧道正式可调查 → 播放隧道背景音乐（BGMPlayer 同一 musicId 防重复）
    BGMPlayer.Play("BGM_P2_TUNNEL_AMBIENT_v01", { loop = true, gain = 0.28 })
end

-- V1.0 P2 新批次：记录隧道调查点首次完成（不同 id 各计一次，重复查看不重复计数）。
-- 仅当该 flag 此前不为 true 时 tunnelInvestigatedCount +1，驱动“完成任意 2 个调查点”条件。
local function RegisterTunnelClueViewed(p2, flagKey)
    if not p2 then return end
    local already = p2.flags[flagKey]
    p2.flags[flagKey] = true
    if already ~= true then
        p2.tunnelInvestigatedCount = (p2.tunnelInvestigatedCount or 0) + 1
    end
    print(
        "[DEBUG TUNNEL CLUE]"
        .. " key=" .. tostring(flagKey)
        .. " already=" .. tostring(already)
        .. " count=" .. tostring(p2.tunnelInvestigatedCount)
    )
end

-- V1.0 P2 本批：记录休息区次要线索首次完成（不同 key 各计一次，重复查看不重复计数）。
-- 仅当该 flag 此前不为 true 时 restInvestigatedCount +1；不影响隧道 tunnelInvestigatedCount，
-- 不触发隧道暴风雪广播、不改变关系值、不消耗耐心、不直接修改结局。
local function RegisterRestClueViewed(p2, flagKey)
    if not p2 then return end
    local already = p2.flags[flagKey]
    p2.flags[flagKey] = true
    if already ~= true then
        p2.restInvestigatedCount = (p2.restInvestigatedCount or 0) + 1
    end
    print(
        "[DEBUG REST CLUE]"
        .. " key=" .. tostring(flagKey)
        .. " already=" .. tostring(already)
        .. " count=" .. tostring(p2.restInvestigatedCount)
    )
end

local P2_ORDINARY_TUNNEL_CLUES = {
    comic = true,
    schedule = true,
    leak = true,
    sign = true,
    cart = true,
}
local P2_ORDINARY_CLINIC_CLUES = {
    temperature = true,
    cans = true,
    bed = true,
    triageRules = true,
    stretcher = true,
    medicineList = true,
    windowHandprint = true,
}

local function GetP2ClueKey(id, kind)
    return tostring(kind) .. ":" .. tostring(id)
end

local function IsP2OrdinaryClue(id, kind)
    if kind == "tunnel" then return P2_ORDINARY_TUNNEL_CLUES[id] == true end
    return P2_ORDINARY_CLINIC_CLUES[id] == true
end

local function GetP2ClueVisited(id, kind)
    local p2 = P2Context.Get()
    return p2 and p2.flags["visited_" .. GetP2ClueKey(id, kind)] == true or false
end

local function MarkP2ClueVisited(id, kind)
    local p2 = P2Context.Get()
    if not p2 then return false end
    local key = "visited_" .. GetP2ClueKey(id, kind)
    local wasVisited = p2.flags[key] == true
    if not wasVisited then
        p2.flags[key] = true
    end
    return wasVisited
end

---@type function
local DecorateP2ClueButton
local function SetP2ClueVisited(id, kind, label)
    local p2 = P2Context.Get()
    if not p2 then return false end
    local key = "visited_" .. GetP2ClueKey(id, kind)
    local wasVisited = p2.flags[key] == true
    if not wasVisited then
        p2.flags[key] = true
    end
    local root = UI.GetRoot()
    local prefix = kind == "tunnel" and "p2_obj_" or "p2_clinic_obj_"
    local button = root and root:FindById(prefix .. id)
    if button then
        DecorateP2ClueButton(button, id, kind, label)
    end
    return wasVisited
end

local function GetP2ClueLabel(id, kind)
    if kind == "tunnel" then
        local labels = {
            comic = "漫画", schedule = "排班表",
            leak = "重复脚印", sign = "指示箭头", cart = "儿童手套",
        }
        return labels[id] or id
    end
    local labels = {
        temperature = "室内温度记录", cans = "用过的营养罐头",
        bed = "空置病床", triageRules = "墙上的分诊制度",
        stretcher = "损坏的担架", medicineList = "药品缺失清单",
        windowHandprint = "窗外的手印",
    }
    return labels[id] or id
end

local P2_CLUE_BREATHE_DURATION = 1.7
local P2_CLUE_BREATHE_MIN = 0.78
local P2_CLUE_BREATHE_MAX = 1.0

DecorateP2ClueButton = function(button, id, kind, label)
    if not button or not IsP2OrdinaryClue(id, kind) then return button end
    local visited = GetP2ClueVisited(id, kind)
    local feedback = button:FindById("p2ClueFeedback")
    if not feedback then return button end
    local stateLabel = feedback:FindById("p2ClueState") --[[@as Label?]]
    local marker = feedback:FindById("p2ClueMarker") --[[@as Panel?]]
    local text = label or GetP2ClueLabel(id, kind)
    feedback:StopAnimation()
    if stateLabel then
        stateLabel:SetText(visited and "已调查" or "未调查")
    end
    feedback:SetStyle({
        opacity = visited and 0.48 or 1,
        backgroundColor = visited and { 50, 75, 95, 12 } or { 80, 190, 230, 16 },
        borderColor = visited and { 100, 145, 170, 150 } or { 120, 225, 255, 185 },
        boxShadow = visited and false or { { x = 0, y = 0, blur = 6, spread = 0, color = { 120, 220, 255, 55 } } },
    })
    if marker then
        marker:SetStyle({
            backgroundColor = visited and { 100, 145, 170, 150 } or { 135, 225, 255, 220 },
        })
    end
    if not visited then
        feedback:Animate({
            keyframes = {
                [0] = { opacity = P2_CLUE_BREATHE_MIN },
                [0.5] = { opacity = P2_CLUE_BREATHE_MAX },
                [1] = { opacity = P2_CLUE_BREATHE_MIN },
            },
            duration = P2_CLUE_BREATHE_DURATION,
            easing = "easeInOut",
            loop = true,
            fillMode = "backwards",
        })
    end
    return button
end

local function P2FeedbackDecorator(button, id, kind, label)
    return DecorateP2ClueButton(button, id, kind, label)
end

local function RefreshP2ClueButtonFeedback()
    local root = UI.GetRoot()
    local p2 = P2Context.Get()
    if not root or not p2 then return end
    local ids
    if p2.phase == "TUNNEL" then
        ids = { "comic", "schedule", "leak", "sign", "cart" }
        for i = 1, #ids do
            DecorateP2ClueButton(root:FindById("p2_obj_" .. ids[i]), ids[i], "tunnel")
        end
    elseif p2.phase == "CLINIC" then
        local area = p2.clinicArea or "HALL"
        if area == "HALL" then
            ids = { "temperature", "cans", "bed", "triageRules", "stretcher" }
        elseif area == "HEARTH" then
            ids = { "medicineList", "windowHandprint", "xianLocker" }
        else
            ids = { "bed" }
        end
        for i = 1, #ids do
            DecorateP2ClueButton(root:FindById("p2_clinic_obj_" .. ids[i]), ids[i], "clinic")
        end
    end
end

-- P2 会话态既有字段 p2.patienceRemaining。
function ConsumeP2Patience()
    local p2 = P2Context.Get()
    if not p2 then return 0 end
    if type(p2.patienceRemaining) ~= "number" then p2.patienceRemaining = 0 end
    if p2.patienceRemaining > 0 then
        p2.patienceRemaining = p2.patienceRemaining - 1
    end
    print("[DEBUG P2 耐心] ConsumeP2Patience -> patienceRemaining="
        .. tostring(p2.patienceRemaining))
    return p2.patienceRemaining
end

function P2_ResetOrdinaryClues()
    ResetP2ScanState()
    P2SceneUI.Reset()
    p2Root_ = nil
    p2ClinicRoot_ = nil
    local resetState = P2State.ResetP2()
    P2Context.Set(resetState)
    print("[P2] Reset: new initial state installed")
end

-- P2 MEMORY 02B《迁移名单》触发辅助（本批新增）：
-- 两张开场图片（缺图静默跳过，预检用 sendEventOnFailure=false，不产生 ResourceCache ERROR）
-- → PlayP2Memory01(memory.steps, …) → returnSteps → onComplete。
-- 不复制记忆正文、不调用默认 PlayP2ReturnDialogue、不触碰 P1 TriggerMemoryEvent。
-- onComplete 缺省时仅 CloseDialog，不擅自跳转场景。
function TriggerP2MigrationMemory(onComplete)
    local memory = Story2.memories and Story2.memories.migrationList
    local memorySteps = (memory and memory.steps) or {}
    local returnSteps = (memory and memory.returnSteps) or {}
    local images = (memory and memory.images) or {}
    -- 音乐任务2：P2「不能带家属」记忆开始
    BGMPlayer.Play("BGM_P2_MEMORY_BAD_v01", { loop = true, gain = 0.28 })
    local finish = function()
        CloseDialog()
        -- 音乐任务2：P2 记忆结束 → 恢复诊所背景音乐
        BGMPlayer.Play("BGM_P2_CLINIC_AMBIENT_v01", { loop = true, gain = 0.28 })
        if onComplete then onComplete() end
    end
    -- 返回现实段：returnSteps 完成后交还 onComplete
    local function PlayReturnSteps()
        if #returnSteps > 0 then
            StartP2Dialogue(returnSteps, finish, "迁移名单")
            -- 返回现实长文本页局部增高（本批）：仅 MEMORY 02B 返回现实窗口实例，
            -- StartOpeningDialogue 同步显示后对当前 dialogBox 抬高 maxHeight，不改全局样式。
            local retRoot = p2ClinicRoot_ or p2Root_
            local retDlg = retRoot and retRoot:FindById("dialog")
            local retBox = retDlg and retDlg:FindById("dialogBox")
            if retBox then
                retBox:SetStyle({ maxHeight = 380 })
            end
        else
            finish()
        end
    end
    -- 记忆本体：空 steps 防御 → 直接走 returnSteps
    local function PlayMemorySteps()
        if #memorySteps > 0 then
            PlayP2Memory01(memorySteps, PlayReturnSteps)
        else
            PlayReturnSteps()
        end
    end
    -- 缺图安全跳过（无文字占位、不给玩家显示文件名；已有图片等待【继续】）
    local function ShowMemImage(fileName, onDone)
        if not fileName or fileName == "" then
            print("[P2-MEM01] missing image: <empty>")
            onDone()
            return
        end
        if cache ~= nil and cache.GetResource ~= nil
            and cache:GetResource("Texture2D", fileName, false) == nil then
            print("[P2-MEM01] missing image: " .. fileName)
            onDone()
            return
        end
        ShowP2MemoryImage(fileName, "记忆", onDone)
    end
    -- 图1：电脑/《迁移选拔统计.xlsx》界面 → 图2：正式进入回忆 → 记忆对白
    ShowMemImage(images.migrationScreen, function()
        ShowMemImage(images.flashbackScene, PlayMemorySteps)
    end)
end

-- P2 向弦常规提问统一登记：耐心耗尽后的下一次新正式询问触发 MEMORY 02B。
-- 返回值：true = 本次登记触发了记忆（调用方应立即 return，跳过原返回流程，由 onMemoryComplete 收尾）；
--         false = 未触发（重复登记 / 耐心尚未耗尽 / 记忆已触发过），调用方继续原返回流程。
-- 计数字段：p2.flags.xianQuestionCount；防重结构：p2.flags.xianQuestionSources[sourceId]=true；
-- 记忆防重：p2.flags.migrationMemoryTriggered（一次性，后续提问仍正常登记但不重复播放）。
function RegisterP2XianQuestion(sourceId, onMemoryComplete, patienceBefore)
    local p2 = P2Context.Get()
    if not p2 then return false end
    p2.flags = p2.flags or {}
    p2.flags.xianQuestionSources = p2.flags.xianQuestionSources or {}
    local countBefore = p2.flags.xianQuestionCount or 0
    if type(patienceBefore) ~= "number" then
        patienceBefore = p2.patienceRemaining
    end
    local duplicate = p2.flags.xianQuestionSources[sourceId] == true
    print("[P2-QUESTION] source=" .. tostring(sourceId)
        .. " countBefore=" .. tostring(countBefore)
        .. " patienceBefore=" .. tostring(patienceBefore)
        .. " duplicate=" .. tostring(duplicate))
    if duplicate then
        return false
    end
    p2.flags.xianQuestionCount = countBefore + 1
    p2.flags.xianQuestionSources[sourceId] = true
    local count = p2.flags.xianQuestionCount
    print("[P2-QUESTION] registered source=" .. tostring(sourceId)
        .. " count=" .. tostring(count)
        .. " patienceAfter=" .. tostring(p2.patienceRemaining))
    -- 耐心耗尽后的下一次新正式询问触发 MEMORY 02B。
    if patienceBefore <= 0 and p2.flags.migrationMemoryTriggered ~= true then
        p2.flags.migrationMemoryTriggered = true
        print("[P2-MEMORY-02B] triggered count=" .. tostring(count)
            .. " source=" .. tostring(sourceId)
            .. " patienceBefore=" .. tostring(patienceBefore))
        TriggerP2MigrationMemory(onMemoryComplete)
        return true
    end
    if p2.flags.migrationMemoryTriggered == true then
        print("[P2-QUESTION] memory already triggered, skip replay")
    end
    return false
end

-- P2 隧道调查入口（独立逻辑，不碰 P1 的 investigated_/asked_/dialogRecord_/xianTrust_/时间系统）
-- id: comic / radio / schedule / verify / leak / sign / cart / poster
function OnP2TunnelClueClicked(id)
    local p2 = P2Context.Get()
    if not p2 then return end
    if p2.phase ~= "TUNNEL" then
        print("[DEBUG P2] OnP2TunnelClueClicked ignored (phase=" .. tostring(p2.phase) .. ")")
        return
    end

    if id == "comic" then
        local viewed = p2.flags.comicViewed
        SetP2ClueVisited("comic", "tunnel", "漫画")
        RegisterTunnelClueViewed(p2, "comicViewed")
        local imagePath =
            Story2.resources
            and Story2.resources.image
            and Story2.resources.image.comic
            or nil
        -- 目标流程：图片预览 → 点击“查看内容” → 关闭图片 → 展示原漫画文本 Dialog → 返回隧道
        -- 漫画窗口提供三个按钮：【查看漫画】【求证弦】【返回隧道】。
        -- 【求证弦】原为隧道主界面独立按钮（本批移入此处），复用 id=="verify" 分支；
        -- 仅在尚未求证（p2.flags.verifyDone ~= true）时显示，避免重复触发 / 重复计数。
        local function showComicDialog()
            local buttons = {
                {
                    label = "查看漫画", variant = "default",
                    onClick = function()
                        ShowP2ClueImage(imagePath, Story2.tunnel.comic.title, showComicDialog)
                    end,
                },
            }
            -- 求证弦：仅未求证且弦清醒（SOBER）时显示（镇静后隐藏；查看漫画/返回隧道不受影响）
            if p2.flags.verifyDone ~= true and p2.xianConscious == "SOBER" then
                table.insert(buttons, {
                    label = "求证弦", variant = "default",
                    onClick = function() OnP2TunnelClueClicked("verify") end,
                })
            end
            table.insert(buttons, { label = "返回隧道", variant = "primary", onClick = CloseDialog })
            local function showComicText()
                ShowDialog(Story2.tunnel.comic.title,
                    Story2.tunnel.comic.text .. (viewed and "\n\n（再次查看）" or ""),
                    buttons)
            end
            if not viewed and Story2.tunnel.comic.dialogue then
                StartP2Dialogue(Story2.tunnel.comic.dialogue, showComicText, Story2.tunnel.comic.title)
            else
                showComicText()
            end
        end
        ShowP2ClueImage(imagePath, Story2.tunnel.comic.title, showComicDialog)
        return
    end
    if id == "radio" then
        local viewed = p2.flags.radioViewed
        SetP2ClueVisited("radio", "tunnel", "广播")
        RegisterTunnelClueViewed(p2, "radioViewed")
        ShowDialog(Story2.tunnel.broadcast.title,
            Story2.tunnel.broadcast.text .. (viewed and "\n\n（再次查看）" or ""),
            { { label = "返回隧道", variant = "primary", onClick = CloseDialog } })
        return
    end
    if id == "schedule" then
        -- 排班表已恢复为普通调查线索：只展示线索内容，不触发任何角色互动 / 选择 / 关系值 / 记忆残响。
        -- 线索计数只计一次（RegisterTunnelClueViewed 内部已按 flag 去重，不重复 +1）。
        local viewed = p2.flags.scheduleViewed
        SetP2ClueVisited("schedule", "tunnel", "排班表")
        RegisterTunnelClueViewed(p2, "scheduleViewed")
        ShowDialog(Story2.tunnel.schedule.title,
            Story2.tunnel.schedule.text .. (viewed and "\n\n（再次查看）" or ""),
            { { label = "返回隧道", variant = "primary", onClick = CloseDialog } })
        return
    end
    if id == "verify" then
        -- 镇静保险（本批）：弦非清醒时静默拦截，返回隧道场景；不设 verifyDone / 不计数
        if not p2 or p2.xianConscious ~= "SOBER" then
            print("[P2-XIAN] interaction blocked: sedated")
            BuildP2Scene()
            return
        end
        -- 求证：独立 P2 询问，不消耗 P1 回应次数、不碰 asked_/responseRemaining_
        -- 仅保留隧道已有求证内容「漫画」；「药柜密码」属于诊所 KEY02，不出现在隧道。
        -- V1.0 本批：移除中间「你想问哪一件事？」选择窗，【求证弦】直接进入漫画求证对话。
        MarkP2ClueVisited("verify", "tunnel")
        RegisterTunnelClueViewed(p2, "verifyDone")
        local v = Story2.tunnel.verify or {}
        local comic = v.comic or {}
        local patienceBefore = p2.patienceRemaining
        local comicDialogue = {
            { speaker = "我", text = "你见过这本书吗？", audioIds = { "P2-E01-ZERO-004" } },
            { speaker = "弦", text = "这种旧漫画很常见", audioIds = { "P2-E01-XIAN-001" } },
            { speaker = "我", text = "里面的涂鸦呢？", audioIds = { "P2-E01-ZERO-005" } },
        }
        local function FinishTunnelComicQuestion()
            local answerStep = {
                speaker = "弦",
                text = "没注意过。",
                audioIds = { "P2-E01-XIAN-002" },
            }
            AppendP2DialogueRecord(answerStep, answerStep.audioIds[1], "tunnel_comic")
            ShowDialog(comic.title or "求证：漫画", answerStep.speaker .. "：\n" .. answerStep.text, {
                { label = "返回隧道", variant = "primary", onClick = function()
                    -- 四句对白完整结束后登记；重复 source 不再扣耐心
                    if not (p2.flags.xianQuestionSources
                        and p2.flags.xianQuestionSources["tunnel_comic"] == true) then
                        ConsumeP2Patience()
                        local triggered = RegisterP2XianQuestion("tunnel_comic", function()
                            BuildP2Scene()
                        end, patienceBefore)
                        if triggered then return end
                    end
                    CloseDialog()
                end },
            })
        end
        StartP2Dialogue(comicDialogue, FinishTunnelComicQuestion, comic.title or "求证：漫画")
        return
    end
    -- 四条次要线索（环境观察，独立 flags，重复查看不重复触发奖励）
    local minor = Story2.tunnel.minorClues[id]
    if minor then
        local flagKey = "minor_" .. id .. "_viewed"
        local viewed = p2.flags[flagKey]
        SetP2ClueVisited(id, "tunnel", id)
        RegisterTunnelClueViewed(p2, flagKey)
        -- V1.0 P2 本批：leak(重复脚印) 使用逐页 dialogue 数组（narration→inner→inner），
        -- 其余次要线索(text 字段)保持原单页 ShowDialog 不变；二者入口与计数逻辑完全一致。
        local dialogue = minor.dialogue
        if dialogue then
            local idx = 1
            local total = #dialogue
            local function ShowStep()
                local step = dialogue[idx]
                if not step then return end
                local isLast = idx >= total
                local body
                if step.narration then
                    body = step.narration
                elseif step.inner then
                    body = "我｜内心：" .. step.inner
                else
                    body = ""
                end
                local buttons = {
                    {
                        label = isLast and "返回隧道" or "继续",
                        variant = "primary",
                        onClick = function()
                            if isLast then
                                CloseDialog()
                                VoicePlayer.Stop()
                            else
                                idx = idx + 1
                                ShowStep()
                            end
                        end,
                    },
                }
                -- 逐句配音：显示当前 step 时播放对应配音
                VoicePlayer.PlayStep(step)
                ShowDialog(minor.title, body, buttons)
            end
            ShowStep()
            return
        end
        ShowDialog(minor.title,
            minor.text .. (viewed and "\n\n（再次查看）" or ""),
            { { label = "返回隧道", variant = "primary", onClick = CloseDialog } })
        return
    end

    print("[DEBUG P2] OnP2TunnelClueClicked unknown id=" .. tostring(id))
end

-- ----------------------------------------------------------------------------
-- 诊所批次（V1.0-04D-B2 迁移自 main.lua，函数名/参数/return 行为/print 文本/Story2
-- 访问/Dialog 调用/EndP2 裸名调用均保持原样；仅把 GetP2() 改为 P2Context.Get()）
-- 以下函数定义为全局（与 main 中原有全局函数一致），供 OnP2ClinicClueClicked / 按钮
-- 回调 / PlayP2Clinic 内嵌自测块以裸名方式继续调用，无需改动任何调用点。
-- ----------------------------------------------------------------------------

-- 恢复诊所备用电源（V0.7-04-02 新增）
-- 仅修改 P2 状态（p2State_.flags / checkpoint），不触碰 P1 任何全局变量。
function RestoreP2Power()
    local p2 = P2Context.Get()
    if not p2 then return end
    p2.flags.powerRestored = true
    p2.flags.powerAttemptCount = (p2.flags.powerAttemptCount or 0) + 1
    p2.checkpoint = "P2_POWER_RESTORED"
    print("[P2 Power]\nrestored=true\nattemptCount=" .. tostring(p2.flags.powerAttemptCount))
    local p = Story2.clinic.clues.power
    ShowDialog("电源已恢复", p.restoreSuccess,
        { { label = "返回诊所", variant = "primary", onClick = CloseDialog } })
end

-- P2 全局记录终端控制已迁移至 p2terminal.lua；controller 保留正式兼容入口。
OpenP2DialogueRecords = function()
    P2Terminal.OpenRecords()
end

OpenP2ClinicTerminalFiles = function()
    P2Terminal.OpenClinicRecords()
end

-- 药柜药物资料由 p2cabinet.lua 提供；此处保留正式调用名供现有流程使用。
function OpenP2MedicationRecords()
    P2Cabinet.ShowMedicationRecords()
end

-- 诊所探索完成检测（V0.7-07 新增，V0.7-08 扩展触发事件）
-- 检查电源已恢复 + 四个核心调查点（终端记录 / 药物资料 / 病床 / 医疗记录）均已查看。
-- 首次全部满足时：置 clinicExploreComplete=true，并触发探索完成事件（只触发一次）。
function CheckP2ClinicExploreComplete()
    local p2 = P2Context.Get()
    if not p2 then return end
    local done = p2.flags.powerRestored
        and (p2.flags.terminalRecordsViewed or false)
        and (p2.flags.medicationsViewed or false)
        and (p2.flags.bedViewed or false)
        and (p2.flags.recordViewed or false)
    if done and not p2.flags.clinicExploreComplete then
        p2.flags.clinicExploreComplete = true
        print("[P2 Clinic]\nexploration complete")
        -- 首次完成：触发探索完成事件（内部负责防重复 + checkpoint 更新）
        TriggerP2ClinicExploreComplete()
    end
end

-- 触发诊所探索完成事件（V0.7-08 新增）
-- 读取 Story2.clinic.exploreCompleteEvent，展示弦/玩家对白 + 信息总结；
-- 置 clinicExploreEventTriggered=true，更新 checkpoint=P2_CLINIC_EVENT_COMPLETE。
-- 由 CheckP2ClinicExploreComplete 在「首次完成」时调用；自带防重复保护。
function TriggerP2ClinicExploreComplete()
    local p2 = P2Context.Get()
    if not p2 then return end
    if p2.flags.clinicExploreEventTriggered then
        print("[DEBUG P2] TriggerP2ClinicExploreComplete: already triggered, skip")
        return
    end
    local ev = Story2.clinic.exploreCompleteEvent
    if not ev then
        print("[DEBUG P2] TriggerP2ClinicExploreComplete: no event data")
        return
    end
    p2.flags.clinicExploreEventTriggered = true
    p2.checkpoint = "P2_CLINIC_EVENT_COMPLETE"
    print("[P2 Clinic]\nexplore event triggered")
    -- 展示：标题 + 弦对白 + 玩家对白 + 信息总结，单条长文本收束
    local body = ev.xianLines .. "\n\n" .. ev.playerLines .. "\n\n————————\n\n" .. ev.summary
    ShowLongDialog(ev.title, body,
        { { label = "继续", variant = "primary", onClick = function()
            CloseDialog()
            -- V1.0 P2 本批：弦返回事件结束后先进入【最终处理】阶段，再衔接原有去留选择
            PrepareP2FinalTreatment()
        end } })
end

-- ----------------------------------------------------------------------------
-- P2 最终处理 / 最终选择 / 食物与结局流程已迁移至 p2finalflow.lua。
-- controller 仅保留正式兼容入口；EndP2() 仍由本模块负责结算与存档。
function PrepareP2FinalTreatment()
    return P2FinalFlow.PrepareFinalTreatment()
end

function ShowP2FinalTreatmentChoice()
    return P2FinalFlow.ShowFinalTreatmentChoice()
end

function PrepareP2FinalChoice()
    return P2FinalFlow.PrepareFinalChoice()
end

function BeginP2SedateXianFlow(onComplete, onCancel)
    return P2FinalFlow.StartSedation(onComplete, onCancel)
end

function ShowP2SearchXianFlow(onComplete)
    return P2FinalFlow.StartSearch(onComplete)
end

function OnP2SearchHotspotClicked(itemKey)
    return P2FinalFlow.SearchItem(itemKey, function()
        RefreshP2SearchHotspots()
    end)
end

function RefreshP2SearchHotspots()
    local p2 = P2Context.Get()
    local root = UI.GetRoot()
    local mapHotspot = root and root:FindById("p2_clinic_search_route_map")
    local braceletHotspot = root and root:FindById("p2_clinic_search_identity_bracelet")
    local canSearch = p2
        and p2.phase == "CLINIC"
        and p2.xianConscious == "SEDATED"
    if mapHotspot then mapHotspot:SetVisible(canSearch == true) end
    if braceletHotspot then braceletHotspot:SetVisible(canSearch == true) end
    print("[P2-SEARCH] hotspots visible=" .. tostring(canSearch == true))
end

function StartP2FoodEvent()
    return P2FinalFlow.StartFoodEvent()
end

function PlayP2FoodEvent()
    return P2FinalFlow.PlayFoodEvent()
end

function ShowP2FoodChoice()
    return P2FinalFlow.ShowFoodChoice()
end

function PlayP2FoodBranch(choiceId)
    return P2FinalFlow.PlayFoodBranch(choiceId)
end

function FinishP2FoodEvent(choiceId)
    return P2FinalFlow.FinishFoodEvent(choiceId)
end

function HandleP2RefuseCollapse()
    return P2FinalFlow.HandleRefuseCollapse()
end

function PlayP2RefuseOutcome(nodeKey)
    return P2FinalFlow.PlayRefuseOutcome(nodeKey)
end

function EnterP2FinalChoice()
    return P2FinalFlow.EnterFinalChoice()
end

function EvaluateP2FinalLeaf(choiceId)
    return P2FinalFlow.EvaluateFinalLeaf(choiceId)
end

function ClassifyP2FinalEnding(choiceId)
    return P2FinalFlow.ClassifyFinalEnding(choiceId)
end

function PlayP2EndingSequence(endingId, onComplete)
    return P2FinalFlow.PlayEndingSequence(endingId, onComplete)
end

function OnP2FinalChoiceSelected(choiceId)
    return P2FinalFlow.HandleFinalChoice(choiceId)
end

-- P2 静态场景 UI 按钮工厂已迁移至 p2sceneui.lua；controller 保留兼容入口。
function CreateP2TunnelButton(id, label, leftPct, topPct)
    return P2SceneUI.CreateTunnelButton(id, label, leftPct, topPct)
end

function CreateP2EnterClinicButton()
    return P2SceneUI.CreateEnterClinicButton()
end

function CreateP2ClinicButton(id, label, leftPct, topPct)
    return P2SceneUI.CreateClinicButton(id, label, leftPct, topPct)
end

-- P2 独立扫描桥接：只收集当前场景已有调查按钮，不读取 P1 热点或 P1 扫描状态。
local function CollectP2ScanHotspots(root, p2)
    local widgets = {}
    local function add(id)
        local widget = root and root:FindById(id)
        if widget and widget:IsVisible() then
            widgets[#widgets + 1] = widget
        end
    end

    if p2 and p2.phase == "TUNNEL" then
        add("p2_obj_comic")
        add("p2_obj_schedule")
        add("p2_obj_leak")
        add("p2_obj_sign")
        add("p2_obj_cart")
    elseif p2 and p2.phase == "CLINIC" then
        local area = p2.clinicArea or "HALL"
        if area == "HALL" then
            add("p2_clinic_obj_hearth")
            add("p2_clinic_obj_temperature")
            add("p2_clinic_obj_cans")
            add("p2_clinic_obj_bed")
            add("p2_clinic_obj_triageRules")
            add("p2_clinic_obj_stretcher")
        elseif area == "HEARTH" then
            add("p2_clinic_obj_backpack")
            add("p2_clinic_obj_organize")
            add("p2_clinic_obj_medicineList")
            add("p2_clinic_obj_windowHandprint")
            add("p2_clinic_obj_xianLocker")
            add("p2_clinic_obj_hearth")
        else
            add("p2_clinic_obj_clinicBed")
            local investigation = root:FindById("p2InvestigationButtons")
            local children = investigation and investigation.children or {}
            for i = 1, #children do
                if children[i]:IsVisible() then
                    widgets[#widgets + 1] = children[i]
                end
            end
        end
    end
    return widgets
end

ResetP2ScanState = function()
    p2ScanMode_ = false
    p2ScanHotspots_ = {}
    ScanFX.Hide()
end

-- P2 Scan入口：复用 ScanFX/ScanStatus，仅在当前 P2 场景收集现有热点。
function OnP2ScanClicked(button)
    local p2 = P2Context.Get()
    local root = UI.GetRoot()
    if not p2 or not root then return end

    if p2ScanMode_ then
        p2ScanMode_ = false
        p2ScanHotspots_ = {}
        ScanFX.Hide()
        button:SetText("SCAN")
        return
    end

    p2ScanHotspots_ = CollectP2ScanHotspots(root, p2)
    p2ScanMode_ = true
    button:SetText("SCANNING")
    ScanStatus.ShowScanning()
    print("[P2-SCAN] start phase=" .. tostring(p2.phase)
        .. " area=" .. tostring(p2.clinicArea)
        .. " hotspots=" .. tostring(#p2ScanHotspots_))
    ScanFX.Play(function()
        local currentP2 = P2Context.Get()
        if not currentP2 or not p2ScanMode_ then return end
        p2ScanHotspots_ = CollectP2ScanHotspots(UI.GetRoot(), currentP2)
        ScanStatus.ShowDetected()
        print("[P2-SCAN] detected current hotspots=" .. tostring(#p2ScanHotspots_))
    end)
end

local function CreateP2ScanButton()
    return P2SceneUI.CreateScanButton()
end

local function CreateP2RecordTerminalButton()
    return P2SceneUI.CreateRecordTerminalButton()
end

-- ----------------------------------------------------------------------------
local function AddP2DynamicClinicChildren(root)
    local pex = P2Context.Get()
    if not root or not pex then return end
    if not pex.flags
        or pex.flags.exhaustionActive ~= true
        or (pex.flags.exhaustionRemaining or 0) <= 0
        or pex.flags.foodChoice ~= "EAT_LATER"
        or pex.flags.foodConsumed == true then
        return
    end
    root:AddChild(UI.Button {
        id = "p2_obj_eat_now",
        text = "吃掉罐头",
        width = 150, height = 64,
        position = "absolute", right = 20, bottom = 40,
        variant = "primary",
        fontSize = 14,
        onClick = function()
            local pe = P2Context.Get()
            if not pe then return end
            if not pe.flags or pe.flags.exhaustionActive ~= true then return end
            local flags = pe.flags
            local before = flags.exhaustionRemaining
            flags.exhaustionActive = false
            flags.exhaustionPending = false
            flags.exhaustionRemaining = 0
            flags.foodConsumed = true
            flags.zeroStable = true
            flags.medicalProxy = true
            print(string.format("[P2-FOOD] delayed food consumed remaining=%s", tostring(before)))
            BuildP2ClinicScene(pe.clinicArea or "HALL")
        end,
    })
end

-- TEMP DEBUG：只读输出当前激活 UI 根下 dialog/dialogBox 的状态。
function LogP2DialogState(tag)
    local root = (UI.GetRoot and UI.GetRoot()) or nil
    local dialog = root and root.FindById and root:FindById("dialog")
    local box = dialog and dialog.FindById and dialog:FindById("dialogBox")
    print(string.format(
        "[P2-DIALOG] tag=%s root=%s dialog=%s visible=%s pointerEvents=%s box=%s",
        tostring(tag), tostring(root ~= nil), tostring(dialog ~= nil),
        tostring(dialog and dialog.visible), tostring(dialog and dialog.pointerEvents),
        tostring(box ~= nil)
    ))
end

-- P2 隧道静态 UI 已迁移至 p2sceneui.lua；controller 保留场景状态、Scan 重置和入口刷新。
function BuildP2Scene()
    ResetP2ScanState()
    p2Root_ = P2SceneUI.BuildTunnelScene()
    SetCurrentUIRoot(p2Root_)
    local p2Now = P2Context.Get()
    if p2Now and p2Now.clinicEntryUnlocked == true then
        local clinicBtn = p2Root_:FindById("p2_obj_clinic")
        if clinicBtn then clinicBtn:SetVisible(true) end
    end
    print("[DEBUG P2] P2 scene built (tunnel)")
end

-- P2 隧道图片预览 UI 已迁移至 p2sceneui.lua；controller 保留兼容入口。
function ShowP2ClueImage(imagePath, title, callback)
    return P2SceneUI.ShowClueImage(imagePath, title, callback)
end

-- P2 诊所静态 UI 已迁移至 p2sceneui.lua；controller 保留状态、动态调查和 Scan 入口。
function BuildP2ClinicScene(area)
    ResetP2ScanState()
    print(string.format(
        "[P2-AREA-SWITCH] build area=%s root=%s",
        tostring(area),
        tostring(p2ClinicRoot_ ~= nil)
    ))
    p2ClinicRoot_ = P2SceneUI.BuildClinicScene(area)
    SetCurrentUIRoot(p2ClinicRoot_)
    local p = P2Context.Get()
    if p then p.clinicArea = area or "HALL" end
    if p and p.clinicArea == "CLINIC" then
        print("[DEBUG P2-CABINET-FLOW] returned_to_clinic")
    end
    AddP2DynamicClinicChildren(p2ClinicRoot_)
    LogP2DialogState("clinic_built")
    RefreshP2Investigation()
    RefreshP2SearchHotspots()
    print("[DEBUG P2] P2 scene built (clinic, area=" .. tostring(area or "HALL") .. ")")
end

-- P2 诊所与 Memory 图片预览 UI 已迁移至 p2sceneui.lua；controller 保留兼容入口。
function ShowP2ClinicClueImage(imagePath, title, buttonText, callback)
    return P2SceneUI.ShowClinicClueImage(imagePath, title, buttonText, callback)
end

function ShowP2MemoryImage(imagePath, title, callback, root)
    return P2SceneUI.ShowMemoryImage(imagePath, title, callback, root)
end

-- P2 进入诊所（V1.0-04F-A 迁移自 main.lua）
-- 函数名/参数/调用流程/phase-checkpoint 状态逻辑均保持原样；定义为全局函数，
-- 以便 CreateP2EnterClinicButton 的 onClick（仍在 main 按钮工厂迁移后的 p2controller 中）
-- 以裸名继续调用，无需改动调用点。
-- 仅把 GetP2() 改为 P2Context.Get()；PlayP2Clinic() 保持裸名调用。
-- ----------------------------------------------------------------------------

-- P2 进入诊所（隧道「进入诊所」按钮回调）
-- 完成阶段切换并进入诊所调查流程。
function EnterP2Clinic()
    local p2 = P2Context.Get()
    if not p2 then return end
    if p2.phase ~= "TUNNEL" then
        print("[DEBUG P2] EnterP2Clinic ignored (phase=" .. tostring(p2.phase) .. ")")
        return
    end
    PlayP2Clinic()
end

-- ----------------------------------------------------------------------------
-- P2 诊所调查入口（V1.0-04F-B 迁移自 main.lua）
-- 函数名/参数/分支逻辑/Story2.clinic.clues 数据访问/ShowDialog·ShowP2Image 调用顺序
-- 均保持原样；定义为全局函数，以便 BuildP2ClinicScene 的按钮 onCreate 回调（裸名）继续调用。
-- 仅把 GetP2() 改为 P2Context.Get()；RestoreP2Power / OpenP2TerminalRecords /
-- OpenP2MedicationRecords / CheckP2ClinicExploreComplete 保持裸名调用。
-- ----------------------------------------------------------------------------

-- P2 休息区次要线索播放器（V1.0 P2 本批新增 MINOR-C01~C09）
-- 逐页播放 Story2.clinic.restArea.minorClues[id].dialogue：
--   narration → screen(若存在) → inner(两条)，每页一条 ShowDialog，标题用线索标签。
-- 其中 screen（规章文字 / 库存清单文字）与 narration（环境描述）均不配音；
-- 仅 inner（我｜内心）参与配音（audioIds 仅作登记，不在此播放）。
-- 首次查看设置对应 flag（restXxxViewed），并计入 restInvestigatedCount（不重复计数）。
-- onComplete 在最后一条关闭后回调（用于取暖炉跳转近景等）。
-- P2 休息区次要线索播放器已迁移至 p2clinicclues.lua；controller 保留正式兼容入口。
function PlayRestMinorClue(...)
    return P2ClinicClues.PlayRestMinorClue(...)
end


-- P2 诊所调查入口（独立逻辑，不碰 P1 的 investigated_/asked_/dialogRecord_/xianTrust_/时间系统）
-- id: terminal / power / cabinet / bed / record
-- P2 炉火交互流程（V1.0 P2 本批：恢复 HEARTH 内玩家主动点火，逻辑自旧 hearth 分支原样迁移）
-- 首次：播放 MINOR-C06 heater 文本 → fireLit=true → 炉火对白 → 信任 +3 → 返回 HEARTH；
-- 已点燃（fireLit=true）：仅显示简短原文，不重复信任 / 计数 / 演出。
-- 背景不切换：HEARTH 本身即炉火近景背景（P2_BG03）。
-- P2 炉火流程已迁移至 p2clinicclues.lua；controller 保留正式兼容入口。
function PlayP2HearthFireFlow(...)
    return P2ClinicClues.PlayHearthFireFlow(...)
end

function OnP2ClinicClueClicked(id)
    local p2 = P2Context.Get()
    if not p2 then return end
    if p2.phase ~= "CLINIC" then
        print("[DEBUG P2] OnP2ClinicClueClicked ignored (phase=" .. tostring(p2.phase) .. ")")
        return
    end
    -- 普通诊所线索由 restClues 或普通 clue 分支分别登记访问状态。
    -- V1.0 P2 新批次D：弦被镇静（xianConscious=="SEDATED"）后，所有与弦本人有关的互动永久失效。
    -- 仅「检查弦的物品」(searchXian) 为镇静后的替代互动，保持可用；其余与弦有关的互动一律拦截。
    local xianPersonInteractions = { hearth = true, backpack = true, organize = true, useSedative = true }
    if p2.xianConscious == "SEDATED" and xianPersonInteractions[id] then
        ShowDialog("弦", "弦已经陷入镇静，无法回应。", {
            { label = "返回诊所", variant = "primary", onClick = CloseDialog },
        })
        print("[DEBUG P2] OnP2ClinicClueClicked [" .. tostring(id) .. "] blocked (xian SEDATED)")
        return
    end
    -- V1.0 P2 本批：休息区次要线索（MINOR-C01~C05、C07~C09）统一分发。
    -- 仅数据在 Story2.clinic.restArea.minorClues 中登记的 id 走此分支；
    -- 不调用通用 ShowP2Image（该接口只服务医务室资源），逐页播放由 PlayRestMinorClue 处理。
    local restClues = Story2.clinic
        and Story2.clinic.restArea
        and Story2.clinic.restArea.minorClues
    local clue = Story2.clinic.clues[id]
    local ordinaryClue = clue and id == "bed"
    if ordinaryClue then
        SetP2ClueVisited(id, "clinic")
    end
    -- 弦的旧储物柜（xianLocker）配图迁移：先显示原 CLINIC 储物柜的 C02 配图
    -- （复用 Story2.resources.image.locker，不新增图片），点「查看内容」后进入 MINOR-C09 流程。
    -- 末句（P2-C09-ZERO-002）页底部直接挂「可选求证04」两个选择（无【继续】、无独立空白选择页）。
    -- 本轮仅接对白入口：不消耗耐心 / 不置已询问 flag / 不做信息解锁（后续批次接入）。
    if id == "xianLocker" and restClues and restClues.xianLocker then
        print("[DEBUG P2-CABINET-FLOW] clue_clicked")
        local xianLockerClue = restClues.xianLocker
        return P2ClinicClues.HandleXianLocker(xianLockerClue)
    end
    -- 墙上的分诊制度（triageRules）由 p2clinicclues.lua 负责。
    if id == "triageRules" and restClues and restClues.triageRules then
        SetP2ClueVisited(id, "clinic")
        return P2ClinicClues.HandleTriageRules(restClues.triageRules)
    end
    if restClues and restClues[id] then
        SetP2ClueVisited(id, "clinic")
        return P2ClinicClues.HandleRestClue(id, restClues[id])
    end
    if id == "clinicBed" then id = "bed" end
    if id == "bed" and clue then
        SetP2ClueVisited(id, "clinic")
        return P2ClinicClues.HandleNormalClinicClue(id, clue)
    end
    if id == "power" then
        local p = Story2.clinic.clues.power
        p2.flags.powerViewed = true
        if not p2.flags.powerRestored then
            ShowDialog(p.powerOff.title,
                p.powerOff.text .. "\n\n" .. p.powerOff.hint,
                {
                    { label = "恢复电源", variant = "primary", onClick = function()
                        RestoreP2Power()
                    end },
                    { label = "返回诊所", variant = "default", onClick = CloseDialog },
                })
        else
            ShowDialog(p.powerOn.title, p.powerOn.text,
                { { label = "返回诊所", variant = "primary", onClick = CloseDialog } })
        end
        return
    end

    if id == "terminal" then
        return P2Terminal.OpenClinicRecords()
    end

    -- 药柜流程由 p2cabinet.lua 负责。
    if id == "cabinet" then
        return P2Cabinet.Open(Story2.clinic.clues.cabinet)
    end

    -- （V1.0 P2 本批：CLINIC「储物柜」重复入口已删除，唯一正式入口为 HEARTH「弦的旧储物柜」xianLocker → MINOR-C09；
    --   C02 配图是否迁移到 xianLocker 另开一轮处理，本轮不迁移。）

    -- 休息互动阶段 · 取暖炉（V1.0-07J，EVENT 02，MINOR-C06 复用入口）
    -- 流程（本批调整）：先播放 MINOR-C06「燃料不足的取暖炉」调查内容（逐页），
    -- 再临时切换诊所背景为 BG03 炉火休息区播放炉火对白（关系值 +3），
    -- 返回后进入取暖炉近景 HEARTH 层（背景 P2_BG03，含 整理药盒 / 弦的背包）。
    -- 入口仍为唯一【取暖炉】按钮（id="hearth"），不新建第二个重复按钮。
    -- 取暖炉（V1.0 P2 本批：按所在区域分流同一 id）
    -- HALL：纯场景入口 → 进入 HEARTH 近景；
    -- HEARTH：【检查取暖炉】→ 炉火交互（首次 heater 文本+fireLit+信任+3；已点燃仅简短原文）。
    if id == "hearth" then
        local p = P2Context.Get()
        local cur = (p and p.clinicArea) or "HALL"
        if cur == "HEARTH" then
            PlayP2HearthFireFlow()
        else
            BuildP2ClinicScene("HEARTH")
        end
        return
    end

    -- 休息互动阶段 · 弦的背包（V1.0-07J，EVENT 03 基础骨架，本批重写）
    -- 流程：两条屏幕文字（各一页）→ 三句零的内心独白 → 第一层选择（本轮仅入口）。
    -- 不复用药盒 / 电脑 / 储物柜事件；不写关系值 / 耐心 / 记忆 / 星星关联等任何状态。
    if id == "backpack" then
        local backpackClue = Story2.bagEvent
        return P2ClinicClues.HandleBackpack(backpackClue)
    end

    -- 休息互动阶段 · 帮助弦整理药盒（V1.0-07J，EVENT 05 → MEMORY 02）
    -- 对白 → 关系值 +4 → 触发 Memory 图（C09）演出 → 返回诊所调查态。
    -- 复用现有 ShowP2MemoryImage；不新增 memoryViewed / 记忆场景 / 存档字段。
    if id == "organize" then
        return P2ClinicClues.HandleOrganize(clue)
    end

    -- 对弦使用短效镇静剂（V1.0-07N-P2-B2-C，条件显隐入口逻辑分支）
    -- 前置：已持有镇静剂+针管且弦清醒（按钮仅在满足时显示，此处再次校验防越权）。
    -- 确认→写入 xianConscious="SEDATED"；放弃→不改动任何状态。已镇静则不再显示按钮，不会重入。
    -- 本批次不开放搜身/地图/手环/维持剂获取，不修改 finalChoice。
    if id == "useSedative" then
        -- P2FinalFlow 负责镇静与后续搜身流程。
        return P2FinalFlow.StartSedation()
    end

    -- 检查弦的物品（V1.0-07N-P2-B2-D，搜身入口，仅弦被镇静后开放）
    -- 前置：xianConscious == "SEDATED"（按钮仅在满足时显示，此处再次校验）。
    -- 两个热点：路线地图(A→hasMap + inventory.route_map) / 身份手环(B→hasBracelet + inventory.identity_bracelet)。
    -- 可重复进入：已取得的物品显示已取状态文本，不重复写入。
    -- 本批次不处理 finalChoice / P3 继承 / 授权核心替换。
    if id == "searchXian" then
        -- P2FinalFlow 负责镇静后的搜身流程。
        return P2FinalFlow.StartSearch()
    end

    if not clue then
        print("[DEBUG P2] OnP2ClinicClueClicked unknown id=" .. tostring(id))
        return
    end
    return P2ClinicClues.HandleNormalClinicClue(id, clue)
end

-- ----------------------------------------------------------------------------
-- P2 结算页面展示（V1.0-04F-C 迁移自 main.lua）
-- 函数名/参数/结算展示逻辑/Story2.ending 数据访问/ShowLongDialog 调用结构保持不变。
-- 仅把 GetP2() 改为 P2Context.Get()。
-- ----------------------------------------------------------------------------

-- 展示 P2 结算页面（V0.8-02 新增）
-- 读取 p2State_.result.choiceResult（玩家选择收束文本）+ Story2.ending.summary（章节总结）。
function ShowP2Ending()
    local p2 = P2Context.Get()
    if not p2 then return end
    print("[P2-END-UI] create ending button source=ShowP2Ending")
    local choiceResult = (p2.result and p2.result.choiceResult) or "（未记录选择）"
    local ending = Story2.ending or {}
    -- V1.0-07N-H3：按 p2.result.leafId 分流结算文案；缺失时回退到原 ending.summary。
    -- V1.0 P2 本批：最终只保留三类关系结局（endingId）；存活/死亡差异已废除，
    --   存在 endingId 时使用关系语义总结，不再读取含死亡表述的 branches[leafId]。
    local summary = ending.summary or ""
    local title = ending.title or "雪线诊所 · 结算"
    local resultEndingId = p2.result and p2.result.endingId
    if resultEndingId == "trustXian" then
        summary = "弦与你在清晨前的雪原中并肩而行。\n（与弦同行，关系结局 A。）"
    elseif resultEndingId == "leaveAlone" then
        summary = "你独自走出了那扇门。身后的诊所灯光渐渐远去。\n（独自离开，关系结局 B。）"
    elseif resultEndingId == "xianLeaves" then
        summary = "弦的背影消失在风雪深处。你留在了原地。\n（弦离开零，关系结局 C。）"
    else
        -- 兜底：无 endingId 时保留旧 leafId 分流（兼容旧存档）
        local leafId = p2.result and p2.result.leafId
        if leafId and ending.branches and ending.branches[leafId] then
            local branch = ending.branches[leafId]
            summary = branch.summary or summary
            title = branch.title or title
        end
    end
    local body = "【你的选择】\n" .. choiceResult
        .. "\n\n————————\n\n【章节总结】\n" .. summary
    local returnToTitleClicked = false
    local function ContinueToP3()
        if returnToTitleClicked or p2.flags.returnToTitleClicked == true then return end
        returnToTitleClicked = true
        p2.flags.returnToTitleClicked = true
        print("[P2-END-UI] continue button clicked")
        CloseDialog()
        config.continueToP3()
    end
    ShowLongDialog(title, body,
        { { label = "继续", variant = "primary", onClick = ContinueToP3 } })
end

-- ----------------------------------------------------------------------------
-- P2 会话态初始化（V1.0-04G-B-2 迁移自 main.lua 的 InitP2State 核心实现）
-- 职责：读取 RunState 信任度 → 创建 P2State → P2Context.Set → 应用 overrides → 状态日志。
-- 定义为全局函数（与 main 原有全局函数一致），EnterP2 / DEBUG 自测块以裸名继续调用。
-- DEBUG 注入子值由 main.lua 薄包装读取后以 overrides 参数传入，本模块不含 DEBUG 逻辑。
-- ----------------------------------------------------------------------------
function InitP2State(trustOverride, overrides)
    local currentRun = RunState.GetCurrent()
    local inheritedTrust = currentRun.xianTrust or 50
    if trustOverride ~= nil then
        inheritedTrust = trustOverride
    end

    local state = P2State.CreateP2InitialState(inheritedTrust)
    P2Context.Set(state)

    if overrides then
        if overrides.phase ~= nil then
            state.phase = overrides.phase
        end
        if overrides.patienceRemaining ~= nil then
            state.patienceRemaining = overrides.patienceRemaining
        end
        if type(overrides.inventory) == "table" then
            state.inventory = overrides.inventory
        end
    end

    print("[P2] State initialized")
    print("  trust:", state.xianTrust)
    print("  phase:", state.phase)
    print("  checkpoint:", state.checkpoint)

    return state
end

-- ----------------------------------------------------------------------------
-- P2 剧情入口编排（V1.0-04H-B 迁移自 main.lua 的 EnterP2）
-- 职责：按序编排 P2 进入流程（状态初始化 → 建立场景 → 进入隧道 → 播放开场）。
-- 定义为全局函数（与 main 原有全局函数一致），CheckChapterEntry 以裸名继续调用。
-- 本函数无 main 局部依赖（不读 p2State_ / uiRoot_ / DEBUG / GetP2()），迁移后调用点零改动。
-- ----------------------------------------------------------------------------
function EnterP2()
    print("[DEBUG ChapterEntry] >>> EnterP2() reached")

    InitP2State()

    BuildP2Scene()

    PlayP2Tunnel()

    PlayP2Opening()
end

-- ----------------------------------------------------------------------------
-- P2 诊所阶段流程（V1.0-04H-D 迁移自 main.lua 的 PlayP2Clinic）
-- 职责：设阶段/检查点 → 建立诊所场景 → 开场对白 → 8 个 DEBUG 自测块 + RunP2DebugExecutionEntries。
-- 定义为全局函数（与 main 原有全局一致），EnterP2Clinic 以裸名继续调用。
-- 本函数原 main 局部 GetP2() 改为 P2Context.Get()（与既有迁移范式一致）；其余逻辑/文本/DEBUG 行为不变。
-- ----------------------------------------------------------------------------
function PlayP2Clinic()
    local p2 = P2Context.Get()
    if not p2 then return end
    p2.phase = "CLINIC"
    p2.checkpoint = "P2_CLINIC_START"
    if not p2.flags.clinicEntered then
        p2.flags.clinicEntered = true
    end
    print("[DEBUG P2] >>> PlayP2Clinic() phase=CLINIC checkpoint=P2_CLINIC_START")
    print("[DEBUG P2] powerRestored=" .. tostring(p2.flags.powerRestored or false))
    -- 音乐任务2：P2 进入诊所 → 播放诊所背景音乐（覆盖隧道音乐，同一 musicId 防重复）
    BGMPlayer.Play("BGM_P2_CLINIC_AMBIENT_v01", { loop = true, gain = 0.28 })
    -- 建立诊所独立场景（与隧道场景架构一致，互不干扰）
    BuildP2ClinicScene()

    -- SCENE02 进入诊所对白：本批从 FinishP2Opening() 迁移至此（由玩家点击「进入诊所」触发）。
    -- 切换诊所场景后播放 scene02Dialog（三句对白仅播放一次），结束后直接弹出独立系统提示窗口。
    -- 注意：scene02Dialog 本身已包含「你先坐一会儿 / 我去找能用的物资 / 好。」三句，
    -- 原先在 onComplete 又用 ShowLongDialog(clinic.opening) 重播了同样三句，造成整段重复播放；
    -- 此处删除该重复播放，三句对白只播一次，随后进入系统提示。
    StartP2Dialogue(Story2.scene02Dialog, function()
        CloseDialog()
        -- 角色对白关闭后，弹出原有独立系统提示窗口（诊所调查开始 / 03:00），
        -- 玩家确认后由 ShowP2InvestigationStart 内部调用 StartP2Investigation() 启动调查与 Timer。
        ShowP2InvestigationStart()
    end, "诊所")

    -- V0.7-04-02B 至 V0.8-02 的八组 P2 诊所 DEBUG 自测统一由 p2debug.lua 执行。
    P2Debug.RunClinicSelfTests({
        getState = P2Context.Get,
        onClinicClueClicked = OnP2ClinicClueClicked,
        restorePower = RestoreP2Power,
        getTerminalClueData = function()
            return Story2.clinic.clues.terminal
        end,
        openTerminalFiles = OpenP2ClinicTerminalFiles,
        openMedicationRecords = OpenP2MedicationRecords,
        prepareFinalChoice = PrepareP2FinalChoice,
        enterFinalChoice = EnterP2FinalChoice,
        onFinalChoiceSelected = OnP2FinalChoiceSelected,
        initP2State = InitP2State,
        buildClinicScene = BuildP2ClinicScene,
        endP2 = EndP2,
        getRunState = RunState.GetCurrent,
        reloadRunState = RunState.Init,
    })
end

-- ----------------------------------------------------------------------------
-- P2 结算（V1.0-04H-F 迁移自 main.lua 的 EndP2）
-- 职责：校验 resultReady → 写结算态（phase/checkpoint/result.completed）→ 同步 RunState 写盘 → 展示结算页。
-- 定义为全局函数（与 main 原有全局一致），p2controller 内 L356/979/994 裸名调用继续生效。
-- 唯一替换：原 main 局部 GetP2() 改为 P2Context.Get()（与既有迁移范式一致）；其余逻辑/存档/结算不变。
-- ----------------------------------------------------------------------------
function EndP2(result)
    local p2 = P2Context.Get()
    if not p2 then
        print("[DEBUG P2] EndP2: p2State_ not initialized")
        return
    end
    if not p2.flags.resultReady then
        print("[DEBUG P2] EndP2: resultReady=false, skip (choice not made)")
        return
    end
    -- 允许外部传入覆盖（保留接口），否则沿用已保存的 result
    if result ~= nil then
        p2.result = result
    end
    p2.phase = "SETTLE"
    p2.checkpoint = "P2_COMPLETE"
    p2.result = p2.result or {}
    p2.result.completed = true
    print("[P2]\ncompleted=true")
    -- 同步 RunState：标记 P2 完成并写入 P2 → P3 的继承物品
    local runState = RunState.GetCurrent()
    runState.chapters.P2.completed = true
    runState.p2Entry = runState.p2Entry or {}
    runState.p2Entry.route_map = p2.inventory and p2.inventory.route_map == true
    runState.p2Entry.identity_bracelet = p2.inventory and p2.inventory.identity_bracelet == true
    RunState.Save()
    -- 展示结算页面
    ShowP2Ending()
end

-- 最终流程模块配置：仅注入最终阶段实际使用的状态、对白、Dialog、区域重建与结算回调。
P2FinalFlow.Configure({
    getState = P2Context.Get,
    showDialog = function(title, body, buttons)
        ShowDialog(title, body, buttons)
    end,
    closeDialog = function()
        CloseDialog()
    end,
    startDialogue = StartP2Dialogue,
    buildClinicScene = BuildP2ClinicScene,
    endP2 = EndP2,
    consumePatience = ConsumeP2Patience,
    registerXianQuestion = RegisterP2XianQuestion,
    logDialogState = function(tag)
        LogP2DialogState(tag)
    end,
    addXianTrust = function(delta)
        if type(AddXianTrust) == "function" then
            AddXianTrust(delta)
        end
    end,
    getXianTrust = function()
        if type(GetXianTrust) == "function" then
            return GetXianTrust()
        end
        return nil
    end,
    refreshSearchHotspots = function()
        RefreshP2SearchHotspots()
    end,
})

-- 终端模块配置：区分全局对话记录与诊所电脑文件两套数据源。
P2Terminal.Configure({
    getState = P2Context.Get,
    closeDialog = function()
        CloseDialog()
    end,
    showDialog = function(title, body, buttons)
        ShowDialog(title, body, buttons)
    end,
    showLongDialog = function(title, body, buttons)
        ShowLongDialog(title, body, buttons)
    end,
    showRestClueDialog = function(title, body, buttons)
        ShowRestClueDialog(title, body, buttons)
    end,
    startDialogue = StartP2Dialogue,
    playMemory = function(steps, onComplete, title)
        PlayP2Memory01(steps, onComplete)
    end,
    consumePatience = ConsumeP2Patience,
    registerXianQuestion = RegisterP2XianQuestion,
    getRoot = function()
        return UI.GetRoot() or p2ClinicRoot_ or p2Root_
    end,
})

-- 场景 UI 模块配置：静态 UI 只接收最小点击回调与挂载依赖。
P2SceneUI.Configure({
    onTunnelClueClick = function(id)
        OnP2TunnelClueClicked(id)
    end,
    onEnterClinic = function()
        EnterP2Clinic()
    end,
    onClinicClueClick = function(id)
        OnP2ClinicClueClicked(id)
    end,
    onSearchHotspotClick = function(itemKey)
        OnP2SearchHotspotClicked(itemKey)
    end,
    onScan = function(button)
        OnP2ScanClicked(button)
    end,
    decorateButton = P2FeedbackDecorator,
    onOpenRecords = function()
        P2Terminal.OpenRecords()
    end,
    onSwitchScene = function(target)
        BuildP2ClinicScene(target)
    end,
    createRecordButton = function(onOpen, options)
        return P2Terminal.CreateRecordButton(onOpen, options)
    end,
    createDialog = function()
        return CreateDialog()
    end,
    closeDialog = function()
        CloseDialog()
    end,
    setRoot = function(root)
        UI.SetRoot(root)
    end,
    buildScanLayer = function()
        return ScanFX.BuildLayer()
    end,
    buildScanStatusLayer = function()
        return ScanStatus.BuildLayer()
    end,
    createDebugStatusPanel = function()
        return P2_DEBUG_STATUS_PANEL and CreateP2DebugStatusPanel()
            or UI.Panel { width = 0, height = 0, visible = false }
    end,
    addDynamicClinicChildren = AddP2DynamicClinicChildren,
})

-- 药柜模块配置：仅注入其实际使用的正式函数与当前 UI 根。
P2Cabinet.Configure({
    getState = P2Context.Get,
    closeDialog = function()
        CloseDialog()
    end,
    showDialog = function(title, body, buttons)
        ShowDialog(title, body, buttons)
    end,
    showLongDialog = function(title, body, buttons)
        ShowLongDialog(title, body, buttons)
    end,
    showRestClueDialog = function(title, body, buttons)
        ShowRestClueDialog(title, body, buttons)
    end,
    startDialogue = StartP2Dialogue,
    consumePatience = ConsumeP2Patience,
    registerXianQuestion = RegisterP2XianQuestion,
    getClinicRoot = function()
        return p2ClinicRoot_ or p2Root_
    end,
})

P2ClinicClues.Configure({
    getState = P2Context.Get,
    showDialog = function(title, body, buttons)
        ShowDialog(title, body, buttons)
    end,
    closeDialog = function()
        CloseDialog()
    end,
    showCompactDialog = function(title, body, buttons)
        ShowCompactDialog(title, body, buttons)
    end,
    showRestClueDialog = function(title, body, buttons)
        ShowRestClueDialog(title, body, buttons)
    end,
    showClinicClueImage = ShowP2ClinicClueImage,
    registerRestClueViewed = RegisterRestClueViewed,
    checkClinicExploreComplete = CheckP2ClinicExploreComplete,
    addXianTrust = function(delta)
        if type(AddXianTrust) == "function" then
            AddXianTrust(delta)
        end
    end,
    startDialogue = StartP2Dialogue,
    consumePatience = ConsumeP2Patience,
    registerXianQuestion = RegisterP2XianQuestion,
    getClinicRoot = function()
        return p2ClinicRoot_ or p2Root_
    end,
    switchScene = BuildP2ClinicScene,
})

return P2Controller
