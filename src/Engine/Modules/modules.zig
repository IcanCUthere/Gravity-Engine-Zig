const Core = @import("CoreModule").Core;
const Graphics = @import("GraphicsModule").Graphics;
const Editor = @import("EditorModule").Editor;
const Game = @import("GameModule").Game;

const builtin = @import("builtin");

const releaseOrder = [_]type{
    Core,
    Graphics,
    Game,
};

const editOrder = [_]type{
    Core,
    Graphics,
    Editor,
    Game,
};

pub const loadOrder = if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) editOrder else releaseOrder;
