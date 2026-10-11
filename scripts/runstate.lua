-- RunState.lua
-- 跨章节运行态（数据层，纯数据 + 内存态操作）
-- 职责边界：
--   - 本模块负责数据结构定义、规范化、内存态同步
--   - 磁盘读写统一委托给 saveadapter.lua（不在此直接调用 File API）
--   - 不含任何 UI 逻辑
--
-- 接入说明：
--   local RunState = require "runstate"
--   RunState.Init()                    -- 启动时：读存档或建默认态并落盘
--   RunState.SyncP1Result(xianTrust_)  -- 在 OnExitClicked 结算点调用（仅内存）
--   RunState.Save()                    -- 结算后调用：写盘
--   local s = RunState.GetCurrent()    -- 读取当前运行态

local RunState = {}
local SaveAdapter = require "saveadapter"

local CURRENT_VERSION = 1

-- 模块级内存态（同一会话内跨 require 复用）
local _current = nil

-- 生成章节解锁/完成状态的默认值
local function defaultChapters()
    return {
        P1 = { unlocked = true,  completed = false },
        P2 = { unlocked = false, completed = false },
    }
end

-- 新存档默认态：第一关已解锁，第二关未解锁，信任度 50，检查点 P1_START
function RunState.CreateDefaultRunState()
    return {
        saveVersion     = CURRENT_VERSION,
        migrationSource = "fresh",
        lastCheckpoint  = "P1_START",
        chapters        = defaultChapters(),
        xianTrust       = 50,
        p2Entry         = {
            route_map = false,
            identity_bracelet = false,
        },   -- P2 → P3 跨关继承物品
        p3_key_photo    = false,
        p3_key_band     = false,
        p3_record_restore = false,
        p3_record_sleep = false,
        p3_memory_cards = {
            sharedPast = false,
            identityBand = false,
            sleepExecution = false,
        },
    }
end

-- 从 V0.5 遗留进度迁移：第一关已完成，第二关已解锁，信任度 50，检查点 P2_START
function RunState.CreateLegacyV05RunState()
    return {
        saveVersion     = CURRENT_VERSION,
        migrationSource = "v0.5-legacy",
        lastCheckpoint  = "P2_START",
        chapters        = {
            P1 = { unlocked = true,  completed = true },
            P2 = { unlocked = true,  completed = false },
        },
        xianTrust       = 50,
        p2Entry         = nil,
        p3_key_photo    = false,
        p3_key_band     = false,
        p3_record_restore = false,
        p3_record_sleep = false,
        p3_memory_cards = {
            sharedPast = false,
            identityBand = false,
            sleepExecution = false,
        },
    }
end

-- 规范化任意外部传入的 state（来自存档读取或旧结构），补齐缺失字段并裁剪范围
-- 处理 nil、缺失字段、xianTrust 越界（钳制到 0~100）
function RunState.NormalizeRunState(state)
    if not state then
        return RunState.CreateDefaultRunState()
    end

    local def = RunState.CreateDefaultRunState()
    local result = {}

    result.saveVersion     = state.saveVersion     or def.saveVersion
    result.migrationSource = state.migrationSource or def.migrationSource
    result.lastCheckpoint  = state.lastCheckpoint  or def.lastCheckpoint

    -- 章节状态：缺失或类型异常时回落默认
    local ch = state.chapters or {}
    result.chapters = {
        P1 = {
            unlocked  = (ch.P1 and ch.P1.unlocked)  == true,
            completed = (ch.P1 and ch.P1.completed) == true,
        },
        P2 = {
            unlocked  = (ch.P2 and ch.P2.unlocked)  == true,
            completed = (ch.P2 and ch.P2.completed) == true,
        },
    }
    -- 兜底：若 P1 已完成则 P2 必须解锁
    if result.chapters.P1.completed then
        result.chapters.P2.unlocked = true
    end

    -- 信任度：非数字回落默认，越界钳制
    local trust = state.xianTrust
    if type(trust) ~= "number" then
        trust = def.xianTrust
    end
    if trust < 0 then trust = 0 end
    if trust > 100 then trust = 100 end
    result.xianTrust = trust

    local p2Entry = state.p2Entry or {}
    result.p2Entry = {
        route_map = p2Entry.route_map == true,
        identity_bracelet = p2Entry.identity_bracelet == true,
    }
    result.p3_key_photo = state.p3_key_photo == true
    result.p3_key_band = state.p3_key_band == true
    result.p3_record_restore = state.p3_record_restore == true
    result.p3_record_sleep = state.p3_record_sleep == true
    local p3Memories = state.p3_memory_cards or {}
    result.p3_memory_cards = {
        sharedPast = p3Memories.sharedPast == true,
        identityBand = p3Memories.identityBand == true,
        sleepExecution = p3Memories.sleepExecution == true,
    }

    return result
end

-- 第一关结算同步（仅内存，不写盘）
-- trust: 传入最终 xianTrust_ 值；缺省则沿用当前内存态值
-- 调用时机：OnExitClicked 结算点（由后续步骤接入）
function RunState.SyncP1Result(trust)
    if not _current then
        _current = RunState.CreateDefaultRunState()
    end

    local t = type(trust) == "number" and trust or _current.xianTrust
    if t < 0 then t = 0 end
    if t > 100 then t = 100 end

    _current.xianTrust = t
    _current.chapters.P1.unlocked  = true
    _current.chapters.P1.completed = true
    _current.chapters.P2.unlocked  = true   -- 第一关完成后解锁第二关
    _current.lastCheckpoint = "P2_START"
end

-- 读取（或惰性初始化）当前内存态
function RunState.GetCurrent()
    if not _current then
        _current = RunState.CreateDefaultRunState()
    end
    return _current
end

-- 直接替换当前内存态（供 saveadapter 载入后调用）
function RunState.SetCurrent(state)
    _current = RunState.NormalizeRunState(state)
    return _current
end

-- 任务2：存档初始化接入
-- 启动时由游戏流程控制器调用：
--   1. 尝试从存档读取
--   2. 存在 → NormalizeRunState 规范化后载入内存
--   3. 不存在 → CreateDefaultRunState 建立默认态
--   4. 将当前内存态落盘（保证首次启动即有一份有效存档）
-- 任何读取异常都由 SaveAdapter 返回 nil，这里安全回落默认态，不崩溃。
function RunState.Init()
    local loaded = SaveAdapter.LoadRunStateFromStorage()
    if loaded then
        _current = RunState.NormalizeRunState(loaded)
        print("[RunState] Init: loaded from storage (source="
              .. tostring(_current.migrationSource) .. ")")
    else
        _current = RunState.CreateDefaultRunState()
        print("[RunState] Init: no valid save, created default (save created)")
    end
    -- 落盘：首次启动创建默认存档；已存在则重写规范化后的合法状态
    RunState.Save()
    return _current
end

-- 任务2：存档写入（委托 SaveAdapter）
-- 调用时机：P1 结算后（OnExitClicked → SyncP1Result → Save）
function RunState.Save()
    local s = RunState.GetCurrent()
    local ok = SaveAdapter.SaveRunStateToStorage(s)
    if not ok then
        print("[RunState] Save: FAILED to persist state")
    end
    return ok
end

-- 调试输出
function RunState.PrintRunState()
    local s = RunState.GetCurrent()
    print("[RunState] ===== RunState Debug =====")
    print("[RunState] saveVersion     : " .. tostring(s.saveVersion))
    print("[RunState] migrationSource : " .. tostring(s.migrationSource))
    print("[RunState] lastCheckpoint  : " .. tostring(s.lastCheckpoint))
    print("[RunState] xianTrust       : " .. tostring(s.xianTrust))
    if s.chapters then
        print("[RunState] P1 unlocked=" .. tostring(s.chapters.P1.unlocked)
              .. " completed=" .. tostring(s.chapters.P1.completed))
        print("[RunState] P2 unlocked=" .. tostring(s.chapters.P2.unlocked)
              .. " completed=" .. tostring(s.chapters.P2.completed))
    end
    print("[RunState] p2Entry         : " .. (s.p2Entry ~= nil and "set" or "nil"))
    print("[RunState] =============================")
end

return RunState
