-- ============================================================================
-- P1 记录终端 UI
--
-- 只负责记录终端的列表/阅读页面显示和页面内 UI 交互。
-- 记录内容、解锁状态及记录文本拼装由调用方提供。
-- ============================================================================

local UI = require("urhox-libs/UI")

local TerminalRecordsUI = {}

local PANEL_BACKGROUND = { 10, 17, 28, 238 }
local CONTENT_BACKGROUND = { 20, 25, 38, 255 }
local PRIMARY_TEXT = { 220, 230, 242, 245 }
local SECONDARY_TEXT = { 130, 175, 198, 210 }
local ACCENT = { 110, 200, 255, 180 }
local SCROLL_PADDING = 16
local HEADER_GAP = 4
local CONTENT_GAP = 12
local TITLE_FONT_SIZE = 21
local SUBTITLE_FONT_SIZE = 11
local RECORD_FONT_SIZE = 15
local RECORD_LINE_HEIGHT = 1.5
local FOOTER_HEIGHT = 52
local BUTTON_WIDTH = 130
local BUTTON_HEIGHT = 44

local function RestoreDialogLayout(dialog, content)
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = "auto", maxHeight = 460 })
    end
    content:SetStyle({ height = "auto" })
end

--- 创建 P1 记录终端入口按钮。
---@param onOpen function 点击后打开记录终端
---@param options table|nil 可选入口配置，支持 id；位置和样式默认沿用 P1 规格
---@return Widget
function TerminalRecordsUI.CreateButton(onOpen, options)
    options = options or {}
    return UI.Button {
        id = options.id or "obj_record",
        text = "记录终端",
        width = 130,
        height = 90,
        position = "absolute",
        left = 8,
        top = 80,
        variant = "default",
        backgroundColor = { 40, 60, 55, 200 },
        borderWidth = 1,
        borderColor = { 90, 150, 130, 180 },
        borderRadius = 10,
        fontSize = 15,
        onClick = onOpen,
    }
end

--- 显示 P1 调查记录列表。
---@param dialog Widget 共享 Dialog 节点
---@param content Widget 共享 Dialog 内容节点
---@param shown table 已由调用方拼装的记录显示数据，包含 text/count
---@param onClose function 关闭终端时执行的外部清理回调
---@param onShowRecord function|nil 显示后将控件引用交给调用方的回调
---@param options table|nil 显示配置：title/buttonLabel/titleBuilder/dialogHeight/contentHeight
function TerminalRecordsUI.Open(dialog, content, shown, onClose, onShowRecord, options)
    options = options or {}
    local title = options.title or "调查记录"
    local buttonLabel = options.buttonLabel or "返回"

    content:ClearChildren()

    local recordLabel = UI.Label {
        id = "recordText",
        text = shown.text,
        fontSize = RECORD_FONT_SIZE,
        lineHeight = RECORD_LINE_HEIGHT,
        fontColor = PRIMARY_TEXT,
        textAlign = "left",
        whiteSpace = "normal",
        wordBreak = "break-word",
        width = "100%",
        flexShrink = 0,
    }
    local scroll = UI.ScrollView {
        id = "recordScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        minHeight = 1,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = CONTENT_BACKGROUND,
        padding = SCROLL_PADDING,
        borderRadius = 8,
        overflow = "hidden",
        children = {
            recordLabel,
        },
    }

    local function addTitle(parent)
        local header = UI.Panel {
            id = "terminalHeader",
            width = "100%",
            flexShrink = 0,
            alignItems = "center",
            gap = HEADER_GAP,
            children = {},
        }
        if options.titleBuilder then
            local builtTitle = options.titleBuilder(title)
            builtTitle.width = "100%"
            builtTitle.alignItems = "center"
            header:AddChild(builtTitle)
        else
            header:AddChild(UI.Label {
                text = title,
                fontSize = TITLE_FONT_SIZE,
                fontColor = PRIMARY_TEXT,
                textAlign = "center",
                width = "100%",
            })
        end
        header:AddChild(UI.Label {
            text = options.subtitle or "INVESTIGATION LOG",
            fontSize = SUBTITLE_FONT_SIZE,
            fontColor = SECONDARY_TEXT,
            textAlign = "center",
            width = "100%",
            letterSpacing = 1,
        })
        header:AddChild(UI.Panel {
            id = "terminalHeaderRule",
            width = "72%",
            height = 1,
            backgroundColor = ACCENT,
        })
        parent:AddChild(header)
    end

    local function addCloseButton(parent)
        local footer = UI.Row {
            id = "terminalFooter",
            width = "100%",
            height = FOOTER_HEIGHT,
            justifyContent = "center",
            alignItems = "center",
            flexShrink = 0,
            children = {},
        }
        footer:AddChild(UI.Button {
            id = "returnButton",
            text = buttonLabel,
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT,
            borderRadius = 10,
            variant = "primary",
            onClick = function()
                RestoreDialogLayout(dialog, content)
                dialog:SetVisible(false)
                if onClose then onClose() end
            end,
        })
        parent:AddChild(footer)
    end

    local terminalContent = UI.Panel {
        id = "terminalRecordsContent",
        width = "100%",
        height = options.contentHeight or "100%",
        maxHeight = options.maxContentHeight or "100%",
        flexDirection = "column",
        gap = CONTENT_GAP,
        padding = 12,
        backgroundColor = PANEL_BACKGROUND,
        borderRadius = 10,
        children = {},
    }
    addTitle(terminalContent)
    terminalContent:AddChild(scroll)
    addCloseButton(terminalContent)
    content:AddChild(terminalContent)

    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = options.dialogHeight or 460 })
    end
    content:SetStyle({ height = "100%" })
    dialog:SetVisible(true)

    -- 将布局引用回传给调用方，用于保留原有下一帧调试输出。
    if onShowRecord then
        onShowRecord(recordLabel, scroll)
    end
end

return TerminalRecordsUI
