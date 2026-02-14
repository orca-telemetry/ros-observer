const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("ros_observer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "ros_observer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ros_observer", .module = mod },
            },
        }),
    });

    // Link libc
    exe.root_module.link_libc = true;

    // Add include paths
    exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/ros/jazzy/include/rcl/" });
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
    exe.linkSystemLibrary("rcl");
    exe.linkSystemLibrary("rcutils");
    exe.linkSystemLibrary("rmw");
    exe.linkSystemLibrary("rmw_implementation");
    exe.linkSystemLibrary("rcl_yaml_param_parser");
    exe.linkSystemLibrary("rosidl_runtime_c");
    exe.linkSystemLibrary("rosidl_typesupport_c");
    exe.linkSystemLibrary("rosidl_typesupport_introspection_c");
    exe.linkSystemLibrary("dl"); // For dynamic loading

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
