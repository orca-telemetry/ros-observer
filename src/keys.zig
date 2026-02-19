const std = @import("std");
const crypto = std.crypto;
const http = std.http;

const KeyStorage = struct {
    const dir_name = ".orca";
    const pub_key_file = "id_ed25519.pub";
    const priv_key_file = "id_ed25519";

    fn getStoragePath(allocator: std.mem.Allocator) ![]u8 {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch "/tmp";
        return std.fs.path.join(allocator, &.{ home, dir_name });
    }
};

const ProvisionPayload = struct {
    token: []const u8,
    public_key: []const u8,
};

pub fn provisionRobot(allocator: std.mem.Allocator, token: []const u8) !void {
    std.debug.print("Starting provisioning with token: {s}\n", .{token});

    // 1. Generate Ed25519 Keypair
    const kp = crypto.sign.Ed25519.KeyPair.generate();

    // 2. Prepare Storage
    const path = try KeyStorage.getStoragePath(allocator);
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const dir = try std.fs.openDirAbsolute(path, .{});

    // 3. Save Private Key (Restrict permissions: 600)
    const priv_file = try dir.createFile(KeyStorage.priv_key_file, .{ .mode = 0o600 });
    try priv_file.writeAll(&kp.secret_key.bytes);
    priv_file.close();

    // 4. Save Public Key
    const pub_file = try dir.createFile(KeyStorage.pub_key_file, .{});
    try pub_file.writeAll(&kp.public_key.bytes);
    pub_file.close();

    std.debug.print("Keys generated and stored in {f}\n", .{path});

    // 5. Send Public Key to MotherApp (Stubbed)
    try uploadPublicKey(allocator, token, kp.public_key.bytes);
}

fn uploadPublicKey(allocator: std.mem.Allocator, token: []const u8, pub_key: [32]u8) !void {
    // 1. Hex encode the public key
    var pub_hex: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&pub_hex, "{f}", .{std.fmt.bytesToHex(&pub_key, std.fmt.Case.upper)});

    // 2. Prepare the JSON body using your implementation
    const payload = ProvisionPayload{
        .token = token,
        .public_key = &pub_hex,
    };

    var string: std.io.Writer.Allocating = .init(allocator);
    defer string.deinit();
    try string.writer.print("{f}", .{std.json.fmt(payload, .{})});
    const json_bytes = string.written();

    // 3. Setup TLS Bundle
    var bundle = std.crypto.Certificate.Bundle{};
    defer bundle.deinit(allocator);
    try bundle.rescan(allocator);

    var client = http.Client{
        .allocator = allocator,
    };
    defer client.deinit();

    // 4. Setup response capture
    // Using the ResponseStorage struct from your FetchOptions
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    // 5. Execute Fetch
    // The fetch call handles the payload transmission and headers internally
    const result = try client.fetch(.{
        .method = .POST,
        .location = .{ .url = "https://api.motherapp.com/v1/provision" },
        .payload = json_bytes,
        .response_writer = &body.writer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .connection = .{ .override = "close" },
        },
    });

    // 6. Handle Response
    if (result.status != .ok) {
        std.debug.print("MotherApp upload failed with status: {d}\n", .{result.status});
        return error.UploadFailed;
    }

    // Access the response via the unmanaged list's slice
    std.debug.print("Successfully provisioned: {f}\n", .{body});
}

fn signData(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const path = try KeyStorage.getStoragePath(allocator);
    const dir = try std.fs.openDirAbsolute(path, .{});

    // 1. Read the private key
    const priv_key_file = try dir.openFile(KeyStorage.priv_key_file, .{});
    defer priv_key_file.close();

    var secret_key_bytes: [crypto.sign.Ed25519.secret_length]u8 = undefined;
    _ = try priv_key_file.readAll(&secret_key_bytes);

    const key_pair = try crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key_bytes);

    // 2. Create the signature
    const sig = try crypto.sign.Ed25519.sign(data, key_pair, null);

    // 3. Return as hex string
    return try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&sig)});
}
