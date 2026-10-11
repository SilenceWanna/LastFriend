local UI = require("urhox-libs/UI")

local P3SceneUI = {}
---@type Widget|nil
local root_ = nil

function P3SceneUI.Build(clueLayer, evidenceLayer)
    root_ = UI.Panel {
        id = "p3Scene",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                id = "p3Background",
                width = "100%",
                height = "100%",
                position = "absolute",
                top = 0,
                left = 0,
                right = 0,
                bottom = 0,
                pointerEvents = "box-none",
                backgroundColor = { 10, 12, 18, 255 },
                backgroundImage = "image/P1/P1_BG_SleepPodRoom_v01.png",
                backgroundFit = "cover",
            },
            UI.Label {
                id = "p3SceneTitle",
                text = "SLEEP ZONE",
                fontSize = 16,
                fontColor = { 220, 230, 255, 255 },
                position = "absolute",
                top = 16,
                left = 16,
            },
            UI.Label {
                id = "p3SceneHint",
                text = "",
                fontSize = 13,
                fontColor = { 200, 210, 230, 200 },
                position = "absolute",
                bottom = 20,
                left = 0,
                right = 0,
                textAlign = "center",
            },
            clueLayer,
            evidenceLayer,
            UI.Panel {
                id = "p3Dialog",
                width = "100%",
                height = "100%",
                position = "absolute",
                top = 0,
                left = 0,
                right = 0,
                bottom = 0,
                justifyContent = "center",
                alignItems = "center",
                backgroundColor = { 0, 0, 0, 105 },
                pointerEvents = "auto",
                visible = false,
                children = {
                    UI.Panel {
                        id = "p3DialogBox",
                        width = "68%",
                        maxWidth = 560,
                        maxHeight = "58%",
                        padding = 18,
                        gap = 12,
                        backgroundColor = { 20, 25, 38, 245 },
                        borderWidth = 1,
                        borderColor = { 110, 200, 255, 180 },
                        borderRadius = 10,
                        children = {},
                    },
                },
            },
        },
    }
    return root_
end

function P3SceneUI.ShowDialog(root, title, body, onContinue, prefixZero)
    local dialog = root:FindById("p3Dialog")
    local dialogBox = root:FindById("p3DialogBox")
    if not dialog or not dialogBox then
        print("[P3 UI] dialog widgets not found")
        return
    end

    dialogBox:ClearChildren()
    local displayBody = tostring(body or "")
    if prefixZero then
        displayBody = "我：" .. displayBody
    end
    displayBody = displayBody:gsub("。”([^\n])", "。”\n%1")
    displayBody = displayBody:gsub("。([^\n”])", "。\n%1")
    dialogBox:AddChild(UI.Label {
        id = "p3DialogTitle",
        text = title or "",
        fontSize = 20,
        fontColor = { 235, 240, 255, 255 },
        textAlign = "center",
        width = "100%",
    })
    dialogBox:AddChild(UI.Label {
        id = "p3DialogBody",
        text = displayBody,
        fontSize = 16,
        fontColor = { 210, 220, 235, 240 },
        textAlign = "left",
        width = "100%",
        minWidth = 0,
        flexShrink = 1,
        whiteSpace = "normal",
        wordBreak = "break-word",
    })
    dialogBox:AddChild(UI.Row {
        width = "100%",
        justifyContent = "center",
        children = {
            UI.Button {
                text = "继续",
                variant = "primary",
                onClick = function()
                    P3SceneUI.HideDialog(root)
                    if onContinue then
                        onContinue()
                    end
                end,
            },
        },
    })
    dialog:SetVisible(true)
end

function P3SceneUI.NextFrame(callback)
    local function nextFrameHandler(eventType, eventData)
        UnsubscribeFromEvent("Update")
        callback()
    end
    SubscribeToEvent("Update", nextFrameHandler)
end

function P3SceneUI.ShowEndingBlackScreen(root, text, onContinue)
    local dialog = root:FindById("p3Dialog")
    local dialogBox = root:FindById("p3DialogBox")
    if not dialog or not dialogBox then return end
    dialogBox:ClearChildren()
    dialogBox:AddChild(UI.Label {
        text = text or "",
        fontSize = 18,
        fontColor = { 235, 242, 250, 255 },
        textAlign = "center",
        width = "100%",
    })
    dialogBox:AddChild(UI.Row {
        width = "100%",
        justifyContent = "center",
        children = {
            UI.Button {
                text = "继续",
                variant = "primary",
                onClick = function()
                    P3SceneUI.HideDialog(root)
                    if onContinue then onContinue() end
                end,
            },
        },
    })
    dialog:SetStyle({ backgroundColor = { 0, 0, 0, 255 } })
    dialog:SetVisible(true)
end

function P3SceneUI.ShowDemoComplete(root, onReturn)
    local dialog = root:FindById("p3Dialog")
    local dialogBox = root:FindById("p3DialogBox")
    if not dialog or not dialogBox then return end
    dialogBox:ClearChildren()
    dialogBox:AddChild(UI.Label {
        text = "第一部 Demo 完成",
        fontSize = 24,
        fontColor = { 235, 242, 250, 255 },
        textAlign = "center",
        width = "100%",
    })
    dialogBox:AddChild(UI.Row {
        width = "100%",
        justifyContent = "center",
        children = {
            UI.Button {
                text = "返回标题",
                variant = "primary",
                onClick = function()
                    P3SceneUI.HideDialog(root)
                    if onReturn then onReturn() end
                end,
            },
        },
    })
    dialog:SetStyle({ backgroundColor = { 12, 14, 20, 255 } })
    dialog:SetVisible(true)
end

function P3SceneUI.HideDialog(root)
    local dialog = root and root:FindById("p3Dialog")
    if dialog then
        dialog:SetVisible(false)
        dialog:SetStyle({ backgroundColor = { 0, 0, 0, 105 } })
    end
end

function P3SceneUI.Reset()
    if root_ and UI.GetRoot() == root_ then
        UI.SetRoot(nil --[[@as Widget]])
    end
    if root_ then
        root_:Destroy()
        root_ = nil
    end
end

function P3SceneUI.GetRoot()
    return root_
end

return P3SceneUI
