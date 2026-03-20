const std = @import("std");
const log = std.log;
const fs = std.fs;
const path = fs.path;
const Dir = fs.Dir;

const mainspace = @import("main.zig");

var resourcePaths = [_]?[fs.max_path_bytes]u8{
  null, // cwdPath
  null, // exeDirPath
  null, // dataDirPath
};

var pathBuffer: [fs.max_path_bytes]u8 = undefined;
var pathAllocator = std.heap.FixedBufferAllocator.init(&pathBuffer);

/// Returns a slice that is valid until the next call to a function in this file
pub fn getPath(relativePath: []const u8) ![:0]const u8
{
  findResourcePaths();

  pathAllocator.reset();

  for (resourcePaths) |resourcePath|
  {
    if (resourcePath) |dirPath|
    {
      const dirPathLen = std.mem.indexOfSentinel(u8, 0, dirPath[0..dirPath.len-1 :0]);
      log.info("checking dir \"{s}\"\n", .{dirPath[0..dirPathLen]});
      var dir = try fs.openDirAbsolute(dirPath[0..dirPathLen], .{});
      log.info("checking dir for subdirectory \"{s}\"\n", .{relativePath});
      dir.access(relativePath, .{}) catch continue;
      dir.close();

      // Normalize path separators to backslashes on Windows
      var normalizedPath = try pathAllocator.allocator().alloc(u8, relativePath.len);
      for (relativePath, 0..) |c, i| {
        normalizedPath[i] = if (c == '/') path.sep else c;
      }

      const resultPath: [:0]u8 = @ptrCast(try pathAllocator.allocator().alloc(u8, dirPathLen+1+normalizedPath.len+1));
      @memcpy(resultPath[0..dirPathLen], dirPath[0..dirPathLen]);
      resultPath[dirPathLen] = path.sep;
      @memcpy(resultPath[dirPathLen+1..dirPathLen+1+normalizedPath.len], normalizedPath);
      resultPath[dirPathLen+1+normalizedPath.len] = 0;

      const finalPath = resultPath[0..dirPathLen+1+normalizedPath.len :0];
      log.info("SUCCESS: Constructed path: \"{s}\"\n", .{finalPath});
      return finalPath;
    } else
    {
      log.info("skipping dir\n", .{});
    }
  }

  const dataDirPath = if (resourcePaths[2]) |dataPath| dataPath[0..std.mem.indexOfSentinel(u8, 0, dataPath[0..dataPath.len-1 :0])] else (&fs.path.sep)[0..1];
  fs.makeDirAbsolute(dataDirPath) catch |e| if (e != std.posix.MakeDirError.PathAlreadyExists) return e;
  var dataDir = try fs.openDirAbsolute(dataDirPath, .{.access_sub_paths = false});

  // Normalize path separators
  var normalizedPath = try pathAllocator.allocator().alloc(u8, relativePath.len);
  for (relativePath, 0..) |c, i| {
    normalizedPath[i] = if (c == '/') path.sep else c;
  }

  const lastSepIndex = std.mem.lastIndexOfScalar(u8, normalizedPath, path.sep) orelse {
    // No separator found, create file directly in dataDir
    const finalPath = try path.joinZ(pathAllocator.allocator(), &.{dataDirPath, normalizedPath});
    log.info("SUCCESS: Created path in dataDir (no sep): \"{s}\"\n", .{finalPath});
    return finalPath;
  };
  
  const relativePathDir = normalizedPath[0..lastSepIndex];
  try dataDir.makePath(relativePathDir);
  const finalPath = try path.joinZ(pathAllocator.allocator(), &.{dataDirPath, normalizedPath});
  log.info("SUCCESS: Created path in dataDir (with sep): \"{s}\"\n", .{finalPath});
  return finalPath;
}

fn findResourcePaths() void
{
  pathAllocator.reset();

  for (0..resourcePaths.len) |p|
  {
    resourcePaths[p] = std.mem.zeroes(@TypeOf(resourcePaths[p].?));
  }

  var pathSlice: []const u8 = undefined;

  pathSlice = fs.realpath(".", &pathBuffer) catch "";
  if (pathSlice.len > 0) @memcpy(resourcePaths[0].?[0..pathSlice.len], pathSlice) else resourcePaths[0] = null;

  pathSlice = fs.selfExeDirPath(&pathBuffer) catch "";
  if (pathSlice.len > 0) @memcpy(resourcePaths[1].?[0..pathSlice.len], pathSlice) else resourcePaths[1] = null;

  pathSlice = fs.getAppDataDir(pathAllocator.allocator(), "mission_bitcoin") catch "";
  if (pathSlice.len > 0) @memcpy(resourcePaths[2].?[0..pathSlice.len], pathSlice) else resourcePaths[2] = null;
}

fn openDataDir()
  (std.mem.Allocator.Error ||
   std.fs.File.OpenError ||
   std.fs.SelfExePathError)!Dir
{
  pathAllocator.reset();

  const dataDirName = fs.getAppDataDir(pathAllocator.allocator(), "mission_bitcoin") catch blk: {
    pathAllocator.reset();
    var exePathBuffer: [fs.max_path_bytes]u8 = undefined;

    break :blk try path.join(pathAllocator.allocator(), &.{
      fs.selfExeDirPath(&exePathBuffer) catch |e|
      {
        log.err("Failed to find app data folder {}\n", .{e});
        return e;
      },
      "mission_bitcoin"
    });
  };

  fs.makeDirAbsolute(dataDirName) catch |e|
  {
    if (e != Dir.MakeError.PathAlreadyExists)
    {
      log.warn("Failed to make user subfolder {}\n", .{e});
    }
  };

  log.debug("Opening dataDir \"{s}\"\n", .{dataDirName});
  const dataDir = try fs.openDirAbsolute(dataDirName, .{});

  return dataDir;
}

//const endianness = std.builtin.Endian.little;
//
///// Settings save file format:
/////
///// - Little endian
/////
///// Magic number: 'RBTs'
///// Settings file version code: u16
///// Flag settings: u32
///// Simulation speed: u32
//
//pub fn saveSettings() !void
//{
//  var dataDir = try openDataDir();
//  defer dataDir.close();
//
//  dataDir.makeDir("user") catch |e|
//  {
//    if (e != Dir.MakeError.PathAlreadyExists)
//    {
//      //log.warn("Failed to make user subfolder {}\n", .{e});
//    }
//  };
//
//  const settingsFile = dataDir.createFile("user" ++ (&path.sep)[0..1] ++ "settings.sav", .{.lock = .exclusive}) catch |e| {
//    //log.err("Failed to open gamestate file {}\n", .{e});
//    return e;
//  };
//  defer settingsFile.close();
//
//  pathAllocator.reset();
//
//  var settingsWriterBuffer: [64]u8 = undefined;
//  var settingsWriter = settingsFile.writer(&settingsWriterBuffer);
//  defer settingsWriter.interface.flush() catch {};
//
//  try settingsWriter.interface.writeAll("RBTs"); // Magic number
//  try settingsWriter.interface.writeInt(u16, 0, endianness); // File version
//}
//
//pub fn loadSettings() !void
//{
//  var dataDir = try openDataDir();
//  defer dataDir.close();
//
//  log.debug("dry wipe {s}\n", .{"user" ++ (&path.sep)[0..1] ++ "settings.sav"});
//  const settingsFile = dataDir.openFile("user" ++ (&path.sep)[0..1] ++ "settings.sav", .{.lock = .exclusive}) catch |e| {
//    log.err("Failed to open settings file: {}\n", .{e});
//    return e;
//  };
//  defer settingsFile.close();
//
//  pathAllocator.reset();
//
//  var settingsReaderBuffer: [64]u8 = undefined;
//  var settingsReader = settingsFile.reader(&settingsReaderBuffer);
//  //defer settingsReader.interface.flush() catch {};
//
//  if ((settingsReader.getSize() catch 0) >= 10)
//  {
//    _ = try settingsReader.interface.discard(.limited(4)); // Magic number
//    if (try settingsReader.interface.takeInt(u16, endianness) == 0) // File version
//    {
//    }
//  }
//}
//
///// Schematic save file format:
/////
///// - Little endian
/////
///// Magic number: 'RBTw' (Robot turtles world)
///// Schematic file version code: u16
///// Tile count: u32
///// Tile array:
/////   Array element:
/////     X position: i16
/////     Y position: i16
/////     Type: u4
/////     Color: u2
/////     Dir: u2
/////     If Type == Turtle:
/////       Program length: u32
/////       Function length: u32
/////       Instruction array:
/////         Array element:
/////           Instruction: u4
//pub fn saveSchematic(name: []const u8) !void
//{
//  log.debug("Saving schematic \"{s}\"\n", .{name});
//  var dataDir = try openDataDir();
//  defer dataDir.close();
//
//  dataDir.makePath("user" ++ (&path.sep)[0..1] ++ "schematics") catch |e|
//  {
//    if (e != Dir.MakeError.PathAlreadyExists)
//    {
//      log.warn("Failed to make user subfolder {}\n", .{e});
//    }
//  };
//  pathAllocator.reset();
//
//  const filename = try pathAllocator.allocator().alloc(u8, name.len + ".sav".len);
//  @memcpy(filename[0..name.len], name);
//  @memcpy(filename[name.len..], ".sav");
//
//  const schematicFile = dataDir.createFile(try path.join(pathAllocator.allocator(), &.{"user", "schematics", filename}), .{.lock = .exclusive}) catch |e|
//  {
//    log.err("Failed to open schematic file {}\n", .{e});
//    return e;
//  };
//  defer schematicFile.close();
//
//  pathAllocator.reset();
//}
//
//pub fn loadSchematic(name: []const u8) !void
//{
//  log.debug("Loading schematic \"{s}\"\n", .{name});
//  var dataDir = try openDataDir();
//  defer dataDir.close();
//
//  const filename = try pathAllocator.allocator().alloc(u8, name.len + ".sav".len);
//  @memcpy(filename[0..name.len], name);
//  @memcpy(filename[name.len..], ".sav");
//
//  const schematicFile = dataDir.openFile(try path.join(pathAllocator.allocator(), &.{"user", "schematics", filename}), .{.lock = .exclusive}) catch |e|
//  {
//    log.err("Failed to open schematic file {}\n", .{e});
//    return e;
//  };
//  defer schematicFile.close();
//
//  pathAllocator.reset();
//
//  for (mainspace.world.schem.items.values()) |tile|
//  {
//    if (tile.type == .Turtle)
//    {
//      mainspace.turtleCount += 1;
//    }
//  }
//}
//
///// Lists the names (no extension) of all schematic files in the save directory
//pub fn schematicNames() ![]const []const u8
//{
//  var dataDir = try openDataDir();
//  defer dataDir.close();
//
//  const schematicSubPath = "user" ++ (&path.sep)[0..1] ++ "schematics";
//  var schematicDir = dataDir.openDir(schematicSubPath, .{.iterate = true}) catch |e|
//  {
//    if (e == error.FileNotFound)
//    {
//      try dataDir.makePath(schematicSubPath);
//      return &.{};
//    } else
//    {
//      return e;
//    }
//  };
//
//  pathAllocator.reset();
//
//  var allocationSize: u32 = 0;
//  var fileCount: u16 = 0;
//
//  var it = try schematicDir.walk(pathAllocator.allocator());
//  while (try it.next()) |entry|
//  {
//    if (entry.kind == .file)
//    {
//      allocationSize += @intCast(@sizeOf([]const u8) + entry.path.len - 4);
//      fileCount += 1;
//    }
//  }
//  it.deinit();
//
//  const buffer = try pathAllocator.allocator().allocWithOptions(u8, allocationSize, .of([]u8), null);
//  var result: [][]u8 = undefined;
//  result.ptr = @ptrCast(buffer.ptr);
//  result.len = 0;
//
//  var stringIndex: u32 = fileCount * @sizeOf([]u8);
//
//  it = try schematicDir.walk(pathAllocator.allocator());
//  while (try it.next()) |entry|
//  {
//    if (entry.kind == .file)
//    {
//      result.len += 1;
//      result[result.len - 1] = buffer[stringIndex..stringIndex+entry.path.len-4];
//      @memcpy(result[result.len - 1], entry.path[0..entry.path.len-4]);
//
//      stringIndex += @intCast(entry.path.len-4);
//    }
//  }
//  it.deinit();
//
//  return result;
//}
