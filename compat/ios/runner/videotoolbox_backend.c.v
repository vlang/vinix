// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if ios_video ? {
	#include <libavcodec/avcodec.h>
	#include <libavutil/mem.h>
	#include <libswscale/swscale.h>
	@[typedef]
	struct C.AVCodec {}
	@[typedef]
	struct C.AVCodecContext {
	mut:
		extradata &u8
		extradata_size i32
		thread_count i32
		has_b_frames i32
	}
	@[typedef]
	struct C.AVPacket {
	mut:
		data &u8
		size i32
	}
	@[typedef]
	struct C.AVFrame {
		data [8]&u8
		linesize [8]i32
		width i32
		height i32
		format i32
		color_range i32
		colorspace i32
	}
	struct C.SwsContext {}
	fn C.avcodec_find_decoder_by_name(&char) &C.AVCodec
	fn C.avcodec_alloc_context3(&C.AVCodec) &C.AVCodecContext
	fn C.avcodec_open2(&C.AVCodecContext, &C.AVCodec, voidptr) i32
	fn C.avcodec_free_context(&&C.AVCodecContext)
	fn C.avcodec_flush_buffers(&C.AVCodecContext)
	fn C.avcodec_send_packet(&C.AVCodecContext, &C.AVPacket) i32
	fn C.avcodec_receive_frame(&C.AVCodecContext, &C.AVFrame) i32
	fn C.av_packet_alloc() &C.AVPacket
	fn C.av_new_packet(&C.AVPacket, i32) i32
	fn C.av_packet_unref(&C.AVPacket)
	fn C.av_packet_free(&&C.AVPacket)
	fn C.av_frame_alloc() &C.AVFrame
	fn C.av_frame_unref(&C.AVFrame)
	fn C.av_frame_free(&&C.AVFrame)
	fn C.av_mallocz(usize) voidptr
	fn C.sws_getCachedContext(&C.SwsContext, i32, i32, i32, i32, i32, i32, i32, voidptr, voidptr, voidptr) &C.SwsContext
	fn C.sws_getCoefficients(i32) &i32
	fn C.sws_setColorspaceDetails(&C.SwsContext, &i32, i32, &i32, i32, i32, i32, i32) i32
	fn C.sws_scale(&C.SwsContext, &&u8, &i32, i32, i32, &&u8, &i32) i32
	fn C.sws_freeContext(&C.SwsContext)
}

// The public session owns this backend. No FFmpeg structure layout is guessed:
// enabled builds compile these field accesses against their target's headers.
struct VTBackend {
mut:
	codec voidptr
	packet voidptr
	frame voidptr
	convert voidptr
}
fn vt_backend_close(mut backend VTBackend) {
	$if ios_video ? {
		if backend.convert != unsafe { nil } { C.sws_freeContext(backend.convert) }
		if backend.frame != unsafe { nil } { C.av_frame_free(unsafe { &&C.AVFrame(&backend.frame) }) }
		if backend.packet != unsafe { nil } { C.av_packet_free(unsafe { &&C.AVPacket(&backend.packet) }) }
		if backend.codec != unsafe { nil } { C.avcodec_free_context(unsafe { &&C.AVCodecContext(&backend.codec) }) }
	}
	backend = VTBackend{}
}
fn vt_backend_open(codec u32, config u64, size u64, mut backend VTBackend) i32 {
	$if ios_video ? {
		decoder := C.avcodec_find_decoder_by_name(if codec == 0x61766331 { c'h264' } else { c'hevc' })
		if decoder == unsafe { nil } { return -12906 }
		mut context := C.avcodec_alloc_context3(decoder)
		if context == unsafe { nil } { return -12904 }
		backend.codec = context
		context.extradata = C.av_mallocz(usize(size) + 64)
		if context.extradata == unsafe { nil } { vt_backend_close(mut backend); return -12904 }
		C.memcpy(context.extradata, unsafe { voidptr(config) }, usize(size))
		context.extradata_size = i32(size)
		context.thread_count = 1
		if C.avcodec_open2(context, decoder, unsafe { nil }) < 0 { vt_backend_close(mut backend); return -12909 }
		// This synchronous profile does not advertise codecs requiring reorder
		// queues. A successful decode always calls back before returning.
		if context.has_b_frames != 0 { vt_backend_close(mut backend); return -12906 }
		backend.packet = C.av_packet_alloc()
		backend.frame = C.av_frame_alloc()
		if backend.packet == unsafe { nil } || backend.frame == unsafe { nil } { vt_backend_close(mut backend); return -12904 }
		return 0
	}
	return -12906 // No software codec backend was selected for this build.
}
fn vt_backend_decode(mut backend VTBackend, bytes u64, count u64, output u64) i32 {
	$if ios_video ? {
		mut packet := unsafe { &C.AVPacket(backend.packet) }
		frame := unsafe { &C.AVFrame(backend.frame) }
		context := unsafe { &C.AVCodecContext(backend.codec) }
		C.av_packet_unref(packet)
		C.av_frame_unref(frame)
		if C.av_new_packet(packet, i32(count)) < 0 { return -12904 }
		C.memcpy(packet.data, unsafe { voidptr(bytes) }, usize(count))
		mut status := C.avcodec_send_packet(context, packet)
		C.av_packet_unref(packet)
		if status >= 0 { status = C.avcodec_receive_frame(context, frame) }
		if status < 0 || context.has_b_frames != 0 {
			C.avcodec_flush_buffers(context)
			C.av_frame_unref(frame)
			return -12909
		}
		defer { C.av_frame_unref(frame) }
		pixel := cv_pixel_state(output)
		if frame.width != i32(pixel.width) || frame.height != i32(pixel.height) { return -12910 }
		format := if pixel.format == 0x42475241 { i32(C.AV_PIX_FMT_BGRA) } else { i32(C.AV_PIX_FMT_NV12) }
		backend.convert = C.sws_getCachedContext(backend.convert, frame.width, frame.height, frame.format,
			frame.width, frame.height, format, C.SWS_BILINEAR, unsafe { nil }, unsafe { nil }, unsafe { nil })
		if backend.convert == unsafe { nil } { return -12904 }
		matrix := C.sws_getCoefficients(if frame.colorspace == 1 { 1 } else { 5 })
		if C.sws_setColorspaceDetails(backend.convert, matrix, i32(frame.color_range == 2), matrix,
			i32(pixel.format != 0x34323076), 0, 1 << 16, 1 << 16) < 0 { return -12910 }
		mut planes := [unsafe { &u8(nil) }, unsafe { &u8(nil) }, unsafe { &u8(nil) }, unsafe { &u8(nil) }]!
		mut strides := [4]i32{}
		if pixel.planes == 0 { planes[0] = unsafe { &u8(pixel.base) }; strides[0] = i32(pixel.stride) }
		else { for i in 0 .. 2 { planes[i] = unsafe { &u8(pixel.addresses[i]) }; strides[i] = i32(pixel.strides[i]) } }
		if C.sws_scale(backend.convert, unsafe { &&u8(&frame.data[0]) }, unsafe { &frame.linesize[0] },
			0, frame.height, unsafe { &&u8(&planes[0]) }, unsafe { &strides[0] }) != frame.height { return -12910 }
		return 0
	}
	return -12906
}
