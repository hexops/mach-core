const std = @import("std");
const core = @import("build.zig").core;

pub fn build(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    target: std.zig.CrossTarget,
    options: core.Options,
) !void {
    try ensureDependencies(b.allocator);

    const Dependency = enum {
        zmath,
        zigimg,
        model3d,
        assets,

        pub fn moduleDependency(
            dep: @This(),
            b2: *std.Build,
            target2: std.zig.CrossTarget,
            optimize2: std.builtin.OptimizeMode,
            gpu_dawn_options: core.gpu_dawn.Options,
        ) std.Build.ModuleDependency {
            _ = gpu_dawn_options;
            const path = switch (dep) {
                .zmath => return std.Build.ModuleDependency{
                    .name = @tagName(dep),
                    .module = zmath.package(b2, target2, optimize2, .{
                        .options = .{ .enable_cross_platform_determinism = true },
                    }).zmath,
                },
                .zigimg => "examples/libs/zigimg/zigimg.zig",
                .assets => return std.Build.ModuleDependency{
                    .name = "assets",
                    .module = b2.dependency("mach_core_example_assets", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-core-example-assets"),
                },
                .model3d => return std.Build.ModuleDependency{
                    .name = "model3d",
                    .module = b2.dependency("mach_model3d", .{
                        .target = target2,
                        .optimize = optimize2,
                    }).module("mach-model3d"),
                },
            };
            return std.Build.ModuleDependency{
                .name = @tagName(dep),
                .module = b2.createModule(.{ .source_file = .{ .path = path } }),
            };
        }
    };

    inline for ([_]struct {
        name: []const u8,
        deps: []const Dependency = &.{},
        std_platform_only: bool = false,
    }{
        .{ .name = "triangle" },
        .{ .name = "triangle-msaa" },
        .{ .name = "clear-color" },
        .{ .name = "procedural-primitives", .deps = &.{.zmath} },
        .{ .name = "boids" },
        .{ .name = "rotating-cube", .deps = &.{.zmath} },
        .{ .name = "pixel-post-process", .deps = &.{.zmath} },
        .{ .name = "two-cubes", .deps = &.{.zmath} },
        .{ .name = "instanced-cube", .deps = &.{.zmath} },
        .{ .name = "advanced-gen-texture-light", .deps = &.{.zmath} },
        .{ .name = "fractal-cube", .deps = &.{.zmath} },
        .{ .name = "map-async", .deps = &.{} },
        .{
            .name = "pbr-basic",
            .deps = &.{ .zmath, .model3d, .assets },
            .std_platform_only = true,
        },
        .{
            .name = "deferred-rendering",
            .deps = &.{ .zmath, .model3d, .assets },
            .std_platform_only = true,
        },
        .{ .name = "textured-cube", .deps = &.{ .zmath, .zigimg, .assets } },
        .{ .name = "sprite2d", .deps = &.{ .zmath, .zigimg, .assets } },
        .{ .name = "image-blur", .deps = &.{ .zigimg, .assets } },
        .{ .name = "cubemap", .deps = &.{ .zmath, .zigimg, .assets } },
    }) |example| {
        // FIXME: this is workaround for a problem that some examples
        // (having the std_platform_only=true field) as well as zigimg
        // uses IO and depends on gpu-dawn which is not supported
        // in freestanding environments. So break out of this loop
        // as soon as any such examples is found. This does means that any
        // example which works on wasm should be placed before those who dont.
        if (example.std_platform_only)
            if (target.getCpuArch() == .wasm32)
                break;

        var deps = std.ArrayList(std.Build.ModuleDependency).init(b.allocator);
        for (example.deps) |d| try deps.append(d.moduleDependency(b, target, optimize, options.gpu_dawn_options));
        const app = try core.App.init(
            b,
            .{
                .name = example.name,
                .src = "examples/" ++ example.name ++ "/main.zig",
                .target = target,
                .optimize = optimize,
                .deps = deps.items,
                .watch_paths = &.{"examples/" ++ example.name},
            },
        );

        try app.link(options);
        for (example.deps) |dep| switch (dep) {
            .model3d => app.step.linkLibrary(b.dependency("mach_model3d", .{
                .target = target,
                .optimize = optimize,
            }).artifact("mach-model3d")),
            else => {},
        };
        app.install();

        const compile_step = b.step(example.name, "Compile " ++ example.name);
        compile_step.dependOn(&app.getInstallStep().?.step);

        const run_cmd = app.addRunArtifact();
        run_cmd.step.dependOn(compile_step);
        const run_step = b.step("run-" ++ example.name, "Run " ++ example.name);
        run_step.dependOn(&run_cmd.step);
    }

    const compile_all = b.step("compile-all", "Compile all examples and applications");
    compile_all.dependOn(b.getInstallStep());
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
        "https://github.com/machlibs/zmath",
        "6ae0a60392d68165bf2f61c42f137c7bd5dc8ae2",
        sdkPath("/examples/libs/zmath"),
    );
    try optional_dependency.ensureGitRepoCloned(
        allocator,
        "https://github.com/slimsag/zigimg",
        "814064a8935dceee99adb11f2b17871b84f75a2b",
        sdkPath("/examples/libs/zigimg"),
    );
}

const zmath = struct {
    pub const Options = struct {
        enable_cross_platform_determinism: bool = true,
    };

    pub const Package = struct {
        options: Options,
        zmath: *std.Build.Module,
        zmath_options: *std.Build.Module,

        pub fn link(pkg: Package, exe: *std.Build.CompileStep) void {
            exe.addModule("zmath", pkg.zmath);
            exe.addModule("zmath_options", pkg.zmath_options);
        }
    };

    pub fn package(
        b: *std.Build,
        _: std.zig.CrossTarget,
        _: std.builtin.Mode,
        args: struct {
            options: Options = .{},
        },
    ) Package {
        const step = b.addOptions();
        step.addOption(
            bool,
            "enable_cross_platform_determinism",
            args.options.enable_cross_platform_determinism,
        );

        const zmath_options = step.createModule();

        const zmath_mod = b.createModule(.{
            .source_file = .{ .path = thisDir() ++ "/examples/libs/zmath/src/main.zig" },
            .dependencies = &.{
                .{ .name = "zmath_options", .module = zmath_options },
            },
        });

        return .{
            .options = args.options,
            .zmath = zmath_mod,
            .zmath_options = zmath_options,
        };
    }

    inline fn thisDir() []const u8 {
        return comptime std.fs.path.dirname(@src().file) orelse ".";
    }
};

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
        const result = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = &.{ "git", "rev-parse", "HEAD" }, .cwd = cwd });
        allocator.free(result.stderr);
        if (result.stdout.len > 0) return result.stdout[0 .. result.stdout.len - 1]; // trim newline
        return result.stdout;
    }

    fn xEnsureGit(allocator: std.mem.Allocator) void {
        const argv = &[_][]const u8{ "git", "--version" };
        const result = std.ChildProcess.exec(.{
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
