-- ============================================================================
-- scripts/titlescreen.lua
-- 标题页构建器。只负责界面布局，具体流程通过回调注入。
-- ============================================================================

local UI = require("urhox-libs/UI")

local TitleScreen = {}

local function CreateDevButton(id, text, onClick)
    return UI.Button {
        id = id,
        text = text,
        variant = "default",
        width = 220,
        height = 52,
        fontSize = 18,
        onClick = onClick,
    }
end

function TitleScreen.Show(options)
    ---@type Widget[]
    local children = {
        UI.Label {
            id = "titleText",
            text = options.title or "零点之后",
            fontSize = 56,
            color = { 235, 240, 255, 255 },
        },
        UI.Label {
            id = "titleSubText",
            text = options.subtitle or "废弃休眠区 · 雪线诊所",
            fontSize = 22,
            color = { 150, 165, 200, 255 },
            marginTop = 16,
        },
        UI.Label {
            id = "titleProgress",
            text = options.progressText or "",
            fontSize = 16,
            color = { 120, 130, 150, 255 },
            marginTop = 28,
        },
        UI.Button {
            id = "titleStartBtn",
            text = options.startLabel or "开始游戏",
            variant = "primary",
            width = 240,
            height = 64,
            fontSize = 22,
            marginTop = 40,
            onClick = options.onStart,
        },
    }

    if options.showDeveloperTools then
        children[#children + 1] = UI.Panel {
            id = "devTestPanel",
            width = "100%",
            flexDirection = "column",
            alignItems = "center",
            marginTop = 36,
            gap = 10,
            children = {
                UI.Label {
                    text = "[DEV] 测试入口",
                    fontSize = 16,
                    color = { 255, 180, 120, 255 },
                    textAlign = "center",
                },
                CreateDevButton("debug_enter_p2_tunnel", "测试 P2 隧道", options.onDevTunnel),
                CreateDevButton("debug_enter_p2_clinic", "测试：进入诊所", options.onDevClinic),
                CreateDevButton("debug_enter_p3", "测试：进入 P3", options.onDevP3),
            },
        }
    end

    local root = UI.Panel {
        id = "titleScreen",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 12, 14, 20, 255 },
        children = children,
    }

    UI.SetRoot(root)
    return root
end

return TitleScreen
