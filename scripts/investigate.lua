-- ============================================================================
-- investigate.lua
-- 第一关「废弃休眠区」场景点击调查（第三阶段：接入核心 + 次要线索通道）
-- 职责（仅新增输入层，不修改任何现有调查逻辑）：
--   1. 热点配置：type="core" 走 OnClueClicked(id)；type="minor" 走 ShowMinorClue(id, nil)。
--   2. 点击命中后按 type 派发到对应既有入口，自身不改变任何游戏状态（除 visited 标记）。
--   3. 未命中仅输出 miss，不触发任何调查/状态副作用。
--   4. DEBUG_MODE=false（正式模式）：不显示调试框，点击逻辑照常工作。
--      DEBUG_MODE=true（调试模式）：叠加半透明调试框 + id，用于确认点击范围。
-- 约束（严格遵守）：
--   - 不修改 OnClueClicked / ShowMinorClue / story.lua / MinorClues_ / 弹窗 / 记录 / 时间 / 好感系统。
--   - 仅调用既有全局函数（OnClueClicked / ShowMinorClue），不新增剧情、不新增数据。
--   - 坐标使用百分比（0..1），不依赖固定像素，天然适配横竖屏与高 DPI。
--   - 弹窗打开时本层不参与命中（弹窗全屏遮罩优先命中，点击层收不到事件，自动暂停）。
--   - 调试框层 pointerEvents="none"，纯视觉，不影响点击逻辑，不在正式版显示。
-- 关于次要线索派发的说明：
--   ShowNearbyMinorClues(coreId, onBack) 的 coreId 是【核心线索 id】，内部用
--   MinorClueGroups_[coreId] 查该核心周边的次要线索列表（main.lua:1834）。
--   直接传 "MN02" 作为 coreId 会查不到分组、返回空列表、弹窗无内容，故此处次要热点
--   直接调用 ShowMinorClue(id, nil) —— 这才是「单条次要线索 → MinorClues_」的既有通道，
--   能让点击 MN02/MN03/MN08 直接展示对应次要线索内容。
-- ============================================================================

local UI = require("urhox-libs/UI")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")

local Investigation = {}

-- ----------------------------------------------------------------------------
-- 0. 模式开关
--    false = 正式模式（无调试框，点击照常）；true = 调试模式（显示热点框 + id）。
--    正式发布保持 false。需要确认热点位置时可临时置 true。
-- ----------------------------------------------------------------------------
local DEBUG_MODE = false   -- 正式场景只显示扫描提示，不显示调试框和内部状态标签

-- 正式提示层中各热点提示 Panel 的引用（点击后隐藏），仅在模块内闭环使用。
local hintWidgets_ = {}
local hintBreatheWidgets_ = {}
-- 点击适配层中各热点放大命中 Panel 的引用（随场景切换重建），仅在模块内闭环使用。
local hitWidgets_ = {}
-- 提示层容器 Widget 引用（StartScan/EndScan 切换整体可见性用）
local investHintWidget_ = nil
-- DEBUG 调试层容器 Widget 引用（随场景切换重建，仅显示当前场景 hotspot 框）
local investDbgWidget_ = nil
-- DEBUG 调试层显示开关：仅在扫描（SCAN）期间临时显示 hotspot 框，正式游戏常驻隐藏
local debugScanVisible_ = false

-- 扫描模式状态（本阶段基础框架）：false=常驻提示关闭，true=扫描中显示未调查提示层
Investigation.scanMode = false

-- ----------------------------------------------------------------------------
-- 0.4 点击区域适配（手机端手指易误触的优化，纯点击适配层，不改动任何既有逻辑）
--    视觉四角框大小不变（由 hotspots 数据 + BuildHintLayer 决定）；
--    实际可命中区域 = 视觉框居中扩大 ~40%（约 30%-50%），降低手指误触难度。
--    实现：为每个热点建一个放大后的透明 pointerEvents=auto 命中面板，onClick 把
--    点击映射到该热点中心坐标，复用既有 Investigation.OnClick → HitTest（均不修改）。
--    命中面板仅在扫描模式生效（onClick 内守卫 scanMode），不扫描时不扩大点击。
-- ----------------------------------------------------------------------------
local HIT_EXPAND = 0.4   -- 点击区域相对视觉框扩大比例（0.4 = 40%）
local investHitWidget_ = nil

-- ----------------------------------------------------------------------------
-- 0.5 呼吸动画配置（仅作用于「未调查」提示框，四角扫描框整体透明度呼吸）
--    alpha: 0.5 → 1.0 → 0.5 循环，周期 ~1.7s。
--    不缩放、不位移、不改点击区域、不加 pointerEvents；不闪烁、不发光爆闪。
--    通过容器的 opacity（整体子树乘算）实现，子角标随之同步呼吸。
-- ----------------------------------------------------------------------------
local BREATHE_DURATION = 1.7   -- 呼吸周期（秒）
local BREATHE_MIN = 0.5        -- 最低透明度
local BREATHE_MAX = 1.0        -- 最高透明度
-- DEBUG 扫描框轻微呼吸（仅视觉层）：填充极淡，整体透明度脉动表现为边框亮度起伏
local DBG_BREATHE_MIN = 0.55   -- 扫描框最低亮度
local DBG_BREATHE_MAX = 1.0    -- 扫描框最高亮度

--- 为单个提示容器开启呼吸动画（opacity 0.5↔1.0 无限循环）
---@param w Widget|nil
local function StartBreathe(w)
    if not w then return end
    w:Animate({
        keyframes = {
            [0]   = { opacity = BREATHE_MIN },
            [0.5] = { opacity = BREATHE_MAX },
            [1]   = { opacity = BREATHE_MIN },
        },
        duration = BREATHE_DURATION,
        easing = "easeInOut",
        loop = true,
        fillMode = "backwards",   -- 立即套用首帧(0.5)，避免进入扫描瞬间闪到全亮
    })
end

--- 停止单个提示容器的呼吸动画（停后不残留 renderProps，恢复默认 opacity=1）
---@param w Widget|nil
local function StopBreathe(w)
    if w then w:StopAnimation() end
end

-- ----------------------------------------------------------------------------
-- 0.6 「扫描发现目标」锁定动画（扫描线完成后，未调查热点依次触发一次）
--    效果：opacity 快速从低到高（固定 boxShadow 发光在峰值最明显 → 发光增强），
--          持续约 0.4s，结束后恢复正常呼吸动画。
--    约束：纯视觉（pointerEvents="none"），不改 hotspots/HitTest/OnClick/坐标；
--          仅新增逻辑，不修改既有呼吸/扫描/点击流程。
--    实现：用 Update 事件驱动一个极简调度器，按 STAGGER 间隔依次给每个未调查
--          热点播放一次性 opacity 脉冲，脉冲结束回调里恢复呼吸。
-- ----------------------------------------------------------------------------
local LOCKON_DURATION = 0.42   -- 单次锁定脉冲时长（秒），落在 0.3~0.5 区间
local LOCKON_STAGGER  = 0.09   -- 每个目标之间的触发间隔（秒），形成「依次」效果
local LOCKON_LOW = 0.18        -- 脉冲起始（低）
local LOCKON_HIGH = 1.0        -- 脉冲峰值（高，发光最强）

-- 调度器状态（仅在扫描完成后短暂活跃）
local lockOnQueue_ = {}
local lockOnIndex_ = 1
---@type number
local lockOnElapsed_ = 0
local lockOnActive_ = false

--- 单次锁定脉冲：先停呼吸 → opacity 低→高→回落 → 结束后视状态恢复呼吸
---@param w Widget
local function PulseLockOn(w)
    StopBreathe(w)
    w:Animate({
        keyframes = {
            [0]   = { opacity = LOCKON_LOW },
            [0.5] = { opacity = LOCKON_HIGH },   -- 峰值：固定 glow 在此时最亮
            [1]   = { opacity = BREATHE_MIN },   -- 回落到呼吸基线，衔接更自然
        },
        duration = LOCKON_DURATION,
        easing = "easeOut",
        loop = false,
        fillMode = "backwards",
        onComplete = function()
            -- 仍在扫描且可见才恢复呼吸；否则保持停止（隐藏态不呼吸）
            if Investigation.scanMode and w:IsVisible() then
                StartBreathe(w)
            else
                StopBreathe(w)
            end
        end,
    })
end

--- 扫描线完成后调用：依次触发所有未调查、可见热点的锁定动画
function Investigation.StartLockOn()
    if not Investigation.scanMode then return end   -- 已退出扫描则不触发

    lockOnQueue_ = {}
    for _, hs in ipairs(Investigation.hotspots) do
        if not hs.visited then
            local w = hintWidgets_[hs.id]
            if w and w:IsVisible() then
                lockOnQueue_[#lockOnQueue_ + 1] = w
            end
        end
    end

    if #lockOnQueue_ == 0 then return end

    lockOnIndex_ = 1
    lockOnElapsed_ = 0
    lockOnActive_ = true
    print("[investigate] StartLockOn: targets=" .. #lockOnQueue_)
end

--- Update 驱动调度器：按间隔依次触发锁定脉冲（无活跃时直接返回，零开销）
---@param eventType string
---@param eventData UpdateEventData
local function OnLockOnUpdate(eventType, eventData)
    if not lockOnActive_ then return end
    local dt = eventData:GetFloat("TimeStep")
    lockOnElapsed_ = lockOnElapsed_ + dt
    while lockOnIndex_ <= #lockOnQueue_
          and lockOnElapsed_ >= (lockOnIndex_ - 1) * LOCKON_STAGGER do
        PulseLockOn(lockOnQueue_[lockOnIndex_])
        lockOnIndex_ = lockOnIndex_ + 1
    end
    if lockOnIndex_ > #lockOnQueue_ then
        lockOnActive_ = false
    end
end
SubscribeToEvent("Update", OnLockOnUpdate)

-- ----------------------------------------------------------------------------
-- 1. 热点配置（完整线索布局，按美术部场景区域 A/B/C/D 分组）
--    字段说明：
--      id    : 数据键，必须与 Story.clues / MinorClues_ 的键一致（不修改数据层的前提下
--              点击才能正确派发到 OnClueClicked / ShowMinorClue），不可随意改名。
--      area  : 场景区域分组（A 休眠舱 / B 工作台 / C 墙面设施 / D 储物出口）
--      name  : 美术部线索命名（展示/调试用，不参与派发逻辑）
--      type  : "core"  → OnClueClicked(id)（核心四线索）
--               "minor" → ShowMinorClue(id, nil)（次要线索，id 须存在 MinorClues_）
--      x/y   : 左上角百分比坐标；w/h：宽高百分比
--      visited: 本会话内是否已调查（仅状态记录，不影响剧情/次数/好感/时间）
--    坐标：保留线索沿用既有校准值；新增线索先占位（避免互相重叠），正式美术标定再微调。
--          背景图为 cover 模式会裁剪，坐标为裁剪后可见区域。
-- ----------------------------------------------------------------------------
Investigation.hotspots = {
    -- ===== A 休眠舱区域（sleep_zone）=====
    { id = "locker",   area = "A", scene = "sleep_zone", name = "CORE01 纸条",        type = "core",  x = 0.09, y = 0.50, w = 0.07, h = 0.06, visited = false },
    { id = "MN02",     area = "A", scene = "sleep_zone", name = "MINOR02 空休眠舱",   type = "minor", x = 0.27, y = 0.49, w = 0.06, h = 0.06, visited = false },
    { id = "MN06",     area = "A", scene = "sleep_zone", name = "MINOR06 镇静剂",     type = "minor", x = 0.20, y = 0.42, w = 0.06, h = 0.06, visited = false },
    { id = "MN07",     area = "A", scene = "sleep_zone", name = "MINOR07 维护签名",   type = "minor", x = 0.15, y = 0.30, w = 0.08, h = 0.05, visited = false },
    { id = "MN10",     area = "A", scene = "sleep_zone", name = "MINOR10 拖拽痕迹",   type = "minor", x = 0.30, y = 0.70, w = 0.10, h = 0.08, visited = false },

    -- ===== B 工作台区域（sleep_zone）=====
    { id = "photo",    area = "B", scene = "sleep_zone", name = "CORE02 合照",        type = "core",  x = 0.70, y = 0.43, w = 0.08, h = 0.06, visited = false },
    { id = "terminal", area = "B", scene = "sleep_zone", name = "CORE03 通讯终端",    type = "core",  x = 0.43, y = 0.38, w = 0.10, h = 0.07, visited = false },
    { id = "MN03",     area = "B", scene = "sleep_zone", name = "MINOR03 两只水杯",   type = "minor", x = 0.58, y = 0.50, w = 0.10, h = 0.08, visited = false },
    { id = "MN08",     area = "B", scene = "sleep_zone", name = "MINOR08 外套",       type = "minor", x = 0.84, y = 0.32, w = 0.08, h = 0.18, visited = false },

    -- ===== C 墙面设施区域（facility_zone）=====
    { id = "MN01",     area = "C", scene = "facility_zone", name = "MINOR01 时钟",       type = "minor", x = 0.15, y = 0.12, w = 0.15, h = 0.11, visited = false },
    { id = "MN04",     area = "C", scene = "facility_zone", name = "MINOR04 迁移名单",   type = "minor", x = 0.15, y = 0.30, w = 0.16, h = 0.18, visited = false },
    { id = "MN11",     area = "C", scene = "facility_zone", name = "MINOR11 制度广播",   type = "minor", x = 0.35, y = 0.18, w = 0.10, h = 0.08, visited = false },
    { id = "MN12",     area = "C", scene = "facility_zone", name = "MINOR12 观察窗",     type = "minor", x = 0.51, y = 0.42, w = 0.22, h = 0.09, visited = false },

    -- ===== D 储物/出口区域（sleep_zone）=====
    { id = "ring",     area = "D", scene = "sleep_zone", name = "CORE04 金属环",      type = "core",  x = 0.16, y = 0.60, w = 0.10, h = 0.10, visited = false },
    { id = "MN09",     area = "D", scene = "sleep_zone", name = "MINOR09 锁住储物格", type = "minor", x = 0.43, y = 0.47, w = 0.10, h = 0.08, visited = false },
    { id = "MN05",     area = "D", scene = "facility_zone", name = "MINOR05 儿童涂鸦",   type = "minor", x = 0.82, y = 0.55, w = 0.12, h = 0.12, visited = false },
}

-- ----------------------------------------------------------------------------
-- 1.2 当前场景（多区域调查基础）
--    本阶段仅声明默认值，供后续场景筛选接口与切换使用；暂未接入 UI 切换。
-- ----------------------------------------------------------------------------
Investigation.currentScene = "sleep_zone"

--- 返回当前 scene 对应的热点集合（统一筛选入口，供各读取函数后续替换使用）
---@return table 当前场景热点数组（新 table，遍历安全，不修改原表）
function Investigation.GetCurrentHotspots()
    local result = {}
    for _, hs in ipairs(Investigation.hotspots) do
        if hs.scene == Investigation.currentScene then
            result[#result + 1] = hs
        end
    end
    return result
end

-- ----------------------------------------------------------------------------
-- 1.3 场景切换（第三阶段基础）
--    切换 currentScene 并重建提示层 / 点击适配层，使显示与点击只针对新场景。
--    不清除 visited（已调查状态跨场景保留）；不触发背景切换 / 剧情 / 按钮。
--    使用前需确保 BuildHintLayer / BuildHitLayer 已在 CreateUI 中构建过容器。
-- ----------------------------------------------------------------------------
function Investigation.SetScene(sceneId)
    if not sceneId then
        print("[investigate] SetScene skipped: nil sceneId")
        return
    end
    if sceneId == Investigation.currentScene and investHintWidget_ then
        print("[investigate] SetScene: already in scene=" .. tostring(sceneId))
        return
    end

    -- 1) 清理当前扫描状态（停止呼吸 / 关闭扫描模式 / 隐藏提示层）
    Investigation.scanMode = false
    if investHintWidget_ then
        for _, hs in ipairs(Investigation.GetCurrentHotspots()) do
            StopBreathe(hintWidgets_[hs.id])
        end
        investHintWidget_:SetVisible(false)
    end
    if investHitWidget_ then investHitWidget_:SetVisible(false) end

    -- 2) 清空引用表（按 id 索引的 widget 引用，重建前丢弃旧场景）
    hintWidgets_ = {}
    hitWidgets_ = {}

    -- 3) 切换场景
    Investigation.currentScene = sceneId

    -- 4) 重建提示层 / 点击适配层 / DEBUG 调试层（各 Build* 内部复用既有容器，
    --    按新场景重新填充子节点；不创建新容器，避免孤儿节点）
    Investigation.BuildHintLayer()
    Investigation.BuildHitLayer()
    Investigation.BuildDebugLayer()   -- 严格跟随 currentScene：清空旧框，按新场景重建

    print("[investigate] SetScene -> scene=" .. tostring(sceneId)
        .. " hints=" .. tostring(#Investigation.GetCurrentHotspots()))
end

-- ----------------------------------------------------------------------------
-- 1.1 重置所有热点 visited 状态（进入第一关时由 main.lua 调用，与 investigated_ 同步）
-- ----------------------------------------------------------------------------
function Investigation.ResetVisited()
    for _, hs in ipairs(Investigation.hotspots) do
        hs.visited = false
    end
    for _, hs in ipairs(Investigation.hotspots) do
        local w = hintWidgets_[hs.id]
        if w then StopBreathe(w) end
    end
    hintWidgets_ = {}
    hintBreatheWidgets_ = {}
    lockOnQueue_ = {}
    lockOnIndex_ = 1
    lockOnElapsed_ = 0
    lockOnActive_ = false
    debugScanVisible_ = false
    if investHintWidget_ then
        investHintWidget_:SetVisible(false)
        Investigation.BuildHintLayer()
    end
    if investHitWidget_ then
        investHitWidget_:SetVisible(false)
        Investigation.BuildHitLayer()
    end
    if investDbgWidget_ then
        investDbgWidget_:SetVisible(false)
        investDbgWidget_:ClearChildren()
    end
end

function Investigation.SetHintVisited(id, isVisited)
    local feedback = hintWidgets_[id]
    if not feedback then return end
    local hs = Investigation.GetHotspot(id)
    if hs then hs.visited = isVisited == true end
    if isVisited then
        StopBreathe(feedback)
        feedback:SetStyle({
            opacity = 0.48,
            backgroundColor = { 50, 75, 95, 12 },
            borderColor = { 100, 145, 170, 150 },
            boxShadow = false,
        })
    else
        feedback:SetStyle({
            opacity = 1,
            backgroundColor = { 80, 190, 230, 16 },
            borderColor = { 120, 225, 255, 185 },
            boxShadow = { { x = 0, y = 0, blur = 6, spread = 0, color = { 120, 220, 255, 55 } } },
        })
        if Investigation.scanMode then StartBreathe(feedback) end
    end
    feedback:SetVisible(true)
end

-- 已调查线索仍保留在场景中，降低亮度并停止呼吸动画。
function Investigation.HideHint(id)
    Investigation.SetHintVisited(id, true)
end

-- ----------------------------------------------------------------------------
-- 2. 命中测试
--    event.x / event.y 为 UI 库已转换的 base pixel 本地坐标（覆盖层 Panel 即全屏），
--    用 UI.GetWidth()/UI.GetHeight() 归一化为 0..1 百分比后与热点矩形比较。
-- ----------------------------------------------------------------------------
---@param event PointerEvent
---@return string|nil 命中则返回热点 id，否则 nil
function Investigation.HitTest(event)
    local w = UI.GetWidth()
    local h = UI.GetHeight()
    if w <= 0 or h <= 0 then
        print("[investigate] HitTest skipped: invalid UI size")
        return nil
    end

    local px = event.x / w
    local py = event.y / h

    for _, hotspot in ipairs(Investigation.GetCurrentHotspots()) do
        if px >= hotspot.x and px <= hotspot.x + hotspot.w
           and py >= hotspot.y and py <= hotspot.y + hotspot.h then
            return hotspot.id
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- 2.1 按 id 取热点条目（用于翻转 visited 状态 / 读取 type）
-- ----------------------------------------------------------------------------
---@param id string
---@return table|nil
function Investigation.GetHotspot(id)
    for _, hs in ipairs(Investigation.hotspots) do
        if hs.id == id then return hs end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- 3. 点击处理入口（绑定到透明点击层的 onClick）
--    命中后按 type 派发到对应既有入口；未命中输出 miss。自身不改游戏状态（除 visited）。
-- ----------------------------------------------------------------------------
---@param widget Widget
---@param event PointerEvent
function Investigation.OnClick(widget, event)
    -- 仅响应主指针（鼠标左键 / 触摸主指），与 UI 库约定一致
    if event and not event:IsPrimaryAction() then
        return
    end

    -- 【排查用】输出命中测试细节：原始坐标 → 百分比 → 命中结果
    local dbgW = UI.GetWidth()
    local dbgH = UI.GetHeight()
    local dbgPx = dbgW > 0 and event.x / dbgW or -1
    local dbgPy = dbgH > 0 and event.y / dbgH or -1
    local dbgId = Investigation.HitTest(event)
    print("[HitTest] screen x=" .. string.format("%.1f", event.x) .. " y=" .. string.format("%.1f", event.y))
    print("[HitTest] size w=" .. tostring(dbgW) .. " h=" .. tostring(dbgH))
    print("[HitTest] percent x=" .. string.format("%.3f", dbgPx) .. " y=" .. string.format("%.3f", dbgPy))
    print("[HitTest] hit=" .. tostring(dbgId))

    local id = Investigation.HitTest(event)
    if id then
        local hs = Investigation.GetHotspot(id)
        local wasVisited = hs and hs.visited or false
        if hs and not wasVisited then
            hs.visited = true
        end
        Investigation.SetHintVisited(id, true)

        if wasVisited then
            print("[investigate]\n" .. "visited: " .. id)
        else
            print("[investigate]\n" .. "first visit: " .. id)
        end

        -- 按类型派发到既有入口（均不修改，仅调用）
        if hs and hs.type == "minor" then
            -- 次要线索：直接展示单条次要线索内容（MinorClues_ → ShowMinorClue 既有通道）
            print("调用:\nShowMinorClue(" .. id .. ")")
            ShowMinorClue(id, nil)
        else
            -- 核心线索：走既有 OnClueClicked
            print("调用:\nOnClueClicked(" .. id .. ")")
            OnClueClicked(id)
        end
    else
        print("[investigate]\n" .. "miss")
    end
end

-- ----------------------------------------------------------------------------
-- 4. 调试可视化层（仅开发用，不影响点击逻辑）
--    - pointerEvents="none"：永不接收事件，纯视觉叠加。
--    - DEBUG_MODE=false 时返回 visible=false 的空 Panel，不进入正式版视觉。
--    - 每个热点一个半透明边框 + id 标签，用于确认点击范围是否准确。
-- ----------------------------------------------------------------------------
-- 扫描标签（科幻 HUD 两行结构）：第一行目标编号，第二行分类名称
-- 已列明者按推荐文本；未列明者回退：第二行用中文 name，第一行留空。
local SCAN_TAG = {
    terminal = { code = "CORE 03", cat = "TERMINAL" },
    photo    = { code = "CORE 02", cat = "MEMORY" },
    locker   = { code = "CORE 01", cat = "LOCKER" },
    ring     = { code = "CORE 04", cat = "UNKNOWN" },
    MN09     = { code = "MINOR 09", cat = "LOCKER" },
    MN01     = { code = "MINOR 01", cat = "CLOCK" },
    MN02     = { code = "MINOR 02", cat = "POD" },
    MN03     = { code = "MINOR 03", cat = "OBJECT" },
    MN04     = { code = "MINOR 04", cat = "TRANSFER LOG" },
    MN05     = { code = "MINOR 05", cat = "CHILD ART" },
    MN06     = { code = "MINOR 06", cat = "MEDICAL" },
    MN07     = { code = "MINOR 07", cat = "LOG" },
    MN08     = { code = "MINOR 08", cat = "CLOTH" },
    MN10     = { code = "MINOR 10", cat = "TRACE" },
    MN11     = { code = "MINOR 11", cat = "NOTICE" },
    MN12     = { code = "MINOR 12", cat = "VIEWPORT" },
}
---@param hs table hotspot 数据
---@return string|nil code 第一行编号
---@return string cat 第二行分类
local function getScanTag(hs)
    local t = SCAN_TAG[hs.id]
    if t then return t.code, t.cat end
    return nil, hs.name or hs.id   -- 未列明：回退中文 name 作为第二行
end

local function GetHotspotLabel(hs)
    local t = SCAN_TAG[hs.id]
    if t and t.cat then
        return t.cat
    end
    return hs.name or hs.id
end

local function BuildClueFeedback(hs)
    local visited = hs.visited
    local function FeedbackStyle(isVisited)
        if isVisited then
            return {
                labelColor = { 140, 170, 190, 205 },
                stateColor = { 125, 155, 175, 190 },
                backgroundColor = { 50, 75, 95, 12 },
                borderColor = { 100, 145, 170, 150 },
                boxShadow = false,
            }
        end
        return {
            labelColor = { 190, 240, 255, 240 },
            stateColor = { 135, 210, 235, 205 },
            backgroundColor = { 80, 190, 230, 16 },
            borderColor = { 120, 225, 255, 185 },
            boxShadow = { { x = 0, y = 0, blur = 6, spread = 0, color = { 120, 220, 255, 55 } } },
        }
    end
    local style = FeedbackStyle(visited)
    local markerColor = visited
        and { 100, 145, 170, 150 }
        or { 135, 225, 255, 220 }
    local MARKER_SIZE = 6
    local MARKER_MARGIN = 8
    local LABEL_FONT_SIZE = 11
    local STATE_FONT_SIZE = 9
    local FEEDBACK_MIN_OPACITY = 0.72
    local FEEDBACK_MAX_OPACITY = 1.0
    local FEEDBACK_BREATHE_DURATION = 1.7
    local function makeStateLabel(text, color)
        return UI.Label {
            id = "clueState_" .. hs.id,
            text = text,
            position = "absolute",
            right = 6,
            bottom = 4,
            fontSize = STATE_FONT_SIZE,
            letterSpacing = 1,
            fontColor = color,
            pointerEvents = "none",
        }
    end
    local feedback = UI.Panel {
        id = "clueFeedback_" .. hs.id,
        position = "absolute",
        left = tostring(hs.x * 100) .. "%",
        top = tostring(hs.y * 100) .. "%",
        width = tostring(hs.w * 100) .. "%",
        height = tostring(hs.h * 100) .. "%",
        pointerEvents = "none",
        backgroundColor = style.backgroundColor,
        borderWidth = 1,
        borderColor = style.borderColor,
        borderRadius = 4,
        boxShadow = style.boxShadow,
        visible = true,
        children = {
            UI.Row {
                id = "clueTag_" .. hs.id,
                width = "100%",
                position = "absolute",
                left = 6,
                top = 4,
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        id = "clueMarker_" .. hs.id,
                        width = MARKER_SIZE,
                        height = MARKER_SIZE,
                        borderRadius = 3,
                        marginRight = MARKER_MARGIN,
                        backgroundColor = markerColor,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        id = "clueLabel_" .. hs.id,
                        text = GetHotspotLabel(hs),
                        whiteSpace = "nowrap",
                        fontSize = LABEL_FONT_SIZE,
                        fontColor = style.labelColor,
                        pointerEvents = "none",
                    },
                },
            },
            makeStateLabel(visited and "已调查" or "未调查", style.stateColor),
        },
    }
    feedback:Animate({
        keyframes = {
            [0] = { opacity = FEEDBACK_MIN_OPACITY },
            [0.5] = { opacity = FEEDBACK_MAX_OPACITY },
            [1] = { opacity = FEEDBACK_MIN_OPACITY },
        },
        duration = FEEDBACK_BREATHE_DURATION,
        easing = "easeInOut",
        loop = true,
        fillMode = "backwards",
    })
    if visited then
        feedback:StopAnimation()
        feedback:SetStyle({ opacity = 0.48 })
    else
        feedback:SetStyle({ opacity = 1 })
        feedback:StopAnimation()
    end
    return feedback
end

---@return Widget 调试层 Panel（始终返回已挂载容器，避免 children 表出现 nil）
function Investigation.BuildDebugLayer()
    local dbgChildren = {}
    if DEBUG_MODE then
        for _, hs in ipairs(Investigation.GetCurrentHotspots()) do
            local tagText = GetHotspotLabel(hs)
            local box = UI.Panel {
                id = "dbg_" .. hs.id,
                position = "absolute",
                left = tostring(hs.x * 100) .. "%",
                top = tostring(hs.y * 100) .. "%",
                width = tostring(hs.w * 100) .. "%",
                height = tostring(hs.h * 100) .. "%",
                pointerEvents = "none",
                backgroundColor = { 80, 220, 255, 18 },
                borderWidth = 1,
                borderColor = { 120, 240, 255, 185 },
                borderRadius = 4,
                children = {
                    UI.Label {
                        id = "clueTag_" .. hs.id,
                        text = tagText,
                        position = "absolute",
                        left = 6,
                        top = 4,
                        whiteSpace = "nowrap",
                        fontSize = 11,
                        fontColor = hs.visited
                            and { 145, 170, 190, 210 }
                            or { 190, 240, 255, 240 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        id = "clueState_" .. hs.id,
                        text = hs.visited and "已调查" or "未调查",
                        position = "absolute",
                        right = 6,
                        bottom = 4,
                        fontSize = 9,
                        letterSpacing = 1,
                        fontColor = hs.visited
                            and { 125, 155, 175, 190 }
                            or { 135, 210, 235, 205 },
                        pointerEvents = "none",
                    },
                },
            }
            -- 轻微呼吸：整体透明度脉动（仅亮度变化，不改尺寸/位置/点击，无圆形光标）
            box:Animate({
                keyframes = {
                    [0]   = { opacity = DBG_BREATHE_MIN },
                    [0.5] = { opacity = DBG_BREATHE_MAX },
                    [1]   = { opacity = DBG_BREATHE_MIN },
                },
                duration = BREATHE_DURATION,
                easing = "easeInOut",
                loop = true,
                fillMode = "backwards",
            })
            dbgChildren[#dbgChildren + 1] = box
        end
    end

    -- 复用已挂载容器（首次构建时创建），避免 SetScene 重建时产生孤儿容器
    if not investDbgWidget_ then
        investDbgWidget_ = UI.Panel {
            id = "investDebug",
            width = "100%",
            height = "100%",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            pointerEvents = "none",
            backgroundColor = { 0, 0, 0, 0 },
            visible = DEBUG_MODE,
            children = {},
        }
    end
    investDbgWidget_:ClearChildren()
    for _, c in ipairs(dbgChildren) do investDbgWidget_:AddChild(c) end
    investDbgWidget_:SetVisible(DEBUG_MODE and debugScanVisible_)
    return investDbgWidget_
end

-- ----------------------------------------------------------------------------
-- 5. 正式探索提示层（轻量反馈，不影响点击 / 弹窗 / 调查逻辑）
--    - pointerEvents="none"：纯视觉叠加，永远不接收事件；独立于 clickLayer。
--    - 未调查热点：半透明微光框 + 简短目标标签，仅在扫描时显示。
--    - 已调查热点：继续隐藏，不改变现有生命周期规则。
--    - DEBUG_MODE=true 时调试框照常显示（BuildDebugLayer 独立）。
-- ----------------------------------------------------------------------------
---@return Widget 点击适配层 Panel（扩大命中区域 + 中心微弱发光点）
function Investigation.BuildHitLayer()
    local hitChildren = {}
    local GLOW_DOT = { { x = 0, y = 0, blur = 8, spread = 0, color = { 120, 220, 255, 90 } } }  -- 微弱发光
    for _, hs in ipairs(Investigation.GetCurrentHotspots()) do
        -- 放大后的命中矩形（居中扩大 HIT_EXPAND），与视觉四角框解耦
        local cx = hs.x + hs.w / 2
        local cy = hs.y + hs.h / 2
        local ew = hs.w * (1 + HIT_EXPAND)
        local eh = hs.h * (1 + HIT_EXPAND)
        local el = (cx - ew / 2) * 100
        local et = (cy - eh / 2) * 100

        -- 中心微弱发光点（可选优化）：锁定后提示目标中心，不遮挡背景，pointerEvents=false
        local dot = UI.Panel {
            id = "hitDot_" .. hs.id,
            position = "absolute",
            left = "50%", top = "50%",
            width = 8, height = 8,
            marginLeft = -4, marginTop = -4,   -- 居中（宽高一半负偏移）
            borderRadius = 999,               -- 圆形
            pointerEvents = "none",
            backgroundColor = { 130, 215, 255, 150 },
            boxShadow = GLOW_DOT,
            visible = (not hs.visited),        -- 已调查不显示
        }

        -- 放大命中面板：透明、pointerEvents=auto、覆盖在 clickLayer 之上（同层后插入）
        local hit = UI.Panel {
            id = "hitArea_" .. hs.id,
            position = "absolute",
            left = el .. "%", top = et .. "%",
            width = (ew * 100) .. "%", height = (eh * 100) .. "%",
            pointerEvents = "auto",            -- 实际接收点击
            backgroundColor = { 0, 0, 0, 0 },  -- 全透明（仅扩大点击，不改视觉）
            onClick = function(widget, event)
                -- 仅扫描模式下扩大命中；非扫描模式透传底层 clickLayer（不扩大）
                if not Investigation.scanMode then return end
                -- 把点击映射到该热点中心坐标，复用既有 OnClick → HitTest（逻辑零改动）
                local w = UI.GetWidth()
                local h = UI.GetHeight()
                local synth = PointerEvent.new(PointerEvent.Types.PointerUp, {
                    x = cx * w,
                    y = cy * h,
                    button = event and event.button or PointerEvent.Button.Left,
                    pointerType = event and event.pointerType or PointerEvent.PointerTypes.Mouse,
                    isPrimary = true,
                })
                Investigation.OnClick(widget, synth)
            end,
            children = { dot },
        }
        hitWidgets_[hs.id] = hit
        hitChildren[#hitChildren + 1] = hit
    end

    -- 复用已挂载容器（首次构建时创建），避免 SetScene 重建时产生孤儿容器
    if not investHitWidget_ then
        investHitWidget_ = UI.Panel {
            id = "investHit",
            width = "100%",
            height = "100%",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            pointerEvents = "none",            -- 容器不接收；子面板按需 auto
            backgroundColor = { 0, 0, 0, 0 },
            visible = Investigation.scanMode, -- 由扫描模式控制整体显隐
            children = {},
        }
    end
    investHitWidget_:ClearChildren()
    for _, c in ipairs(hitChildren) do investHitWidget_:AddChild(c) end
    investHitWidget_:SetVisible(Investigation.scanMode)
    return investHitWidget_
end

---@return Widget 提示层 Panel
function Investigation.BuildHintLayer()
    local feedbackChildren = {}
    local currentHotspots = Investigation.GetCurrentHotspots()
    for _, hs in ipairs(currentHotspots) do
        local feedback = BuildClueFeedback(hs)
        feedbackChildren[#feedbackChildren + 1] = feedback
    end
    if not investHintWidget_ then
        investHintWidget_ = UI.Panel {
            id = "investHint",
            width = "100%",
            height = "100%",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            pointerEvents = "none",
            backgroundColor = { 0, 0, 0, 0 },
            visible = Investigation.scanMode,
            children = {},
        }
    end
    investHintWidget_:ClearChildren()
    hintWidgets_ = {}
    hintBreatheWidgets_ = {}
    for index, child in ipairs(feedbackChildren) do
        investHintWidget_:AddChild(child)
        local hs = currentHotspots[index]
        if hs then
            hintWidgets_[hs.id] = child
            hintBreatheWidgets_[hs.id] = child
        end
    end
    investHintWidget_:SetVisible(Investigation.scanMode)
    return investHintWidget_
end

-- ----------------------------------------------------------------------------
-- 6. 扫描模式（基础框架，本阶段仅做状态切换 + 提示层显隐，无复杂动画）
--    扫描模式用于玩家主动「探查」场景：开扫描时显示未调查热点的轻提示层，
--    关闭扫描时隐藏。点击热点逻辑完全不变（core→OnClueClicked / minor→ShowMinorClue）。
-- ----------------------------------------------------------------------------

--- 进入扫描模式：显示当前场景所有线索提示（已调查降亮度，未调查保持呼吸）
function Investigation.StartScan()
    Investigation.scanMode = true
    for _, hs in ipairs(Investigation.GetCurrentHotspots()) do
        local w = hintWidgets_[hs.id]
        if w then
            w:SetVisible(true)
            if hs.visited then
                StopBreathe(w)
                w:SetStyle({
                    opacity = 0.48,
                    backgroundColor = { 50, 75, 95, 12 },
                    borderColor = { 100, 145, 170, 150 },
                    boxShadow = false,
                })
            else
                w:SetStyle({
                    opacity = 1,
                    backgroundColor = { 80, 190, 230, 16 },
                    borderColor = { 120, 225, 255, 185 },
                    boxShadow = { { x = 0, y = 0, blur = 6, spread = 0, color = { 120, 220, 255, 55 } } },
                })
                StartBreathe(w)
            end
        end
    end
    if investHintWidget_ then
        investHintWidget_:SetVisible(true)
    end
    if investHitWidget_ then
        investHitWidget_:SetVisible(true)
    end
    -- 扫描期间临时显示 DEBUG 调试框（仅视觉层），用于验证扫描玩法
    debugScanVisible_ = true
    Investigation.BuildDebugLayer()
    print("[investigate] StartScan: scanMode=" .. tostring(Investigation.scanMode))
end

--- 退出扫描模式：停止呼吸动画并隐藏扫描提示层
function Investigation.EndScan()
    Investigation.scanMode = false
    if investHintWidget_ then
        for _, hs in ipairs(Investigation.hotspots) do
            local w = hintWidgets_[hs.id]
            if w then StopBreathe(w) end
        end
        investHintWidget_:SetVisible(false)
    end
    -- 点击适配层（放大命中区域）随扫描一并隐藏，退出后回到正常点击范围
    if investHitWidget_ then investHitWidget_:SetVisible(false) end
    -- 退出扫描即隐藏 DEBUG 调试框（正式游戏常驻隐藏）
    debugScanVisible_ = false
    Investigation.BuildDebugLayer()
    print("[investigate] EndScan: scanMode=" .. tostring(Investigation.scanMode))
end

return Investigation
