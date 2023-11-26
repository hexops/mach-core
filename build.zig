const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach_glfw");
const gpu = @import("mach_gpu");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mach_gpu_dep = b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });
    const sysgpu_dep = b.dependency("mach_sysgpu", .{
        .target = target,
        .optimize = optimize,
    });
    const gamemode_dep = b.dependency("mach_gamemode", .{
        .target = target,
        .optimize = optimize,
    });
    const sysjs_dep = b.dependency("mach_sysjs", .{
        .target = target,
        .optimize = optimize,
    });
    const module = b.addModule("mach-core", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{ .name = "mach-gpu", .module = mach_gpu_dep.module("mach-gpu") },
            .{ .name = "mach-glfw", .module = mach_glfw_dep.module("mach-glfw") },
            .{ .name = "mach-sysgpu", .module = sysgpu_dep.module("mach-sysgpu") },
            .{ .name = "mach-gamemode", .module = gamemode_dep.module("mach-gamemode") },
            .{ .name = "mach-sysjs", .module = sysjs_dep.module("mach-sysjs") },
        },
    });

    if (target.getCpuArch() != .wasm32) {
        const main_tests = b.addTest(.{
            .name = "core-tests",
            .root_source_file = .{ .path = sdkPath("/src/main.zig") },
            .target = target,
            .optimize = optimize,
        });
        var iter = module.dependencies.iterator();
        while (iter.next()) |e| {
            main_tests.addModule(e.key_ptr.*, e.value_ptr.*);
        }
        link(b, main_tests);
        b.installArtifact(main_tests);

        const test_step = b.step("test", "run tests");
        test_step.dependOn(&b.addRunArtifact(main_tests).step);

        const install_docs = b.addInstallDirectory(.{
            .source_dir = main_tests.getEmittedDocs(),
            .install_dir = .prefix, // default build output prefix, ./zig-out
            .install_subdir = "docs",
        });
        const docs_step = b.step("docs", "Generate API docs");
        docs_step.dependOn(&install_docs.step);
    }

    try @import("build_examples.zig").build(b, optimize, target, module);
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
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

    pub const Platform = enum {
        native,
        web,

        pub fn fromTarget(target: std.Target) Platform {
            if (target.cpu.arch == .wasm32) return .web;
            return .native;
        }
    };

    pub fn init(
        app_builder: *std.Build,
        core_builder: *std.Build,
        options: struct {
            name: []const u8,
            src: []const u8,
            target: std.zig.CrossTarget,
            optimize: std.builtin.OptimizeMode,
            custom_entrypoint: ?[]const u8 = null,
            deps: ?[]const std.build.ModuleDependency = null,
            res_dirs: ?[]const []const u8 = null,
            watch_paths: ?[]const []const u8 = null,
            mach_core_mod: ?*std.Build.Module = null,
        },
    ) !App {
        const target = (try std.zig.system.NativeTargetInfo.detect(options.target)).target;
        const platform = Platform.fromTarget(target);

        var dependencies = std.ArrayList(std.build.ModuleDependency).init(app_builder.allocator);

        const mach_core_mod = options.mach_core_mod orelse app_builder.dependency("mach_core", .{
            .target = options.target,
            .optimize = options.optimize,
        }).module("mach-core");
        try dependencies.append(.{
            .name = "mach-core",
            .module = mach_core_mod,
        });

        if (options.deps) |app_deps| try dependencies.appendSlice(app_deps);

        const app_module = app_builder.createModule(.{
            .source_file = .{ .path = options.src },
            .dependencies = try dependencies.toOwnedSlice(),
        });

        const compile = blk: {
            if (platform == .web) {
                // wasm libraries should go into zig-out/www/
                app_builder.lib_dir = app_builder.fmt("{s}/www", .{app_builder.install_path});

                const lib = app_builder.addSharedLibrary(.{
                    .name = options.name,
                    .root_source_file = .{ .path = options.custom_entrypoint orelse sdkPath("/src/platform/wasm/main.zig") },
                    .target = options.target,
                    .optimize = options.optimize,
                    .main_mod_path = if (options.custom_entrypoint == null) .{ .path = sdkPath("/src") } else null,
                });
                lib.rdynamic = true;

                break :blk lib;
            } else {
                const exe = app_builder.addExecutable(.{
                    .name = options.name,
                    .root_source_file = .{ .path = options.custom_entrypoint orelse sdkPath("/src/platform/native/main.zig") },
                    .target = options.target,
                    .optimize = options.optimize,
                    .main_mod_path = if (options.custom_entrypoint == null) .{ .path = sdkPath("/src") } else null,
                });
                // TODO(core): figure out why we need to disable LTO: https://github.com/hexops/mach/issues/597
                exe.want_lto = false;
                break :blk exe;
            }
        };

        compile.addModule("mach-core", mach_core_mod);
        compile.addModule("app", app_module);

        // Installation step
        app_builder.installArtifact(compile);
        const install = app_builder.addInstallArtifact(compile, .{});
        if (options.res_dirs) |res_dirs| {
            for (res_dirs) |res| {
                const install_res = app_builder.addInstallDirectory(.{
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
                const install_js = app_builder.addInstallFileWithDir(
                    .{ .path = js },
                    std.build.InstallDir{ .custom = "www" },
                    std.fs.path.basename(js),
                );
                install.step.dependOn(&install_js.step);
            }
        }

        // Link dependencies
        if (platform != .web) {
            link(core_builder, compile);
        }

        const run = app_builder.addRunArtifact(compile);
        run.step.dependOn(&install.step);
        return .{
            .b = app_builder,
            .compile = compile,
            .install = install,
            .run = run,
            .name = options.name,
            .platform = platform,
            .res_dirs = options.res_dirs,
            .watch_paths = options.watch_paths,
        };
    }
};

pub fn link(core_builder: *std.Build, step: *std.build.CompileStep) void {
    @import("mach_glfw").link(core_builder.dependency("mach_glfw", .{
        .target = step.target,
        .optimize = step.optimize,
    }).builder, step);
    gpu.link(core_builder.dependency("mach_gpu", .{
        .target = step.target,
        .optimize = step.optimize,
    }).builder, step, .{}) catch unreachable;
}

comptime {
    const min_zig = std.SemanticVersion.parse("0.11.0") catch unreachable;
    if (builtin.zig_version.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ builtin.zig_version, min_zig }));
    }
}
