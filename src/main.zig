const std = @import("std");
const c = @import("c.zig").c;
const keys = @import("keys.zig");
const ros_discovery = @import("ros_discovery.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "provision")) {
        if (args.len < 4 or !std.mem.eql(u8, args[2], "--token")) {
            std.debug.print("Error: provision requires --token <value>\n", .{});
            return;
        }
        try keys.provisionRobot(allocator, args[3]);
    } else if (std.mem.eql(u8, command, "discover")) {
        // Initialize RCL
        var context = c.rcl_get_zero_initialized_context();
        var init_options = c.rcl_get_zero_initialized_init_options();

        const alloc = c.rcutils_get_default_allocator();
        var ret = c.rcl_init_options_init(&init_options, alloc);
        if (ret != c.RCL_RET_OK) {
            std.debug.print("Failed to initialize init_options\n", .{});
            return error.RclInitFailed;
        }
        defer _ = c.rcl_init_options_fini(&init_options);

        ret = c.rcl_init(0, null, &init_options, &context);
        if (ret != c.RCL_RET_OK) {
            std.debug.print("Failed to initialize rcl\n", .{});
            return error.RclInitFailed;
        }
        defer _ = c.rcl_shutdown(&context);
        defer _ = c.rcl_context_fini(&context);

        // Create node
        var node = c.rcl_get_zero_initialized_node();
        const node_name = "network_discovery_node_zig";
        const node_namespace = "";

        var node_options = c.rcl_node_get_default_options();
        ret = c.rcl_node_init(&node, node_name, node_namespace, &context, &node_options);
        if (ret != c.RCL_RET_OK) {
            std.debug.print("Failed to initialize node\n", .{});
            return error.NodeInitFailed;
        }
        defer _ = c.rcl_node_fini(&node);

        std.debug.print("Network Discovery Node (Zig) started\n", .{});

        // Wait for DDS discovery to settle
        std.debug.print("Waiting for DDS discovery...\n", .{});
        std.Thread.sleep(2 * std.time.ns_per_s);

        try ros_discovery.runDiscovery(allocator, &node);
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: ros_observer <command> [options]
        \\
        \\Commands:
        \\  provision --token <T>   Generate keys and register with Orca
        \\  discover                Scan ROS 2 network and output JSON
        \\
    , .{});
}
