-- ============================================================================
-- scripts/p2terminal.lua
-- 《零点之后》第二关「雪线诊所」终端控制模块
--
-- 终端分为两套完全独立的内容：
--   1. P2 全局记录终端：读取已发生的 P2 对话历史。
--   2. 诊所电脑文件：读取诊所设备内的 computerFiles / computerFileContent。
--
-- 本模块只负责内容拼装、打开/返回流程与 TerminalRecordsUI 调用；正式 P2
-- 状态仍由调用方持有，模块仅通过注入的 getter/setter 读写终端相关字段。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Story2 = require("story2")
local TerminalRecordsUI = require("terminalrecordsui")
local BGMPlayer = require("bgmplayer")
local VoicePlayer = require("voiceplayer")

local P2Terminal = {}
local config = {}

function P2Terminal.Configure(newConfig)
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

local function PlayMemory(steps, onComplete, title)
    config.playMemory(steps, onComplete, title)
end

local function ShowComputerFiles()
    local fileButtons = {}
    for _, f in ipairs(Story2.computerFiles or {}) do
        local id = f.id
        local title = f.title or f.id or "未命名文件"
        table.insert(fileButtons, {
            label = title,
            variant = "default",
            onClick = function()
                CloseDialog()
                -- 已接入正文的文件：复用 StartOpeningDialogue 播放
                local content = Story2.computerFileContent and Story2.computerFileContent[id]
                if content and content.steps then
                    -- 三个文件窗口标题（无扩展名，区别于列表按钮文案）；StartOpeningDialogue 第三参。
                    local fileTitle = ({
                        record = "值班记录",
                        diary = "校医日记",
                        migration = "迁移名单统计",
                    })[id] or title
                    -- KEY04 migration：纵向档案，单文本框一次显示，不分页、不逐 step 播放
                    if id == "migration" then
                        local body =
                            "【零】\n" ..
                            "技术／评级：技术权限最高\n" ..
                            "迁移资格：通过\n" ..
                            "随迁家属：0\n\n" ..

                            "【弦】\n" ..
                            "技术／评级：医疗维护权限\n" ..
                            "迁移资格：条件通过\n" ..
                            "随迁家属：0\n\n" ..

                            "【身份损坏人员】\n" ..
                            "技术／评级：未成年／无独立劳动力评级\n" ..
                            "迁移资格：未通过\n" ..
                            "随迁家属：—\n\n" ..

                            "表格下方附有一条校医留下的工作日记。\n\n" ..

                            "今晚又有人来问，能不能修改家属资格。\n" ..
                            "我已经解释过很多次，医疗系统没有权限改变迁移名单。\n" ..
                            "没有迁移资格，也没有登记为随迁家属，就无法进入迁移程序。\n" ..
                            "即使有人愿意放弃自己的位置，系统也不会自动把名额转给另一个人。"
                        config.showRestClueDialog(fileTitle, body, {
                            {
                                label = "返回电脑",
                                variant = "primary",
                                onClick = function()
                                    CloseDialog()
                                    -- KEY04 阅读后播放两句零的内心独白（各一页），结束返回电脑文件列表
                                    local lines = (Story2.computerFileContent and Story2.computerFileContent.migrationEpilogue) or {}
                                    local ei = 1
                                    local function PlayEpilogue()
                                        local step = lines[ei]
                                        if not step then
                                            ShowComputerFiles()
                                            return
                                        end
                                        local isLast = ei >= #lines
                                        -- 逐句配音：显示当前 step 时播放对应配音
                                        VoicePlayer.PlayStep(step)
                                        ShowDialog("我｜内心", "我｜内心：" .. step.inner, {
                                            {
                                                label = "继续",
                                                variant = "primary",
                                                onClick = function()
                                                    if isLast then
                                                        CloseDialog()
                                                        VoicePlayer.Stop()
                                                        -- KEY04 询问弦（一次性常规问答）：已询问或弦非清醒（镇静）→ 直接返回文件列表
                                                        local p2q = GetState()
                                                        local ask = Story2.computerAsk and Story2.computerAsk.migration
                                                        if ask and ask.dialogue and p2q and p2q.flags
                                                            and p2q.flags.migrationFileAsked ~= true
                                                            and p2q.xianConscious == "SOBER" then
                                                            ShowDialog("调查", "继续调查？", {
                                                                {
                                                                    label = "询问弦",
                                                                    variant = "primary",
                                                                    onClick = function()
                                                                        CloseDialog()
                                                                        -- 镇静保险（本批）：静默拦截，返回电脑文件列表
                                                                        if not p2q or p2q.xianConscious ~= "SOBER" then
                                                                            print("[P2-XIAN] interaction blocked: sedated")
                                                                            CloseDialog()
                                                                            ShowComputerFiles()
                                                                            return
                                                                        end
                                                                        StartDialogue(ask.dialogue, function()
                                                                            -- 四句问答完整结束后统一结算（不在点击按钮时提前）
                                                                            local patienceBefore = p2q.patienceRemaining
                                                                            config.consumePatience()
                                                                            -- 耐心耗尽后的下一次新正式询问触发 MEMORY 02B
                                                                            local triggered = config.registerXianQuestion("migration_file", function()
                                                                                CloseDialog()
                                                                                ShowComputerFiles()
                                                                            end, patienceBefore)
                                                                            p2q.flags.migrationFileAsked = true
                                                                            if triggered then return end
                                                                            CloseDialog()
                                                                            ShowComputerFiles()
                                                                        end)
                                                                    end,
                                                                },
                                                                {
                                                                    label = "返回文件列表",
                                                                    variant = "default",
                                                                    onClick = function()
                                                                        CloseDialog()
                                                                        ShowComputerFiles()
                                                                    end,
                                                                },
                                                            })
                                                        else
                                                            ShowComputerFiles()
                                                        end
                                                    else
                                                        ei = ei + 1
                                                        CloseDialog()
                                                        PlayEpilogue()
                                                    end
                                                end,
                                            },
                                        })
                                    end
                                    PlayEpilogue()
                                end,
                            },
                        })
                        return
                    end
                    StartDialogue(content.steps, function()
                        CloseDialog()
                        if id == "diary" then
                            local pp = GetState()
                            if pp and pp.flags then
                                pp.flags.readDiary = true
                                if pp.flags.memory02Played ~= true then
                                    pp.flags.memory02Played = true
                                    local organize = Story2.clinic
                                        and Story2.clinic.restEvents
                                        and Story2.clinic.restEvents.organize
                                    -- 音乐任务2：P2「她又晕倒了」记忆开始
                                    BGMPlayer.Play("BGM_P2_MEMORY_WARM_v01", { loop = true, gain = 0.28 })
                                    PlayMemory(organize and organize.memorySteps or {}, function()
                                        -- 音乐任务2：P2 记忆结束 → 恢复诊所背景音乐
                                        BGMPlayer.Play("BGM_P2_CLINIC_AMBIENT_v01", { loop = true, gain = 0.28 })
                                        ShowDialog("系统", organize and organize.memorySystemText
                                            or "已解锁药物识别：清醒维持剂。", {
                                            {
                                                label = "返回电脑",
                                                variant = "primary",
                                                onClick = function()
                                                    CloseDialog()
                                                    ShowComputerFiles()
                                                end,
                                            },
                                        })
                                    end)
                                    return
                                end
                            end
                        end
                        -- 该文件存在可选求证对白（第十九批 migration）→ 弹「继续调查？」
                        local ask = Story2.computerAsk and Story2.computerAsk[id]
                        if ask and ask.dialogue then
                            ShowDialog("调查", "继续调查？", {
                                {
                                    label = "询问弦",
                                    variant = "primary",
                                    onClick = function()
                                        CloseDialog()
                                        StartDialogue(ask.dialogue, function()
                                            CloseDialog()
                                            ShowComputerFiles()
                                        end)
                                    end,
                                },
                                {
                                    label = "返回文件列表",
                                    variant = "default",
                                    onClick = function()
                                        CloseDialog()
                                        ShowComputerFiles()
                                    end,
                                },
                            })
                        else
                            -- 无可选求证 → 直接返回文件列表
                            ShowComputerFiles()
                        end
                    end, fileTitle)
                else
                    -- 未知文件安全回退，不中断终端流程。
                    ShowDialog(title, "该文件暂无可读内容。", {
                        { label = "返回文件列表", variant = "primary", onClick = function()
                            CloseDialog()
                            ShowComputerFiles()
                        end },
                    })
                end
            end,
        })
    end
    table.insert(fileButtons, {
        label = "关闭",
        variant = "primary",
        onClick = CloseDialog,
    })
    ShowDialog("电脑文件", "请选择文件。", fileButtons)
end

function P2Terminal.GetRecordContent(records)
    local blocks = {}
    for i = 1, #records do
        local record = records[i]
        local lines = record.lines
        if not lines and record.speaker and record.text then
            lines = { record }
        end
        if lines and #lines > 0 then
            local blockLines = {}
            for j = 1, #lines do
                local line = lines[j]
                blockLines[#blockLines + 1] = tostring(line.speaker) .. "："
                blockLines[#blockLines + 1] = "“" .. tostring(line.text) .. "”"
                if j < #lines then
                    blockLines[#blockLines + 1] = ""
                end
            end
            blocks[#blocks + 1] = table.concat(blockLines, "\n")
        end
    end
    if #blocks == 0 then
        return "暂无对话记录", 0
    end
    return table.concat(blocks, "\n\n------------------------------\n\n"), #blocks
end

function P2Terminal.OpenRecords()
    local p2 = GetState()
    if not p2 then return end
    local text, count = P2Terminal.GetRecordContent(p2.dialogRecords or {})
    local shown = {
        text = text,
        count = count,
    }
    local root = config.getRoot()
    local dialog = root and root:FindById("dialog")
    local content = root and root:FindById("dialogContent")
    if not (dialog and content) then
        print("[DEBUG P2] OpenP2DialogueRecords: dialog widgets not found")
        return
    end
    TerminalRecordsUI.Open(
        dialog,
        content,
        shown,
        function()
            CloseDialog()
        end,
        nil,
        {
            title = "调查记录",
            buttonLabel = "返回",
            contentHeight = 412,
            dialogHeight = 460,
        })
end

function P2Terminal.OpenClinicFiles()
    ShowComputerFiles()
end

function P2Terminal.OpenClinicRecords()
    local p2 = GetState()
    if not p2 then return end
    local records = Story2.clinic.clues.terminalRecords
    if not records or #records == 0 then
        print("[DEBUG P2] OpenP2ClinicTerminalFiles: no records")
        return
    end
    local lines = {}
    for i = 1, #records do
        lines[#lines + 1] = "■ " .. records[i].title .. "\n" .. records[i].text
    end
    p2.flags.terminalRecordsViewed = true
    print("[DEBUG P2] OpenP2ClinicTerminalFiles: recordsViewed=true count=" .. tostring(#records))
    config.showLongDialog("终端记录", table.concat(lines, "\n\n————————\n\n"),
        { { label = "返回诊所", variant = "primary", onClick = CloseDialog } })
end

function P2Terminal.CreateRecordButton(onOpen, options)
    return TerminalRecordsUI.CreateButton(onOpen, options)
end

function P2Terminal.Reset()
    config = {}
end

return P2Terminal
