-- ============================================================================
-- scripts/gamecontroller.lua
-- 《零点之后》游戏流程控制器
-- 类型: 手机横屏 2D 叙事探索游戏（无物理，纯 UI 交互）
-- 说明: 负责全局章节切换、P1 剧情编排和通用 UI 协调。
--       剧情文本、场景 UI、音频播放和关系状态均由独立模块承载。
-- ============================================================================

local GameController = {}

local UI = require("urhox-libs/UI")
local Story = require("story")
local RunState = require("runstate")
require("p2debug")
local P2Controller = require("p2controller")
local P3Controller = require("p3controller")

P2Controller.Configure({
    continueToP3 = function()
        P3Controller.Enter()
    end,
})
local Investigation = require("investigate")  -- 第一阶段：场景点击调查输入层（仅新增点击层，不修改现有调查逻辑）
local ScanFX = require("scanfx")        -- 扫描启动动画：一次性扫描线（纯视觉反馈层）
local ScanStatus = require("scanstatus")  -- 扫描状态文字 HUD（纯视觉反馈层）
local TerminalRecordsUI = require("terminalrecordsui")  -- P1 记录终端显示层
local P1MinorClues = require("p1minorclues")
local P1Archive = require("p1archive")
local P1StoryFlow = require("p1storyflow")
local VoicePlayer = require("voiceplayer")
local P1ClueController = require("p1cluecontroller")
local P1AskController = require("p1askcontroller")
local P1SceneUI = require("p1sceneui")
local BGMPlayer = require("bgmplayer")  -- 背景音乐播放器（独立 Scene，不与配音共用句柄）
local RelationshipState = require("relationshipstate")
local TitleScreen = require("titlescreen")

-- 音乐任务2：离开 P1 进入 P2 前停止 P1 调查背景音乐。
-- 对全局 EnterP2（p2controller 定义）做一次性透明包装：所有进入 P2 的路径
-- （撤离 / 正常出口 / 倒计时归零 / 章节快进 / 开发入口）统一先停 BGM，再进 P2。
-- 不修改 p2controller.lua，不改变 EnterP2 自身行为语义。
do
    local originalEnterP2 = EnterP2
    function EnterP2()
        print("[BGM] 离开 P1 进入 P2，停止 P1 调查背景音乐")
        BGMPlayer.Stop()
        originalEnterP2()
    end
end

-- ============================================================================
-- 0. 调试开关
-- ============================================================================
local DEBUG_MODE = true

-- P1 场景调查开关：仅控制是否创建旧核心线索按钮（CreateClueButton 四按钮）。
-- false（默认 / 正式）：不创建旧按钮，玩家仅靠场景点击完成调查，验证纯探索体验。
-- true（调试）：恢复旧按钮，作为对照 / 备用测试入口。
-- 只影响按钮显示层，不改变任何调查逻辑（OnClueClicked / 热点系统 / 剧情数据均不动）。
local ENABLE_LEGACY_CLUE_BUTTON = false


-- V0.6 章节入口调试模式（测试2用）：
-- 设为 true 时，启动注入 Legacy V0.5 状态（P1 完成 / P2 解锁 / trust=50），
-- 用于验证「P1 完成且 P2 已解锁」→ P2 占位入口的分流逻辑。
-- 普通玩家流程下保持 false，绝不影响正常游戏。
local DEBUG_LEGACY_BOOT = false


-- ============================================================================
-- 1. 全局状态变量 (Global State)
-- ============================================================================
---@type Widget|nil
local uiRoot_ = nil
local sceneName_ = Story.sceneName

--- 返回已构建的游戏界面根节点。
---@return Widget
local function GetGameRoot()
    if not uiRoot_ then
        error("Game UI root has not been created")
    end
    return uiRoot_
end

--- 取得公共对话层及内容容器，在结构损坏时立即给出明确错误。
---@return Widget dialog
---@return Widget content
local function GetDialogWidgets()
    local root = GetGameRoot()
    local dialog = root:FindById("dialog")
    local content = root:FindById("dialogContent")
    if not dialog then error("Game dialog layer is missing") end
    if not content then error("Game dialog content is missing") end
    return dialog, content
end

--- 标题页 UI 根（V1.0-06B 新增）：与 P1 gameUI / P2 p2Root_ 完全独立，
--- 仅由 UI.SetRoot(titleRoot_) 接管渲染（V1.0-06C-FIX-A 起不再调用
--- SetCurrentUIRoot(titleRoot_)，避免覆盖 uiRoot_ 导致标题按钮切不回 gameUI）。
---@type table|nil
local titleRoot_ = nil

-- V1.0-04E-B UI 根桥接 setter：供 p2controller 写入当前活动 UI 根。
-- uiRoot_ 仍为 main.lua 局部变量，仅经此接口赋值；不改变现有读写逻辑、不新增 getter。
function SetCurrentUIRoot(root)
    uiRoot_ = root
end

-- 第二阶段：场景背景管理接口（不写死，按 sceneId 映射资源路径）
-- 仅新增背景切换能力，不修改背景尺寸/缩放/UI 布局。
---@type table<string, string>
local SCENE_BG_MAP_ = {
    sleep_zone = "image/P1/P1_BG_SleepPodRoom_v01.png",   -- 当前休眠区背景（保持不变）
    facility_zone = "image/P1/P1_BG_FacilityZone_v01.png",    -- 设施区背景（正式资源接入）
}
---@type Widget|nil
local bgImage_ = nil

-- 按场景切换背景图：仅更新 backgroundImage 资源，保持 backgroundFit=cover 与缩放比例不变。
function SetBackgroundForScene(sceneId)
    if not bgImage_ then
        print("[WARN背景] bgImage_ 尚未初始化，跳过背景切换 sceneId=" .. tostring(sceneId))
        return
    end
    local path = SCENE_BG_MAP_[sceneId]
    if not path then
        print("[WARN背景] 未配置背景资源 sceneId=" .. tostring(sceneId))
        return
    end
    -- [SceneBG] 诊断：确认调用到的 sceneId 与资源路径
    print("[SceneBG]")
    print("  scene = " .. tostring(sceneId))
    print("  path  = " .. tostring(path))
    bgImage_:SetBackgroundImage(path)
    print("[DEBUG背景] 切换背景 sceneId=" .. tostring(sceneId) .. " -> " .. path)
end

-- 全关共享的隐藏回应次数
local responseRemaining_ = 3

-- 每条线索是否已询问过（本版本每点只一次询问）
---@type table<string, boolean>
local asked_ = {}

-- 每条线索是否至少调查过一次
---@type table<string, boolean>
local investigated_ = {}

-- 每条线索保存的玩家与弦问答记录（完整 dialogue 数组）
---@type table<string, table>
local dialogRecord_ = {}

-- 弦是否已终止回答（回应次数耗尽后再次询问触发）
local xianSilent_ = false

-- 第四问后警戒状态：第四问已触发且弦发出过警告，进入禁止调查状态；
-- 之后每次点击任意线索都会触发紧急提醒（不使用一次性标记，每次都触发）
local xianWarningState_ = false

-- 合照线索图片查看阶段标记：为 true 时表示正在看图片，关闭后应继续原调查流程
local photoViewing_ = false

-- 已废弃：曾用于限制紧急提醒只显示一次，现改为每次调查都触发，保留变量以免其余引用报错
local xianEmergencyWarningShown_ = false

-- 开场是否已播放
local openingDone_ = false

-- V1.0-08-P1-A：弦的自由调查阶段耐心值（隐藏变量，不显示于玩家 UI）。
-- 表示弦当前还可接受玩家追问的次数，初始固定为 3。
-- 不影响关系值 / 好感值 / 调查状态 / 询问次数（responseRemaining_）。
local xian_patience = 3

-- V1.0-08-P1-A：P1 负面记忆是否已触发（隐藏状态变量）。
-- 初始为未触发（false）；本次仅创建变量，不添加任何触发逻辑。
local negative_memory_triggered = false

-- V1.0-08-P1-C：玩家在弦耐心耗尽后，再次发起询问的待触发状态。
-- 初始为 false；当耐心为 0 且对尚未询问的核心线索选择「询问弦」时置 true，
-- 供下一批接入负面记忆事件。本次仅设置状态，不播放任何剧情、不启动倒计时。
local p1_negative_memory_pending = false

-- V1.0-08-P1-D：统一耗尽对话是否已播放完成（负面记忆就绪状态）。
-- 初始为 false；统一耗尽对话播放完成后置 true，供下一批接入负面记忆演出。
-- 本批不把 negative_memory_triggered 置 true。
local p1_negative_memory_ready = false

-- V1.0-08-P1-G：撤离事件是否已启动（调查锁定标志）。
-- 初始为 false；Memory Event 播放完成后由 StartEscapeSequence() 置 true，
-- 此后所有调查入口统一提示「广播声越来越近，现在必须离开」，不再允许新调查。
local p1_escape_started = false

-- V1.0-08-P1-F：Memory Event 播放状态由 P1StoryFlow 模块管理。

-- 恢复协助救援授权状态：A/B 选择后为 true，C/D 选择后为 false（默认 false）
local rescueAuthorization_ = false

-- 第四问信任扣减是否已应用（确保只扣一次）
local trustPenaltyApplied_ = false

-- 关卡结束选择「跟弦离开」信任加成是否已应用（确保只加一次）
local trustGainApplied_ = false

-- 第一关剩余调查时间（初始 100，最低不减到 0 以下）
---@type number
local investigationTimeRemaining_ = 100

-- 最近一次调查后的时间状态等级（用于检测跨级变化才触发提醒）
local lastInvestigationTimeLevel_ = "safe"

-- 时间提醒去重状态，与调查时间一同复位。
local timeWarningShown_ = false
local timeDangerShown_ = false

-- 第一关独立可见倒计时（180 秒，与调查时间系统相互独立，不互相影响）
---@type number
local levelTimeRemaining_ = 180

-- 倒计时是否已启动：开场、恢复协助阶段不计时，进入自由调查时才启动
local levelTimerStarted_ = false

-- 紧急倒计时阶段：第四问触发后开启，此阶段普通 dialog 弹窗不再暂停倒计时
local emergencyCountdownPhase_ = false

-- 归零事件是否已处理（确保 OnTimeUp 只触发一次）
local timeUpHandled_ = false

-- 最近一次刷新到 UI 的整数秒数（避免每帧重复 SetText）
local lastDisplayedSecs_ = 180

-- 倒计时文本控件引用（CreateUI 中赋值）
local countdownLabel_ = nil

-- 将剩余秒数格式化为 MM:SS（供 Escape 等位置统一显示倒计时）
local function FormatCountdown(secs)
    local s = math.max(0, math.floor(secs))
    local m = math.floor(s / 60)
    return string.format("%02d:%02d", m, s % 60)
end

-- DEBUG布局：下一帧打印记录弹窗尺寸的一次性标记
local pendingRecordDebug_ = false
local pendingRecordLabel_ = nil
local pendingRecordScroll_ = nil

-- Minor 详情滚动弹窗状态由 P1MinorClues 模块管理。

-- ============================================================================
-- 2. 生命周期函数 (Lifecycle)
-- ============================================================================

-- P1 线索档案数据与获得状态由 P1Archive 模块管理。

---@type function
local ConfigureP1MinorClues

function GameController.Start()
    graphics.windowTitle = "废弃休眠区"
    -- 手机横屏（保持不变）
    graphics:SetOrientations("Landscape")

    InitUI()
    CreateUI()
    ConfigureP1MinorClues()
    SubscribeToEvents()

    print("=== Game Started: " .. sceneName_ .. " ===")

    -- V0.6-03 章节入口：先初始化 RunState，再判断进入哪一章
    InitRunState()

    -- V1.0-06B：显示标题页接管 UI Root，章节分流由标题页主按钮触发。
    -- CheckChapterEntry() 暂不直接调用（下一版本 V1.0-06C 接入主按钮回调）。
    -- CheckChapterEntry()
    ShowTitleScreen()
end

function GameController.Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 2.5 V0.6-03 章节入口网关（数据驱动，最小侵入 P1 流程）
-- ============================================================================

-- 任务1：RunState 初始化接入
-- 在 Start() 中调用：经 RunState.Init() 完成存档读取/默认创建并落盘。
-- 不破坏现有 P1 流程（CheckChapterEntry 仍按状态分流）。
function InitRunState()
    -- 接管存档：读存档或建默认态并落盘（首次启动即生成 save_v06.json）
    RunState.Init()

    -- 调试：测试2 用，注入 Legacy V0.5 状态并落盘（普通玩家此开关为 false，不触发）
    if DEBUG_LEGACY_BOOT then
        RunState.SetCurrent(RunState.CreateLegacyV05RunState())
        RunState.Save()
        print("[DEBUG ChapterEntry] (DEBUG_LEGACY_BOOT) injected legacy V0.5 state")
    end

    print("[DEBUG ChapterEntry] RunState initialized (source="
          .. tostring(RunState.GetCurrent().migrationSource) .. ")")
end

-- 入口日志：确认 RunState 读取正确（任务3）
local function LogChapterEntry(reason)
    local s = RunState.GetCurrent()
    print("[DEBUG ChapterEntry]")
    print("  reason       = " .. tostring(reason))
    print("  chapter      = " .. tostring(s.lastCheckpoint))
    print("  P1Completed  = " .. tostring(s.chapters.P1.completed))
    print("  P2Unlocked   = " .. tostring(s.chapters.P2.unlocked))
    print("  xianTrust    = " .. tostring(s.xianTrust))
end

-- 任务2：章节判断入口
-- 读取当前 RunState，根据状态分流：
--   情况A 新游戏 / P1未完成       → PlayOpening()（保持原 V0.5 行为，不改动）
--   情况B P1完成 且 P2已解锁       → 进入 P2 正式流程（InitP2State + PlayP2Opening）
--   情况C DEBUG_FORCE_P2_ENTRY     → 强制走 P2 流程（开发期快进，普通玩家不可达）
function CheckChapterEntry()
    local s = RunState.GetCurrent()

    -- 情况C：调试强制 P2 入口（仅在 DEBUG_FORCE_P2_ENTRY=true 时生效）
    if DEBUG_FORCE_P2_ENTRY then
        LogChapterEntry("DEBUG_FORCE_P2")
        EnterP2()
        return
    end

    -- 情况B：P1 完成且 P2 解锁 → 进入 P2 正式流程
    if s.chapters.P1.completed and s.chapters.P2.unlocked then
        LogChapterEntry("P1_DONE_P2_UNLOCKED")
        EnterP2()
        return
    end

    -- 情况A：新游戏 / P1 未完成 → 原 P1 开场（不改变 PlayOpening 逻辑）
    LogChapterEntry("P1_FRESH_OR_INCOMPLETE")
    PlayOpening()
end

-- ============================================================================
-- 3. 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

-- 保留给既有入口的薄桥接；次要线索实现全部位于 P1MinorClues。
function ShowMinorClueSequence(clue, options)
    return P1MinorClues.ShowSequence(clue, options)
end

function ShowMinorClue(clueId, onBack)
    return P1MinorClues.Show(clueId, onBack)
end

function ShowScrollableMinorDialog(title, body, buttons, clueId)
    return P1MinorClues.ShowScrollable(title, body, buttons, clueId)
end

function FlushMinorDebug()
    return P1MinorClues.FlushMinorDebug()
end

function GetNearbyMinorClues(coreId)
    return P1MinorClues.GetNearby(coreId)
end

function ShowNearbyMinorClues(coreId, onBack)
    return P1MinorClues.ShowNearby(coreId, onBack)
end

---@param prefix string
---@param event PointerEvent|nil
local function LogPointerPosition(prefix, event)
    if not event then
        print(prefix .. " x=? y=?")
        return
    end
    print(prefix .. " x=" .. tostring(event.x) .. " y=" .. tostring(event.y))
end

-- ============================================================================
-- 4. UI 构建
-- ============================================================================

function CreateUI()
    for _, id in ipairs(Story.order) do
        investigated_[id] = false
        asked_[id] = false
        dialogRecord_[id] = nil
    end
    -- 第二阶段：进入第一关时同步重置场景点击热点的 visited 状态
    if Investigation then Investigation.ResetVisited() end

    P1SceneUI.Configure({
        openTerminal = OnRecordTerminalClicked,
        openArchive = OpenImageGallery,
        onExit = OnExitClicked,
        onReset = function()
            ResetP1()
        end,
        onScan = function(self)
            if Investigation.scanMode then
                Investigation.EndScan()
                self:SetText("SCAN")
            else
                Investigation.StartScan()
                self:SetText("SCANNING")
                ScanStatus.ShowScanning()
                ScanFX.Play(function()
                    Investigation.StartLockOn()
                    ScanStatus.ShowDetected()
                end)
            end
        end,
        onSceneSwitch = function(self)
            if Investigation.currentScene == "facility_zone" then
                Investigation.SetScene("sleep_zone")
                SetBackgroundForScene("sleep_zone")
                self:SetText("设施区")
            else
                Investigation.SetScene("facility_zone")
                SetBackgroundForScene("facility_zone")
                self:SetText("返回休眠区")
            end
        end,
        debugVisible = DEBUG_MODE,
    })
    local sceneWidgets = P1SceneUI.Build()

    uiRoot_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            sceneWidgets.background,

            -- 第一阶段测试：透明全屏点击层（场景点击调查输入层）
            -- 覆盖背景区、pointerEvents=auto 接收点击；位于线索按钮/弹窗之下，
            -- 故自身不遮挡按钮与弹窗，且弹窗打开时优先命中弹窗、本层自动暂停。
            -- 命中热点后调用现有 OnClueClicked(id)，未命中仅输出 debug，不改任何状态。
            UI.Panel {
                id = "clickLayer",
                width = "100%",
                height = "100%",
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                pointerEvents = "auto",
                backgroundColor = { 0, 0, 0, 0 },
                -- 【排查用】确认点击事件是否进入 clickLayer
                onPointerDown = function(event, widget)
                    LogPointerPosition("[clickLayer] down", event)
                end,
                onClick = function(widget, event)
                    LogPointerPosition("[clickLayer] click", event)
                    if event then
                        Investigation.OnClick(widget, event)
                    end
                end,
            },

            -- 正式探索提示层（轻量微光框，pointerEvents=none 不影响点击）
            Investigation.BuildHintLayer(),

            -- 点击区域适配层（手机端扩大命中范围：透明放大面板，pointerEvents=auto，
            -- 仅覆盖在四角框之外的放大区域；非扫描模式不生效。视觉四角框大小不变）
            Investigation.BuildHitLayer(),

            -- 第一阶段调试可视化层（仅开发用，pointerEvents=none 不影响点击）
            Investigation.BuildDebugLayer(),

            -- 扫描启动动画：一次性扫描线（纯视觉，pointerEvents=none 不影响点击）
            ScanFX.BuildLayer(),

            -- 扫描状态文字 HUD（纯视觉，pointerEvents=none 不影响点击）
            ScanStatus.BuildLayer(),

            sceneWidgets.hintLabel,

            -- 底部：记录终端 / 线索档案 / 出口
            sceneWidgets.recordButton,
            sceneWidgets.archiveButton,
            sceneWidgets.exitButton,

            sceneWidgets.resetButton,
            sceneWidgets.scanButton,
            sceneWidgets.sceneSwitchButton,
            sceneWidgets.debugLabel,
            sceneWidgets.countdownLabel,

            -- 占位弹窗容器（内容动态填充）
            CreateDialog(),

            -- 旧核心线索按钮（仅调试用）：由 ENABLE_LEGACY_CLUE_BUTTON 控制是否创建。
            -- 放在 children 末尾：开关关闭时为 nil，ipairs 不会中断前置 UI 构建。
            -- 包裹在 box-none 容器中：开关关闭时不拦截点击，底层 clickLayer 仍正常接收场景点击。
            -- 只影响显示层，不改调查逻辑；onPointerDown/onClick 调试日志保留便于后续排查。
            ENABLE_LEGACY_CLUE_BUTTON and UI.Panel {
                id = "legacyClueButtons",
                width = "100%",
                height = "100%",
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                pointerEvents = "box-none",
                backgroundColor = { 0, 0, 0, 0 },
                onPointerDown = function(event, widget)
                    LogPointerPosition("[clickLayer] down", event)
                end,
                onClick = function(widget, event)
                    LogPointerPosition("[clickLayer] click", event)
                    if event then
                        Investigation.OnClick(widget, event)
                    end
                end,
                children = {
                    -- 第一排：储物柜 / 合照
                    CreateClueButton("locker", "储物柜", 14, 20),
                    CreateClueButton("photo", "合照", 50, 20),
                    -- 第二排：通讯终端 / 黑色金属环
                    CreateClueButton("terminal", "通讯终端", 14, 44),
                    CreateClueButton("ring", "黑色金属环", 50, 44),
                },
            } or nil,
        }
    }

    UI.SetRoot(uiRoot_)

    bgImage_ = uiRoot_:FindById("bgImage")
    countdownLabel_ = uiRoot_:FindById("countdownLabel")

    print("[DEBUG背景] 第一关背景加载成功 P1_BG_SleepPodRoom_v01")

    UpdateDebug()
end

-- ============================================================================
-- 2.6 V1.0-06B 标题页 UI（骨架，06C 接回路由，06D 动态文案）
-- 职责：构建独立 titleRoot_ 并接管 UI Root，显示游戏标题 / 动态进度 / 动态主按钮。
-- 主按钮 onClick 统一执行 UI.SetRoot(uiRoot_) + SetCurrentUIRoot(uiRoot_) +
-- CheckChapterEntry()（不在此复制 P1/P2 分流，路由唯一源头仍是 CheckChapterEntry）。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 开发测试快捷入口（仅 DEBUG_P2_TEST=true 时由标题页调用，正式发布保持 false）
-- 一键进入 P2 隧道：不经过 P1、不修改正式存档、不写 save_v06.json。
-- 直接复用正式 EnterP2()（内部 InitP2State + BuildP2Scene + PlayP2Tunnel + PlayP2Opening），
-- 不复制任何 P2 内部逻辑。
-- ----------------------------------------------------------------------------
function DevEnterP2Tunnel()
    print("[DEV] DevEnterP2Tunnel() reached")
    -- 关闭标题页渲染，切回游戏 UI 根（EnterP2 内部会接管场景 UI Root）。
    local root = GetGameRoot()
    UI.SetRoot(root)
    SetCurrentUIRoot(root)
    -- 直接复用正式 P2 入口：EnterP2() 内部已顺序执行
    -- InitP2State() → BuildP2Scene() → PlayP2Tunnel() → PlayP2Opening()，
    -- 不复制任何 P2 内部逻辑、不要求先完成 P1、不修改正式存档（InitP2State 仅基于
    -- RunState.xianTrust 在内存创建 P2State，不写 save_v06.json）。
    EnterP2()
end

-- TEMP DEBUG：直接进入 P2 诊所，发布前删除
-- 一键进入 P2 诊所休息区 HEARTH：不经过 P1、不播 P2 隧道开场 / 进入诊所前对白、不写正式存档。
-- 仅初始化最小 P2 内存上下文（InitP2State），clinicArea 由 BuildP2ClinicScene("HEARTH") 内部写入；
-- 不自动设置 powerRestored / 登记本 / 电脑文件 / 药柜密码，不改关系值与耐心，不触发记忆。
function DevEnterP2Clinic()
    print("[DEV] DevEnterP2Clinic() reached")
    -- 关闭标题页渲染，切回游戏 UI 根（BuildP2ClinicScene 内部会接管场景 UI Root）。
    local root = GetGameRoot()
    UI.SetRoot(root)
    SetCurrentUIRoot(root)
    local state = InitP2State()
    state.phase = "CLINIC"
    state.checkpoint = "P2_CLINIC_START"
    state.clinicArea = "CLINIC"
    state.clinicTimerStarted = true
    state.clinicTimeRemaining = 180
    BuildP2ClinicScene("CLINIC")
end

function ShowTitleScreen()
    print("[Title] ShowTitleScreen() reached")
    print("[DEBUG TITLE DEV] DEBUG_P2_TEST=" .. tostring(DEBUG_P2_TEST))

    local progressText = "废弃休眠区 · 雪线诊所"

    titleRoot_ = TitleScreen.Show({
        progressText = progressText,
        showDeveloperTools = DEBUG_P2_TEST == true,
        onStart = function()
            print("[TITLE] start game clicked -> P1")
            local root = GetGameRoot()
            UI.SetRoot(root)
            SetCurrentUIRoot(root)
            CreateUI()
            ResetP1()
        end,
        onDevTunnel = function()
            print("[DEV] title test button: 测试 P2 隧道 clicked")
            DevEnterP2Tunnel()
        end,
        onDevClinic = function()
            print("[DEV] title test button: 测试：进入诊所 clicked")
            DevEnterP2Clinic()
        end,
        onDevP3 = function()
            print("[DEV] title test button: 测试：进入 P3 clicked")
            P3Controller.Enter()
        end,
    })

    print("[Title] titleRoot_ set as active UI root; progress=" .. tostring(progressText)
          .. " button=开始游戏")
end

--- 创建一个调查点按钮（占位）
function CreateClueButton(id, label, leftPct, topPct)
    return UI.Button {
        id = "obj_" .. id,
        text = label,
        width = 130,
        height = 90,
        position = "absolute",
        left = leftPct .. "%",
        top = topPct .. "%",
        variant = "default",
        backgroundColor = { 40, 50, 70, 200 },
        borderWidth = 1,
        borderColor = { 90, 110, 150, 180 },
        borderRadius = 10,
        fontSize = 15,
        onClick = function(self)
            OnClueClicked(id)
        end,
    }
end

--- 占位弹窗容器（遮罩 + 内容盒）
function CreateDialog()
    return UI.Panel {
        id = "dialog",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        -- 冷色调半透明遮罩（不遮挡场景主体，仅做 modal 压暗）
        backgroundColor = { 6, 10, 18, 150 },
        children = {
            UI.Panel {
                id = "dialogBox",
                width = "80%",
                maxWidth = 480,
                maxHeight = 460,
                padding = 24,
                gap = 16,
                -- 科幻终端：深色半透明背景 + 青蓝细边框 + 轻微发光 + 圆角
                backgroundColor = { 14, 20, 32, 232 },   -- 深色半透明
                borderRadius = 14,
                borderWidth = 1,
                borderColor = { 110, 200, 255, 200 },     -- 青蓝色细边框
                boxShadow = {                              -- 轻微发光效果
                    { x = 0, y = 0, blur = 18, spread = 0, color = { 80, 170, 240, 80 } },
                },
                alignItems = "center",
                overflow = "hidden",
                children = {
                    UI.Panel {
                        id = "dialogContent",
                        width = "100%",
                        gap = 14,
                        alignItems = "center",
                    },
                }
            }
        }
    }
end

--- 构建「科幻终端」风格标题块（标题 + 青色细分隔线），供各弹窗复用。
--- 纯视觉表现，不改动任何调查 / 剧情逻辑。
---@param title string
---@return Widget
local function BuildTitleBlock(title)
    return UI.Panel {
        id = "dialogTitleBlock",
        width = "100%",
        alignItems = "center",
        gap = 10,
        children = {
            UI.Label {
                text = title,
                fontSize = 21,
                letterSpacing = 2,                          -- 科技感字距
                fontColor = { 150, 230, 255, 255 },         -- 青色冷调标题
                textAlign = "center",
            },
            UI.Panel {
                id = "dialogTitleRule",
                width = "60%",
                height = 1,
                backgroundColor = { 110, 200, 255, 150 },   -- 青色细分隔线
            },
        },
    }
end

-- P1 次要线索模块依赖配置：公共弹窗、图片和主流程只通过回调提供。
ConfigureP1MinorClues = function()
    P1MinorClues.Configure({
        getUIRoot = function()
            return uiRoot_
        end,
        isEscapeStarted = function()
            return p1_escape_started
        end,
        showDialog = ShowDialog,
        showClueImage = ShowClueImage,
        closeDialog = CloseDialog,
        buildTitleBlock = BuildTitleBlock,
        getScreenHeight = function()
            return graphics:GetHeight()
        end,
    })
    P1Archive.Configure({
        getDialog = function()
            local root = uiRoot_
            if not root then return nil, nil end
            return root:FindById("dialog"), root:FindById("dialogContent")
        end,
        buildTitleBlock = BuildTitleBlock,
        closeDialog = CloseDialog,
    })
    P1StoryFlow.Configure({
        showDialog = ShowDialog,
        closeDialog = CloseDialog,
        onRecoveryFinished = function()
            ShowRecoveryChoice()
        end,
        onCore03Finished = function()
            ShowCore03Choice()
        end,
        onExhaustedFinished = function()
            p1_negative_memory_pending = false
            p1_negative_memory_ready = false
            print("[DEBUG]")
            print("Exhausted Finished")
            print("pending=" .. tostring(p1_negative_memory_pending))
            print("ready=" .. tostring(p1_negative_memory_ready))
            print("[DEBUG负面记忆] 统一耗尽对话播放完成，自动开始负面记忆")
            -- 音乐任务2：P1「不是我想这样」负面记忆开始
            BGMPlayer.Play("BGM_P1_MEMORY_BAD_v01", { loop = true, gain = 0.28 })
            TriggerMemoryEvent("P1_NEGATIVE_001")
        end,
        onMemoryEventFinished = function(memoryId)
            negative_memory_triggered = true
            print("[DEBUG]")
            print("Memory Finished")
            print("triggered=" .. tostring(negative_memory_triggered))
            print("[DEBUG负面记忆] Memory Event 播放完成 id=" .. tostring(memoryId))
            local remain = math.ceil(levelTimeRemaining_)
            if levelTimeRemaining_ > 30 then
                levelTimeRemaining_ = 30
                print("[DEBUG倒计时] Memory Event 后收紧倒计时 -> 30s（原剩余=" .. tostring(remain) .. "）")
            else
                print("[DEBUG倒计时] Memory Event 后保持当前倒计时=" .. tostring(remain) .. "s")
            end
            -- 音乐任务2：P1 负面记忆结束 → 恢复调查背景音乐
            BGMPlayer.Play("BGM_P1_INVESTIGATION_AMBIENT_v01", { loop = true, gain = 0.28 })
            StartEscapeSequence()
        end,
    })
    P1ClueController.Configure({
        closeDialog = CloseDialog,
        showDialog = ShowDialog,
        showClueImage = ShowClueImage,
        showPhotoInspectDialog = ShowPhotoInspectDialog,
        showLockerInspectDialog = ShowLockerInspectDialog,
        buildClueButtons = BuildClueButtons,
        getPhotoViewing = function()
            return photoViewing_
        end,
        setPhotoViewing = function(value)
            photoViewing_ = value
        end,
        reopenClue = function(id)
            OnClueClicked(id)
        end,
    })
    P1AskController.Configure({
        getAskState = function(id)
            return {
                isSilent = xianSilent_,
                isAsked = asked_[id] == true,
                responseRemaining = responseRemaining_,
                xianPatience = xian_patience,
                negativeMemoryPending = p1_negative_memory_pending,
                negativeMemoryReady = p1_negative_memory_ready,
                negativeMemoryTriggered = negative_memory_triggered,
            }
        end,
        isCoreClue = P1ClueController.IsCoreClue,
        clearNegativeMemoryReady = function()
            p1_negative_memory_ready = false
        end,
        beginPatienceExhausted = function(id)
            p1_negative_memory_pending = true
            print("[DEBUG负面记忆] 耐心耗尽后再次询问，开始统一耗尽对话 id=" .. tostring(id))
            StartP1PatienceExhaustedDialog()
        end,
        triggerMemoryEvent = TriggerMemoryEvent,
        playCore03 = PlayCore03Dialogue,
        playCoreDialogue = PlayCoreDialogue,
        triggerFourthAsk = TriggerFourthAsk,
    })
end

-- ============================================================================
-- 5. 剧情流程逻辑
-- ============================================================================

--- 自动播放开场；逐句播放主体由 P1StoryFlow 模块负责。
function StartOpeningDialogue(dialogTable, onComplete, dialogTitle)
    return P1StoryFlow.PlaySteps(dialogTable, onComplete, dialogTitle)
end

function PlayOpening()
    openingDone_ = true
    print("=== Opening played ===")
    UpdateDebug()
    -- SCENE01：连续剧情演出，播放结束后自动进入 SCENE01B
    P1StoryFlow.StartOpening {
        onComplete = function()
            PlayRecoveryAssist()
        end,
        dialogTitle = "废弃休眠区",
    }
end


--- 恢复协助阶段：开场苏醒后、自由调查前，玩家第一次决定是否相信弦
--- SCENE01B：连续对白播放由 P1StoryFlow 负责，结束后进入原 A/B/C/D 选择
function PlayRecoveryAssist()
    print("=== Recovery assist phase ===")
    P1StoryFlow.PlayRecoveryAssist {
        dialogTitle = "废弃休眠区",
    }
end

--- A/B/C/D 选择界面（核心交互逻辑：关系值 / 救援授权 / 进入自由调查 均不变）
--- 仅把原有「选择即结算」改为「选择后逐句对白播放」，每句对应一次 ShowDialog，
--- 满足「一句对白 = 一个 Dialog = 一个配音文件」规范。结算逻辑在最后一句结束后执行。
function ShowRecoveryChoice()
    ShowDialog(
        "恢复协助",
        "把手给她，还是拒绝？",
        {
            { label = "A：把手递给她", variant = "default", onClick = PlayRecoveryA },
            { label = "B：检查后允许",   variant = "default", onClick = PlayRecoveryB },
            { label = "C：只拿水，拒绝接入", variant = "default", onClick = PlayRecoveryC },
            { label = "D：推开她",       variant = "default", onClick = PlayRecoveryD },
        })
end

--- 统一结算：保留原关系值 / 授权逻辑，最后进入自由调查
--- @param trustDelta integer 关系值增量
--- @param authorized boolean 救援授权
--- @param label string 选择标识（仅调试）
local function FinishRecovery(trustDelta, authorized, label)
    print("[DEBUG恢复协助] 玩家选择=" .. tostring(label))
    AddXianTrust(trustDelta)
    rescueAuthorization_ = authorized
    print(string.format(
        "[DEBUG恢复授权]\n选择=%s\n救援授权=%s",
        tostring(label), tostring(rescueAuthorization_)))
    local state = GetXianRelationshipState()
    print(string.format(
        "[DEBUG恢复协助关系]\n选择=%s\n当前关系值=%s\n当前状态=%s",
        tostring(label), tostring(GetXianTrust()), state))
    CloseDialog()
    VoicePlayer.Stop()
    EndRecoveryAssist()
end

--- 选择 A：把手递给她（逐句）
function PlayRecoveryA()
    -- ① 旁白
    ShowDialog("恢复协助", "“我”把右手递给弦。\n弦没有握紧。\n只用终端轻触金属环。", {
        { label = "继续", variant = "primary", onClick = function()
            -- ② 弦：好了。喝吧。
            local step = {
                speaker = "弦",
                text = "好了。\n喝吧。",
                voiceId = "P1-S01B-XIAN-A01",
            }
            VoicePlayer.PlayStep(step)
            ShowDialog(step.speaker, step.text, {
                { label = "继续", variant = "primary", onClick = function()
                    -- ③ 我｜内心
                    local step2 = {
                        speaker = "我｜内心",
                        text = "她的动作很熟练。\n像以前做过很多次。",
                        voiceId = "P1-S01B-INNER-A01",
                    }
                    VoicePlayer.PlayStep(step2)
                    ShowDialog(step2.speaker, step2.text, {
                        { label = "结束对话", variant = "primary", onClick = function()
                            -- 保持原逻辑：+6 / 授权 / 进入调查
                            FinishRecovery(6, true, "A")
                        end },
                    })
                end },
            })
        end },
    })
end

--- 选择 B：检查后允许（逐句）
function PlayRecoveryB()
    -- ① 旁白
    ShowDialog("恢复协助", "“我”先检查水袋封口和终端编号。\n弦安静地等。\n没有催促。", {
        { label = "继续", variant = "primary", onClick = function()
            -- ② 我
            local step = {
                speaker = "我",
                text = "水没有开过。\n终端也没有外接记录。",
                voiceId = "P1-S01B-ZERO-B01",
            }
            VoicePlayer.PlayStep(step)
            ShowDialog(step.speaker, step.text, {
                { label = "继续", variant = "primary", onClick = function()
                    -- ③ 弦
                    local step2 = {
                        speaker = "弦",
                        text = "现在可以了吗？",
                        voiceId = "P1-S01B-XIAN-B01",
                    }
                    VoicePlayer.PlayStep(step2)
                    ShowDialog(step2.speaker, step2.text, {
                        { label = "继续", variant = "primary", onClick = function()
                            -- ④ 我
                            local step3 = {
                                speaker = "我",
                                text = "可以。",
                                voiceId = "P1-S01B-ZERO-B02",
                            }
                            VoicePlayer.PlayStep(step3)
                            ShowDialog(step3.speaker, step3.text, {
                                { label = "结束对话", variant = "primary", onClick = function()
                                    -- 保持原逻辑：+3 / 授权 / 进入调查
                                    FinishRecovery(3, true, "B")
                                end },
                            })
                        end },
                    })
                end },
            })
        end },
    })
end

--- 选择 C：只拿水，拒绝接入（逐句）
function PlayRecoveryC()
    -- ① 我
    local step = {
        speaker = "我",
        text = "水我收下。\n程序不用。",
        voiceId = "P1-S01B-ZERO-C01",
    }
    VoicePlayer.PlayStep(step)
    ShowDialog(step.speaker, step.text, {
        { label = "继续", variant = "primary", onClick = function()
            -- ② 弦
            local step2 = {
                speaker = "弦",
                text = "随你。",
                voiceId = "P1-S01B-XIAN-C01",
            }
            VoicePlayer.PlayStep(step2)
            ShowDialog(step2.speaker, step2.text, {
                { label = "继续", variant = "primary", onClick = function()
                    -- ③ 弦
                    local step3 = {
                        speaker = "弦",
                        text = "不舒服就立刻告诉我。",
                        voiceId = "P1-S01B-XIAN-C02",
                    }
                    VoicePlayer.PlayStep(step3)
                    ShowDialog(step3.speaker, step3.text, {
                        { label = "结束对话", variant = "primary", onClick = function()
                            -- 保持原逻辑：关系值不变 / 不授权 / 进入调查
                            FinishRecovery(0, false, "C")
                        end },
                    })
                end },
            })
        end },
    })
end

--- 选择 D：推开她（逐句）
function PlayRecoveryD()
    -- ① 旁白
    ShowDialog("恢复协助", "“我”推开弦的手。\n水袋掉在舱边。\n发出轻响。", {
        { label = "继续", variant = "primary", onClick = function()
            -- ② 我
            local step = {
                speaker = "我",
                text = "别碰我。",
                voiceId = "P1-S01B-ZERO-D01",
            }
            VoicePlayer.PlayStep(step)
            ShowDialog(step.speaker, step.text, {
                { label = "继续", variant = "primary", onClick = function()
                    -- ③ 弦
                    local step2 = {
                        speaker = "弦",
                        text = "……\n好。",
                        voiceId = "P1-S01B-XIAN-D01",
                    }
                    VoicePlayer.PlayStep(step2)
                    ShowDialog(step2.speaker, step2.text, {
                        { label = "继续", variant = "primary", onClick = function()
                            -- ④ 旁白
                            ShowDialog("恢复协助", "弦把终端收回。\n退开半步。", {
                                { label = "结束对话", variant = "primary", onClick = function()
                                    -- 保持原逻辑：-6 / 不授权 / 进入调查
                                    FinishRecovery(-6, false, "D")
                                end },
                            })
                        end },
                    })
                end },
            })
        end },
    })
end

--- 恢复协助统一结束流程：进入自由调查阶段（暂未接入关系值/授权变化）
function EndRecoveryAssist()
    print("[DEBUG恢复协助] 恢复协助阶段结束，进入自由调查")
    -- 进入自由调查时启动第一关 180 秒倒计时。
    levelTimerStarted_ = true
    print("[DEBUG倒计时] 第一关倒计时启动")
    UpdateDebug()
    -- 音乐任务2：玩家获得自由调查操作权 → 开始循环播放 P1 调查背景音乐
    -- 该入口只走一次（A/B/C/D 单次选择），不会在重建/刷新线索/再次 Scan 时重启音乐
    BGMPlayer.Play("BGM_P1_INVESTIGATION_AMBIENT_v01", {
        loop = true,
        gain = 0.28,
    })
end

--- 点击调查点
function OnClueClicked(id)
    -- V1.0-08-P1-G：撤离事件启动后，所有调查入口（核心线索与次要线索均经此函数）
    -- 统一锁定：不进入任何调查/问答，只提示「广播声越来越近，现在必须离开」。
    -- 不删除按钮、不修改已有调查内容，仅增加这一层保护。
    if p1_escape_started then
        ShowDialog("撤离", "广播声越来越近。\n\n现在必须离开。", {
            { label = "返回", variant = "primary", onClick = CloseDialog },
        })
        return
    end

    local c = Story.clues[id]
    if not c then
        print("WARN: unknown clue id = " .. tostring(id))
        return
    end

    -- 第四问后警戒状态：进入禁止调查状态，之后每次点击任意线索都触发弦的紧急提醒
    -- （不消耗调查时间、不修改 investigated_、不影响调查记录与好感/时间系统）
    if xianWarningState_ then
        print("[DEBUG弦警戒] 玩家尝试继续调查，触发紧急提醒")
        ShowDialog("弦", "零，停止调查。\n我们必须离开。", {
            { label = "返回调查", variant = "primary", onClick = CloseDialog },
        })
        return
    end

    -- 合照线索：先查看图片，关闭图片后再进入原调查流程
    -- 图片查看阶段不消耗时间、不修改 investigated_、不改好感；关闭后继续原逻辑
    if P1ClueController.HandlePhotoClicked(id, c.title) then
        return
    end

    -- 记录点击前是否已调查，用于区分状态1/状态2 的关闭按钮文案
    local wasInvestigated = investigated_[id]

    -- 标记调查过（调查本身不消耗回应次数）
    investigated_[id] = true

    -- 仅在首次调查该线索时消耗调查时间（重复点击已调查线索不再消耗）
    local warningTriggeredNow = false
    local dangerTriggeredNow = false
    if not wasInvestigated then
        ConsumeInvestigationTime(10)
        -- 首次调查后做时间阈值检测（只检测，不改变任何剧情）
        if CheckInvestigationTime(30) then
            print("[DEBUG时间事件] 触发低时间检测")
        end
        -- 首次调查后读取时间状态等级（只检测，不改变任何剧情）
        local currentLevel = GetInvestigationTimeLevel()
        print("[DEBUG时间状态事件] 当前状态=" .. tostring(currentLevel))

        -- 仅当发生跨级变化时才触发提醒（与上次记录状态比较）
        if currentLevel == "warning" and lastInvestigationTimeLevel_ ~= "warning"
            and not HasShownTimeWarning() then
            MarkTimeWarningShown()
            print("[DEBUG时间提醒事件] warning提醒首次触发")
            warningTriggeredNow = true
        end

        if currentLevel == "danger" and lastInvestigationTimeLevel_ ~= "danger"
            and not HasShownTimeDanger() then
            MarkTimeDangerShown()
            print("[DEBUG时间提醒事件] danger提醒首次触发")
            dangerTriggeredNow = true
        end

        -- 更新最近一次记录的状态等级
        lastInvestigationTimeLevel_ = currentLevel
    end

    -- 按状态决定显示内容与按钮
    P1ClueController.HandleClueClicked(id, c, asked_[id], wasInvestigated)

    -- warning 首次触发：在调查弹窗之后显示弦的提醒（仅一次，不影响调查流程）
    if warningTriggeredNow then
        ShowDialog("弦", "零，够了。", {
            { label = "返回调查", variant = "primary", onClick = CloseDialog },
        })
    end

    -- danger 首次触发：在调查弹窗之后显示弦的提醒（仅一次，不影响调查流程）
    if dangerTriggeredNow then
        ShowDialog("弦", "零，停止调查。\n我们必须离开。", {
            { label = "返回调查", variant = "primary", onClick = CloseDialog },
        })
    end

    print("Investigated [" .. id .. "] resp=" .. responseRemaining_
        .. " asked=" .. tostring(asked_[id])
        .. " silent=" .. tostring(xianSilent_))
    UpdateDebug()
end

--- 为某调查点构建弹窗按钮（状态1/状态2 使用）
--- closeLabel: 状态1="稍后询问" / 状态2="返回调查"
function BuildClueButtons(id, closeLabel)
    local btns = {}

    if not xianSilent_ then
        -- 未沉默 → 提供「询问弦」（每个线索只能一次，已由 asked_ 控制）
        -- 回调先 CloseDialog() 还原 dialogBox 高度（避免 locker/photo 专属 inspect 窗口
        -- 钉死的固定高度泄漏到问答步骤，导致普通短对白使用大号窗口、出现大片空白），
        -- 再进入原有问答入口 OnAskClicked；不调用任何专属 inspect 弹窗函数。
        table.insert(btns, {
            label = "询问弦",
            variant = "primary",
            onClick = function()
                CloseDialog()
                OnAskClicked(id)
            end,
        })
    end

    -- 关闭弹窗、返回调查界面；不消耗回应次数、不改变状态
    table.insert(btns, {
        label = closeLabel or "返回调查",
        variant = "default",
        onClick = CloseDialog,
    })

    return btns
end

--- 点击「询问弦」：交由 P1AskController 处理询问行为控制
function OnAskClicked(id)
    return P1AskController.HandleAskClicked(id)
end

--- 第 8 句播放完后暂停，弹出 A/B 选择（问答中途分支）
function ShowCore03Choice()
    print("[DEBUG CORE03] 对白暂停，弹出 A/B 选择")
    ShowDialog("损坏的通讯终端", "弦盯着你，等一个回答。", {
        {
            label = "A：我只是在确认事实。",
            variant = "primary",
            onClick = function()
                print("[DEBUG CORE03] 选择 A：关系值不变")
                ShowCore03Branch("A")
            end,
        },
        {
            label = "B：你没有给我别的解释。",
            variant = "default",
            onClick = function()
                print("[DEBUG CORE03] 选择 B：关系值 -5")
                ShowCore03Branch("B")
            end,
        },
    })
end

--- A/B 分线播放：严格一句一句对白，不合并零/弦台词
--- A: 零「我只是在确认事实。」→ 继续 → 弦「行。」→ 结束 → FinishDialog
--- B: 零「你没有给我别的解释。」→ 继续 → 弦「……我解释了。你不信。」→ 结束 → FinishDialog
--- 每句对应一次 ShowDialog，便于后续一句一个配音文件。
--- @param branch string "A" | "B"
function ShowCore03Branch(branch)
    print("[DEBUG CORE03] 分线播放 branch=" .. tostring(branch))
    -- 第一句：零的台词（单独一个弹窗）
    local playerStep = {
        speaker = "我",
        text = branch == "A"
            and "我只是在确认事实。"
            or "你没有给我别的解释。",
        voiceId = branch == "A"
            and "P1-C03-A-ZERO-001"
            or "P1-C03-B-ZERO-001",
    }
    VoicePlayer.PlayStep(playerStep)
    ShowDialog("损坏的通讯终端", playerStep.speaker .. "：\n" .. playerStep.text, {
        {
            label = "继续",
            variant = "primary",
            onClick = function()
                -- 第二句：弦的台词（单独一个弹窗），结束才结算
                local xianStep = {
                    speaker = "弦",
                    text = branch == "A"
                        and "行"
                        or "……\n我解释了。\n你不信。",
                    voiceId = branch == "A"
                        and "P1-C03-A-XIAN-001"
                        or "P1-C03-B-XIAN-001",
                }
                VoicePlayer.PlayStep(xianStep)
                ShowDialog("损坏的通讯终端", xianStep.speaker .. "：\n" .. xianStep.text, {
                    {
                        label = "结束对话",
                        variant = "primary",
                        onClick = function()
                            -- 选择 B：关系值 -5（仅一次，由 FinishDialog 的 asked_ 守卫保证不重复）
                            if branch == "B" then
                                AddXianTrust(-5)
                                print("[DEBUG CORE03] 分支 B 完成，关系值 -5")
                            else
                                print("[DEBUG CORE03] 分支 A 完成，关系值不变")
                            end
                            -- 两条路线结束统一执行 FinishDialog，只扣一次耐心 / 标记一次 asked_
                            FinishDialog("terminal")
                        end,
                    },
                })
            end,
        },
    })
end

--- CORE03 入口（由 OnAskClicked 在 id=="terminal" 时调用）
function PlayCore03Dialogue()
    P1StoryFlow.PlayCore03()
end


--- 普通核心线索逐句对白播放器（CORE01/CORE02/CORE04 共用，CORE03 仍走独立 PlayCore03Dialogue）
--- 与 PlayDialogStep 的区别：每个角色轮次（story.clues[id].dialogue 的每一条 {speaker,text}）
--- 都是【独立弹窗】，不把「我」与「弦」合并到同一弹窗。
--- 数据格式：dialogue = { {speaker="我", text="..."}, {speaker="弦", text="..."}, ... }
--- 末句结束后调用 FinishDialog(id) 一次（由 FinishDialog 内部 asked_ 守卫保证只执行一次结算）。
---@type {id: string, index: integer}|nil
local coreStep_ = nil

--- 播放 dialogue 当前一条角色轮次（独立弹窗）
local function ShowCoreDialogueStep()
    local step = coreStep_
    if not step then
        return
    end
    local c = Story.clues[step.id]
    if not c then
        coreStep_ = nil
        print("[P1] missing core clue: " .. tostring(step.id))
        return
    end
    local d = c.dialogue[step.index]
    if not d then
        return
    end
    -- V1.0 新批次：photo 问答需自适应高度（避免沿用 inspect 长弹窗残留的 dialogBox 固定高度，
    -- 导致短问答步骤被撑到 460px 留大片空白）。仅 photo 在打开前复位 dialogBox 高度，
    -- 其余线索（locker/terminal/ring）原样走 ShowDialog，不受影响。
    if step.id == "photo" then
        local dialog = GetGameRoot():FindById("dialog")
        if dialog then
            local db = dialog:FindById("dialogBox")
            if db then db:SetStyle({ height = "auto" }) end
        end
    end
    local body
    if d.narration then
        body = d.narration
    else
        body = d.speaker .. "：\n“" .. d.text .. "”"
    end
    local isLast = step.index >= #c.dialogue
    local btns = {
        {
            label = isLast and "结束对话" or "继续",
            variant = "primary",
            onClick = function()
                if isLast then
                    coreStep_ = nil
                    FinishDialog(step.id)
                else
                    step.index = step.index + 1
                    ShowCoreDialogueStep()
                end
            end,
        },
    }
    -- 逐句配音：显示当前 step 时播放对应配音
    VoicePlayer.PlayStep(d)
    ShowDialog(c.title, body, btns)
end

--- 入口（由 OnAskClicked 在 id 非 terminal 时调用）：重置逐句进度并播放第一句
---@param id string 核心线索 id
function PlayCoreDialogue(id)
    coreStep_ = { id = id, index = 1 }
    ShowCoreDialogueStep()
end

--- ============================================================================
-- V1.0-08-P1-D：弦耐心耗尽后的统一「结束回答」对话
-- 不进入任何核心线索原问答、不调用 FinishDialog、不标记 asked_、不扣
-- responseRemaining_ / 调查时间 / 关系值 / xian_patience。
-- 复用 ShowDialog 的「继续/结束」按钮模式，按固定步骤逐句播放独立对话。
-- ============================================================================
-- 耗尽对白播放主体由 P1StoryFlow 模块负责。
--- 外部入口：启动统一耗尽对话（由 OnAskClicked 的耐心耗尽拦截调用）。
--- 仅播放独立人物对话并设置状态，不播负面记忆、不播系统广播、不启动倒计时。
function StartP1PatienceExhaustedDialog()
    print("[DEBUG]")
    print("StartP1PatienceExhaustedDialog()")
    P1StoryFlow.PlayExhausted()
end

-- ============================================================================
-- V1.0-08-P1-F：通用 Memory Event 记忆事件系统（跨章节复用播放器）
-- 以后 P1 / P2 / P3 均可调用同一个播放器 TriggerMemoryEvent(memoryId)。
-- 对白数据集中在 MemoryEvents 中，新增记忆只需追加数据，不修改播放器。
-- ============================================================================
-- Memory Event 播放主体由 P1StoryFlow 模块负责。
function TriggerMemoryEvent(memoryId)
    return P1StoryFlow.PlayMemoryEvent(memoryId)
end

-- ============================================================================
-- V1.0-08-P1-G：通用 Escape Sequence 撤离事件系统（跨章节复用）
-- Memory Event 播放结束后由播放器内部调用，立即进入撤离事件。
-- 以后 P2 / P3 也可调用同一个 StartEscapeSequence()。
-- 本批：播放系统广播、显示 00:30、设置锁定标志，不做真实计时。
-- ============================================================================
function StartEscapeSequence()
    print("[DEBUG]")
    print("Escape Started")

    -- 先锁定调查入口，再按顺序播放广播与倒计时，避免后一个弹窗覆盖前一个。
    p1_escape_started = true

    local function ShowEscapeCountdown()
        ShowDialog("撤离倒计时", "剩余时间：" .. FormatCountdown(levelTimeRemaining_), {
            { label = "确认", variant = "primary", onClick = CloseDialog },
        })
        print("[DEBUG撤离] Countdown UI")
    end

    -- ① 系统广播
    local broadcastStep = {
        speaker = "系统广播",
        text = "休眠区将在三十秒后封锁。",
        voiceId = "P1-BROADCAST-001",
    }
    VoicePlayer.PlayStep(broadcastStep)
    ShowDialog(broadcastStep.speaker, broadcastStep.text, {
        {
            label = "确认",
            variant = "primary",
            onClick = function()
                CloseDialog()
                ShowEscapeCountdown()
            end,
        },
    })
    print("[DEBUG撤离] Broadcast")
    print("[DEBUG撤离] Escape Sequence Started")
    print("escape=" .. tostring(p1_escape_started))
end

--- 整段 dialogue 播放完成：消耗 1 次、标记已询问、保存完整记录
function FinishDialog(id)
    if asked_[id] then
        return
    end
    responseRemaining_ = responseRemaining_ - 1
    asked_[id] = true
    dialogRecord_[id] = Story.clues[id].dialogue  -- 保存完整对话数组

    -- V1.0-08-P1-B：四条核心线索（locker/photo/terminal/ring）完成完整问答后，
    -- 仅在第一次完成时递减弦的耐心值（xian_patience）。
    -- 不修改 dialog/UI/关系值/responseRemaining_/已询问标记/线索内容/倒计时事件。
    -- 已询问（asked_ 已为 true）的线索不会再次进入本段（上方 return 拦截），
    -- 故重复点击已询问线索不会再次扣除耐心。
    -- 负数保护：仅在耐心值 > 0 时递减。
    local isCoreClue = (id == "locker" or id == "photo"
        or id == "terminal" or id == "ring")
    if isCoreClue and xian_patience > 0 then
        xian_patience = xian_patience - 1
        print("[DEBUG耐心] 核心线索首次完成问答 id=" .. tostring(id)
            .. " xian_patience 递减 -> " .. tostring(xian_patience))
    end
    print("[DEBUG耐心]")
    print("FinishDialog")
    print("id=" .. tostring(id))
    print("xian_patience=" .. tostring(xian_patience))

    -- 完成一次完整询问弦的对话 → 消耗调查时间（仅首次完成该线索询问时扣）
    print("[DEBUG第四问] 即将消耗询问时间")
    ConsumeInvestigationTime(5)
    print(string.format(
        "[DEBUG第四问检测后] 当前时间=%s 状态=%s 上次状态=%s",
        tostring(investigationTimeRemaining_),
        tostring(GetInvestigationTimeLevel()),
        tostring(lastInvestigationTimeLevel_)))
    print("Ask done [" .. id .. "] resp=" .. responseRemaining_
        .. " (整段播完才扣1次)")
    UpdateDebug()
    CloseDialog()
    VoicePlayer.Stop()
end

--- 第四次询问事件：触发后隐藏询问按钮
function TriggerFourthAsk()
    print("[DEBUG第四问流程] TriggerFourthAsk进入")
    print("[DEBUG第四问] TriggerFourthAsk 已进入")
    print("=== Fourth ask event triggered ===")
    xianSilent_ = true
    -- 仅在首次触发时扣除信任（过度追问使弦降低信任）
    if not trustPenaltyApplied_ then
        trustPenaltyApplied_ = true
        AddXianTrust(-5)
    end
    ShowDialog(Story.fourthAsk.title, Story.fourthAsk.text, {
        { label = "关闭", variant = "primary", onClick = CloseDialog },
    })

    -- 第四次询问作为压力反馈节点：额外消耗调查时间，使时间状态可能进入 warning/danger
    ConsumeInvestigationTime(10)
    print("[DEBUG第四问时间消耗] 剩余时间=" .. tostring(investigationTimeRemaining_))

    -- 第四次询问核心压力反馈：检测时间状态，复用已有 warning/danger 提醒逻辑
    -- （与 OnClueClicked 的跨级变化触发逻辑保持一致）
    print("[DEBUG第四问] 准备进行时间检测")
    local fourthLevel = GetInvestigationTimeLevel()
    print(string.format(
        "[DEBUG第四问检测前] 当前时间=%s 状态=%s 上次状态=%s",
        tostring(investigationTimeRemaining_),
        tostring(fourthLevel),
        tostring(lastInvestigationTimeLevel_)))
    print(string.format(
        "[DEBUG第四问时间检测] 当前时间=%s 状态=%s",
        tostring(investigationTimeRemaining_), tostring(fourthLevel)))
    print(string.format(
        "[DEBUG第四问状态] 当前时间=%s 当前等级=%s 上次等级=%s warning已触发=%s danger已触发=%s",
        tostring(investigationTimeRemaining_),
        tostring(fourthLevel),
        tostring(lastInvestigationTimeLevel_),
        tostring(HasShownTimeWarning()),
        tostring(HasShownTimeDanger())))
    print(string.format(
        "[DEBUG第四问分支判断] 当前=%s 上次=%s warning=%s danger=%s",
        tostring(GetInvestigationTimeLevel()),
        tostring(lastInvestigationTimeLevel_),
        tostring(HasShownTimeWarning()),
        tostring(HasShownTimeDanger())))
    if fourthLevel == "warning" and lastInvestigationTimeLevel_ ~= "warning"
        and not HasShownTimeWarning() then
        MarkTimeWarningShown()
        print("[DEBUG时间提醒事件] warning提醒首次触发")
        ShowDialog("弦", "零，够了。", {
            { label = "返回调查", variant = "primary", onClick = CloseDialog },
        })
    elseif fourthLevel == "danger" and lastInvestigationTimeLevel_ ~= "danger"
        and not HasShownTimeDanger() then
        MarkTimeDangerShown()
        print("[DEBUG时间提醒事件] danger提醒首次触发")
        ShowDialog("弦", "零，停止调查。\n我们必须离开。", {
            { label = "返回调查", variant = "primary", onClick = CloseDialog },
        })
    end
    lastInvestigationTimeLevel_ = fourthLevel

    -- 第四问后警戒状态：warning提醒已触发后，标记弦已发出警告
    xianWarningState_ = true
    print("[DEBUG弦警戒] 第四问后警戒状态开启")

    -- 第四问后进入紧急倒计时阶段：普通 dialog 不再暂停倒计时
    emergencyCountdownPhase_ = true
    print("[DEBUG倒计时] 进入紧急倒计时阶段")

    UpdateDebug()
end

--- 点击记录终端：打开调查记录界面（只读取已保存的 dialogRecord）
function OnRecordTerminalClicked()
    print("[DEBUG] 记录终端按钮已点击  dialogRecord数量=" .. RecordCount())
    local dialog, content = GetDialogWidgets()

    local savedCount = RecordCount()
    local shown = BuildRecordText()
    local hasNewline = string.find(shown.text, "\n", 1, true) ~= nil
    print("[记录终端] dialogRecord 数量=" .. savedCount
        .. " 当前显示记录数量=" .. shown.count)
    print("[记录终端] 字符串长度=" .. string.len(shown.text)
        .. " 包含\\n=" .. tostring(hasNewline))
    print("[记录终端] 完整字符串：\n" .. shown.text)

    TerminalRecordsUI.Open(
        dialog,
        content,
        shown,
        CloseDialog,
        function(recordLabel, scroll)
            pendingRecordDebug_ = true
            pendingRecordLabel_ = recordLabel
            pendingRecordScroll_ = scroll
        end)
end
-- 线索档案数据、顺序和列表控制由 P1Archive 模块管理。
function OpenImageGallery()
    return P1Archive.Open()
end

--- 下一帧打印记录弹窗尺寸（布局已完成）
--- 布局未完成（nan / 0）则保留标记，下一帧继续尝试
function FlushRecordDebug()
    if not pendingRecordDebug_ then
        return
    end
    local label = pendingRecordLabel_
    local scroll = pendingRecordScroll_
    if not label or not scroll then
        pendingRecordDebug_ = false
        pendingRecordLabel_ = nil
        pendingRecordScroll_ = nil
        return
    end
    local ll = label:GetAbsoluteLayout()
    local sl = scroll:GetAbsoluteLayout()
    local cw, ch = scroll:GetContentSize()

    -- 判断数值是否有效（nan 在 Lua 中自不相等）
    local function valid(v)
        return type(v) == "number" and v == v
    end

    local labelOk = ll and valid(ll.w) and valid(ll.h)
    local scrollOk = sl and valid(sl.w) and valid(sl.h)
    local contentOk = valid(cw) and valid(ch) and (cw > 0 or ch > 0)

    -- 布局尚未完成：保留 pendingRecordDebug_，下一帧重试
    if not (labelOk and scrollOk and contentOk) then
        return
    end

    -- 已拿到有效数值：打印并清除标记
    pendingRecordDebug_ = false
    pendingRecordLabel_ = nil
    pendingRecordScroll_ = nil
    print(string.format(
        "[DEBUG布局] Label高度=%s 宽度=%s | ScrollView高度=%s | 内容宽=%s 内容高=%s",
        tostring(ll.h), tostring(ll.w),
        tostring(sl.h),
        tostring(cw), tostring(ch)))
end

--- 拼装调查记录正文（仅读取已保存的 dialogRecord）
--- 返回 { text = 正文, count = 显示记录数 }
function BuildRecordText()
    local lines = {}
    local count = 0
    for _, id in ipairs(Story.order) do
        local rec = dialogRecord_[id]
        if rec then
            count = count + 1
            local c = Story.clues[id]
            table.insert(lines, "线索名称：")
            table.insert(lines, c.title)
            table.insert(lines, "")
            table.insert(lines, "对话记录：")
            for _, d in ipairs(rec) do
                -- 兼容三种数据格式：
                --  {speaker,text}（locker/photo/ring 通用，逐字同步 live 播放的“{speaker}：\n“{text}””）
                --  {who,text} / {narration}（terminal 通讯终端，逐字同步 CORE03_STEPS_）
                --  {player,xian}（历史残留，已不再使用，仅作兜底）
                if d.speaker then
                    table.insert(lines, d.speaker .. "：")
                    table.insert(lines, "“" .. d.text .. "”")
                elseif d.who then
                    table.insert(lines, d.who .. "：")
                    table.insert(lines, "“" .. d.text .. "”")
                elseif d.narration then
                    table.insert(lines, d.narration)
                else
                    table.insert(lines, "我：")
                    table.insert(lines, d.player)
                    table.insert(lines, "")
                    table.insert(lines, "弦：")
                    table.insert(lines, d.xian)
                end
                table.insert(lines, "")
            end
            table.insert(lines, "------------------------------")
            table.insert(lines, "")
        end
    end
    if count == 0 then
        table.insert(lines, "暂无对话记录")
    end
    return { text = table.concat(lines, "\n"), count = count }
end

--- 临时开发功能：重置第一关全部运行状态并重新播放开场→恢复协助
--- 仅用于第一关试玩，制作第二关时整段删除（含调用处的「重新开始」按钮）
--- 不设计正式存档系统；直接复位内存状态后重播开场流程
function ResetP1()
    print("[DEBUG重置] 第一关运行状态重置，准备重播开场")

    -- 关闭当前可能残留的弹窗
    CloseDialog()

    -- 调查 / 询问 / 记录
    responseRemaining_ = 3
    asked_ = {}
    investigated_ = {}
    dialogRecord_ = {}
    xianSilent_ = false
    Investigation.ResetVisited()
    Investigation.SetScene("sleep_zone")

    -- 弦警惕 / 警戒状态
    xianWarningState_ = false
    xianEmergencyWarningShown_ = false

    -- 图片查看阶段标记
    photoViewing_ = false

    -- 开场进度
    openingDone_ = false
    P1StoryFlow.ResetOpening()
    P1StoryFlow.ResetRecoveryAssist()
    P1StoryFlow.ResetCore03()
    P1StoryFlow.ResetExhausted()

    -- 好感 / 授权 / 信任加成（仅复位数值，不改动数值设计）
    RelationshipState.Reset(50)
    rescueAuthorization_ = false
    trustPenaltyApplied_ = false
    trustGainApplied_ = false

    -- 弦耐心值复位（重玩后重新固定为 3，不显示于 UI、不影响其他系统）
    xian_patience = 3

    -- 负面记忆待触发状态复位（重玩后清回 false；negative_memory_triggered 始终保持 false）
    p1_negative_memory_pending = false
    p1_negative_memory_ready = false

    -- 撤离事件状态复位（重玩后恢复 false，调查锁定解除）
    p1_escape_started = false

    -- Memory Event 播放中状态复位（重玩后恢复 false）
    P1StoryFlow.ResetMemoryEvent()

    -- 调查时间系统
    investigationTimeRemaining_ = 100
    lastInvestigationTimeLevel_ = "safe"
    timeWarningShown_ = false
    timeDangerShown_ = false

    -- 次要线索两阶段查看状态（MN03 重玩后重新从初次观察开始）
    P1MinorClues.Reset()

    -- 线索图片档案：重玩后所有图片重新标记为未获得
    P1Archive.Reset()

    -- 第一关可见倒计时
    levelTimeRemaining_ = 180
    levelTimerStarted_ = false
    emergencyCountdownPhase_ = false
    timeUpHandled_ = false
    lastDisplayedSecs_ = 180

    -- 刷新调试面板
    UpdateDebug()

    -- 重新播放开场（开场结束后自动进入恢复协助阶段）
    PlayOpening()
end

--- 点击出口
function OnExitClicked()
    -- 出口三种状态：
    --  1) 统一耗尽对话播放期间（pending/ready）：出口无效，不中断耗尽对话
    --  2) Memory Event 播放期间（memory_event_playing）：出口无效，不中断 Memory
    --  3) Escape 撤离阶段（p1_escape_started）：出口必须可用，立即结算进 P2
    -- 注意：negative_memory_triggered 不再作为锁死条件——Memory 结束后一定进入 Escape，
    --       彼时应由 p1_escape_started 分支放行出口。

    -- 状态1：统一耗尽对话播放期间，出口无效
    if p1_negative_memory_pending
        or p1_negative_memory_ready then
        print("[DEBUG出口] 处于耗尽对话流程中，出口无效，保持当前流程")
        return
    end

    -- 状态2：Memory Event 播放期间，出口无效
    if P1StoryFlow.IsMemoryEventActive() then
        print("[DEBUG出口] Memory Event 播放中，出口无效，保持当前流程")
        return
    end

    -- 状态3：Escape 撤离阶段，出口必须可用——立即结算并进入 P2，不等待倒计时归零
    if p1_escape_started then
        -- 防止与倒计时归零（OnTimeUp）重复进入 P2
        if timeUpHandled_ then
            return
        end
        timeUpHandled_ = true
        levelTimerStarted_ = false
        RunState.SyncP1Result(GetXianTrust())
        RunState.Save()
        CloseDialog()
        EnterP2()
        return
    end

    -- 调查不足（核心线索完成数 < 2）：保持原有限制，不进入第二关。
    if AskedCount() < 2 then
        ShowDialog("出口", "调查还不够充分，现在还走不了。", {
            { label = "继续调查", variant = "default", onClick = function()
                CloseDialog()
            end },
        })
        print("[DEBUG出口] 核心线索不足两条，保持限制")
        return
    end

    -- 正常撤离：已完成至少两条核心线索，且未触发耗尽/记忆/Escape 流程。
    -- 不再播放旧出口剧情 / 旧回忆对白 / 旧 Exit Dialog，直接进入第二关。
    local exitStep = {
        speaker = "弦",
        text = "走吧。",
        voiceId = "P1-EXIT-XIAN-001",
    }
    VoicePlayer.PlayStep(exitStep)
    ShowDialog(exitStep.speaker, exitStep.text, {
        { label = "进入第二章", variant = "primary", onClick = function()
            CloseDialog()
            VoicePlayer.Stop()
            EnterP2()
        end },
    })

    -- 关卡结束选项：玩家最终选择相信弦、跟弦离开，提升双方信任（仅一次）
    if not trustGainApplied_ then
        trustGainApplied_ = true
        AddXianTrust(5)
    end

    -- V0.6-04：P1 结算保存（仅内存同步 + 落盘，不改动任何好感/弹窗/剧情逻辑）
    -- 此点为关系值终值确认后的安全结算时机
    RunState.SyncP1Result(GetXianTrust())
    RunState.Save()

    print("[DEBUG出口] 正常撤离，弦：走吧。")
end

-- ============================================================================
-- 6. 弹窗显示 / 关闭
-- ============================================================================

function ShowDialog(title, body, buttons)
    local dialog, content = GetDialogWidgets()

    content:ClearChildren()

    content:AddChild(BuildTitleBlock(title))
    content:AddChild(UI.Label {
        id = "dialogText",
        text = body,
        fontSize = 14,
        fontColor = { 210, 220, 235, 240 },
        textAlign = "left",
        flexShrink = 1,
        width = "100%",
    })

    local btnRow = UI.ButtonGroup { gap = 12, marginTop = 8, children = {} }
    for _, b in ipairs(buttons) do
        btnRow:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            onClick = b.onClick,
        })
    end
    content:AddChild(btnRow)
    print("[DEBUG UI] ShowDialog按钮布局改为ButtonGroup")

    dialog:SetVisible(true)
end

--- 紧凑弹窗（仅服务于 P2 休息区次要线索的「我｜内心」对白）。
--- 与公共 ShowDialog 完全解耦；仅把 dialogBox 上限高度收紧到一个小值（约 200），
--- 使一行/两行短文本不再占据大块空白；正文仍自动高度、不裁切、按钮居中。
--- 复用公共 dialog / dialogContent 节点，关闭时由 CloseDialog 还原 dialogBox 高度，
--- 因此不影响其它 ShowDialog / ShowLongDialog 调用。
---@param title string
---@param body string
---@param buttons table
function ShowCompactDialog(title, body, buttons)
    local dialog, content = GetDialogWidgets()

    content:ClearChildren()

    content:AddChild(BuildTitleBlock(title))
    content:AddChild(UI.Label {
        text = body,
        fontSize = 14,
        fontColor = { 210, 220, 235, 240 },
        textAlign = "left",
        flexShrink = 1,
        width = "100%",
    })

    local btnRow = UI.ButtonGroup { gap = 12, marginTop = 8, children = {} }
    for _, b in ipairs(buttons) do
        btnRow:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            onClick = b.onClick,
        })
    end
    content:AddChild(btnRow)

    -- 收紧 dialogBox 高度上限：紧凑框，避免单行文本配大空白。
    -- 不设固定 height，仅压低 maxHeight，正文过短则按内容自适应；过长仍受 200 上限约束。
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ maxHeight = 200 })
    end

    dialog:SetVisible(true)
    -- TEMP DEBUG：弹窗显示后的对话层状态（发布前删除）
    if type(LogP2DialogState) == "function" then LogP2DialogState("show_dialog") end
end

--- P1「旧照片」首次 inspect 专属三段式弹窗（photo only，仅由 OnClueClicked("photo") 调用）。
--- 与公共 ShowDialog / ShowLongDialog 完全解耦；不影响其它弹窗与 P2。
--- 结构（明确三段，固定高度，footer 永不被裁切）：
---   PhotoDialogBox(dialogBox 确定高度)
---   └─ LongContent(确定数值高度 = dialogBox 内容区，单列三段)
---        ├─ TitleBlock        (auto)
---        ├─ PhotoBodyScroll   (flexGrow=1, flexBasis=0, 只占剩余空间，内部滚动)
---        └─ PhotoActionFooter (固定 height=64, flexShrink=0, 在 ScrollView 外)
--- 关键：LongContent 高度 = dialogBox 内容区（已扣 dialogBox 上下 padding 24*2），
---       三段的 auto+flexGrow+固定 之和恰好等于该高度，绝不溢出 dialogBox 的 overflow=hidden，
---       因此 footer 完整可见、不参与滚动、不被上方正文挤压。
function ShowPhotoInspectDialog(title, body, buttons)
    local dialog, content = GetDialogWidgets()

    -- 双保险：每次打开都从自适应状态开始（CloseDialog 会还原，这里再复位一次）
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then dialogBox:SetStyle({ height = "auto" }) end
    content:SetStyle({ height = "auto" })
    content:ClearChildren()

    -- dialogBox 确定高度：屏幕高 ~72%，且不超过 440（留足视口余量）
    local H = 440
    if graphics and graphics.GetHeight then
        H = math.min(440, math.max(200, math.floor(graphics:GetHeight() * 0.72)))
    end
    -- dialogBox 上下 padding 各 24 → 内容区 = H - 48，LongContent 据此确定高度（唯一内容子节点，填满不溢出）
    local innerH = H - 48

    -- footer 固定高度：按钮(~44) + 上下 padding(10*2) + 安全余量 = 64
    local FOOTER_H = 64
    local BTN_H = 44

    -- 私有三段容器：高度=内容区，单列三段，gap=12
    local longContent = UI.Panel {
        id = "dialogLongContent",
        width = "100%",
        height = innerH,
        flexDirection = "column",
        gap = 12,
        children = {},
    }

    -- ① 标题（auto，不压缩）
    longContent:AddChild(BuildTitleBlock(title))

    -- ② 正文滚动区：占标题与 footer 之外的剩余空间，内部滚动，不挤压 footer
    local scroll = UI.ScrollView {
        id = "dialogScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = { 20, 25, 38, 255 },
        padding = 14,
        borderRadius = 8,
        children = {
            UI.Label {
                text = body,
                fontSize = 14,
                fontColor = { 210, 220, 235, 240 },
                textAlign = "left",
                width = "100%",
            },
        },
    }
    longContent:AddChild(scroll)

    -- ③ 底部按钮 footer：固定高度、不压缩、不滚动、始终完整可见
    local footer = UI.Row {
        id = "dialogPhotoFooter",
        gap = 12,
        flexWrap = "wrap",
        height = FOOTER_H,
        minHeight = FOOTER_H,
        flexShrink = 0,
        paddingTop = 10,
        paddingBottom = 10,
        justifyContent = "center",
        alignItems = "center",
        children = {},
    }
    for _, b in ipairs(buttons) do
        footer:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            height = BTN_H,
            onClick = b.onClick,
        })
    end
    longContent:AddChild(footer)

    -- 私有容器作为 content 的唯一子节点（高度恰好 = dialogBox 内容区），不溢出 dialogBox
    content:AddChild(longContent)

    -- 钉死 dialogBox 确定高度（CloseDialog 还原 height="auto" 后无残留）
    if dialogBox then
        dialogBox:SetStyle({ height = H })
    end

    dialog:SetVisible(true)
end

--- P1「储物柜/纸条」首次 inspect 专属三段式弹窗（locker only，仅由 OnClueClicked("locker") 调用）。
--- 与公共 ShowDialog / ShowLongDialog / ShowPhotoInspectDialog 完全解耦；不影响其它弹窗与 P2。
--- 复用已验证正常的「旧照片」三段式结构（标题 / 可滚动正文 / 固定底部按钮区），
--- 避免 locker 长文本把底部【询问弦 / 返回调查 / 查看纸条】按钮挤出窗口。
--- 结构（明确三段，固定高度，footer 永不被裁切）：
---   LockerDialogBox(dialogBox 确定高度)
---   └─ LockerContent(确定数值高度 = dialogBox 内容区，单列三段)
---        ├─ TitleBlock        (auto)
---        ├─ LockerBodyScroll  (flexGrow=1, flexBasis=0, 只占剩余空间，内部滚动)
---        └─ LockerActionFooter (minHeight=64, flexShrink=0, 在 ScrollView 外，完整可见)
function ShowLockerInspectDialog(title, body, buttons)
    local dialog, content = GetDialogWidgets()

    -- 双保险：每次打开都从自适应状态开始（CloseDialog 会还原，这里再复位一次）
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then dialogBox:SetStyle({ height = "auto" }) end
    content:SetStyle({ height = "auto" })
    content:ClearChildren()

    -- dialogBox 确定高度：屏幕高 ~72%，且不超过 440（留足视口余量）
    local H = 440
    if graphics and graphics.GetHeight then
        H = math.min(440, math.max(200, math.floor(graphics:GetHeight() * 0.72)))
    end
    -- dialogBox 上下 padding 各 24 → 内容区 = H - 48，三段容器据此确定高度（唯一内容子节点，填满不溢出）
    local innerH = H - 48

    -- footer 最小高度：按钮(~44) + 上下 padding(10*2) + 安全余量 = 64；允许换行时按内容自然增高，绝不裁切
    local FOOTER_MIN_H = 64
    local BTN_H = 44

    -- 私有三段容器：高度=内容区，单列三段，gap=12
    local longContent = UI.Panel {
        id = "lockerLongContent",
        width = "100%",
        height = innerH,
        flexDirection = "column",
        gap = 12,
        children = {},
    }

    -- ① 标题（auto，不压缩）
    longContent:AddChild(BuildTitleBlock(title))

    -- ② 正文滚动区：占标题与 footer 之外的剩余空间，内部滚动，不挤压 footer
    local scroll = UI.ScrollView {
        id = "lockerScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = { 20, 25, 38, 255 },
        padding = 14,
        borderRadius = 8,
        children = {
            UI.Label {
                text = body,
                fontSize = 14,
                fontColor = { 210, 220, 235, 240 },
                textAlign = "left",
                width = "100%",
            },
        },
    }
    longContent:AddChild(scroll)

    -- ③ 底部按钮 footer：固定最小高度、不压缩、不滚动、始终完整可见（换行时自然增高）
    local footer = UI.Row {
        id = "lockerActionFooter",
        gap = 12,
        flexWrap = "wrap",
        minHeight = FOOTER_MIN_H,
        flexShrink = 0,
        paddingTop = 10,
        paddingBottom = 10,
        justifyContent = "center",
        alignItems = "center",
        children = {},
    }
    for _, b in ipairs(buttons) do
        footer:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            height = BTN_H,
            onClick = b.onClick,
        })
    end
    longContent:AddChild(footer)

    -- 私有容器作为 content 的唯一子节点（高度恰好 = dialogBox 内容区），不溢出 dialogBox
    content:AddChild(longContent)

    -- 钉死 dialogBox 确定高度（CloseDialog 还原 height="auto" 后无残留）
    if dialogBox then
        dialogBox:SetStyle({ height = H })
    end

    dialog:SetVisible(true)
end

--- 长文本专用弹窗：标题 + 中间可滚动文本 + 底部固定按钮
--- 仅用于开场自动对白等超长内容
function ShowLongDialog(title, body, buttons)
    local dialog, content = GetDialogWidgets()

    content:ClearChildren()

    -- V1.0 新批次：长文本弹窗使用「私有布局容器」LongContent，不依赖公共 dialogContent 的确定高度。
    -- dialogContent 为所有 Dialog 共用节点（禁改），本身无确定主轴线高度；
    -- 若把 ScrollView 直接挂在 dialogContent 下，其 flexGrow 会因父链无确定高度而塌陷（ScrollView.lua 运行时告警）。
    -- 故自建私有容器，并赋予「确定数值高度」= dialogBox 确定高度 - 上下内边距(各24)，
    -- 使内部 ScrollView 的 flexGrow 能拿到剩余空间、底部按钮行始终留在可视区。
    local maxH = 460
    if graphics and graphics.GetHeight then
        maxH = math.min(460, math.max(160, math.floor(graphics:GetHeight() * 0.85)))
    end
    local innerH = maxH - 48   -- dialogBox padding = 24（上）+ 24（下）

    -- 私有容器：确定数值高度，完全自包含，不改动 dialogContent
    local longContent = UI.Panel {
        id = "dialogLongContent",
        width = "100%",
        height = innerH,        -- 确定数值高度，不依赖父链是否 definite
        flexDirection = "column",
        gap = 12,
        children = {},
    }

    -- 顶部：标题（科幻终端风格标题块）
    longContent:AddChild(BuildTitleBlock(title))

    -- 中间：可滚动文本区域（占弹窗主要空间，超长内部滚动；父 longContent 高度确定 → flexGrow 生效）
    local scroll = UI.ScrollView {
        id = "dialogScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = { 20, 25, 38, 255 },
        padding = 14,
        borderRadius = 8,
        children = {
            UI.Label {
                text = body,
                fontSize = 14,
                fontColor = { 210, 220, 235, 240 },
                textAlign = "left",
                width = "100%",
            },
        },
    }
    longContent:AddChild(scroll)

    -- 底部：固定按钮行（始终可见可点击，不进入滚动区）
    local btnRow = UI.Row { gap = 12, marginTop = 12, flexWrap = "wrap", justifyContent = "center", children = {} }
    for _, b in ipairs(buttons) do
        btnRow:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            onClick = b.onClick,
        })
    end
    longContent:AddChild(btnRow)

    -- 将私有容器挂到公共 dialogContent 下（dialogContent 自身不被改动、不设高度）
    content:AddChild(longContent)

    -- 钉死 dialogBox 确定高度（仅 SetStyle 高度；不改 maxHeight，CloseDialog 还原 height="auto" 后无残留）。
    -- 视口自适应：固定高度改为「不超过屏幕高度 85%」，避免矮屏下弹窗溢出。
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = maxH })
    end

    dialog:SetVisible(true)
end

--- 休息区次要线索专用长文本弹窗（V1.0 P2 本批新增）。
--- 结构复用 ShowLongDialog 的「私有容器 + 可滚动文本 + 底部固定按钮」方案，
--- 但使用独立 node id（restClueContent / restClueScroll / restClueFooter）避免与其它弹窗冲突，
--- 且高度更小（≈屏高 52%，上限 340 / 下限 210），单列短文本不再出现大块空白。
function ShowRestClueDialog(title, body, buttons)
    local dialog, content = GetDialogWidgets()

    content:ClearChildren()

    local screenH = 480
    if graphics and graphics.GetHeight then
        screenH = graphics:GetHeight()
    end
    -- 较小高度：不超过屏高 52%，下限 210、上限 340；不再回到 460 或屏高 85%。
    local maxH = math.min(340, math.max(210, math.floor(screenH * 0.52)))
    local innerH = maxH - 48   -- dialogBox padding = 24（上）+ 24（下）

    -- 私有容器：确定数值高度，完全自包含，不改动 dialogContent。
    local restContent = UI.Panel {
        id = "restClueContent",
        width = "100%",
        height = innerH,
        flexDirection = "column",
        gap = 12,
        children = {},
    }

    -- 顶部：标题（科幻终端风格标题块）
    restContent:AddChild(BuildTitleBlock(title))

    -- 中间：可滚动文本区域（超长内部滚动；父高度确定 → flexGrow 生效）
    local scroll = UI.ScrollView {
        id = "restClueScroll",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = true,
        backgroundColor = { 20, 25, 38, 255 },
        padding = 14,
        borderRadius = 8,
        children = {
            UI.Label {
                text = body,
                fontSize = 14,
                fontColor = { 210, 220, 235, 240 },
                textAlign = "left",
                width = "100%",
                whiteSpace = "normal",
            },
        },
    }
    restContent:AddChild(scroll)

    -- 底部：固定按钮行（始终可见可点击，不进入滚动区）
    local btnRow = UI.Row { id = "restClueFooter", gap = 12, marginTop = 12, flexWrap = "wrap", justifyContent = "center", children = {} }
    for _, b in ipairs(buttons) do
        btnRow:AddChild(UI.Button {
            text = b.label,
            variant = b.variant or "default",
            onClick = b.onClick,
        })
    end
    restContent:AddChild(btnRow)

    -- 将私有容器挂到公共 dialogContent 下（dialogContent 自身不被改动、不设高度）
    content:AddChild(restContent)

    -- 钉死 dialogBox 确定高度（仅 SetStyle 高度；不改 maxHeight，CloseDialog 还原 height="auto" 后无残留）。
    local dialogBox = dialog:FindById("dialogBox")
    if dialogBox then
        dialogBox:SetStyle({ height = maxH })
    end

    dialog:SetVisible(true)
end

--- 通用线索图片查看：接收图片路径，显示图片弹窗，关闭后执行 callback
--- 不处理任何调查逻辑、不修改任何游戏状态（investigated_/时间/好感/记录均不动）
--- 复用现有 dialog 遮罩层，图片通过 backgroundImage 加载资源根下路径
--- @param imagePath string 资源根下图片路径
--- @param callback function|nil 关闭后回调（交由调用方决定后续逻辑）
--- @param title string|nil 可选标题，不传则不显示标题栏
function ShowClueImage(imagePath, callback, title)
    return P1Archive.ShowImage(imagePath, {
        onBack = callback,
        title = title,
    })
end

function CloseDialog()
    local dialog = GetGameRoot():FindById("dialog")
    if dialog then
        -- 还原记录弹窗对高度约束的临时修改，避免影响其他弹窗
        local dialogBox = dialog:FindById("dialogBox")
        if dialogBox then dialogBox:SetStyle({ height = "auto", maxHeight = 460 }) end
        local content = dialog:FindById("dialogContent")
        if content then content:SetStyle({ height = "auto" }) end
        dialog:SetVisible(false)
    end
    -- 关闭即放弃当前逐句对话进度（未结束不消耗次数，可重新询问）
    -- TEMP DEBUG：弹窗关闭后的对话层状态（发布前删除）
    if type(LogP2DialogState) == "function" then LogP2DialogState("close_dialog") end
end

-- ============================================================================
--- 修改玩家与弦的关系状态（好感度）
---@param value number 正负数均可
function AddXianTrust(value)
    local trust = RelationshipState.Add(value)
    print("[DEBUG好感] 当前弦好感度=" .. tostring(trust))
end

--- 获取当前玩家与弦的关系状态（好感度）
---@return number 当前好感度
function GetXianTrust()
    return RelationshipState.Get()
end

--- 判断当前好感度是否达到指定阈值
---@param value number 目标阈值
---@return boolean 当前好感度 >= value 时为 true
function CheckXianTrust(value)
    local result = RelationshipState.Meets(value)
    print(string.format(
        "[DEBUG好感检查] 当前好感度=%s 判断阈值=%s 结果=%s",
        tostring(GetXianTrust()), tostring(value), tostring(result)))
    return result
end

--- 根据当前好感度返回关系状态等级字符串
---@return string "trust" | "normal" | "cautious" | "hostile"
function GetXianTrustLevel()
    local level = RelationshipState.GetTrustLevel()
    print(string.format(
        "[DEBUG好感状态] 当前好感度=%s 状态=%s",
        tostring(GetXianTrust()), level))
    return level
end

--- 根据当前弦关系值返回角色关系状态（供后续对白/距离/互动表现使用）
--- 仅读取关系状态模块，不修改任何状态，不影响耐心/时间系统
---@return string "willing" | "observing" | "disappointed" | "leaving"
function GetXianRelationshipState()
    local state = RelationshipState.GetCharacterState()
    print(string.format(
        "[DEBUG弦状态] 当前关系值=%s 状态=%s",
        tostring(GetXianTrust()), state))
    return state
end

--- 减少第一关剩余调查时间（最低减到 0）
---@param value number 消耗量（正数）
function ConsumeInvestigationTime(value)
    investigationTimeRemaining_ = investigationTimeRemaining_ - value
    if investigationTimeRemaining_ < 0 then
        investigationTimeRemaining_ = 0
    end
    print("[DEBUG时间] 剩余调查时间=" .. tostring(investigationTimeRemaining_))
end

--- 获取当前剩余调查时间
---@return number 当前剩余调查时间
function GetInvestigationTime()
    return investigationTimeRemaining_
end

--- 判断当前剩余调查时间是否 <= 指定阈值
---@param value number 阈值
---@return boolean 当前剩余时间 <= value 时为 true
function CheckInvestigationTime(value)
    local result = investigationTimeRemaining_ <= value
    print(string.format(
        "[DEBUG时间检查] 剩余时间=%s 判断阈值=%s 结果=%s",
        tostring(investigationTimeRemaining_), tostring(value), tostring(result)))
    return result
end

--- 根据当前剩余调查时间返回状态等级字符串
---@return string "safe" | "warning" | "danger"
function GetInvestigationTimeLevel()
    local level
    if investigationTimeRemaining_ > 40 then
        level = "safe"
    elseif investigationTimeRemaining_ > 20 then
        level = "warning"
    else
        level = "danger"
    end
    print(string.format(
        "[DEBUG时间状态] 剩余时间=%s 状态=%s",
        tostring(investigationTimeRemaining_), level))
    return level
end

--- 是否已触发过 warning 级别时间提醒
---@return boolean
function HasShownTimeWarning()
    return timeWarningShown_
end

--- 标记 warning 级别时间提醒已触发
function MarkTimeWarningShown()
    timeWarningShown_ = true
    print(string.format(
        "[DEBUG时间提醒状态] warning=%s danger=%s",
        tostring(timeWarningShown_), tostring(timeDangerShown_)))
end

--- 是否已触发过 danger 级别时间提醒
---@return boolean
function HasShownTimeDanger()
    return timeDangerShown_
end

--- 标记 danger 级别时间提醒已触发
function MarkTimeDangerShown()
    timeDangerShown_ = true
    print(string.format(
        "[DEBUG时间提醒状态] warning=%s danger=%s",
        tostring(timeWarningShown_), tostring(timeDangerShown_)))
end

--- 开发测试用：直接设置剩余调查时间（仅 DEBUG，不接入任何游戏流程）
---@param value number 目标剩余时间
function SetInvestigationTimeDebug(value)
    investigationTimeRemaining_ = value
    -- 同步最近状态等级，避免启动即预设 danger/warning 时首次点击误触发提醒
    lastInvestigationTimeLevel_ = GetInvestigationTimeLevel()
    print("[DEBUG时间修改] 当前剩余时间设置为=" .. tostring(investigationTimeRemaining_))
end

-- ============================================================================
-- 7. 调试显示
-- ============================================================================

function InvestigatedCount()
    local n = 0
    for _, id in ipairs(Story.order) do
        if investigated_[id] then n = n + 1 end
    end
    return n
end

function CurrentState()
    if not openingDone_ then
        return "开场"
    end
    if xianSilent_ then
        return "已沉默（询问隐藏）"
    end
    return "调查中"
end

function AskedCount()
    local n = 0
    for _, id in ipairs(Story.order) do
        if asked_[id] then n = n + 1 end
    end
    return n
end

function RecordCount()
    local n = 0
    for _, id in ipairs(Story.order) do
        if dialogRecord_[id] then n = n + 1 end
    end
    return n
end

function UpdateDebug()
    if not DEBUG_MODE then
        return
    end
    local lbl = GetGameRoot():FindById("debugLabel")
    if not lbl then
        return
    end

    local lines = {
        "DEBUG",
        "剩余回应次数：" .. responseRemaining_,
        "已调查线索：" .. InvestigatedCount() .. "/" .. #Story.order,
        "已询问线索：" .. AskedCount() .. "/" .. #Story.order,
        "记录数量：" .. RecordCount(),
        "当前状态：" .. CurrentState(),
    }
    lbl:SetText(table.concat(lines, "\n"))
end

-- ============================================================================
-- 8. 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    -- 单一 Update 入口：P2 更新由 P1 已验证有效的主循环驱动，
    -- 不得在 p2controller 内单独订阅 Update（两种订阅形式均实测不触发）。
    -- 必须放在所有 early-return 之前，确保 P2 阶段（timeUpHandled_=true）每帧仍执行。
    if HandleP2Update then
        HandleP2Update(eventType, eventData)
    end

    -- 延迟打印记录弹窗布局尺寸（下一帧布局已完成）
    FlushRecordDebug()
    -- 延迟打印 Minor 滚动弹窗布局尺寸（下一帧布局已完成）
    FlushMinorDebug()

    -- 第一关可见倒计时：dialog 弹窗显示时暂停计时
    if timeUpHandled_ then
        return
    end

    -- 倒计时未启动（开场/恢复协助阶段）不计时
    if not levelTimerStarted_ then
        return
    end

    local dialog = GetGameRoot():FindById("dialog")
    if dialog and dialog:IsVisible() then
        -- 紧急倒计时阶段：即使弹窗显示也不暂停，制造持续压迫感
        if not emergencyCountdownPhase_ then
            return
        end
    end

    local dt = eventData["TimeStep"]:GetFloat()
    levelTimeRemaining_ = math.max(0, levelTimeRemaining_ - dt)

    -- 整数秒刷新显示，仅在秒数变化时更新文本（MM:SS 格式）
    local secs = math.ceil(levelTimeRemaining_)
    if secs ~= lastDisplayedSecs_ then
        lastDisplayedSecs_ = secs
        if countdownLabel_ then
            local m = math.floor(secs / 60)
            local s = secs % 60
            countdownLabel_:SetText(string.format("%02d:%02d", m, s))
        end
    end

    -- 归零只触发一次 OnTimeUp
    if levelTimeRemaining_ <= 0 and not timeUpHandled_ then
        timeUpHandled_ = true
        OnTimeUp()
    end
end

-- 倒计时归零时的回调：自动进入第二关（不弹确认框、不等待玩家点击）
function OnTimeUp()
    print("[DEBUG倒计时] 时间归零，自动进入第二关")
    EnterP2()
end
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        CloseDialog()
    end
end

return GameController
