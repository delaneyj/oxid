const Math = @import("../math.zig");
const Gbe = @import("../gbe.zig");
const GbeSystem = @import("../gbe_system.zig");
const Constants = @import("constants.zig");
const GRIDSIZE_SUBPIXELS = @import("level.zig").GRIDSIZE_SUBPIXELS;
const GameSession = @import("game.zig").GameSession;
const decrementTimer = @import("frame.zig").decrementTimer;
const physInWall = @import("physics.zig").physInWall;
const C = @import("components.zig");
const Prototypes = @import("prototypes.zig");

// TODO - system should be able to read all of these, but only write to them
// one (player)...
// right now, other than player fields, it's writing:
// - self.phys.speed
// - self.phys.push_dir
// - self.phys.facing
// that's it. the react system is also writing self.creature.move_speed.
// need an Event to set phys fields.

pub const PlayerMovementSystem = struct{
  const SystemData = struct{
    id: Gbe.EntityId,
    creature: *C.Creature,
    phys: *C.PhysObject,
    player: *C.Player,
    transform: *C.Transform,
  };

  pub const run = GbeSystem.build(GameSession, SystemData, think);

  fn think(gs: *GameSession, self: SystemData) bool {
    if (decrementTimer(&self.player.dying_timer)) {
      _ = Prototypes.PlayerCorpse.spawn(gs, Prototypes.PlayerCorpse.Params{
        .pos = self.transform.pos,
      });
      return false;
    } else if (self.player.dying_timer > 0) {
      self.phys.speed = 0;
      self.phys.push_dir = null;
    } else {
      playerMove(gs, self);
      playerShoot(gs, self);
    }
    return true;
  }

  fn playerShoot(gs: *GameSession, self: SystemData) void {
    if (gs.in_shoot) {
      if (self.player.trigger_released) {
        // the player can only have a certain amount of bullets in play at a
        // time.
        // look for a bullet slot that is either null (never been used) or a
        // non-existent entity (old bullet is gone)
        if (for (self.player.bullets) |*slot| {
          if (slot.*) |bullet_id| {
            if (gs.gbe.find(bullet_id, C.Bullet) == null) {
              break slot;
            }
          } else {
            break slot;
          }
        } else null) |slot| {
          // spawn the bullet one quarter of a grid cell in front of the player
          const pos = self.transform.pos;
          const dir_vec = Math.Direction.normal(self.phys.facing);
          const ofs = Math.Vec2.scale(dir_vec, GRIDSIZE_SUBPIXELS / 4);
          const bullet_pos = Math.Vec2.add(pos, ofs);
          if (Prototypes.Bullet.spawn(gs, Prototypes.Bullet.Params{
            .inflictor_player_controller_id = self.player.player_controller_id,
            .owner_id = self.id,
            .pos = bullet_pos,
            .facing = self.phys.facing,
            .bullet_type = Prototypes.Bullet.BulletType.PlayerBullet,
            .cluster_size = switch (self.player.attack_level) {
              C.Player.AttackLevel.One => u32(1),
              C.Player.AttackLevel.Two => u32(2),
              C.Player.AttackLevel.Three => u32(3),
            },
          })) |bullet_entity_id| {
            slot.* = bullet_entity_id;
          } else |err| {}
          self.player.trigger_released = false;
        }
      }
    } else {
      self.player.trigger_released = true;
    }
  }

  fn playerMove(gs: *GameSession, self: SystemData) void {
    var xmove: i32 = 0;
    var ymove: i32 = 0;
    if (gs.in_right) { xmove += 1; }
    if (gs.in_left) { xmove -= 1; }
    if (gs.in_down) { ymove += 1; }
    if (gs.in_up) { ymove -= 1; }

    self.phys.speed = 0;
    self.phys.push_dir = null;

    const pos = self.transform.pos;

    if (xmove != 0) {
      const dir = if (xmove < 0) Math.Direction.W else Math.Direction.E;

      if (ymove == 0) {
        // only moving along x axis. try to slip around corners
        tryPush(pos, dir, self.creature.move_speed, self.phys);
      } else {
        // trying to move diagonally.
        const secondary_dir = if (ymove < 0) Math.Direction.N else Math.Direction.S;

        // prefer to move on the x axis (arbitrary, but i had to pick something)
        if (!physInWall(self.phys, Math.Vec2.add(pos, Math.Direction.normal(dir)))) {
          self.phys.facing = dir;
          self.phys.speed = self.creature.move_speed;
        } else if (!physInWall(self.phys, Math.Vec2.add(pos, Math.Direction.normal(secondary_dir)))) {
          self.phys.facing = secondary_dir;
          self.phys.speed = self.creature.move_speed;
        }
      }
    } else if (ymove != 0) {
      // only moving along y axis. try to slip around corners
      const dir = if (ymove < 0) Math.Direction.N else Math.Direction.S;

      tryPush(pos, dir, self.creature.move_speed, self.phys);
    }
  }

  fn tryPush(pos: Math.Vec2, dir: Math.Direction, speed: i32, self_phys: *C.PhysObject) void {
    const pos1 = Math.Vec2.add(pos, Math.Direction.normal(dir));

    if (!physInWall(self_phys, pos1)) {
      // no need to push, this direction works
      self_phys.facing = dir;
      self_phys.speed = speed;
      return;
    }

    var slip_dir: ?Math.Direction = null;

    var i: i32 = 1;
    while (i < Constants.PlayerSlipThreshold) : (i += 1) {
      if (dir == Math.Direction.W or dir == Math.Direction.E) {
        if (!physInWall(self_phys, Math.Vec2.init(pos1.x, pos1.y - i))) {
          slip_dir = Math.Direction.N;
          break;
        }
        if (!physInWall(self_phys, Math.Vec2.init(pos1.x, pos1.y + i))) {
          slip_dir = Math.Direction.S;
          break;
        }
      }
      if (dir == Math.Direction.N or dir == Math.Direction.S) {
        if (!physInWall(self_phys, Math.Vec2.init(pos1.x - i, pos1.y))) {
          slip_dir = Math.Direction.W;
          break;
        }
        if (!physInWall(self_phys, Math.Vec2.init(pos1.x + i, pos1.y))) {
          slip_dir = Math.Direction.E;
          break;
        }
      }
    }

    if (slip_dir) |slipdir| {
      self_phys.facing = slipdir;
      self_phys.speed = speed;
      self_phys.push_dir = dir;
    }
  }
};

pub const PlayerReactionSystem = struct{
  pub const SystemData = struct{
    id: Gbe.EntityId,
    creature: *C.Creature,
    phys: *C.PhysObject,
    player: *C.Player,
    transform: *C.Transform,
  };

  pub const run = GbeSystem.build(GameSession, SystemData, playerReact);

  fn playerReact(gs: *GameSession, self: SystemData) bool {
    var it = gs.gbe.eventIter(C.EventConferBonus, "recipient_id", self.id); while (it.next()) |event| {
      switch (event.pickup_type) {
        C.Pickup.Type.PowerUp => {
          self.player.attack_level = switch (self.player.attack_level) {
            C.Player.AttackLevel.One => C.Player.AttackLevel.Two,
            else => C.Player.AttackLevel.Three,
          };
          self.player.last_pickup = C.Pickup.Type.PowerUp;
        },
        C.Pickup.Type.SpeedUp => {
          self.player.speed_level = switch (self.player.speed_level) {
            C.Player.SpeedLevel.One => C.Player.SpeedLevel.Two,
            else => C.Player.SpeedLevel.Three,
          };
          self.creature.move_speed = switch (self.player.speed_level) {
            C.Player.SpeedLevel.One => Constants.PlayerMoveSpeed1,
            C.Player.SpeedLevel.Two => Constants.PlayerMoveSpeed2,
            C.Player.SpeedLevel.Three => Constants.PlayerMoveSpeed3,
          };
          self.player.last_pickup = C.Pickup.Type.SpeedUp;
        },
        C.Pickup.Type.LifeUp => {
          _ = Prototypes.EventAwardLife.spawn(gs,  C.EventAwardLife{
            .player_controller_id = self.player.player_controller_id,
          });
        },
        C.Pickup.Type.Coin => {},
      }
    }
    return true;
  }
};