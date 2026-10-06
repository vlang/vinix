// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded requests use ordinary operation replies; the existing state headers
// and protocol version remain compatible with installed standalone clients.
module main

const color_meter_request_magic = u32(0x434f4c52)
const color_meter_request_size = 24
const color_meter_report_size = 441
const color_meter_grid_size = 9
const color_meter_grid_count = 81

enum ColorMeterCommand {
	none_
	sample
	pointer
	copy_hex
	copy_rgb
}

enum ColorMeterStatus {
	ready
	sampled
	copied
	unavailable
	invalid
}

struct ColorMeterRequest {
	sequence u32
	command ColorMeterCommand
	x int
	y int
	aperture int = 1
}

struct ColorMeterReport {
	sequence u32
	status ColorMeterStatus
	width int
	height int
	x int
	y int
	aperture int = 1
	rgb u32
	count int
	grid [81]u32
	valid [81]bool
}

interface DesktopServiceApp {
mut:
	take_desktop_service_request() ColorMeterRequest
	receive_desktop_service_reply(payload string)
}

fn color_meter_aperture_valid(value int) bool {
	return value == 1 || value == 3 || value == 5 || value == 9
}

fn color_meter_read_u32(data string, offset int) u32 {
	return u32(data[offset]) | u32(data[offset + 1]) << 8 |
		u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
}

fn color_meter_encode_request(request ColorMeterRequest) []u8 {
	mut bytes := []u8{cap: color_meter_request_size}
	wire_put_u32(mut bytes, color_meter_request_magic)
	wire_put_u32(mut bytes, request.sequence)
	wire_put_i32(mut bytes, int(request.command))
	wire_put_i32(mut bytes, request.x)
	wire_put_i32(mut bytes, request.y)
	wire_put_i32(mut bytes, request.aperture)
	return bytes
}

fn color_meter_decode_request(data string) ?ColorMeterRequest {
	if data.len != color_meter_request_size || color_meter_read_u32(data, 0) != color_meter_request_magic { return none }
	command := color_meter_read_u32(data, 8)
	aperture := int(i32(color_meter_read_u32(data, 20)))
	if command < u32(ColorMeterCommand.sample) || command > u32(ColorMeterCommand.copy_rgb)
		|| !color_meter_aperture_valid(aperture) { return none }
	return ColorMeterRequest{
		sequence: color_meter_read_u32(data, 4)
		command: unsafe { ColorMeterCommand(command) }
		x: int(i32(color_meter_read_u32(data, 12)))
		y: int(i32(color_meter_read_u32(data, 16)))
		aperture: aperture
	}
}

fn color_meter_encode_report(report ColorMeterReport) []u8 {
	mut bytes := []u8{cap: color_meter_report_size}
	wire_put_u32(mut bytes, report.sequence)
	wire_put_i32(mut bytes, int(report.status))
	wire_put_i32(mut bytes, report.width)
	wire_put_i32(mut bytes, report.height)
	wire_put_i32(mut bytes, report.x)
	wire_put_i32(mut bytes, report.y)
	wire_put_i32(mut bytes, report.aperture)
	wire_put_u32(mut bytes, report.rgb)
	wire_put_i32(mut bytes, report.count)
	for index in 0 .. color_meter_grid_count {
		wire_put_u32(mut bytes, report.grid[index])
		bytes << u8(if report.valid[index] { 1 } else { 0 })
	}
	return bytes
}

fn color_meter_decode_report(data string) ?ColorMeterReport {
	if data.len != color_meter_report_size { return none }
	status := color_meter_read_u32(data, 4)
	width := int(i32(color_meter_read_u32(data, 8)))
	height := int(i32(color_meter_read_u32(data, 12)))
	x := int(i32(color_meter_read_u32(data, 16)))
	y := int(i32(color_meter_read_u32(data, 20)))
	aperture := int(i32(color_meter_read_u32(data, 24)))
	rgb := color_meter_read_u32(data, 28)
	count := int(i32(color_meter_read_u32(data, 32)))
	if status > u32(ColorMeterStatus.invalid) || width < 0 || height < 0
		|| width > 32768 || height > 32768 || !color_meter_aperture_valid(aperture)
		|| rgb > 0xffffff || count < 0 || count > aperture * aperture { return none }
	if (status == u32(ColorMeterStatus.sampled) || status == u32(ColorMeterStatus.copied))
		&& (width == 0 || height == 0 || x < 0 || y < 0 || x >= width || y >= height || count == 0) { return none }
	mut grid := [81]u32{}
	mut valid := [81]bool{}
	mut valid_count := 0
	for index in 0 .. color_meter_grid_count {
		offset := 36 + index * 5
		grid[index] = color_meter_read_u32(data, offset)
		flag := data[offset + 4]
		if grid[index] > 0xffffff || flag > 1 { return none }
		valid[index] = flag == 1
		if valid[index] { valid_count++ }
	}
	if count > valid_count { return none }
	return ColorMeterReport{
		sequence: color_meter_read_u32(data, 0)
		status: unsafe { ColorMeterStatus(status) }
		width: width
		height: height
		x: x
		y: y
		aperture: aperture
		rgb: rgb
		count: count
		grid: grid
		valid: valid
	}
}

fn native_app_desktop_service_request(mut app NativeApp) []u8 {
	if mut app is DesktopServiceApp {
		// Returning a struct promotes this interface wrapper under V3. Own the
		// small wrapper explicitly while borrowing the application it references.
		mut service := &DesktopServiceApp(app)
		defer { unsafe { free(service) } }
		request := service.take_desktop_service_request()
		if request.command != .none_ { return color_meter_encode_request(request) }
	}
	return []u8{}
}

fn native_app_receive_desktop_service(mut app NativeApp, payload string) {
	if payload.len == text_copy_reply_size && color_meter_read_u32(payload, 0) == text_copy_magic {
		native_app_receive_text_copy(mut app, payload)
		return
	}
	if mut app is DesktopServiceApp {
		mut service := DesktopServiceApp(app)
		service.receive_desktop_service_reply(payload)
	}
}

fn send_native_app_operation_response(fd int, state AppWireState, mut app NativeApp) bool {
	mut bytes := native_app_text_copy_request(mut app)
	if bytes.len == 0 { bytes = native_app_desktop_service_request(mut app) }
	sent := send_app_response(fd, true, state, bytes)
	if bytes.cap > 0 { unsafe { bytes.free() } }
	return sent
}

// Cursor backing contains the composed screen before its cursor was painted.
// Sampling it avoids reporting a pointer's white outline or black fill.
fn color_meter_pixel(desktop &Desktop, x int, y int) u32 {
	canvas := &desktop.canvas
	box := desktop.cursor_backing.box
	scale := canvas.scale
	if box.valid && scale > 0 {
		left := box.x * scale
		top := box.y * scale
		stride := box.w * scale
		if x >= left && y >= top && x < left + stride && y < top + box.h * scale {
			offset := (y - top) * stride + x - left
			if offset >= 0 && offset < desktop.cursor_backing.pixels.len {
				return desktop.cursor_backing.pixels[offset] & 0xffffff
			}
		}
	}
	return unsafe { canvas.pixels[y * canvas.stride + x] } & 0xffffff
}

fn color_meter_sample(desktop &Desktop, request ColorMeterRequest) ColorMeterReport {
	canvas := &desktop.canvas
	mut report := ColorMeterReport{
		sequence: request.sequence
		status: .unavailable
		width: if canvas.physical_width > 0 && canvas.physical_width <= 32768 { canvas.physical_width } else { 0 }
		height: if canvas.physical_height > 0 && canvas.physical_height <= 32768 { canvas.physical_height } else { 0 }
		x: request.x
		y: request.y
		aperture: if color_meter_aperture_valid(request.aperture) { request.aperture } else { 1 }
	}
	if report.width == 0 || report.height == 0 || canvas.stride < report.width
		|| canvas.stride > 32768 || unsafe { canvas.pixels == nil } { return report }
	if request.command == .pointer {
		report = ColorMeterReport{
			...report
			x: desktop.pointer_x * canvas.scale + canvas.scale / 2
			y: desktop.pointer_y * canvas.scale + canvas.scale / 2
		}
	}
	if report.x < 0 || report.y < 0 || report.x >= report.width || report.y >= report.height
		|| !color_meter_aperture_valid(request.aperture) {
		return ColorMeterReport{ ...report, status: .invalid }
	}
	mut grid := [81]u32{}
	mut valid := [81]bool{}
	mut red := u32(0)
	mut green := u32(0)
	mut blue := u32(0)
	mut count := 0
	radius := request.aperture / 2
	for row in 0 .. color_meter_grid_size {
		for column in 0 .. color_meter_grid_size {
			x := report.x + column - 4
			y := report.y + row - 4
			index := row * color_meter_grid_size + column
			if x < 0 || y < 0 || x >= report.width || y >= report.height { continue }
			pixel := color_meter_pixel(desktop, x, y)
			grid[index] = pixel
			valid[index] = true
			if column >= 4 - radius && column <= 4 + radius && row >= 4 - radius && row <= 4 + radius {
				red += (pixel >> 16) & 255
				green += (pixel >> 8) & 255
				blue += pixel & 255
				count++
			}
		}
	}
	if count == 0 { return ColorMeterReport{ ...report, status: .invalid } }
	rgb := ((red + u32(count / 2)) / u32(count) << 16) |
		((green + u32(count / 2)) / u32(count) << 8) |
		((blue + u32(count / 2)) / u32(count))
	return ColorMeterReport{ ...report, status: .sampled, rgb: rgb, count: count, grid: grid, valid: valid }
}

fn color_meter_value_text(rgb u32, hex bool) string {
	mut buffer := [64]u8{}
	length := if hex {
		unsafe { C.snprintf(&char(&buffer[0]), 64, c'#%02X%02X%02X', (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }
	} else {
		unsafe { C.snprintf(&char(&buffer[0]), 64, c'rgb(%u, %u, %u)', (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }
	}
	return if length > 0 && length < 64 { unsafe { tos(&buffer[0], length).clone() } } else { '' }
}

fn (mut app RemoteApp) handle_desktop_service(data string) bool {
	if !app.desktop_services || app.peer_features & app_feature_desktop_services == 0 { return false }
	request := color_meter_decode_request(data) or { return false }
	if unsafe { app.desktop == nil } { return false }
	mut report := ColorMeterReport{}
	if request.command == .sample || request.command == .pointer {
		report = color_meter_sample(app.desktop, request)
	} else {
		report = ColorMeterReport{ ...app.color_sample, sequence: request.sequence }
		if report.status != .sampled && report.status != .copied {
			report = ColorMeterReport{ ...report, status: .invalid }
		} else {
			text := color_meter_value_text(report.rgb, request.command == .copy_hex)
			app.desktop.clipboard.close_request()
			copied := app.desktop.clipboard.set_local_text(text)
			unsafe { text.free() }
			report = ColorMeterReport{ ...report, status: if copied { ColorMeterStatus.copied } else { ColorMeterStatus.invalid } }
		}
	}
	previous := ColorMeterReport{ ...app.color_sample, sequence: report.sequence }
	changed := previous != report
	app.color_sample = report
	bytes := color_meter_encode_report(report)
	defer { unsafe { bytes.free() } }
	payload := unsafe { tos(bytes.data, bytes.len) }
	reply := app.transact(.desktop_service_reply, 0, 0, payload) or { return false }
	defer { if reply.payload.cap > 0 { unsafe { reply.payload.free() } } }
	if !reply.ok { return false }
	if changed { app.tree_stale = true }
	return changed
}
