const gbe = @import("gbe");
const GameSession = @import("../game.zig").GameSession;
const constants = @import("../constants.zig");
const c = @import("../components.zig");
const p = @import("../prototypes.zig");
const audio = @import("../audio.zig");

pub fn run(gs: *GameSession) void {
    var it = gs.ecs.iter(struct {
        id: gbe.EntityId,
        creature: *c.Creature,
        transform: *const c.Transform,
        monster: ?*const c.Monster,
        player: ?*c.Player,
        inbox: gbe.Inbox(8, c.EventTakeDamage, "self_id"),
    });
    while (it.next()) |self| {
        if (self.creature.invulnerability_timer > 0) {
            continue;
        }
        if (self.creature.god_mode) {
            continue;
        }
        if (self.creature.hit_points <= 0) {
            continue;
        }

        const total_damage = blk: {
            var n: u32 = 0;
            for (self.inbox.all()) |event| {
                n += event.amount;
            }
            break :blk n;
        };

        if (total_damage <= 0) {
            continue;
        }

        if (self.creature.hit_points > total_damage) {
            // hurt but not killed
            p.playSample(gs, .monster_impact);
            self.creature.hit_points -= total_damage;
            self.creature.flinch_timer = constants.duration60(4);
            continue;
        }

        // killed
        self.creature.hit_points = 0;

        if (self.player) |self_player| {
            // player died
            p.playSample(gs, .player_scream);
            p.playSample(gs, .player_death);

            self_player.dying_timer = constants.player_death_anim_time;

            _ = p.EventPlayerDied.spawn(gs, .{
                .player_controller_id = self_player.player_controller_id,
            }) catch undefined;

            if (self_player.last_pickup) |pickup_type| {
                _ = p.Pickup.spawn(gs, .{
                    .pos = self.transform.pos,
                    .pickup_type = pickup_type,
                }) catch undefined;
            }

            continue;
        }

        // something other than a player died
        if (self.monster) |self_monster| {
            _ = p.EventMonsterDied.spawn(gs, .{}) catch undefined;

            // in the case that multiple players shot this monster at the same
            // time, pick one of them at random to award the kill to
            if (self.inbox.one().inflictor_player_controller_id)
                    |player_controller_id| {
                _ = p.EventAwardPoints.spawn(gs, .{
                    .player_controller_id = player_controller_id,
                    .points = self_monster.kill_points,
                }) catch undefined;
            }

            if (self_monster.has_coin) {
                _ = p.Pickup.spawn(gs, .{
                    .pos = self.transform.pos,
                    .pickup_type = .coin,
                }) catch undefined;
            }
        }

        p.playSample(gs, .monster_impact);
        p.playSynth(gs, "explosion", audio.ExplosionVoice, audio.ExplosionVoice.NoteParams {
            .unused = false,
        });

        _ = p.Animation.spawn(gs, .{
            .pos = self.transform.pos,
            .simple_anim = .explosion,
            .z_index = constants.z_index_explosion,
        }) catch undefined;

        gs.ecs.markForRemoval(self.id);
    }
}
