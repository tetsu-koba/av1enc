const std = @import("std");
const IVF = @import("ivf.zig");
const AV1Enc = @import("av1enc.zig").AV1Enc;

var running: bool = false;
var frame_count: u32 = 0;
var ivf_writer: IVF.IVFWriter = undefined;

pub fn I4202Av1(input_file: []const u8, output_file: []const u8, width: u32, height: u32, framerate: u32, bitrate: u32, keyframe_interval: u32) !void {
    const alc = std.heap.page_allocator;

    var yuv_file = try std.fs.cwd().openFile(input_file, .{});
    defer yuv_file.close();

    var outfile = try std.fs.cwd().createFile(output_file, .{});
    defer outfile.close();

    const framerate_den: u32 = 1;
    const ivf_header = IVF.IVFHeader{
        .signature = .{ 'D', 'K', 'I', 'F' },
        .version = 0,
        .header_size = 32,
        .fourcc = .{ 'A', 'V', '0', '1' }, //"AV01",
        .width = @intCast(width),
        .height = @intCast(height),
        .framerate_num = framerate,
        .framerate_den = framerate_den,
        .num_frames = 0,
        .unused = 0,
    };
    ivf_writer = try IVF.IVFWriter.init(outfile, &ivf_header);
    defer ivf_writer.deinit();

    const yuv_size = width * height * 3 / 2;
    const yuv_buf = try alc.alloc(u8, yuv_size);
    defer alc.free(yuv_buf);

    var av1enc = try AV1Enc.init(width, height, framerate, framerate_den, bitrate, keyframe_interval);
    defer av1enc.deinit();

    running = true;
    while (running) {
        if (yuv_size != try yuv_file.readAll(yuv_buf)) {
            break;
        }
        try av1enc.sendFrame(yuv_buf, &callback);
    }
    try av1enc.flush(&callback);
}

fn callback(encoded_data: []const u8) void {
    if (!running) {
        return;
    }
    ivf_writer.writeIVFFrame(encoded_data, frame_count) catch |err| {
        switch (err) {
            error.BrokenPipe => {},
            else => {
                std.log.err("frameHandle: {s}", .{@errorName(err)});
            },
        }
        running = false;
    };
    frame_count += 1;
}

pub fn main() !void {
    const usage = "Usage: {s} input_file output_file width height framerate kbps keyframe_interval\n";
    const alc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alc);
    defer std.process.argsFree(alc, args);

    if (args.len < 8) {
        std.debug.print(usage, .{args[0]});
        std.posix.exit(1);
    }
    const input_file = args[1];
    const output_file = args[2];
    const width = try std.fmt.parseInt(u32, args[3], 10);
    const height = try std.fmt.parseInt(u32, args[4], 10);
    const framerate = try std.fmt.parseInt(u32, args[5], 10);
    const bitrate = try std.fmt.parseInt(u32, args[6], 10) * 1000;
    const keyframe_interval = try std.fmt.parseInt(u32, args[7], 10);

    try I4202Av1(input_file, output_file, width, height, framerate, bitrate, keyframe_interval);
}
