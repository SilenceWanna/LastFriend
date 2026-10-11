-- ============================================================================
-- scripts/main.lua
-- Maker 运行时入口：只负责转发生命周期，具体游戏流程位于 gamecontroller.lua。
-- ============================================================================

local GameController = require("gamecontroller")

function Start()
    GameController.Start()
end

function Stop()
    GameController.Stop()
end
