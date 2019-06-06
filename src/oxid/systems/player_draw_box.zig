const std = @import("std");
const gbe = @import("gbe");
const draw = @import("../../common/draw.zig");
const GameSession = @import("../game.zig").GameSession;
const C = @import("../components.zig");
const Prototypes = @import("../prototypes.zig");

const SystemData = struct {
    player: *const C.Player,
};

pub const run = gbe.buildSystem(GameSession, SystemData, think);

fn think(gs: *GameSession, self: SystemData) bool {
    if (self.player.line_of_fire) |box| {
        _ = Prototypes.EventDrawBox.spawn(gs, C.EventDrawBox {
            .box = box,
            .color = draw.Color {
                .r = 0,
                .g = 0,
                .b = 0,
                .a = 255,
            },
        }) catch undefined;
    }
    return true;
}