// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Vinix Capture: a native ui2 front end and compositor-owned screen recorder.
//
// The app remains an ordinary application process. Its small request/report
// state crosses app_process.v with the rest of the desktop state, while the
// compositor writes its own Canvas after presentation. That keeps framebuffer
// ownership in one process and guarantees that saved pixels are exactly the
// pixels the user saw. PNG and uncompressed AVI are emitted here directly;
// no X11, toolkit, image library or media process is involved.
module main

import ui2

const capture_app_title = 'Capture'

const capture_action_screenshot_tab = 'capture.tab.screenshot'
const capture_action_video_tab = 'capture.tab.video'
const capture_action_delay_0 = 'capture.delay.0'
const capture_action_delay_3 = 'capture.delay.3'
const capture_action_delay_5 = 'capture.delay.5'
const capture_action_fps_5 = 'capture.fps.5'
const capture_action_fps_10 = 'capture.fps.10'
const capture_action_take_screenshot = 'capture.screenshot'
const capture_action_start_video = 'capture.video.start'
const capture_action_stop = 'capture.stop'

const capture_video_max_width = 640
const capture_video_max_height = 480
const capture_avi_file_limit = u64(1_900_000_000)

enum CaptureCommand {
	none_
	screenshot
	start_video
	stop
}

enum CapturePhase {
	idle
	screenshot_countdown
	video_countdown
	recording
	screenshot_saved
	video_saved
	failed
	cancelled
}

enum CapturePage {
	screenshot
	video
}

enum CaptureFrameKind {
	none_
	screenshot
	video_start
	video_frame
}

enum CaptureFileKind {
	screenshot
	video
}

struct CaptureRequest {
	sequence u32
	command  CaptureCommand
	delay    int
	fps      int
}

struct CaptureReport {
mut:
	handled_sequence u32
	phase            CapturePhase
	file_id          u64
	started_ms       u64
	elapsed_ms       u64
	frames           int
	width            int
	height           int
	fps              int
}

struct AviWriter {
mut:
	fd                   int = -1
	width                int
	height               int
	fps                  int
	row_stride           int
	frame_size           int
	frames               int
	max_frames           int
	bytes_written        u64
	riff_size_offset     int
	total_frames_offset  int
	stream_length_offset int
	movi_size_offset     int
	frame_offsets        []u32
	frame                []u8
}

struct CaptureService {
mut:
	request         CaptureRequest
	report          CaptureReport
	due_ms          u64
	last_frame_ms   u64
	last_file_id    u64
	owner_window_id int
	pending_frame   CaptureFrameKind
	writer          AviWriter
}

// ── Portable PNG writer ───────────────────────────────────────────

fn capture_put_be32(mut out []u8, value u32) {
	out << u8(value >> 24)
	out << u8(value >> 16)
	out << u8(value >> 8)
	out << u8(value)
}

fn capture_put_le16(mut out []u8, value u16) {
	out << u8(value)
	out << u8(value >> 8)
}

fn capture_put_le32(mut out []u8, value u32) {
	out << u8(value)
	out << u8(value >> 8)
	out << u8(value >> 16)
	out << u8(value >> 24)
}

fn capture_patch_le32(mut out []u8, offset int, value u32) {
	if offset < 0 || offset + 4 > out.len {
		return
	}
	out[offset] = u8(value)
	out[offset + 1] = u8(value >> 8)
	out[offset + 2] = u8(value >> 16)
	out[offset + 3] = u8(value >> 24)
}

fn capture_put_fourcc(mut out []u8, value string) {
	for index := 0; index < 4; index++ {
		out << if index < value.len { value[index] } else { u8(0) }
	}
}

fn capture_crc32(data []u8) u32 {
	mut crc := ~u32(0)
	for byte in data {
		crc ^= u32(byte)
		for _ in 0 .. 8 {
			crc = if crc & 1 != 0 { (crc >> 1) ^ u32(0xedb88320) } else { crc >> 1 }
		}
	}
	return ~crc
}

fn capture_adler32(data []u8) u32 {
	mut a := u32(1)
	mut b := u32(0)
	for byte in data {
		a = (a + u32(byte)) % 65521
		b = (b + a) % 65521
	}
	return b << 16 | a
}

fn capture_png_chunk(mut out []u8, kind string, data []u8) {
	capture_put_be32(mut out, u32(data.len))
	crc_start := out.len
	capture_put_fourcc(mut out, kind)
	out << data
	capture_put_be32(mut out, capture_crc32(out[crc_start..]))
}

fn capture_png_bytes(canvas &Canvas) ![]u8 {
	if canvas.pixels == unsafe { nil } || canvas.width <= 0 || canvas.height <= 0
		|| canvas.width > 16384 || canvas.height > 16384 {
		return error('invalid capture canvas')
	}
	row_size := canvas.width * 3 + 1
	raw_size := row_size * canvas.height
	mut raw := []u8{len: raw_size}
	defer {
		unsafe { raw.free() }
	}
	for y := 0; y < canvas.height; y++ {
		row := y * row_size
		raw[row] = 0 // PNG filter: None
		for x := 0; x < canvas.width; x++ {
			pixel := unsafe { canvas.pixels[y * canvas.stride + x] }
			offset := row + 1 + x * 3
			raw[offset] = u8(pixel >> 16)
			raw[offset + 1] = u8(pixel >> 8)
			raw[offset + 2] = u8(pixel)
		}
	}

	blocks := (raw.len + 65534) / 65535
	mut compressed := []u8{cap: raw.len + blocks * 5 + 6}
	defer {
		unsafe { compressed.free() }
	}
	// A zlib stream whose DEFLATE blocks are stored rather than compressed.
	// This is intentionally simple and bounded: the file remains a standard
	// PNG, while the desktop needs no compression runtime in its initramfs.
	compressed << u8(0x78)
	compressed << u8(0x01)
	mut offset := 0
	for offset < raw.len {
		remaining := raw.len - offset
		length := if remaining > 65535 { 65535 } else { remaining }
		compressed << if offset + length == raw.len { u8(1) } else { u8(0) }
		capture_put_le16(mut compressed, u16(length))
		capture_put_le16(mut compressed, ~u16(length))
		compressed << raw[offset..offset + length]
		offset += length
	}
	capture_put_be32(mut compressed, capture_adler32(raw))

	mut ihdr := []u8{cap: 13}
	defer {
		unsafe { ihdr.free() }
	}
	capture_put_be32(mut ihdr, u32(canvas.width))
	capture_put_be32(mut ihdr, u32(canvas.height))
	ihdr << u8(8) // bit depth
	ihdr << u8(2) // truecolour
	ihdr << u8(0) // compression
	ihdr << u8(0) // filter
	ihdr << u8(0) // no interlace

	mut png := []u8{cap: 8 + 25 + compressed.len + 24}
	png << [u8(0x89), `P`, `N`, `G`, `\r`, `\n`, 0x1a, `\n`]
	capture_png_chunk(mut png, 'IHDR', ihdr)
	capture_png_chunk(mut png, 'IDAT', compressed)
	capture_png_chunk(mut png, 'IEND', []u8{})
	return png
}

fn capture_write_png(path string, canvas &Canvas) bool {
	bytes := capture_png_bytes(canvas) or { return false }
	ok := desktop_write_file(path, bytes.data, u64(bytes.len))
	unsafe { bytes.free() }
	return ok
}

// ── Portable AVI writer ───────────────────────────────────────────

fn capture_begin_chunk(mut out []u8, kind string) int {
	capture_put_fourcc(mut out, kind)
	size_offset := out.len
	capture_put_le32(mut out, 0)
	return size_offset
}

fn capture_finish_chunk(mut out []u8, size_offset int) {
	capture_patch_le32(mut out, size_offset, u32(out.len - size_offset - 4))
}

fn capture_begin_list(mut out []u8, kind string) int {
	size_offset := capture_begin_chunk(mut out, 'LIST')
	capture_put_fourcc(mut out, kind)
	return size_offset
}

fn capture_video_dimensions(source_width int, source_height int) (int, int) {
	if source_width <= 0 || source_height <= 0 {
		return 0, 0
	}
	mut width := source_width
	mut height := source_height
	if width > capture_video_max_width || height > capture_video_max_height {
		if i64(width) * capture_video_max_height > i64(height) * capture_video_max_width {
			width = capture_video_max_width
			height = source_height * capture_video_max_width / source_width
		} else {
			height = capture_video_max_height
			width = source_width * capture_video_max_height / source_height
		}
	}
	if width > 2 && width & 1 != 0 {
		width--
	}
	if height > 2 && height & 1 != 0 {
		height--
	}
	return width, height
}

fn capture_open_avi(path string, canvas &Canvas, fps int) !AviWriter {
	width, height := capture_video_dimensions(canvas.width, canvas.height)
	if width <= 0 || height <= 0 || fps <= 0 || fps > 30 {
		return error('invalid video geometry')
	}
	fd := desktop_create_truncated(path)
	if fd < 0 {
		return error('cannot create recording')
	}
	row_stride := (width * 3 + 3) & ~3
	frame_size := row_stride * height
	mut header := []u8{cap: 256}

	capture_put_fourcc(mut header, 'RIFF')
	riff_size_offset := header.len
	capture_put_le32(mut header, 0)
	capture_put_fourcc(mut header, 'AVI ')

	hdrl_size := capture_begin_list(mut header, 'hdrl')
	avih_size := capture_begin_chunk(mut header, 'avih')
	capture_put_le32(mut header, u32(1_000_000 / fps))
	capture_put_le32(mut header, u32(frame_size * fps))
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 0x10) // AVIF_HASINDEX
	total_frames_offset := header.len
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 1)
	capture_put_le32(mut header, u32(frame_size))
	capture_put_le32(mut header, u32(width))
	capture_put_le32(mut header, u32(height))
	for _ in 0 .. 4 {
		capture_put_le32(mut header, 0)
	}
	capture_finish_chunk(mut header, avih_size)

	strl_size := capture_begin_list(mut header, 'strl')
	strh_size := capture_begin_chunk(mut header, 'strh')
	capture_put_fourcc(mut header, 'vids')
	capture_put_fourcc(mut header, 'DIB ')
	capture_put_le32(mut header, 0)
	capture_put_le16(mut header, 0)
	capture_put_le16(mut header, 0)
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 1)
	capture_put_le32(mut header, u32(fps))
	capture_put_le32(mut header, 0)
	stream_length_offset := header.len
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, u32(frame_size))
	capture_put_le32(mut header, 0xffffffff)
	capture_put_le32(mut header, u32(frame_size))
	capture_put_le16(mut header, 0)
	capture_put_le16(mut header, 0)
	capture_put_le16(mut header, u16(width))
	capture_put_le16(mut header, u16(height))
	capture_finish_chunk(mut header, strh_size)

	strf_size := capture_begin_chunk(mut header, 'strf')
	capture_put_le32(mut header, 40)
	capture_put_le32(mut header, u32(width))
	capture_put_le32(mut header, u32(height))
	capture_put_le16(mut header, 1)
	capture_put_le16(mut header, 24)
	capture_put_le32(mut header, 0) // BI_RGB
	capture_put_le32(mut header, u32(frame_size))
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 0)
	capture_put_le32(mut header, 0)
	capture_finish_chunk(mut header, strf_size)
	capture_finish_chunk(mut header, strl_size)
	capture_finish_chunk(mut header, hdrl_size)

	movi_size_offset := capture_begin_list(mut header, 'movi')
	if !desktop_write_all(fd, header.data, u64(header.len)) {
		desktop_close(fd)
		unsafe { header.free() }
		return error('cannot write recording header')
	}
	header_length := header.len
	unsafe { header.free() }
	max_frames_u64 := (capture_avi_file_limit - u64(header_length)) / u64(frame_size + 24)
	return AviWriter{
		fd: fd
		width: width
		height: height
		fps: fps
		row_stride: row_stride
		frame_size: frame_size
		max_frames: int(max_frames_u64)
		bytes_written: u64(header_length)
		riff_size_offset: riff_size_offset
		total_frames_offset: total_frames_offset
		stream_length_offset: stream_length_offset
		movi_size_offset: movi_size_offset
		frame_offsets: []u32{cap: 1024}
		frame: []u8{len: frame_size}
	}
}

fn (mut writer AviWriter) add_frame(canvas &Canvas) bool {
	if writer.fd < 0 || writer.frames >= writer.max_frames || canvas.pixels == unsafe { nil } {
		return false
	}
	for destination_y := 0; destination_y < writer.height; destination_y++ {
		source_y := (writer.height - 1 - destination_y) * canvas.height / writer.height
		row := destination_y * writer.row_stride
		for destination_x := 0; destination_x < writer.width; destination_x++ {
			source_x := destination_x * canvas.width / writer.width
			pixel := unsafe { canvas.pixels[source_y * canvas.stride + source_x] }
			offset := row + destination_x * 3
			writer.frame[offset] = u8(pixel)
			writer.frame[offset + 1] = u8(pixel >> 8)
			writer.frame[offset + 2] = u8(pixel >> 16)
		}
	}
	mut chunk := []u8{cap: 8}
	capture_put_fourcc(mut chunk, '00db')
	capture_put_le32(mut chunk, u32(writer.frame_size))
	offset := writer.bytes_written - u64(writer.movi_size_offset + 4)
	ok := desktop_write_all(writer.fd, chunk.data, u64(chunk.len))
		&& desktop_write_all(writer.fd, writer.frame.data, u64(writer.frame.len))
	unsafe { chunk.free() }
	if !ok || offset > u64(0xffffffff) {
		return false
	}
	writer.frame_offsets << u32(offset)
	writer.frames++
	writer.bytes_written += u64(8 + writer.frame_size)
	return true
}

fn capture_patch_file_u32(fd int, offset int, value u32) bool {
	mut bytes := []u8{cap: 4}
	capture_put_le32(mut bytes, value)
	ok := desktop_seek_start(fd, u64(offset)) && desktop_write_all(fd, bytes.data, 4)
	unsafe { bytes.free() }
	return ok
}

fn (mut writer AviWriter) release() {
	if writer.frame.cap > 0 {
		unsafe { writer.frame.free() }
	}
	if writer.frame_offsets.cap > 0 {
		unsafe { writer.frame_offsets.free() }
	}
	writer.frame = []u8{}
	writer.frame_offsets = []u32{}
}

fn (mut writer AviWriter) finish() bool {
	if writer.fd < 0 {
		writer.release()
		return false
	}
	movi_end := writer.bytes_written
	mut index := []u8{cap: 8 + writer.frame_offsets.len * 16}
	capture_put_fourcc(mut index, 'idx1')
	capture_put_le32(mut index, u32(writer.frame_offsets.len * 16))
	for offset in writer.frame_offsets {
		capture_put_fourcc(mut index, '00db')
		capture_put_le32(mut index, 0x10)
		capture_put_le32(mut index, offset)
		capture_put_le32(mut index, u32(writer.frame_size))
	}
	mut ok := desktop_write_all(writer.fd, index.data, u64(index.len))
	writer.bytes_written += u64(index.len)
	unsafe { index.free() }
	if writer.bytes_written > u64(0xffffffff) {
		ok = false
	}
	ok = capture_patch_file_u32(writer.fd, writer.riff_size_offset, u32(writer.bytes_written - 8))
		&& ok
	ok = capture_patch_file_u32(writer.fd, writer.total_frames_offset, u32(writer.frames))
		&& ok
	ok = capture_patch_file_u32(writer.fd, writer.stream_length_offset, u32(writer.frames))
		&& ok
	ok = capture_patch_file_u32(writer.fd, writer.movi_size_offset, u32(movi_end - u64(writer.movi_size_offset + 4)))
		&& ok
	ok = desktop_close(writer.fd) == 0 && ok
	writer.fd = -1
	writer.release()
	return ok
}

fn (mut writer AviWriter) abort() {
	if writer.fd >= 0 {
		desktop_close(writer.fd)
		writer.fd = -1
	}
	writer.release()
}

// ── Compositor capture service ────────────────────────────────────

fn capture_file_path(kind CaptureFileKind, id u64) string {
	stem := if kind == .screenshot { 'Screenshot' } else { 'Recording' }
	extension := if kind == .screenshot { 'png' } else { 'avi' }
	return '/root/${stem}-${id}.${extension}'
}

fn capture_timestamp_id(seconds i64) u64 {
	if seconds < 0 {
		return 1
	}
	civil := civil_from_epoch(seconds)
	return u64(civil.year) * 10_000_000_000 + u64(civil.month) * 100_000_000 + u64(civil.day) * 1_000_000 + u64(civil.hour) * 10_000 + u64(civil.minute) * 100 + u64(civil.second)
}

fn (mut service CaptureService) next_file_id(kind CaptureFileKind, tz_offset i64) u64 {
	seconds, _ := desktop_realtime()
	mut id := capture_timestamp_id(if seconds < 0 { seconds } else { seconds + tz_offset })
	if id <= service.last_file_id {
		id = service.last_file_id + 1
	}
	for _ in 0 .. 1000 {
		path := capture_file_path(kind, id)
		exists := desktop_stat(path) != none
		unsafe { path.free() }
		if !exists {
			service.last_file_id = id
			return id
		}
		id++
	}
	service.last_file_id = id
	return id
}

fn capture_now_ms() u64 {
	now := desktop_monotonic_ms()
	return if now == ~u64(0) { 0 } else { now }
}

fn (mut d Desktop) capture_show_owner() {
	id := d.capture.owner_window_id
	if id <= 0 {
		return
	}
	index := d.window_index(id) or { return }
	d.windows[index].minimized = false
	d.raise(id)
}

fn (mut d Desktop) capture_fail() {
	d.capture.writer.abort()
	d.capture.pending_frame = .none_
	d.capture.report = CaptureReport{
		handled_sequence: d.capture.request.sequence
		phase: .failed
	}
	d.capture_show_owner()
	d.dirty = true
}

fn (mut d Desktop) capture_finish_video(show_owner bool) {
	frames := d.capture.writer.frames
	width := d.capture.writer.width
	height := d.capture.writer.height
	fps := d.capture.writer.fps
	now := capture_now_ms()
	elapsed := if now >= d.capture.report.started_ms {
		now - d.capture.report.started_ms
	} else {
		0
	}
	file_id := d.capture.report.file_id
	ok := d.capture.writer.finish()
	d.capture.pending_frame = .none_
	d.capture.report = CaptureReport{
		handled_sequence: d.capture.request.sequence
		phase: if ok { CapturePhase.video_saved } else { CapturePhase.failed }
		file_id: file_id
		started_ms: d.capture.report.started_ms
		elapsed_ms: elapsed
		frames: frames
		width: width
		height: height
		fps: fps
	}
	if show_owner || !ok {
		d.capture_show_owner()
	}
	d.dirty = true
}

fn (mut d Desktop) accept_capture_request(request CaptureRequest) {
	if request.sequence == 0 || request.sequence == d.capture.request.sequence {
		return
	}
	d.capture.request = request
	d.capture.report.handled_sequence = request.sequence
	now := capture_now_ms()
	match request.command {
		.screenshot, .start_video {
			if d.capture.report.phase == .recording {
				d.capture_finish_video(false)
			}
			d.capture.pending_frame = .none_
			d.capture.due_ms = now + u64(request.delay * 1000)
			d.capture.report = CaptureReport{
				handled_sequence: request.sequence
				phase: if request.command == .screenshot {
					CapturePhase.screenshot_countdown
				} else {
					CapturePhase.video_countdown
				}
				elapsed_ms: u64(request.delay * 1000)
				fps: request.fps
			}
		}
		.stop {
			if d.capture.report.phase == .recording {
				d.capture_finish_video(false)
			} else if d.capture.report.phase == .screenshot_countdown
				|| d.capture.report.phase == .video_countdown {
				d.capture.pending_frame = .none_
				d.capture.report = CaptureReport{
					handled_sequence: request.sequence
					phase: .cancelled
				}
			}
		}
		.none_ {}
	}
	d.dirty = true
}

fn (mut d Desktop) capture_tick() {
	if d.capture.pending_frame != .none_ {
		return
	}
	now := capture_now_ms()
	match d.capture.report.phase {
		.screenshot_countdown, .video_countdown {
			if now >= d.capture.due_ms {
				d.capture.pending_frame = if d.capture.report.phase == .screenshot_countdown {
					CaptureFrameKind.screenshot
				} else {
					CaptureFrameKind.video_start
				}
				d.dirty = true
				return
			}
			remaining := d.capture.due_ms - now
			if d.capture.report.elapsed_ms != remaining {
				d.capture.report.elapsed_ms = remaining
			}
		}
		.recording {
			if d.capture.report.fps <= 0 {
				d.capture_fail()
				return
			}
			interval := u64(1000 / d.capture.report.fps)
			if now < d.capture.last_frame_ms || now - d.capture.last_frame_ms >= interval {
				d.capture.pending_frame = .video_frame
				d.dirty = true
			}
			if now >= d.capture.report.started_ms {
				d.capture.report.elapsed_ms = now - d.capture.report.started_ms
			}
		}
		else {}
	}
}

// Called only after the newly composed canvas has been presented. A zero-delay
// capture therefore still gets the first frame in which its own window has
// already been hidden.
fn (mut d Desktop) capture_presented(canvas &Canvas) {
	kind := d.capture.pending_frame
	if kind == .none_ {
		return
	}
	d.capture.pending_frame = .none_
	match kind {
		.screenshot {
			id := d.capture.next_file_id(.screenshot, d.tz_offset_seconds)
			path := capture_file_path(.screenshot, id)
			ok := capture_write_png(path, canvas)
			unsafe { path.free() }
			if !ok {
				d.capture_fail()
				return
			}
			d.capture.report = CaptureReport{
				handled_sequence: d.capture.request.sequence
				phase: .screenshot_saved
				file_id: id
				width: canvas.width
				height: canvas.height
			}
			d.capture_show_owner()
			d.dirty = true
		}
		.video_start {
			id := d.capture.next_file_id(.video, d.tz_offset_seconds)
			path := capture_file_path(.video, id)
			writer := capture_open_avi(path, canvas, d.capture.request.fps) or {
				unsafe { path.free() }
				d.capture_fail()
				return
			}
			unsafe { path.free() }
			d.capture.writer = writer
			now := capture_now_ms()
			d.capture.report = CaptureReport{
				handled_sequence: d.capture.request.sequence
				phase: .recording
				file_id: id
				started_ms: now
				fps: d.capture.request.fps
				width: d.capture.writer.width
				height: d.capture.writer.height
			}
			if !d.capture.writer.add_frame(canvas) {
				d.capture_fail()
				return
			}
			d.capture.last_frame_ms = now
			d.capture.report.frames = d.capture.writer.frames
			d.dirty = true
		}
		.video_frame {
			if !d.capture.writer.add_frame(canvas) {
				if d.capture.writer.frames >= d.capture.writer.max_frames {
					d.capture_finish_video(true)
				} else {
					d.capture_fail()
				}
				return
			}
			d.capture.last_frame_ms = capture_now_ms()
			d.capture.report.frames = d.capture.writer.frames
		}
		.none_ {}
	}
}

fn (d &Desktop) capture_idle_interval(maximum i64, active_interval i64) i64 {
	if d.capture.pending_frame != .none_ {
		return active_interval
	}
	if d.capture.report.phase == .recording && d.capture.report.fps > 0 {
		interval := i64(1000 / d.capture.report.fps)
		return if interval < maximum { interval } else { maximum }
	}
	if d.capture.report.phase == .screenshot_countdown
		|| d.capture.report.phase == .video_countdown {
		return if maximum < 100 { maximum } else { 100 }
	}
	return maximum
}

fn (mut d Desktop) capture_close() {
	if d.capture.report.phase == .recording {
		d.capture_finish_video(false)
	} else {
		d.capture.writer.abort()
		d.capture.pending_frame = .none_
		if d.capture.report.phase == .screenshot_countdown
			|| d.capture.report.phase == .video_countdown {
			d.capture.report = CaptureReport{
				handled_sequence: d.capture.request.sequence
				phase: .cancelled
			}
		}
	}
	d.capture.owner_window_id = 0
}

// ── Native ui2 application ────────────────────────────────────────

struct CaptureApp {
mut:
	desktop         &Desktop = unsafe { nil }
	page            CapturePage
	delay           int = 3
	fps             int = 10
	seen_phase      CapturePhase
	seen_sequence   u32
	seen_frames     int
	seen_time_slice u64
}

fn open_capture(mut desktop Desktop) !NativeApp {
	return &CaptureApp{
		desktop: desktop
	}
}

fn capture_choice(id string, text string, x int, y int, width int, selected bool) ui2.Element {
	return ui2.button(id, text, ui2.rect(f64(x), f64(y), f64(width), 30), ui2.BoxStyle{
		bg: if selected { app_accent } else { settings_choice_bg }
		radius: 7
	}, ui2.TextStyle{
		color: if selected { app_on_accent } else { body_text }
		size: 12
		bold: selected
		align: .center
	})
}

fn capture_owned_label(text string, frame ui2.Rect, style ui2.TextStyle) ui2.Element {
	return ui2.label(frame_owned_text_id, text, frame, style)
}

fn capture_duration(milliseconds u64) string {
	total_seconds := milliseconds / 1000
	minutes := total_seconds / 60
	seconds := total_seconds % 60
	minute_text := pad2(int(minutes))
	second_text := pad2(int(seconds))
	result := '${minute_text}:${second_text}'
	unsafe {
		minute_text.free()
		second_text.free()
	}
	return result
}

fn capture_status_text(report CaptureReport) (string, string) {
	match report.phase {
		.idle {
			return 'Ready to capture'.clone(), 'Files are saved in /root.'.clone()
		}
		.screenshot_countdown {
			seconds := (report.elapsed_ms + 999) / 1000
			return 'Screenshot in ${seconds}'.clone(), 'Restore this window to cancel.'.clone()
		}
		.video_countdown {
			seconds := (report.elapsed_ms + 999) / 1000
			return 'Recording in ${seconds}'.clone(), 'Restore this window to cancel.'.clone()
		}
		.recording {
			duration := capture_duration(report.elapsed_ms)
			title := 'Recording  ${duration}'
			detail := '${report.frames} frames  |  ${report.width} x ${report.height}  |  ${report.fps} fps'
			unsafe { duration.free() }
			return title, detail
		}
		.screenshot_saved {
			path := capture_file_path(.screenshot, report.file_id)
			title := 'Screenshot saved  ${report.width} x ${report.height}'
			detail := path.clone()
			unsafe { path.free() }
			return title, detail
		}
		.video_saved {
			path := capture_file_path(.video, report.file_id)
			duration := capture_duration(report.elapsed_ms)
			title := 'Recording saved  ${duration}'
			detail := path.clone()
			unsafe {
				path.free()
				duration.free()
			}
			return title, detail
		}
		.failed {
			return 'Capture failed'.clone(), 'Could not write the file in /root.'.clone()
		}
		.cancelled {
			return 'Capture cancelled'.clone(), 'Nothing was saved.'.clone()
		}
	}
}

fn (mut app CaptureApp) request(command CaptureCommand) {
	if app.desktop == unsafe { nil } {
		return
	}
	sequence := app.desktop.capture.request.sequence + 1
	app.desktop.capture.request = CaptureRequest{
		sequence: sequence
		command: command
		delay: app.delay
		fps: app.fps
	}
}

fn (mut app CaptureApp) poll() bool {
	if app.desktop == unsafe { nil } {
		return false
	}
	report := app.desktop.capture.report
	time_slice := if report.phase == .recording {
		report.elapsed_ms / 100
	} else {
		report.elapsed_ms / 1000
	}
	changed := report.phase != app.seen_phase || report.handled_sequence != app.seen_sequence
		|| report.frames != app.seen_frames || time_slice != app.seen_time_slice
	app.seen_phase = report.phase
	app.seen_sequence = report.handled_sequence
	app.seen_frames = report.frames
	app.seen_time_slice = time_slice
	return changed
}

fn (mut app CaptureApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(24)

	children << ui2.button_with_image('', '', 'builtin:camera', ui2.rect(20, 17, 34, 34), ui2.BoxStyle{
		transparent: true
	}, ui2.TextStyle{
		color: app_accent
	})
	children << ui2.label('', 'CAPTURE', ui2.rect(64, 14, f64(width - 84), 17), ui2.TextStyle{
		color: body_muted
		size: 11
		bold: true
	})
	children << ui2.label('', 'Screenshots and screen recordings', ui2.rect(64, 29, f64(width - 84), 24), ui2.TextStyle{
		color: body_heading
		size: 17
		bold: true
	})

	tab_width := (width - 40) / 2
	children << capture_choice(capture_action_screenshot_tab, 'Screenshot', 20, 64, tab_width, app.page == .screenshot)
	children << capture_choice(capture_action_video_tab, 'Video', 20 + tab_width, 64, tab_width, app.page == .video)
	children << ui2.view('', ui2.rect(20, 102, f64(width - 40), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	report := if app.desktop == unsafe { nil } {
		CaptureReport{}
	} else {
		app.desktop.capture.report
	}
	active := report.phase == .recording || report.phase == .screenshot_countdown
		|| report.phase == .video_countdown
	if app.page == .screenshot {
		children << ui2.label('', 'Full desktop screenshot', ui2.rect(20, 119, f64(width - 40), 22), ui2.TextStyle{
			color: body_heading
			size: 14
			bold: true
		})
		children << ui2.label('', 'Delay', ui2.rect(20, 153, 100, 18), ui2.TextStyle{
			color: body_muted
			size: 11
			bold: true
		})
		choice_width := (width - 56) / 3
		children << capture_choice(capture_action_delay_0, 'No delay', 20, 175, choice_width, app.delay == 0)
		children << capture_choice(capture_action_delay_3, '3 seconds', 28 + choice_width, 175, choice_width, app.delay == 3)
		children << capture_choice(capture_action_delay_5, '5 seconds', 36 + 2 * choice_width, 175, choice_width, app.delay == 5)
		children << ui2.label('', 'PNG  |  full desktop  |  includes the pointer', ui2.rect(20, 218, f64(width - 40), 18), ui2.TextStyle{
			color: body_muted
			size: 11
		})
		button_text := if active {
			if report.phase == .recording { 'Stop recording' } else { 'Cancel' }
		} else {
			'Take screenshot'
		}
		button_action := if active { capture_action_stop } else { capture_action_take_screenshot }
		children << ui2.button(button_action, button_text, ui2.rect(20, 250, f64(width - 40), 38), ui2.BoxStyle{
			bg: if active { clock_stop } else { app_accent }
			radius: 8
		}, ui2.TextStyle{
			color: app_on_accent
			size: 13
			bold: true
			align: .center
		})
	} else {
		children << ui2.label('', 'Record the desktop', ui2.rect(20, 119, f64(width - 40), 22), ui2.TextStyle{
			color: body_heading
			size: 14
			bold: true
		})
		children << ui2.label('', 'Frame rate', ui2.rect(20, 153, 100, 18), ui2.TextStyle{
			color: body_muted
			size: 11
			bold: true
		})
		choice_width := (width - 48) / 2
		children << capture_choice(capture_action_fps_5, 'Compact  5 fps', 20, 175, choice_width, app.fps == 5)
		children << capture_choice(capture_action_fps_10, 'Smooth  10 fps', 28 + choice_width, 175, choice_width, app.fps == 10)
		children << ui2.label('', 'AVI video  |  up to 640 x 480  |  pointer included  |  no audio', ui2.rect(20, 218, f64(width - 40), 18), ui2.TextStyle{
			color: body_muted
			size: 11
		})
		button_text := if active {
			if report.phase == .recording { 'Stop recording' } else { 'Cancel' }
		} else {
			'Start recording'
		}
		button_action := if active { capture_action_stop } else { capture_action_start_video }
		children << ui2.button(button_action, button_text, ui2.rect(20, 250, f64(width - 40), 38), ui2.BoxStyle{
			bg: if active { clock_stop } else { app_accent }
			radius: 8
		}, ui2.TextStyle{
			color: app_on_accent
			size: 13
			bold: true
			align: .center
		})
	}

	status_y := height - 76
	status_title, status_detail := capture_status_text(report)
	children << ui2.view('', ui2.rect(20, f64(status_y), f64(width - 40), 58), ui2.BoxStyle{
		bg: if report.phase == .recording { 0xffeeee } else { body_panel }
		radius: 8
	}, [])
	children << capture_owned_label(status_title, ui2.rect(34, f64(status_y + 8), f64(width - 68), 20), ui2.TextStyle{
		color: if report.phase == .recording { clock_stop } else { body_heading }
		size: 12
		bold: true
	})
	children << capture_owned_label(status_detail, ui2.rect(34, f64(status_y + 30), f64(width - 68), 18), ui2.TextStyle{
		color: body_muted
		size: 11
	})
	return ui2.screen(app_surface, children)
}

fn (mut app CaptureApp) handle(event_id string) ! {
	match event_id {
		capture_action_screenshot_tab {
			app.page = .screenshot
		}
		capture_action_video_tab {
			app.page = .video
		}
		capture_action_delay_0 {
			app.delay = 0
		}
		capture_action_delay_3 {
			app.delay = 3
		}
		capture_action_delay_5 {
			app.delay = 5
		}
		capture_action_fps_5 {
			app.fps = 5
		}
		capture_action_fps_10 {
			app.fps = 10
		}
		capture_action_take_screenshot { app.request(.screenshot) }
		capture_action_start_video { app.request(.start_video) }
		capture_action_stop { app.request(.stop) }
		else {}
	}
}
