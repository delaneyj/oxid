const gbe = @import("gbe");
const GameSession = @import("../game.zig").GameSession;
const c = @import("../components.zig");

pub fn run(gs: *GameSession) void {
    var it = gs.ecs.iter(struct {
        player: *c.Player,
        creature: *c.Creature,
        inbox: gbe.Inbox(16, c.EventGameInput, null),
    });
    while (it.next()) |self| {
        for (self.inbox.all()) |event| {
            if (event.player_number != self.player.player_number) {
                continue;
            }
            switch (event.command) {
                .Up => {
                    self.player.in_up = event.down;
                },
                .Down => {
                    self.player.in_down = event.down;
                },
                .Left => {
                    self.player.in_left = event.down;
                },
                .Right => {
                    self.player.in_right = event.down;
                },
                .Shoot => {
                    self.player.in_shoot = event.down;
                },
                .ToggleGodMode => {
                    if (event.down) {
                        self.creature.god_mode = !self.creature.god_mode;
                    }
                },
                else => {},
            }
        }
    }
}
