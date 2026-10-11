-- SaveAdapter.lua
-- 存档适配层（只负责平台文件读写，不碰任何数据逻辑）
-- 职责边界：
--   - 本模块只做 文件存在检查 / 读取 / cjson 解析 / 写入
--   - 不调用 RunState 的任何数据函数（数据规范化由 runstate.lua 负责）
--   - 业务流程不直接调用 File API，统一经此模块
--
-- 接入说明（后续步骤才会使用，本步骤由 runstate.lua 调用）：
--   local SaveAdapter = require "saveadapter"
--   local data = SaveAdapter.LoadRunStateFromStorage()  -- 失败返回 nil
--   SaveAdapter.SaveRunStateToStorage(stateTable)        -- 失败打印 DEBUG 并返回 false
--
-- 文件命名：相对路径 "save_v06.json"（引擎自动隔离到当前项目/用户目录）

local SaveAdapter = {}

local SAVE_FILE = "save_v06.json"

-- 读取存档
-- 成功：返回解析后的 table
-- 失败（文件不存在 / JSON 损坏 / 读取失败）：返回 nil，并打印 DEBUG 日志
function SaveAdapter.LoadRunStateFromStorage()
    local fileSystem = GetFileSystem()
    if not fileSystem then
        print("[SaveAdapter] ERROR: FileSystem unavailable")
        return nil
    end

    if not fileSystem:FileExists(SAVE_FILE) then
        print("[SaveAdapter] no save file found (" .. SAVE_FILE .. ")")
        return nil
    end

    local file = File(SAVE_FILE, FILE_READ)
    if not (file and file:IsOpen()) then
        print("[SaveAdapter] ERROR: failed to open save file for read")
        return nil
    end

    local raw = file:ReadString()
    file:Close()

    if not raw or raw == "" then
        print("[SaveAdapter] WARN: save file empty, treat as corrupt")
        return nil
    end

    local ok, data = pcall(cjson.decode, raw)
    if not ok or type(data) ~= "table" then
        print("[SaveAdapter] ERROR: corrupt JSON in save file ("
              .. tostring(data) .. ")")
        return nil
    end

    print("[SaveAdapter] save loaded successfully")
    return data
end

-- 写入存档
-- state: 已规范化的 table（由 RunState 负责规范化，本模块只编码写入）
-- 成功：返回 true；失败：打印 DEBUG 并返回 false
function SaveAdapter.SaveRunStateToStorage(state)
    if type(state) ~= "table" then
        print("[SaveAdapter] ERROR: cannot save non-table state")
        return false
    end

    local file = File(SAVE_FILE, FILE_WRITE)
    if not (file and file:IsOpen()) then
        print("[SaveAdapter] ERROR: failed to open save file for write")
        return false
    end

    local ok, encoded = pcall(cjson.encode, state)
    if not ok then
        file:Close()
        print("[SaveAdapter] ERROR: cjson.encode failed: " .. tostring(encoded))
        return false
    end

    file:WriteString(encoded)
    file:Close()

    print("[SaveAdapter] save written (" .. SAVE_FILE .. ")")
    return true
end

return SaveAdapter
