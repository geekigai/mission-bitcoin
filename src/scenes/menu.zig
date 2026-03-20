const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig");
const mainspace = @import("../main.zig");
const sdl = mainspace.sdl;
const WinCoord = mainspace.WinCoord;
const directoryManager = @import("../directory_manager.zig");
const game = @import("game.zig");

var gpa: Allocator = undefined;
var playerTextures: [4]*sdl.SDL_Texture = undefined;
var playerColors: [4][3]f32 = undefined;
var fontPathCopy: [512:0]u8 = undefined;

// Cache fonts for all sizes we use
var fontSizes: [4]f32 = .{ 36, 24, 18, 16 };
var cachedFonts: [4]?*sdl.TTF_Font = .{ null, null, null, null };

var selectedRocket: ?u8 = null;
var gameMode: u8 = 0;
var numOpponents: u8 = 0;

const GameModeOptions = [_][:0]const u8{ "Easy", "Normal", "Hard", "Multiplayer" };
const OpponentOptions = [_][:0]const u8{ "1", "2", "3" };

const Button = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    label: [:0]const u8,
};

var playButton: Button = undefined;
var howToPlayButton: Button = undefined;

pub const scene = Scene{
    .keybinds = &.{},

    .init = struct {
        fn init(allocator: Allocator) !*const Scene {
            gpa = allocator;

            const jsonOut = try jsonFromFile(allocator, []struct {
                color: [3]f32,
                entryIndex: u8,
            }, "assets/metadata/players.json");
            defer jsonOut.deinit();

            for (jsonOut.value, 0..) |player, i| {
                playerColors[i] = player.color;
                playerTextures[i] = sdl.IMG_LoadTexture(
                    mainspace.renderer,
                    try directoryManager.getPath("assets/images/player.svg"),
                );
            }

            const winSize = mainspace.winSize();
            const buttonHeight: f32 = 40;
            const buttonWidth: f32 = 150;

            playButton = .{
                .x = winSize[0] / 2 + 10,
                .y = winSize[1] - 100,
                .w = buttonWidth,
                .h = buttonHeight,
                .label = "Play",
            };

            howToPlayButton = .{
                .x = winSize[0] / 2 - buttonWidth - 10,
                .y = winSize[1] - 100,
                .w = buttonWidth,
                .h = buttonHeight,
                .label = "How to Play",
            };

            // Load font path once
            const tempPath = try directoryManager.getPath("assets/fonts/Outfit-VariableFont_wght.ttf");
            var i: usize = 0;
            while (i < 511 and tempPath[i] != 0) : (i += 1) {
                fontPathCopy[i] = tempPath[i];
            }
            fontPathCopy[i] = 0;

            // Cache all font sizes at startup
            for (fontSizes, 0..) |fontSize, fontIdx| {
                cachedFonts[fontIdx] = sdl.TTF_OpenFont(@ptrCast(&fontPathCopy), fontSize);
            }

            return &scene;
        }
    }.init,

    .getInput = struct {
        fn getInput(
            event: sdl.SDL_Event,
            keys: []const bool,
            mPos: @Vector(2, f32),
            mButtons: sdl.SDL_MouseButtonFlags,
        ) !bool {
            _ = keys;
            _ = mPos;
            _ = mButtons;

            if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
                const pos: WinCoord = .{ event.button.x, event.button.y };

                for (0..4) |i| {
                    const rocketPos = getRocketPosition(@intCast(i));
                    const rocketRadius: f32 = 40;
                    const dist = std.math.hypot(pos[0] - rocketPos[0], pos[1] - rocketPos[1]);
                    if (dist < rocketRadius) {
                        selectedRocket = @intCast(i);
                    }
                }

                if (isPointInRect(pos, getGameModeDropdownRect())) {
                    gameMode = (gameMode + 1) % @as(u8, @intCast(GameModeOptions.len));
                }

                if (isPointInRect(pos, getOpponentsDropdownRect())) {
                    numOpponents = (numOpponents + 1) % @as(u8, @intCast(OpponentOptions.len));
                }

                if (selectedRocket != null and isPointInRect(pos, getButtonRect(playButton))) {
                    log.info("Play button clicked with rocket: {?}\n", .{selectedRocket});
                    game.currentPlayer = selectedRocket.?;
                    // Transition to game scene
                    const gameScene = Scene.scenes.get(.Game);
                    try gameScene.init(gpa);
                }

                if (isPointInRect(pos, getButtonRect(howToPlayButton))) {
                    log.info("How to Play button clicked\n", .{});
                }
            }

            return true;
        }
    }.getInput,

    .update = struct {
        fn update() !void {
        }
    }.update,

    .render = struct {
       fn render() !void {
         log.info("Menu render called\n", .{});
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
        }
    }.render,

    .deinit = struct {
        fn deinit() !void {
            for (cachedFonts) |font| {
                if (font != null) {
                    sdl.TTF_CloseFont(font);
                }
            }
            for (playerTextures) |texture| {
                sdl.SDL_DestroyTexture(texture);
            }
        }
    }.deinit,
};

fn getRocketPosition(index: u8) WinCoord {
    const winSize = mainspace.winSize();
    const spacing: f32 = 120;
    const startX = winSize[0] / 2 - (spacing * 1.5);
    return .{ startX + spacing * @as(f32, @floatFromInt(index)), winSize[1] * 0.35 };
}

fn renderRockets(winSize: WinCoord) void {
    _ = winSize;
    const rocketRadius: f32 = 40;

    for (0..4) |i| {
        const pos = getRocketPosition(@intCast(i));
        const isBright = selectedRocket == @as(?u8, @intCast(i));
        const brightness: f32 = if (isBright) 1.0 else 0.5;

        _ = sdl.SDL_SetTextureColorModFloat(
            playerTextures[i],
            playerColors[i][0] * brightness,
            playerColors[i][1] * brightness,
            playerColors[i][2] * brightness,
        );

        _ = sdl.SDL_RenderTexture(mainspace.renderer, playerTextures[i], null, &.{
            .x = pos[0] - rocketRadius,
            .y = pos[1] - rocketRadius,
            .w = rocketRadius * 2,
            .h = rocketRadius * 2,
        });
    }
}

fn getGameModeDropdownRect() [4]f32 {
    const winSize = mainspace.winSize();
    const dropdownWidth: f32 = 170;
    const spacing: f32 = 50;
    const totalWidth = (dropdownWidth * 2) + spacing;
    const startX = (winSize[0] - totalWidth) / 2;
    
    return .{
        startX,
        winSize[1] * 0.55,
        dropdownWidth,
        40,
    };
}

fn getOpponentsDropdownRect() [4]f32 {
    const winSize = mainspace.winSize();
    const dropdownWidth: f32 = 170;
    const spacing: f32 = 50;
    const totalWidth = (dropdownWidth * 2) + spacing;
    const startX = (winSize[0] - totalWidth) / 2;
    
    return .{
        startX + dropdownWidth + spacing,
        winSize[1] * 0.55,
        dropdownWidth,
        40,
    };
}

fn getButtonRect(button: Button) [4]f32 {
    return .{ button.x, button.y, button.w, button.h };
}

fn getFontIndex(fontSize: f32) ?usize {
    for (fontSizes, 0..) |size, idx| {
        if (size == fontSize) {
            return idx;
        }
    }
    return null;
}

fn renderText(text: [:0]const u8, x: f32, y: f32, fontSize: f32, centered: bool) void {
    const fontIdx = getFontIndex(fontSize) orelse return;
    const font = cachedFonts[fontIdx] orelse return;

    const textSurface = sdl.TTF_RenderText_Solid(font, @ptrCast(text.ptr), text.len, .{ .r = 255, .g = 255, .b = 255, .a = 255 }) orelse return;
    defer sdl.SDL_DestroySurface(textSurface);

    const textTexture = sdl.SDL_CreateTextureFromSurface(mainspace.renderer, textSurface) orelse return;
    defer sdl.SDL_DestroyTexture(textTexture);

    var rect: sdl.SDL_FRect = undefined;
    rect.w = @floatFromInt(textSurface.*.w);
    rect.h = @floatFromInt(textSurface.*.h);
    
    if (centered) {
        rect.x = x - rect.w / 2;
        rect.y = y - rect.h / 2;
    } else {
        rect.x = x;
        rect.y = y;
    }

    _ = sdl.SDL_RenderTexture(mainspace.renderer, textTexture, null, &rect);
}

fn renderDropdownValue(value: [:0]const u8, x: f32, y: f32, fontSize: f32) void {
    const rect = [4]f32{ x, y, 170, 40 };
    
    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 0.3, 0.3, 0.3, 1.0);
    _ = sdl.SDL_RenderFillRect(mainspace.renderer, &.{
        .x = rect[0],
        .y = rect[1],
        .w = rect[2],
        .h = rect[3],
    });

    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, 1.0, 1.0, 1.0, 1.0);
    _ = sdl.SDL_RenderRect(mainspace.renderer, &.{
        .x = rect[0],
        .y = rect[1],
        .w = rect[2],
        .h = rect[3],
    });

    renderText(value, x + 85, y + 20, fontSize, true);
}

fn renderButtonWithText(button: Button, enabled: bool) void {
    const color: f32 = if (enabled) 1.0 else 0.5;

    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, color * 0.2, color * 0.2, color * 0.2, 1.0);
    _ = sdl.SDL_RenderFillRect(mainspace.renderer, &.{
        .x = button.x,
        .y = button.y,
        .w = button.w,
        .h = button.h,
    });

    _ = sdl.SDL_SetRenderDrawColorFloat(mainspace.renderer, color, color, color, 1.0);
    _ = sdl.SDL_RenderRect(mainspace.renderer, &.{
        .x = button.x,
        .y = button.y,
        .w = button.w,
        .h = button.h,
    });

    renderText(button.label, button.x + button.w / 2, button.y + button.h / 2, 16, true);
}

fn isPointInRect(point: WinCoord, rect: [4]f32) bool {
    return point[0] >= rect[0] and
        point[0] <= rect[0] + rect[2] and
        point[1] >= rect[1] and
        point[1] <= rect[1] + rect[3];
}

fn jsonFromFile(allocator: Allocator, T: type, path: []const u8) !std.json.Parsed(T) {
    const filePath = try directoryManager.getPath(path);
    var file = try std.fs.openFileAbsolute(filePath, .{});
    defer file.close();

    var readBuffer: [1024]u8 = undefined;
    var fileReader = file.reader(&readBuffer);
    var jsonReader = std.json.Reader.init(allocator, &fileReader.interface);
    defer jsonReader.deinit();

    return try std.json.parseFromTokenSource(T, allocator, &jsonReader, .{});
}