const Self = @This();

const std = @import("std");
const log = std.log;

const Ring = @import("ring.zig");
const game = @import("scenes/game.zig");

const mainspace = @import("main.zig");

pub const Pos = ?@Vector(2, u8);

pub const startingPos = null;
pub const endingPos: Pos = @splat(
  std.math.maxInt(@typeInfo(@typeInfo(Pos).optional.child).vector.child));

var moveBuffer: [4]Pos = undefined;
pub var moves: []Pos = moveBuffer[0..0];

pos: Pos,
entryIndex: u8,

exchangeTokens: game.TokenType = 0,
coldStorageTokens: game.TokenType = 0,
lostTokens: game.TokenType = 0,

pub fn move(self: *Self, parent: []Ring, pos: Pos) void
{
  self.pos = pos;

  const ring = &parent[pos.?[1]];
  const space = &ring.spaces[pos.?[0]];

  defer {
    log.info("Getting moves for player {}\n", .{game.currentPlayer});
    _ = game.players.items[game.currentPlayer].value.getMoves(
      parent, mainspace.rand.intRangeAtMost(u8, 1, 6)
    );
  }

  if (pos != null and space.hasToken == true)
  {
    self.exchangeTokens += @intFromBool(ring.removeToken(pos.?[0]));

    game.nextTurn();

    return;
  }

  switch (space.type)
  {
    .Default => {},
    .ColdStorage => {
      self.coldStorageTokens += self.exchangeTokens;
      self.exchangeTokens = 0;
    },
    .ExchangeHack => {
      for (game.players.items) |*player|
      {
        player.value.lostTokens += player.value.exchangeTokens;
        player.value.exchangeTokens = 0;
      }
    },
    .OrangePill => {
      // TODO: When this space is landed on, the current player should select another player to give one token to
    },
    .Exec6102 => {
      for (game.players.items) |*player|
      {
        player.value.lostTokens = 0;
        player.value.exchangeTokens = 0;
      }
    },
    .Moon => {
      self.coldStorageTokens += self.lostTokens;
      self.lostTokens = 0;
    },
  }

  if (!space.reroll)
  {
    game.nextTurn();
  }
}

/// Populates moveBuffer with available moves and returns moves slice
pub fn getMoves(self: *Self, parent: []Ring, steps: u8) []Pos
{
  moves = moveBuffer[0..0];

  if (steps == 0)
  {
    moveBuffer[0] = self.pos;
    return moves;
  }

  const StackElement = struct
  {
    pos: @typeInfo(Pos).optional.child,
    depth: u8,
    direction: i2,
  };

  var stackBuffer: [4]StackElement = undefined;
  var stack: []StackElement = stackBuffer[0..1];

  if (self.pos == startingPos)
  {
    stack[stack.len-1] = .{
      .pos = .{self.entryIndex, 0},
      .depth = steps-1,
      .direction = 0,
    };
  } else
  {
    stack[stack.len-1] = .{
      .pos = self.pos.?,
      .depth = steps,
      .direction = 0,
    };
  }

  while (stack.len > 0)
  {
    const top = stack[stack.len-1];
    stack.len -= 1;

    if (top.depth == 0)
    {
      moves.len += 1;
      moves[moves.len-1] = top.pos;

      continue;
    }

    if (parent[top.pos[1]].spaces[top.pos[0]].type == .Moon)
    {
      continue;
    }

    if (parent[top.pos[1]].tokenCount == 0)
    {
      if (parent[top.pos[1]].spaces[top.pos[0]].jumpIndex) |jumpIndex|
      {
        stack.len += 1;
        stack[stack.len-1] = .{
          .pos = .{
            jumpIndex,
            top.pos[1]+1
          },
          .depth = top.depth-1,
          .direction = 0,
        };
      }
    }

    if (top.direction == 0)
    {
      stack.len += 1;
      stack[stack.len-1] = .{
        .pos = .{
          @intCast(
            @mod(
              @as(i9, top.pos[0])-1,
              @as(i9, @intCast(parent[top.pos[1]].spaces.len))
            )
          ),
          top.pos[1]
        },
        .depth = top.depth-1,
        .direction = -1,
      };

      stack.len += 1;
      stack[stack.len-1] = .{
        .pos = .{
          @intCast(
            @mod(
              @as(i9, top.pos[0])+1,
              @as(i9, @intCast(parent[top.pos[1]].spaces.len))
            )
          ),
          top.pos[1]
        },
        .depth = top.depth-1,
        .direction = 1,
      };
    } else
    {
      stack.len += 1;
      stack[stack.len-1] = .{
        .pos = .{
          @intCast(
            @mod(
              @as(i9, top.pos[0])+top.direction,
              @as(i9, @intCast(parent[top.pos[1]].spaces.len))
            )
          ),
          top.pos[1]
        },
        .depth = top.depth-1,
        .direction = top.direction,
      };
    }
  }

  return moves;
}
