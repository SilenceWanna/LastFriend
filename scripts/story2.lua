-- ============================================================================
-- scripts/story2.lua
-- 《零点之后》第二关「雪线诊所」剧情与资源数据
-- 说明：本文件只保存可见文本、分支配置与资源路径，不包含 UI 或流程逻辑。
--       剧情编排由 p2controller.lua 及 P2 功能模块负责。
-- ============================================================================

local Story2 = {}

-- 场景名称
Story2.sceneName = "雪线诊所"

-- ----------------------------------------------------------------------------
-- 阶段名称（与 P2State.phase 对应，供 UI 和日志使用）
-- ----------------------------------------------------------------------------
Story2.phases = {
    ENTER   = "进入",
    TUNNEL  = "隧道",
    CLINIC  = "诊所",
    SETTLE  = "结算",
}

-- ----------------------------------------------------------------------------
-- P2 开场连续对白
-- 数据结构与 P1_OPENING_DIALOG 100% 对齐：仅允许 speaker/text、narration、inner 三种字段。
-- 由 p2controller.lua 的 PlayP2Opening() 通过 StartOpeningDialogue 调用。
-- ----------------------------------------------------------------------------
Story2.openingDialog = {
    { narration = "零穿上防护外套，" },
    { narration = "跟着弦离开废弃休眠区。" },
    { narration = "厚重的隔离门缓缓开启。" },
    { narration = "门外是一条照明系统几乎完全瘫痪的地下通道。" },
    { narration = "弦打开手电筒。" },
    { narration = "微弱的光束只能照亮前方一小片区域。" },
    { narration = "路线终端投射出一道短暂的蓝色导航光。" },
    { narration = "墙壁表面覆着一层薄冰。" },
    { narration = "空气寒冷而安静。" },
    { narration = "只剩两人的脚步声在隧道中不断回荡。" },
    { inner = "没有她，我连哪条路还能走都不知道。", audioIds = { "P2-EXIT-INNER-001" } },
    { narration = "零刚走出休眠区没多久。" },
    { narration = "脚步忽然一顿。" },
    { narration = "眼前一阵发黑。" },
    { narration = "身体失去平衡。" },
    { narration = "向前倒去。" },
    { narration = "弦几乎是条件反射地扶住了她。" },
}

-- ----------------------------------------------------------------------------
-- P2 返回现实后续固定对白（V1.0 P2 第四批修正：从 openingDialog 迁出的 6 句）
-- 正式剧本中归属：微选择 → MEMORY 01 → 返回现实 之后，不能在微选择之前播放。
-- 数据结构与 openingDialog / P1_OPENING_DIALOG 100% 对齐，仅用 speaker/text、narration、inner。
-- 本批仅建立数据表，不调用；后续在 ShowP2SupportChoice() → Memory01 → 返回现实后接入。
-- ----------------------------------------------------------------------------
Story2.postMemoryDialog = {
    { speaker = "我", text = "……\n弦。", audioIds = { "P2-S01-ZERO-001" } },
    { speaker = "弦", text = "嗯？", audioIds = { "P2-S01-XIAN-001" } },
    { speaker = "我", text = "你看起来对这里很熟。", audioIds = { "P2-S01-ZERO-002" } },
    { speaker = "弦", text = "来的时候探过路。", audioIds = { "P2-S01-XIAN-002" } },
    { narration = "短暂停顿。" },
    { narration = "弦用手电筒照向前方结冰的地面。" },
}

-- ----------------------------------------------------------------------------
-- P2 SCENE02 进入诊所（V1.0 P2 第九批）
-- 数据格式与 P1_OPENING_DIALOG / openingDialog 100% 对齐：仅用 speaker/text、narration、inner。
-- 由 FinishP2Opening() 经 StartOpeningDialogue 播放；结束后接入调查入口。
-- 不含系统提示 / 倒计时。
-- ----------------------------------------------------------------------------
Story2.scene02Dialog = {
    { narration = "两人在暴风雪抵达前进入废弃诊所。" },
    { narration = "这里原本属于学校。" },
    { narration = "后来被改造成临时医疗站。" },
    { narration = "室内没有供电。" },
    { narration = "窗外已经被白色风雪覆盖。" },
    { speaker = "弦", text = "你先坐一会儿。", audioIds = { "P2-S02-XIAN-001" } },
    { speaker = "弦", text = "我去找能用的物资。" },
    { speaker = "我", text = "好。", audioIds = { "P2-S02-ZERO-001" } },
    { narration = "弦提着手电筒走向外侧药架。" },
}

-- ----------------------------------------------------------------------------
-- P2 MEMORY 01（V1.0 P2 第五批）
-- 数据结构与 P1 MemoryEvents[id].steps 完全一致：steps 数组，单步仅用 speaker/text 或 narration。
-- 本批不修改 P1 Memory 系统、不复制 TriggerMemoryEvent，由 p2controller 的 PlayP2Memory01() 复用同格式播放。
-- ----------------------------------------------------------------------------
Story2.memory01 = {
    steps = {
        { speaker = "过去的零", text = "别动。", audioIds = { "P2-M01-ZERO-001" } },
        { narration = "弦没有反抗。" },
        { speaker = "过去的零", text = "我不会丢下你。", audioIds = { "P2-M01-ZERO-001" } },
        { narration = "弦抬头看向零。" },
        { narration = "她的眼神混杂着依赖、愤怒、还有无法说出口的失望。" },
        { narration = "记忆突然中断。" },
    },
}

-- ----------------------------------------------------------------------------
-- P2 返回现实对白（V1.0 P2 第五批）
-- 数据结构与 P1_OPENING_DIALOG / openingDialog 100% 对齐：仅用 speaker/text、narration、inner。
-- 由 PlayP2ReturnDialogue() 经 StartOpeningDialogue 播放；结束后接入 postMemoryDialog。
-- ----------------------------------------------------------------------------
Story2.returnDialog = {
    { speaker = "我", text = "", audioIds = { "P2-RETURN-ZERO-001" } },
    { speaker = "弦", text = "零？", audioIds = { "P2-RETURN-XIAN-001" } },
    { speaker = "我", text = "我刚才……", audioIds = { "P2-RETURN-ZERO-002" } },
    { speaker = "弦", text = "先离开这里。", audioIds = { "P2-RETURN-XIAN-002" } },
}

-- ----------------------------------------------------------------------------
-- P2 扶住微选择：A 路线对白（V1.0 P2 第六批数据化）
-- 格式与 openingDialog 100% 对齐（speaker/text、narration、inner）。
-- 由 ShowP2SupportChoice() 的 A 分支经 StartOpeningDialogue 调用，结束后进入 Memory01。
-- ----------------------------------------------------------------------------
Story2.supportAcceptDialog = {
    { narration = "弦扶住了我。" },
}

-- ----------------------------------------------------------------------------
-- P2 扶住微选择：B 路线对白（V1.0 P2 第六批数据化）
-- 格式与 openingDialog 100% 对齐。
-- 由 ShowP2SupportChoice() 的 B 分支经 StartOpeningDialogue 调用，结束后进入 Memory01。
-- ----------------------------------------------------------------------------
Story2.supportRejectDialog = {
    { speaker = "我", text = "我自己能走。", audioIds = { "P2-EXIT-ZERO-PUSH-001" } },
    { speaker = "弦", text = "……\n好。", audioIds = { "P2-EXIT-XIAN-PUSH-001" } },
}

-- ----------------------------------------------------------------------------
-- P2 线索数据（V1.0 P2 第七批：调查系统基础框架，仅搭结构）
-- 结构与 P1 Story.clues 完全一致：title / inspect / dialogue。本批不填正式剧情。
-- 以后第二关所有线索全部放这里；dialogue 为询问弦的完整对白数组。
-- ----------------------------------------------------------------------------
Story2.clues = {
    -- KEY03 窗帘后的应急电源（V1.0 P2 第十三批）
    -- 结构对齐 P1 Story.clues：title / inspect / dialogue；dialogue 为恢复电源连续对白。
    power = {
        title = "应急电源",
        inspect = "诊室窗帘后藏着一台小型应急电源，插头已经松脱。",
        dialogue = {
            { inner = "找到了，还能用。", audioIds = { "P2-K03-ZERO-001" } },
            { narration = "零重新接好插头，按下启动开关。" },
            { narration = "诊室灯光连续闪烁两次，随后勉强稳定下来。\n桌上的电脑自动开机，黑暗中无法辨认的调查区域也逐渐显现。" },
        },
    },
    -- 诊室电脑：双状态热点（V1.0 P2 第十四批）
    -- 结构对齐 P1 Story.clues：title / inspect / dialogue。
    -- 字段含义固定，不区分通电前/后（通电前/后由 controller 按 p2.flags.powerRestored 切换展示，见 OnP2ClueClicked "computer"）。
    -- dialogue 为通电前「检查电脑」连续对白（3 句 inner）。
    computer = {
        title = "诊室电脑",
        inspect = "诊室桌上放着一台旧电脑。\n按下电源键，没有任何反应。",
        dialogue = {
            { inner = "没电。", audioIds = { "P2-K01-ZERO-001" } },
            { inner = "线路没有坏。", audioIds = { "P2-K01-ZERO-002" } },
            { inner = "应该还有应急电源。", audioIds = { "P2-K01-ZERO-003" } },
        },
    },
    -- KEY02 药柜密码 0718（V1.0 P2 第二十批 + 本批互动扩展）
    -- 结构对齐 P1 Story.clues：title / inspect / dialogue。
    -- inspect：首次调查的环境描述（长描述弹窗正文）。
    -- dialogue：零的内心台词（2 句 inner），首次调查逐句紧凑对白播放。
    -- cabinetAsk：本批新增「寻求弦的帮助」求证对白（4 句 speaker/text）。
    --   弦不直接提供密码；对话结束由 controller 进入现有四位数字键盘。
    --   audioIds 仅登记配音 ID，不参与播放（对齐 Story2 其它 audioIds 约定）。
    --   注意：P2-K02-ZERO-003 原为空 slot，本批按台本登记为「弦，你知道密码吗？」，不保留空白 step。
    cabinet = {
        title = "锁住的药柜",
        inspect = "墙边的金属药柜使用四位数字密码，柜门完好，没有被撬开的痕迹。",
        dialogue = {
            { inner = "四位密码。", audioIds = { "P2-K02-ZERO-001" } },
            { inner = "诊室里会有吗？" },
        },
        cabinetAsk = {
            dialogue = {
                { speaker = "我", text = "弦，你知道这个柜子的密码吗？", audioIds = { "P2-K02-ZERO-002" } },
                { speaker = "弦", text = "不知道。", audioIds = { "P2-K02-XIAN-001" } },
                { speaker = "我", text = "你不是来过吗？", audioIds = { "P2-K02-ZERO-003" } },
                { speaker = "弦", text = "我只来过外面。", audioIds = { "P2-K02-XIAN-002" } },
            },
        },
    },
}

-- ----------------------------------------------------------------------------
-- P2 诊室电脑文件列表（V1.0 P2 第十五批）：仅文件列表，不含正文。
-- 结构：id + title。本批不写正文 / 不写屏幕文字 / 不写 inner。
-- 由 p2controller 的 ShowP2ComputerFiles() 读取并生成文件按钮。
-- ----------------------------------------------------------------------------
Story2.computerFiles = {
    {
        id = "record",
        title = "值班记录.docx",
    },
    {
        id = "diary",
        title = "校医日记.docx",
    },
    {
        id = "migration",
        title = "迁移选拔统计.xlsx",
    },
}

-- ----------------------------------------------------------------------------
-- P2 诊室电脑文件正文（V1.0 P2 第十六批）：仅本批实现 record。
-- 数据结构与 P1_OPENING_DIALOG / openingDialog 100% 对齐：仅用 narration / inner / speaker / text。
-- 由 p2controller 的 ShowP2ComputerFiles() 在点击对应文件时经 StartOpeningDialogue 播放。
-- ----------------------------------------------------------------------------
Story2.computerFileContent = {
    record = {
        title = "值班记录.docx",
        steps = {
            { narration =
                "临时诊所将在暴风雪期间开放。\n" ..
                "储备药品仅供已登记人员使用。\n" ..
                "非紧急患者不得领取清醒维持剂。"
            },
            { inner = "清醒维持剂……", audioIds = { "P2-K04-ZERO-001" } },
            { inner = "休眠之后使用的药？", audioIds = { "P2-K04-ZERO-002" } },
        },
    },
    -- KEY04 第二份文件（V1.0 P2 第十七批）：校医日记.docx
    -- 数据结构与 record / openingDialog 100% 对齐：仅用 narration / inner。
    diary = {
        title = "校医日记.docx",
        steps = {
            { narration =
                "7月18日。\n" ..
                "弦再次把零送来。\n" ..
                "低血糖、短暂意识丧失、过度疲劳。\n" ..
                "她坚持说零只是“没睡好”。\n" ..
                "我让她记住药柜密码，免得下次又站在门口等。"
            },
            { inner = "7月18日。", audioIds = { "P2-K04-ZERO-003" } },
            { inner = "“再次”……", audioIds = { "P2-K04-ZERO-004" } },
            { inner = "她以前经常送我来这里？", audioIds = { "P2-K04-ZERO-005" } },
        },
    },
    -- KEY04 第三份文件（V1.0 P2 第十八批）：迁移选拔统计.xlsx
    -- 数据结构与 record / diary / openingDialog 100% 对齐：仅用 narration / inner。
    migration = {
        title = "迁移选拔统计.xlsx",
        steps = {
            { narration =
                "【零】\n" ..
                "技术／评级：技术权限最高\n" ..
                "迁移资格：通过\n" ..
                "随迁家属：0\n\n" ..

                "【弦】\n" ..
                "技术／评级：医疗维护权限\n" ..
                "迁移资格：条件通过\n" ..
                "随迁家属：0\n\n" ..

                "【身份损坏人员】\n" ..
                "技术／评级：未成年／无独立劳动力评级\n" ..
                "迁移资格：未通过\n" ..
                "随迁家属：—"
            },
            { narration =
                "表格下方附有一条校医留下的工作日记。\n\n" ..
                "今晚又有人来问，能不能修改家属资格。\n" ..
                "我已经解释过很多次，医疗系统没有权限改变迁移名单。\n" ..
                "没有迁移资格，也没有登记为随迁家属，就无法进入迁移程序。\n" ..
                "即使有人愿意放弃自己的位置，系统也不会自动把名额转给另一个人。"
            },
        },
    },
    -- KEY04 migration 阅读后零的内心独白（点击「返回电脑」后播放，两句各一页）。
    -- audioIds 仅登记配音，不参与播放；正文与滚动窗口保持原样。
    migrationEpilogue = {
        {
            inner = "随迁家属都是零。",
            audioIds = { "P2-K04-ZERO-006" },
        },
        {
            inner = "那个未成年人是谁？",
            audioIds = { "P2-K04-ZERO-007" },
        },
    },
}

-- ----------------------------------------------------------------------------
-- P2 电脑文件「可选求证」对白（V1.0 P2 第十九批）：仅本批实现 migration（求证03）。
-- 结构对齐 P1 Story.clues / support*Dialog：dialogue 数组，单步用 speaker / text。
-- 由 p2controller 在 migration 文件播放结束后，经「询问弦」按钮由 StartOpeningDialogue 复用播放。
-- ----------------------------------------------------------------------------
Story2.computerAsk = {
    migration = {
        dialogue = {
            { speaker = "我", text = "弦，这个未成年人的记录是谁？", audioIds = { "P2-K04-ZERO-008" } },
            { speaker = "弦", text = "身份信息已经损坏，名字看不出来。", audioIds = { "P2-K04-XIAN-001" } },
            { speaker = "我", text = "你认识她。", audioIds = { "P2-K04-ZERO-009" } },
            { speaker = "弦", text = "先把药找出来。其他的以后再说。", audioIds = { "P2-K04-XIAN-002" } },
        },
    },
}

-- ----------------------------------------------------------------------------
-- P2 药柜内容列表（V1.0 P2 第二十一批）：仅 id / title，不含正文。
-- 结构对齐 Story2.computerFiles。由 p2controller 的 ShowP2Cabinet() 读取生成按钮。
-- recordBook（登记本）与 medicalKit（医用急救箱）均已接入。
-- ----------------------------------------------------------------------------
Story2.cabinetContent = {
    {
        id = "recordBook",
        title = "登记本",
    },
    {
        id = "medicalKit",
        title = "医用急救箱",
    },
}

-- ----------------------------------------------------------------------------
-- P2 药柜登记本正文（V1.0 P2 第二十一批）：KEY05。
-- 数据结构与 openingDialog / computerFileContent.* 100% 对齐：仅 narration / inner。
-- 由 ShowP2Cabinet() 点击「登记本」经 StartOpeningDialogue 播放，结束自动返回药柜列表。
-- ----------------------------------------------------------------------------
Story2.cabinetRecord = {
    title = "登记本",
    steps = {
        { narration = "7月18日，21:40。" },
        { narration = "送诊人：弦。" },
        { narration = "患者：零。" },
        { narration = "症状：眩晕、低血糖、短暂意识中断。" },
        { narration = "处置：补充营养。" },
        { narration = "注射清醒维持剂。" },
        { inner = "她真的带我来过这里。", audioIds = { "P2-K05-ZERO-001" } },
        { inner = "而且不止一次。", audioIds = { "P2-K05-ZERO-002" } },
    },
}

-- ----------------------------------------------------------------------------
-- P2 药柜医用急救箱正文（V1.0 P2 第二十二批，KEY05 第二部分）
-- 数据结构与 cabinetRecord / computerFileContent.* / openingDialog 100% 对齐：仅 narration / inner。
-- 由 ShowP2Cabinet() 点击「医用急救箱」经 StartOpeningDialogue 播放，结束自动返回药柜列表。
-- 本批仅查看，不获得物品 / 不写入背包 / 不新增状态 / 不剧情推进。
-- ----------------------------------------------------------------------------
Story2.medicalKit = {
    title = "医用急救箱",
    steps = {
        { narration = "一支未使用针管。" },
        { narration = "消毒棉。" },
        { narration = "绷带。" },
        { narration = "一瓶标签完整的短效镇静剂。" },
        { narration = "空置的清醒维持剂卡槽。" },
        { inner = "短效镇静，剂量足够让成年人睡几个小时。", audioIds = { "P2-K05-ZERO-003" } },
        { inner = "如果真的需要摆脱弦……\n这可能是唯一的机会。", audioIds = { "P2-K05-ZERO-004" } },
    },
}

-- ----------------------------------------------------------------------------
-- P2 药柜医用急救箱「已查看」简短提示（V1.0 P2 第二十五批）
-- 重复查看急救箱时播放，避免每次重播 9 步内容。
-- 结构对齐 medicalKit / openingDialog：仅 title / steps / inner。文本不硬编码进 controller。
-- ----------------------------------------------------------------------------
Story2.medicalKitReviewed = {
    title = "医用急救箱",
    steps = {
        { inner = "里面已经没有值得继续调查的信息。" },
    },
}

-- ----------------------------------------------------------------------------
-- P2 获得物品提示（V1.0 P2 第二十三批）：查看医用急救箱后播放。
-- 数据结构与 cabinetRecord / openingDialog 100% 对齐：仅 narration。
-- 播放结束由 ShowP2Cabinet 置 inventory.syringe / inventory.sedative = true，再返回药柜。
-- ----------------------------------------------------------------------------
Story2.obtainItems = {
    steps = {
        { narration = "获得：针管。" },
        { narration = "获得：短效镇静剂。" },
    },
}

-- ----------------------------------------------------------------------------
-- 隧道阶段数据
-- ----------------------------------------------------------------------------
Story2.tunnel = {
    title = "隧道",

    -- 广播文本（调查「广播」后展示）
    broadcast = {
        title = "墙上的广播",
        text =
            "系统广播：\n距离下一轮暴风雪抵达还有三分钟。\n\n" ..
            "系统广播：\n请就近进入封闭建筑。\n\n" ..
            "弦：\n抓紧时间。\n\n" ..
            "弦：\n前面有间诊所，可以暂时休息。",
    },

    -- 漫画文本（调查「漫画」后展示）
    comic = {
        title = "地上的漫画书",
        text =
            "地面上一本被踩脏、已经受潮的漫画书。\n封面画着一座漂浮在星空中的城市，\n内页有几处儿童涂鸦。\n\n儿童涂鸦：黄色星星、三个人牵手、远处的空间站。",
        dialogue = {
            { inner = "这本书……", audioIds = { "P2-E01-ZERO-001" } },
            { inner = "这些涂鸦，好像在哪里见过。", audioIds = { "P2-E01-ZERO-002" } },
        },
    },

    -- 排班表文本（调查「排班表」后展示；普通调查线索，不含角色互动）
    schedule = {
        title = "半张排班表",
        text =
            "雪线诊所 · 值班排班（残页）\n\n" ..
            "夜班：——（被撕掉）\n" ..
            "替班：弦\n\n" ..
            "备注：当日仅一人到岗。",
    },

    -- 求证文本（玩家对弦「求证」时弦的回应；走独立 P2 询问，不碰 P1 asked_/response）
    -- 结构：保留顶层 verify.title / verify.text 供现有「求证弦」按钮（id=verify）读取（不破坏调用约定）；
    -- 两个独立求证事件以子字段 comic / cabinet 承载（D2 专项同步）。
    -- 当前 controller 的 verify 分支仅消费顶层 title/text（对应求证01 漫画）；
    -- 求证02 药柜密码数据由药柜流程使用。
    verify = {
        title = "求证：漫画",
        text =
            "我：\n你见过这本书吗？\n\n" ..
            "弦：\n这种旧漫画很常见\n\n" ..
            "我：\n里面的涂鸦呢？\n\n" ..
            "弦：\n没注意过。",
        -- 求证01：漫画与涂鸦（对应顶层 title/text）
        comic = {
            title = "求证：漫画",
            text =
                "我：\n你见过这本书吗？\n\n" ..
                "弦：\n这种旧漫画很常见\n\n" ..
                "我：\n里面的涂鸦呢？\n\n" ..
                "弦：\n没注意过。",
        },
        -- 求证02：药柜密码（仅数据注册，当前无独立按钮，待程序适配）
        cabinet = {
            title = "求证：药柜密码",
            text =
                "我：\n弦，你知道这个柜子的密码吗？\n\n" ..
                "弦：\n不知道。\n\n" ..
                "我：\n你不是来过吗？\n\n" ..
                "弦：\n我只来过外面。",
        },
    },

    -- 四条次要线索（环境观察，独立 P2 flags 保存，重复查看不重复触发）
    minorClues = {
        leak = {
            title = "重复脚印",
            dialogue = {
                { narration = "隧道地面积着一层薄灰。\n除了两人刚留下的脚印外，\n还能看见一组已经模糊的旧脚印。" },
                { inner = "有人从这里走过去" },
                { inner = "后来又沿原路回来了" },
            },
            audioIds = { "P2-T01-ZERO-001", "P2-T01-ZERO-002" },
        },
        sign = {
            title = "被涂改的箭头",
            text = "原来的路线被人改过。\n弦走的是后来画的方向。",
        },
        cart = {
            title = "冻住的儿童手套",
            text = "小孩子的……\n这里以前也有家属通过？",
        },
        poster = {
            title = "排班表",
            text =
                "雪线诊所 · 值班排班（残页）\n" ..
                "夜班：——（被撕掉）\n" ..
                "替班：弦\n" ..
                "备注：当日仅一人到岗。",
        },
    },

    -- 暴风雪广播（隧道自由调查双条件达成后播放；不修改原「广播」线索文本）
    blizzard = {
        { narration = "隧道顶部的广播突然恢复运行。" },
        { narration = "电流噪音后进入警报。" },
        { speaker = "系统广播", text = "距离下一轮暴风雪抵达还有三分钟。", audioIds = { "P2-PA-001" } },
        { speaker = "系统广播", text = "请就近进入封闭建筑。", audioIds = { "P2-PA-002" } },
        { speaker = "弦", text = "抓紧时间。", audioIds = { "P2-S01-XIAN-003" } },
        { speaker = "弦", text = "前面有间诊所，可以暂时休息。", audioIds = { "P2-S01-XIAN-004" } },
    },
}

-- ----------------------------------------------------------------------------
-- 诊所阶段数据（逻辑在 P2 功能模块）
-- ----------------------------------------------------------------------------
Story2.clinic = {
    title = "诊所",

    -- 诊所开场文本（进入诊所自动展示）
    opening =
        "弦：\n你先坐一会儿。\n\n" ..
        "弦：\n我去找能用的物资。",

    -- 五个调查点（独立 P2 诊所逻辑，不碰 P1 调查系统）
    clues = {
        -- 电脑终端：支持「未通电 / 已通电」两种状态。
        terminal = {
            -- 电源未恢复时查看
            terminalLocked = {
                title = "诊室电脑（未通电）",
                text =
                    "没电。\n" ..
                    "线路没有坏。\n" ..
                    "应该还有应急电源。",
            },
            -- 电源恢复后查看
            terminalActive = {
                title = "医疗终端（已通电）",
                text =
                    "你合上备用电源后，终端的待机灯亮起。\n" ..
                    "屏幕缓缓亮起，进入系统主界面。\n" ..
                    "主界面列出数份「患者档案」与一份「值班记录」——\n" ..
                    "可以调阅其中的内容。",
            },
        },
        -- 终端可查看的记录列表（电源恢复后由 OpenP2TerminalRecords 调阅）
        -- 纯数据：title + text，逻辑层只负责读取并展示。
        terminalRecords = {
            {
                title = "值班记录 · 雪夜",
                text =
                    "【值班记录】\n" ..
                    "今晚仅我一人值守。\n" ..
                    "患者状况稳定，但药品库存见底。\n" ..
                    "外面的雪一直没停，电话也打不通。",
            },
            {
                title = "患者档案 · 镇静剂",
                text =
                    "【患者档案】\n" ..
                    "长期处方：镇静剂，标签署名与诊所登记不符。\n" ..
                    "备注栏写着：『用量需医师确认』——但医师本月未到岗。",
            },
            {
                title = "区域广播 · 残余",
                text =
                    "【系统日志】\n" ..
                    "检测到区域广播残余记录已自动归档。\n" ..
                    "内容同隧道内广播：『仅一名值班』。",
            },
        },
        -- 电源设备：支持恢复前后的不同文本状态。
        power = {
            -- 电源未恢复时查看
            powerOff = {
                title = "电源设备",
                text =
                    "墙上的配电箱半开着。\n" ..
                    "主闸是合上的，但有一路备用电源被手动断开。\n" ..
                    "（此时电脑、医疗终端均无电源，无法使用。）",
                hint = "（可尝试操作：恢复电源）",
            },
            -- 电源恢复后查看
            powerOn = {
                title = "电源设备（已通电）",
                text =
                    "你合上了那路备用电源。\n" ..
                    "配电箱指示灯由红转绿，诊所的灯次第亮起。\n" ..
                    "电脑与医疗终端的待机灯同时亮了起来——\n" ..
                    "现在它们有电了，可以接入后续系统。",
            },
            -- 恢复电源成功后的提示文本（供 RestoreP2Power() 调用）
            restoreSuccess =
                "找到了。\n" ..
                "零接通电源。\n" ..
                "还能用。\n" ..
                "诊所灯光闪烁两次后亮起，电脑自动启动，原本无法看清的调查点全部开放。",
        },
        -- 药柜：支持「未通电 / 已通电」两种状态。
        cabinet = {
            -- 电源未恢复时查看
            cabinetLocked = {
                title = "药柜（未通电）",
                text =
                    "四位密码。\n" ..
                    "密码应该留在这里的某份记录里。",
            },
            -- 电源恢复后查看
            cabinetActive = {
                title = "药柜（已通电）",
                text =
                    "备用电源接通后，药柜的电子锁「嘀」地一声解锁。\n" ..
                    "柜门缓缓弹开，里面分类摆着几样药物。\n" ..
                    "每支都贴着标签，可以调阅药物资料。",
            },
        },
        -- 药柜内的药物数据（电源恢复后由 OpenP2MedicationRecords 调阅）
        -- 纯数据：id / name / description。本阶段不含效果计算 / 结局逻辑。
        medications = {
            {
                id = "sedative",
                name = "镇静剂",
                description = "常见于本诊所的长期处方。标签署名与登记不符，备注要求医师确认用量。",
                -- V1.0-07N-P2-B2-B：取得镇静剂+针管相关文本（短效镇静剂与针管同位于诊所药物储备，一并取得）。
                takeText =
                    "零（内心）：\n短效镇静剂……还有一支空针管。\n\n" ..
                    "零（内心）：\n如果要用，现在就能拿走。\n\n" ..
                    "系统提示：已取走短效镇静剂与针管。",
                takenText =
                    "系统提示：短效镇静剂与针管已在身上。",
            },
            {
                id = "analgesic",
                name = "镇痛片",
                description = "常规镇痛药，库存见底。说明书写着『勿与镇静剂同服』。",
            },
            {
                id = "antibiotic",
                name = "抗生素",
                description = "广谱抗生素，仅余两盒。过期日期被人为涂改过。",
            },
        },
        bed = {
            title = "空置病床",
            text =
                "有人在这里住过。\n" ..
                "离开时甚至整理了床铺。",
        },
        -- （V1.0 P2 本批：CLINIC「医疗记录」record 简化重复数据已删除；
        --   唯一正式入口为 HALL「墙上的分诊制度」triageRules → MINOR-C04，
        --   核心进度 flag recordViewed 迁移至 triageRules 查看完成时设置。）
        -- 附加调查点：弦的旧储物柜（MINOR-C11，纯数据，逻辑在 p2controller 的 OnP2ClinicClueClicked）
        -- 附加内容，不计入五项探索完成条件，不新增主流程 flag。
        locker = {
            title = "储物柜",
            text =
                "墙角立着一个旧储物柜，柜门贴着一张褪色的姓名标签，\n" ..
                "字迹被磨得模糊，只能勉强看清一个「弦」字。\n" ..
                "拉开柜门，里面是空的——\n" ..
                "什么都没留下，像是从没人回来取过。",
        },
        -- 附加二级内容：储物柜内的背包（C03，作为 locker 的二级查看，不独立成点）
        -- 仅描述背包内可见的随身物品，不扩写角色背景、不新增其他线索。
        backpack = {
            title = "背包内容",
            text =
                "柜子底层塞着一个旧背包，拉链半开。\n" ..
                "里面只有几件换洗衣物、一个空药瓶，\n" ..
                "和一张被揉皱又展平的值班表——\n" ..
                "边角写着同一个名字：「弦」。",
        },
    },

    -- 诊所探索完成事件（由 P2 controller 的同名流程读取）。
    -- 五个调查点 + 电源恢复全部完成后触发一次。
    exploreCompleteEvent = {
        title = "线索齐了",
        -- 弦对白（逐句按 \n 分段）
        xianLines =
            "弦：\n“电源、终端、药柜、床、记录……都看过了。”\n" ..
            "弦：\n“现在我能拼出今晚发生了什么。”",
        -- 玩家对白（逐句按 \n 分段）
        playerLines =
            "我：\n“你看到的是……什么？”\n" ..
            "我：\n“这诊所，今晚到底几个人？”",
        -- 信息总结文本（事件展示后的收束说明）
        summary =
            "【线索总结】\n" ..
            "· 备用电源被手动断开过，现已恢复。\n" ..
            "· 终端记录显示：今晚仅一名值班，药品库存见底。\n" ..
            "· 药柜药物标签署名与登记不符，镇静剂备注要求医师确认。\n" ..
            "· 病床近期有人，医疗记录签名被涂黑。\n" ..
            "（随后将进入最终抉择，本步骤仅记录完成事件。）",
    },
}

-- ----------------------------------------------------------------------------
-- 休息互动阶段数据（V1.0-07J 接入，见下方 Story2.clinic.restEvents）
-- 原 07I-B 的独立炉火场景已回退，本数据块仅保留作旧存档兼容。
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- 休息互动阶段（V1.0-07J，SCENE04，诊所自由调查的一部分，非独立 Scene）
-- 三个可选互动：取暖炉 / 弦的背包 / 帮助弦整理药盒（→ MEMORY 02）。
-- 纯数据；逻辑在 p2controller 的 OnP2ClinicClueClicked 三个分支。
-- 不新增 flag、不写入存档、不参与五项探索完成条件。
-- 文本严格按《P2_雪线诊所_完整制作剧本_v3.0》SCENE04，不润色、不扩写。
-- ----------------------------------------------------------------------------
Story2.clinic.restEvents = {
    -- V1.0-07N-P2-B2-C：对弦使用短效镇静剂（条件显隐入口，非独立场景）。
    -- 仅数据；逻辑在 p2controller 的 OnP2ClinicClueClicked "useSedative" 分支。
    -- 文本严格按剧本 SCENE05「镇静弦」演出，不润色、不扩写。
    useSedative = {
        title = "使用短效镇静剂",
        confirmText =
            "系统提示：是否对弦使用短效镇静剂？\n\n" ..
            "（弦背对零整理药物。一旦使用，将无法逆转。）",
        successText =
            "零将镇静剂抽入针管。弦听见身后的声音，刚准备回头——\n" ..
            "针尖刺入的瞬间，她的动作停住了。\n\n" ..
            "弦缓缓倒下，呼吸变得平稳而缓慢。\n" ..
            "系统提示：弦已进入镇静状态。",
        successDialogue = {
            { speaker = "弦", text = "零？你还是不信我。", audioIds = { "P2-SED-XIAN-001" } },
        },
    },
    -- V1.0-07N-P2-B2-D：检查弦的物品（搜身，仅弦被镇静后开放）。
    -- 仅数据；逻辑在 p2controller 的 OnP2ClinicClueClicked "searchXian" 分支。
    -- 文本严格按剧本 §820-838（搜身交互 A/B）与 EVENT 04 / §225（清醒维持剂可选取得），不润色、不扩写。
    searchXian = {
        title = "检查弦的物品",
        menuText = "要检查弦的哪里？",
        outerwear = {
            title = "路线地图",
            inventoryKey = "route_map",
            text =
                "弦失去意识后，玩家可检查她外套内侧。路线地图折叠在贴身口袋／地图套中。\n\n" ..
                "系统提示：取得弦的路线地图。",
            dialogue = {
                { inner = "地图在她身上。", audioIds = { "P2-SEARCH-ZERO-001" } },
                { inner = "她从一开始就没打算让我自己走。", audioIds = { "P2-SEARCH-ZERO-002" } },
            },
            takenText = "系统提示：已经找到路线地图。",
        },
        wrist = {
            title = "身份手环",
            inventoryKey = "identity_bracelet",
            text =
                "弦的身份手环仍扣在左手腕上。玩家必须手动解除卡扣。\n\n" ..
                "系统提示：取得弦的身份手环。",
            dialogue = {
                { inner = "外部通道需要她的身份验证。", audioIds = { "P2-SEARCH-ZERO-003" } },
                { inner = "拿走这个，她就没法追上来了。", audioIds = { "P2-SEARCH-ZERO-004" } },
            },
            takenText = "系统提示：已经取得身份手环。",
        },
    },
    -- EVENT 02：点燃炉火（点击「取暖炉」）
    hearth = {
        title = "取暖炉",
        text =
            "零：\n有点冷，我点个火。\n\n" ..
            "弦：\n嗯。",
        dialogue = {
            { speaker = "我", text = "有点冷，我点个火。", audioIds = { "P2-FIRE-ZERO-001" } },
            { speaker = "弦", text = "嗯。", audioIds = { "P2-FIRE-XIAN-001" } },
        },
    },
    -- EVENT 03：弦的背包（点击「弦的背包」）
    backpack = {
        title = "弦的背包",
        text =
            "背包中：\n" ..
            "· 漫画书\n" ..
            "· 折叠的儿童画\n" ..
            "· 普通补给\n\n" ..
            "（路线地图不在背包内。身份手环仍戴在弦手腕上。）\n\n" ..
            "漫画扉页：\n「姐姐，等你回来，我们一起看结局。」\n\n" ..
            "儿童画：两名女孩牵手，旁边黄色星星。\n\n" ..
            "零内心：\n“姐姐”……\n这本书属于她的家人。\n隧道里的那一本，又是谁留下的？",
    },
    -- EVENT 05：帮助弦整理药盒（点击「整理药盒」）→ 关系值 +4 → MEMORY 02
    organize = {
        title = "整理药盒",
        text = "弦的药盒中有三种外观近似的药。",
        -- V1.0 P2 第二十六批：整理完成后重复点击的简短提示（防重复触发完整演出 / 重复加关系值）
        doneText = "药盒已经整理好了。",
        -- MEMORY 02：《她又晕倒了》（C09 演出图）
        memoryTitle = "记忆 · 她又晕倒了",
        memorySteps = {
            { speaker = "过去的弦", text = "校医！", audioIds = { "P2-M02-XIAN-001" } },
            { narration = "没有回应。" },
            { speaker = "过去的弦", text = "她又晕倒了！", audioIds = { "P2-M02-XIAN-001" } },
            { speaker = "过去的零", text = "弦……", audioIds = { "P2-M02-ZERO-001" } },
            { speaker = "过去的弦", text = "别说话。", audioIds = { "P2-M02-XIAN-002" } },
            { narration = "弦把零放到病床上，拉开药柜，却发现校医不在。" },
            { speaker = "过去的弦", text = "校医怎么不在……", audioIds = { "P2-M02-XIAN-002" } },
            { speaker = "过去的弦", text = "你等一下。", audioIds = { "P2-M02-XIAN-003" } },
            { speaker = "过去的弦", text = "我去给你拿药。", audioIds = { "P2-M02-XIAN-003" } },
            { narration = "屏幕文字：清醒维持剂" },
        },
        memorySystemText = "已解锁药物识别：清醒维持剂。",
        memoryText =
            "过去的诊所走廊。弦背着零快步跑进诊所，呼吸非常急促。\n\n" ..
            "过去的弦：\n校医！\n\n" ..
            "没有回应。\n\n" ..
            "过去的弦：\n她又晕倒了！\n\n" ..
            "背上的零勉强睁开眼睛。\n\n" ..
            "过去的零：\n弦……\n\n" ..
            "过去的弦：\n别说话。\n\n" ..
            "弦把零放到病床上，拉开药柜，却发现校医不在。\n\n" ..
            "过去的弦：\n校医怎么不在……\n\n" ..
            "她深吸一口气。\n\n" ..
            "过去的弦：\n你等一下。\n\n" ..
            "过去的弦：\n我去给你拿药。\n\n" ..
            "镜头特写药盒。弦取出一支标有蓝色横线的药剂。\n" ..
            "屏幕文字：清醒维持剂\n\n" ..
            "记忆中断。\n" ..
            "系统提示：已解锁药物识别：清醒维持剂。",
    },
    -- EVENT 04：弦的药盒（自由调查，仅文本数据注册，当前无独立交互入口）
    -- 纯数据；不新增按钮 / flag / 关系值 / 交互逻辑。待后续接入调用方可启用。
    medication = {
        title = "弦的药盒",
        text =
            "我：\n就是登记本里的药。\n\n" ..
            "我：\n它能让我保持清醒。\n\n" ..
            "我：\n三种药的外观几乎一样。\n\n" ..
            "我：\n拿错的话，后果可能更糟。",
        -- EVENT04 药盒调查零的内心独白：已识别分支（已查看登记本）
        steps = {
            { inner = "清醒维持剂", audioIds = { "P2-MED-ZERO-001" } },
            { inner = "另外两种……标签已经看不清了", audioIds = { "P2-MED-ZERO-002" } },
            { inner = "它们分别有什么作用……", audioIds = { "P2-MED-ZERO-004" } },
        },
        -- EVENT04 药盒调查零的内心独白：未识别分支（未获得识别信息）
        stepsUnknown = {
            { inner = "三种药的外观几乎一样。", audioIds = { "P2-MED-ZERO-003" } },
            { inner = "它们分别有什么作用……", audioIds = { "P2-MED-ZERO-004" } },
        },
    },
}

-- ----------------------------------------------------------------------------
-- EVENT 03 弦的背包：基础互动骨架（本批新增，独立数据；不复用 restEvents.backpack 旧文本）
-- 流程：两条屏幕文字（不配音，各一页）→ 三句零的内心独白（inner，各一页）→ 第一层选择。
-- audioIds 仅登记配音 ID，不参与播放；第一层选择仅入口，分支对白与系统效果后续批次接入。
-- ----------------------------------------------------------------------------
Story2.bagEvent = {
    title = "弦的背包",
    -- 开场描述：合并为单一紧凑窗口文本（背包内容 + 漫画扉页 + 儿童画），不再拆页
    opening =
        "背包中只有漫画书、一张折叠的儿童画和普通补给。\n\n" ..
        "（路线地图不在背包中。身份手环仍戴在弦手腕上。）\n\n" ..
        "漫画扉页：\n姐姐，等你回来，我们一起看结局。\n\n" ..
        "儿童画：\n两名女孩牵手，旁边画着黄色星星。",
    -- 三句零的内心独白（StartOpeningDialogue 逐页播放）
    inner = {
        { inner = "“姐姐”……", audioIds = { "P2-BAG-ZERO-001" } },
        { inner = "这本书是她家人的？", audioIds = { "P2-BAG-ZERO-002" } },
        { inner = "隧道里的那一本，又是谁留下的？", audioIds = { "P2-BAG-ZERO-003" } },
    },
    -- ----------------------------------------------------------------------------
    -- 「拿漫画质问弦」第一段质问对白（EVENT 03 第二层入口，本批新增）
    -- 演出备注（声音彻底冷下来 / 弦伸出手 / 弦的视线落在被打开的背包上）仅为制作参考：
    --   · 弦的视线… → 已转为 narration 第 4 步；
    --   · 弦伸出手   → 已转为 narration 第 8 步；
    --   · 声音彻底冷下来 → 不显示。
    -- 前 8 步经 StartOpeningDialogue 逐页播放；第 9 步（XIAN-002「把书还给我」）由 controller
    -- 单独渲染，并在同页底部挂第二层两个选择（无【继续】、无独立空白选择页）。
    -- audioIds 仅登记配音 ID，不参与播放；narration 不配音。
    -- ----------------------------------------------------------------------------
    confront = {
        title = "弦的背包",
        steps = {
            { speaker = "我", text = "弦。\n\n为什么你的包里也有这本书？", audioIds = { "P2-BAG-ZERO-004" } },
            { narration = "弦回头。" },
            { narration = "弦的视线落在被打开的背包上。" },
            { speaker = "弦", text = "你翻了我的东西。", audioIds = { "P2-BAG-XIAN-001" } },
            { speaker = "我", text = "书里面那颗黄色的星星。", audioIds = { "P2-BAG-ZERO-005" } },
            { narration = "弦伸出手。" },
        },
        -- 第二层选择挂在 XIAN-002「把书还给我」这一页
        lastStep = { speaker = "弦", text = "把书还给我", audioIds = { "P2-BAG-XIAN-002" } },
    },
    -- ----------------------------------------------------------------------------
    -- 「把漫画还给弦」结算对白（EVENT 03 第二层 A 路线，本批新增）
    -- 两步经 StartOpeningDialogue 逐页播放；对白完整结束后由 controller 统一结算：
    --   关系值 -3（AddXianTrust(-3)）→ 耐心 -1（ConsumeP2Patience，>0 保护）
    --   → 置 bagStarChildKnown（弦认识黄色星星对应的孩子，但拒绝说明身份）+ bagConfronted（质问路线已完成）
    -- 本批不触发负面记忆；narration 不配音。
    -- ----------------------------------------------------------------------------
    returnComic = {
        title = "弦的背包",
        steps = {
            { narration = "零把漫画递回去。弦接过后重新放进背包。" },
            { speaker = "弦", text = "别再翻我的东西", audioIds = { "P2-BAG-XIAN-003" } },
        },
    },
    -- ----------------------------------------------------------------------------
    -- 「继续追问」B 路线对白（EVENT 03 第二层，本批新增）
    -- 8 步经 StartOpeningDialogue 逐页播放；XIAN-007 完整结束后由 controller 统一结算：
    --   关系值 -6（AddXianTrust(-6)）→ 耐心直接归 0（不检查剩余）→ 触发负面记忆《迁移名单》
    --   → 置 bagConfronted + bagFamilyKnown（弦有一名会称她为“姐姐”的家人）。
    -- 演出备注（弦的视线落在被打开的背包上）已转为第 2 步 narration，不显示制作标记。
    -- audioIds 仅登记配音 ID，不参与播放；narration 不配音。
    -- ----------------------------------------------------------------------------
    pressFurther = {
        title = "弦的背包",
        steps = {
            { speaker = "我", text = "她是谁？", audioIds = { "P2-BAG-ZERO-006" } },
            { narration = "弦的视线落在被打开的背包上。" },
            { speaker = "弦", text = "不重要", audioIds = { "P2-BAG-XIAN-004" } },
            { speaker = "我", text = "你一直在回避", audioIds = { "P2-BAG-ZERO-007" } },
            { speaker = "弦", text = "因为那不是你的东西", audioIds = { "P2-BAG-XIAN-005" } },
            { speaker = "我", text = "但它可能和我有关", audioIds = { "P2-BAG-ZERO-008" } },
            { speaker = "弦", text = "你以前也是这样\n只要你觉得一件事和你有关，就认为自己有权知道全部", audioIds = { "P2-BAG-XIAN-006" } },
        },
    },
}

-- ----------------------------------------------------------------------------
-- P2 负面记忆《迁移名单》（EVENT 03 B 路线专用，MEMORY 02B；正文为本批按正式剧本逐字写入）
-- 格式与 Story2.memory01.steps 一致（narration 或 speaker/text 单步），
-- 供 PlayP2Memory01(customSteps, onComplete) 播放（接入调用另行处理，本批仅数据）。
--   · steps：记忆本体 10 步（2 段 narration + 6 句对白 + 2 段 narration）
--   · returnSteps：返回现实数据（与 steps 分离，后续由自定义 onComplete 播放，本批仅数据不接调用）
-- audioIds 仅登记配音 ID，不参与播放；narration 与 returnSteps 不配音。
-- 演出备注（冷静；像在宣读规则 / 压着情绪 / 声音开始发抖 / 极轻；第一次明确拒绝零 / 镜头与声音）
-- 仅为制作参考，不写入可见台词。
-- ----------------------------------------------------------------------------
Story2.memories = Story2.memories or {}
Story2.memories.migrationList = {
    title = "迁移名单",
    -- MEMORY 02B 开场图片（缺图时由 controller 安全跳过）。
    --   · migrationScreen：正在运行的电脑与《迁移选拔统计.xlsx》界面
    --   · flashbackScene ：正式进入回忆后的画面
    -- 路径沿用项目现有 image/P2/ 规范；文件名保持 P2_MEM01_* 规范名（无中文/括号/空格，统一下划线）
    images = {
        migrationScreen = "image/P2/P2_MEM01_SECOND_SUSPICION.png",
        flashbackScene  = "image/P2/P2_MEM01_FLASHBACK_SCENE.png",
    },
    -- 原开场两段 narration 已删除（改由上述两张图片承载），steps 直接从第一句对白开始
    steps = {
        { speaker = "过去的零", text = "不能带家属。", audioIds = { "P2-MB02-ZERO-001" } },
        { speaker = "过去的弦", text = "她才十岁。", audioIds = { "P2-MB02-XIAN-001" } },
        { speaker = "过去的零", text = "规定就是规定。", audioIds = { "P2-MB02-ZERO-002" } },
        { speaker = "过去的弦", text = "她一个人留在这里会死。", audioIds = { "P2-MB02-XIAN-002" } },
        { speaker = "过去的零", text = "我不会签字。", audioIds = { "P2-MB02-ZERO-003" } },
        { narration = "弦沉默，缓缓握紧鼠标。\n屏幕中的“迁移资格：未通过”被指针遮住一瞬。" },
        { speaker = "过去的弦", text = "……你别管。", audioIds = { "P2-MB02-XIAN-003" } },
        { narration = "画面出现乱码与撕裂，耳鸣骤然升高，\n记忆中断。" },
    },
    -- 返回现实（与 steps 分离；后续在 PlayP2Memory01 自定义 onComplete 中播放）
    returnSteps = {
        { narration = "零扶住桌沿，呼吸变得急促。\n弦看了她一眼，没有询问，也没有靠近。" },
    },
}

-- ----------------------------------------------------------------------------
-- P2 结局演出数据（V1.0 P2 本批新增：仅结构化剧情数据，未接入 finalChoice / 结局判定 / P3 跳转）
--   · trustXian   结局 A：相信弦，与弦同行
--   · leaveAlone  结局 B：独自离开
--   · xianLeaves  结局 C：弦离开零
--   · enterP3     通用转场：回到原点（未来进入 P3，本轮仅数据）
-- 格式与 memory01 / migrationList.steps 一致（narration 或 speaker/text 单步，逐页播放）。
-- audioIds 仅登记配音 ID，不参与播放；narration 不配音。
-- 制作备注（喘息 / 声音发颤 / 低声 / 镜头与声音 等）仅为制作参考，不写入可见文本。
-- 结局叶（leave_now / stay_dawn sub）到 A/B/C 的映射下一轮单独处理，本批不做任何绑定。
-- ----------------------------------------------------------------------------
Story2.p2Endings = {
    -- 结局 A：相信弦，与弦同行
    trustXian = {
        title = "相信弦，与弦同行",
        steps = {
            { narration = "暴风雪中。" },
            { narration = "狂风声不断逼近，视线逐渐模糊。" },
            { narration = "零和弦在雪地中艰难前进。" },
            { speaker = "我", text = "弦……", audioIds = { "P2-END-A-ZERO-001" } },
            { narration = "没有回应。" },
            { speaker = "我", text = "弦……", audioIds = { "P2-END-A-ZERO-002" } },
            { narration = "风声越来越大，远处的人影逐渐模糊。" },
            { speaker = "我", text = "弦，你在哪……", audioIds = { "P2-END-A-ZERO-003" } },
            { narration = "画面逐渐失焦。" },
            { narration = "黑屏。" },
        },
    },
    -- 结局 B：独自离开
    leaveAlone = {
        title = "独自离开",
        steps = {
            { narration = "暴风雪中，零独自前进。" },
            { narration = "她手中的设备发出微弱光亮。" },
            { narration = "零回头，身后没有任何人。" },
            { narration = "寒风越来越强，视线逐渐模糊。" },
            { speaker = "我", text = "不能停……不能停……", audioIds = { "P2-END-B-ZERO-001" } },
            { narration = "意识逐渐远去。" },
            { narration = "零倒在雪地中。" },
            { narration = "黑屏。" },
        },
    },
    -- 结局 C：弦离开零
    xianLeaves = {
        title = "弦离开零",
        steps = {
            { narration = "【诊所内，炉火微弱燃烧。】" },
            { narration = "【零靠着墙坐在炉火旁，外套裹在身上，已经睡着。】" },
            { narration = "【弦站在不远处，安静地看了零一会儿。】" },
            { narration = "【短暂停顿。】" },
            { speaker = "弦", text = "对不起。", audioIds = { "P2-END-XIAN-001" } },
            { speaker = "弦", text = "这次，我不能再听你的了。", audioIds = { "P2-END-XIAN-002" } },
            { narration = "【弦背起自己的东西，转身走向出口。】" },
            { narration = "【诊所门打开，暴风雪的声音瞬间灌入室内。】" },
            { narration = "【弦走进风雪，她的身影逐渐消失在门外。】" },
            { narration = "【诊所门缓缓关上，室内重新只剩炉火燃烧的声音。】" },
            { narration = "【零仍然没有醒。】" },
            { narration = "【她在睡梦中轻轻皱眉。】" },
            { speaker = "零", text = "弦……", audioIds = { "P2-END-C-ZERO-001" } },
        },
    },
    -- 通用转场：进入 P3《回到原点》（本轮仅数据，不调用 P3）
    enterP3 = {
        title = "回到原点",
        steps = {
            { narration = "黑屏。" },
            { narration = "黑暗中传来微弱的呼吸声。" },
            { narration = "一滴眼泪从零的眼角滑落。" },
            { speaker = "我", text = "……弦……", audioIds = { "P2-P3-ZERO-001" } },
            { narration = "零骤然睁开眼。" },
        },
    },
}

-- ----------------------------------------------------------------------------
-- P2 食物事件（V1.0 P2 本批新增：倒计时剩余 90 秒自动触发——弦返回并递给零营养罐头，第一阶段）
--   · opening：事件开场（逐页）；choices：现在吃 / 等会儿再吃 / 不吃
--   · eatNow / eatLater / refuse：三条分支台词（逐页）
-- audioIds 仅登记配音 ID，不参与播放；narration 不配音。
-- 后续批次：隐藏 60 秒衰竭倒计时 / 耳鸣 / 重新进食入口 / 归零昏迷。
-- ----------------------------------------------------------------------------
Story2.foodEvent = {
    title = "营养罐头",
    opening = {
        { narration = "弦抱着几盒药物返回，\n把手电筒放在桌上，\n从背包中取出一只密封营养罐头。" },
        { speaker = "弦", text = "你醒来这么久，还没吃东西", audioIds = { "P2-FOOD-XIAN-001" } },
        { narration = "她把罐头递给零。" },
        { speaker = "弦", text = "我刚找到一罐，你吃吗？", audioIds = { "P2-FOOD-XIAN-002" } },
    },
    choices = {
        { id = "EAT_NOW",   label = "现在吃" },
        { id = "EAT_LATER", label = "等会儿再吃" },
        { id = "REFUSE",    label = "不吃" },
    },
    eatNow = {
        { speaker = "我", text = "给我吧。", audioIds = { "P2-FOOD-ZERO-001" } },
        { narration = "弦打开罐头。\n递给零之前，她用手环扫描密封标识，\n两枚腕环短暂靠近。" },
        { speaker = "弦", text = "慢一点。", audioIds = { "P2-FOOD-XIAN-003" } },
        { speaker = "我", text = "你不吃？", audioIds = { "P2-FOOD-ZERO-002" } },
        { speaker = "弦", text = "我刚才吃过。", audioIds = { "P2-FOOD-XIAN-004" } },
    },
    eatLater = {
        { speaker = "我", text = "先放着吧。", audioIds = { "P2-FOOD-ZERO-003" } },
        { speaker = "弦", text = "你最好现在吃。", audioIds = { "P2-FOOD-XIAN-005" } },
        { speaker = "我", text = "我知道。", audioIds = { "P2-FOOD-ZERO-004" } },
        { speaker = "弦", text = "……随你。", audioIds = { "P2-FOOD-XIAN-006" } },
    },
    refuse = {
        { speaker = "我", text = "不用。", audioIds = { "P2-FOOD-ZERO-005" } },
        { speaker = "弦", text = "你现在需要补充能量。", audioIds = { "P2-FOOD-XIAN-007" } },
        { speaker = "我", text = "我不想吃你的东西。", audioIds = { "P2-FOOD-ZERO-006" } },
        { narration = "弦看着零，\n很久没有说话。" },
        { speaker = "弦", text = "好。", audioIds = { "P2-FOOD-XIAN-008" } },
        { narration = "她把罐头收回背包。" },
    },
    -- EAT_LATER 衰竭归零昏倒旁白（逐页显示）
    collapse = {
        steps = {
            { title = "意识消退", narration = "零的视线逐渐模糊。" },
            { title = "意识消退", narration = "周围的声音像隔着一层水。" },
            { title = "意识消退", narration = "她失去意识，倒了下去。" },
        },
    },
    collapseNextMorning = {
        steps = {
            { narration = "第二天早上，风雪逐渐停了。" },
            { narration = "弦收拾好随身物品，独自离开诊所。" },
            { narration = "零仍然没有醒来。" },
        },
    },
    -- REFUSE 拒食后的昏迷演出（暂定稿，待剧本复核）
    collapseRefuse = {
        steps = {
            { narration = "弦离开后，诊所里重新安静下来。" },
            { narration = "零扶住桌沿，眼前的光线开始晃动。" },
            { speaker = "我", text = "……", audioIds = { "P2-FOOD-ZERO-007" } },
            { narration = "她试图站稳，身体却失去了力气。" },
            { narration = "周围的声音逐渐远去。" },
            { narration = "零失去意识，倒了下去。" },
        },
    },
    -- 低信任（GetXianTrust() < 35）：弦离开
    refuseXianLeaves = {
        steps = {
            { narration = "不知过了多久，门外传来短暂的脚步声。" },
            { narration = "脚步没有停下，很快消失在风雪中。" },
            { narration = "诊所再次陷入寂静。" },
        },
    },
    -- 较高信任（GetXianTrust() >= 35）：弦返回救治
    refuseXianRescues = {
        steps = {
            { narration = "模糊的意识中，零听见门被推开的声音。" },
            { narration = "有人快步走到她身边。" },
            { speaker = "弦", text = "零。", audioIds = { "P2-FOOD-XIAN-010" } },
            { narration = "弦握住零的手腕，将两枚手环靠近。" },
            { narration = "医疗代理权限完成临时授权。" },
            { speaker = "弦", text = "别睡。", audioIds = { "P2-FOOD-XIAN-011" } },
            { narration = "零没有睁开眼。" },
        },
    },
}

-- ----------------------------------------------------------------------------
-- MINOR-C09 弦的旧储物柜「可选求证04」对白（本批新增：仅入口按钮与对白，
-- 暂不接入耐心消耗 / 已询问标记 / 重复询问限制 / 信息解锁状态）。
-- 演出备注（看了一眼已经褪色的标签 / 短暂停顿 / 没有否认）仅为制作参考，不写入 dialogue text。
-- audioIds 仅登记配音 ID，不参与播放（对齐 Story2 其它 audioIds 约定）。
-- ----------------------------------------------------------------------------
Story2.xianLockerAsk = {
    dialogue = {
        { speaker = "我", text = "这是你的柜子？", audioIds = { "P2-C09-ZERO-003" } },
        { speaker = "弦", text = "临时帮过一段时间。", audioIds = { "P2-C09-XIAN-001" } },
        { speaker = "我", text = "只是帮忙？", audioIds = { "P2-C09-ZERO-004" } },
        { speaker = "弦", text = "那会人手不够。", audioIds = { "P2-C09-XIAN-002" } },
        { speaker = "我", text = "所以你知道这里有哪些药？", audioIds = { "P2-C09-ZERO-005" } },
        { speaker = "弦", text = "知道一部分", audioIds = { "P2-C09-XIAN-003" } },
    },
}

-- ----------------------------------------------------------------------------
-- 休息区次要线索（V1.0 P2 本批新增 MINOR-C01 ~ MINOR-C09）
-- 全部归属诊所休息区（HALL 大厅 / HEARTH 取暖炉近景），不进入隧道 / 医务室 / 药柜窗口。
-- 数据格式与 tunnel.minorClues 对齐：单线索含 dialogue 数组（逐页播放，顺序见下方注释），
-- 以及 audioIds 表（仅用于登记音频 ID，不参与播放；环境描述 / 规章文字 / 清单文字不配音）。
-- 文本严格按制作剧本，逐字使用，不润色、不扩写、不补写。
-- 播放顺序（每页一条 ShowDialog）：
--   1. narration（环境描述，不配音）
--   2. screen（屏幕/规章/清单文字，如存在，不配音）
--   3. inner（第一条 我｜内心，配音）
--   4. inner（第二条 我｜内心，配音）
-- ----------------------------------------------------------------------------
Story2.clinic.restArea = {
    minorClues = {
        -- MINOR-C01：室内温度记录（HALL 大厅）
        temperature = {
            title = "室内温度记录",
            dialogue = {
                { narration = "墙上挂着温度变化表。\n过去六小时，室内温度每小时下降两度。" },
                { inner = "温度一直在降。" },
                { inner = "这里撑不到明天早上。" },
            },
            audioIds = { "P2-C01-ZERO-001", "P2-C01-ZERO-002" },
        },
        -- MINOR-C02：用过的营养罐头（HALL 大厅）
        cans = {
            title = "用过的营养罐头",
            dialogue = {
                { narration = "垃圾桶里有两个空罐头，生产日期相同。\n其中一个刚打开不久。" },
                { inner = "一个是很久以前留下的" },
                { inner = "另一个才打开不久" },
            },
            audioIds = { "P2-C02-ZERO-001", "P2-C02-ZERO-002" },
        },
        -- MINOR-C03：空置病床（HALL 大厅）
        bed = {
            title = "空置病床",
            dialogue = {
                { narration = "角落病床上的被褥被人整理得非常整齐。\n枕头下面压着一根长发。" },
                { inner = "有人在这里住过。" },
                { inner = "离开时甚至整理了床铺。" },
            },
            audioIds = { "P2-C03-ZERO-001", "P2-C03-ZERO-002" },
        },
        -- MINOR-C04：墙上的分诊制度（HALL 大厅）
        -- 注：screen 为规章文字，不配音（audioIds 仅登记两条 inner 的配音）。
        triageRules = {
            title = "墙上的分诊制度",
            dialogue = {
                -- 本批：原 narration + screen 两步合并为单一屏幕文字 step，一次显示完（仅点一次【继续】）
                { screen = "墙面张贴着资源分配规则：资源不足时，优先保障必要技术人员。\n无岗位人员仅接受基础处置。" },
                { inner = "连治疗也要按照贡献分配。" },
                { inner = "没有岗位的人只能得到基础处理。" },
            },
            audioIds = { "P2-C04-ZERO-001", "P2-C04-ZERO-002" },
        },
        -- MINOR-C05：损坏的担架（HALL 大厅）
        stretcher = {
            title = "损坏的担架",
            dialogue = {
                { narration = "墙边靠着一副损坏的担架。\n一侧轮子已经折断。\n布面残留着大片清洗后仍未褪去的暗色痕迹。" },
                { inner = "血迹洗过很多次" },
                { inner = "这里以前接收过不少伤员" },
            },
            audioIds = { "P2-C05-ZERO-001", "P2-C05-ZERO-002" },
        },
        -- MINOR-C06：燃料不足的取暖炉（复用现有【取暖炉】入口 id="hearth"，不新建按钮）
        -- 调查内容（dialogue）先于炉火演出播放；演出结束返回后进入 HEARTH 近景（背景 P2_BG03）。
        heater = {
            title = "取暖炉",
            dialogue = {
                { narration = "诊所里放着一只便携取暖炉。\n燃料已经接近底部。\n旁边堆着几只拆开的旧纸箱。" },
                { inner = "燃料剩的不多" },
                { inner = "省着用，应该还能撑一晚" },
            },
            audioIds = { "P2-C06-ZERO-001", "P2-C06-ZERO-002" },
        },
        -- MINOR-C07：药品缺失清单（HEARTH 近景）
        -- 注：screen 为库存清单文字，不配音。
        medicineList = {
            title = "药品缺失清单",
            dialogue = {
                { narration = "药物旁夹着一张库存清单。\n几项药品数量被人重新标记过。" },
                { screen = "清醒维持剂缺失两支。\n镇静剂剩余一支。\n休眠后营养罐头剩余三份。" },
                { inner = "少了两支清醒维持剂" },
                { inner = "有人比我们更早来取过药" },
            },
            audioIds = { "P2-C07-ZERO-001", "P2-C07-ZERO-002" },
        },
        -- MINOR-C08：窗外的手印（HEARTH 近景）
        windowHandprint = {
            title = "窗外的手印",
            dialogue = {
                { narration = "结霜的窗户外侧留着一个模糊手印，位置很低。\n五指张开的范围也比成年人的手掌更小" },
                { inner = "像是小孩留下的" },
                { inner = "当时站在窗外？" },
            },
            audioIds = { "P2-C08-ZERO-001", "P2-C08-ZERO-002" },
        },
        -- MINOR-C09：弦的旧储物柜（HEARTH 近景）
        xianLocker = {
            title = "弦的旧储物柜",
            dialogue = {
                { narration = "柜门上贴着已经褪色的姓名标签。\n只能看清一个“弦”字，柜内为空。" },
                { inner = "这是弦的柜子" },
                { inner = "她不只是送我来过" },
            },
            audioIds = { "P2-C09-ZERO-001", "P2-C09-ZERO-002" },
        },
    },
}

-- ----------------------------------------------------------------------------
-- 最终选择（纯数据，逻辑在 p2controller 的 EnterP2FinalChoice / OnP2FinalChoiceSelected）
-- V1.0-07N-H1：重构为剧本 §8「最终选择」结局树结构。
--   · 顶层 option 保留 id / text（兼容未修改的 controller 按钮生成与 OnP2FinalChoiceSelected 的 id 查找）。
--   · 顶层 resultText 用于分支叶尚未匹配时的安全回退。
--   · 每个 option 新增 sub 子分支表；子项含 leafId / endingText / isDeath + 数据化 condition（仅描述，不写 Lua 判断、不读 p2 状态）。
--   · condition 字段名对应已就绪状态：xianConscious / hasMap / hasBracelet / hasSoberAgent / fireLit / medicalProxy。
Story2.finalChoice = {
    title = "最后的选择",
    options = {
        -- 选择A：现在离开
        {
            id = "leave_now",
            text = "现在离开。",
            resultText = "你决定立即离开诊所。",
            sub = {
                {
                    leafId = "leave_together",
                    condition = { xianConscious = "SOBER" },
                    endingText =
                        "弦带领零离开诊所，进入P3正常路线。\n" ..
                        "零并不知道自己的腕环授权核心已经被替换。",
                    isDeath = false,
                },
                {
                    leafId = "leave_alone_full",
                    condition = { xianConscious = "SEDATED", hasMap = true, hasBracelet = true },
                    endingText = "零成功穿过外部通道，进入P3独自逃亡路线。",
                    isDeath = false,
                },
                {
                    leafId = "leave_alone_map",
                    condition = { xianConscious = "SEDATED", hasMap = true, hasBracelet = false },
                    endingText = "路是对的。门没有打开。",
                    isDeath = true,
                },
                {
                    leafId = "leave_alone_bracelet",
                    condition = { xianConscious = "SEDATED", hasMap = false, hasBracelet = true },
                    endingText = "身份被允许通过。没有人告诉我该往哪里走。",
                    isDeath = true,
                },
                {
                    leafId = "leave_alone_none",
                    condition = { xianConscious = "SEDATED", hasMap = false, hasBracelet = false },
                    endingText = "我以为出口就在前面。",
                    isDeath = true,
                },
            },
        },
        -- 选择B：留到清晨
        {
            id = "stay_dawn",
            text = "留到清晨。",
            resultText = "你决定留在诊所等待清晨。",
            sub = {
                {
                    leafId = "stay_sober_proxy",
                    condition = { xianConscious = "SOBER", medicalProxy = true },
                    endingText =
                        "两人在诊所短暂休息。零睡着后，弦完成授权核心替换。\n" ..
                        "清晨，弦叫醒零，两人进入P3正常路线。",
                    isDeath = false,
                },
                {
                    leafId = "stay_sedated_fire",
                    condition = { xianConscious = "SEDATED", fireLit = true, hasMap = true, hasBracelet = true },
                    endingText = "零在弦醒来前离开诊所，同时持有地图与身份手环，走入清晨的雪原。",
                    isDeath = false,
                },
                {
                    leafId = "stay_sedated_nofire",
                    condition = { xianConscious = "SEDATED", fireLit = false },
                    endingText = "火没有升起来。天也没有亮。",
                    isDeath = true,
                },
            },
        },
    },
}

-- ----------------------------------------------------------------------------
-- 资源路径（纯数据，供 P2 界面模块读取）
-- 仅登记已经入库的图片，避免无效路径进入运行时。
-- ----------------------------------------------------------------------------
Story2.resources = {
    image = {
        tunnel_bg = "image/P2/P2_BG01_Tunnel_v01.png",  -- 隧道背景（P2-BG01 正式资源，磁盘位于 assets/image/P2/）
        clinic_bg = "image/P2/P2_BG02_ClinicHall_v01.png",  -- 诊所背景
        comic     = "image/P2/P2_C01_Comic_v01.png",    -- 隧道线索图·漫画（P2-C01 正式资源，磁盘位于 assets/image/P2/）
        medicine_box = "image/P2/P2_C08_MedicineBox_v01.png",  -- 药柜内药物资料二级配图·药盒（P2-C08 正式资源，磁盘位于 assets/image/P2/）
        -- V1.0-07G 五张美术资源（磁盘均位于 assets/image/P2/）
        locker            = "image/P2/P2_C02_Locker_v02.png",           -- P2-C02 储物柜（暂无对应调查点，仅注册）
        backpack_contents = "image/P2/P2_C03_BackpackContents_v01.png",  -- P2-C03 背包内容（暂无对应调查点，仅注册）
        computer          = "image/P2/P2_C06_Computer_v01.png",         -- P2-C06 电脑（对应 clinic clue：医疗终端 terminal）
        medicine_cabinet  = "image/P2/P2_C07_MedicineCabinet_v01.png",   -- P2-C07 药柜（对应 clinic clue：药柜 cabinet）
        rest_area         = "image/P2/P2_BG03_RestArea_v01.png",         -- P2-BG03 炉火休息区背景（V1.0-07I-B 新增场景）
        infirmary         = "image/P2/P2_BG04_Infirmary_v01.png",       -- P2-BG04 医务室独立背景（V1.0-P2-SPACE 拆分）
        memory            = "image/P2/P2_C09_Memory_v01.png",           -- P2-C09 Memory图（V1.0-07I-B 炉火场景演出图，已挂接）
    },
}

-- ----------------------------------------------------------------------------
-- 章节结算（纯数据，逻辑在 p2controller 的 ShowP2Ending）
-- V1.0-07N-H3：扩展为 branches 表，按 p2.result.leafId 分流结局文案。
--   · 保留原 title / summary 作为 leafId 缺失时的 fallback。
--   · 每个分支含 title / summary / isDeath，leafId 对应 finalChoice sub 叶。
Story2.ending = {
    title = "雪线诊所 · 结算",
    summary =
        "雪渐渐停了。\n" ..
        "诊所的灯还亮着，备用电源撑过了一夜。\n" ..
        "你带着今晚看到的一切，走出了那扇门——\n" ..
        "有些真相你已经握在手里，有些，还要等下一场雪来揭。\n" ..
        "（章节结算，后续步骤将接入第二部内容。）",
    branches = {
        leave_together = {
            title = "雪线诊所 · 结算",
            summary =
                "弦带领你离开诊所，走入清晨前的雪原。\n" ..
                "你并不知道，自己的腕环授权核心已经在睡梦中被人替换。\n" ..
                "（与弦同行，P3 正常路线。）",
            isDeath = false,
        },
        leave_alone_full = {
            title = "雪线诊所 · 结算",
            summary =
                "你同时拿走了地图与弦的身份手环。\n" ..
                "外部通道验证通过，你独自走进风雪，消失在路口。\n" ..
                "（独自逃亡，P3 独自路线。）",
            isDeath = false,
        },
        leave_alone_map = {
            title = "雪线诊所 · 结算",
            summary =
                "路是对的。门没有打开。\n" ..
                "低温在等待中耗尽你的体力，雪原吞没了最后一点体温。\n" ..
                "（死亡结局。）",
            isDeath = true,
        },
        leave_alone_bracelet = {
            title = "雪线诊所 · 结算",
            summary =
                "身份被允许通过。没有人告诉我该往哪里走。\n" ..
                "你在茫茫雪原中迷失，直到意识远去。\n" ..
                "（死亡结局。）",
            isDeath = true,
        },
        leave_alone_none = {
            title = "雪线诊所 · 结算",
            summary =
                "我以为出口就在前面。\n" ..
                "离开诊所后，你迅速迷失在暴风雪里。\n" ..
                "（死亡结局。）",
            isDeath = true,
        },
        stay_sober_proxy = {
            title = "雪线诊所 · 结算",
            summary =
                "两人在诊所短暂休息。你睡着后，弦完成了授权核心的替换。\n" ..
                "清晨，弦叫醒你，两人并肩走向 P3。\n" ..
                "（与弦同行，P3 正常路线。）",
            isDeath = false,
        },
        stay_sedated_fire = {
            title = "雪线诊所 · 结算",
            summary =
                "炉火撑过了整夜。你在弦醒来前离开，同时握有地图与身份手环。\n" ..
                "清晨的雪原在门外等你。\n" ..
                "（独自逃亡，P3 独自路线。）",
            isDeath = false,
        },
        stay_sedated_nofire = {
            title = "雪线诊所 · 结算",
            summary =
                "火没有升起来。天也没有亮。\n" ..
                "诊所温度持续下降，你在睡眠中失去意识。\n" ..
                "（死亡结局。）",
            isDeath = true,
        },
    },
}

return Story2
