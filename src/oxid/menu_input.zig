const menus = @import("menus.zig");
const GameSession = @import("game.zig").GameSession;
const input = @import("input.zig");
const Key = @import("../common/key.zig").Key;

const MenuInputContext = struct {
    key: ?Key,
    command: ?input.MenuCommand,
    menu_context: menus.MenuContext,
    cursor_pos: usize,
    option_index: usize,
    num_options: usize,
    new_cursor_pos: usize,
    effect: ?menus.Effect,
    sound: ?menus.Sound,

    pub fn setPositionTop(self: *@This()) void {}
    pub fn title(self: *@This(), alignment: menus.TextAlignment, s: []const u8) void {}
    pub fn label(self: *@This(), comptime fmt: []const u8, args: ...) void {}
    pub fn vspacer(self: *@This()) void {}

    const OptionInnerResult = enum { Left, Right, Enter };
    fn optionInner(self: *@This(), is_slider: bool, comptime fmt: []const u8, args: ...) ?OptionInnerResult {
        defer self.option_index += 1;

        if (self.option_index == self.cursor_pos) {
            if (self.command) |command| {
                switch (command) {
                    .Enter => {
                        return OptionInnerResult.Enter;
                    },
                    .Left => {
                        return OptionInnerResult.Left;
                    },
                    .Right => {
                        return OptionInnerResult.Right;
                    },
                    .Up => {
                        self.setSound(.Blip);
                        self.new_cursor_pos =
                            if (self.cursor_pos > 0)
                                self.cursor_pos - 1
                            else
                                self.num_options - 1;
                    },
                    .Down => {
                        self.setSound(.Blip);
                        self.new_cursor_pos =
                            if (self.cursor_pos < self.num_options - 1)
                                self.cursor_pos + 1
                            else
                                0;
                    },
                    else => {},
                }
            }
        }

        return null;
    }

    pub fn option(self: *@This(), comptime fmt: []const u8, args: ...) bool {
        // for "buttons", only enter key works
        return if (self.optionInner(false, fmt, args)) |result| result == .Enter else false;
    }

    pub fn optionToggle(self: *@This(), comptime fmt: []const u8, args: ...) bool {
        // for on/off toggles, left, right and enter keys all work
        return self.optionInner(false, fmt, args) != null;
    }

    pub fn optionSlider(self: *@This(), comptime fmt: []const u8, args: ...) ?menus.OptionSliderResult {
        return if (self.optionInner(true, fmt, args)) |result|
            switch (result) {
                .Left => menus.OptionSliderResult.Left,
                .Right => menus.OptionSliderResult.Right,
                else => null,
            }
        else null;
    }

    pub fn setEffect(self: *@This(), effect: menus.Effect) void {
        self.effect = effect;
    }

    pub fn setSound(self: *@This(), sound: menus.Sound) void {
        self.sound = sound;
    }
};

pub const MenuInputParams = struct {
    key: Key,
    maybe_command: ?input.MenuCommand,
    menu_context: menus.MenuContext,
};

pub fn menuInput(menu_stack: *menus.MenuStack, params: MenuInputParams) ?menus.Result {
    if (menu_stack.len == 0) {
        return null;
    }
    return menu_stack.array[menu_stack.len - 1].dispatch(MenuInputParams, params, menuInputInner);
}

fn menuInputInner(comptime T: type, state: *T, params: MenuInputParams) ?menus.Result {
    var ctx = MenuInputContext {
        .key = null,
        .command = null,
        .menu_context = params.menu_context,
        .cursor_pos = state.cursor_pos,
        .option_index = 0,
        .num_options = 0,
        .new_cursor_pos = state.cursor_pos,
        .effect = null,
        .sound = null,
    };

    // analyze (get number of options)
    state.func(MenuInputContext, &ctx);

    const num_options = ctx.option_index;

    // handle input
    ctx = MenuInputContext {
        .key = params.key,
        .command = params.maybe_command,
        .menu_context = params.menu_context,
        .cursor_pos = state.cursor_pos,
        .option_index = 0,
        .num_options = num_options,
        .new_cursor_pos = state.cursor_pos,
        .effect = null,
        .sound = null,
    };

    state.func(MenuInputContext, &ctx);

    state.cursor_pos = ctx.new_cursor_pos;

    if (ctx.effect != null or ctx.sound != null) {
        return menus.Result {
            .effect = ctx.effect orelse menus.Effect { .NoOp = {} },
            .sound = ctx.sound,
        };
    }
    return null;
}
