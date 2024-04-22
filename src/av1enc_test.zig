const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;

const IVF = @import("ivf.zig");
const AV1Enc = @import("av1enc.zig").AV1Enc;

var frame_count: u32 = 0;
var ivf_writer: IVF.IVFWriter = undefined;

test "encode test" {
    try encode("testfiles/sample01.i420", "testfiles/output.ivf");
    try checkIVF("testfiles/output.ivf");
}

fn encode(input_file: []const u8, output_file: []const u8) !void {
    const alc = std.heap.page_allocator;

    var yuv_file = try std.fs.cwd().openFile(input_file, .{});
    defer yuv_file.close();

    var outfile = try std.fs.cwd().createFile(output_file, .{});
    defer outfile.close();

    const width: u32 = 160;
    const height: u32 = 120;
    const bitrate: u32 = 1000;
    const framerate_num: u32 = 15;
    const framerate_den: u32 = 1;
    const keyframe_interval: u32 = 60;

    const ivf_header = IVF.IVFHeader{
        .signature = .{ 'D', 'K', 'I', 'F' },
        .version = 0,
        .header_size = 32,
        .fourcc = .{ 'A', 'V', '0', '1' }, //"AV01",
        .width = width,
        .height = height,
        .framerate_num = framerate_num,
        .framerate_den = framerate_den,
        .num_frames = 0,
        .unused = 0,
    };
    ivf_writer = try IVF.IVFWriter.init(outfile, &ivf_header);
    defer ivf_writer.deinit();

    const yuv_size = width * height * 3 / 2;
    const yuv_buf = try alc.alloc(u8, yuv_size);
    defer alc.free(yuv_buf);

    var av1enc = try AV1Enc.init(width, height, framerate_num, framerate_den, bitrate, keyframe_interval);
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

fn checkIVF(filename: []const u8) !void {
    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();
    var reader = try IVF.IVFReader.init(file);
    defer reader.deinit();

    try testing.expectEqualSlices(u8, &reader.header.fourcc, "AV01");
    try testing.expect(reader.header.width == 160);
    try testing.expect(reader.header.height == 120);
    try testing.expect(reader.header.framerate_num == 15);
    try testing.expect(reader.header.framerate_den == 1);
    try testing.expect(reader.header.num_frames == 75);

    var frame_index: usize = 0;
    while (true) {
        var ivf_frame_header: IVF.IVFFrameHeader = undefined;
        reader.readIVFFrameHeader(&ivf_frame_header) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        try testing.expect(ivf_frame_header.timestamp == frame_index);

        // Skip the frame data according to frame_size
        try reader.skipFrame(ivf_frame_header.frame_size);

        frame_index += 1;
    }
}
