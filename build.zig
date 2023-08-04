const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach_glfw");
const gpu_dawn = @import("mach_gpu_dawn");
const gpu = @import("mach_gpu").Sdk(.{
    .gpu_dawn = gpu_dawn,
});

pub var mach_glfw_import: []const u8 = "mach_gpu.mach_gpu_dawn.mach_glfw";

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    if (target.getCpuArch() != .wasm32) {
        const test_step = b.step("test", "run tests");
        test_step.dependOn(&(try testStep(b, optimize, target)).step);
    }

    try @import("build_examples.zig").build(b, optimize, target);
}

fn glfwLink(b: *std.Build, step: *std.build.CompileStep) void {
    const glfw_dep = b.dependency(mach_glfw_import, .{
        .target = step.target,
        .optimize = step.optimize,
    });
    step.linkLibrary(glfw_dep.artifact("mach-glfw"));
    step.addModule("glfw", glfw_dep.module("mach-glfw"));

    // TODO(build-system): Zig package manager currently can't handle transitive deps like this, so we need to use
    // these explicitly here:
    @import("glfw").addPaths(step);
    if (step.target.toTarget().isDarwin()) @import("xcode_frameworks").addPaths(b, step);
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

var _module: ?*std.build.Module = null;

pub fn module(b: *std.Build, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) *std.build.Module {
    if (_module) |m| return m;

    const gamemode_dep = b.dependency("mach_gamemode", .{});

    _module = b.createModule(.{
        .source_file = .{ .path = sdkPath("/src/main.zig") },
        .dependencies = &.{
            .{ .name = "gpu", .module = gpu.module(b) },
            .{ .name = "glfw", .module = b.dependency(mach_glfw_import, .{
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
    main_tests.addModule("glfw", b.dependency(mach_glfw_import, .{
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
                exe.addModule("glfw", b.dependency(mach_glfw_import, .{
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
            gpu.link(b, compile, .{}) catch return error.FailedToLinkGPU;
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

comptime {
    const min_zig = std.SemanticVersion.parse("0.11.0-dev.4410+76f7b40e1") catch unreachable;
    if (builtin.zig_version.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ builtin.zig_version, min_zig }));
    }
}
