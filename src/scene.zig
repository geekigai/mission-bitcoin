const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const InputEvent = @import("input_event.zig");

const mainspace = @import("main.zig");
const sdl = mainspace.sdl;

pub const ID = enum
{
  Menu,
  Game,
  Manual,
  AI,
  Remote,
};

pub const scenes = std.EnumArray(ID, Self).init(.{
  .Menu = @import("scenes/menu.zig").scene,
  .Game = @import("scenes/game.zig").scene,
  .Manual = @import("scenes/manual_player.zig").scene,
  .AI = @import("scenes/ai_player.zig").scene,
  .Remote = @import("scenes/remote_player.zig").scene,
});

keybinds: []struct {
  key: []const u8,
  value: InputEvent
},

init: *const fn(allocator: Allocator) anyerror!*const Self,

/// Returns whether to pass the event down
getInput: *const fn(
  event: sdl.SDL_Event,
  keys: []const bool,
  mPos: @Vector(2, f32),
  mButtons: sdl.SDL_MouseButtonFlags) anyerror!bool,

update: *const fn() anyerror!void,

render: *const fn() anyerror!void,

deinit: *const fn() anyerror!void,

