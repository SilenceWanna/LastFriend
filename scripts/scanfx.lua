-- ============================================================================
-- scanfx.lua
-- 《零点之后》第一关「扫描启动动画」一次性扫描线（纯视觉反馈层）
-- 职责（仅新增视觉反馈，不修改任何调查 / 剧情 / 点击逻辑）：
--   1. 扫描线：一条淡蓝色水平线，从屏幕顶部移动到底部（约 1.0s）。
--   2. 纯视觉：pointerEvents="none"，不接收事件，不影响底层 clickLayer 点击。
--   3. 一次性：播放结束后自动隐藏；不循环、不残留、不干扰呼吸动画 / 热点角标。
-- 约束（严格遵守）：
--   - 不修改 hotspots / HitTest / OnClick / 调查逻辑 / Story / MinorClues / 呼吸动画。
--   - 优先使用已有 UI 动画（Widget:Animate → UI.Transition keyframe），不引入 NanoVG。
--   - 不新增 pointerEvents、不改变点击区域、不缩放热点。
-- ============================================================================

local UI = require("urhox-libs/UI")

local ScanFX = {}

-- 模块内引用（BuildLayer 构建时赋值，Play/Hide 复用）
---@type Widget|nil
local lineWidget_ = nil     -- 扫描线主体
---@type Widget|nil
local trailWidget_ = nil    -- 扫描线下方的轻微尾迹
---@type Widget|nil
local layerWidget_ = nil    -- 扫描特效全屏容器（由场景根加入）

-- 局部视觉规格：不改变既有扫描时长和完成回调。
local LINE_DURATION = 1.0
local LINE_HEIGHT = 2
local LINE_COLOR = { 150, 225, 255, 185 }
local TRAIL_HEIGHT = 48
local TRAIL_COLOR = { 80, 175, 235, 22 }
local MASK_COLOR = { 40, 105, 150, 18 }
local LINE_GLOW = {
    { x = 0, y = 0, blur = 6, spread = 0, color = { 110, 205, 255, 85 } },
}

--- 构建一次扫描特效层：扫描线、轻微尾迹和低透明度冷色遮罩。
---@return Widget 扫描特效层容器
function ScanFX.BuildLayer()
    local mask = UI.Panel {
        id = "scanfxMask",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "none",
        backgroundColor = MASK_COLOR,
    }
    local trail = UI.Panel {
        id = "scanfxTrail",
        position = "absolute",
        left = 0, right = 0, top = 0,
        width = "100%",
        height = TRAIL_HEIGHT,
        pointerEvents = "none",
        backgroundColor = TRAIL_COLOR,
        translateY = -TRAIL_HEIGHT,
    }
    trailWidget_ = trail
    local line = UI.Panel {
        id = "scanfxLine",
        position = "absolute",
        left = 0, right = 0, top = 0,
        width = "100%",
        height = LINE_HEIGHT,
        pointerEvents = "none",
        backgroundColor = LINE_COLOR,
        boxShadow = LINE_GLOW,
        translateY = 0,
    }
    lineWidget_ = line

    local layer = UI.Panel {
        id = "scanfxLayer",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "none",
        backgroundColor = { 0, 0, 0, 0 },
        visible = false,
        children = { mask, trail, line },
    }
    layerWidget_ = layer
    return layer
end

--- 播放一次性扫描特效。重复调用前停止旧动画，保证同一时刻只有一条扫描线。
---@param onDone function|nil 播放结束回调（可选）
function ScanFX.Play(onDone)
    if not lineWidget_ then
        print("[scanfx] Play skipped: lineWidget_ not built")
        if onDone then onDone() end
        return
    end
    local H = UI.GetHeight() or 0
    if H <= 0 then
        print("[scanfx] Play skipped: invalid UI height")
        if onDone then onDone() end
        return
    end

    ScanFX.Hide()
    if layerWidget_ then layerWidget_:SetVisible(true) end
    lineWidget_:SetVisible(true)
    if trailWidget_ then trailWidget_:SetVisible(true) end
    print("[scanfx] Play: start scan line, duration=" .. LINE_DURATION .. "s")

    local function finish()
        if layerWidget_ then layerWidget_:SetVisible(false) end
        if lineWidget_ then lineWidget_:StopAnimation() end
        if trailWidget_ then trailWidget_:StopAnimation() end
        print("[scanfx] Play done: hidden")
        if onDone then onDone() end
    end
    local animation = {
        keyframes = {
            [0] = { translateY = 0 },
            [1] = { translateY = H },
        },
        duration = LINE_DURATION,
        easing = "easeInOut",
        loop = false,
        fillMode = "backwards",
        onComplete = finish,
    }
    lineWidget_:Animate(animation)
    if trailWidget_ then
        trailWidget_:Animate({
            keyframes = {
                [0] = { translateY = -TRAIL_HEIGHT },
                [1] = { translateY = H - TRAIL_HEIGHT },
            },
            duration = LINE_DURATION,
            easing = "easeInOut",
            loop = false,
            fillMode = "backwards",
        })
    end
end

--- 立即隐藏扫描特效，清理遮罩、扫描线和尾迹动画。
function ScanFX.Hide()
    if layerWidget_ then layerWidget_:SetVisible(false) end
    if lineWidget_ then
        lineWidget_:StopAnimation()
        lineWidget_:SetVisible(false)
    end
    if trailWidget_ then
        trailWidget_:StopAnimation()
        trailWidget_:SetVisible(false)
    end
end

return ScanFX
