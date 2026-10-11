local UI = require("urhox-libs/UI")
local ClueArchiveUI = require("cluearchiveui")
local TerminalRecordsUI = require("terminalrecordsui")

local P1SceneUI = {}

local deps_ = {}

function P1SceneUI.Configure(deps)
    deps_ = deps
end

function P1SceneUI.Build()
    return {
        background = UI.Panel {
            id = "bgImage",
            width = "100%",
            height = "100%",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            pointerEvents = "box-none",
            backgroundColor = { 10, 12, 18, 255 },
            backgroundImage = "image/P1/P1_BG_SleepPodRoom_v01.png",
            backgroundFit = "cover",
        },
        hintLabel = UI.Label {
            id = "hintLabel",
            text = "点击场景中的物体查看信息",
            fontSize = 13,
            fontColor = { 200, 210, 230, 200 },
            position = "absolute",
            bottom = 20,
            left = 0, right = 0,
            textAlign = "center",
        },
        recordButton = TerminalRecordsUI.CreateButton(deps_.openTerminal),
        archiveButton = ClueArchiveUI.CreateButton(deps_.openArchive),
        exitButton = UI.Button {
            id = "obj_exit",
            text = "出口",
            width = 130,
            height = 90,
            position = "absolute",
            right = 8,
            top = 80,
            variant = "default",
            backgroundColor = { 70, 50, 40, 200 },
            borderWidth = 1,
            borderColor = { 150, 110, 90, 180 },
            borderRadius = 10,
            fontSize = 15,
            onClick = deps_.onExit,
        },
        resetButton = UI.Button {
            id = "dev_reset",
            text = "重新开始",
            width = 130,
            height = 90,
            position = "absolute",
            left = 20,
            bottom = 40,
            variant = "default",
            backgroundColor = { 90, 40, 40, 220 },
            borderWidth = 1,
            borderColor = { 200, 120, 120, 200 },
            borderRadius = 10,
            fontSize = 15,
            onClick = deps_.onReset,
        },
        scanButton = UI.Button {
            id = "scanButton",
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
            onClick = deps_.onScan,
        },
        sceneSwitchButton = UI.Button {
            id = "sceneSwitchButton",
            text = "设施区",
            width = 120,
            height = 90,
            position = "absolute",
            right = 20,
            bottom = 140,
            variant = "default",
            backgroundColor = { 50, 55, 75, 210 },
            borderWidth = 1,
            borderColor = { 110, 125, 165, 190 },
            borderRadius = 10,
            fontSize = 15,
            onClick = deps_.onSceneSwitch,
        },
        debugLabel = UI.Label {
            id = "debugLabel",
            text = "",
            fontSize = 12,
            fontColor = { 120, 255, 160, 255 },
            position = "absolute",
            top = 16,
            right = 16,
            textAlign = "right",
            visible = deps_.debugVisible,
        },
        countdownLabel = UI.Label {
            id = "countdownLabel",
            text = "03:00",
            fontSize = 22,
            fontColor = { 255, 210, 120, 255 },
            position = "absolute",
            top = 40,
            right = 16,
            textAlign = "right",
        },
    }
end

return P1SceneUI
