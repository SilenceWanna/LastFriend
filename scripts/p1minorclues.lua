local UI = require("urhox-libs/UI")
local P1Content = require("p1content")

local P1MinorClues = {}

local MinorClues_ = P1Content.MinorClues
local MinorClueGroups_ = P1Content.MinorClueGroups

local minorViewed_ = {}

---@type number
local minorScrollOffset_ = 0
---@type number
local minorContentHeight_ = 0
---@type number
local minorViewportHeight_ = 0
---@type number
local minorMaxScroll_ = 0
local minorScrollbarVisible_ = false
local minorActiveClueId_ = nil
local pendingMinorDebug_ = false
local pendingMinorScroll_ = nil

local MinorClueImages_ = {
    MN02 = "image/P1/P1_MN02_SleepPod_v01.png",
    MN03 = "image/P1/P1_MN03_Cups_v01.png",
    MN07 = "image/P1/P1_MN07_MaintenanceLog_v01.png",
    MN08 = "image/P1/P1_MN08_Jacket_v01.png",
}

local standardTextDialogIds = {
    MN01 = true,
    MN02 = true,
    MN03 = true,
    MN04 = true,
    MN05 = true,
    MN06 = true,
    MN07 = true,
    MN08 = true,
    MN09 = true,
    MN10 = true,
    MN11 = true,
    MN12 = true,
}

local deps_ = {}

function P1MinorClues.Configure(deps)
    deps_ = deps
end

function P1MinorClues.Reset()
    minorViewed_ = {}
end

--- 按“描述 → 内心逐句”播放 P1 次要线索；不改任何调查状态或记录。
function P1MinorClues.ShowSequence(clue, options)
    options = options or {}
    local description = clue.description or ""
    local thoughts = clue.thoughts or {}
    local imagePath = options.imagePath
    local onBack = options.onBack

    local function FinishSequence()
        if imagePath then
            deps_.showClueImage(imagePath, onBack, clue.title)
        elseif onBack then
            deps_.closeDialog()
            onBack()
        else
            deps_.closeDialog()
        end
    end

    local function ShowThought(index)
        local thought = thoughts[index]
        if not thought then
            FinishSequence()
            return
        end
        local isLast = index >= #thoughts
        local buttons = {
            {
                label = isLast and (imagePath and "查看现场" or "返回调查") or "继续",
                variant = isLast and "primary" or "default",
                onClick = function()
                    if isLast then
                        FinishSequence()
                    else
                        ShowThought(index + 1)
                    end
                end,
            },
        }
        deps_.showDialog("我", "我｜内心：\n" .. thought, buttons)
    end

    if description ~= "" then
        deps_.showDialog(clue.title, description, {
            {
                label = "继续",
                variant = "primary",
                onClick = function()
                    if #thoughts > 0 then
                        ShowThought(1)
                    else
                        FinishSequence()
                    end
                end,
            },
        })
    elseif #thoughts > 0 then
        ShowThought(1)
    else
        FinishSequence()
    end
end

--- 播放一条次要线索：复用现有 dialog 遮罩，不修改任何核心游戏状态
--- 不消耗调查时间、不消耗弦耐心、不进入询问系统、不影响关系值、不修改核心线索状态
--- @param clueId string 次要线索 id（如 "MN02"）
--- @param onBack function|nil 返回按钮回调；不传则仅关闭弹窗。通常经 ShowNearbyMinorClues 透传 OnClueClicked(coreId) 以回到原核心线索页
function P1MinorClues.Show(clueId, onBack)
    -- V1.0-08-P1-G：撤离事件启动后，次要线索入口统一锁定，只提示撤离。
    if deps_.isEscapeStarted() then
        deps_.showDialog("撤离", "广播声越来越近。\n\n现在必须离开。", {
            { label = "返回", variant = "primary", onClick = deps_.closeDialog },
        })
        return
    end
    local clue = MinorClues_[clueId]
    if not clue then
        print("WARN: unknown minor clue id = " .. tostring(clueId))
        return
    end

    local body = clue.text or ""
    local stageLabel = ""
    if clueId == "MN03" then
        if minorViewed_["MN03"] then
            stageLabel = "（再次查看）"
        else
            body = clue.stage1 or body
            stageLabel = "（初次观察）"
            minorViewed_["MN03"] = true
        end
    end
    print("[DEBUG次要线索] 显示次要线索 id=" .. tostring(clueId) .. stageLabel .. " 标题=" .. tostring(clue.title))

    local btns = {
        {
            label = "返回调查",
            variant = "primary",
            onClick = function()
                deps_.closeDialog()
                if onBack then onBack() end
            end,
        },
    }
    local useStandardTextDialog = standardTextDialogIds[clueId] == true
    local function ShowMinorBody()
        if useStandardTextDialog then
            local sequenceData = {
                title = clue.title,
                description = clue.description,
                thoughts = clue.thoughts,
            }
            P1MinorClues.ShowSequence(sequenceData, {
                imagePath = MinorClueImages_[clueId],
                onBack = onBack,
            })
        else
            P1MinorClues.ShowScrollable(clue.title, body, btns, clueId)
        end
    end

    if MinorClueImages_[clueId] and not useStandardTextDialog then
        table.insert(btns, 1, {
            label = "查看现场",
            variant = "default",
            onClick = function()
                deps_.showClueImage(
                    MinorClueImages_[clueId],
                    ShowMinorBody,
                    clue.title)
            end,
        })
    end
    -- 标准线索序列的图片入口由最后一句内心统一衔接，避免重复创建按钮。
    ShowMinorBody()
end

--- 专用可滚动 Minor 详情弹窗
--- 结构：【固定弹窗盒 height≈屏幕 80%】→【固定标题】+【可滚动正文 ScrollView】+【固定底部「返回调查」按钮】
--- 只有正文 ScrollView 滚动；标题与按钮固定在弹窗盒内，不参与滚动，长文本不再挤出按钮。
--- 复用引擎原生 ScrollView（自动支持：鼠标滚轮 / 移动端拖动 / 右侧滚动条拖动 / onScroll 回调）。
--- 不修改任何 Minor 文本内容、数据结构、调查状态、onBack 返回逻辑。
--- @param title string 弹窗标题
--- @param body string 正文文本（多段 \\n 分隔）
--- @param buttons table 按钮表（沿用 ShowMinorClue 已构建的 btns，含「返回调查」）
--- @param clueId string|nil 次要线索 id（仅用于调试日志）
function P1MinorClues.ShowScrollable(title, body, buttons, clueId)
    local root = deps_.getUIRoot()
    local dialog = root:FindById("dialog")
    local box = dialog and dialog:FindById("dialogBox")
    local content = dialog and dialog:FindById("dialogContent")
    if not (dialog and box and content) then
        print("ERROR: minor dialog widgets not found")
        return
    end

    -- 每次打开新的 Minor：滚动位置重置到顶部（不继承上一个 Minor 的 offset）
    minorScrollOffset_ = 0
    minorActiveClueId_ = clueId

    -- 弹窗盒高度：屏幕高度的 80%，并夹在 [260, 560] 之间，预留顶/底边距与安全区
    local screenH = deps_.getScreenHeight()
    local boxH = math.floor(screenH * 0.80)
    boxH = math.max(260, math.min(560, boxH))

    content:ClearChildren()

    -- 顶部：固定标题块（不进入滚动区）
    content:AddChild(deps_.buildTitleBlock(title))

    -- 中间：可滚动正文区域（占满标题与按钮之间的剩余空间，超长内部滚动）
    local bodyLabel = UI.Label {
        text = body,
        fontSize = 14,
        fontColor = { 210, 220, 235, 240 },
        textAlign = "left",
        width = "100%",
        flexShrink = 0,
    }
    local scroll = UI.ScrollView {
        id = "minorScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = { 20, 25, 38, 255 },
        padding = 14,
        borderRadius = 8,
        onScroll = function(self, sx, sy)
            minorScrollOffset_ = sy
            -- 引擎已内部夹紧 scrollY；此处同步状态供调试
            minorScrollOffset_ = math.max(0, math.min(minorScrollOffset_, minorMaxScroll_))
            print("[DEBUG MinorScroll] clueId=" .. tostring(minorActiveClueId_)
                .. " offset=" .. tostring(math.floor(minorScrollOffset_))
                .. " maxScroll=" .. tostring(math.floor(minorMaxScroll_)))
        end,
        children = { bodyLabel },
    }
    content:AddChild(scroll)

    -- 底部：固定返回按钮行（始终可见可点击，不进入滚动区）
    local btnRow = UI.Row { gap = 12, marginTop = 12, flexWrap = "wrap", children = {} }
    for _, b in ipairs(buttons) do
        btnRow:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            onClick = function()
                print("[DEBUG MinorScroll] 返回调查 clueId=" .. tostring(minorActiveClueId_))
                if b.onClick then b.onClick() end
            end,
        })
    end
    content:AddChild(btnRow)

    -- 关键：弹窗盒设为确定高度，content 撑满盒，使中间 ScrollView 的 flexGrow 拿到剩余空间；
    -- 标题与按钮行固定，只有 ScrollView 滚动。关闭弹窗时由 CloseDialog 还原高度约束。
    -- 同时把静态 maxHeight 抬高到 boxH，避免被默认 460 上限夹住导致高度不足。
    box:SetStyle({ height = boxH, maxHeight = boxH })
    content:SetStyle({ height = "100%" })

    dialog:SetVisible(true)

    -- 下一帧布局完成后打印正文尺寸/滚动范围（避免首帧 GetContentSize 返回 0）
    pendingMinorDebug_ = true
    pendingMinorScroll_ = scroll
end

--- 下一帧打印 Minor 滚动弹窗尺寸（布局稳定后再读 content/viewport/maxScroll）
function P1MinorClues.FlushMinorDebug()
    if not pendingMinorDebug_ then return end
    local scroll = pendingMinorScroll_
    pendingMinorDebug_ = false
    pendingMinorScroll_ = nil
    if not scroll then return end
    local cw, ch = scroll:GetContentSize()
    local l = scroll.GetLayout and scroll:GetLayout()
    local viewH = (l and l.h) or 0
    minorContentHeight_ = ch
    minorViewportHeight_ = viewH
    minorMaxScroll_ = math.max(0, ch - viewH)
    minorScrollbarVisible_ = (minorMaxScroll_ > 0)
    print("[DEBUG MinorScroll] clueId=" .. tostring(minorActiveClueId_)
        .. " contentHeight=" .. tostring(math.floor(minorContentHeight_))
        .. " viewportHeight=" .. tostring(math.floor(minorViewportHeight_))
        .. " maxScroll=" .. tostring(math.floor(minorMaxScroll_))
        .. " scrollbarVisible=" .. tostring(minorScrollbarVisible_))
end

--- 获取某核心线索区域对应的次要线索 id 列表（无则返回空表）
---@param coreId string 核心线索 id（如 "locker"）
---@return table 次要线索 id 数组
function P1MinorClues.GetNearby(coreId)
    local group = MinorClueGroups_[coreId]
    if not group then
        return {}
    end
    return group
end

--- 显示某核心线索区域的次要线索选择窗口：列出该区域全部次要线索供玩家点选
--- 仅用于 locker 测试接入；复用 dialog 遮罩，不修改任何核心游戏状态
---@param coreId string 核心线索 id
---@param onBack function|nil 返回按钮回调；不传则仅关闭弹窗。通常传入 OnClueClicked(coreId) 以回到原核心线索页
function P1MinorClues.ShowNearby(coreId, onBack)
    -- V1.0-08-P1-G：撤离事件启动后，次要线索入口统一锁定，只提示撤离。
    if deps_.isEscapeStarted() then
        deps_.showDialog("撤离", "广播声越来越近。\n\n现在必须离开。", {
            { label = "返回", variant = "primary", onClick = deps_.closeDialog },
        })
        return
    end
    local ids = P1MinorClues.GetNearby(coreId)
    print("[DEBUG次要线索] 打开周边线索选择 coreId=" .. tostring(coreId) .. " 数量=" .. tostring(#ids))
    local btns = {}
    for _, mid in ipairs(ids) do
        local clue = MinorClues_[mid]
        local title = clue and clue.title or mid
        table.insert(btns, {
            label = title,
            variant = "default",
            onClick = function()
                deps_.closeDialog()
                P1MinorClues.Show(mid, onBack)
            end,
        })
    end
    table.insert(btns, {
        label = "返回调查",
        variant = "primary",
        onClick = function()
            deps_.closeDialog()
            if onBack then onBack() end
        end,
    })
    deps_.showDialog("周围的细节", "这里还有一些值得留意的东西。", btns)
end

return P1MinorClues
