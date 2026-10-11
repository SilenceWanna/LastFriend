local UI = require("urhox-libs/UI")
local Story3 = require("story3")
local VoicePlayer = require("voiceplayer")

local P3Clues = {}
local config = {}
local feedbackWidgets_ = {}

-- v1.0 独立 MINOR 热点布局（参考 P1 原位；R02/R04 已错开，R06 避开 KEY03）
local clueLayout_ = {
    R01 = { left = 0.27, top = 0.49, width = 0.06, height = 0.06 },
    R02 = { left = 0.15, top = 0.30, width = 0.08, height = 0.05 },
    R03 = { left = 0.20, top = 0.42, width = 0.06, height = 0.06 },
    R04 = { left = 0.15, top = 0.36, width = 0.08, height = 0.05 },
    R06 = { left = 0.58, top = 0.34, width = 0.15, height = 0.06 },
}

local clueOrder_ = { "R01", "R02", "R03", "R04", "R05", "R06", "R07", "R08" }

-- 与 KEY 共点的 MINOR：不生成独立按钮，宿主为对应 KEY 热点（两阶段调查）
local sharedMinorKey_ = { R05 = "KEY02", R07 = "KEY01", R08 = "KEY03" }
-- 反查表：KEY 热点 → 首次点击时先播的共点 MINOR
local minorForKey_ = {}
for minorId, keyId in pairs(sharedMinorKey_) do
    minorForKey_[keyId] = minorId
end
local keyLayouts_ = {
    KEY01 = { left = 0.74, top = 0.30, width = 0.18, height = 0.16 },
    KEY02 = { left = 0.08, top = 0.62, width = 0.18, height = 0.16 },
    KEY03 = { left = 0.48, top = 0.42, width = 0.20, height = 0.16 },
}
local keyField_ = { KEY01 = "photo", KEY02 = "band", KEY03 = "terminal" }
---@type function
local RefreshKeyFeedback

function P3Clues.Configure(newConfig)
    config = newConfig
    print("[P3 DEBUG] P3Clues configured tryOpenEvidence="
        .. tostring(config.tryOpenEvidence ~= nil)
        .. " retryOpenEvidenceNextFrame="
        .. tostring(config.retryOpenEvidenceNextFrame ~= nil))
end

local function IsViewed(id)
    local state = config.getState and config.getState()
    return state and state.minorViewed and state.minorViewed[id] == true
end

local function RefreshFeedback(id)
    local feedback = feedbackWidgets_[id]
    if not feedback then return end
    local viewed = IsViewed(id)
    local stateLabel = feedback:FindById("p3ClueState_" .. id)
    if stateLabel then
        stateLabel:SetText(viewed and "已调查" or "未调查")
    end
    feedback:StopAnimation()
    if viewed then
        feedback:SetStyle({
            opacity = 0.48,
            backgroundColor = { 50, 75, 95, 12 },
            borderColor = { 100, 145, 170, 150 },
            boxShadow = false,
        })
    else
        feedback:SetStyle({
            opacity = 1,
            backgroundColor = { 30, 100, 140, 72 },
            borderColor = { 120, 225, 255, 220 },
            boxShadow = { { x = 0, y = 0, blur = 8, spread = 0, color = { 120, 220, 255, 90 } } },
        })
        feedback:Animate({
            keyframes = {
                [0] = { opacity = 0.78 },
                [0.5] = { opacity = 1.0 },
                [1] = { opacity = 0.78 },
            },
            duration = 1.7,
            easing = "easeInOut",
            loop = true,
            fillMode = "backwards",
        })
    end
end

local function CompleteClue(id)
    local state = config.getState and config.getState()
    if state and state.minorViewed and state.minorViewed[id] ~= true then
        state.minorViewed[id] = true
    end
    RefreshFeedback(id)
end

local function HasInheritedIdentityBracelet()
    local state = config.getState and config.getState()
    return state and state.inherited and state.inherited.identity_bracelet == true
end

local function IsKeyAvailable(id)
    return id ~= "KEY02" or HasInheritedIdentityBracelet()
end

local function IsKeyViewed(id)
    local state = config.getState and config.getState()
    local field = keyField_[id]
    return state and state.keys and field and state.keys[field] == true
end

local function CompleteKey(id)
    if not IsKeyAvailable(id) then
        return
    end
    local state = config.getState and config.getState()
    local key = Story3.keys[id]
    local field = keyField_[id]
    if not state or not key or not field then return end
    if state.keys[field] == true then
        RefreshKeyFeedback(id)
        return
    end
    state.keys[field] = true
    state.evidenceCards = state.evidenceCards or {}
    if state.evidenceCards[key.evidenceCard] ~= true then
        state.evidenceCards[key.evidenceCard] = true
    end
    local debugState = config.getState and config.getState()
    print("[P3 DEBUG] KEY"
        .. " photo=" .. tostring(debugState and debugState.keys and debugState.keys.photo)
        .. " band=" .. tostring(debugState and debugState.keys and debugState.keys.band)
        .. " terminal=" .. tostring(debugState and debugState.keys and debugState.keys.terminal)
        .. " phase=" .. tostring(debugState and debugState.phase)
        .. " evidenceOpened=" .. tostring(debugState and debugState.flags and debugState.flags.evidenceOpened))
    print("[P3 DEBUG] calling TryOpen", config.tryOpenEvidence ~= nil)
    if config.tryOpenEvidence then
        config.tryOpenEvidence()
    end
    print("[P3 DEBUG] calling retry evidence", config.retryOpenEvidenceNextFrame ~= nil)
    if config.retryOpenEvidenceNextFrame then
        config.retryOpenEvidenceNextFrame()
    end
    RefreshKeyFeedback(id)
end

local function ShowRecord(id, recordKey, onContinue)
    local key = Story3.keys[id]
    local record = key and key.records and key.records[recordKey]
    if not record then
        onContinue()
        return
    end
    local lines = {}
    for i = 1, #record.fields do
        local field = record.fields[i]
        lines[#lines + 1] = field.label .. "：" .. field.value
    end
    config.showDialog(record.title, table.concat(lines, "\n"), onContinue)
end

local function ShowKeyDialogue(id, index, onComplete)
    local key = Story3.keys[id]
    local line = key and key.dialogue and key.dialogue[index]
    if not line then
        onComplete()
        return
    end
    -- 逐句配音：显示当前 step 时播放对应配音
    VoicePlayer.PlayStep(line)
    config.showDialog(key.title, line.text or "", function()
        ShowKeyDialogue(id, index + 1, onComplete)
    end, true)
end

local function ShowDetectionCard(id, onContinue)
    local key = Story3.keys[id]
    local card = key and key.detectionCard
    if not card then
        onContinue()
        return
    end
    config.showDialog(key.title, "身份信息：" .. card.identity
        .. "\n权限：" .. card.permission
        .. "\n编号：" .. card.number, onContinue)
end

local function OpenKey(id)
    if not IsKeyAvailable(id) then
        return
    end
    local key = Story3.keys[id]
    if not key then return end

    -- description 弹窗之后的 KEY 流程（KEY02 检测卡 / KEY03 双记录 / 其余直接对白）
    local function PlayKeyFlow()
        if id == "KEY02" then
            ShowDetectionCard(id, function()
                ShowKeyDialogue(id, 1, function()
                    CompleteKey(id)
                end)
            end)
            return
        end
        if id == "KEY03" then
            ShowRecord(id, "restore", function()
                ShowRecord(id, "sleep", function()
                    ShowKeyDialogue(id, 1, function()
                        CompleteKey(id)
                    end)
                end)
            end)
            return
        end
        ShowKeyDialogue(id, 1, function()
            CompleteKey(id)
        end)
    end

    -- KEY01（残缺合照）与 KEY03 均仅显示层跳过 description，直接进入各自流程
    if id == "KEY01" or id == "KEY03" then
        PlayKeyFlow()
        return
    end
    config.showDialog(key.title, key.description or "", PlayKeyFlow)
end

local function ShowDialogue(id, index, onComplete)
    local clue = Story3.minorClues[id]
    local line = clue and clue.dialogue and clue.dialogue[index]
    if not line then
        onComplete()
        return
    end
    -- 逐句配音：显示当前 step 时播放对应配音
    VoicePlayer.PlayStep(line)
    config.showDialog(clue.title, line.text or "", function()
        ShowDialogue(id, index + 1, onComplete)
    end, true)
end

local function OpenClue(id)
    local clue = Story3.minorClues[id]
    if not clue then return end

    local function PlayDialogue()
        ShowDialogue(id, 1, function()
            CompleteClue(id)
        end)
    end
    -- v1.0 MINOR 无 description：跳过简介弹窗，直接播对白
    if clue.description then
        config.showDialog(clue.title, clue.description, PlayDialogue)
        return
    end
    PlayDialogue()
end

-- 同一热点两阶段调查（R07→KEY01 / R05→KEY02 / R08→KEY03）：
-- 首次点击播共点 MINOR（仅标记 minorViewed，不计 KEY）；
-- 再次点击起走现有 KEY 完整流程（OpenKey → CompleteKey，逻辑与状态写入不变）。
local function OpenSharedHotspot(keyId)
    local minorId = minorForKey_[keyId]
    if minorId then
        local state = config.getState and config.getState()
        if state and state.minorViewed and state.minorViewed[minorId] ~= true then
            OpenClue(minorId)
            return
        end
    end
    OpenKey(keyId)
end

local function CreateFeedback(id, title)
    local viewed = IsViewed(id)
    local feedback = UI.Panel {
        id = "p3ClueFeedback_" .. id,
        position = "absolute",
        left = 8,
        top = 16,
        width = 132,
        height = 52,
        pointerEvents = "none",
        backgroundColor = { 30, 100, 140, 72 },
        borderWidth = 1,
        borderColor = { 120, 225, 255, 220 },
        borderRadius = 4,
        boxShadow = { { x = 0, y = 0, blur = 8, spread = 0, color = { 120, 220, 255, 90 } } },
        children = {
            UI.Label {
                id = "p3ClueTitle_" .. id,
                text = title,
                position = "absolute",
                left = 8,
                top = 6,
                whiteSpace = "nowrap",
                fontSize = 11,
                fontColor = { 190, 240, 255, 240 },
                pointerEvents = "none",
            },
            UI.Label {
                id = "p3ClueState_" .. id,
                text = viewed and "已调查" or "未调查",
                position = "absolute",
                right = 6,
                bottom = 4,
                fontSize = 9,
                letterSpacing = 1,
                fontColor = { 135, 210, 235, 205 },
                pointerEvents = "none",
            },
        },
    }
    feedbackWidgets_[id] = feedback
    return feedback
end

RefreshKeyFeedback = function(id)
    local feedback = feedbackWidgets_[id]
    if not feedback then return end
    local viewed = IsKeyViewed(id)
    local stateLabel = feedback:FindById("p3KeyState_" .. id)
    if stateLabel then
        stateLabel:SetText(viewed and "已调查" or "未调查")
    end
    feedback:StopAnimation()
    if viewed then
        feedback:SetStyle({
            opacity = 0.48,
            backgroundColor = { 50, 75, 95, 12 },
            borderColor = { 100, 145, 170, 150 },
            boxShadow = false,
        })
    else
        feedback:SetStyle({
            opacity = 1,
            backgroundColor = { 30, 100, 140, 72 },
            borderColor = { 120, 225, 255, 220 },
            boxShadow = { { x = 0, y = 0, blur = 8, spread = 0, color = { 120, 220, 255, 90 } } },
        })
        feedback:Animate({
            keyframes = {
                [0] = { opacity = 0.78 },
                [0.5] = { opacity = 1.0 },
                [1] = { opacity = 0.78 },
            },
            duration = 1.7,
            easing = "easeInOut",
            loop = true,
            fillMode = "backwards",
        })
    end
end

local function CreateKeyFeedback(id, title)
    local viewed = IsKeyViewed(id)
    local feedback = UI.Panel {
        id = "p3KeyFeedback_" .. id,
        position = "absolute",
        left = id == "KEY03" and 0 or 8,
        top = id == "KEY03" and 0 or 16,
        width = 132,
        height = 52,
        pointerEvents = "none",
        backgroundColor = { 30, 100, 140, 72 },
        borderWidth = 1,
        borderColor = { 120, 225, 255, 220 },
        borderRadius = 4,
        boxShadow = { { x = 0, y = 0, blur = 8, spread = 0, color = { 120, 220, 255, 90 } } },
        children = {
            UI.Label {
                id = "p3KeyTitle_" .. id,
                text = title,
                position = "absolute",
                left = 8,
                top = 6,
                whiteSpace = "nowrap",
                fontSize = 11,
                fontColor = { 190, 240, 255, 240 },
                pointerEvents = "none",
            },
            UI.Label {
                id = "p3KeyState_" .. id,
                text = viewed and "已调查" or "未调查",
                position = "absolute",
                right = 6,
                bottom = 4,
                fontSize = 9,
                letterSpacing = 1,
                fontColor = { 135, 210, 235, 205 },
                pointerEvents = "none",
            },
        },
    }
    feedbackWidgets_[id] = feedback
    return feedback
end

function P3Clues.Build()
    feedbackWidgets_ = {}
    local buttons = {}
    for i = 1, #clueOrder_ do
        local id = clueOrder_[i]
        -- 与 KEY 共点的 MINOR（R05/R07/R08）不生成独立按钮，避免双热点
        if not sharedMinorKey_[id] then
            local clue = Story3.minorClues[id]
            local layout = clueLayout_[id]
            local button = UI.Button {
                id = "p3_clue_" .. id,
                text = "",
                width = tostring(layout.width * 100) .. "%",
                height = tostring(layout.height * 100) .. "%",
                position = "absolute",
                left = tostring(layout.left * 100) .. "%",
                top = tostring(layout.top * 100) .. "%",
                variant = "default",
                backgroundColor = { 0, 0, 0, 0 },
                borderWidth = 1,
                borderColor = { 0, 0, 0, 0 },
                borderRadius = 8,
                boxShadow = false,
                onClick = function()
                    OpenClue(id)
                end,
            }
            button:AddChild(CreateFeedback(id, clue.title))
            buttons[#buttons + 1] = button
        end
    end

    for i = 1, #clueOrder_ do
        RefreshFeedback(clueOrder_[i])
    end

    local key = Story3.keys.KEY01
    if key then
        local layout = keyLayouts_.KEY01
        local button = UI.Button {
            id = "p3_key_KEY01",
            text = "",
            width = tostring(layout.width * 100) .. "%",
            height = tostring(layout.height * 100) .. "%",
            position = "absolute",
            left = tostring(layout.left * 100) .. "%",
            top = tostring(layout.top * 100) .. "%",
            variant = "default",
            backgroundColor = { 0, 0, 0, 0 },
            borderWidth = 1,
            borderColor = { 0, 0, 0, 0 },
            borderRadius = 8,
            boxShadow = false,
            onClick = function()
                OpenSharedHotspot("KEY01")
            end,
        }
        button:AddChild(CreateKeyFeedback("KEY01", key.title))
        buttons[#buttons + 1] = button
    end

    local key02 = Story3.keys.KEY02
    if key02 and IsKeyAvailable("KEY02") then
        local layout = keyLayouts_.KEY02
        local button = UI.Button {
            id = "p3_key_KEY02",
            text = "",
            width = tostring(layout.width * 100) .. "%",
            height = tostring(layout.height * 100) .. "%",
            position = "absolute",
            left = tostring(layout.left * 100) .. "%",
            top = tostring(layout.top * 100) .. "%",
            variant = "default",
            backgroundColor = { 0, 0, 0, 0 },
            borderWidth = 1,
            borderColor = { 0, 0, 0, 0 },
            borderRadius = 8,
            boxShadow = false,
            onClick = function()
                OpenSharedHotspot("KEY02")
            end,
        }
        button:AddChild(CreateKeyFeedback("KEY02", key02.title))
        buttons[#buttons + 1] = button
    end

    local key03 = Story3.keys.KEY03
    if key03 then
        local layout = keyLayouts_.KEY03
        local button = UI.Button {
            id = "p3_key_KEY03",
            text = "",
            width = tostring(layout.width * 100) .. "%",
            height = tostring(layout.height * 100) .. "%",
            position = "absolute",
            left = tostring(layout.left * 100) .. "%",
            top = tostring(layout.top * 100) .. "%",
            variant = "default",
            backgroundColor = { 0, 0, 0, 0 },
            borderWidth = 1,
            borderColor = { 0, 0, 0, 0 },
            borderRadius = 8,
            boxShadow = false,
            onClick = function()
                OpenSharedHotspot("KEY03")
            end,
        }
        button:AddChild(CreateKeyFeedback("KEY03", key03.title))
        buttons[#buttons + 1] = button
    end

    local layer = UI.Panel {
        id = "p3ClueLayer",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        pointerEvents = "box-none",
        backgroundColor = { 0, 0, 0, 0 },
        children = buttons,
    }
    RefreshKeyFeedback("KEY01")
    RefreshKeyFeedback("KEY02")
    RefreshKeyFeedback("KEY03")
    return layer
end

return P3Clues
