local UI = require("urhox-libs/UI")
local VoicePlayer = require("voiceplayer")
local BGMPlayer = require("bgmplayer")
local P3Controller = {}
local P3State = require("p3state")
local P3SceneUI = require("p3sceneui")
local P3Clues = require("p3clues")
local P3Evidence = require("p3evidence")
local Story3 = require("story3")
local RunState = require("runstate")

---@type P3StateData|nil
local state_ = nil
local retryEvidencePending_ = false

local function ShowP3Dialog(title, body, onContinue, prefixZero)
    P3SceneUI.ShowDialog(P3SceneUI.GetRoot(), title, body, onContinue, prefixZero)
end

local function IsP3InteractionAvailable()
    local root = P3SceneUI.GetRoot()
    local dialog = root and root:FindById("p3Dialog")
    return not P3Evidence.IsOpen() and not (dialog and dialog:IsVisible())
end

local function RetryEndingNextFrame(callback)
    P3SceneUI.NextFrame(callback)
end


local function WriteP3RunState()
    if not state_ then return end
    local runState = RunState.GetCurrent()
    runState.lastCheckpoint = "P3_COMPLETE"
    runState.p3_key_photo = state_.keys.photo
    runState.p3_key_band = state_.keys.band
    runState.p3_record_restore = state_.keys.recordRestore
    runState.p3_record_sleep = state_.keys.recordSleep
    runState.p3_memory_cards = {
        sharedPast = state_.memories.sharedPast,
        identityBand = state_.memories.identityBand,
        sleepExecution = state_.memories.sleepExecution,
    }
    RunState.Save()
end

local function StartP3Ending()
    print("[P3 DEBUG] StartP3Ending ENTER")
    if not state_ or state_.flags.endingStarted then return end
    state_.phase = "ENDING"
    state_.flags.endingStarted = true
    -- 音乐任务2：P3 最终结局/片尾开始 → 播放片尾主题（单次，不循环）
    BGMPlayer.Play("BGM_ENDING_THEME_LAST_FRIEND_v01", { loop = false, gain = 0.28 })
    P3Evidence.Hide()
    P3SceneUI.HideDialog(P3SceneUI.GetRoot())
    local ending = Story3.ending
    local index = 1
    local function PlayNext()
        local step = ending.dialogue[index]
        if not step then
            P3SceneUI.ShowEndingBlackScreen(P3SceneUI.GetRoot(), ending.blackScreen, function()
                state_.flags.completed = true
                state_.phase = "COMPLETE"
                WriteP3RunState()
                -- 音乐任务2：片尾/游戏结束 → 停止音乐
                BGMPlayer.Stop()
                P3SceneUI.ShowDemoComplete(P3SceneUI.GetRoot(), function()
                    ShowTitleScreen()
                end)
            end)
            return
        end
        ShowP3Dialog("我", step.text, function()
            index = index + 1
            PlayNext()
        end, true)
    end
    PlayNext()
end

function P3Controller.Enter()
    state_ = P3State.Reset()
    local runState = RunState.GetCurrent()
    local p2Entry = runState.p2Entry or {}
    state_.inherited.route_map = p2Entry.route_map == true
    state_.inherited.identity_bracelet = p2Entry.identity_bracelet == true
    print("[P3] inherited route_map=" .. tostring(state_.inherited.route_map)
        .. " identity_bracelet=" .. tostring(state_.inherited.identity_bracelet))
    retryEvidencePending_ = false
    state_.phase = "OPENING"
    print("[DEBUG P3] Enter() phase=OPENING")

    P3Clues.Configure({
        getState = function()
            return state_
        end,
        showDialog = function(title, body, onContinue, prefixZero)
            ShowP3Dialog(title, body, onContinue, prefixZero)
        end,
        tryOpenEvidence = function()
            P3Evidence.TryOpen()
        end,
        retryOpenEvidenceNextFrame = function()
            print("[P3 DEBUG] retryOpenEvidenceNextFrame scheduled")
            P3SceneUI.NextFrame(function()
                print("[P3 DEBUG] retryOpenEvidenceNextFrame fired")
                P3Evidence.TryOpen()
            end)
        end,
    })

    P3Evidence.Configure({
        getState = function()
            return state_
        end,
        showDialog = function(title, body, onContinue, prefixZero)
            ShowP3Dialog(title, body, onContinue, prefixZero)
        end,
        isInteractionAvailable = IsP3InteractionAvailable,
        tryOpenEvidence = function()
            P3Evidence.TryOpen()
        end,
        retryOpenEvidenceNextFrame = function()
            print("[P3 DEBUG] retryOpenEvidenceNextFrame scheduled")
            P3SceneUI.NextFrame(function()
                print("[P3 DEBUG] retryOpenEvidenceNextFrame fired")
                P3Evidence.TryOpen()
            end)
        end,
        retryEndingNextFrame = RetryEndingNextFrame,
        startEnding = StartP3Ending,
    })

    P3Evidence.Reset()
    P3SceneUI.Reset()
    local root = P3SceneUI.Build(P3Clues.Build(), P3Evidence.Build())
    UI.SetRoot(root)

    local index = 1
    local opening = Story3.opening or {}
    local function PlayNext()
        local step = opening[index]
        if not step then
            state_.phase = "FREE"
            print("[DEBUG P3] opening complete phase=FREE")
            -- 音乐任务2：P3 开场结束、玩家获得调查操作权 → 播放调查背景音乐
            BGMPlayer.Play("BGM_P3_INVESTIGATION_AMBIENT_v01", { loop = true, gain = 0.28 })
            P3Evidence.TryOpen()
            return
        end

        -- 逐句配音：在当前 step 显示前播放对应台词音频（缺失时仅 WARNING，不阻断文字流程）
        VoicePlayer.PlayStep(step)

        P3SceneUI.ShowDialog(root, "回到原点", step.narration or "", function()
            index = index + 1
            PlayNext()
        end, true)
    end

    PlayNext()
end

return P3Controller
