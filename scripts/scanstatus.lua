-- ============================================================================
-- scanstatus.lua
-- 《零点之后》第一关扫描系统「状态文字 HUD」（纯视觉反馈层）
-- 职责（仅新增视觉反馈，不修改任何扫描 / 调查 / 剧情 / 点击逻辑）：
--   1. 点击 SCAN → 顶部中央显示「SCANNING...」。
--   2. 扫描完成 → 切换为「ANOMALY DETECTED」，持续约 1 秒后淡出。
-- 约束（严格遵守）：
--   - 不修改 ScanFX / investigate.lua 热点逻辑 / HitTest / OnClick / 调查系统。
--   - 纯视觉：pointerEvents="none"，不接收事件，不影响底层点击与已有按钮。
--   - 半透明、青色科幻文字，置于屏幕顶部中央，不遮挡场景。
--   - 优先使用已有 UI 动画（Widget:Animate → UI.Transition opacity）。
-- ============================================================================

local UI = require("urhox-libs/UI")

local ScanStatus = {}

---@type Label|nil
local statusMainText_ = nil
---@type Label|nil
local statusSubText_ = nil
---@type Panel|nil
local statusAccentLine_ = nil
local statusVersion_ = 0

-- 统一 P1/P2 的冷色科幻状态视觉规格。
local FADE_DURATION = 0.25
local DETECT_HOLD = 1.0
local STATUS_TOP = 18
local MAIN_FONT_SIZE = 19
local SUB_FONT_SIZE = 10
local MAIN_COLOR = { 175, 235, 255, 245 }
local SUB_COLOR = { 125, 185, 215, 205 }
local ACCENT_COLOR = { 105, 205, 255, 180 }

local function SetStatus(mainText, subText)
    local mainWidget = statusMainText_
    local subWidget = statusSubText_
    if not mainWidget then return end
    if not subWidget then return end
    mainWidget:SetText(mainText)
    subWidget:SetText(subText or "")
end

local function AnimateWidget(widget, holdDuration, token)
    local fadeEnd = FADE_DURATION
    local animation = {
        keyframes = {
            [0] = { opacity = 0 },
            [fadeEnd] = { opacity = 1 },
        },
        duration = fadeEnd,
        easing = "easeOut",
        loop = false,
        fillMode = "forwards",
    }
    if holdDuration and holdDuration > 0 then
        animation.keyframes[fadeEnd + holdDuration] = { opacity = 1 }
        animation.keyframes[fadeEnd + holdDuration + FADE_DURATION] = { opacity = 0 }
        animation.duration = fadeEnd + holdDuration + FADE_DURATION
        animation.easing = "easeInOut"
        animation.onComplete = function()
            if token == statusVersion_ then
                SetStatus("", "")
                local accentWidget = statusAccentLine_
                if accentWidget then
                    accentWidget:SetStyle({ opacity = 0 })
                end
            end
        end
    end
    widget:StopAnimation()
    widget:Animate(animation)
end

local function AnimateStatus(mainText, subText, holdDuration)
    local mainWidget = statusMainText_
    local subWidget = statusSubText_
    local accentWidget = statusAccentLine_
    if not (mainWidget and subWidget and accentWidget) then return end
    statusVersion_ = statusVersion_ + 1
    local token = statusVersion_
    SetStatus(mainText, subText)
    AnimateWidget(mainWidget, holdDuration, token)
    AnimateWidget(subWidget, holdDuration, token)
    AnimateWidget(accentWidget, holdDuration, token)
end

--- 构建 P1/P2 共用的状态提示层：中文主提示、英文辅助提示和强调线。
---@return Widget 状态层容器
function ScanStatus.BuildLayer()
    local mainText = UI.Label {
        id = "statusMainText",
        text = "",
        width = "100%",
        fontSize = MAIN_FONT_SIZE,
        fontColor = MAIN_COLOR,
        letterSpacing = 2,
        textAlign = "center",
        pointerEvents = "none",
        opacity = 0,
    }
    local subText = UI.Label {
        id = "statusSubText",
        text = "",
        width = "100%",
        fontSize = SUB_FONT_SIZE,
        fontColor = SUB_COLOR,
        letterSpacing = 1,
        textAlign = "center",
        pointerEvents = "none",
        opacity = 0,
    }
    local accentLine = UI.Panel {
        id = "statusAccentLine",
        width = 84,
        height = 1,
        alignSelf = "center",
        pointerEvents = "none",
        backgroundColor = ACCENT_COLOR,
        opacity = 0,
    }
    statusMainText_ = mainText
    statusSubText_ = subText
    statusAccentLine_ = accentLine
    local layer = UI.Panel {
        id = "scanStatusLayer",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
        paddingTop = STATUS_TOP,
        pointerEvents = "none",
        backgroundColor = { 0, 0, 0, 0 },
        visible = true,
        children = { mainText, subText, accentLine },
    }
    return layer
end

--- 扫描中提示：中文为主，英文为辅助。
function ScanStatus.ShowScanning()
    if not statusMainText_ then return end
    AnimateStatus("扫描中", "SCANNING", 0)
    print("[scanstatus] ShowScanning")
end

--- 扫描完成提示：统一使用目标检测文案，随后自动淡出。
function ScanStatus.ShowDetected()
    if not statusMainText_ then return end
    AnimateStatus("检测到目标", "TARGET DETECTED", DETECT_HOLD)
    print("[scanstatus] ShowDetected")
end

--- 扫描无目标时的可选提示，保留旧接口之外不影响既有调用。
function ScanStatus.ShowNoSignal()
    if not statusMainText_ then return end
    AnimateStatus("未检测到目标", "NO SIGNAL", DETECT_HOLD)
end

--- 扫描完成的可选提示，供后续调用方使用。
function ScanStatus.ShowComplete()
    if not statusMainText_ then return end
    AnimateStatus("扫描完成", "SCAN COMPLETE", DETECT_HOLD)
end

return ScanStatus
