-- P2State.lua
-- 第二关会话态（数据层，纯数据容器 + 内存态操作，不含任何 UI / 存档 I/O）
-- 本模块只描述第二关运行期的状态数据，绝不存储 UI 对象、回调、音频对象、对话状态。
--
-- 接入示例：
--   local P2State = require "p2state"
--   local p2 = P2State.CreateP2InitialState(RunState.GetCurrent().xianTrust)
--   P2State.ResetP2()
--   P2State.ValidateP2State(p2)

local P2State = {}

local CURRENT_VERSION = 1

-- 信任度 → 初始耐心档位
--   >= 80 → 4（高信任，耐心充足）
--   >= 50 → 3（正常信任）
--   >= 35 → 2（一般信任，耐心偏紧）
--   <  35 → 0（低信任，耐心耗尽，进入对立张力）
local function patienceTier(trust)
    if trust >= 80 then return 4 end
    if trust >= 50 then return 3 end
    if trust >= 35 then return 2 end
    return 0
end

-- 创建第二关初始会话态
-- inheritedTrust: 从 RunState 继承的 xianTrust（第一关结算值）
function P2State.CreateP2InitialState(inheritedTrust)
    local trust = type(inheritedTrust) == "number" and inheritedTrust or 50
    if trust < 0 then trust = 0 end
    if trust > 100 then trust = 100 end

    local patience = patienceTier(trust)

    return {
        stateVersion      = CURRENT_VERSION,
        phase             = "ENTER",          -- 第二关阶段标识（ENTER / EXPLORE / CLIMAX / SETTLE ... 后续扩展）
        checkpoint        = "P2_START",
        initialTrust      = trust,            -- 进入第二关时的继承信任度（固定快照）
        patienceInitial   = patience,         -- 初始耐心档位（由信任度推导，本关固定）
        patienceRemaining = patience,         -- 当前剩余耐心（运行期会被消耗/恢复）
        bodyState         = "NORMAL",         -- 身体状态（NORMAL / FATIGUE / INJURED / CRITICAL ...）
        xianState         = "NEUTRAL",        -- 先（NPC）态度（NEUTRAL / WARY / HOSTILE / TRUST ...）
        inventory         = {
            syringe = false,
            sedative = false,
            route_map = false,
            identity_bracelet = false,
        },  -- P2 物品清单（药物与短效镇静剂后搜身道具）
        dialogRecords     = {},               -- P2 已实际播放的零/弦对白历史（仅运行期）
        dialogRecordIds   = {},               -- P2 对白历史去重索引（仅运行期）
        flags             = {},               -- 剧情/事件布尔标记（纯数据：{ flagName = true }）
        result            = nil,              -- 结算结果（由后续步骤在通关/失败时填充）
        -- V1.0-07N-P1-A：结局分支基础状态承载字段（仅建字段，本批次不接入任何剧情逻辑）。
        -- 弦意识状态：独立于 xianTrust（关系值）/ xianState（态度），仅表达 SOBER/SEDATED。
        xianConscious     = "SOBER",          -- 弦意识轴（"SOBER" 清醒 / "SEDATED" 被短效镇静剂迷晕）
        -- 固定剧情道具状态：仅作未来剧情节点写入位置，本批次禁止设为 true / 加获取逻辑 / 加 inventory 系统。
        hasMap            = false,            -- 路线地图（弦被镇静后搜身取得）
        hasBracelet       = false,            -- 弦身份手环（弦被镇静后摘取）
        hasSoberAgent     = false,            -- 清醒维持剂（可选取得）
        -- V1.0-07N-P2-B1：镇静链路道具状态（仅建字段，本批次不接入获取/使用逻辑）。
        hasSedative       = false,            -- 是否持有短效镇静剂（对弦使用前置）
        hasSyringe        = false,            -- 是否持有针管（对弦使用前置）
        -- V1.0-07N-P3-B：清醒路线医疗代理权限状态（仅建字段，本批次不接入认证/获取逻辑）。
        -- 含义：弦是否已通过腕环认证获得临时医疗代理权限（P2 产生 / P3 消费 / 存档继承，后续单独批次处理）。
        -- 注意：与本关"授权核心是否替换"（coreReplaced）为不同剧情状态，二者不可合并。
        medicalProxy      = false,            -- 是否已获得医疗代理权限
        -- V1.0 P2 第十一批：诊所调查 180 秒倒计时（P2 独立状态，不复用 P1 levelTimeRemaining_ 等）。
        clinicTimeRemaining = 180,            -- 当前剩余秒数（初始 180）
        clinicTimerStarted  = false,         -- 倒计时是否已启动
        clinicTimeUpHandled = false,         -- 归零事件是否已处理（防重复触发）
        -- V1.0 P2 第十二批：第一阶段调查收口状态（弦返回事件 / 入口锁定）。
        clinicPhaseOneComplete  = false,     -- 第一阶段调查是否已结束（收口）
        xianReturnEventPlaying  = false,     -- 弦返回事件是否正在播放（防重复播放）
        -- V1.0 P2 新批次：隧道自由调查双条件触发（与诊所 03:00 Timer 完全独立，互不影响）。
        -- 本批不显示隧道倒计时 UI（仅内部计时 tunnelElapsed 驱动 25 秒条件）。
        tunnelExplorationStarted = false,    -- 隧道自由调查是否开始（进入隧道时置 true）
        tunnelInvestigatedCount  = 0,        -- 已完成的不同隧道调查点数量
        restInvestigatedCount    = 0,        -- 已完成的不同休息区次要线索数量（MINOR-C01~C09）
        tunnelElapsed            = 0,         -- 隧道自由调查累计时间（秒）
        blizzardBroadcastTriggered = false,  -- 暴风雪广播+弦对白是否已播放（防重复）
        blizzardBroadcastPending    = false, -- 条件达成后等待当前 Dialog 关闭再播放
        clinicEntryUnlocked      = false,    -- “进入诊所”是否解锁（广播后解锁）
    }
end

-- 重置第二关会话态（重新进入第二关时调用）
function P2State.ResetP2()
    -- 注意：本函数不持有持久引用，调用方负责重新 CreateP2InitialState 并接管返回值。
    -- 这里仅提供规范化空态构造入口，避免调用方遗漏字段。
    return P2State.CreateP2InitialState(50)
end

-- 校验第二关会话态结构完整性
-- 返回 true/false，并打印不合规项（调试用）
function P2State.ValidateP2State(state)
    local ok = true
    local reason = {}

    if type(state) ~= "table" then
        print("[P2State] Validate FAILED: state is not a table")
        return false
    end

    local required = {
        "stateVersion", "phase", "checkpoint", "initialTrust",
        "patienceInitial", "patienceRemaining", "bodyState",
        "xianState", "inventory", "flags", "result",
    }
    for i = 1, #required do
        local k = required[i]
        if state[k] == nil then
            ok = false
            reason[#reason + 1] = "missing field: " .. k
        end
    end

    if type(state.inventory) ~= "table" then
        ok = false
        reason[#reason + 1] = "inventory is not a table"
    end
    if type(state.flags) ~= "table" then
        ok = false
        reason[#reason + 1] = "flags is not a table"
    end
    if state.dialogRecords == nil then state.dialogRecords = {} end
    if state.dialogRecordIds == nil then state.dialogRecordIds = {} end

    if type(state.initialTrust) ~= "number" then
        ok = false
        reason[#reason + 1] = "initialTrust is not a number"
    end
    if type(state.patienceInitial) ~= "number" then
        ok = false
        reason[#reason + 1] = "patienceInitial is not a number"
    end
    if type(state.patienceRemaining) ~= "number" then
        ok = false
        reason[#reason + 1] = "patienceRemaining is not a number"
    end

    -- V1.0-07N-P1-A：旧存档兼容——新增字段若缺失则自动补默认值，不因此判定校验失败。
    -- 注意：新字段不加入上方 required 列表（否则旧存档会 FAILED），仅在此静默回填。
    if state.xianConscious == nil then
        state.xianConscious = "SOBER"   -- 默认清醒，兼容旧态
    end
    if state.hasMap == nil then state.hasMap = false end
    if state.hasBracelet == nil then state.hasBracelet = false end
    if state.hasSoberAgent == nil then state.hasSoberAgent = false end
    -- V1.0-07N-P2-B1：同上，镇静链路道具字段缺失则静默回填，不加入 required。
    if state.hasSedative == nil then state.hasSedative = false end
    if state.hasSyringe == nil then state.hasSyringe = false end
    -- V1.0-07N-P3-B：医疗代理权限字段缺失则静默回填，不加入 required（避免旧存档 FAILED）。
    if state.medicalProxy == nil then state.medicalProxy = false end
    -- V1.0 P2 新批次：隧道自由调查双条件触发状态（与诊所 03:00 Timer 独立）缺失则静默回填。
    if state.tunnelExplorationStarted == nil then state.tunnelExplorationStarted = false end
    if state.tunnelInvestigatedCount == nil then state.tunnelInvestigatedCount = 0 end
    if state.restInvestigatedCount == nil then state.restInvestigatedCount = 0 end
    if state.tunnelElapsed == nil then state.tunnelElapsed = 0 end
    if state.blizzardBroadcastTriggered == nil then state.blizzardBroadcastTriggered = false end
    if state.blizzardBroadcastPending == nil then state.blizzardBroadcastPending = false end
    if state.clinicEntryUnlocked == nil then state.clinicEntryUnlocked = false end

    if ok then
        print("[P2State] Validate OK")
    else
        print("[P2State] Validate FAILED:")
        for i = 1, #reason do
            print("  - " .. reason[i])
        end
    end
    return ok
end

-- 调试输出
function P2State.PrintP2State(state)
    if not state then
        print("[P2State] (nil state)")
        return
    end
    print("[P2State] ===== P2State Debug =====")
    print("[P2State] stateVersion      : " .. tostring(state.stateVersion))
    print("[P2State] phase             : " .. tostring(state.phase))
    print("[P2State] checkpoint        : " .. tostring(state.checkpoint))
    print("[P2State] initialTrust      : " .. tostring(state.initialTrust))
    print("[P2State] patienceInitial   : " .. tostring(state.patienceInitial))
    print("[P2State] patienceRemaining : " .. tostring(state.patienceRemaining))
    print("[P2State] bodyState         : " .. tostring(state.bodyState))
    print("[P2State] xianState         : " .. tostring(state.xianState))
    print("[P2State] xianConscious     : " .. tostring(state.xianConscious))
    print("[P2State] hasMap            : " .. tostring(state.hasMap))
    print("[P2State] hasBracelet       : " .. tostring(state.hasBracelet))
    print("[P2State] hasSoberAgent     : " .. tostring(state.hasSoberAgent))
    print("[P2State] hasSedative       : " .. tostring(state.hasSedative))
    print("[P2State] hasSyringe        : " .. tostring(state.hasSyringe))
    print("[P2State] medicalProxy      : " .. tostring(state.medicalProxy))
    print("[P2State] inventory         : " .. tostring(#state.inventory) .. " entries")
    print("[P2State] flags             : " .. tostring(#state.flags) .. " entries")
    print("[P2State] result            : " .. (state.result ~= nil and "set" or "nil"))
    print("[P2State] =============================")
end

return P2State
