# Last Friend 项目结构

## 运行时代码

- `scripts/main.lua`：Maker 唯一入口，只转发 `Start` 和 `Stop` 生命周期。
- `scripts/gamecontroller.lua`：全局游戏流程、P1 编排以及 P2/P3 的入口协调。
- `scripts/titlescreen.lua`：标题页与开发调试入口 UI。
- `scripts/relationshipstate.lua`：弦的信任度、等级与关系状态。
- `scripts/runstate.lua` / `scripts/saveadapter.lua`：跨章节运行态与存档读写。
- `scripts/story.lua` / `scripts/story2.lua` / `scripts/story3.lua`：各章节的剧情、分支和资源数据。

## 章节模块

- `p1*`：P1 的场景、调查、询问、线索档案与剧情流程。
- `p2*`：P2 的会话态、场景、诊所线索、电脑、药柜与结局流程。
- `p3*`：P3 的会话态、场景、证据卡与结局流程。

## 通用功能

- `bgmplayer.lua` / `voiceplayer.lua` / `voicecatalog.lua`：背景音乐、配音播放与配音索引。
- `scanfx.lua` / `scanstatus.lua`：扫描视觉效果与扫描状态。
- `investigate.lua`：通用调查数据与交互支持。
- `cluearchiveui.lua` / `terminalrecordsui.lua`：可复用的线索档案和终端记录 UI。

## 资源与工程数据

- `assets/`：游戏运行时图片、音频、视频和精灵资源。
- `.project/project.json`：Maker 项目入口、版本与 TapTap 发布元数据。
- `.project/game_material/`：当前本地存在的发布封面。图标、截图和宣传图使用项目中已保存的远程 URL。
- `urhox-libs/`：Maker/UrhoX UI 与引擎支持库。

## 验证与历史材料

- `screenshots/`：当前可复用的功能验证截图。
- `logs/`：静态检查与运行日志。
- `archive/`：不参与运行的历史脚本、存档快照与 QA 过程图。

新增运行时功能应放入对应章节模块或通用模块，不要将大段业务逻辑放回 `main.lua`。QA 中间产物应存入 `archive/qa/`，避免再次散落到项目根目录。
