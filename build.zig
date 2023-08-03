const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach_glfw");
const gpu_dawn = @import("libs/mach-gpu-dawn/build.zig");
const gpu = @import("libs/mach-gpu/build.zig").Sdk(.{
    .gpu_dawn = gpu_dawn,
});
pub const core = @import("build.zig").Sdk(.{
    .gpu = gpu,
    .gpu_dawn = gpu_dawn,
    .glfw = glfw,
});

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    if (target.getCpuArch() != .wasm32) {
        const test_step = b.step("test", "run tests");
        test_step.dependOn(&(try core.testStep(b, optimize, target)).step);
    }

    try @import("build_examples.zig").build(b, optimize, target);
}

fn glfwLink(b: *std.Build, step: *std.build.CompileStep) void {
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = step.target,
        .optimize = step.optimize,
    });
    step.linkLibrary(glfw_dep.artifact("mach-glfw"));
    step.addModule("glfw", glfw_dep.module("mach-glfw"));

    // TODO(build-system): Zig package manager currently can't handle transitive deps like this, so we need to use
    // these explicitly here:
    @import("glfw").addPaths(step);
    if (step.target.toTarget().isDarwin()) xcode_frameworks.addPaths(b, step);
    step.linkLibrary(b.dependency("vulkan_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("vulkan-headers"));
    step.linkLibrary(b.dependency("x11_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("x11-headers"));
    step.linkLibrary(b.dependency("wayland_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("wayland-headers"));
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

pub fn Sdk(comptime deps: anytype) type {
    return struct {
        pub const gpu_dawn = deps.gpu_dawn;

        var _module: ?*std.build.Module = null;

        pub fn module(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.Module {
            if (_module) |m| return m;

            const gamemode_dep = b.dependency("mach_gamemode", .{});

            _module = b.createModule(.{
                .source_file = .{ .path = sdkPath("/src/main.zig") },
                .dependencies = &.{
                    .{ .name = "gpu", .module = deps.gpu.module(b) },
                    .{ .name = "glfw", .module = b.dependency("mach_glfw", .{
                        .target = target,
                        .optimize = optimize,
                    }).module("mach-glfw") },
                    .{ .name = "gamemode", .module = gamemode_dep.module("mach-gamemode") },
                },
            });
            return _module.?;
        }

        pub fn testStep(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) !*std.build.RunStep {
            const main_tests = b.addTest(.{
                .name = "core-tests",
                .root_source_file = .{ .path = sdkPath("/src/main.zig") },
                .target = target,
                .optimize = optimize,
            });
            var iter = module(b, optimize, target).dependencies.iterator();
            while (iter.next()) |e| {
                main_tests.addModule(e.key_ptr.*, e.value_ptr.*);
            }
            main_tests.addModule("glfw", b.dependency("mach_glfw", .{
                .target = target,
                .optimize = optimize,
            }).module("mach-glfw"));
            glfwLink(b, main_tests);
            if (target.isLinux()) {
                const gamemode_dep = b.dependency("mach_gamemode", .{});
                main_tests.addModule("gamemode", gamemode_dep.module("mach-gamemode"));
            }
            main_tests.addIncludePath(.{ .path = sdkPath("/include") });
            b.installArtifact(main_tests);
            return b.addRunArtifact(main_tests);
        }

        pub const App = struct {
            b: *std.Build,
            name: []const u8,
            compile: *std.build.Step.Compile,
            install: *std.build.Step.InstallArtifact,
            run: *std.build.Step.Run,
            platform: Platform,
            res_dirs: ?[]const []const u8,
            watch_paths: ?[]const []const u8,
            sysjs_dep: ?*std.Build.Dependency,

            pub const Platform = enum {
                native,
                web,

                pub fn fromTarget(target: std.Target) Platform {
                    if (target.cpu.arch == .wasm32) return .web;
                    return .native;
                }
            };

            pub fn init(
                b: *std.Build,
                options: struct {
                    name: []const u8,
                    src: []const u8,
                    target: std.zig.CrossTarget,
                    optimize: std.builtin.OptimizeMode,
                    custom_entrypoint: ?[]const u8 = null,
                    deps: ?[]const std.build.ModuleDependency = null,
                    res_dirs: ?[]const []const u8 = null,
                    watch_paths: ?[]const []const u8 = null,
                    gpu_dawn_options: deps.gpu_dawn.Options = .{},
                },
            ) !App {
                const target = (try std.zig.system.NativeTargetInfo.detect(options.target)).target;
                const platform = Platform.fromTarget(target);

                var dependencies = std.ArrayList(std.build.ModuleDependency).init(b.allocator);
                try dependencies.append(.{ .name = "core", .module = module(b, options.optimize, options.target) });
                if (options.deps) |app_deps| try dependencies.appendSlice(app_deps);

                const app_module = b.createModule(.{
                    .source_file = .{ .path = options.src },
                    .dependencies = try dependencies.toOwnedSlice(),
                });

                const sysjs_dep = if (platform == .web) b.dependency("mach_sysjs", .{
                    .target = options.target,
                    .optimize = options.optimize,
                }) else null;

                const compile = blk: {
                    if (platform == .web) {
                        // wasm libraries should go into zig-out/www/
                        b.lib_dir = b.fmt("{s}/www", .{b.install_path});

                        const lib = b.addSharedLibrary(.{
                            .name = options.name,
                            .root_source_file = .{ .path = options.custom_entrypoint orelse sdkPath("/src/platform/wasm/main.zig") },
                            .target = options.target,
                            .optimize = options.optimize,
                        });
                        lib.rdynamic = true;
                        lib.addModule("sysjs", sysjs_dep.?.module("mach-sysjs"));

                        break :blk lib;
                    } else {
                        const exe = b.addExecutable(.{
                            .name = options.name,
                            .root_source_file = .{ .path = options.custom_entrypoint orelse sdkPath("/src/platform/native/main.zig") },
                            .target = options.target,
                            .optimize = options.optimize,
                        });
                        // TODO(core): figure out why we need to disable LTO: https://github.com/hexops/mach/issues/597
                        exe.want_lto = false;
                        exe.addModule("glfw", b.dependency("mach_glfw", .{
                            .target = exe.target,
                            .optimize = exe.optimize,
                        }).module("mach-glfw"));

                        if (target.os.tag == .linux) {
                            const gamemode_dep = b.dependency("mach_gamemode", .{});
                            exe.addModule("gamemode", gamemode_dep.module("mach-gamemode"));
                        }

                        break :blk exe;
                    }
                };

                if (options.custom_entrypoint == null) compile.main_pkg_path = .{ .path = sdkPath("/src") };
                compile.addModule("core", module(b, options.optimize, options.target));
                compile.addModule("app", app_module);

                // Installation step
                b.installArtifact(compile);
                const install = b.addInstallArtifact(compile, .{});
                if (options.res_dirs) |res_dirs| {
                    for (res_dirs) |res| {
                        const install_res = b.addInstallDirectory(.{
                            .source_dir = .{ .path = res },
                            .install_dir = install.dest_dir.?,
                            .install_subdir = std.fs.path.basename(res),
                            .exclude_extensions = &.{},
                        });
                        install.step.dependOn(&install_res.step);
                    }
                }
                if (platform == .web) {
                    inline for (.{ sdkPath("/src/platform/wasm/mach.js"), @import("mach_sysjs").getJSPath() }) |js| {
                        const install_js = b.addInstallFileWithDir(
                            .{ .path = js },
                            std.build.InstallDir{ .custom = "www" },
                            std.fs.path.basename(js),
                        );
                        install.step.dependOn(&install_js.step);
                    }
                }

                // Link dependencies
                if (platform != .web) {
                    glfwLink(b, compile);
                    deps.gpu.link(b, compile, .{ .gpu_dawn_options = options.gpu_dawn_options }) catch return error.FailedToLinkGPU;
                }

                const run = b.addRunArtifact(compile);
                run.step.dependOn(&install.step);
                return .{
                    .b = b,
                    .compile = compile,
                    .install = install,
                    .run = run,
                    .name = options.name,
                    .platform = platform,
                    .res_dirs = options.res_dirs,
                    .watch_paths = options.watch_paths,
                    .sysjs_dep = sysjs_dep,
                };
            }
        };
    };
}

// TODO(build-system): This is a workaround that we copy anywhere xcode_frameworks needs to be used.
// With the Zig package manager, it should be possible to remove this entirely and instead just
// write:
//
// ```
// step.linkLibrary(b.dependency("xcode_frameworks", .{
//     .target = step.target,
//     .optimize = step.optimize,
// }).artifact("xcode-frameworks"));
// @import("xcode_frameworks").addPaths(step);
// ```
//
// However, today this package cannot be imported with the Zig package manager due to `error: TarUnsupportedFileType`
// which would be fixed by https://github.com/ziglang/zig/pull/15382 - so instead for now you must
// copy+paste this struct into your `build.zig` and write:
//
// ```
// try xcode_frameworks.addPaths(b, step);
// ```
const xcode_frameworks = struct {
    pub fn addPaths(b: *std.Build, step: *std.build.CompileStep) void {
        // branch: mach
        xEnsureGitRepoCloned(b.allocator, "https://github.com/hexops/xcode-frameworks", "723aa55e9752c8c6c25d3413722b5fe13d72ac4f", xSdkPath("/zig-cache/xcode_frameworks")) catch |err| @panic(@errorName(err));

        step.addFrameworkPath(.{ .path = xSdkPath("/zig-cache/xcode_frameworks/Frameworks") });
        step.addSystemIncludePath(.{ .path = xSdkPath("/zig-cache/xcode_frameworks/include") });
        step.addLibraryPath(.{ .path = xSdkPath("/zig-cache/xcode_frameworks/lib") });
    }

    fn xEnsureGitRepoCloned(allocator: std.mem.Allocator, clone_url: []const u8, revision: []const u8, dir: []const u8) !void {
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

comptime {
    const min_zig = std.SemanticVersion.parse("0.11.0-dev.4410+76f7b40e1") catch unreachable;
    if (builtin.zig_version.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ builtin.zig_version, min_zig }));
    }
}
