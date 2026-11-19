//! Whether fx uses what a repository commits: its `.fx.json`, the profiles in
//! `.fx/agents/`, the skills in its skill folders, the servers in `.mcp.json`,
//! and project instructions such as AGENTS.md. On by default.
//!
//! A host that runs fx on a repository it does not trust, such as a coding
//! sandbox, turns it off with `"project_config": false` at the top of the
//! profile's `settings.json`, or with `FX_PROJECT_CONFIG=0` for a whole
//! process tree. The variable wins over the setting. A repository can never
//! turn it back on: the key is not project-safe, so a `.fx.json` that sets it
//! is ignored like any other profile-only key.
//!
//! Off, the repository's files stay readable to the agent as workspace data
//! through its tools; fx only stops taking configuration from them.
//!
//! The answer is read once per process, since the profile and the
//! environment are the process's own: every loader asks `allowed()`.

const std = @import("std");
const io_mod = @import("../shared/io.zig");
const profile_paths = @import("../shared/profile_paths.zig");

pub const setting_key = "project_config";
pub const env_var = "FX_PROJECT_CONFIG";

/// The largest profile settings file `config_runtime` reads.
const max_settings_bytes = 64 * 1024;

const unknown: u8 = 0;
const on: u8 = 1;
const off: u8 = 2;

var cached: std.atomic.Value(u8) = .init(unknown);

/// Whether fx may take configuration from the repository it works in.
pub fn allowed() bool {
    const value = cached.load(.acquire);
    if (value != unknown) return value == on;
    const resolved: u8 = if (resolve()) on else off;
    cached.store(resolved, .release);
    return resolved == on;
}

/// What `FX_PROJECT_CONFIG` says: `0`, `false`, or `off` turn it off, and
/// `1`, `true`, or `on` turn it on. Anything else says nothing.
pub fn parseEnv(raw: []const u8) ?bool {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "0") or std.ascii.eqlIgnoreCase(trimmed, "false") or std.ascii.eqlIgnoreCase(trimmed, "off")) return false;
    if (std.mem.eql(u8, trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "true") or std.ascii.eqlIgnoreCase(trimmed, "on")) return true;
    return null;
}

/// What a profile `settings.json` says at its top level: its
/// `project_config` boolean, or null when it has none or isn't an object.
pub fn parseSettings(text: []const u8) ?bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{}) catch return null;
    if (parsed != .object) return null;
    const value = parsed.object.get(setting_key) orelse return null;
    return if (value == .bool) value.bool else null;
}

fn resolve() bool {
    if (io_mod.getenv(env_var)) |raw| {
        if (parseEnv(raw)) |value| return value;
    }
    const home = io_mod.homeDir() orelse return true;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const path = profile_paths.settingsPath(alloc, home) catch return true;
    var file = io_mod.openExistingRegularFile(std.Io.Dir.cwd(), path, .read_only) catch return true;
    defer file.close(io_mod.getIo());
    const text = io_mod.readFileToEnd(alloc, &file, max_settings_bytes) catch return true;
    return parseSettings(text) orelse true;
}

// Tests never change the answer: tests run concurrently and share it. Test a
// gated loader through its variant that takes the decision as a parameter,
// such as `profiles.Roots.initFor` or `workspace_config.readFileFor`.

test "FX_PROJECT_CONFIG reads the words fx accepts" {
    try std.testing.expectEqual(false, parseEnv(" 0\n").?);
    try std.testing.expectEqual(false, parseEnv("FALSE").?);
    try std.testing.expectEqual(false, parseEnv("off").?);
    try std.testing.expectEqual(true, parseEnv("1").?);
    try std.testing.expectEqual(true, parseEnv("True").?);
    try std.testing.expect(parseEnv("") == null);
    try std.testing.expect(parseEnv("maybe") == null);
}

test "only a boolean at the profile's top level decides" {
    try std.testing.expectEqual(false, parseSettings("{\"project_config\":false}").?);
    try std.testing.expectEqual(true, parseSettings("{\"project_config\":true,\"model\":\"m\"}").?);
    try std.testing.expect(parseSettings("{\"project_config\":\"false\"}") == null);
    try std.testing.expect(parseSettings("{\"workspaces\":{\"/w\":{\"project_config\":false}}}") == null);
    try std.testing.expect(parseSettings("[]") == null);
    try std.testing.expect(parseSettings("not json") == null);
}
