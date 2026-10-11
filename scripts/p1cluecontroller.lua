local P1ClueController = {}

local BGMPlayer = require("bgmplayer")

local CORE_CLUE_IDS = {
    locker = true,
    photo = true,
    terminal = true,
    ring = true,
}

local CORE_CLUE_IMAGES = {
    locker = "image/P1/P1_C01_Note_v01.png",
    terminal = "image/P1/P1_C03_Terminal_v01.png",
    ring = "image/P1/P1_C04_Ring_v01.png",
}

local PHOTO_IMAGE = "image/P1/P1_clue_photo_memory.png"

local deps_ = {}

function P1ClueController.Configure(deps)
    deps_ = deps
end

function P1ClueController.IsCoreClue(id)
    return CORE_CLUE_IDS[id] == true
end

function P1ClueController.HandlePhotoClicked(id, title)
    if id ~= "photo" then
        return false
    end
    if deps_.getPhotoViewing() then
        deps_.setPhotoViewing(false)
        print("[DEBUG合照] 图片已关闭，继续原调查流程")
        -- 音乐任务2：合照内容关闭 → 恢复 P1 调查背景音乐
        BGMPlayer.Play("BGM_P1_INVESTIGATION_AMBIENT_v01", { loop = false, gain = 0.28 })
        return false
    end

    deps_.setPhotoViewing(true)
    print("[DEBUG合照] 点击合照线索，打开图片查看")
    -- 音乐任务2：正式合照打开 → 播放合照音乐
    BGMPlayer.Play("BGM_P1_CLUE_PHOTO_v01", { loop = true, gain = 0.28 })
    deps_.showClueImage(
        PHOTO_IMAGE,
        function()
            deps_.reopenClue("photo")
        end,
        title)
    return true
end

local function AddImageButton(buttons, id, title)
    local imagePath = CORE_CLUE_IMAGES[id]
    if not imagePath then
        return
    end
    local labels = {
        locker = "查看纸条",
        terminal = "查看现场",
        ring = "查看金属环",
    }
    table.insert(buttons, 1, {
        label = labels[id],
        variant = "default",
        onClick = function()
            deps_.showClueImage(
                imagePath,
                function()
                    deps_.reopenClue(id)
                end,
                title)
        end,
    })
end

function P1ClueController.HandleClueClicked(id, clue, asked, wasInvestigated)
    local buttons
    if asked then
        buttons = {
            { label = "返回调查", variant = "default", onClick = deps_.closeDialog },
        }
        AddImageButton(buttons, id, clue.title)
    else
        local closeLabel = wasInvestigated and "返回调查" or "稍后询问"
        buttons = deps_.buildClueButtons(id, closeLabel)
        AddImageButton(buttons, id, clue.title)
    end

    if id == "photo" then
        deps_.showPhotoInspectDialog(clue.title, clue.inspect, buttons)
    elseif id == "locker" then
        deps_.showLockerInspectDialog(clue.title, clue.inspect, buttons)
    else
        deps_.showDialog(clue.title, clue.inspect, buttons)
    end
end

return P1ClueController
