const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");

const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;

const directoryManager = @import("../directory_manager.zig");

const Space = @import("../space.zig");
const Ring = @import("../ring.zig");
const Player = @import("../player.zig");

const manual = @import("manual_player.zig");

const BoardCoord = Player.Pos;

pub const totalTokens = 21;
pub const TokenType = std.math.IntFittingRange(0, totalTokens);

var gpa: Allocator = undefined;

var ringTexture: *sdl.SDL_Texture = undefined;

var spaceHasTokenTexture: *sdl.SDL_Texture = undefined;
var spaceRerollTextures: [2]*sdl.SDL_Texture = undefined;
var spaceTypeTextures =
  std.EnumArray(Space.Type, *sdl.SDL_Texture).initUndefined();

var tokenTexture: *sdl.SDL_Texture = undefined;

var playerTexture: *sdl.SDL_Texture = undefined;

var spaces = std.ArrayList(Space).empty;
pub var board = std.ArrayList(Ring).empty;

const Color = @Vector(4, f32);
pub const PlayerEntry = struct {
  color: Color,
  controller: ?*const Scene,
  value: Player,
};
pub var players: std.ArrayList(PlayerEntry) = .empty;

pub var currentPlayer: u8 = undefined;

// Updates currentPlayerIndex and currentPlayer to be the next in line
pub fn nextTurn() void
{
  currentPlayer =
    (currentPlayer + 1) % @as(u8, @intCast(players.items.len));
}

//var moves: [4]BoardCoord = @splat(null);
//var moveLength: u8 = 0;

pub const scene = Scene{
  .keybinds = &.{},

  .init = struct {fn init(allocator: Allocator) !*const Scene
  {
    log.info("Initializing game\n", .{});
    gpa = allocator;

    try loadTextures();

    const jsonOut =
      try jsonFromFile(allocator, []struct {
        color: [3]f32,
        entryIndex: u8,
      }, "assets/metadata/players.json");
    defer jsonOut.deinit();

    try players.ensureTotalCapacity(allocator, jsonOut.value.len);
    log.debug("Player array position: {*}\n", .{players.items});

    for (jsonOut.value) |player|
    {
      log.info("Loading player {any}\n", .{player.color});

      players.append(allocator, .{
        .color = player.color ++ .{1.0},
        .controller = if (player.color[0] == 0.0)
            Scene.scenes.getPtrConst(.Manual)
          else
            null,//Scene.scenes.getPtrConst(.AI),
        .value = .{
          .pos = Player.startingPos,
          .entryIndex = player.entryIndex,
          .exchangeTokens = 0,
          .coldStorageTokens = 0,
          .lostTokens = 0,
        }
      }) catch unreachable;
    }

    try loadBoard(allocator);

    currentPlayer =
      mainspace.rand.uintLessThan(u8, @intCast(players.items.len));
    _ = players.items[currentPlayer].value.getMoves(
      board.items, mainspace.rand.intRangeAtMost(u8, 1, 6)
    );

    return &scene;
  }}.init,
  
  .getInput = struct {fn getInput(
    event: sdl.SDL_Event,
    keys: []const bool,
    mPos: @Vector(2, f32),
    mButtons: sdl.SDL_MouseButtonFlags) !bool
  {
    if (players.items[currentPlayer].controller) |controller|
    {
      _ = try controller.getInput(event, keys, mPos, mButtons);
    }

    return true;
  }}.getInput,

  .update = struct {fn update() !void
  {
    if (players.items[currentPlayer].controller) |controller|
    {
      try controller.update();
    } else
    {
      nextTurn();
      _ = players.items[currentPlayer].value.getMoves(
        board.items, mainspace.rand.intRangeAtMost(u8, 1, 6)
      );
    }
  }}.update,
  
  .render = struct {fn render() !void
  {
    try renderSpaces(board.items);

    const winSize = boardRenderArea()[1];
    const size = @min(winSize[0], winSize[1]) * 0.05;

    for (players.items, 0..players.items.len) |player, p|
    {
      const pos =
        boardToWindowPos(board.items, @intCast(p), player.value.pos) catch
          unreachable;

      _ = sdl.SDL_SetTextureColorModFloat(
        playerTexture,
        player.color[0],
        player.color[1],
        player.color[2]);
      if (!sdl.SDL_RenderTexture(
        mainspace.renderer, playerTexture, null,
        &.{
          .x = pos[0] - size*0.5,
          .y = pos[1] - size*0.5,
          .w = size,
          .h = size,
        }))
      {
        return error.SDL_RenderFail;
      }
    }

    if (players.items[currentPlayer].controller) |controller|
    {
      try controller.render();
    }

    try renderPlayerWallets(board.items);
  }}.render,
  
  .deinit = struct {fn deinit() !void
  {
    board.deinit(gpa);
    spaces.deinit(gpa);

    players.deinit(gpa);

    sdl.SDL_DestroyTexture(spaceHasTokenTexture);
    sdl.SDL_DestroyTexture(spaceRerollTextures[0]);
    sdl.SDL_DestroyTexture(spaceRerollTextures[1]);
    for (spaceTypeTextures.values) |texture|
    {
      sdl.SDL_DestroyTexture(texture);
    }
    sdl.SDL_DestroyTexture(playerTexture);
  }}.deinit,
};

fn loadTextures() !void
{
  ringTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath("assets/images/ring.svg"));

  spaceHasTokenTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath("assets/images/spaces/token_space.svg"));
  spaceRerollTextures[0] = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath("assets/images/spaces/no_reroll.svg"));
  spaceRerollTextures[1] = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath("assets/images/spaces/reroll.svg"));
  inline for (0..spaceTypeTextures.values.len) |t|
  {
    const spaceType: Space.Type = @enumFromInt(t);

    const filename = spaceType.toSnakeStr();
    const path =
      "assets/images/spaces/" ++ filename[0..filename.len-1] ++ ".svg";
    log.debug("Loading \"{s}\"\n", .{path});

    spaceTypeTextures.values[t] = sdl.IMG_LoadTexture(
      mainspace.renderer,
      try directoryManager.getPath(path));
  }

  tokenTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath("assets/images/token.svg"));

  playerTexture = sdl.IMG_LoadTexture(
    mainspace.renderer,
    try directoryManager.getPath("assets/images/player.svg"));
}

fn loadBoard(allocator: Allocator) !void
{
  const jsonOut =
    try jsonFromFile(allocator, [][]Space, "assets/metadata/board.json");
  defer jsonOut.deinit();

  const spaceCount = blk:{
    var spaceCount: u16 = 0;

    for (jsonOut.value) |ring|
    {
      spaceCount += @intCast(ring.len);
    }

    break:blk spaceCount;
  };

  try spaces.ensureTotalCapacity(allocator, spaceCount+1);
  try board.ensureTotalCapacity(allocator, jsonOut.value.len+1);

  for (jsonOut.value) |ring|
  {
    board.append(allocator,
      .{
        .spaces = spaces.items[spaces.items.len..spaces.items.len],
        .tokenCount = 0,
      }) catch
      unreachable;

    for (ring) |space|
    {
      spaces.append(allocator, space) catch unreachable;

      if (space.hasToken == true)
      {
        board.items[board.items.len-1].tokenCount += 1;
      }
      
      board.items[board.items.len-1].spaces.len += 1;
    }
  }

  spaces.append(allocator, .{
    .reroll = false,
    .type = .Moon,
  }) catch unreachable;
  board.append(allocator, .{
    .spaces = spaces.items[spaces.items.len-1..spaces.items.len],
    .tokenCount = 0,
  }) catch unreachable;
}

// Parsed data must be freed with .deinit()
fn jsonFromFile(allocator: Allocator, T: type, path: []const u8)
  !std.json.Parsed(T)
{
  const boardFilePath =
    try directoryManager.getPath(path);
  var boardFile = try std.fs.openFileAbsolute(boardFilePath, .{});
  defer boardFile.close();

  var readBuffer: [1024]u8 = undefined;
  var fileReader = boardFile.reader(&readBuffer);
  var jsonReader = std.json.Reader.init(allocator, &fileReader.interface);
  defer jsonReader.deinit();

  return try std.json.parseFromTokenSource(T, allocator, &jsonReader, .{});
}

fn renderSpaces(spaceArr: []Ring) error{SDL_RenderFail, InvalidPos}!void
{
  var noErr = true;
  //const center = boardRenderCenter();

  for (spaceArr, 0..spaceArr.len) |ring, y|
  {
    //const radius = getRingRadius(@intCast(spaceArr.len), @intCast(y));
    //if (!sdl.SDL_RenderTexture(
    //  mainspace.renderer, ringTexture, null,
    //  &.{
    //    .x = center[0]-radius,
    //    .y = center[1]-radius,
    //    .w = radius*2,
    //    .h = radius*2,
    //  }))
    //{
    //  return error.SDL_RenderFail;
    //}

    for (ring.spaces, 0..ring.spaces.len) |space, x|
    {
      const pos =
        try boardToWindowPos(spaceArr, null, .{@intCast(x), @intCast(y)});

      noErr &= sdl.SDL_SetRenderDrawColorFloat(
        mainspace.renderer,
        0.0, 0.25, 1.0, 1.0);

      const nextPos = try boardToWindowPos(
        spaceArr,
        null,
        .{@intCast((x+1)%ring.spaces.len), @intCast(y)});

      noErr &= sdl.SDL_RenderLine(
        mainspace.renderer,
        pos[0], pos[1],
        nextPos[0], nextPos[1]);

      if (space.jumpIndex) |i|
      {
        const linkPos =
          try boardToWindowPos(spaceArr, null, .{i, @intCast(y+1)});

        noErr &= sdl.SDL_SetRenderDrawColorFloat(
          mainspace.renderer,
          1.0, 0.5, 0.0, 1.0);

        noErr &= sdl.SDL_RenderLine(
          mainspace.renderer,
          pos[0], pos[1],
          linkPos[0], linkPos[1]);
      }

      try renderSpace(space, pos, getSpaceRadius(spaceArr, .{
        @intCast(x),
        @intCast(y)
      }));
    }
  }

  if (!noErr)
  {
    return error.SDL_RenderFail;
  }
}

//fn renderRing(ring: []const Space, radius: f32) !void
//{
//  const center = boardRenderCenter();
//
//  const angleOffset = (std.math.pi*2) / @as(f32, @floatFromInt(ring.len));
//  for (0..ring.len) |s|
//  {
//    const angle = ringStartAngle() + angleOffset*@as(f32, @floatFromInt(s));
//    const dir = WinCoord{@cos(angle), @sin(angle)};
//
//    try renderSpace(
//      ring[s],
//      center + dir*@as(WinCoord, @splat(radius)));
//  }
//}

fn renderSpace(space: Space, pos: mainspace.WinCoord, radius: f32)
  error{SDL_RenderFail}!void
{
  var noErr = true;

  if (space.hasToken != null)
  {
    noErr &= sdl.SDL_RenderTexture(
      mainspace.renderer, spaceHasTokenTexture, null,
      &.{
        .x = pos[0]-radius,
        .y = pos[1]-radius,
        .w = radius*2,
        .h = radius*2,
      }
    );
  }
  noErr &= sdl.SDL_RenderTexture(
    mainspace.renderer, spaceRerollTextures[@intFromBool(space.reroll)], null,
    &.{
      .x = pos[0]-radius,
      .y = pos[1]-radius,
      .w = radius*2,
      .h = radius*2,
    });
  noErr &= sdl.SDL_RenderTexture(
    mainspace.renderer, spaceTypeTextures.get(space.type), null,
    &.{
      .x = pos[0]-radius,
      .y = pos[1]-radius,
      .w = radius*2,
      .h = radius*2,
    });
  if (space.hasToken == true)
  {
    noErr &= sdl.SDL_RenderTexture(
      mainspace.renderer, tokenTexture, null,
      &.{
        .x = pos[0]-radius,
        .y = pos[1]-radius,
        .w = radius*2,
        .h = radius*2,
      }
    );
  }

  if (!noErr)
  {
    return error.SDL_RenderFail;
  }
}

fn renderPlayerWallets(spaceArr: []Ring) error{SDL_RenderFail, InvalidPos}!void
{
  var noErr = true;

  const renderArea = walletRenderArea();

  const walletSize: WinCoord = .{
    renderArea[1][0] / @as(f32, @floatFromInt(players.items.len)),
    renderArea[1][1]
  };

  const tokenRadius: f32 = @min(
    walletSize[0]*0.2,
    walletSize[1]*0.3,
    renderArea[1][0]*0.02,
  );

  for (0..players.items.len, players.items) |p, player|
  {
    const walletArea: [2]WinCoord = .{
      .{walletSize[0] * @as(f32, @floatFromInt(p)), renderArea[0][1]},
      .{walletSize[0], walletSize[1]},
    };

    noErr &= sdl.SDL_SetRenderDrawColorFloat(
      mainspace.renderer,
      player.color[0], player.color[1], player.color[2], player.color[3]);
    noErr &= sdl.SDL_RenderFillRect(
      mainspace.renderer, &.{
        .x = walletArea[0][0],
        .y = walletArea[0][1],
        .w = walletArea[1][0],
        .h = walletArea[1][1],
      });

    noErr &= sdl.SDL_SetRenderDrawColorFloat(
      mainspace.renderer,
      1.0, 0.0, 0.0, 1.0);
    noErr &= sdl.SDL_RenderRect(
      mainspace.renderer, &.{
        .x = walletArea[0][0] + walletArea[1][0]*0.05,
        .y = walletArea[0][1] + walletArea[1][1]*0.025,
        .w = walletArea[1][0]*0.4,
        .h = walletArea[1][1]*0.95,
      });

    try renderTokenStack(
      .{
        walletArea[0][0] + walletArea[1][0]*0.25,
        walletArea[0][1] + walletArea[1][1]*0.95
      },
      tokenRadius,
      player.value.exchangeTokens
    );

    noErr &= sdl.SDL_SetRenderDrawColorFloat(
      mainspace.renderer,
      0.0, 0.0, 1.0, 1.0);
    noErr &= sdl.SDL_RenderRect(
      mainspace.renderer, &.{
        .x = walletArea[0][0] + walletArea[1][0]*0.55,
        .y = walletArea[0][1] + walletArea[1][1]*0.025,
        .w = walletArea[1][0]*0.4,
        .h = walletArea[1][1]*0.95,
      });

    try renderTokenStack(
      .{
        walletArea[0][0] + walletArea[1][0]*0.75,
        walletArea[0][1] + walletArea[1][1]*0.95
      },
      tokenRadius,
      player.value.coldStorageTokens
    );

    const radius =
      getSpaceRadius(spaceArr, .{0, @intCast(spaceArr.len-1)}) * 0.5;
    try renderTokenStack(
      try boardToWindowPos(
        spaceArr,
        @intCast(players.items.len-p-1),
        Player.endingPos
      ) + WinCoord{0, radius*0.5},
      radius,
      players.items[players.items.len-p-1].value.lostTokens
    );
  }

  if (!noErr)
  {
    return error.SDL_RenderFail;
  }
}

fn renderTokenStack(pos: WinCoord, radius: f32, count: TokenType)
  error{SDL_RenderFail}!void
{
  for (0..count) |t|
  {
    if (!sdl.SDL_RenderTextureAffine(mainspace.renderer, tokenTexture, null, &.{
        .x = pos[0] - radius,
        .y = pos[1] - radius - @as(f32, @floatFromInt(t))*radius*0.1,
      }, &.{
        .x = pos[0] + radius,
        .y = pos[1] - radius - @as(f32, @floatFromInt(t))*radius*0.1,
      }, &.{
        .x = pos[0] - radius,
        .y = pos[1] - @as(f32, @floatFromInt(t))*radius*0.1,
      }))
    {
      return error.SDL_RenderFail;
    }
  }
}

pub fn boardToWindowPos(spaceArr: []Ring, playerIndex: ?u8, pos: BoardCoord)
  error{InvalidPos}!WinCoord
{
  const winSize = boardRenderArea()[1];
  const center = boardRenderCenter();
  
  if (pos == Player.startingPos or @reduce(.And, pos.? == Player.endingPos.?))
  {
    const playerIndexF: f32 =
      @floatFromInt(playerIndex orelse {return error.InvalidPos;});
    const angle = std.math.pi*0.25 + playerIndexF * std.math.pi*0.5;

    const dir = WinCoord{@cos(angle), @sin(angle)};
    const dis =
      if (pos == Player.startingPos)
        @min(winSize[0], winSize[1]) * 0.6
      else
        getSpaceRadius(spaceArr, .{0, @intCast(spaceArr.len-1)}) * 0.5;

    return center + dir*@as(WinCoord, @splat(dis));
  }

  const startAngle = ringStartAngle(pos.?[1]);
  const angleOffset =
    (std.math.pi*2) / @as(f32, @floatFromInt(spaceArr[pos.?[1]].spaces.len));
  const angle = startAngle + angleOffset*@as(f32, @floatFromInt(pos.?[0]));

  const dir = WinCoord{@cos(angle), @sin(angle)};
  const radius = getRingRadius(@intCast(spaceArr.len), pos.?[1]);
  return center + dir*@as(WinCoord, @splat(radius));
}

pub fn windowToBoardPos(spaceArr: []Ring, pos: WinCoord) BoardCoord
{
  const ringCount: f32 = @floatFromInt(spaceArr.len);

  const center = boardRenderCenter();

  const dis = std.math.hypot(pos[0] - center[0], pos[1] - center[1]);

  const maxRadius = getRingRadius(@intCast(spaceArr.len), 0);
  const radiusOffset = maxRadius / (ringCount-1);

  const ringIndex: u8 = @intFromFloat(std.math.clamp(
    ringCount-@round(dis/radiusOffset)-1,
    0, ringCount-1
  ));

  const ringLen: f32 = @floatFromInt(spaceArr[ringIndex].spaces.len);

  const angle =
    -std.math.atan2(pos[0] - center[0], pos[1] - center[1]) +
    std.math.pi*0.5 -
    ringStartAngle(ringIndex);
  const angleOffset = std.math.pi*2 / ringLen;

  const spaceIndex: u8 =
    @intFromFloat(@mod(@round(angle / angleOffset), ringLen));

  return .{spaceIndex, @intCast(std.math.clamp(ringIndex, 0, spaceArr.len-1))};
}

pub fn getRingRadius(ringCount: u8, index: u8) f32
{
  const winSize = boardRenderArea()[1];
  const maxRadius = @min(winSize[0], winSize[1]) * 0.45;

  const radiusOffset = maxRadius / @as(f32, @floatFromInt(ringCount-1));

  return maxRadius - radiusOffset*@as(f32, @floatFromInt(index));
}

fn getSpaceRadius(spaceArr: []Ring, pos: BoardCoord) f32
{
  if (pos == null)
  {
    return 0.0;
  }

  const winSize = boardRenderArea()[1];
  const boardSize = @min(winSize[0], winSize[1]);

  if (pos.?[1] < spaceArr.len-1)
  {
    return boardSize * @as(f32, 0.025);
  } else
  {
    return boardSize * @as(f32, 0.05);
  }
}

fn ringStartAngle(ringIndex: u8) f32
{
  return @as(f32, @floatFromInt(ringIndex % 2)) * 0.1;
}

pub fn boardRenderArea() [2]WinCoord
{
  const winSize = mainspace.winSize();

  return .{@splat(0), .{winSize[0], winSize[1]*0.8}};
}

fn boardRenderCenter() WinCoord
{
  const winSize = boardRenderArea();

  return (winSize[0]+winSize[1]) * @as(WinCoord, @splat(0.5));
}

fn walletRenderArea() [2]WinCoord
{
  const winSize = mainspace.winSize();

  return .{.{winSize[0], winSize[1]*0.8}, .{winSize[0], winSize[1]*0.2}};
}
