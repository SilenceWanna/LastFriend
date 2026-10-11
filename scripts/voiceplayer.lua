-- ============================================================================
-- scripts/voiceplayer.lua
-- 《零点之后》逐句配音播放器
--
-- 职责：为逐页对白提供"一句台词 = 一段配音"的一次性播放能力。
-- 只做播放控制，不改动任何 Dialog / UI / 剧情 / 状态 / Timer。
--
-- 约定：
--   · 配音资源根目录   audio/
--   · 扩展名           .mp3
--   · 资源映射（按 voiceId 开头自动进入章节目录）：
--        P1-* → audio/P1/<voiceId>.mp3
--        P2-* → audio/P2/<voiceId>.mp3
--        P3-* → audio/P3/<voiceId>.mp3
--   · ID 来源顺序      step.voiceId > step.audioIds[1] > step.id
--   · 已上传判定       VoiceCatalog 白名单（不做 cache:Exists 前置检查）
--
-- 安全降级：
--   · voiceId 不在白名单 / 章节无法识别 / Effects.PlaySound 返回 nil
--       → 仅 WARNING / 静默跳过，不触发引擎 ERROR、不阻断文字流程
--   · 不再读取或尝试播放 wav（遗留 wav 文件仅不引用，不删除）
--
-- 防叠音：
--   · 每次 Play 前先 Stop 上一句（currentHandle_），避免快速点击叠加
-- ============================================================================

local Effects = require("urhox-libs/Effects/Effects")
local VoiceCatalog = require("voicecatalog")

local VoicePlayer = {}

-- 独立音频场景（仅用于播放一次性配音，不参与任何 3D 渲染）。
-- 模块级持有，避免被 GC 回收（参照引擎文档"弱引用/顶层对象无人持有"陷阱）。
local voiceScene_ = Scene()
---@type table|nil 当前播放句柄（Effects.PlaySound 返回值：{node, source, Stop, FadeOut}）
local currentHandle_ = nil

local VOICE_DIR_ = "audio/"
local VOICE_EXT_ = ".mp3"

local function GetVoiceScene()
    return voiceScene_
end

--- 根据 voiceId 生成配音资源路径。
--- 规则：<P1|P2|P3>-… → Sounds/Voice/<章节目录>/<voiceId>.mp3
---@param voiceId string 配音 ID，如 "P1-S01-XIAN-001"
---@return string|nil 生成的相对资源路径；章节无法识别时返回 nil
local function ResolveVoicePath(voiceId)
    local chapter = voiceId and voiceId:match("^(P%d+)%-")
    if not chapter then
        return nil
    end
    return VOICE_DIR_ .. chapter .. "/" .. voiceId .. VOICE_EXT_
end

--- 停止上一句配音（若存在）。安全调用句柄 Stop 并清空引用。
function VoicePlayer.Stop()
    if currentHandle_ then
        local handle = currentHandle_
        currentHandle_ = nil
        if handle.Stop then
            handle:Stop()
        end
    end
end

--- 播放一句台词对应的配音。
---@param step table 台词 step（取 step.voiceId / step.audioIds[1] / step.id）
---@return boolean 是否真正发起播放（无 ID / 缺资源时返回 false）
function VoicePlayer.PlayStep(step)
    if not step then
        print("[WARNING VoicePlayer] PlayStep 收到 nil step，跳过配音")
        return false
    end

    local voiceId =
        step.voiceId
        or (step.audioIds and step.audioIds[1])
        or step.id

    if not voiceId then
        -- 无 ID 静默跳过（P1 等数据未配 voiceId 的 step 属正常情况）
        return false
    end

    return VoicePlayer.Play(voiceId)
end

--- 播放指定 voiceId 对应的配音文件。
---@param voiceId string 配音 ID，映射到 audio/<章节>/<voiceId>.mp3
---@return boolean 是否真正发起播放（不在白名单 / 章节无法识别 / 播放失败时返回 false）
function VoicePlayer.Play(voiceId)
    if not voiceId or voiceId == "" then
        print("[WARNING VoicePlayer] voiceId 为空，跳过配音")
        return false
    end

    local path = ResolveVoicePath(voiceId)
    if not path then
        print("[WARNING VoicePlayer] 无法识别 voiceId 章节，跳过配音: " .. tostring(voiceId))
        return false
    end

    -- 未登记白名单：跳过（正常情况，对应台词无已上传配音）
    if not VoiceCatalog[voiceId] then
        print("[WARNING VoicePlayer] 配音未登记白名单，跳过: " .. tostring(voiceId))
        return false
    end

    -- 播放前先停止上一句，防止叠音
    VoicePlayer.Stop()

    print("[VOICE] play id=" .. tostring(voiceId) .. " path=" .. tostring(path))
    currentHandle_ = Effects.PlaySound(GetVoiceScene(), path, { gain = 1.0 })
    print("[VOICE] handle=" .. tostring(currentHandle_ ~= nil))
    if not currentHandle_ then
        print("[WARNING VoicePlayer] Effects.PlaySound 返回 nil（可能加载失败）: " .. tostring(path))
        return false
    end

    return true
end

return VoicePlayer
