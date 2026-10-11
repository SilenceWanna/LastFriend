local ClueArchiveUI = require("cluearchiveui")

local P1Archive = {}

local ImageGallery_ = {
    C01 = { title = "纸条",        path = "image/P1/P1_C01_Note_v01.png",     obtained = false },
    C02 = { title = "旧照片",      path = "image/P1/P1_clue_photo_memory.png", obtained = false },
    C03 = { title = "通讯终端",    path = "image/P1/P1_C03_Terminal_v01.png",  obtained = false },
    C04 = { title = "黑色金属环",  path = "image/P1/P1_C04_Ring_v01.png",      obtained = false },
    MN02 = { title = "空休眠舱",   path = "image/P1/P1_MN02_SleepPod_v01.png",  obtained = false },
    MN03 = { title = "两只水杯",   path = "image/P1/P1_MN03_Cups_v01.png",     obtained = false },
    MN07 = { title = "维护签名",   path = "image/P1/P1_MN07_MaintenanceLog_v01.png", obtained = false },
    MN08 = { title = "外套",       path = "image/P1/P1_MN08_Jacket_v01.png",   obtained = false },
}

local ArchiveOrder_ = { "C01", "C02", "C03", "C04", "MN02", "MN03", "MN07", "MN08" }

local deps_ = {}

function P1Archive.Configure(deps)
    deps_ = deps
end

function P1Archive.MarkObtained(imagePath)
    for key, entry in pairs(ImageGallery_) do
        if entry.path == imagePath then
            if not entry.obtained then
                entry.obtained = true
                print("[DEBUG图档] 线索图片已获得 id=" .. tostring(key) .. " 路径=" .. tostring(imagePath))
            end
            return
        end
    end
end

function P1Archive.Open()
    local dialog, content = deps_.getDialog()
    if not (dialog and content) then
        print("ERROR: dialog widgets not found")
        return
    end

    ClueArchiveUI.Open(
        dialog,
        content,
        ImageGallery_,
        ArchiveOrder_,
        deps_.buildTitleBlock,
        P1Archive.MarkObtained,
        deps_.closeDialog)
end

function P1Archive.ShowImage(imagePath, options)
    options = options or {}
    local dialog, content = deps_.getDialog()
    if not (dialog and content) then
        print("ERROR: dialog widgets not found")
        return
    end

    ClueArchiveUI.ShowImage(
        dialog,
        content,
        imagePath,
        options.title,
        deps_.buildTitleBlock,
        P1Archive.MarkObtained,
        deps_.closeDialog,
        options.onBack,
        options.returnLabel,
        options.fileLabel)
end

function P1Archive.IsObtained(id)
    local entry = ImageGallery_[id]
    return entry ~= nil and entry.obtained == true
end

function P1Archive.Reset()
    for _, entry in pairs(ImageGallery_) do
        entry.obtained = false
    end
end

function P1Archive.GetGallery()
    return ImageGallery_
end

function P1Archive.GetOrder()
    return ArchiveOrder_
end

return P1Archive
