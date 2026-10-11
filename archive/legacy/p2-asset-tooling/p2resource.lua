-- ============================================================================
-- scripts/p2resource.lua
-- 《零点之后》第二关「雪线诊所」资源系统模块
--
-- 本模块持有 P2 资源系统的运行时接口：资源事件派发、音频/图片占位接口、
-- 资源路径与文件存在性校验。
--
-- 依赖说明：
--   Story2 在主模块中是 local 变量，本模块无法跨文件访问，
--   因此本模块持有自己的局部依赖副本（local require）。
--   P2Asset 暂不在本阶段加载，待后续迁移函数时再按需引入。
-- ============================================================================

local Story2 = require("story2")
local P2Asset = require("p2asset")

-- P2 资源事件统一接口（V0.9-03 新增）
-- 根据 id 派发到对应的音频/图片资源调用，作为剧情节点的统一资源入口。
-- 支持：opening / tunnel / clinic / ending
-- 不接入真实播放系统，仅透传给 PlayP2Audio / ShowP2Image。
function TriggerP2ResourceEvent(id)
    print("[P2 Resource Event]\nid=" .. tostring(id))
    if id == "opening" then
        PlayP2Audio("opening")
    elseif id == "tunnel" then
        PlayP2Audio("tunnel")
        ShowP2Image("tunnel_bg")
    elseif id == "clinic" then
        PlayP2Audio("clinic")
        ShowP2Image("clinic_bg")
    elseif id == "ending" then
        PlayP2Audio("ending")
    else
        print("[P2 Resource Event] unknown id=" .. tostring(id))
    end
end

-- P2 音频接口（V0.9-01 新增，占位接口）
-- 仅从 Story2.resources.audio[id] 读取路径并打印，不接入真实播放。
-- id 取值：opening / tunnel / clinic / ending
function PlayP2Audio(id)
    local path = (Story2.resources and Story2.resources.audio and Story2.resources.audio[id]) or ""
    if path == "" then
        print("[P2 Audio]\nresource not assigned")
    else
        print("[P2 Audio]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
    end
end

-- P2 图片接口（V0.9-01 新增，占位接口）
-- 仅从 Story2.resources.image[id] 读取路径并打印，不接入真实渲染/加载。
-- id 取值：tunnel_bg / clinic_bg
function ShowP2Image(id)
    local path = (Story2.resources and Story2.resources.image and Story2.resources.image[id]) or ""
    if path == "" then
        print("[P2 Image]\nresource not assigned")
    else
        print("[P2 Image]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
    end
end

-- P2 资源路径检查（V0.9-04 新增）
-- 仅遍历 Story2.resources 配置，检查每个资源是否配置了路径（不检查文件是否真实存在）。
-- 有路径输出 [P2 Resource]，为空输出 [P2 Resource Missing]。
function ValidateP2Resources()
    print("[DEBUG P2] ===== resource validate START =====")
    local res = Story2.resources
    if not res then
        print("[DEBUG P2] no Story2.resources found")
        return
    end
    -- 音频
    if res.audio then
        for id, path in pairs(res.audio) do
            if path and path ~= "" then
                print("[P2 Resource]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
            else
                print("[P2 Resource Missing]\nid=" .. tostring(id))
            end
        end
    end
    -- 图片
    if res.image then
        for id, path in pairs(res.image) do
            if path and path ~= "" then
                print("[P2 Resource]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
            else
                print("[P2 Resource Missing]\nid=" .. tostring(id))
            end
        end
    end
    print("[DEBUG P2] ===== resource validate END =====")
end

-- P2 资源文件存在性验证（V0.9-05 新增）
-- 仅调用 FileExists 检查配置文件路径是否真实存在，不加载/不播放资源。
-- 存在 → [P2 Resource Found]；不存在 → [P2 Resource Missing File]。
function ValidateP2ResourceFiles()
    print("[DEBUG P2] ===== resource file validate START =====")
    local fs = GetFileSystem()
    if not fs then
        print("[DEBUG P2] GetFileSystem() returned nil")
        print("[DEBUG P2] ===== resource file validate END =====")
        return
    end
    local res = Story2.resources
    if not res then
        print("[DEBUG P2] no Story2.resources found")
        print("[DEBUG P2] ===== resource file validate END =====")
        return
    end
    -- 音频
    if res.audio then
        for id, path in pairs(res.audio) do
            if path and path ~= "" then
                if fs:FileExists(path) then
                    print("[P2 Resource Found]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
                else
                    print("[P2 Resource Missing File]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
                end
            else
                print("[P2 Resource Missing File]\nid=" .. tostring(id) .. "\npath=")
            end
        end
    end
    -- 图片
    if res.image then
        for id, path in pairs(res.image) do
            if path and path ~= "" then
                if fs:FileExists(path) then
                    print("[P2 Resource Found]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
                else
                    print("[P2 Resource Missing File]\nid=" .. tostring(id) .. "\npath=" .. tostring(path))
                end
            else
                print("[P2 Resource Missing File]\nid=" .. tostring(id) .. "\npath=")
            end
        end
    end
    print("[DEBUG P2] ===== resource file validate END =====")
end

-- ============================================================================
-- P2Asset 资源演示函数（V0.9-06 ~ V0.9-25）
-- 以下函数从 main.lua 原样迁移，逻辑/打印/参数均未改动。
-- 仅依赖全局 P2Asset 模块接口，不触碰任何状态系统。
-- ============================================================================

function ValidateP2AssetManifest()
    print("[DEBUG P2] ===== asset manifest validate START =====")
    local manifest = P2Asset.resources
    if not manifest then
        print("[DEBUG P2] no P2Asset.resources found")
        print("[DEBUG P2] ===== asset manifest validate END =====")
        return
    end
    for i = 1, #manifest do
        local r = manifest[i]
        print("[P2 Asset]"
              .. "\nid=" .. tostring(r.id)
              .. "\ntype=" .. tostring(r.type)
              .. "\nowner=" .. tostring(r.owner)
              .. "\nstatus=" .. tostring(r.status))
    end
    print("[DEBUG P2] ===== asset manifest validate END =====")
end

-- P2 资源资产状态校验（V0.9-07 新增）
-- 调用 p2asset.lua 的 P2Asset.ValidateStatus()，遍历并输出全部资源状态，不加载资源。
function ValidateP2AssetStatus()
    P2Asset.ValidateStatus()
end

-- P2 资源完成度统计展示（V0.9-08 新增）
-- 调用 p2asset.lua 的 P2Asset.GetProgress()，输出完成度统计，不加载资源。
function ShowP2AssetProgress()
    local p = P2Asset.GetProgress()
    print("[P2 Asset Progress]"
          .. "\ntotal=" .. tostring(p.total)
          .. "\ndone=" .. tostring(p.done)
          .. "\nreview=" .. tostring(p.review)
          .. "\ntodo=" .. tostring(p.todo)
          .. "\nprogress=" .. tostring(p.progress))
end

-- P2 按负责人分类的资源完成度统计展示（V0.9-09 新增）
-- 调用 p2asset.lua 的 P2Asset.GetDepartmentProgress()，分别输出 audio / art 两组统计。
function ShowP2DepartmentProgress()
    local d = P2Asset.GetDepartmentProgress()
    local function dump(label, p)
        print(label .. ":"
              .. "\ntotal=" .. tostring(p.total)
              .. "\ndone=" .. tostring(p.done)
              .. "\nreview=" .. tostring(p.review)
              .. "\ntodo=" .. tostring(p.todo)
              .. "\nprogress=" .. tostring(p.progress))
    end
    print("[P2 Department Progress]")
    dump("audio", d.audio)
    dump("art", d.art)
end

-- P2 批量修改资源状态演示（V0.9-10 新增）
-- 调用 p2asset.lua 的 P2Asset.SetDepartmentStatus()，输出本次批量修改的资源数量。
function BatchUpdateP2AssetStatusDemo()
    local function run(owner, status)
        local r = P2Asset.SetDepartmentStatus(owner, status)
        print("[P2 Asset Batch]"
              .. "\nowner=" .. tostring(owner)
              .. "\nchanged=" .. tostring(r.changed))
    end
    run("audio", "done")
    run("art", "review")
end

-- P2 审核数据统计展示（V0.9-12 新增）
-- 调用 p2asset.lua 的 P2Asset.GetReviewStats()，输出审核统计，不加载资源。
function ShowP2AssetReviewStats()
    local s = P2Asset.GetReviewStats()
    print("[P2 Asset Review Stats]"
          .. "\ntotal=" .. tostring(s.total)
          .. "\ntodo=" .. tostring(s.todo)
          .. "\nreview=" .. tostring(s.review)
          .. "\ndone=" .. tostring(s.done)
          .. "\ncompletion=" .. tostring(s.completionRate)
          .. "\nreviewRate=" .. tostring(s.reviewRate))
end

-- V0.9-13 P2 资源负责人统计（调用 P2Asset.GetOwnerStats）
function ShowP2AssetOwnerStats()
    local s = P2Asset.GetOwnerStats()
    local function emit(owner)
        local g = s[owner] or {}
        print("[P2 Asset Owner Stats]"
              .. "\nowner=" .. owner
              .. "\ntotal=" .. tostring(g.total)
              .. "\ndone=" .. tostring(g.done)
              .. "\nreview=" .. tostring(g.review)
              .. "\ntodo=" .. tostring(g.todo)
              .. "\ncompletion=" .. tostring(g.completionRate))
    end
    emit("audio")
    emit("art")
end

-- V0.9-14 P2 资源搜索接口演示（调用 P2Asset.FindResources）
function ShowP2AssetSearchDemo()
    local function emit(list)
        for i = 1, #list do
            local r = list[i]
            print("[P2 Asset Search]"
                  .. "\nid=" .. tostring(r.id)
                  .. "\ntype=" .. tostring(r.type)
                  .. "\nowner=" .. tostring(r.owner)
                  .. "\nstatus=" .. tostring(r.status))
        end
    end

    print("[P2 Asset Search] === owner=audio ===")
    emit(P2Asset.FindResources({ owner = "audio" }))

    print("[P2 Asset Search] === status=done ===")
    emit(P2Asset.FindResources({ status = "done" }))

    print("[P2 Asset Search] === owner=art + status=done ===")
    emit(P2Asset.FindResources({ owner = "art", status = "done" }))
end

-- V0.9-17 P2 资源类型筛选演示（调用 P2Asset.FindByType）
function ShowP2AssetTypeSearchDemo()
    local function emitOne(type)
        local list = P2Asset.FindByType(type)
        print("[P2 Asset Type Search] type=" .. tostring(type) .. " count=" .. tostring(#list))
        for i = 1, #list do
            local r = list[i]
            print("[P2 Asset Type Search]"
                  .. "\nid=" .. tostring(r.id)
                  .. "\nowner=" .. tostring(r.owner)
                  .. "\nstatus=" .. tostring(r.status))
        end
    end
    emitOne("audio")
    emitOne("image")
    emitOne("unknown")
end

-- V0.9-18 P2 资源组合筛选演示（调用 P2Asset.FindAdvanced）
function ShowP2AssetAdvancedSearchDemo()
    local function emitAdvanced(label, filter)
        local list = P2Asset.FindAdvanced(filter)
        print("[P2 Asset Advanced Search] " .. label .. " count=" .. tostring(#list))
        for i = 1, #list do
            local r = list[i]
            print("[P2 Asset Advanced Search]"
                  .. "\nid=" .. tostring(r.id)
                  .. "\nowner=" .. tostring(r.owner)
                  .. "\nstatus=" .. tostring(r.status))
        end
    end
    emitAdvanced("owner=audio+status=done", { owner = "audio", status = "done" })
    emitAdvanced("owner=art+status=done", { owner = "art", status = "done" })
    emitAdvanced("type=image+status=todo", { type = "image", status = "todo" })
    emitAdvanced("owner=unknown+status=done", { owner = "unknown", status = "done" })
end

-- V0.9-19 P2 查询结果统计演示（调用 P2Asset.GetSearchStats）
function ShowP2AssetSearchStatsDemo()
    local function emitStats(label, list)
        local s = P2Asset.GetSearchStats(list)
        print("[P2 Asset Search Stats] " .. label
              .. "\ntotal=" .. tostring(s.total)
              .. "\naudio=" .. tostring(s.audio)
              .. "\nimage=" .. tostring(s.image)
              .. "\ndone=" .. tostring(s.done)
              .. "\nreview=" .. tostring(s.review)
              .. "\ntodo=" .. tostring(s.todo))
    end
    emitStats("FindByType(audio)", P2Asset.FindByType("audio"))
    emitStats("FindAdvanced(image,todo)", P2Asset.FindAdvanced({ type = "image", status = "todo" }))
    emitStats("nil", nil)
end

-- V0.9-20 P2 查询结果排序演示（调用 P2Asset.SortResources）
function ShowP2AssetSortDemo()
    local list = P2Asset.FindAdvanced({ status = "todo" })
    local function emitSorted(mode)
        local sorted = P2Asset.SortResources(list, mode)
        print("[P2 Asset Sort] mode=" .. tostring(mode))
        for i = 1, #sorted do
            local r = sorted[i]
            print("[P2 Asset Sort]"
                  .. "\nid=" .. tostring(r.id)
                  .. "\ntype=" .. tostring(r.type)
                  .. "\nstatus=" .. tostring(r.status))
        end
    end
    emitSorted("id")
    emitSorted("status")
    emitSorted("type")
end

-- V0.9-21 P2 查询结果分页演示（调用 P2Asset.PaginateResources）
function ShowP2AssetPaginationDemo()
    local list = P2Asset.FindByType("image")
    local pageSize = 3
    for p = 1, 3 do
        local res = P2Asset.PaginateResources(list, p, pageSize)
        print("[P2 Asset Pagination]"
              .. "\npage=" .. tostring(res.page)
              .. "\npageSize=" .. tostring(res.pageSize)
              .. "\ntotal=" .. tostring(res.total)
              .. "\ntotalPages=" .. tostring(res.totalPages))
        for i = 1, #res.items do
            local r = res.items[i]
            print("[P2 Asset Pagination]"
                  .. "\nid=" .. tostring(r.id)
                  .. "\ntype=" .. tostring(r.type)
                  .. "\nstatus=" .. tostring(r.status))
        end
    end
end

-- V0.9-22 P2 资源导出演示（调用 P2Asset.ExportResources / ExportSummary）
function ShowP2AssetExportDemo()
    local list = P2Asset.FindAdvanced({ type = "image", status = "todo" })
    local exp = P2Asset.ExportResources(list)
    local sum = P2Asset.ExportSummary(list)
    print("[P2 Asset Export]"
          .. "\ncount=" .. tostring(exp.count)
          .. "\nsummary:"
          .. "\naudio=" .. tostring(sum.audio)
          .. "\nimage=" .. tostring(sum.image)
          .. "\ndone=" .. tostring(sum.done)
          .. "\nreview=" .. tostring(sum.review)
          .. "\ntodo=" .. tostring(sum.todo))
    for i = 1, #exp.resources do
        local r = exp.resources[i]
        print("[P2 Asset Export]"
              .. "\nid=" .. tostring(r.id)
              .. "\npath=" .. tostring(r.path)
              .. "\nowner=" .. tostring(r.owner)
              .. "\nstatus=" .. tostring(r.status))
    end
end

-- V0.9-23 P2 资源统一导出演示（调用 P2Asset.ExportPackage）
function ShowP2AssetExportPackageDemo()
    local list = P2Asset.FindAdvanced({ owner = "art", status = "todo" })
    local pkg = P2Asset.ExportPackage(list)
    print("[P2 Asset Package]"
          .. "\ncount=" .. tostring(pkg.count)
          .. "\nsummary:"
          .. "\naudio=" .. tostring(pkg.summary.audio)
          .. "\nimage=" .. tostring(pkg.summary.image)
          .. "\ndone=" .. tostring(pkg.summary.done)
          .. "\nreview=" .. tostring(pkg.summary.review)
          .. "\ntodo=" .. tostring(pkg.summary.todo))
    print("[P2 Asset Package] text:\n" .. pkg.text)
    print("[P2 Asset Package] csv:\n" .. pkg.csv)
end

-- V0.9-25 P2 资源版本管理演示（调用 P2Asset 版本接口）
function ShowP2AssetVersionDemo()
    local before = P2Asset.GetVersion("opening")
    print("[P2 Asset Version] before version=" .. tostring(before))
    local inc = P2Asset.IncrementVersion("opening")
    print("[P2 Asset Version] after version=" .. tostring(inc.newVersion)
          .. " success=" .. tostring(inc.success)
          .. " oldVersion=" .. tostring(inc.oldVersion))
    local ownerInc = P2Asset.IncrementOwnerVersion("art")
    print("[P2 Asset Version] owner=" .. tostring(ownerInc.owner)
          .. " changed=" .. tostring(ownerInc.changed))
    local csv = P2Asset.ExportCSV()
    print("[P2 Asset Version] csv header=" .. tostring(csv:match("^([^\n]+)")))
end
