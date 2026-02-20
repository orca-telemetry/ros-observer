const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const exe = b.addExecutable(.{
        .name = "ros_observer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // strip all debug symbols (Crucial for size)
    exe.root_module.strip = false;

    // dead Code Elimination (Linker Garbage Collection)
    // This removes functions that are never called.
    exe.link_gc_sections = true;

    // Link libc
    exe.root_module.link_libc = true;

    // Add include paths
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rcl/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rcl/rcl/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rcutils/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rmw/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rcl_yaml_param_parser/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/type_description_interfaces/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rosidl_runtime_c/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/service_msgs/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/builtin_interfaces/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rosidl_typesupport_interface/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rosidl_dynamic_typesupport/" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rosidl_typesupport_introspection_c/" });

    // Add library search path
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/ros/jazzy/lib/" });

    // Add rpath so the executable can find ROS2 libraries at runtime
    exe.root_module.addRPath(.{ .cwd_relative = "/opt/ros/jazzy/lib/" });

    // Link against ROS2 libraries
    exe.root_module.linkSystemLibrary("rcl", .{});
    exe.root_module.linkSystemLibrary("rcutils", .{});
    exe.root_module.linkSystemLibrary("rmw", .{});
    exe.root_module.linkSystemLibrary("rmw_implementation", .{});
    exe.root_module.linkSystemLibrary("rcl_yaml_param_parser", .{});
    exe.root_module.linkSystemLibrary("rosidl_runtime_c", .{});
    exe.root_module.linkSystemLibrary("rosidl_typesupport_c", .{});
    exe.root_module.linkSystemLibrary("rosidl_typesupport_introspection_c", .{});
    exe.root_module.linkSystemLibrary("dl", .{}); // For dynamic loading

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
