// SPDX-License-Identifier: GPL-2.0-only
module tarstream

import os

$if !tarstream_fd_only ? {
	#flag -lz
	#include <zlib.h>
	#define vinix_boot_z_stream z_stream
}

@[typedef]
struct C.vinix_boot_z_stream {
mut:
	next_in   &u8
	avail_in  u32
	next_out  &u8
	avail_out u32
	total_out u64
}

@[c: 'zlibVersion']
fn C.vinix_boot_zlib_version() &char
@[c: 'inflateInit2_']
fn C.vinix_boot_inflate_init(&C.vinix_boot_z_stream, i32, &char, i32) i32
@[c: 'inflate']
fn C.vinix_boot_inflate(&C.vinix_boot_z_stream, i32) i32
@[c: 'inflateEnd']
fn C.vinix_boot_inflate_end(&C.vinix_boot_z_stream) i32

const boot_chunk = 64 * 1024

struct BootGzip {
mut:
	source   os.File
	inflater voidptr // z_stream stays at a stable address and is absent from descriptor-only builds
	input    []u8
	ended    bool
}

// Vinix boot inflates one gzip member using the size and CRC from its trailer.
// Keep this decoder separate from readers that support concatenated archives.
pub fn open_boot_ustar(path string) !Reader {
	$if tarstream_fd_only ? {
		return error('use a decompressed descriptor for this reader')
	} $else {
		mut gzip := &BootGzip{source: os.open(path)!, input: []u8{len: boot_chunk}}
		mut opened := false
		defer {
			if !opened {
				gzip.close()
				unsafe { free(gzip) }
			}
		}
		mut stream := &C.vinix_boot_z_stream{}
		// Use the gzip wrapper and zlib's maximum deflate window.
		if C.vinix_boot_inflate_init(stream, 15 + 16, C.vinix_boot_zlib_version(),
			i32(sizeof(C.vinix_boot_z_stream))) != C.Z_OK {
			unsafe { free(stream) }
			return error('cannot initialize ISO initramfs gzip decoder')
		}
		gzip.inflater = voidptr(stream)
		gzip.fill()!
		if stream.avail_in < 3 || gzip.input[0] != 0x1f || gzip.input[1] != 0x8b || gzip.input[2] != 8 {
			return error('ISO initramfs must be gzip-compressed')
		}
		opened = true
		return Reader{boot: gzip}
	}
}

fn (mut gzip BootGzip) fill() ! {
	$if !tarstream_fd_only ? {
		mut stream := unsafe { &C.vinix_boot_z_stream(gzip.inflater) }
		count := gzip.source.read(mut gzip.input) or {
			if err !is os.Eof { return err }
			0
		}
		stream.next_in = gzip.input.data
		stream.avail_in = u32(count)
	}
}

fn (mut gzip BootGzip) read(mut output []u8) !int {
	$if tarstream_fd_only ? {
		return error('archive stream is closed')
	} $else {
		if gzip.ended { return 0 }
		mut stream := unsafe { &C.vinix_boot_z_stream(gzip.inflater) }
		limit := u32(int_min(output.len, boot_chunk))
		stream.next_out = output.data
		stream.avail_out = limit
		for stream.avail_out != 0 && !gzip.ended {
			if stream.avail_in == 0 { gzip.fill()! }
			code := C.vinix_boot_inflate(stream, C.Z_NO_FLUSH)
			if stream.total_out > 0xffff_ffff {
				return error('ISO initramfs exceeds the boot gzip size limit')
			}
			match code {
				C.Z_OK {}
				C.Z_STREAM_END {
					if stream.avail_in == 0 { gzip.fill()! }
					if stream.avail_in != 0 { return error('data follows the ISO initramfs gzip member') }
					gzip.ended = true
				}
				C.Z_BUF_ERROR { return error('truncated ISO initramfs gzip stream') }
				else { return error('invalid ISO initramfs gzip stream') }
			}
		}
		return int(limit - stream.avail_out)
	}
}

// TAR can end before the gzip trailer reaches the decoder.
fn (mut gzip BootGzip) finish() ! {
	mut buffer := []u8{len: boot_chunk}
	defer { unsafe { buffer.free() } }
	for gzip.read(mut buffer)! != 0 {}
}

fn (mut gzip BootGzip) close() {
	$if !tarstream_fd_only ? {
		if gzip.inflater != unsafe { nil } {
			C.vinix_boot_inflate_end(unsafe { &C.vinix_boot_z_stream(gzip.inflater) })
			unsafe { free(gzip.inflater) }
		}
		gzip.source.close()
		unsafe { gzip.input.free() }
	}
}
