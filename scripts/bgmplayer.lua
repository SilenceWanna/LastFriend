-- ============================================================================
-- scripts/bgmplayer.lua
-- 《零点之后》背景音乐播放器（BGMPlayer）
--
-- 职责：提供独立于 VoicePlayer 的音乐播放能力（循环 BGM 播放 / 停止）。
-- 本模块只做"音乐播放器"，不接入任何 P1/P2/P3 剧情调用点。
--
-- 约定：
--   · 音乐资源根目录   audio/BGM/
--   · 扩展名           .mp3
--   · 资源映射         audio/BGM/<musicId>.mp3
--   · 循环             Sound 资源级 SetLooped（资源由引擎缓存复用，幂等）
--
-- 独立 Scene：
--   · 使用独立的 bgmScene_，与 VoicePlayer 的 voiceScene_ 完全分离；
--   · 使用独立的 currentHandle_ / currentMusicId_，不与配音句柄共用。
--
-- 防叠音：
--   · 播放另一首音乐前先 Stop 旧音乐，禁止叠加；
--   · 同一 musicId 正在播放时直接返回，不重新创建节点。
--
-- 安全降级：
--   · 资源缺失：不做 cache:Exists 前置（避免 WASM 端假阴性阻断播放），
--     直接尝试加载（对齐 VoicePlayer 已验证的白名单思路），失败仅 WARNING，不产生 Lua Error；
--   · Stop 无句柄：安全返回，不报错。
--
-- fadeSeconds 降级：
--   · 本模块不引入 Update 监听 / Timer，fadeSeconds 当前安全降级为立即 Stop。
-- ============================================================================

local Effects = require("urhox-libs/Effects/Effects")

local BGMPlayer = {}

-- 独立音频场景（仅用于循环 BGM，不参与任何 3D 渲染）。
-- 模块级持有，避免被 GC 回收（参照引擎文档"弱引用/顶层对象无人持有"陷阱）。
local bgmScene_ = Scene()
---@type table|nil 当前 BGM 句柄（Effects.PlaySoundLooped 返回值：{node, source, Stop, FadeIn, FadeOut}）
local currentHandle_ = nil
---@type string|nil 当前正在播放的 musicId
local currentMusicId_ = nil

local BGM_DIR_ = "audio/BGM/"
local BGM_EXT_ = ".mp3"

-- 默认音量（暂定 0.28）
local DEFAULT_GAIN_ = 0.28

-- 首批登记的音乐 ID 白名单（本轮只登记，不接入剧情）
---@type table<string, boolean>
local BGM_CATALOG_ = {
    ["BGM_P1_INVESTIGATION_AMBIENT_v01"] = true,
    ["BGM_P1_CLUE_PHOTO_v01"] = true,
    ["BGM_P1_MEMORY_BAD_v01"] = true,
    ["BGM_P2_TUNNEL_AMBIENT_v01"] = true,
    ["BGM_P2_CLINIC_AMBIENT_v01"] = true,
    ["BGM_P2_MEMORY_WARM_v01"] = true,
    ["BGM_P2_MEMORY_BAD_v01"] = true,
    ["BGM_P2_ENDING_BLIZZARD_v01"] = true,
    ["BGM_P3_INVESTIGATION_AMBIENT_v01"] = true,
    ["BGM_ENDING_THEME_LAST_FRIEND_v01"] = true,
}

---@return Scene
local function GetBgmScene()
    return bgmScene_
end

--- 根据 musicId 生成 BGM 资源路径。
--- 规则：audio/BGM/<musicId>.mp3
---@param musicId string 音乐 ID，如 "BGM_P1_INVESTIGATION_AMBIENT_v01"
---@return string 生成的相对资源路径
local function ResolveBgmPath(musicId)
    return BGM_DIR_ .. musicId .. BGM_EXT_
end

--- 停止当前 BGM（立即停止，安全）。
--- 没有句柄时静默返回，不报错；停止后清空 currentHandle_ 与 currentMusicId_。
function BGMPlayer.Stop()
    if currentHandle_ then
        local handle = currentHandle_
        currentHandle_ = nil
        currentMusicId_ = nil
        if handle.Stop then
            handle:Stop()
        end
    end
end

--- 是否正在播放指定音乐。
---@param musicId string 音乐 ID
---@return boolean 当前句柄存在且 musicId 与正在播放的曲目一致时返回 true
function BGMPlayer.IsPlaying(musicId)
    return currentHandle_ ~= nil and currentMusicId_ == musicId
end

--- 设置当前 BGM 音量（仅影响当前正在播放的曲目；停止后重新 Play 用 options.gain）。
---@param gain number 线性增益，0 = 静音，1 = 满音量
function BGMPlayer.SetGain(gain)
    if currentHandle_ and currentHandle_.source then
        currentHandle_.source.gain = gain
    end
end

--- 播放指定 musicId 对应的 BGM。
---@param musicId string 音乐 ID，映射到 audio/BGM/<musicId>.mp3
---@param options? {loop?: boolean, gain?: number} 可选配置
---@return boolean 是否真正发起播放（未登记 / 已在播放同一曲目 / 播放失败时返回 false）
function BGMPlayer.Play(musicId, options)
    print("[BGM] request id=" .. tostring(musicId))
    if not musicId or musicId == "" then
        print("[WARNING BGMPlayer] musicId 为空，跳过播放")
        return false
    end

    options = options or {}
    local loop = options.loop
    if loop == nil then
        loop = true
    end
    local gain = options.gain or DEFAULT_GAIN_

    -- 同一曲目正在播放：直接返回，不重新创建节点
    if BGMPlayer.IsPlaying(musicId) then
        print("[BGM] 已在播放同一曲目，跳过: " .. tostring(musicId))
        return false
    end

    -- 未登记白名单：跳过（正常情况，对应音乐未接入）
    if not BGM_CATALOG_[musicId] then
        print("[WARNING BGMPlayer] musicId 未登记白名单，跳过: " .. tostring(musicId))
        return false
    end

    local path = ResolveBgmPath(musicId)
    print("[BGM] path " .. tostring(path))

    -- 播放另一首音乐前，先停止当前曲目，禁止叠加
    BGMPlayer.Stop()

    -- 播放链：用 VoicePlayer 已验证出声的 Effects.PlaySound 取得 handle，
    -- 不再依赖 cache:Exists 前置与 PlaySoundLooped（避免 WASM 端假阴性/未知失败路径）。
    -- autoRemove=false：循环音乐不能按音长自动删除节点。
    currentHandle_ = Effects.PlaySound(GetBgmScene(), path, {
        gain = gain,
        autoRemove = false,
    })

    if not currentHandle_ then
        print("[WARNING BGMPlayer] Effects.PlaySound 返回 nil（可能加载失败）: " .. tostring(path))
        currentMusicId_ = nil
        return false
    end

    -- 循环：对实际 Sound 资源设置 SetLooped（幂等；资源由引擎缓存复用，重复设置无副作用）
    if currentHandle_.source and currentHandle_.source.sound then
        currentHandle_.source.sound:SetLooped(loop)
    end

    currentMusicId_ = musicId
    print("[BGM] handle=" .. tostring(currentHandle_ ~= nil) .. " loop=" .. tostring(loop))
    return true
end

return BGMPlayer
