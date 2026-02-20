const std = @import("std");
const crypto = std.crypto;
const http = std.http;
const constants = @import("constants.zig");

pub const KeyStorage = struct {
    const dir_name = ".orca";
    const pub_key_file = "id_ed25519.pub";
    const priv_key_file = "id_ed25519";
    const robot_id_file = "robot_id";

    fn getStoragePath(allocator: std.mem.Allocator) ![]u8 {
        const home_owned = std.process.getEnvVarOwned(allocator, "HOME") catch null;
        defer if (home_owned) |h| allocator.free(h);
        const home = home_owned orelse "/tmp";
        return std.fs.path.join(allocator, &.{ home, dir_name });
    }

    pub fn getRobotId(allocator: std.mem.Allocator) ![]u8 {
        const storage_path = try getStoragePath(allocator);
        defer allocator.free(storage_path);
        var dir = try std.fs.openDirAbsolute(storage_path, .{});
        defer dir.close();

        const file = try dir.openFile(robot_id_file, .{});
        defer file.close();

        var buf: [36]u8 = undefined;
        const size = try file.readAll(&buf);
        return allocator.dupe(u8, buf[0..size]);
    }

    pub fn signPayload(allocator: std.mem.Allocator, message: []const u8) ![64]u8 { // Note: Ed25519 signature is 64 bytes
        const storage_path = try getStoragePath(allocator);
        defer allocator.free(storage_path);

        var dir = try std.fs.openDirAbsolute(storage_path, .{});
        defer dir.close();

        // 1. Ed25519 SecretKey is 64 bytes. If stored as HEX, the file is 128 bytes.
        var hex_buffer: [crypto.sign.Ed25519.SecretKey.encoded_length * 2]u8 = undefined;
        const file = try dir.openFile(priv_key_file, .{});
        defer file.close();

        const amt = try file.readAll(&hex_buffer);
        if (amt < hex_buffer.len) return error.InvalidKeyLength;

        // 2. Decode the Hex string into actual bytes
        var secret_key_bytes: [crypto.sign.Ed25519.SecretKey.encoded_length]u8 = undefined;
        _ = try std.fmt.hexToBytes(&secret_key_bytes, &hex_buffer);

        // 3. Now this will work!
        const secretKey = try crypto.sign.Ed25519.SecretKey.fromBytes(secret_key_bytes);
        const keypair = try crypto.sign.Ed25519.KeyPair.fromSecretKey(secretKey);

        const sig = try keypair.sign(message, null);
        return sig.toBytes();
    }
};

const ProvisionPayload = struct {
    publicKey: []const u8,
};

pub fn provisionRobot(allocator: std.mem.Allocator, token: []const u8) !void {
    std.debug.print("Starting provisioning with token: {s}\n", .{token});

    // 1. Generate Ed25519 Keypair
    const kp = crypto.sign.Ed25519.KeyPair.generate();

    // 2. Prepare Storage
    const path = try KeyStorage.getStoragePath(allocator);
    defer allocator.free(path);
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var dir = try std.fs.openDirAbsolute(path, .{});
    defer dir.close();

    // 3. Save Private Key as hex (Restrict permissions: 600)
    const priv_hex = std.fmt.bytesToHex(&kp.secret_key.bytes, .lower);
    const priv_file = try dir.createFile(KeyStorage.priv_key_file, .{ .mode = 0o600 });
    try priv_file.writeAll(&priv_hex);
    priv_file.close();

    // 4. Save Public Key as hex
    const pub_hex = std.fmt.bytesToHex(&kp.public_key.bytes, .lower);
    const pub_file = try dir.createFile(KeyStorage.pub_key_file, .{});
    try pub_file.writeAll(&pub_hex);
    pub_file.close();

    std.debug.print("Keys generated and stored in {s}\n", .{path});

    // 5. Send Public Key to MotherApp
    try uploadPublicKey(allocator, dir, token, kp);
}

const ProvisionResponse = struct {
    robotId: []const u8,
};

fn uploadPublicKey(allocator: std.mem.Allocator, dir: std.fs.Dir, token: []const u8, key_pair: crypto.sign.Ed25519.KeyPair) !void {
    const base64_encoder = std.base64.standard.Encoder;

    // 1. Base64 encode the public key
    var pub_b64: [base64_encoder.calcSize(32)]u8 = undefined;
    _ = base64_encoder.encode(&pub_b64, &key_pair.public_key.bytes);

    // 2. Prepare the JSON body
    const payload = ProvisionPayload{
        .publicKey = &pub_b64,
    };

    var string: std.Io.Writer.Allocating = .init(allocator);
    defer string.deinit();
    try string.writer.print("{f}", .{std.json.fmt(payload, .{})});
    const json_bytes = string.written();

    // 3. Sign the JSON body and base64 encode the signature
    const sig_bytes = try KeyStorage.signPayload(allocator, json_bytes);
    var sig_b64: [base64_encoder.calcSize(64)]u8 = undefined;
    _ = base64_encoder.encode(&sig_b64, &sig_bytes);

    // 4. Setup HTTP Client
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();

    // 5. Execute Fetch
    const url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ constants.provision_base_url, token });
    defer allocator.free(url);
    const result = try client.fetch(.{
        .method = .POST,
        .location = .{ .url = url },
        .payload = json_bytes,
        .response_writer = &body.writer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
        .extra_headers = &.{
            .{ .name = "X-Signature", .value = &sig_b64 },
        },
    });

    // 6. Handle Response
    if (result.status != .ok) {
        std.debug.print("MotherApp upload failed with status: {d}\n", .{result.status});
        return error.UploadFailed;
    }

    // 7. Parse robot ID from response and save to disk
    const response_data = body.written();
    const parsed = std.json.parseFromSlice(ProvisionResponse, allocator, response_data, .{ .ignore_unknown_fields = true }) catch {
        std.debug.print("Failed to parse provision response: {s}\n", .{response_data});
        return error.InvalidResponse;
    };
    defer parsed.deinit();

    const robot_id_file = try dir.createFile(KeyStorage.robot_id_file, .{});
    defer robot_id_file.close();
    try robot_id_file.writeAll(parsed.value.robotId);

    std.debug.print("Successfully provisioned robot: {s}\n", .{parsed.value.robotId});
}

pub fn getPublicKeyHex(allocator: std.mem.Allocator) ![]u8 {
    const path = try KeyStorage.getStoragePath(allocator);
    defer allocator.free(path);
    var dir = try std.fs.openDirAbsolute(path, .{});
    defer dir.close();

    const pub_file = try dir.openFile(KeyStorage.pub_key_file, .{});
    defer pub_file.close();

    // File is already stored as hex
    var hex_buf: [crypto.sign.Ed25519.PublicKey.encoded_length * 2]u8 = undefined;
    _ = try pub_file.readAll(&hex_buf);

    return try allocator.dupe(u8, &hex_buf);
}
