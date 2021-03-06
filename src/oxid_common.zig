const std = @import("std");
const gbe = @import("gbe");
const Hunk = @import("zig-hunk").Hunk;
const HunkSide = @import("zig-hunk").HunkSide;
const warn = @import("warn.zig").warn;
const platform_draw = @import("platform/opengl/draw.zig");
const draw = @import("common/draw.zig");
const Font = @import("common/font.zig").Font;
const loadFont = @import("common/font.zig").loadFont;
const loadTileset = @import("oxid/graphics.zig").loadTileset;
const InputSource = @import("common/key.zig").InputSource;
const areInputSourcesEqual = @import("common/key.zig").areInputSourcesEqual;
const perf = @import("oxid/perf.zig");
const config = @import("oxid/config.zig");
const constants = @import("oxid/constants.zig");
const ComponentLists = @import("oxid/game.zig").ComponentLists;
const GameSession = @import("oxid/game.zig").GameSession;
const gameInit = @import("oxid/frame.zig").gameInit;
const input = @import("oxid/input.zig");
const levels = @import("oxid/levels.zig");
const p = @import("oxid/prototypes.zig");
const c = @import("oxid/components.zig");
const menus = @import("oxid/menus.zig");
const MenuInputParams = @import("oxid/menu_input.zig").MenuInputParams;
const menuInput = @import("oxid/menu_input.zig").menuInput;
const audio = @import("oxid/audio.zig");
const MenuDrawParams = @import("oxid/draw_menu.zig").MenuDrawParams;
const drawMenu = @import("oxid/draw_menu.zig").drawMenu;
const drawGame = @import("oxid/draw.zig").drawGame;
const setFriendlyFire = @import("oxid/functions/set_friendly_fire.zig")
                            .setFriendlyFire;

// this many pixels is added to the top of the window for font stuff
pub const hud_height = 16;

// size of the virtual screen. the actual window size will be an integer
// multiple of this
pub const virtual_window_width = levels.width * levels.pixels_per_tile; // 320
pub const virtual_window_height = levels.height * levels.pixels_per_tile
                                        + hud_height; // 240

pub const MainState = struct {
    hunk: *Hunk,
    cfg: config.Config,
    draw_state: platform_draw.DrawState,
    audio_module: audio.MainModule,
    static: GameStatic,
    session: GameSession,
    game_over: bool,
    new_high_score: bool,
    high_scores: [constants.num_high_scores]u32,
    menu_anim_time: u32,
    menu_stack: menus.MenuStack,
    fullscreen: bool,
    canvas_scale: u31,
    max_canvas_scale: u31,
    friendly_fire: bool,
    sound_enabled: bool,
};

pub const GameStatic = struct {
    tileset: draw.Tileset,
    palette: [48]u8,
    font: Font,
};

pub const InitParams = struct {
    hunk: *Hunk,
    random_seed: u32,
    audio_buffer_size: usize,
    fullscreen: bool,
    canvas_scale: u31,
    max_canvas_scale: u31,
    sound_enabled: bool,
};

pub fn init(self: *MainState, comptime ns: type, params: InitParams) bool {
    self.hunk = params.hunk;

    self.high_scores = ns.loadHighScores(&self.hunk.low());

    loadFont(&self.hunk.low(), &self.static.font) catch |err| {
        warn("Failed to load font: {}\n", .{err});
        return false;
    };

    loadTileset(
        &self.hunk.low(),
        &self.static.tileset,
        self.static.palette[0..],
    ) catch |err| {
        warn("Failed to load tileset: {}\n", .{err});
        return false;
    };

    self.audio_module = audio.MainModule.init(
        self.hunk,
        params.audio_buffer_size,
    ) catch |err| {
        warn("Failed to load audio module: {}\n", .{err});
        return false;
    };

    self.cfg = blk: {
        // if config couldn't load, warn and fall back to default config
        const cfg = ns.loadConfig(&self.hunk.low()) catch |err| {
            warn("Failed to load config: {}\n", .{err});
            break :blk config.getDefault();
        };
        break :blk cfg;
    };

    self.session.init(params.random_seed);
    gameInit(&self.session) catch |err| {
        warn("Failed to initialize game: {}\n", .{err});
        return false;
    };

    perf.init();

    platform_draw.init(&self.draw_state, .{
        .hunk = self.hunk,
        .virtual_window_width = virtual_window_width,
        .virtual_window_height = virtual_window_height,
    }) catch |err| {
        warn("platform_draw.init failed: {}\n", .{err});
        return false;
    };
    // note: if any failure conditions are added to this function below this
    // point, platform_draw.deinit will need to be called

    self.game_over = false;
    self.new_high_score = false;
    self.menu_anim_time = 0;
    self.menu_stack = .{
        .array = undefined,
        .len = 1,
    };
    self.menu_stack.array[0] = .{
        .main_menu = menus.MainMenu.init(),
    };
    self.fullscreen = params.fullscreen;
    self.canvas_scale = params.canvas_scale;
    self.max_canvas_scale = params.max_canvas_scale;
    self.friendly_fire = true;
    self.sound_enabled = params.sound_enabled;

    return true;
}

pub fn deinit(self: *MainState) void {
    platform_draw.deinit(&self.draw_state);
}

pub fn makeMenuContext(self: *const MainState) menus.MenuContext {
    return .{
        .sound_enabled = self.sound_enabled,
        .fullscreen = self.fullscreen,
        .cfg = self.cfg,
        .high_scores = self.high_scores,
        .new_high_score = self.new_high_score,
        .game_over = self.game_over,
        .anim_time = self.menu_anim_time,
        .canvas_scale = self.canvas_scale,
        .max_canvas_scale = self.max_canvas_scale,
        .friendly_fire = self.friendly_fire,
    };
}

pub const InputSpecial = union(enum) {
    noop,
    quit,
    toggle_sound,
    toggle_fullscreen,
    set_canvas_scale: u31,
};

pub fn inputEvent(
    outer_self: var,
    comptime ns: type,
    source: InputSource,
    down: bool,
) ?InputSpecial {
    const main_state: *MainState = &outer_self.main_state;

    if (down) {
        const maybe_menu_command =
            for (main_state.cfg.menu_bindings) |maybe_source, i| {
                const s = maybe_source orelse continue;

                if (!areInputSourcesEqual(s, source)) continue;

                break @intToEnum(
                    input.MenuCommand,
                    @intCast(@TagType(input.MenuCommand), i),
                );
            } else null;

        // if menu is open, input goes to it
        if (main_state.menu_stack.len > 0) {
            // note that the menu receives input even if the menu_command is null
            // (used by the key rebinding menu)
            const result = menuInput(&main_state.menu_stack, .{
                .source = source,
                .maybe_command = maybe_menu_command,
                .menu_context = makeMenuContext(main_state),
            }) orelse return null;

            if (result.sound) |sound| {
                main_state.audio_module.playMenuSound(sound);
            }

            return applyMenuEffect(outer_self, ns, result.effect);
        }

        // menu is not open, but should we open it?
        if (maybe_menu_command) |menu_command| {
            if (menu_command == .escape) {
                // assuming that if the menu isn't open, we must be in game
                main_state.audio_module.playMenuSound(.backoff);

                return applyMenuEffect(outer_self, ns, menus.Effect {
                    .push = .{ .in_game_menu = menus.InGameMenu.init() },
                });
            }
        }
    }

    // game command?
    var player_number: u32 = 0;
    while (player_number < config.num_players) : (player_number += 1) {
        for (main_state.cfg.game_bindings[player_number]) |maybe_source, i| {
            const s = maybe_source orelse continue;

            if (!areInputSourcesEqual(s, source)) continue;

            _ = p.EventGameInput.spawn(&main_state.session, .{
                .player_number = player_number,
                .command = @intToEnum(input.GameCommand,
                    @intCast(@TagType(input.GameCommand), i)),
                .down = down,
            }) catch undefined;

            return InputSpecial { .noop = {} };
        }
    }

    return null;
}

fn applyMenuEffect(
    outer_self: var,
    comptime ns: var,
    effect: menus.Effect,
) ?InputSpecial {
    const self = &outer_self.main_state;

    switch (effect) {
        .noop => {},
        .push => |new_menu| {
            self.menu_stack.push(new_menu);
        },
        .pop => {
            self.menu_stack.pop();
        },
        .start_new_game => |is_multiplayer| {
            self.menu_stack.clear();
            startGame(&self.session, is_multiplayer);
            self.game_over = false;
            self.new_high_score = false;
        },
        .end_game => {
            finalizeGame(self, ns);
            abortGame(&self.session);

            self.menu_stack.clear();
            self.menu_stack.push(.{
                .main_menu = menus.MainMenu.init(),
            });
        },
        .toggle_sound => {
            return InputSpecial { .toggle_sound = {} };
        },
        .set_volume => |value| {
            self.cfg.volume = value;
        },
        .set_canvas_scale => |value| {
            return InputSpecial { .set_canvas_scale = value };
        },
        .toggle_fullscreen => {
            return InputSpecial { .toggle_fullscreen = {} };
        },
        .toggle_friendly_fire => {
            self.friendly_fire = !self.friendly_fire;
            // update existing bullets
            setFriendlyFire(&self.session, self.friendly_fire);
        },
        .bind_game_command => |payload| {
            const command_index = @enumToInt(payload.command);
            const in_use =
                if (payload.source) |new_source|
                    for (self.cfg.game_bindings[payload.player_number])
                                                            |maybe_source| {
                        const source = maybe_source orelse continue;
                        if (!areInputSourcesEqual(source, new_source)) continue;
                        break true;
                    } else false
                else false;
            if (!in_use) {
                self.cfg.game_bindings[payload.player_number][command_index] =
                    payload.source;
            }
        },
        .reset_anim_time => {
            self.menu_anim_time = 0;
        },
        .quit => {
            return .quit;
        },
    }

    return .noop;
}

// i feel like these functions are too heavy to be done inline by this system.
// they should be created as events and handled by middleware?
// called when "start new game" is selected in the menu. if a game is already
// in progress, restart it
pub fn startGame(gs: *GameSession, is_multiplayer: bool) void {
    // remove all entities except the MainController
    inline for (@typeInfo(ComponentLists).Struct.fields) |field| {
        if (field.field_type.ComponentType == c.MainController) continue;
        gs.ecs.markAllForRemoval(field.field_type.ComponentType);
    }

    // update MainController (note: this entity was spawned right when the
    // program was launched)
    gs.ecs.findFirstComponent(c.MainController).?.game_running_state = .{
        .render_move_boxes = false,
    };

    // spawn GameController and PlayerControllers
    const num_players: u32 = if (is_multiplayer) 2 else 1;

    _ = p.GameController.spawn(gs, .{
        .num_players = num_players,
    }) catch undefined;

    var n: u32 = 0; while (n < num_players) : (n += 1) {
        _ = p.PlayerController.spawn(gs, .{
            .player_number = n,
        }) catch undefined;
    }
}

// called when "end game" is selected in the menu
pub fn abortGame(gs: *GameSession) void {
    gs.ecs.findFirstComponent(c.MainController).?.game_running_state = null;

    // remove all entities except the MainController
    inline for (@typeInfo(ComponentLists).Struct.fields) |field| {
        if (field.field_type.ComponentType == c.MainController) continue;
        gs.ecs.markAllForRemoval(field.field_type.ComponentType);
    }
}

pub fn handleGameOver(self: *MainState, comptime ns: var) void {
    if (self.session.ecs.findFirstComponent(c.EventGameOver) != null) {
        finalizeGame(self, ns);
        self.menu_stack.push(.{
            .game_over_menu = menus.GameOverMenu.init(),
        });
    }
}

fn finalizeGame(self: *MainState, comptime ns: var) void {
    self.game_over = true;
    self.new_high_score = false;

    var save_high_scores = true;

    // get players' scores
    var it = self.session.ecs.componentIter(c.PlayerController);
    while (it.next()) |pc| {
        // insert the score somewhere in the high score list
        const new_score = pc.score;

        // the list is always sorted highest to lowest
        var i: usize = 0; while (i < constants.num_high_scores) : (i += 1) {
            if (new_score > self.high_scores[i]) {
                // insert the new score here
                std.mem.copyBackwards(u32,
                    self.high_scores[i + 1..constants.num_high_scores],
                    self.high_scores[i..constants.num_high_scores - 1]
                );

                self.high_scores[i] = new_score;
                if (i == 0) {
                    self.new_high_score = true;
                }

                save_high_scores = true;
                break;
            }
        }
    }

    if (save_high_scores) {
        ns.saveHighScores(&self.hunk.low(), self.high_scores) catch |err| {
            warn("Failed to save high scores: {}\n", .{err});
        };
    }
}

pub fn drawMain(self: *MainState) void {
    platform_draw.prepare(&self.draw_state);

    drawGame(
        &self.draw_state,
        &self.static,
        &self.session,
        self.cfg,
        self.high_scores[0],
    );

    drawMenu(&self.menu_stack, .{
        .ds = &self.draw_state,
        .static = &self.static,
        .menu_context = makeMenuContext(self),
    });
}
