const std = @import("std");
const IVF = @import("ivf.zig");
const AV1Enc = @import("av1enc.zig").AV1Enc;

var frame_count: u32 = 0;
var ivf_writer: IVF.IVFWriter = undefined;

pub fn I4202Av1(input_file: []const u8, output_file: []const u8, width: u16, height: u16, framerate: u32, bitrate: u32, keyframe_interval: u32) !void {
    const alc = std.heap.page_allocator;

    var yuv_file = try std.fs.cwd().openFile(input_file, .{});
    defer yuv_file.close();

    var outfile = try std.fs.cwd().createFile(output_file, .{});
    defer outfile.close();

    const time_scale: u32 = 1;
    const ivf_header = IVF.IVFHeader{
        .signature = .{ 'D', 'K', 'I', 'F' },
        .version = 0,
        .header_size = 32,
        .fourcc = .{ 'A', 'V', '0', '1' }, //"AV01",
        .width = width,
        .height = height,
        .frame_rate = framerate,
        .time_scale = time_scale,
        .num_frames = 0,
        .unused = 0,
    };
    ivf_writer = try IVF.IVFWriter.init(outfile, &ivf_header);
    defer ivf_writer.deinit();

    const yuv_size = width * height * 3 / 2;
    var yuv_buf = try alc.alloc(u8, yuv_size);
    defer alc.free(yuv_buf);

    var av1enc = try AV1Enc.init(width, height, framerate, time_scale, bitrate, keyframe_interval);
    defer av1enc.deinit();

    while (true) {
        if (yuv_size != try yuv_file.readAll(yuv_buf)) {
            break;
        }
        try av1enc.sendFrame(yuv_buf, &callback);
    }
    try av1enc.flush(&callback);
}

fn callback(encoded_data: []const u8) void {
    ivf_writer.writeIVFFrame(encoded_data, frame_count) catch |err| {
        std.debug.print("callback: {s}\n", .{@errorName(err)});
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
        std.os.exit(1);
    }
    const input_file = std.mem.sliceTo(args[1], 0);
    const output_file = std.mem.sliceTo(args[2], 0);
    const width = try std.fmt.parseInt(u16, args[3], 10);
    const height = try std.fmt.parseInt(u16, args[4], 10);
    const framerate = try std.fmt.parseInt(u32, args[5], 10);
    const bitrate = try std.fmt.parseInt(u32, args[6], 10) * 1000;
    const keyframe_interval = try std.fmt.parseInt(u32, args[7], 10);

    try I4202Av1(input_file, output_file, width, height, framerate, bitrate, keyframe_interval);
}
