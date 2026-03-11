const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const directoryManager = @import("../directory_manager.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

const game = @import("game.zig");

const Player = @import("../player.zig");

const BoardCoord = Player.Pos;

var gpa: Allocator = undefined;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    gpa = allocator;

    return &scene;
  }}.init,
  
  .getInput = struct {fn getInput(
    event: sdl.SDL_Event,
    keys: []const bool,
    mPos: @Vector(2, f32),
    mButtons: sdl.SDL_MouseButtonFlags) !bool
  {
    _ = event;
    _ = keys;
    _ = mPos;
    _ = mButtons;

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {
    if (Player.moves.len == 0)
    {
      return;
    }

    const currentPlayer = &game.players.items[game.currentPlayer].value;

    currentPlayer.move(
      game.board.items,
      Player.moves[mainspace.rand.uintLessThan(u3, @intCast(Player.moves.len))]
    );
  }}.update,
  
  .render = struct {fn render() !void
  {

  }}.render,
  
  .deinit = struct {fn deinit() !void
  {

  }}.deinit,
};

