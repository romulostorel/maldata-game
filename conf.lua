-- LÖVE2D configuration: window, identity, version pinning.
-- Edit here to change window size or LÖVE version expected.

function love.conf(t)
    t.identity = "inverted-roguelike"
    t.version = "11.5"
    t.console = false

    t.window.title = "Inverted Roguelike v1"
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = false
    t.window.vsync = 1

    -- Disable unused modules to keep startup lean.
    t.modules.audio = false
    t.modules.sound = false
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.video = false
    t.modules.touch = false
end
