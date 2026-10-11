-- ============================================================================
-- P1 线索档案 UI
--
-- 只负责线索档案入口按钮、档案列表和线索大图的显示与 UI 交互。
-- 线索获得状态、数据和外部状态处理均由调用方通过参数/回调提供。
-- ============================================================================

local UI = require("urhox-libs/UI")

local ClueArchiveUI = {}

local ARCHIVE_PANEL_BG = { 10, 16, 26, 242 }
local ARCHIVE_CARD_BG = { 18, 28, 42, 240 }
local ARCHIVE_IMAGE_BG = { 11, 19, 31, 255 }
local ARCHIVE_PRIMARY_TEXT = { 235, 242, 250, 255 }
local ARCHIVE_SECONDARY_TEXT = { 145, 169, 194, 220 }
local ARCHIVE_ACCENT = { 120, 220, 255, 255 }
local ARCHIVE_BORDER = { 92, 154, 190, 180 }
local ARCHIVE_MUTED_BORDER = { 76, 112, 142, 150 }
local ARCHIVE_GAP = 12
local ARCHIVE_TITLE_SIZE = 24
local ARCHIVE_BODY_SIZE = 13

local function CloseDialog(dialog, content, onClose)
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = "auto", maxHeight = 460 })
    end
    content:SetStyle({ height = "auto" })
    dialog:SetVisible(false)
    if onClose then
        onClose()
    end
end

local function ResolveFileLabel(imagePath)
    local labels = {
        ["image/P1/P1_C01_Note_v01.png"] = "FILE 01",
        ["image/P1/P1_clue_photo_memory.png"] = "FILE 02",
        ["image/P1/P1_C03_Terminal_v01.png"] = "FILE 03",
        ["image/P1/P1_C04_Ring_v01.png"] = "FILE 04",
        ["image/P1/P1_MN02_SleepPod_v01.png"] = "FILE 05",
        ["image/P1/P1_MN03_Cups_v01.png"] = "FILE 06",
        ["image/P1/P1_MN07_MaintenanceLog_v01.png"] = "FILE 07",
        ["image/P1/P1_MN08_Jacket_v01.png"] = "FILE 08",
    }
    return labels[imagePath] or "FILE --"
end

local function BuildArchiveHeader(obtainedCount, totalCount)
    return UI.Panel {
        id = "archiveHeader",
        width = "100%",
        height = 100,
        flexShrink = 0,
        gap = 4,
        alignItems = "center",
        justifyContent = "center",
        children = {
            UI.Label {
                text = "线索档案",
                fontSize = ARCHIVE_TITLE_SIZE,
                fontColor = ARCHIVE_PRIMARY_TEXT,
                textAlign = "center",
                width = "100%",
                height = 32,
            },
            UI.Label {
                text = "ARCHIVE RECORDS",
                fontSize = 10,
                fontColor = ARCHIVE_SECONDARY_TEXT,
                textAlign = "center",
                letterSpacing = 2,
                width = "100%",
                height = 18,
            },
            UI.Label {
                text = string.format("%d / %d 已获得", obtainedCount, totalCount),
                fontSize = 12,
                fontColor = ARCHIVE_ACCENT,
                textAlign = "center",
                width = 108,
                height = 24,
                paddingTop = 4,
                paddingBottom = 4,
                backgroundColor = { 24, 58, 78, 210 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = ARCHIVE_BORDER,
            },
            UI.Panel {
                width = "62%",
                height = 1,
                marginTop = 4,
                backgroundColor = ARCHIVE_BORDER,
            },
        },
    }
end

local function BuildArchiveCard(entry, fileLabel, onOpenImage)
    local card = UI.Panel {
        id = "archiveCard_" .. fileLabel:gsub("%s", "_"),
        width = "44%",
        height = 172,
        flexShrink = 1,
        minWidth = 0,
        backgroundColor = ARCHIVE_CARD_BG,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = ARCHIVE_MUTED_BORDER,
        padding = 8,
        gap = 4,
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function()
            onOpenImage(entry.path, entry.title, fileLabel)
        end,
        children = {
            UI.Panel {
                width = "100%",
                height = 94,
                flexShrink = 0,
                backgroundColor = ARCHIVE_IMAGE_BG,
                borderRadius = 6,
                backgroundImage = entry.path,
                backgroundFit = "contain",
                pointerEvents = "none",
            },
            UI.Label {
                text = entry.title,
                width = "100%",
                height = 20,
                fontSize = ARCHIVE_BODY_SIZE,
                fontColor = ARCHIVE_PRIMARY_TEXT,
                textAlign = "center",
                maxLines = 1,
                whiteSpace = "nowrap",
                pointerEvents = "none",
            },
            UI.Label {
                text = fileLabel,
                width = "100%",
                height = 16,
                fontSize = 9,
                fontColor = ARCHIVE_SECONDARY_TEXT,
                textAlign = "center",
                letterSpacing = 1,
                pointerEvents = "none",
            },
            UI.Label {
                text = "● 已获得",
                width = "100%",
                height = 16,
                fontSize = 9,
                fontColor = ARCHIVE_ACCENT,
                textAlign = "center",
                pointerEvents = "none",
            },
        },
    }
    return card
end

--- 创建 P1 线索档案入口按钮。
---@param onOpen function 点击后打开档案列表
---@return Widget
function ClueArchiveUI.CreateButton(onOpen)
    return UI.Button {
        id = "obj_archive",
        text = "线索档案",
        width = 120,
        height = 90,
        position = "absolute",
        right = 20,
        bottom = 40,
        variant = "default",
        backgroundColor = { 50, 55, 75, 210 },
        borderWidth = 1,
        borderColor = { 110, 125, 165, 190 },
        borderRadius = 10,
        fontSize = 15,
        onClick = onOpen,
    }
end

--- 显示已获得的 P1 线索档案列表。
---@param dialog Widget 共享 Dialog 节点
---@param content Widget 共享 Dialog 内容节点
---@param entries table 线索数据表，条目需包含 title/path/obtained
---@param archiveOrder table 线索档案固定显示顺序
---@param buildTitleBlock function 创建共享样式标题块的回调（保留接口兼容）
---@param onImageViewed function|nil 查看图片时通知调用方更新状态
---@param onClose function|nil 关闭 Dialog 时通知调用方清理外部状态
function ClueArchiveUI.Open(dialog, content, entries, archiveOrder, buildTitleBlock, onImageViewed, onClose)
    content:ClearChildren()

    local obtainedCount = 0
    for _, entry in pairs(entries) do
        if entry.obtained then
            obtainedCount = obtainedCount + 1
        end
    end

    local archiveContent = UI.Panel {
        id = "archiveContent",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        gap = ARCHIVE_GAP,
        backgroundColor = ARCHIVE_PANEL_BG,
        borderRadius = 10,
        padding = 10,
        overflow = "hidden",
        children = {
            BuildArchiveHeader(obtainedCount, #archiveOrder),
        },
    }

    local grid = UI.Panel {
        id = "archiveGrid",
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = ARCHIVE_GAP,
        alignContent = "flex-start",
        children = {},
    }

    local scroll = UI.ScrollView {
        id = "galleryScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = { 14, 23, 36, 255 },
        borderRadius = 8,
        padding = 10,
        children = { grid },
    }

    if obtainedCount == 0 then
        grid:AddChild(UI.Label {
            text = "暂无记录",
            width = "100%",
            fontSize = 14,
            fontColor = ARCHIVE_SECONDARY_TEXT,
            textAlign = "center",
            marginTop = 24,
        })
    else
        for index, key in ipairs(archiveOrder) do
            local entry = entries[key]
            if entry and entry.obtained then
                local fileLabel = string.format("FILE %02d", index)
                grid:AddChild(BuildArchiveCard(entry, fileLabel, function(path, title, label)
                    ClueArchiveUI.ShowImage(
                        dialog,
                        content,
                        path,
                        title,
                        buildTitleBlock,
                        onImageViewed,
                        onClose,
                        function()
                            ClueArchiveUI.Open(
                                dialog,
                                content,
                                entries,
                                archiveOrder,
                                buildTitleBlock,
                                onImageViewed,
                                onClose)
                        end,
                        "返回档案",
                        label)
                end))
            end
        end
    end
    archiveContent:AddChild(scroll)

    local footer = UI.Row {
        id = "archiveFooter",
        width = "100%",
        height = 52,
        minHeight = 52,
        flexShrink = 0,
        gap = ARCHIVE_GAP,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Button {
                id = "archiveCloseButton",
                text = "关闭",
                variant = "primary",
                width = 128,
                height = 44,
                onClick = function()
                    CloseDialog(dialog, content, onClose)
                end,
            },
        },
    }
    archiveContent:AddChild(footer)
    content:AddChild(archiveContent)

    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = 460 })
    end
    content:SetStyle({ height = "100%" })

    dialog:SetVisible(true)
    print("[DEBUG档案] 线索档案已打开 已获得=" .. obtainedCount .. "/" .. #archiveOrder)
end

--- 显示单张线索大图。
--- 该函数同时服务于档案缩略图和 P1 其他线索图片查看。
--- 末尾两个可选参数仅用于显示层：返回按钮文案和档案编号。
---@param dialog Widget 共享 Dialog 节点
---@param content Widget 共享 Dialog 内容节点
---@param imagePath string 图片资源路径
---@param title string|nil 图片标题
---@param buildTitleBlock function 创建共享样式标题块的回调
---@param onImageViewed function|nil 图片首次查看回调
---@param onClose function|nil 关闭 Dialog 时通知调用方清理外部状态
---@param onClosed function|nil Dialog 关闭后继续执行的回调
---@param returnLabel string|nil 返回按钮文案，默认“返回调查”
---@param fileLabel string|nil 档案编号，缺省按图片路径推导
function ClueArchiveUI.ShowImage(
    dialog,
    content,
    imagePath,
    title,
    buildTitleBlock,
    onImageViewed,
    onClose,
    onClosed,
    returnLabel,
    fileLabel)
    local dialogBox = dialog:FindById("dialogBox")
    local resolvedFileLabel = fileLabel or ResolveFileLabel(imagePath)

    if onImageViewed then
        onImageViewed(imagePath)
    end

    if dialogBox then
        dialogBox:SetStyle({ height = 540 })
    end
    content:SetStyle({ height = "100%" })
    content:ClearChildren()

    local imagePage = UI.Panel {
        id = "archiveImagePage",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        gap = ARCHIVE_GAP,
        backgroundColor = ARCHIVE_PANEL_BG,
        borderRadius = 10,
        padding = 10,
        overflow = "hidden",
        children = {
            UI.Panel {
                id = "archiveImageHeader",
                width = "100%",
                height = 52,
                flexShrink = 0,
                gap = 2,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = resolvedFileLabel,
                        width = "100%",
                        height = 16,
                        fontSize = 10,
                        fontColor = ARCHIVE_ACCENT,
                        textAlign = "center",
                        letterSpacing = 2,
                    },
                    UI.Label {
                        text = title or "",
                        width = "100%",
                        height = 26,
                        fontSize = 20,
                        fontColor = ARCHIVE_PRIMARY_TEXT,
                        textAlign = "center",
                        maxLines = 1,
                        whiteSpace = "nowrap",
                    },
                },
            },
            UI.Panel {
                id = "archiveImageView",
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                minHeight = 0,
                backgroundColor = ARCHIVE_IMAGE_BG,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = ARCHIVE_MUTED_BORDER,
                backgroundImage = imagePath,
                backgroundFit = "contain",
            },
        },
    }

    local footer = UI.Row {
        id = "archiveImageFooter",
        width = "100%",
        height = 52,
        minHeight = 52,
        flexShrink = 0,
        gap = ARCHIVE_GAP,
        flexWrap = "wrap",
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Button {
                id = "archiveReturnButton",
                text = returnLabel or "返回调查",
                variant = "primary",
                width = 128,
                height = 44,
                onClick = function()
                    CloseDialog(dialog, content, onClose)
                    if onClosed then
                        onClosed()
                    end
                end,
            },
            UI.Button {
                id = "archiveImageCloseButton",
                text = "关闭",
                variant = "default",
                width = 96,
                height = 44,
                onClick = function()
                    CloseDialog(dialog, content, onClose)
                end,
            },
        },
    }
    imagePage:AddChild(footer)
    content:AddChild(imagePage)

    dialog:SetVisible(true)
    print("[DEBUG合照] 图片查看弹窗已显示 路径=" .. tostring(imagePath))
end

return ClueArchiveUI
