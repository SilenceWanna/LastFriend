-- ============================================================================
-- scripts/p2asset.lua
-- 《零点之后》第二关「雪线诊所」资源资产清单
-- 本文件只保存 P2 资源资产清单（纯数据），不含任何加载/播放逻辑。
-- 逻辑层在 main.lua 的 ValidateP2AssetManifest（仅读取并输出，不加载资源）。
-- 字段：id / path / type / status / owner / version
--   status 默认 "todo"；owner: audio 资源归 "audio"，图片资源归 "art"。
--   version 默认 1，记录资源迭代次数（V0.9-25 新增）。
-- ============================================================================

local P2Asset = {}

-- P2 资源资产清单
-- 顺序：4 音频 + 7 图片，共 11 项。
P2Asset.resources = {
    -- 音频（owner = audio）
    { id = "opening",  path = "audio/p2/opening.wav",   type = "audio", status = "todo", owner = "audio", version = 1 },
    { id = "tunnel",   path = "audio/p2/tunnel.wav",    type = "audio", status = "todo", owner = "audio", version = 1 },
    { id = "clinic",   path = "audio/p2/clinic.wav",    type = "audio", status = "todo", owner = "audio", version = 1 },
    { id = "ending",   path = "audio/p2/ending.wav",    type = "audio", status = "todo", owner = "audio", version = 1 },

    -- 图片（owner = art）
    { id = "tunnel_bg", path = "image/P2/P2_BG01_Tunnel_v01.png", type = "image", status = "done", owner = "art", version = 1 },
    { id = "clinic_bg", path = "image/P2/P2_BG02_ClinicHall_v01.png", type = "image", status = "done", owner = "art", version = 1 },
    -- P2-C01 漫画（隧道线索图）
    { id = "comic", path = "image/P2/P2_C01_Comic_v01.png", type = "image", status = "done", owner = "art", version = 1 },
    -- P2-C08 药盒（药柜内药物资料二级配图）
    { id = "medicine_box", path = "image/P2/P2_C08_MedicineBox_v01.png", type = "image", status = "done", owner = "art", version = 1 },
    -- V1.0-07G 五张美术资源
    { id = "locker",            path = "image/P2/P2_C02_Locker_v02.png",           type = "image", status = "done", owner = "art", version = 1 },
    { id = "backpack_contents", path = "image/P2/P2_C03_BackpackContents_v01.png", type = "image", status = "done", owner = "art", version = 1 },
    { id = "computer",          path = "image/P2/P2_C06_Computer_v01.png",         type = "image", status = "done", owner = "art", version = 1 },
    { id = "medicine_cabinet",  path = "image/P2/P2_C07_MedicineCabinet_v01.png",  type = "image", status = "done", owner = "art", version = 1 },
    { id = "rest_area",         path = "image/P2/P2_BG03_RestArea_v01.png",         type = "image", status = "done", owner = "art", version = 1 },
    { id = "memory",            path = "image/P2/P2_C09_Memory_v01.png",           type = "image", status = "done", owner = "art", version = 1 },
    { id = "power",     path = "images/p2/power.png",     type = "image", status = "todo", owner = "art", version = 1 },
    { id = "terminal",  path = "images/p2/terminal.png",  type = "image", status = "todo", owner = "art", version = 1 },
    { id = "cabinet",   path = "images/p2/cabinet.png",   type = "image", status = "todo", owner = "art", version = 1 },
    { id = "bed",       path = "images/p2/bed.png",       type = "image", status = "todo", owner = "art", version = 1 },
    { id = "record",    path = "images/p2/record.png",    type = "image", status = "todo", owner = "art", version = 1 },
}

-- 按 id 查找资源索引（内部辅助）
local function findIndex(id)
    for i = 1, #P2Asset.resources do
        if P2Asset.resources[i].id == id then
            return i
        end
    end
    return nil
end

-- 修改指定 id 资源的 status（V0.9-07 新增）
function P2Asset.SetStatus(id, status)
    local idx = findIndex(id)
    if not idx then
        print("[P2 Asset] SetStatus: unknown id=" .. tostring(id))
        return
    end
    P2Asset.resources[idx].status = status
end

-- 读取指定 id 资源的 status（V0.9-07 新增）；未知 id 返回 nil
function P2Asset.GetStatus(id)
    local idx = findIndex(id)
    if not idx then
        return nil
    end
    return P2Asset.resources[idx].status
end

-- 遍历全部资源，输出 [P2 Asset Status]（V0.9-07 新增）；不加载资源
function P2Asset.ValidateStatus()
    print("[DEBUG P2] ===== asset status validate START =====")
    for i = 1, #P2Asset.resources do
        local r = P2Asset.resources[i]
        print("[P2 Asset Status]"
              .. "\nid=" .. tostring(r.id)
              .. "\nstatus=" .. tostring(r.status))
    end
    print("[DEBUG P2] ===== asset status validate END =====")
end

-- 统计辅助：对传入的资源列表按 status 计数并计算完成度
-- 返回 { total, done, review, todo, progress }
local function countStats(list)
    local total, done, review, todo = 0, 0, 0, 0
    for i = 1, #list do
        local s = list[i].status
        total = total + 1
        if s == "done" then
            done = done + 1
        elseif s == "review" then
            review = review + 1
        else
            todo = todo + 1
        end
    end
    local progress = 0
    if total > 0 then
        progress = math.floor(done / total * 100)
    end
    return {
        total = total,
        done = done,
        review = review,
        todo = todo,
        progress = progress,
    }
end

-- 资源完成度统计（V0.9-08 新增）
-- 统计各状态数量并计算完成度（progress = done / total * 100，向下取整）。
-- 返回 table：{ total, done, review, todo, progress }
function P2Asset.GetProgress()
    return countStats(P2Asset.resources)
end

-- 按负责人（owner）分类的资源完成度统计（V0.9-09 新增）
-- 根据 resource.owner 归入 audio / art 两组，分别统计状态与完成度。
-- 返回 { audio = {...}, art = {...} }，每组结构同 GetProgress。
function P2Asset.GetDepartmentProgress()
    local audioList, artList = {}, {}
    for i = 1, #P2Asset.resources do
        local r = P2Asset.resources[i]
        if r.owner == "audio" then
            audioList[#audioList + 1] = r
        elseif r.owner == "art" then
            artList[#artList + 1] = r
        end
    end
    return {
        audio = countStats(audioList),
        art = countStats(artList),
    }
end

-- 批量修改指定 owner 下所有资源的状态（V0.9-10 新增）
-- 遍历 resources，若 resource.owner == owner，则将其 status 设为传入 status。
-- 支持 owner: "audio" / "art"；未知 owner 不改任何资源，返回 changed=0。
-- 返回 { changed = 修改数量 }
function P2Asset.SetDepartmentStatus(owner, status)
    local changed = 0
    for i = 1, #P2Asset.resources do
        local r = P2Asset.resources[i]
        if r.owner == owner then
            r.status = status
            changed = changed + 1
        end
    end
    return { changed = changed }
end

-- 资源审核状态流转（V0.9-11 新增）
-- 三个函数均返回 { success, oldStatus, newStatus }。
-- 仅在指定前置状态下发生流转，其他状态保持不变。

-- todo → review；非 todo 时保持不变
function P2Asset.SubmitForReview(id)
    local idx = findIndex(id)
    if not idx then
        return { success = false, oldStatus = nil, newStatus = nil }
    end
    local r = P2Asset.resources[idx]
    local old = r.status
    if old == "todo" then
        r.status = "review"
        return { success = true, oldStatus = old, newStatus = "review" }
    end
    return { success = false, oldStatus = old, newStatus = old }
end

-- review → done；非 review 时保持不变
function P2Asset.Approve(id)
    local idx = findIndex(id)
    if not idx then
        return { success = false, oldStatus = nil, newStatus = nil }
    end
    local r = P2Asset.resources[idx]
    local old = r.status
    if old == "review" then
        r.status = "done"
        return { success = true, oldStatus = old, newStatus = "done" }
    end
    return { success = false, oldStatus = old, newStatus = old }
end

-- review → todo；非 review 时保持不变
function P2Asset.Reject(id)
    local idx = findIndex(id)
    if not idx then
        return { success = false, oldStatus = nil, newStatus = nil }
    end
    local r = P2Asset.resources[idx]
    local old = r.status
    if old == "review" then
        r.status = "todo"
        return { success = true, oldStatus = old, newStatus = "todo" }
    end
    return { success = false, oldStatus = old, newStatus = old }
end

-- 审核数据统计（V0.9-12 新增）
-- 复用 countStats 统计各状态数量，并计算完成率 / 审核率（向下取整百分比）。
-- 返回 { total, todo, review, done, completionRate, reviewRate }
function P2Asset.GetReviewStats()
    local s = countStats(P2Asset.resources)
    local completionRate = 0
    local reviewRate = 0
    if s.total > 0 then
        completionRate = math.floor(s.done / s.total * 100)
        reviewRate = math.floor(s.review / s.total * 100)
    end
    return {
        total = s.total,
        todo = s.todo,
        review = s.review,
        done = s.done,
        completionRate = completionRate,
        reviewRate = reviewRate,
    }
end

-- 负责人资源统计（V0.9-13 新增）
-- 类似 GetDepartmentProgress，按 owner 归类为 audio / art，
-- 但额外输出每个负责人的完成率（completionRate = done / total * 100，向下取整）。
-- 返回 { audio = {total,done,review,todo,completionRate}, art = {...} }。
function P2Asset.GetOwnerStats()
    local groups = { audio = {}, art = {} }
    for i = 1, #P2Asset.resources do
        local r = P2Asset.resources[i]
        if groups[r.owner] then
            groups[r.owner][#groups[r.owner] + 1] = r
        end
    end
    local result = {}
    for owner, list in pairs(groups) do
        local s = countStats(list)
        result[owner] = {
            total = s.total,
            done = s.done,
            review = s.review,
            todo = s.todo,
            completionRate = s.progress,
        }
    end
    return result
end

-- 按条件查询资源（V0.9-14 新增）
-- filter 为可选字段表，支持任意组合：
--   filter.owner  : 按负责人匹配（"audio" / "art"）
--   filter.type   : 按资源类型匹配（"audio" / "image"）
--   filter.status : 按状态匹配（"todo" / "review" / "done"）
-- 字段为 nil 时忽略该条件；所有非空条件需同时满足（AND）。
-- 返回符合条件的资源对象列表（引用，非拷贝）。
function P2Asset.FindResources(filter)
    filter = filter or {}
    local result = {}
    for i = 1, #P2Asset.resources do
        local r = P2Asset.resources[i]
        if (filter.owner == nil or r.owner == filter.owner)
           and (filter.type == nil or r.type == filter.type)
           and (filter.status == nil or r.status == filter.status) then
            result[#result + 1] = r
        end
    end
    return result
end

-- 按类型快捷查询资源（V0.9-17 新增）
-- 复用 FindResources({ type = type })，不复制筛选逻辑。
-- type 为 nil 时返回空列表；type 为未知值时 FindResources 自然不匹配也返回空列表。
-- 返回符合条件的资源对象列表（引用，非拷贝），元素保留 id/path/type/status/owner。
function P2Asset.FindByType(type)
    if type == nil then
        return {}
    end
    return P2Asset.FindResources({ type = type })
end

-- 组合条件筛选资源（V0.9-18 新增）
-- 复用 FindResources()，支持 owner / type / status 多条件同时筛选（AND）。
-- 边界处理：
--   filter 为 nil  → 返回空列表 {}，不报错（避免退化为返回全部）。
--   未知字段       → 被 FindResources 自然忽略，不影响查询。
-- 返回符合条件的资源对象列表（引用，非拷贝），元素保留 id/path/type/status/owner。
function P2Asset.FindAdvanced(filter)
    if filter == nil then
        return {}
    end
    return P2Asset.FindResources({
        owner = filter.owner,
        type = filter.type,
        status = filter.status,
    })
end

-- 对查询结果列表做统计（V0.9-19 新增）
-- 输入：资源列表（如 FindAdvanced / FindByOwner / FindByType 返回值），不重新查询、不修改资源、无副作用。
-- 统计字段：total（总数）、audio（type=audio 数）、image（type=image 数）、
--           done（status=done 数）、review（status=review 数）、todo（其他状态数）。
-- 边界：list 为 nil → 返回全 0 统计，不报错。
function P2Asset.GetSearchStats(list)
    if list == nil then
        return { total = 0, audio = 0, image = 0, done = 0, review = 0, todo = 0 }
    end
    local s = { total = 0, audio = 0, image = 0, done = 0, review = 0, todo = 0 }
    for i = 1, #list do
        local r = list[i]
        s.total = s.total + 1
        if r.type == "audio" then
            s.audio = s.audio + 1
        elseif r.type == "image" then
            s.image = s.image + 1
        end
        if r.status == "done" then
            s.done = s.done + 1
        elseif r.status == "review" then
            s.review = s.review + 1
        else
            s.todo = s.todo + 1
        end
    end
    return s
end

-- 对查询结果列表排序（V0.9-20 新增）
-- 输入：list（来自 FindResources/FindByOwner/FindByStatus/FindAdvanced 等），mode 排序模式。
-- 支持 mode：
--   "id"     : 按 id 字符串升序
--   "status" : 按状态优先级 done < review < todo（id 作为稳定次键）
--   "type"   : 按类型优先级 audio < image（id 作为稳定次键）
-- 边界：list 为 nil → 返回空列表 {}；mode 未知 → 返回原列表副本，不报错。
-- 仅排序：返回新的排序列表，不修改原始 list 顺序、不修改资源对象内容、不修改资源状态。
function P2Asset.SortResources(list, mode)
    if list == nil then
        return {}
    end
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    if mode == "id" then
        table.sort(copy, function(a, b) return a.id < b.id end)
    elseif mode == "status" then
        local rank = { done = 1, review = 2, todo = 3 }
        table.sort(copy, function(a, b)
            local ra, rb = rank[a.status] or 3, rank[b.status] or 3
            if ra ~= rb then return ra < rb end
            return a.id < b.id
        end)
    elseif mode == "type" then
        local rank = { audio = 1, image = 2 }
        table.sort(copy, function(a, b)
            local ra, rb = rank[a.type] or 2, rank[b.type] or 2
            if ra ~= rb then return ra < rb end
            return a.id < b.id
        end)
    end
    return copy
end

-- 对查询结果列表分页（V0.9-21 新增）
-- 输入：list（查询接口返回的资源列表）、page（页码，从 1 开始）、pageSize（每页数量）。
-- 返回：{ items, page, pageSize, total, totalPages }
-- 边界处理：
--   list 为 nil          → items={}, total=0, totalPages=0（page/pageSize 保留入参修正值）
--   page < 1             → 自动修正为 1
--   pageSize <= 0        → 自动修正为 1
--   page 超过 totalPages → items={}，仍保留 page/pageSize/total/totalPages
-- 仅切片：不修改原始 list、不修改资源对象内容、不修改资源状态。
function P2Asset.PaginateResources(list, page, pageSize)
    if page == nil or page < 1 then page = 1 end
    if pageSize == nil or pageSize <= 0 then pageSize = 1 end
    local total = list and #list or 0
    local totalPages = 0
    if total > 0 then
        totalPages = math.ceil(total / pageSize)
    end
    local items = {}
    if total > 0 and page <= totalPages then
        local startIdx = (page - 1) * pageSize + 1
        local endIdx = math.min(page * pageSize, total)
        for i = startIdx, endIdx do
            items[#items + 1] = list[i]
        end
    end
    return {
        items = items,
        page = page,
        pageSize = pageSize,
        total = total,
        totalPages = totalPages,
    }
end

-- 导出资源列表（V0.9-22 新增）
-- 输入：list（查询接口返回的资源列表；也兼容 PaginateResources 的 { items = {...} } 形式）。
-- 返回：{ count, resources }，resources 为字段副本（id/path/type/status/owner），
--       不直接暴露原 resources 引用、不修改资源对象、不改变资源状态。
-- 边界：list 为 nil → { count=0, resources={} }。
function P2Asset.ExportResources(list)
    if list == nil then
        return { count = 0, resources = {} }
    end
    local src = list.items or list
    local resources = {}
    for i = 1, #src do
        local r = src[i]
        resources[#resources + 1] = {
            id = r.id,
            path = r.path,
            type = r.type,
            status = r.status,
            owner = r.owner,
            version = r.version or 1,
        }
    end
    return { count = #resources, resources = resources }
end

-- 导出资源统计（V0.9-22 新增）
-- 复用 GetSearchStats()，不重写统计逻辑。
-- 输入：list（同 ExportResources，兼容 { items = {...} } 形式）。
-- 返回：{ count, audio, image, done, review, todo }。
function P2Asset.ExportSummary(list)
    local src = (list and list.items) or list
    local s = P2Asset.GetSearchStats(src)
    return {
        count = s.total,
        audio = s.audio,
        image = s.image,
        done = s.done,
        review = s.review,
        todo = s.todo,
    }
end

-- 将 list 规整为资源数组（V0.9-23 内部复用）
-- 兼容：查询返回列表、ExportResources().resources、PaginateResources().items、{items=...}。
local function toArray(list)
    if list == nil then return {} end
    if list.resources then return list.resources end
    if list.items then return list.items end
    return list
end

-- 文本导出（V0.9-23 新增）
-- 输入：资源列表（兼容 list / {items} / {resources} 形式）。
-- 返回：字符串，格式 [P2 Asset List] + count + 每项 id/type/owner/status/path。
-- 仅读取、不修改资源对象、不改变状态、不写文件。
-- 边界：list 为 nil → 仅返回表头 + count=0。
function P2Asset.ExportText(list)
    local arr = toArray(list)
    local lines = { "[P2 Asset List]", "count=" .. tostring(#arr) }
    for i = 1, #arr do
        local r = arr[i]
        lines[#lines + 1] = tostring(i) .. "."
        lines[#lines + 1] = "id=" .. tostring(r.id)
        lines[#lines + 1] = "type=" .. tostring(r.type)
        lines[#lines + 1] = "owner=" .. tostring(r.owner)
        lines[#lines + 1] = "status=" .. tostring(r.status)
        lines[#lines + 1] = "version=" .. tostring(r.version or 1)
        lines[#lines + 1] = "path=" .. tostring(r.path)
    end
    return table.concat(lines, "\n")
end

-- CSV 导出（V0.9-23 新增，V0.9-25 增加 version 列）
-- 字段顺序固定：id,type,owner,status,version,path；无多余空格。
-- 返回：CSV 字符串（首行为 header）。
-- 边界：list 为 nil → 仅返回 header 行。
function P2Asset.ExportCSV(list)
    local arr = toArray(list)
    local lines = { "id,type,owner,status,version,path" }
    for i = 1, #arr do
        local r = arr[i]
        lines[#lines + 1] = table.concat(
            { tostring(r.id), tostring(r.type), tostring(r.owner), tostring(r.status), tostring(r.version or 1), tostring(r.path) },
            ",")
    end
    return table.concat(lines, "\n")
end

-- 统一导出（V0.9-23 新增）
-- 一次性聚合：count / text / csv / summary，全部复用已有接口，不重复统计逻辑。
-- 返回：{ count, text, csv, summary }
function P2Asset.ExportPackage(list)
    local exp = P2Asset.ExportResources(list)
    return {
        count = exp.count,
        text = P2Asset.ExportText(list),
        csv = P2Asset.ExportCSV(list),
        summary = P2Asset.ExportSummary(list),
    }
end

-- 读取资源版本（V0.9-25 新增）
-- 返回资源 version 字段（未设置时兼容默认 1）；未知 id 返回 nil。
function P2Asset.GetVersion(id)
    local idx = findIndex(id)
    if not idx then
        return nil
    end
    return P2Asset.resources[idx].version or 1
end

-- 单资源版本升级（V0.9-25 新增）
-- 仅修改 version（status/owner/path 不变），返回 { success, oldVersion, newVersion }。
-- 未知 id 返回 { success=false, oldVersion=nil, newVersion=nil }。
function P2Asset.IncrementVersion(id)
    local idx = findIndex(id)
    if not idx then
        return { success = false, oldVersion = nil, newVersion = nil }
    end
    local r = P2Asset.resources[idx]
    local oldV = r.version or 1
    local newV = oldV + 1
    r.version = newV
    return { success = true, oldVersion = oldV, newVersion = newV }
end

-- 负责人批量版本升级（V0.9-25 新增）
-- 所有 owner 匹配的资源 version +1（仅修改 version），返回 { owner, changed }。
-- 未知 owner 返回 { owner=owner, changed=0 }。
function P2Asset.IncrementOwnerVersion(owner)
    local changed = 0
    for i = 1, #P2Asset.resources do
        local r = P2Asset.resources[i]
        if r.owner == owner then
            r.version = (r.version or 1) + 1
            changed = changed + 1
        end
    end
    return { owner = owner, changed = changed }
end

return P2Asset
