-- ============================================================================
-- scripts/p2finalflow.lua
-- 《零点之后》第二关「雪线诊所」最终阶段控制模块
--
-- 负责最终处理、镇静、搜身、食物事件、最终选择与结局分流。
-- 正式 P2 状态和 EndP2/RunState 所有权仍由 controller/state 持有；本模块
-- 通过 Configure 注入最小运行依赖，不反向依赖 p2controller.lua。
-- ============================================================================

local Story2 = require("story2")
local BGMPlayer = require("bgmplayer")

local P2FinalFlow = {}
local config = {}

---@type function
local PrepareP2FinalTreatment
---@type function
local ShowP2FinalTreatmentChoice
---@type function
local PrepareP2FinalChoice
---@type function
local BeginP2SedateXianFlow
---@type function
local ShowP2SearchXianFlow
---@type function
local StartP2FoodEvent
---@type function
local PlayP2FoodEvent
---@type function
local ShowP2FoodChoice
---@type function
local PlayP2FoodBranch
---@type function
local FinishP2FoodEvent
---@type function
local HandleP2RefuseCollapse
---@type function
local PlayP2RefuseOutcome
---@type function
local EnterP2FinalChoice
---@type function
local EvaluateP2FinalLeaf
---@type function
local ClassifyP2FinalEnding
---@type function
local PlayP2EndingSequence
---@type function
local OnP2FinalChoiceSelected

function P2FinalFlow.Configure(newConfig)
    config = newConfig
end

local function GetP2State()
    return config.getState()
end

local function ShowDialog(title, body, buttons)
    return config.showDialog(title, body, buttons)
end

local function CloseDialog()
    return config.closeDialog()
end

local function StartP2Dialogue(steps, onComplete, title)
    return config.startDialogue(steps, onComplete, title)
end

local function BuildP2ClinicScene(area)
    return config.buildClinicScene(area)
end

local function EndP2(result)
    return config.endP2(result)
end

local function ConsumeP2Patience()
    return config.consumePatience()
end

local function RegisterP2XianQuestion(sourceId, onMemoryComplete, patienceBefore)
    return config.registerXianQuestion(sourceId, onMemoryComplete, patienceBefore)
end

local function LogP2DialogState(tag)
    if config.logDialogState then
        return config.logDialogState(tag)
    end
end

local function AddXianTrust(delta)
    if config.addXianTrust then
        return config.addXianTrust(delta)
    end
end

local function GetXianTrust()
    if config.getXianTrust then
        local trust = config.getXianTrust()
        if trust ~= nil then
            return trust
        end
    end
    return 50
end

-- P2 最终处理阶段（V1.0 P2 本批新增：倒计时结束 → 正式去留选择之间的基础机制）
-- 仅搭阶段入口与第一层选择；镇静确认 / 搜身 / 结局逻辑下一轮迁移。
-- PrepareP2FinalTreatment：置 finalTreatmentReady 并展示最终处理选择窗口。
-- ShowP2FinalTreatmentChoice：【暂不使用镇静剂】常驻；【使用短效镇静剂】仅当
--   hasSedative && hasSyringe && xianConscious=="SOBER" 时显示（本轮仅临时回调）。
-- 两个选项最终都汇入现有 PrepareP2FinalChoice() → 【立即离开 / 留到清晨】。
-- ----------------------------------------------------------------------------
PrepareP2FinalTreatment = function()
    local p2 = GetP2State()
    if not p2 then return end
    p2.flags = p2.flags or {}
    -- 防重复（本批）：探索完成支路与倒计时归零支路都可能进入，仅首次展示最终处理窗口
    --（独立 finalTreatmentShown 锁，不复用 finalTreatmentReady / 不影响 finalChoiceReady）
    if p2.flags.finalTreatmentShown == true then
        print("[P2-FINAL-TREATMENT] already shown, skip")
        return
    end
    p2.flags.finalTreatmentShown = true
    p2.flags.finalTreatmentReady = true
    print("[P2]\nready for final treatment")
    -- TEMP DEBUG：进入最终处理前对话层状态（发布前删除）
    LogP2DialogState("before_final_treatment")
    ShowP2FinalTreatmentChoice()
end

ShowP2FinalTreatmentChoice = function()
    local p2 = GetP2State()
    if not p2 then return end
    local buttons = {}
    -- V1.0 P2 本批：REFUSE 昏迷收口后，零已昏迷——不允许再镇静弦，仅显示【继续】进入去留选择
    local refuseCollapsed = (p2.flags and p2.flags.refuseCollapseHandled == true)
    -- 条件镇静选项：仅持有镇静剂+针管且弦清醒且非 REFUSE 昏迷收口时显示（正式镇静+搜身连续流程）
    if p2.hasSedative == true and p2.hasSyringe == true and p2.xianConscious == "SOBER"
        and refuseCollapsed ~= true then
        buttons[#buttons + 1] = {
            label = "使用短效镇静剂",
            variant = "default",
            onClick = function()
                print("[P2-FINAL-TREATMENT] sedative selected")
                CloseDialog()
                -- 防重：搜身已完成（或已镇静）后不得再次使用镇静剂，直接进入去留选择
                local pd = GetP2State()
                if pd and pd.flags and pd.flags.finalSearchCompleted == true then
                    print("[P2-FINAL-TREATMENT] proceed to final choice")
                    PrepareP2FinalChoice()
                    return
                end
                -- 正式流程：确认 → SEDATED → 搜身 → 完整结束后进入去留选择
                BeginP2SedateXianFlow(
                    function()
                        print("[P2-FINAL-TREATMENT] proceed to final choice")
                        CloseDialog()
                        PrepareP2FinalChoice()
                    end,
                    function()
                        -- 玩家放弃：返回【最终处理】选择窗，不修改任何状态
                        ShowP2FinalTreatmentChoice()
                    end)
            end,
        }
    end
    -- 基础按钮：暂不使用镇静剂（REFUSE 昏迷收口后改显示【继续】）→ 直接进入原有去留选择
    buttons[#buttons + 1] = {
        label = refuseCollapsed and "继续" or "暂不使用镇静剂",
        variant = "primary",
        onClick = function()
            CloseDialog()
            PrepareP2FinalChoice()
        end,
    }
    ShowDialog("最终处理",
        "暴风雪仍未停止。\n离开之前，\n你必须决定如何处理弦目前的状态。",
        buttons)
end

-- 准备最终抉择（V0.7-08 新增，V0.7-09 串联进入选择）
-- 置 finalChoiceReady，并直接进入最终选择界面（事件「继续」后衔接）。
PrepareP2FinalChoice = function()
    local p2 = GetP2State()
    if not p2 then return end
    p2.flags.finalChoiceReady = true
    print("[P2]\nready for final choice")
    -- V0.7-09：进入最终选择界面（内部校验 finalChoiceReady，已就绪才展示）
    EnterP2FinalChoice()
end

-- ----------------------------------------------------------------------------
-- P2 正式镇静弦流程（V1.0 P2 本批：自旧 useSedative 常驻分支提取，供【最终处理】阶段复用）
-- BeginP2SedateXianFlow(onComplete, onCancel)：
--   确认窗 → 取消：onCancel（缺省仅 CloseDialog，不改状态）；
--          → 确认：xianConscious="SEDATED" → 成功提示 → 连续进入搜身 ShowP2SearchXianFlow(onComplete)。
-- 数据来源与文本不变（Story2.clinic.restEvents.useSedative）。
-- ----------------------------------------------------------------------------
BeginP2SedateXianFlow = function(onComplete, onCancel)
    local p = GetP2State()
    if not p or not p.hasSedative or not p.hasSyringe or p.xianConscious ~= "SOBER" then
        print("[DEBUG P2] useSedative ignored (precondition not met)")
        CloseDialog()
        if onCancel then onCancel() end
        return
    end
    local us = Story2.clinic.restEvents and Story2.clinic.restEvents.useSedative
    ShowDialog(us and us.title or "使用短效镇静剂", us and us.confirmText or "是否使用？",
        {
            { label = "确认使用", variant = "default", onClick = function()
                p.xianConscious = "SEDATED"
                if config.refreshSearchHotspots then
                    config.refreshSearchHotspots()
                end
                print("[P2] xianConscious -> SEDATED")
                print("[P2-FINAL-TREATMENT] xian sedated")
                -- 成功提示后连续进入搜身流程（不再以"返回诊所"终止）
                ShowDialog(us and us.title or "使用短效镇静剂", us and us.successText or "弦已进入镇静状态。",
                    { { label = "继续", variant = "primary", onClick = function()
                        CloseDialog()
                        local successDialogue = us and us.successDialogue or {}
                        if #successDialogue > 0 then
                            StartP2Dialogue(successDialogue, function()
                                CloseDialog()
                                ShowP2SearchXianFlow(onComplete)
                            end, us and us.title or "使用短效镇静剂")
                        else
                            ShowP2SearchXianFlow(onComplete)
                        end
                    end } })
            end },
            { label = "放弃", variant = "default", onClick = function()
                CloseDialog()
                if onCancel then onCancel() end
            end },
        })
end

-- ----------------------------------------------------------------------------
-- P2 搜身流程（V1.0 P2 本批：自旧 searchXian 常驻分支提取，供镇静后连续流程复用）
-- ShowP2SearchXianFlow(onComplete)：
--   二级菜单：路线地图(A→hasMap + inventory.route_map) / 身份手环(B→hasBracelet + inventory.identity_bracelet) / 返回(C→结束)。
--   可重复进入：已取得物品显示已取状态，不重复写入；物品详情「返回」回到菜单（可收齐）。
--   场景热点与二级菜单共用同一套一次性获得逻辑。
--   菜单「返回」= 完整结束：置一次性 finalSearchCompleted，输出汇总日志，调用 onComplete（缺省仅 CloseDialog）。
-- 数据来源与文本不变（Story2.clinic.restEvents.searchXian）。
-- ----------------------------------------------------------------------------
ShowP2SearchXianFlow = function(onComplete)
    local p = GetP2State()
    if not p or p.xianConscious ~= "SEDATED" then
        print("[DEBUG P2] searchXian ignored (xian not SEDATED)")
        CloseDialog()
        if onComplete then onComplete() end
        return
    end
    local sx = Story2.clinic.restEvents and Story2.clinic.restEvents.searchXian
    if not sx then
        print("[DEBUG P2] searchXian: no data")
        CloseDialog()
        if onComplete then onComplete() end
        return
    end
    local finished = false
    local function Finish()
        if finished then return end
        finished = true
        if p.flags then p.flags.finalSearchCompleted = true end
        print(string.format(
            "[P2-FINAL-TREATMENT] search complete map=%s bracelet=%s soberAgent=%s",
            tostring(p.hasMap), tostring(p.hasBracelet), tostring(p.hasSoberAgent)))
        CloseDialog()
        -- TEMP DEBUG：搜身收口关闭对话后的对话层状态（发布前删除）
        LogP2DialogState("search_closed")
        if onComplete then onComplete() end
    end
    -- 物品详情「返回」回到菜单（可继续收齐其余物品）
    local function ItemDialog(item, field, inventoryKey)
        local owned = p[field] == true
            or (p.inventory and p.inventory[inventoryKey] == true)
        if owned then
            p[field] = true
            p.inventory = p.inventory or {}
            p.inventory[inventoryKey] = true
            ShowDialog(item.title, item.takenText or "已取得。",
                { { label = "返回", variant = "primary", onClick = function()
                    CloseDialog()
                    ShowP2SearchXianFlow(onComplete)
                end } })
        else
            p[field] = true
            p.inventory = p.inventory or {}
            p.inventory[inventoryKey] = true
            print("[P2] searchXian " .. tostring(field) .. " -> true inventory=" .. tostring(inventoryKey))
            local itemDialogue = item.dialogue or {}
            local function ShowTakenResult()
                ShowDialog(item.title, item.takenText or "已取得。",
                    { { label = "返回", variant = "primary", onClick = function()
                        CloseDialog()
                        ShowP2SearchXianFlow(onComplete)
                    end } })
            end
            if #itemDialogue > 0 then
                StartP2Dialogue(itemDialogue, ShowTakenResult, item.title)
            else
                ShowTakenResult()
            end
        end
    end
    ShowDialog(sx.title or "检查弦的物品", sx.menuText or "要检查弦的哪里？",
        {
            { label = sx.outerwear and sx.outerwear.title or "路线地图", variant = "default", onClick = function()
                ItemDialog(sx.outerwear or {}, "hasMap", "route_map")
            end },
            { label = sx.wrist and sx.wrist.title or "身份手环", variant = "default", onClick = function()
                ItemDialog(sx.wrist or {}, "hasBracelet", "identity_bracelet")
            end },
            { label = "返回", variant = "default", onClick = function()
                Finish()
            end },
        })
end

local function SearchP2SingleItem(itemKey, onComplete)
    local p = GetP2State()
    if not p or p.xianConscious ~= "SEDATED" then
        print("[DEBUG P2] search hotspot ignored (xian not SEDATED)")
        CloseDialog()
        return
    end
    local sx = Story2.clinic.restEvents and Story2.clinic.restEvents.searchXian
    local item
    local field
    if itemKey == "route_map" then
        item = sx and sx.outerwear
        field = "hasMap"
    elseif itemKey == "identity_bracelet" then
        item = sx and sx.wrist
        field = "hasBracelet"
    end
    if not item or not field then
        print("[DEBUG P2] unknown search hotspot item=" .. tostring(itemKey))
        return
    end
    local owned = p[field] == true
        or (p.inventory and p.inventory[itemKey] == true)
    if not owned then
        p[field] = true
        p.inventory = p.inventory or {}
        p.inventory[itemKey] = true
        print("[P2] search hotspot acquired " .. tostring(itemKey))
    else
        p[field] = true
        p.inventory = p.inventory or {}
        p.inventory[itemKey] = true
    end
    ShowDialog(item.title, owned and (item.takenText or "已取得。") or (item.text or ""), {
        { label = "返回诊所", variant = "primary", onClick = function()
            CloseDialog()
            if onComplete then onComplete() end
        end },
    })
end

-- 场景热点直接打开对应道具详情；入口仍由 SEDATED 状态再次校验。
P2FinalFlow.SearchItem = SearchP2SingleItem

-- ----------------------------------------------------------------------------
-- P2 食物事件（V1.0 P2 本批新增第一阶段：主倒计时剩余 90 秒自动触发 → 弦递罐头 → 三选一）
-- 状态：foodEventTriggered（一次性触发）/ foodEventActive（事件期间暂停主倒计时）/
--       foodChoice（EAT_NOW / EAT_LATER / REFUSE）/ foodEventReturnArea（返回区域）
-- A 现在吃：zeroStable/medicalProxy/foodConsumed=true、信任+5、主倒计时重置 180（三分钟休息互动阶段）
-- B 等会儿再吃：exhaustionPending=true、信任-5、保留剩余耐心（隐藏 60 秒衰竭下一轮实现）
-- C 不吃：exhaustionPending/foodRefused=true、信任-10、耐心清零（结局倾向下一轮经 GetXianTrust 判定，本轮只存状态）
-- ----------------------------------------------------------------------------
StartP2FoodEvent = function()
    local p2 = GetP2State()
    if not p2 then return end
    p2.flags = p2.flags or {}
    -- 防重复：已触发 / 已有选择 / 已收口 / 已进入最终处理 → 不再触发
    if p2.flags.foodEventTriggered == true or p2.flags.foodChoice ~= nil
        or p2.flags.clinicPhaseOneComplete == true or p2.flags.finalTreatmentShown == true then
        return
    end
    p2.flags.foodEventTriggered = true
    p2.flags.foodEventActive = true
    if p2.flags.foodEventRemainingTime == nil then
        p2.flags.foodEventRemainingTime = p2.clinicTimeRemaining
    end
    p2.flags.foodEventReturnArea = p2.clinicArea or "HALL"
    print(string.format("[P2-FOOD] triggered remaining=%s area=%s",
        tostring(p2.clinicTimeRemaining and math.ceil(p2.clinicTimeRemaining)),
        tostring(p2.flags.foodEventReturnArea)))
    PlayP2FoodEvent()
end

PlayP2FoodEvent = function()
    local fe = Story2.foodEvent
    local p2 = GetP2State()
    if not fe or not p2 then
        if p2 and p2.flags then p2.flags.foodEventActive = false end
        return
    end
    StartP2Dialogue(fe.opening or {}, function()
        CloseDialog()
        ShowP2FoodChoice()
    end, fe.title or "营养罐头")
end

ShowP2FoodChoice = function()
    local fe = Story2.foodEvent
    local p2 = GetP2State()
    if not fe or not p2 then return end
    local buttons = {}
    for _, c in ipairs(fe.choices or {}) do
        buttons[#buttons + 1] = {
            label = c.label,
            variant = (c.id == "EAT_NOW") and "primary" or "default",
            onClick = function()
                CloseDialog()
                PlayP2FoodBranch(c.id)
            end,
        }
    end
    ShowDialog(fe.title or "营养罐头", "要如何回应？", buttons)
end

PlayP2FoodBranch = function(choiceId)
    local fe = Story2.foodEvent
    if not fe then
        FinishP2FoodEvent(choiceId)
        return
    end
    local steps = choiceId == "EAT_NOW" and fe.eatNow
        or choiceId == "EAT_LATER" and fe.eatLater
        or choiceId == "REFUSE" and fe.refuse
        or nil
    if not steps or #steps == 0 then
        FinishP2FoodEvent(choiceId)
        return
    end
    StartP2Dialogue(steps, function()
        CloseDialog()
        FinishP2FoodEvent(choiceId)
    end, fe.title or "营养罐头")
end

FinishP2FoodEvent = function(choiceId)
    local p2 = GetP2State()
    if not p2 then return end
    p2.flags = p2.flags or {}
    p2.flags.foodChoice = choiceId
    p2.flags.foodEventActive = false
    if choiceId == "EAT_NOW" then
        p2.flags.zeroStable = true
        p2.flags.medicalProxy = true
        p2.flags.foodConsumed = true
        if type(AddXianTrust) == "function" then AddXianTrust(5) end
        p2.clinicTimeRemaining = p2.flags.foodEventRemainingTime or p2.clinicTimeRemaining
        print("[P2-FOOD] timer resumed remaining=" .. tostring(p2.clinicTimeRemaining))
    elseif choiceId == "EAT_LATER" then
        p2.flags.zeroStable = false
        p2.flags.foodConsumed = false
        p2.flags.exhaustionPending = true
        if type(AddXianTrust) == "function" then AddXianTrust(-5) end
        -- V1.0 P2 本批：启动 10 秒隐藏衰竭倒计时（3 秒警告；归零昏倒进入最终处理）
        p2.flags.exhaustionActive = true
        p2.flags.exhaustionRemaining = 10
        p2.flags.exhaustionWarningPlayed = false
        p2.flags.exhaustionCollapsed = false
        p2.clinicTimeRemaining = p2.flags.foodEventRemainingTime or p2.clinicTimeRemaining
        print("[P2-FOOD] exhaustion started remaining=10")
    else -- REFUSE
        p2.flags.zeroStable = false
        p2.flags.foodConsumed = false
        p2.flags.exhaustionPending = true
        p2.flags.foodRefused = true
        if type(AddXianTrust) == "function" then AddXianTrust(-10) end
        -- 弦本关剩余耐心清零（复用现有 patienceRemaining 字段，不新增重复字段）
        p2.patienceRemaining = 0
        -- REFUSE 同样进入隐藏衰竭倒计时，但不提供补救按钮；归零后复用 EAT_LATER 直达 C 收口
        p2.flags.exhaustionActive = true
        p2.flags.exhaustionRemaining = 10
        p2.flags.exhaustionWarningPlayed = false
        p2.flags.exhaustionCollapsed = false
        p2.clinicTimeRemaining = p2.flags.foodEventRemainingTime or p2.clinicTimeRemaining
        print("[P2-FOOD] exhaustion started remaining=10 choice=REFUSE")
        BuildP2ClinicScene(p2.flags.foodEventReturnArea or "HALL")
        return
    end
    print(string.format("[P2-FOOD] choice=%s trust=%s",
        tostring(choiceId),
        tostring(type(GetXianTrust) == "function" and GetXianTrust() or "?")))
    -- 返回事件触发前所在区域（默认 HALL）
    local retArea = p2.flags.foodEventReturnArea or "HALL"
    BuildP2ClinicScene(retArea)
end

-- ----------------------------------------------------------------------------
-- P2 REFUSE 拒食昏迷 → 信任分流（V1.0 P2 本批新增）
-- 昏迷演出只播一次（refuseCollapseHandled）；随后按真实 GetXianTrust() 分流：
--   trust < 35  → XIAN_LEAVES：弦离开，forceEndingId="xianLeaves"（强制 C）；
--   trust >= 35 → XIAN_RESCUES：弦返回救治，medicalProxy/zeroStable=true。
-- 两条结局演出完成后均进入 PrepareP2FinalTreatment()（REFUSE 下不显示镇静选项）。
-- 不写任何死亡/存活字段。
-- ----------------------------------------------------------------------------
HandleP2RefuseCollapse = function()
    local p2 = GetP2State()
    if not p2 or not p2.flags then return end
    if p2.flags.refuseCollapseHandled == true then return end
    p2.flags.refuseCollapseHandled = true
    print("[P2-FOOD] refuse collapse")
    local cr = Story2.foodEvent and Story2.foodEvent.collapseRefuse
    StartP2Dialogue((cr and cr.steps) or {}, function()
        CloseDialog()
        local trust = 50
        if type(GetXianTrust) == "function" then trust = GetXianTrust() or 50 end
        if trust < 35 then
            p2.flags.refuseOutcome = "XIAN_LEAVES"
            p2.flags.forceEndingId = "xianLeaves"
            p2.flags.medicalProxy = false
            p2.flags.zeroStable = false
            print("[P2-FOOD] refuse outcome=XIAN_LEAVES trust=" .. tostring(trust))
            PlayP2RefuseOutcome("refuseXianLeaves")
        else
            p2.flags.refuseOutcome = "XIAN_RESCUES"
            p2.flags.medicalProxy = true
            p2.flags.zeroStable = true
            p2.flags.foodConsumed = false
            p2.flags.forceEndingId = nil
            print("[P2-FOOD] refuse outcome=XIAN_RESCUES trust=" .. tostring(trust))
            PlayP2RefuseOutcome("refuseXianRescues")
        end
    end, "营养罐头")
end

PlayP2RefuseOutcome = function(nodeKey)
    local node = Story2.foodEvent and Story2.foodEvent[nodeKey]
    StartP2Dialogue((node and node.steps) or {}, function()
        CloseDialog()
        PrepareP2FinalTreatment()
    end, "营养罐头")
end

-- 进入最终选择界面（V0.7-09 新增）
-- 仅当 finalChoiceReady=true 时读取 Story2.finalChoice 并展示选项弹窗；
-- 否则直接返回（不允许未就绪进入选择）。
EnterP2FinalChoice = function()
    local p2 = GetP2State()
    if not p2 then return end
    if not p2.flags.finalChoiceReady then
        print("[DEBUG P2] EnterP2FinalChoice: finalChoiceReady=false, skip")
        return
    end
    local fc = Story2.finalChoice
    if not fc or not fc.options then
        print("[DEBUG P2] EnterP2FinalChoice: no finalChoice data")
        return
    end
    local buttons = {}
    for i = 1, #fc.options do
        local opt = fc.options[i]
        buttons[#buttons + 1] = {
            label = opt.text,
            variant = "default",
            onClick = function()
                OnP2FinalChoiceSelected(opt.id)
            end,
        }
    end
    print("[DEBUG P2] EnterP2FinalChoice: showing " .. tostring(#buttons) .. " options")
    ShowDialog(fc.title, "你需要做出选择。", buttons)
end

-- 最终选择结局叶求值（V1.0-07N-H2 新增，独立辅助函数）
-- 根据当前 p2 状态，在指定顶层选项的 sub 子分支表中选取匹配的 leaf。
-- 仅做状态读取与条件描述匹配，不新增 state 字段 / 不新增 flag / 不写存档。
-- @param choiceId string 顶层选项 id（leave_now / stay_dawn）
-- @return table|nil 匹配的 leaf（含 leafId / endingText / isDeath）；无匹配返回 nil
EvaluateP2FinalLeaf = function(choiceId)
    local p2 = GetP2State()
    if not p2 then return nil end
    local fc = Story2.finalChoice
    if not fc or not fc.options then return nil end
    local sub = nil
    for i = 1, #fc.options do
        if fc.options[i].id == choiceId then
            sub = fc.options[i].sub
            break
        end
    end
    if not sub then return nil end
    for i = 1, #sub do
        local leaf = sub[i]
        local cond = leaf.condition
        if cond then
            local ok = true
            if cond.xianConscious ~= nil and (p2.xianConscious or "SOBER") ~= cond.xianConscious then ok = false end
            if ok and cond.hasMap ~= nil and (p2.hasMap or false) ~= cond.hasMap then ok = false end
            if ok and cond.hasBracelet ~= nil and (p2.hasBracelet or false) ~= cond.hasBracelet then ok = false end
            if ok and cond.hasSoberAgent ~= nil and (p2.hasSoberAgent or false) ~= cond.hasSoberAgent then ok = false end
            if ok and cond.fireLit ~= nil and (p2.flags.fireLit or false) ~= cond.fireLit then ok = false end
            if ok and cond.medicalProxy ~= nil and (p2.medicalProxy or false) ~= cond.medicalProxy then ok = false end
            if ok then return leaf end
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- P2 最终结局归类（V1.0 P2 本批：删除存活/死亡差异，统一三类关系结局）
--   A trustXian  相信弦，与弦同行（零与弦一同离开）
--   B leaveAlone 不相信弦，独自离开（零独行，弦未同行）
--   C xianLeaves 关系恶化，弦离开零（弦拒绝同行，独自离开）
-- 优先级：先判 C（仅弦清醒时可能），再判镇静（B），最后 A。
-- 恶化阈值 xianTrust < 35：沿用 patienceTier 既有"<35 → 低信任/对立张力"分界
--（p2state.lua:19-23）；初始 50，需净损失 ≥15（多次明显伤害，如还书-3＋质问-6 等叠加），
-- 单次普通提问(-1)或单次质问(-6)均无法触发。
-- 道具（hasMap/hasBracelet/hasSoberAgent/fireLit/medicalProxy）不再决定结局类别，仅供过程表现与 P3 继承。
-- @return table { endingId = "trustXian"|"leaveAlone"|"xianLeaves", endingTitle = string }
ClassifyP2FinalEnding = function(choiceId)
    local p2 = GetP2State()
    -- V1.0 P2 本批：REFUSE 低信任强制结局（唯一允许的 forceEndingId），优先于一切常规判定
    if p2 and p2.flags and p2.flags.forceEndingId == "xianLeaves" then
        return { endingId = "xianLeaves", endingTitle = "弦离开零" }
    end
    -- V1.0 P2 修复：关系值真实来源是 main 的 xianTrust_（GetXianTrust 全局读访问），
    -- p2 state 中不存在 xianTrust 字段（仅 initialTrust 快照）——旧读法恒回退 50 导致 C 不可达。
    local trust = 50
    if type(GetXianTrust) == "function" then
        trust = GetXianTrust() or 50
    elseif p2 and p2.xianTrust then
        trust = p2.xianTrust
    end
    -- 1) C：弦保持清醒但关系严重恶化 → 弦离开零
    if p2 and p2.xianConscious == "SOBER" and trust < 35 then
        return { endingId = "xianLeaves", endingTitle = "弦离开零" }
    end
    -- 2) B：弦被镇静（或最终处理阶段使用镇静剂）→ 零独自离开
    if p2 and p2.xianConscious == "SEDATED" then
        return { endingId = "leaveAlone", endingTitle = "独自离开" }
    end
    -- 3) A：弦清醒且关系未恶化 → 相信弦，与弦同行（leave_now / stay_dawn 均可进入，仅过程文案不同）
    return { endingId = "trustXian", endingTitle = "相信弦，与弦同行" }
end

-- 三类关系结局的统一收束文案（仅关系语义，不含死亡/存活/道具失败表述）
local P2_ENDING_SUMMARY = {
    trustXian = "你选择相信弦。风雪未停，你们一同离开了诊所。（关系结局：与弦同行）",
    leaveAlone = "你没有再相信弦。剩下的事，你决定独自面对。（关系结局：独自离开）",
    xianLeaves = "弦看了你最后一眼，转身走进风雪，没有再回头。（关系结局：弦离开零）",
}

-- P2 关系结局演出播放器（V1.0 P2 本批新增）
-- 复用现有 StartOpeningDialogue（steps + 标题 + onComplete），不新写对话系统。
--   · endingId → Story2.p2Endings[endingId]（trustXian / leaveAlone / xianLeaves）
--   · 每页标题使用节点 title；narration 只显示文本，speaker 台词显示角色名与文本
--   · 不修改 endingId / 关系值 / 道具 / P3 状态；不播放 enterP3，不跳转 P3
--   · endingId 无对应节点：打日志后直接 onComplete（不报错、不阻断结算）
PlayP2EndingSequence = function(endingId, onComplete)
    local node = Story2.p2Endings and Story2.p2Endings[endingId]
    if not node or type(node.steps) ~= "table" or #node.steps == 0 then
        print("[P2-ENDING] missing sequence: " .. tostring(endingId))
        if onComplete then onComplete() end
        return
    end
    -- 音乐任务2：P2 结局确定后 → 播放暴风雪结局音乐（结局演出正式开始）
    BGMPlayer.Play("BGM_P2_ENDING_BLIZZARD_v01", { loop = true, gain = 0.28 })
    StartP2Dialogue(node.steps, function()
        CloseDialog()
        if onComplete then onComplete() end
    end, node.title or "结局")
end

-- 处理最终选择（V0.7-09 新增，V0.8-01 扩充结果 flag / resultReady）
-- 保存选择结果到 p2State_（flags.finalChoiceSelected + 具体选项标记 + result + resultReady），
-- 展示对应 resultText，更新 checkpoint=P2_FINAL_CHOICE_SELECTED。
-- 已选择后重复进入不会覆盖已有结果（OnP2FinalChoiceSelected 直接返回）。
OnP2FinalChoiceSelected = function(choiceId)
    local p2 = GetP2State()
    if not p2 then return end
    if p2.flags.finalChoiceSelected then
        print("[DEBUG P2] OnP2FinalChoiceSelected: already selected=" .. tostring(p2.result.choice) .. ", skip")
        return
    end
    -- V1.0-07N-H2：优先按 sub 结局叶求值（剧本§8 结构）；无匹配叶时回退到旧 resultText。
    -- V1.0 P2 本批：最终只保留三类关系结局（A/B/C），删除存活/死亡差异；
    --   叶仅保留 leafId 供追溯，展示文案统一改用关系语义（不再读取含死亡表述的 endingText）。
    local leaf = EvaluateP2FinalLeaf(choiceId)
    local ending = ClassifyP2FinalEnding(choiceId)
    local resultText = P2_ENDING_SUMMARY[ending.endingId] or "（未知选项）"
    if not leaf then
        local fc = Story2.finalChoice
        if fc and fc.options then
            for i = 1, #fc.options do
                if fc.options[i].id == choiceId then
                    -- 兜底仅保留 choiceResult 兼容路径（正常情况不会走到）
                    resultText = resultText ~= "（未知选项）" and resultText or fc.options[i].resultText
                    break
                end
            end
        end
    end
    -- 互斥选项标记使用与 Story2.finalChoice 一致的语义名称。
    p2.flags.finalChoiceSelected = true
    p2.flags.leaveNowSelected = (choiceId == "leave_now")
    p2.flags.stayDawnSelected = (choiceId == "stay_dawn")
    -- 同步 result（供后续结算消费）
    p2.result = p2.result or {}
    p2.result.choice = choiceId
    p2.result.choiceResult = resultText
    -- V1.0 P2 本批：写入关系结局标识（供结算页 / 下一轮结局演出 / P3 继承消费）；
    --   停止写入 isDeath（存活/死亡差异已废除）；leafId 仅作追溯保留。
    p2.result.endingId = ending.endingId
    p2.result.endingTitle = ending.endingTitle
    if leaf then
        p2.result.leafId = leaf.leafId
    end
    p2.flags.resultReady = true
    p2.checkpoint = "P2_FINAL_CHOICE_SELECTED"
    print("[P2 Final]\nchoice=" .. tostring(choiceId)
          .. " leafId=" .. tostring(p2.result.leafId)
          .. " endingId=" .. tostring(p2.result.endingId))
    -- V1.0 P2 本批：先播放三类关系结局演出，结束后经原 EndP2()（结算簿记）进入原 ShowP2Ending 关系总结页。
    -- 不播放 enterP3、不跳转 P3、不重置 P2Context；不恢复 isDeath/存活判定。
    print("[P2-ENDING] play endingId=" .. tostring(p2.result.endingId)
        .. " leafId=" .. tostring(p2.result.leafId))
    PlayP2EndingSequence(p2.result.endingId, function()
        EndP2()
    end)
end

-- ----------------------------------------------------------------------------

P2FinalFlow.PrepareFinalTreatment = PrepareP2FinalTreatment
P2FinalFlow.ShowFinalTreatmentChoice = ShowP2FinalTreatmentChoice
P2FinalFlow.PrepareFinalChoice = PrepareP2FinalChoice
P2FinalFlow.EnterFinalChoice = EnterP2FinalChoice
P2FinalFlow.HandleFinalChoice = OnP2FinalChoiceSelected
P2FinalFlow.StartSedation = BeginP2SedateXianFlow
P2FinalFlow.StartSearch = ShowP2SearchXianFlow
P2FinalFlow.StartFoodEvent = StartP2FoodEvent
P2FinalFlow.PlayFoodEvent = PlayP2FoodEvent
P2FinalFlow.ShowFoodChoice = ShowP2FoodChoice
P2FinalFlow.PlayFoodBranch = PlayP2FoodBranch
P2FinalFlow.FinishFoodEvent = FinishP2FoodEvent
P2FinalFlow.HandleRefuseCollapse = HandleP2RefuseCollapse
P2FinalFlow.PlayRefuseOutcome = PlayP2RefuseOutcome
P2FinalFlow.EvaluateFinalLeaf = EvaluateP2FinalLeaf
P2FinalFlow.ClassifyFinalEnding = ClassifyP2FinalEnding
P2FinalFlow.PlayEndingSequence = PlayP2EndingSequence

function P2FinalFlow.Reset()
    config = {}
end

return P2FinalFlow
