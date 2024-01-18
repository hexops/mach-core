const std = @import("std");
const core = @import("build.zig");
const sysgpu = @import("mach_sysgpu");

pub fn build(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
    mach_core_mod: *std.Build.Module,
) !void {
    try ensureDependencies(b.allocator);

    const Dependency = enum {
        zigimg,
        model3d,
        assets,

        pub fn dependency(
            dep: @This(),
            b2: *std.Build,
            target2: std.Build.ResolvedTarget,
            optimize2: std.builtin.OptimizeMode,
        ) std.Build.Module.Import {
            const path = switch (dep) {
                .zigimg => "examples/libs/zigimg/zigimg.zig",
                .assets => return std.Build.Module.Import{
                    .name = "assets",
                    .module = b2.dependency("mach_core_example_assets", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-core-example-assets"),
                },
                .model3d => return std.Build.Module.Import{
                    .name = "model3d",
                    .module = b2.dependency("mach_model3d", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-model3d"),
                },
            };
            return std.Build.Module.Import{
                .name = @tagName(dep),
                .module = b2.createModule(.{ .root_source_file = .{ .path = path } }),
            };
        }
    };

    inline for ([_]struct {
        name: []const u8,
        deps: []const Dependency = &.{},
        std_platform_only: bool = false,
        sysgpu: bool = false,
    }{
        .{ .name = "wasm-test" },
        .{ .name = "triangle" },
        .{ .name = "triangle-msaa" },
        .{ .name = "clear-color" },
        .{ .name = "procedural-primitives" },
        .{ .name = "boids" },
        .{ .name = "rotating-cube" },
        .{ .name = "pixel-post-process" },
        .{ .name = "two-cubes" },
        .{ .name = "instanced-cube" },
        .{ .name = "gen-texture-light" },
        .{ .name = "fractal-cube" },
        .{ .name = "map-async" },
        .{ .name = "rgb-quad" },
        .{
            .name = "pbr-basic",
            .deps = &.{ .model3d, .assets },
            .std_platform_only = true,
        },
        .{
            .name = "deferred-rendering",
            .deps = &.{ .model3d, .assets },
            .std_platform_only = true,
        },
        .{ .name = "textured-cube", .deps = &.{ .zigimg, .assets } },
        .{ .name = "textured-quad", .deps = &.{ .zigimg, .assets } },
        .{ .name = "sprite2d", .deps = &.{ .zigimg, .assets } },
        .{ .name = "image", .deps = &.{ .zigimg, .assets } },
        .{ .name = "image-blur", .deps = &.{ .zigimg, .assets } },
        .{ .name = "cubemap", .deps = &.{ .zigimg, .assets } },

        // sysgpu
        .{ .name = "boids", .sysgpu = true },
        .{ .name = "clear-color", .sysgpu = true },
        .{ .name = "cubemap", .deps = &.{ .zigimg, .assets }, .sysgpu = true },
        .{ .name = "deferred-rendering", .deps = &.{ .model3d, .assets }, .std_platform_only = true, .sysgpu = true },
        .{ .name = "fractal-cube", .sysgpu = true },
        .{ .name = "gen-texture-light", .sysgpu = true },
        .{ .name = "image-blur", .deps = &.{ .zigimg, .assets }, .sysgpu = true },
        .{ .name = "instanced-cube", .sysgpu = true },
        .{ .name = "map-async", .sysgpu = true },
        .{ .name = "pbr-basic", .deps = &.{ .model3d, .assets }, .std_platform_only = true, .sysgpu = true },
        .{ .name = "pixel-post-process", .sysgpu = true },
        .{ .name = "procedural-primitives", .sysgpu = true },
        .{ .name = "rotating-cube", .sysgpu = true },
        .{ .name = "sprite2d", .deps = &.{ .zigimg, .assets }, .sysgpu = true },
        .{ .name = "image", .deps = &.{ .zigimg, .assets }, .sysgpu = true },
        .{ .name = "textured-cube", .deps = &.{ .zigimg, .assets }, .sysgpu = true },
        .{ .name = "textured-quad", .deps = &.{ .zigimg, .assets }, .sysgpu = true },
        .{ .name = "triangle", .sysgpu = true },
        .{ .name = "triangle-msaa", .sysgpu = true },
        .{ .name = "two-cubes", .sysgpu = true },
        .{ .name = "rgb-quad", .sysgpu = true },
    }) |example| {
        // FIXME: this is workaround for a problem that some examples
        // (having the std_platform_only=true field) as well as zigimg
        // uses IO and depends on gpu-dawn which is not supported
        // in freestanding environments. So break out of this loop
        // as soon as any such examples is found. This does means that any
        // example which works on wasm should be placed before those who dont.
        if (example.std_platform_only)
            if (target.result.cpu.arch == .wasm32)
                break;

        var deps = std.ArrayList(std.Build.Module.Import).init(b.allocator);
        try deps.append(std.Build.Module.Import{
            .name = "zmath",
            .module = b.createModule(.{
                .root_source_file = .{ .path = "examples/zmath.zig" },
            }),
        });
        for (example.deps) |d| try deps.append(d.dependency(b, target, optimize));
        const cmd_name = if (example.sysgpu) "sysgpu-" ++ example.name else example.name;
        const app = try core.App.init(
            b,
            b,
            .{
                .name = cmd_name,
                .src = if (example.sysgpu)
                    "examples/sysgpu/" ++ example.name ++ "/main.zig"
                else
                    "examples/" ++ example.name ++ "/main.zig",
                .target = target,
                .optimize = optimize,
                .deps = deps.items,
                .watch_paths = if (example.sysgpu)
                    &.{"examples/sysgpu/" ++ example.name}
                else
                    &.{"examples/" ++ example.name},
                .mach_core_mod = mach_core_mod,
            },
        );

        for (example.deps) |dep| switch (dep) {
            .model3d => app.compile.linkLibrary(b.dependency("mach_model3d", .{
                .target = target,
                .optimize = optimize,
            }).artifact("mach-model3d")),
            else => {},
        };

        const install_step = b.step(cmd_name, "Install " ++ cmd_name);
        install_step.dependOn(&app.install.step);
        b.getInstallStep().dependOn(install_step);

        const run_step = b.step("run-" ++ cmd_name, "Run " ++ cmd_name);
        run_step.dependOn(&app.run.step);
    }
}

pub fn copyFile(src_path: []const u8, dst_path: []const u8) void {
    std.fs.cwd().makePath(std.fs.path.dirname(dst_path).?) catch unreachable;
    std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{}) catch unreachable;
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn ensureDependencies(allocator: std.mem.Allocator) !void {
    try optional_dependency.ensureGitRepoCloned(
        allocator,
        "https://github.com/slimsag/zigimg",
        "ad6ad042662856f55a4d67499f1c4606c9951031",
        sdkPath("/examples/libs/zigimg"),
    );
}

const optional_dependency = struct {
    fn ensureGitRepoCloned(allocator: std.mem.Allocator, clone_url: []const u8, revision: []const u8, dir: []const u8) !void {
        if (xIsEnvVarTruthy(allocator, "NO_ENSURE_SUBMODULES") or xIsEnvVarTruthy(allocator, "NO_ENSURE_GIT")) {
            return;
        }

        xEnsureGit(allocator);

        if (std.fs.openDirAbsolute(dir, .{})) |_| {
            const current_revision = try xGetCurrentGitRevision(allocator, dir);
            if (!std.mem.eql(u8, current_revision, revision)) {
                // Reset to the desired revision
                xExec(allocator, &[_][]const u8{ "git", "fetch" }, dir) catch |err| std.debug.print("warning: failed to 'git fetch' in {s}: {s}\n", .{ dir, @errorName(err) });
                try xExec(allocator, &[_][]const u8{ "git", "checkout", "--quiet", "--force", revision }, dir);
                try xExec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, dir);
            }
            return;
        } else |err| return switch (err) {
            error.FileNotFound => {
                std.log.info("cloning required dependency..\ngit clone {s} {s}..\n", .{ clone_url, dir });

                try xExec(allocator, &[_][]const u8{ "git", "clone", "-c", "core.longpaths=true", clone_url, dir }, ".");
                try xExec(allocator, &[_][]const u8{ "git", "checkout", "--quiet", "--force", revision }, dir);
                try xExec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, dir);
                return;
            },
            else => err,
        };
    }

    fn xExec(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
        var child = std.ChildProcess.init(argv, allocator);
        child.cwd = cwd;
        _ = try child.spawnAndWait();
    }

    fn xGetCurrentGitRevision(allocator: std.mem.Allocator, cwd: []const u8) ![]const u8 {
        const result = try std.ChildProcess.run(.{ .allocator = allocator, .argv = &.{ "git", "rev-parse", "HEAD" }, .cwd = cwd });
        allocator.free(result.stderr);
        if (result.stdout.len > 0) return result.stdout[0 .. result.stdout.len - 1]; // trim newline
        return result.stdout;
    }

    fn xEnsureGit(allocator: std.mem.Allocator) void {
        const argv = &[_][]const u8{ "git", "--version" };
        const result = std.ChildProcess.run(.{
            .allocator = allocator,
            .argv = argv,
            .cwd = ".",
        }) catch { // e.g. FileNotFound
            std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
            std.process.exit(1);
        };
        defer {
            allocator.free(result.stderr);
            allocator.free(result.stdout);
        }
        if (result.term.Exited != 0) {
            std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
            std.process.exit(1);
        }
    }

    fn xIsEnvVarTruthy(allocator: std.mem.Allocator, name: []const u8) bool {
        if (std.process.getEnvVarOwned(allocator, name)) |truthy| {
            defer allocator.free(truthy);
            if (std.mem.eql(u8, truthy, "true")) return true;
            return false;
        } else |_| {
            return false;
        }
    }

    fn xSdkPath(comptime suffix: []const u8) []const u8 {
        if (suffix[0] != '/') @compileError("suffix must be an absolute path");
        return comptime blk: {
            const root_dir = std.fs.path.dirname(@src().file) orelse ".";
            break :blk root_dir ++ suffix;
        };
    }
};
