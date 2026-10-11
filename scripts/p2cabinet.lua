-- ============================================================================
-- scripts/p2cabinet.lua
-- 《零点之后》第二关「雪线诊所」药柜流程模块
--
-- 只负责药柜局部交互：入口分流、密码键盘、药柜内容与药物资料。
-- 正式 P2 状态由调用方提供并继续归 controller/state 所有；本模块只读写
-- 药柜流程实际使用的状态字段。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Story2 = require("story2")

local P2Cabinet = {}
local config = {}
local P2_CABINET_PASSWORD = "0718"

function P2Cabinet.Configure(newConfig)
    config = newConfig
end

local function GetState()
    return config.getState()
end

local function CloseDialog()
    config.closeDialog()
end

local function ShowDialog(title, body, buttons)
    config.showDialog(title, body, buttons)
end

local function StartDialogue(steps, onComplete, title)
    config.startDialogue(steps, onComplete, title)
end

local function ShowCabinetChoice(clue)
    local p2 = GetState()
    if not p2 then return end
    local buttons = {}

    -- 寻求弦的帮助：仅未求证且弦清醒（SOBER）时显示（镇静后隐藏；【自己寻找密码】不受影响）
    if p2.flags.cabinetAsked ~= true and p2.xianConscious == "SOBER" then
        table.insert(buttons, {
            label = "寻求弦的帮助",
            variant = "default",
            onClick = function()
                CloseDialog()
                -- 镇静保险（本批）：弦非清醒时静默拦截，返回药柜选择窗口；不播对白/不扣耐心/不计数
                if not p2 or p2.xianConscious ~= "SOBER" then
                    print("[P2-XIAN] interaction blocked: sedated")
                    ShowCabinetChoice(clue)
                    return
                end
                -- 先检查本线索是否已经求证（二次保险，主显隐已由按钮条件保证）
                if p2.flags.cabinetAsked == true then
                    P2Cabinet.ShowPasswordPad()
                    return
                end
                -- 消耗 1 点耐心（复用既有 patienceRemaining 字段 + 统一 > 0 保护）
                local patienceBefore = p2.patienceRemaining
                config.consumePatience()
                -- 设置一次性求证 flag（同一存档不再二次求证 / 不再扣耐心 / 不再播对白）
                p2.flags.cabinetAsked = true
                -- 播放完整四句求证对白（弦不直接提供密码），结束直接进入现有数字键盘
                local ask = (clue and clue.cabinetAsk) or {}
                local steps = ask.dialogue
                if steps and #steps > 0 then
                    StartDialogue(steps, function()
                        -- 常规提问登记：完整四句对白结束后计数（不在点击按钮时提前登记）
                        -- triggered=true → 耐心耗尽后的下一次新正式询问触发 MEMORY 02B，跳过原返回，由回调返回药柜选择窗口
                        local triggered = config.registerXianQuestion("cabinet_help", function()
                            ShowCabinetChoice(clue)
                        end, patienceBefore)
                        if triggered then return end
                        -- 询问弦只播问答：结束后返回药柜选择窗口，不自动弹出密码键盘
                        CloseDialog()
                        ShowCabinetChoice(clue)
                    end, "锁住的药柜")
                else
                    -- 数据缺失兜底：完成原状态结算后返回药柜选择窗口，不打开密码键盘
                    local triggered = config.registerXianQuestion("cabinet_help", function()
                        ShowCabinetChoice(clue)
                    end, patienceBefore)
                    if triggered then return end
                    ShowCabinetChoice(clue)
                end
            end,
        })
    end

    -- 自己寻找密码：始终显示，进入现有四位数字键盘
    table.insert(buttons, {
        label = "自己寻找密码",
        variant = "primary",
        onClick = function()
            CloseDialog()
            print("[DEBUG CABINET PASSWORD] opening keypad dialog")
            P2Cabinet.ShowPasswordPad()
        end,
    })

    -- 返回医务室（保留现有医务室返回可达性）
    table.insert(buttons, {
        label = "返回医务室",
        variant = "default",
        onClick = CloseDialog,
    })

    ShowDialog(clue.title or "锁住的药柜", "你想怎么打开药柜？", buttons)
end

function P2Cabinet.Open(clue)
    local p2 = GetState()
    if not p2 then return end

    -- 已解锁：直接进柜内内容，跳过一切开场/选择/键盘/求证。
    if p2.flags.cabinetUnlocked == true then
        P2Cabinet.ShowContents()
        return
    end

    -- 首次调查完整开场：环境描述 → 内心两段 → 选择窗（仅第一次）
    if not (p2.flags.cabinetIntroSeen == true) then
        if p2.flags then p2.flags.cabinetIntroSeen = true end
        -- 环境描述（可滚动长描述弹窗，独立一页，避免窗口过小显示不全）
        config.showRestClueDialog(clue.title or "锁住的药柜", clue.inspect or "", {
            {
                label = "继续",
                variant = "primary",
                onClick = function()
                    CloseDialog()
                    -- 零的内心台词（紧凑逐句对白，独立展示，不拼进环境描述）
                    StartDialogue(clue.dialogue, function()
                        CloseDialog()
                        ShowCabinetChoice(clue)
                    end, "锁住的药柜")
                end,
            },
        })
        return
    end

    -- 已看过开场（含已求证）：直接进入选择窗（不重播环境描述与内心）
    ShowCabinetChoice(clue)
end

function P2Cabinet.ShowPasswordPad()
    -- 药柜仅存在于医务室（CLINIC）场景，dialog 挂在 p2ClinicRoot_ 下；
    -- 切勿用 p2Root_（隧道根，非当前活动根，其 dialog 不可见）。
    local root = config.getClinicRoot()
    if not root then
        print("ERROR: ShowP2CabinetKeypadDialog called before BuildP2Scene")
        return
    end
    local dialog = root:FindById("dialog")
    local content = root:FindById("dialogContent")
    if not (dialog and content) then
        print("ERROR: P2 cabinet keypad dialog widgets not found")
        return
    end

    -- 仅针对药柜数字键盘弹窗：放大 dialogBox 高度，确保 4 行键盘 + 底部按钮完整显示。
    -- 不修改全局 CreateDialog 默认尺寸；普通剧情弹窗内容很短，抬高 maxHeight 对其无影响。
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ maxHeight = 620 })
    end

    local pp = GetState()
    -- 已打开则不应再弹（兜底，入口 OnP2ClueClicked 已拦截）
    if pp and pp.flags and pp.flags.cabinetUnlocked == true then
        P2Cabinet.ShowContents()
        return
    end

    -- 当前输入值（局部字符串持有，禁止转 number，否则 0718 会丢前导 0）
    local cabinetPasswordInput = ""

    -- 顶部输入状态显示：● 表示已输入位，_ 表示空位（最多 4 位，不暴露正确答案）
    local statusLabel = nil
    local errorLabel = nil

    -- 统一刷新顶部状态（根据当前长度生成 ● _ _ _ 形式）
    local function refreshStatus()
        if not statusLabel then return end
        local s = ""
        for i = 1, 4 do
            if i <= #cabinetPasswordInput then
                s = s .. "●"
            else
                s = s .. "_"
            end
            if i < 4 then s = s .. " " end
        end
        statusLabel:SetText(s)
    end

    -- 统一校验入口：仅【确认】调用，杜绝两套逻辑
    local function verifyPassword()
        -- 不足 4 位 → 提示请输入四位密码，清空以便重新输入
        if #cabinetPasswordInput ~= 4 then
            if errorLabel then
                errorLabel:SetText("请输入四位密码。")
                errorLabel:SetVisible(true)
            end
            cabinetPasswordInput = ""
            refreshStatus()
            return
        end
        -- 按字符串比较（保留前导 0）
        if cabinetPasswordInput == P2_CABINET_PASSWORD then
            CloseDialog()
            local p = GetState()
            if p and p.flags then
                p.flags.cabinetUnlocked = true
                p.flags.visited_clinic_cabinet = true
            end
            StartDialogue({
                { narration = "密码正确。" },
                { narration = "药柜缓缓打开。" },
            }, function()
                P2Cabinet.ShowContents()
            end)
        else
            -- 错误：不关闭、不开柜、不置位；提示错误并清空输入，允许无限重试
            if errorLabel then
                errorLabel:SetText("密码错误，请重试。")
                errorLabel:SetVisible(true)
            end
            cabinetPasswordInput = ""
            refreshStatus()
        end
    end

    -- 追加一位数字（满 4 位不再追加）
    local function appendDigit(d)
        if #cabinetPasswordInput >= 4 then return end
        cabinetPasswordInput = cabinetPasswordInput .. d
        if errorLabel then errorLabel:SetVisible(false) end
        refreshStatus()
    end

    content:ClearChildren()
    content:AddChild(UI.Label {
        text = "输入密码",
        fontSize = 20,
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
        width = "100%",
        marginBottom = 4,
    })
    content:AddChild(UI.Label {
        text = "请输入四位密码。",
        fontSize = 14,
        fontColor = { 210, 220, 235, 240 },
        textAlign = "center",
        width = "100%",
        marginTop = 4,
    })

    -- 顶部输入状态（● _ _ _ 形式）
    statusLabel = UI.Label {
        text = "_ _ _ _",
        fontSize = 28,
        fontColor = { 150, 230, 255, 255 },
        textAlign = "center",
        width = "100%",
        marginTop = 10,
        letterSpacing = 4,
    }
    content:AddChild(statusLabel)

    -- 错误提示 Label（默认隐藏）
    errorLabel = UI.Label {
        text = "",
        fontSize = 13,
        fontColor = { 240, 120, 120, 255 },
        textAlign = "center",
        width = "100%",
        marginTop = 6,
        visible = false,
    }
    content:AddChild(errorLabel)

    -- 数字键盘：每行 3 个按钮，间距一致，按钮尺寸足够手机点击
    local keypadDigits = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "清除", "0", "退格" }
    local function onDigitClick(d)
        if d == "清除" then
            cabinetPasswordInput = ""
            if errorLabel then errorLabel:SetVisible(false) end
            refreshStatus()
        elseif d == "退格" then
            cabinetPasswordInput = string.sub(cabinetPasswordInput, 1, #cabinetPasswordInput - 1)
            if errorLabel then errorLabel:SetVisible(false) end
            refreshStatus()
        else
            appendDigit(d)
        end
    end

    local keyBtnW = 84
    local keyBtnH = 52
    -- 分 4 行（每行 3 个）构建键盘；行间距收敛以保证手机屏完整显示
    for row = 0, 3 do
        local rowChildren = {}
        for col = 1, 3 do
            local idx = row * 3 + col
            local d = keypadDigits[idx]
            if d then
                table.insert(rowChildren, UI.Button {
                    text = d,
                    variant = "default",
                    width = keyBtnW, height = keyBtnH,
                    fontSize = 20,
                    onClick = function() onDigitClick(d) end,
                })
            end
        end
        content:AddChild(UI.Row {
            gap = 12, justifyContent = "center", marginTop = 8, width = "100%",
            children = rowChildren,
        })
    end

    -- 底部按钮：【确认】【关闭】
    content:AddChild(UI.Row {
        gap = 12, justifyContent = "center", marginTop = 12, width = "100%",
        children = {
            UI.Button {
                text = "确认",
                variant = "primary",
                onClick = function() verifyPassword() end,
            },
            UI.Button {
                text = "关闭",
                variant = "default",
                onClick = function() CloseDialog() end,
            },
        },
    })

    dialog:SetVisible(true)
end

function P2Cabinet.ShowContents()
    local root = config.getClinicRoot()
    local dialog = root and root:FindById("dialog")
    local dialogBox = dialog and dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = "auto", maxHeight = 460 })
    end
    local content = dialog and dialog:FindById("dialogContent")
    if content then
        content:SetStyle({ height = "auto" })
    end

    local p2 = GetState()
    local inv = p2 and p2.inventory
    local kitOwned = inv and inv.syringe == true and inv.sedative == true
    local itemButtons = {}
    for _, item in ipairs(Story2.cabinetContent or {}) do
        local id = item.id
        local title = item.title or item.id or "未命名物品"
        if id == "medicalKit" and kitOwned then
            title = "医用急救箱（已查看）"
        end
        table.insert(itemButtons, {
            label = title,
            variant = "default",
            onClick = function()
                CloseDialog()
                -- 已接入正文的物品：复用 StartOpeningDialogue 播放，结束返回药柜列表
                if id == "recordBook" then
                    StartDialogue(Story2.cabinetRecord.steps, function()
                        CloseDialog()
                        P2Cabinet.ShowContents()
                    end, Story2.cabinetRecord.title or "登记本")
                elseif id == "medicalKit" then
                    if kitOwned then
                        -- 已查看过：不再重播 9 步内容，仅播放一句简短提示后返回药柜
                        StartDialogue(Story2.medicalKitReviewed.steps, function()
                            CloseDialog()
                            P2Cabinet.ShowContents()
                        end, Story2.medicalKitReviewed.title or "医用急救箱")
                    else
                        -- 首次查看：播放完整内容 → 获得提示 → 置 inventory → 返回药柜
                        StartDialogue(Story2.medicalKit.steps, function()
                            CloseDialog()
                            StartDialogue(Story2.obtainItems.steps, function()
                                CloseDialog()
                                if inv then
                                    inv.syringe = true
                                    inv.sedative = true
                                end
                                P2Cabinet.ShowContents()
                            end, "医用急救箱")
                        end, Story2.medicalKit.title or "医用急救箱")
                    end
                else
                    -- 未知条目安全回退，不中断药柜流程。
                    ShowDialog(title, "该药柜条目暂无可读内容。", {
                        { label = "返回药柜", variant = "primary", onClick = function()
                            CloseDialog()
                            P2Cabinet.ShowContents()
                        end },
                    })
                end
            end,
        })
    end
    table.insert(itemButtons, {
        label = "关闭",
        variant = "primary",
        onClick = CloseDialog,
    })
    ShowDialog("药柜", "药柜已经打开。", itemButtons)
end

function P2Cabinet.ShowMedicationRecords()
    local p2 = GetState()
    if not p2 then return end
    local meds = Story2.clinic.clues.medications
    if not meds or #meds == 0 then
        print("[DEBUG P2] OpenP2MedicationRecords: no medications")
        return
    end
    local lines = {}
    for i = 1, #meds do
        lines[#lines + 1] = "■ " .. meds[i].name .. "\n" .. meds[i].description
    end
    p2.flags.medicationsViewed = true
    print("[DEBUG P2] OpenP2MedicationRecords: medicationsViewed=true count=" .. tostring(#meds))

    -- V1.0-07N-P2-B2-B：镇静剂条目取得逻辑。沿用现有药物资料对话框，仅为 sedative 增加「取走」动作。
    -- 不新增独立调查点；可重复进入：已取则按钮/文本切换为已取状态，不重复异常写入。
    local sedative = nil
    for i = 1, #meds do
        if meds[i].id == "sedative" then
            sedative = meds[i]
            break
        end
    end
    local buttons = { { label = "返回诊所", variant = "primary", onClick = CloseDialog } }
    if sedative then
        if p2.hasSedative then
            -- 已取走：仅展示已取状态文本，不再写入。
            buttons = {
                { label = "查看已取物品", variant = "default", onClick = function()
                    ShowDialog(sedative.name, sedative.takenText or "已取走。",
                        { { label = "返回", variant = "primary", onClick = CloseDialog } })
                end },
                { label = "返回诊所", variant = "primary", onClick = CloseDialog },
            }
        else
            -- 首次：提供取走选项，点击后写入 hasSedative/hasSyringe 并展示取得结果。
            buttons = {
                { label = "取走镇静剂与针管", variant = "default", onClick = function()
                    p2.hasSedative = true
                    p2.hasSyringe = true
                    print("[P2] sedative+syringe taken: hasSedative=" .. tostring(p2.hasSedative)
                          .. " hasSyringe=" .. tostring(p2.hasSyringe))
                    -- TEMP DEBUG：诊断镇静按钮显隐（发布前删除）
                    print(string.format(
                        "[P2-SEDATIVE] acquired: sedative=%s syringe=%s conscious=%s area=%s",
                        tostring(p2.hasSedative),
                        tostring(p2.hasSyringe),
                        tostring(p2.xianConscious),
                        tostring(p2.clinicArea)
                    ))
                    ShowDialog(sedative.name, sedative.takeText or "已取走短效镇静剂与针管。",
                        { { label = "返回诊所", variant = "primary", onClick = CloseDialog } })
                end },
                { label = "返回诊所", variant = "primary", onClick = CloseDialog },
            }
        end
    end
    config.showLongDialog("药物资料", table.concat(lines, "\n\n————————\n\n"), buttons)
end

function P2Cabinet.Reset()
    config = {}
end

return P2Cabinet
