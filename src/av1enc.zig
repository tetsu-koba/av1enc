const std = @import("std");
const log = std.log;
const rav1e = @cImport(@cInclude("rav1e.h"));

pub const AV1Enc = struct {
    width: u32,
    height: u32,
    framerate_num: u32,
    framerate_den: u32,
    bitrate: u32,
    keyframe_interval: u32,
    config: *rav1e.RaConfig,
    encoder: *rav1e.RaContext,

    const Self = @This();

    pub fn init(
        width: u32,
        height: u32,
        framerate_num: u32,
        framerate_den: u32,
        bitrate: u32,
        keyframe_interval: u32,
    ) !AV1Enc {
        var self = AV1Enc{
            .width = width,
            .height = height,
            .framerate_num = framerate_num,
            .framerate_den = framerate_den,
            .bitrate = bitrate,
            .keyframe_interval = keyframe_interval,
            .config = undefined,
            .encoder = undefined,
        };
        const config: ?*rav1e.RaConfig = rav1e.rav1e_config_default();
        if (config) |c| {
            self.config = c;
        } else {
            log.err("Failed to create config", .{});
            return error.FailedToCreateConfig;
        }

        _ = rav1e.rav1e_config_parse_int(config, "width", @intCast(width));
        _ = rav1e.rav1e_config_parse_int(config, "height", @intCast(height));
        _ = rav1e.rav1e_config_parse_int(config, "key_frame_interval", @intCast(keyframe_interval));
        _ = rav1e.rav1e_config_parse_int(config, "bitrate", @intCast(bitrate));
        _ = rav1e.rav1e_config_parse_int(config, "speed", 9);
        if (0 != rav1e.rav1e_config_parse(config, "low_latency", "true")) {
            log.err("Failed to config low_latency", .{});
        }

        const encoder: ?*rav1e.RaContext = rav1e.rav1e_context_new(config);
        if (encoder) |e| {
            self.encoder = e;
        } else {
            log.err("Failed to create encoder", .{});
            return error.FailedToCreateEncoder;
        }
        return self;
    }

    pub fn deinit(self: *Self) void {
        rav1e.rav1e_context_unref(self.encoder);
        rav1e.rav1e_config_unref(self.config);
    }

    pub fn sendFrame(self: *Self, frame_data: []const u8, cb: *const fn ([]const u8) void) !void {
        const frame = rav1e.rav1e_frame_new(self.encoder);
        if (frame == null) {
            log.err("Failed to create frame", .{});
            return error.FailedToCreateFrame;
        }
        defer rav1e.rav1e_frame_unref(frame);

        const w = self.width;
        const h = self.height;
        rav1e.rav1e_frame_fill_plane(frame, 0, frame_data.ptr, w * h, w, 1);
        rav1e.rav1e_frame_fill_plane(frame, 1, frame_data.ptr + w * h, w * h / 4, w / 2, 1);
        rav1e.rav1e_frame_fill_plane(frame, 2, frame_data.ptr + w * h * 5 / 4, w * h / 4, w / 2, 1);

        const status = rav1e.rav1e_send_frame(self.encoder, frame);
        if (status != rav1e.RA_ENCODER_STATUS_SUCCESS) {
            log.err("Failed to send frame: {}", .{status});
            return error.FailedToSendFrame;
        }

        while (true) {
            var packet: ?*rav1e.RaPacket = undefined;
            const sts = rav1e.rav1e_receive_packet(self.encoder, &packet);

            if (sts == rav1e.RA_ENCODER_STATUS_SUCCESS) {
                if (packet) |p| {
                    cb(p.data[0..p.len]);
                    rav1e.rav1e_packet_unref(packet);
                }
            } else if (sts == rav1e.RA_ENCODER_STATUS_ENCODED) {
                //log.info("Encoded", .{});
                continue;
            } else if (sts == rav1e.RA_ENCODER_STATUS_NEED_MORE_DATA) {
                //log.info("Need more data", .{});
                break;
            } else {
                log.err("Failed to receive packet: {}", .{sts});
                return error.FailedToReceivePacket;
            }
        }
    }

    pub fn flush(self: *Self, cb: *const fn ([]const u8) void) !void {
        const flush_status = rav1e.rav1e_send_frame(self.encoder, null);
        if (flush_status != rav1e.RA_ENCODER_STATUS_SUCCESS) {
            log.err("Failed to send null frame: {}", .{flush_status});
            return error.FailedToSendNullFrame;
        }

        while (true) {
            var packet: ?*rav1e.RaPacket = undefined;
            const status = rav1e.rav1e_receive_packet(self.encoder, &packet);

            if (status == rav1e.RA_ENCODER_STATUS_SUCCESS) {
                if (packet) |p| {
                    cb(p.data[0..p.len]);
                    rav1e.rav1e_packet_unref(packet);
                }
            } else if (status == rav1e.RA_ENCODER_STATUS_ENCODED) {
                //log.info("Encoded", .{});
                continue;
            } else if (status == rav1e.RA_ENCODER_STATUS_LIMIT_REACHED) {
                //log.info("Limit reached", .{});
                break;
            } else {
                log.err("Failed to receive packet: {}", .{status});
                return error.FailedToReceivePacket;
            }
        }
    }
};
