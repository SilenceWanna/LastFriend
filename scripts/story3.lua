local Story3 = {}

Story3.opening = {
    {
        narration = "……",
        audioIds = { "P3-S01-ZERO-001" },
    },
    {
        narration = "这里……\n我来过。",
        audioIds = { "P3-S01-ZERO-002" },
    },
    {
        narration = "为什么……\n我想不起来。",
        audioIds = { "P3-S01-ZERO-003" },
    },
}

Story3.minorClues = {
    R01 = {
        title = "损坏休眠舱",
        dialogue = {
            { text = "这里以前有人。", audioIds = { "P3-R01-ZERO-001" } },
        },
    },
    R02 = {
        title = "修改后的编号",
        dialogue = {
            { text = "有人改过这里。", audioIds = { "P3-R02-ZERO-001" } },
        },
    },
    R03 = {
        title = "空药盒",
        dialogue = {
            { text = "这种东西……我见过。", audioIds = { "P3-R03-ZERO-001" } },
        },
    },
    R04 = {
        title = "旧维修记录",
        dialogue = {
            { text = "为什么这里一直有人维护？", audioIds = { "P3-R04-ZERO-001" } },
        },
    },
    R05 = {
        title = "废弃身份卡",
        dialogue = {
            { text = "又是损坏的信息。", audioIds = { "P3-R05-ZERO-001" } },
        },
    },
    R06 = {
        title = "墙面刻痕",
        dialogue = {
            { text = "这是给谁留下的？", audioIds = { "P3-R06-ZERO-001" } },
        },
    },
    R07 = {
        title = "破损照片碎片",
        description = "抽屉底部压着一张旧合照。照片从中间被撕开，只剩零站在空间站入口前的一侧；缺口旁还能看见另一人的半截衣袖。相纸背面留着一行已经褪色的手写字：“零、弦／入选纪念”。日期部分随另一半照片一起缺失。",
        dialogue = {
            { text = "我是不是忘记了什么？", audioIds = { "P3-R07-ZERO-001" } },
        },
    },
    R08 = {
        title = "备用通讯线路",
        description = "终端外壳仍保持拆开状态，原本被剪断的线路后来被人临时接回。零沿着接头拆开后盖，在夹层中发现两张被反复折叠的纸质记录；纸边沾有机油和已经干涸的水渍。",
        dialogue = {
            { text = "有人尝试恢复通讯。", audioIds = { "P3-R08-ZERO-001" } },
        },
    },
}

Story3.keys = {
    KEY01 = {
        title = "残缺合照",
        description = "抽屉底部压着一张旧合照。照片从中间被撕开，只剩零站在空间站入口前的一侧；缺口旁还能看见另一人的半截衣袖。相纸背面留着一行已经褪色的手写字：“零、弦／入选纪念”。日期部分随另一半照片一起缺失。",
        dialogue = {
            {
                text = "这是我。",
                audioIds = { "P3-K01-ZERO-001" },
            },
            {
                text = "另一边的人……\n是谁？",
                audioIds = { "P3-K01-ZERO-002" },
            },
        },
        evidenceCard = "共同经历",
    },
    KEY02 = {
        title = "黑色身份手环",
        description = "零重新检查随身携带的黑色身份手环。手环表面留有细小磨损，蓝色认证光仍会短暂亮起。",
        detectionCard = {
            identity = "损坏",
            permission = "不可读取",
            number = "X",
        },
        dialogue = {
            {
                text = "这个东西……",
                audioIds = { "P3-K02-ZERO-001" },
            },
            {
                text = "X……\n为什么会在我这里？",
                audioIds = { "P3-K02-ZERO-002" },
            },
        },
        evidenceCard = "身份遗留",
    },
    KEY03 = {
        title = "通讯终端记录",
        description = "终端外壳仍保持拆开状态，原本被剪断的线路后来被人临时接回。零沿着接头拆开后盖，在夹层中发现两张被反复折叠的纸质记录；纸边沾有机油和已经干涸的水渍。",
        records = {
            restore = {
                title = "恢复记录",
                fields = {
                    { label = "对象", value = "零" },
                    { label = "恢复状态", value = "异常" },
                    { label = "当前记忆状态", value = "不稳定" },
                    { label = "建议", value = "避免强制刺激" },
                },
            },
            sleep = {
                title = "休眠执行记录",
                fields = {
                    { label = "对象", value = "零" },
                    { label = "执行原因", value = "权限调整" },
                    { label = "执行人", value = "弦" },
                },
            },
        },
        dialogue = {
            {
                text = "恢复……\n谁在恢复我的记忆？",
                audioIds = { "P3-K03-ZERO-001" },
            },
            {
                text = "……\n弦。",
                audioIds = { "P3-K03-ZERO-002" },
            },
            {
                text = "为什么？",
                audioIds = { "P3-K03-ZERO-003" },
            },
        },
        evidenceCard = "休眠执行",
    },
}

Story3.ending = {
    dialogue = {
        {
            text = "如果你想害我……\n为什么救我？",
            audioIds = { "P3-END-ZERO-001" },
        },
        {
            text = "如果你想救我……\n为什么瞒着我？",
            audioIds = { "P3-END-ZERO-002" },
        },
    },
    blackScreen = "真相并没有消失。\n只是没有人记得完整的答案。",
}

return Story3
