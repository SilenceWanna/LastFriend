-- ============================================================================
-- scripts/p2sceneui.lua
-- 《零点之后》第二关「雪线诊所」静态场景 UI 构建模块
--
-- 只负责 P2 三类场景的 UI 树、背景、静态按钮、固定入口、调查容器、Dialog
-- 挂载和图片预览 UI。场景状态、调查分发、Scan 状态和正式流程由调用方持有。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Story2 = require("story2")

local P2SceneUI = {}
local config = {}
---@type Widget|nil
local tunnelRoot_ = nil
---@type Widget|nil
local clinicRoot_ = nil

function P2SceneUI.Configure(newConfig)
    config = newConfig
end

local P2_CLUE_ENGLISH_NAMES = {
    comic = "COMIC",
    schedule = "ROSTER",
    leak = "FOOTPRINTS",
    sign = "ARROW",
    cart = "GLOVE",
    temperature = "THERMAL",
    cans = "RATION",
    bed = "BED",
    triageRules = "TRIAGE",
    stretcher = "STRETCHER",
    backpack = "BACKPACK",
    organize = "MEDKIT",
    medicineList = "SHORTAGE",
    windowHandprint = "HANDPRINT",
}

local function AttachP2StaticFeedback(button, label, accent, functional, breathe, visited)
    local feedbackChildren = {
        UI.Panel {
            id = "p2StaticMarker",
            position = "absolute",
            left = 8,
            top = 22,
            width = 6,
            height = 6,
            borderRadius = 3,
            backgroundColor = functional and { 135, 225, 255, 220 } or { 160, 190, 210, 180 },
            pointerEvents = "none",
        },
        UI.Label {
            id = "p2StaticLabel",
            text = label,
            position = "absolute",
            left = 22,
            top = 16,
            width = "100%",
            whiteSpace = "nowrap",
            fontSize = 11,
            fontColor = accent and { 220, 230, 255, 230 } or { 190, 240, 255, 240 },
            pointerEvents = "none",
        },
    }
    if breathe then
        table.insert(feedbackChildren, UI.Label {
            id = "p2StaticState",
            text = visited and "已调查" or "未调查",
            position = "absolute",
            right = 6,
            bottom = 4,
            fontSize = 9,
            letterSpacing = 1,
            fontColor = accent and { 135, 155, 180, 190 } or { 135, 210, 235, 205 },
            pointerEvents = "none",
        })
    end
    local feedback = UI.Panel {
        id = "p2StaticFeedback",
        position = "absolute",
        left = 8,
        top = 16,
        width = 114,
        height = 50,
        pointerEvents = "none",
        backgroundColor = accent and { 50, 55, 75, 80 } or { 80, 190, 230, 16 },
        borderWidth = 1,
        borderColor = accent and { 110, 125, 165, 155 } or { 120, 225, 255, 185 },
        borderRadius = 4,
        boxShadow = functional
            and { { x = 0, y = 0, blur = 6, spread = 0, color = { 120, 220, 255, 70 } } }
            or false,
        children = feedbackChildren,
    }
    button:AddChild(feedback)
    if breathe then
        feedback:StopAnimation()
        if visited then
            feedback:SetStyle({
                opacity = 0.48,
                backgroundColor = { 50, 75, 95, 12 },
                borderColor = { 100, 145, 170, 150 },
                boxShadow = false,
            })
            local marker = feedback:FindById("p2StaticMarker")
            if marker then
                marker:SetStyle({ backgroundColor = { 100, 145, 170, 150 } })
            end
        else
            feedback:SetStyle({
                backgroundColor = { 30, 100, 140, 72 },
                borderColor = { 120, 225, 255, 220 },
                boxShadow = { { x = 0, y = 0, blur = 8, spread = 0, color = { 120, 220, 255, 90 } } },
            })
            local marker = feedback:FindById("p2StaticMarker")
            if marker then
                marker:SetStyle({ backgroundColor = { 135, 225, 255, 255 } })
            end
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
    return button
end

function P2SceneUI.AttachStaticFeedback(button, label, breathe, visited)
    return AttachP2StaticFeedback(button, label, true, true, breathe, visited)
end

local function CreateP2Feedback(button, id, kind, label, feedbackW, feedbackH)
    local feedback = UI.Panel {
        id = "p2ClueFeedback",
        position = "absolute",
        left = 8,
        top = 16,
        width = feedbackW or 114,
        height = feedbackH or 50,
        pointerEvents = "none",
        backgroundColor = { 80, 190, 230, 16 },
        borderWidth = 1,
        borderColor = { 120, 225, 255, 185 },
        borderRadius = 4,
        boxShadow = { { x = 0, y = 0, blur = 6, spread = 0, color = { 120, 220, 255, 55 } } },
        children = {
            UI.Row {
                id = "p2ClueTag",
                width = "100%",
                position = "absolute",
                left = 6,
                top = 4,
                alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        id = "p2ClueMarker",
                        width = 6,
                        height = 6,
                        borderRadius = 3,
                        marginRight = 8,
                        backgroundColor = { 135, 225, 255, 220 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        id = "p2ClueLabel",
                        text = P2_CLUE_ENGLISH_NAMES[id] or "",
                        whiteSpace = "nowrap",
                        fontSize = 11,
                        fontColor = { 190, 240, 255, 240 },
                        pointerEvents = "none",
                    },
                },
            },
            UI.Label {
                id = "p2ClueState",
                text = "未调查",
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
    button:AddChild(feedback)
    if not config.decorateButton then return button end
    return config.decorateButton(button, id, kind, label)
end

local function CreateTunnelButton(id, label, leftPct, topPct, feedbackW, feedbackH)
    local button = UI.Button {
        id = "p2_obj_" .. id,
        text = "",
        width = 130, height = 82,
        position = "absolute",
        left = leftPct .. "%", top = topPct .. "%",
        variant = "default",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 1, borderColor = { 0, 0, 0, 0 }, borderRadius = 10,
        boxShadow = false,
        fontSize = 14,
        onClick = function(self)
            config.onTunnelClueClick(id)
        end,
    }
    if config.decorateButton then
        return CreateP2Feedback(button, id, "tunnel", label, feedbackW, feedbackH)
    end
    return button
end

local function CreateEnterClinicButton()
    local button = UI.Button {
        id = "p2_obj_clinic",
        text = "",
        width = 120, height = 90,
        position = "absolute", right = 20, bottom = 40,
        variant = "default",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 1, borderColor = { 0, 0, 0, 0 }, borderRadius = 10,
        boxShadow = false,
        fontSize = 15,
        visible = false,
        onClick = function(self)
            config.onEnterClinic()
        end,
    }
    return AttachP2StaticFeedback(button, "CLINIC", true, false)
end

local function CreateClinicButton(id, label, leftPct, topPct, isFunctional, isStaticHotspot, feedbackW, feedbackH)
    local button = UI.Button {
        id = "p2_clinic_obj_" .. id,
        text = "",
        width = isFunctional and 120 or 130,
        height = isFunctional and 90 or 82,
        position = "absolute",
        left = leftPct .. "%", top = topPct .. "%",
        variant = "default",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 1,
        borderColor = { 0, 0, 0, 0 },
        borderRadius = 10,
        boxShadow = false,
        fontSize = 15,
        onClick = function(self)
            config.onClinicClueClick(id)
        end,
    }
    if isStaticHotspot then
        return button
    end
    if isFunctional then
        return AttachP2StaticFeedback(button, label, true, true)
    end
    if config.decorateButton then
        return CreateP2Feedback(button, id, "clinic", label, feedbackW, feedbackH)
    end
    return button
end

local function CreateSearchHotspot(itemKey, label, leftPct, topPct)
    local button = UI.Button {
        id = "p2_clinic_search_" .. itemKey,
        text = "",
        width = 120,
        height = 74,
        position = "absolute",
        left = leftPct .. "%",
        top = topPct .. "%",
        variant = "default",
        backgroundColor = { 0, 0, 0, 0 },
        borderWidth = 1,
        borderColor = { 0, 0, 0, 0 },
        borderRadius = 10,
        boxShadow = false,
        visible = false,
        onClick = function(self)
            config.onSearchHotspotClick(itemKey)
        end,
    }
    return AttachP2StaticFeedback(button, label, true, true)
end

local function CreateScanButton()
    return UI.Button {
        id = "p2_scanButton",
        text = "SCAN",
        width = 130,
        height = 90,
        position = "absolute",
        left = 20,
        bottom = 140,
        variant = "default",
        backgroundColor = { 18, 28, 42, 180 },
        borderWidth = 1,
        borderColor = { 120, 220, 255, 200 },
        borderRadius = 8,
        fontSize = 16,
        letterSpacing = 2,
        fontColor = { 150, 230, 255, 255 },
        onClick = function(self)
            config.onScan(self)
        end,
    }
end

local function CreateRecordTerminalButton()
    local button = config.createRecordButton(
        config.onOpenRecords,
        { id = "p2_record_terminal_button" })
    button:SetText("RECORDS")
    return button
end

local function CreateDebugPanel()
    if config.createDebugStatusPanel then
        return config.createDebugStatusPanel()
    end
    return UI.Panel { width = 0, height = 0, visible = false }
end

local function CreateScanLayers()
    local scanLayer = config.buildScanLayer and config.buildScanLayer()
    local scanStatusLayer = config.buildScanStatusLayer and config.buildScanStatusLayer()
    return scanLayer or UI.Panel { width = 0, height = 0, visible = false },
        scanStatusLayer or UI.Panel { width = 0, height = 0, visible = false }
end

function P2SceneUI.BuildTunnelScene()
    local scanLayer, scanStatusLayer = CreateScanLayers()
    tunnelRoot_ = UI.Panel {
        id = "p2Scene",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                id = "p2Bg",
                width = "100%", height = "100%",
                position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
                pointerEvents = "box-none",
                backgroundColor = { 14, 16, 22, 255 },
                backgroundImage = Story2.resources
                    and Story2.resources.image
                    and Story2.resources.image.tunnel_bg
                    or nil,
                backgroundFit = "cover",
            },
            UI.Label {
                id = "p2SceneTitle",
                text = "TUNNEL",
                fontSize = 16,
                fontColor = { 220, 230, 255, 255 },
                position = "absolute", top = 16, left = 16,
            },
            UI.Label {
                id = "p2Hint",
                text = "点击隧道中的物体查看信息",
                fontSize = 13,
                fontColor = { 200, 210, 230, 200 },
                position = "absolute", bottom = 20, left = 0, right = 0,
                textAlign = "center",
            },
            UI.Label {
                id = "p2CountdownLabel",
                text = "03:00",
                fontSize = 18,
                fontColor = { 255, 180, 120, 255 },
                position = "absolute", top = 16, right = 16,
                textAlign = "right",
                visible = false,
            },
            scanLayer,
            scanStatusLayer,
            CreateDebugPanel(),
            CreateTunnelButton("comic", "漫画", 1, 48, 88),
            CreateTunnelButton("schedule", "排班表", 34, 28, 96),
            CreateTunnelButton("leak", "重复脚印", 45, 58, 122),
            CreateTunnelButton("sign", "指示箭头", 20, 32, 86),
            CreateTunnelButton("cart", "儿童手套", 78, 76, 86),
            CreateEnterClinicButton(),
            CreateScanButton(),
            CreateRecordTerminalButton(),
            UI.Panel {
                id = "p2InvestigationButtons",
                width = "100%", height = "100%",
                position = "absolute",
                left = 0, top = 0,
                backgroundColor = { 0, 0, 0, 0 },
                pointerEvents = "box-none",
                visible = false,
                children = {},
            },
            config.createDialog(),
        },
    }
    config.setRoot(tunnelRoot_)
    return tunnelRoot_
end

function P2SceneUI.BuildClinicScene(area)
    area = area or "HALL"
    local isHall = area == "HALL"
    local isHearth = area == "HEARTH"
    local isClinic = not isHall and not isHearth
    local scanLayer, scanStatusLayer = CreateScanLayers()
    local backgroundKey = isClinic and "infirmary"
        or isHearth and "rest_area"
        or "clinic_bg"
    local clinicBackground = Story2.resources
        and Story2.resources.image
        and Story2.resources.image[backgroundKey]
        or nil

    clinicRoot_ = UI.Panel {
        id = "p2ClinicScene",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                id = "p2ClinicBg",
                width = "100%", height = "100%",
                position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
                pointerEvents = "box-none",
                backgroundColor = { 18, 22, 28, 255 },
                backgroundImage = clinicBackground,
                backgroundFit = "cover",
            },
            UI.Label {
                id = "p2ClinicTitle",
                text = "SNOWLINE CLINIC"
                    .. (not isHall and not isHearth and " · INFIRMARY"
                        or isHearth and " · HEARTH"
                        or " · LOUNGE"),
                fontSize = 16,
                fontColor = { 220, 230, 255, 255 },
                position = "absolute", top = 16, left = 16,
            },
            UI.Label {
                id = "p2ClinicHint",
                text = "点击诊所内的物体查看信息",
                fontSize = 13,
                fontColor = { 200, 210, 230, 200 },
                position = "absolute", bottom = 20, left = 0, right = 0,
                textAlign = "center",
            },
            UI.Label {
                id = "p2CountdownLabel",
                text = "03:00",
                fontSize = 18,
                fontColor = { 255, 180, 120, 255 },
                position = "absolute", top = 16, right = 16,
                textAlign = "right",
                visible = false,
            },
            scanLayer,
            scanStatusLayer,
            CreateDebugPanel(),
        },
    }

    local switchText, switchTarget
    if not isHall and not isHearth then
        switchText, switchTarget = "LOUNGE", "HALL"
    elseif isHearth then
        switchText, switchTarget = "LOUNGE", "HALL"
    else
        switchText, switchTarget = "CLINIC", "CLINIC"
    end
    clinicRoot_:AddChild(UI.Button {
        id = "p2_obj_area_switch",
        text = switchText,
        width = 150, height = 76,
        position = "absolute", left = 20, bottom = 40,
        variant = "default",
        backgroundColor = { 50, 65, 88, 230 },
        borderWidth = 1, borderColor = { 125, 155, 195, 225 }, borderRadius = 10,
        boxShadow = { { x = 0, y = 0, blur = 4, spread = 0, color = { 70, 110, 155, 40 } } },
        fontSize = 14,
        onClick = function(self)
            config.onSwitchScene(switchTarget)
        end,
    })

    if isHall then
        clinicRoot_:AddChild(CreateClinicButton("hearth", "取暖炉", 40, 74))
        clinicRoot_:AddChild(CreateClinicButton("temperature", "室内温度记录", 8, 18, false, false, 96))
        clinicRoot_:AddChild(CreateClinicButton("cans", "用过的营养罐头", 8, 42, false, false, 90))
        clinicRoot_:AddChild(CreateClinicButton("bed", "空置病床", 8, 66, false, false, 78))
        clinicRoot_:AddChild(CreateClinicButton("triageRules", "墙上的分诊制度", 62, 18, false, false, 90))
        clinicRoot_:AddChild(CreateClinicButton("stretcher", "损坏的担架", 62, 42, false, false, 108))
    elseif isHearth then
        clinicRoot_:AddChild(CreateClinicButton("backpack", "弦的背包", 8, 18, false, false, 104))
        clinicRoot_:AddChild(CreateClinicButton("organize", "整理药盒", 62, 18, false, false, 90))
        clinicRoot_:AddChild(CreateClinicButton("medicineList", "药品缺失清单", 8, 50, false, false, 104))
        clinicRoot_:AddChild(CreateClinicButton("windowHandprint", "窗外的手印", 62, 50, false, false, 112))
        clinicRoot_:AddChild(CreateClinicButton("xianLocker", "LOCKER", 34, 82, true))
        clinicRoot_:AddChild(CreateClinicButton("hearth", "HEATER", 62, 34, true))
    else
        clinicRoot_:AddChild(CreateClinicButton("clinicBed", "BED", 78, 46, true, true))
        clinicRoot_:AddChild(CreateSearchHotspot("route_map", "路线地图", 8, 82))
        clinicRoot_:AddChild(CreateSearchHotspot("identity_bracelet", "身份手环", 62, 82))
    end

    if config.addDynamicClinicChildren then
        config.addDynamicClinicChildren(clinicRoot_)
    end

    clinicRoot_:AddChild(CreateScanButton())
    clinicRoot_:AddChild(CreateRecordTerminalButton())
    clinicRoot_:AddChild(UI.Panel {
        id = "p2InvestigationButtons",
        width = "100%", height = "100%",
        position = "absolute",
        left = 0, top = 0,
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "box-none",
        visible = false,
        children = {},
    })
    clinicRoot_:AddChild(config.createDialog())
    config.setRoot(clinicRoot_)
    return clinicRoot_
end

local function ShowImage(root, imagePath, title, buttonText, callback, logPrefix)
    if not root then
        print("ERROR: P2 scene root missing for image preview")
        return
    end
    local dialog = root:FindById("dialog")
    local content = root:FindById("dialogContent")
    local dialogBox = dialog and dialog:FindById("dialogBox")
    if not (dialog and content) then
        print("ERROR: P2 dialog widgets not found")
        return
    end
    if dialogBox then dialogBox:SetStyle({ height = 540 }) end
    content:SetStyle({ height = "100%" })
    content:ClearChildren()
    if title then
        content:AddChild(UI.Label {
            text = title,
            fontSize = 20,
            fontColor = { 255, 255, 255, 255 },
            textAlign = "center",
        })
    end
    content:AddChild(UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        backgroundColor = { 12, 15, 24, 255 },
        borderRadius = 8,
        backgroundImage = imagePath,
        backgroundFit = "contain",
    })
    content:AddChild(UI.Row {
        gap = 12,
        marginTop = 12,
        children = {
            UI.Button {
                text = buttonText or "查看内容",
                variant = "primary",
                onClick = function()
                    print("[DEBUG P2-CABINET-FLOW] image_view_content_clicked")
                    if dialogBox then dialogBox:SetStyle({ height = "auto" }) end
                    content:SetStyle({ height = "auto" })
                    print("[DEBUG P2-CABINET-FLOW] close_image_begin")
                    config.closeDialog()
                    print("[DEBUG P2-CABINET-FLOW] close_image_done")
                    if callback then
                        print("[DEBUG P2-CABINET-FLOW] callback_begin")
                        callback()
                        print("[DEBUG P2-CABINET-FLOW] callback_done")
                    end
                end,
            },
        },
    })
    dialog:SetVisible(true)
    print((logPrefix or "[DEBUG P2] 线索图片预览已显示 路径=") .. tostring(imagePath))
end

function P2SceneUI.BuildRestScene()
    return P2SceneUI.BuildClinicScene("HALL")
end

function P2SceneUI.ShowClueImage(imagePath, title, callback)
    ShowImage(tunnelRoot_, imagePath, title, "查看内容", callback, "[DEBUG P2] 线索图片预览已显示 路径=")
end

function P2SceneUI.ShowClinicClueImage(imagePath, title, buttonText, callback)
    ShowImage(clinicRoot_, imagePath, title, buttonText, callback, "[DEBUG P2] 诊所线索图片预览已显示 路径=")
end

function P2SceneUI.ShowMemoryImage(imagePath, title, callback, root)
    ShowImage(root or clinicRoot_, imagePath, title, "继续", callback, "[DEBUG P2] Memory 演出图已显示 路径=")
end

function P2SceneUI.CreateTunnelButton(id, label, leftPct, topPct, feedbackW, feedbackH)
    return CreateTunnelButton(id, label, leftPct, topPct, feedbackW, feedbackH)
end

function P2SceneUI.CreateEnterClinicButton()
    return CreateEnterClinicButton()
end

function P2SceneUI.CreateClinicButton(id, label, leftPct, topPct, isFunctional, isStaticHotspot, feedbackW, feedbackH)
    return CreateClinicButton(id, label, leftPct, topPct, isFunctional, isStaticHotspot, feedbackW, feedbackH)
end

function P2SceneUI.CreateScanButton()
    return CreateScanButton()
end

function P2SceneUI.CreateRecordTerminalButton()
    return CreateRecordTerminalButton()
end

function P2SceneUI.GetTunnelRoot()
    return tunnelRoot_
end

function P2SceneUI.GetClinicRoot()
    return clinicRoot_
end

function P2SceneUI.Reset()
    local activeRoot = UI.GetRoot()
    if activeRoot == tunnelRoot_ or activeRoot == clinicRoot_ then
        UI.SetRoot(nil --[[@as Widget]])
    end
    if tunnelRoot_ then
        tunnelRoot_:Destroy()
    end
    if clinicRoot_ then
        clinicRoot_:Destroy()
    end
    tunnelRoot_ = nil
    clinicRoot_ = nil
end

return P2SceneUI
