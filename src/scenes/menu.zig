const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;

const game = @import("game.zig");

var gpa: Allocator = undefined;

var selectedRocket: ?u8 = null;
var gameMode: usize = 0;
var numOpponents: usize = 0;

const GameModeOptions = [_][*:0]const u8{ "Standard", "Speed" };
const OpponentOptions = [_][*:0]const u8{ "1", "2", "3" };

const ButtonInfo = struct
{
  rect: [4]f32,
  label: [*:0]const u8,
};

const howToPlayButton = ButtonInfo{
  .rect = .{ 0.05, 0.75, 0.2, 0.08 },
  .label = "How to Play",
};

const playButton = ButtonInfo{
  .rect = .{ 0.75, 0.75, 0.2, 0.08 },
  .label = "Play",
};

var cachedFontSize: u8 = 0;
var cachedFont: ?*sdl.TTF_Font = null;

fn getOrLoadFont(size: u8) ?*sdl.TTF_Font
{
  if (cachedFont != null and cachedFontSize == size) return cachedFont;

  if (cachedFont) |f|
  {
    sdl.TTF_CloseFont(f);
    cachedFont = null;
  }

  const sysFontPaths = [_][*:0]const u8{
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/lato/Lato-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
  };

  for (sysFontPaths) |path|
  {
    if (sdl.TTF_OpenFont(path, @as(f32, @floatFromInt(size)))) |f|
    {
      cachedFont = f;
      cachedFontSize = size;
      return f;
    }
  }

  return null;
}

fn getButtonRect(button: ButtonInfo) [4]f32
{
  const winSize = mainspace.winSize();
  return .{
    button.rect[0] * winSize[0],
    button.rect[1] * winSize[1],
    button.rect[2] * winSize[0],
    button.rect[3] * winSize[1],
  };
}

fn getGameModeDropdownRect() [4]f32
{
  const winSize = mainspace.winSize();
  return .{
    winSize[0] * 0.1,
    winSize[1] * 0.55,
    winSize[0] * 0.35,
    winSize[1] * 0.06,
  };
}

fn getOpponentsDropdownRect() [4]f32
{
  const winSize = mainspace.winSize();
  return .{
    winSize[0] * 0.55,
    winSize[1] * 0.55,
    winSize[0] * 0.35,
    winSize[1] * 0.06,
  };
}

fn isPointInRect(pos: @Vector(2, f32), rect: [4]f32) bool
{
  return pos[0] >= rect[0] and pos[0] <= rect[0] + rect[2] and
    pos[1] >= rect[1] and pos[1] <= rect[1] + rect[3];
}

fn renderText(text: [*:0]const u8, x: f32, y: f32, size: u8, centered: bool) void
{
  const font = getOrLoadFont(size) orelse return;

  const fg = sdl.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
  const surface = sdl.TTF_RenderText_Blended(font, text, 0, fg) orelse return;
  defer sdl.SDL_DestroySurface(surface);

  const texture = sdl.SDL_CreateTextureFromSurface(mainspace.renderer, surface) orelse return;
  defer sdl.SDL_DestroyTexture(texture);

  var tw: f32 = undefined;
  var th: f32 = undefined;
  _ = sdl.SDL_GetTextureSize(texture, &tw, &th);

  const drawX = if (centered) x - tw / 2.0 else x;
  const drawY = y - th / 2.0;

  _ = sdl.SDL_RenderTexture(mainspace.renderer, texture, null,
    &.{ .x = drawX, .y = drawY, .w = tw, .h = th });
}

fn renderDropdownValue(text: [*:0]const u8, x: f32, y: f32, size: u8) void
{
  const winSize = mainspace.winSize();

  _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 0.2, 0.2, 0.2, 1.0);
  _ = sdl.SDL_RenderFillRect(mainspace.renderer, &.{
    .x = x,
    .y = y,
    .w = winSize[0] * 0.35,
    .h = winSize[1] * 0.06,
  });

  renderText(text, x + winSize[0] * 0.175, y + winSize[1] * 0.03, size, true);
}

fn renderButtonWithText(button: ButtonInfo, enabled: bool) void
{
  const rect = getButtonRect(button);

  if (enabled)
  {
    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 0.2, 0.6, 0.2, 1.0);
  } else
  {
    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 0.3, 0.3, 0.3, 1.0);
  }

  _ = sdl.SDL_RenderFillRect(mainspace.renderer, &.{
    .x = rect[0], .y = rect[1], .w = rect[2], .h = rect[3],
  });

  renderText(button.label, rect[0] + rect[2] / 2.0, rect[1] + rect[3] / 2.0, 18, true);
}

fn renderRockets(winSize: mainspace.WinCoord) void
{
  if (game.players.items.len == 0) return;

  const rocketSize = @min(winSize[0], winSize[1]) * 0.08;
  const totalPlayers: f32 = @floatFromInt(game.players.items.len);
  const startX = winSize[0] / 2.0 - totalPlayers * rocketSize * 0.6;
  const y = winSize[1] * 0.38;

  for (game.players.items, 0..) |player, i|
  {
    const x = startX + @as(f32, @floatFromInt(i)) * rocketSize * 1.2;
    const isSelected = selectedRocket != null and selectedRocket.? == @as(u8, @intCast(i));
    const drawSize = if (isSelected) rocketSize * 1.2 else rocketSize;

    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer,
      player.color[0], player.color[1], player.color[2], 1.0);
    _ = sdl.SDL_RenderFillRect(mainspace.renderer, &.{
      .x = x - drawSize / 2.0,
      .y = y - drawSize / 2.0,
      .w = drawSize,
      .h = drawSize,
    });

    if (isSelected)
    {
      _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 1.0, 1.0, 1.0, 1.0);
      _ = sdl.SDL_RenderRect(mainspace.renderer, &.{
        .x = x - drawSize / 2.0 - 2.0,
        .y = y - drawSize / 2.0 - 2.0,
        .w = drawSize + 4.0,
        .h = drawSize + 4.0,
      });
    }
  }
}

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
    _ = keys;
    _ = mButtons;

    if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN)
    {
      const pos = mPos;

      const winSize = mainspace.winSize();
      const rocketSize = @min(winSize[0], winSize[1]) * 0.08;
      const totalPlayers: f32 = @floatFromInt(game.players.items.len);
      const startX = winSize[0] / 2.0 - totalPlayers * rocketSize * 0.6;
      const y = winSize[1] * 0.38;

      for (game.players.items, 0..) |_, i|
      {
        const x = startX + @as(f32, @floatFromInt(i)) * rocketSize * 1.2;
        if (isPointInRect(pos, .{
          x - rocketSize / 2.0, y - rocketSize / 2.0,
          rocketSize, rocketSize,
        }))
        {
          selectedRocket = @intCast(i);
        }
      }

      if (selectedRocket != null and isPointInRect(pos, getButtonRect(playButton)))
      {
        log.info("Play button clicked with rocket: {?}\n", .{selectedRocket});
        game.currentPlayer = selectedRocket.?;
        mainspace.currentScene = .Game;
      }

      if (isPointInRect(pos, getGameModeDropdownRect()))
      {
        gameMode = (gameMode + 1) % GameModeOptions.len;
      }

      if (isPointInRect(pos, getOpponentsDropdownRect()))
      {
        numOpponents = (numOpponents + 1) % OpponentOptions.len;
      }
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {
  }}.update,

  .render = struct {fn render() !void
  {
    const winSize = mainspace.winSize();

    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 0.1, 0.1, 0.1, 1.0);
    _ = sdl.SDL_RenderClear(mainspace.renderer);

    renderText("Mission Bitcoin", winSize[0] / 2, 50, 36, true);

    renderText("Choose your color", winSize[0] / 2, winSize[1] * 0.22, 24, true);
    renderRockets(winSize);

    // Game Mode section - centered
    const gameModeDropdownRect = getGameModeDropdownRect();
    renderText("Game Mode", gameModeDropdownRect[0] + gameModeDropdownRect[2] / 2, gameModeDropdownRect[1] - 25, 18, true);
    renderDropdownValue(GameModeOptions[gameMode], gameModeDropdownRect[0], gameModeDropdownRect[1], 18);

    // Opponents section - centered
    const opponentsDropdownRect = getOpponentsDropdownRect();
    renderText("Number of Opponents", opponentsDropdownRect[0] + opponentsDropdownRect[2] / 2, opponentsDropdownRect[1] - 25, 18, true);
    renderDropdownValue(OpponentOptions[numOpponents], opponentsDropdownRect[0], opponentsDropdownRect[1], 18);

    renderButtonWithText(howToPlayButton, true);
    renderButtonWithText(playButton, selectedRocket != null);
  }}.render,

  .deinit = struct {fn deinit() !void
  {
    if (cachedFont) |f|
    {
      sdl.TTF_CloseFont(f);
      cachedFont = null;
    }
  }}.deinit,
};
