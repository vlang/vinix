// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Native application processes and the desktop protocol between them and the
// compositor.
//
// The compositor is the display server: it alone owns the framebuffer and
// input devices. Each application is nevertheless a real process. It builds
// its ui2 tree on request and sends the small, platform-independent result to
// the compositor, which paints it inside the application's window. Actions and
// keyboard input travel in the other direction. This is the same boundary a
// conventional display server provides, reduced to the controls this backend
// can actually draw.
module main

import math.bits
import ui2

const app_protocol_magic = u32(0x56415050) // VAPP
const app_protocol_version = u8(1)
const app_request_header_size = 44
const app_response_header_size = 36
const app_protocol_max_payload = 16 * 1024 * 1024
const app_protocol_max_string = 64 * 1024
const app_protocol_max_elements = 16 * 1024
const app_protocol_max_depth = 64
const remote_owned_element_key = '__vinix.remote.owned'
const native_app_directory = '/usr/bin/'

enum AppCommand as u8 {
	build = 1
	handle
	key_input
	poll
	pointer
	close
}

struct AppPointerPayload {
	kind   int
	x      int
	y      int
	width  int
	height int
}

struct AppProcessOptions {
	name        string
	request_fd  int
	response_fd int
	tz_offset   i64
}

struct AppWireState {
	settings        Settings
	requested_scale int = desktop_scale_100
}

struct AppReply {
	ok      bool
	state   AppWireState
	payload []u8
}

struct WireReader {
	data []u8
mut:
	index    int
	elements int
}

fn wire_put_u8(mut out []u8, value u8) {
	out << value
}

fn wire_put_u32(mut out []u8, value u32) {
	out << u8(value)
	out << u8(value >> 8)
	out << u8(value >> 16)
	out << u8(value >> 24)
}

fn wire_put_i32(mut out []u8, value int) {
	wire_put_u32(mut out, u32(value))
}

fn wire_put_u64(mut out []u8, value u64) {
	for shift := 0; shift < 64; shift += 8 {
		out << u8(value >> shift)
	}
}

fn wire_put_f64(mut out []u8, value f64) {
	wire_put_u64(mut out, bits.f64_bits(value))
}

fn wire_put_string(mut out []u8, value string) {
	wire_put_u32(mut out, u32(value.len))
	for byte in value {
		out << byte
	}
}

fn (mut r WireReader) take_u8() !u8 {
	if r.index >= r.data.len {
		return error('short application message')
	}
	value := r.data[r.index]
	r.index++
	return value
}

fn (mut r WireReader) take_u32() !u32 {
	if r.index < 0 || r.index + 4 > r.data.len {
		return error('short application message')
	}
	value := u32(r.data[r.index]) | (u32(r.data[r.index + 1]) << 8) | (u32(r.data[r.index + 2]) << 16) | (u32(r.data[r.index + 3]) << 24)
	r.index += 4
	return value
}

fn (mut r WireReader) take_i32() !int {
	return int(i32(r.take_u32()!))
}

fn (mut r WireReader) take_u64() !u64 {
	if r.index < 0 || r.index + 8 > r.data.len {
		return error('short application message')
	}
	mut value := u64(0)
	for shift := 0; shift < 64; shift += 8 {
		value |= u64(r.data[r.index + shift / 8]) << shift
	}
	r.index += 8
	return value
}

fn (mut r WireReader) take_f64() !f64 {
	return bits.f64_from_bits(r.take_u64()!)
}

fn (mut r WireReader) take_string() !string {
	length := int(r.take_u32()!)
	if length < 0 || length > app_protocol_max_string || r.index + length > r.data.len {
		return error('invalid application string')
	}
	if length == 0 {
		return ''
	}
	value := r.data[r.index..r.index + length].bytestr()
	r.index += length
	return value
}

fn wire_put_state(mut out []u8, state AppWireState) {
	wire_put_i32(mut out, int(state.settings.button_side))
	wire_put_i32(mut out, int(state.settings.taskbar_mode))
	wire_put_i32(mut out, int(state.settings.theme))
	wire_put_i32(mut out, state.settings.wallpaper_color)
	wire_put_i32(mut out, state.settings.wallpaper_image)
	wire_put_i32(mut out, state.requested_scale)
}

fn wire_take_state(mut reader WireReader) !AppWireState {
	button_side := reader.take_i32()!
	taskbar_mode := reader.take_i32()!
	theme := reader.take_i32()!
	wallpaper_color := reader.take_i32()!
	wallpaper_image := reader.take_i32()!
	requested_scale := reader.take_i32()!
	if button_side < int(ButtonSide.right) || button_side > int(ButtonSide.left)
		|| taskbar_mode < int(TaskbarMode.standard) || taskbar_mode > int(TaskbarMode.combined)
		|| theme < int(ThemeKind.default_) || theme > int(ThemeKind.macos)
		|| !desktop_scale_valid(requested_scale) {
		return error('invalid application state')
	}
	return AppWireState{
		settings: Settings{
			button_side: unsafe { ButtonSide(button_side) }
			taskbar_mode: unsafe { TaskbarMode(taskbar_mode) }
			theme: unsafe { ThemeKind(theme) }
			wallpaper_color: wallpaper_color
			wallpaper_image: wallpaper_image
		}
		requested_scale: requested_scale
	}
}

// Only fields consumed by the framebuffer renderer cross the boundary. ui2's
// platform-only metadata (native text controls, menus and accessibility hints)
// has no meaning in this backend and is deliberately absent from the protocol.
fn encode_app_element(element ui2.Element, mut out []u8) ! {
	if out.len > app_protocol_max_payload {
		return error('application tree is too large')
	}
	wire_put_u8(mut out, u8(element.kind))
	mut flags := u8(0)
	if element.box.transparent {
		flags |= 1
	}
	if element.text_style.bold {
		flags |= 2
	}
	if element.text_style.shadow {
		flags |= 4
	}
	if element.clickable {
		flags |= 8
	}
	if element.draggable {
		flags |= 16
	}
	if element.hidden {
		flags |= 32
	}
	if element.enabled {
		flags |= 64
	}
	wire_put_u8(mut out, flags)
	wire_put_u8(mut out, u8(element.text_style.align))
	wire_put_u8(mut out, 0)
	wire_put_f64(mut out, element.frame.x)
	wire_put_f64(mut out, element.frame.y)
	wire_put_f64(mut out, element.frame.width)
	wire_put_f64(mut out, element.frame.height)
	wire_put_u32(mut out, element.box.bg)
	wire_put_f64(mut out, element.box.radius)
	wire_put_u32(mut out, element.text_style.color)
	wire_put_u32(mut out, element.text_style.background_color)
	wire_put_f64(mut out, element.text_style.size)
	wire_put_string(mut out, element.id)
	wire_put_string(mut out, element.action_id)
	wire_put_string(mut out, element.text)
	wire_put_string(mut out, element.image_path)
	wire_put_string(mut out, element.text_style.font_family)
	wire_put_u32(mut out, u32(element.children.len))
	for child in element.children {
		encode_app_element(child, mut out)!
	}
}

fn decode_app_element(mut reader WireReader, depth int) !ui2.Element {
	if depth > app_protocol_max_depth || reader.elements >= app_protocol_max_elements {
		return error('application tree exceeds protocol limits')
	}
	reader.elements++
	kind_value := int(reader.take_u8()!)
	flags := reader.take_u8()!
	align_value := int(reader.take_u8()!)
	reader.take_u8()!
	if kind_value < int(ui2.Kind.screen) || kind_value > int(ui2.Kind.scroll)
		|| align_value < int(ui2.Align.left) || align_value > int(ui2.Align.right) {
		return error('invalid application element')
	}
	frame := ui2.rect(reader.take_f64()!, reader.take_f64()!, reader.take_f64()!, reader.take_f64()!)
	box_bg := reader.take_u32()!
	box_radius := reader.take_f64()!
	text_color := reader.take_u32()!
	text_background := reader.take_u32()!
	text_size := reader.take_f64()!
	id := reader.take_string()!
	action_id := reader.take_string()!
	text := reader.take_string()!
	image_path := reader.take_string()!
	font_family := reader.take_string()!
	child_count := int(reader.take_u32()!)
	if child_count < 0 || child_count > app_protocol_max_elements - reader.elements {
		return error('invalid application child count')
	}
	mut children := []ui2.Element{cap: child_count}
	for _ in 0 .. child_count {
		children << decode_app_element(mut reader, depth + 1)!
	}
	return ui2.Element{
		kind: unsafe { ui2.Kind(kind_value) }
		id: id
		action_id: action_id
		key: remote_owned_element_key
		text: text
		image_path: image_path
		frame: frame
		box: ui2.BoxStyle{
			bg: box_bg
			radius: box_radius
			transparent: flags & 1 != 0
		}
		text_style: ui2.TextStyle{
			color: text_color
			background_color: text_background
			size: text_size
			font_family: font_family
			bold: flags & 2 != 0
			shadow: flags & 4 != 0
			align: unsafe { ui2.Align(align_value) }
		}
		clickable: flags & 8 != 0
		draggable: flags & 16 != 0
		hidden: flags & 32 != 0
		enabled: flags & 64 != 0
		children: children
	}
}

fn decode_app_tree(payload []u8) !ui2.Element {
	mut reader := WireReader{ data: payload }
	tree := decode_app_element(mut reader, 0)!
	if reader.index != payload.len {
		free_tree(tree)
		return error('application tree has trailing data')
	}
	return tree
}

fn app_process_options(args []string) ?AppProcessOptions {
	mut name := ''
	mut request_fd := -1
	mut response_fd := -1
	mut tz_offset := i64(0)
	for arg in args {
		if arg.starts_with('--vinix-app=') {
			name = arg['--vinix-app='.len..]
		} else if arg.starts_with('--request-fd=') {
			request_fd = arg['--request-fd='.len..].int()
		} else if arg.starts_with('--response-fd=') {
			response_fd = arg['--response-fd='.len..].int()
		} else if arg.starts_with('--app-tz=') {
			tz_offset = arg['--app-tz='.len..].i64()
		}
	}
	if name == '' {
		return none
	}
	if request_fd < 3 || response_fd < 3 || request_fd == response_fd {
		return none
	}
	return AppProcessOptions{
		name: name
		request_fd: request_fd
		response_fd: response_fd
		tz_offset: tz_offset
	}
}

fn app_factory_named(name string) ?AppFactory {
	for factory in available_apps {
		if factory.process_name == name {
			return factory
		}
	}
	return none
}

fn app_current_state(desktop &Desktop) AppWireState {
	return AppWireState{
		settings: desktop.settings
		requested_scale: desktop_requested_scale()
	}
}

fn apply_app_state(mut desktop Desktop, state AppWireState) {
	wallpaper_changed := desktop.settings.wallpaper_color != state.settings.wallpaper_color
		|| desktop.settings.wallpaper_image != state.settings.wallpaper_image
	desktop.settings = state.settings
	if wallpaper_changed {
		desktop.invalidate_wallpaper()
	}
	if desktop_requested_scale() != state.requested_scale {
		desktop_request_scale(state.requested_scale)
		desktop.dirty = true
	}
}

fn send_app_request(fd int, command AppCommand, width int, height int, state AppWireState, payload string) bool {
	if payload.len > app_protocol_max_payload {
		return false
	}
	mut header := []u8{cap: app_request_header_size}
	wire_put_u32(mut header, app_protocol_magic)
	wire_put_u8(mut header, app_protocol_version)
	wire_put_u8(mut header, u8(command))
	wire_put_u8(mut header, 0)
	wire_put_u8(mut header, 0)
	wire_put_i32(mut header, width)
	wire_put_i32(mut header, height)
	wire_put_state(mut header, state)
	wire_put_u32(mut header, u32(payload.len))
	ok := header.len == app_request_header_size
		&& desktop_write_all(fd, header.data, u64(header.len))
		&& (payload.len == 0 || desktop_write_all(fd, payload.str, u64(payload.len)))
	unsafe { header.free() }
	return ok
}

fn receive_app_request(fd int) !(AppCommand, int, int, AppWireState, string) {
	mut header := []u8{len: app_request_header_size}
	if !desktop_read_all(fd, header.data, u64(header.len)) {
		unsafe { header.free() }
		return error('application request pipe closed')
	}
	mut reader := WireReader{ data: header }
	magic := reader.take_u32()!
	version := reader.take_u8()!
	command_value := int(reader.take_u8()!)
	reader.take_u8()!
	reader.take_u8()!
	width := reader.take_i32()!
	height := reader.take_i32()!
	state := wire_take_state(mut reader)!
	payload_length := int(reader.take_u32()!)
	unsafe { header.free() }
	if magic != app_protocol_magic || version != app_protocol_version
		|| command_value < int(AppCommand.build) || command_value > int(AppCommand.close)
		|| payload_length < 0 || payload_length > app_protocol_max_payload {
		return error('invalid application request')
	}
	mut payload := []u8{len: payload_length}
	if payload_length > 0 && !desktop_read_all(fd, payload.data, u64(payload_length)) {
		unsafe { payload.free() }
		return error('short application request payload')
	}
	text := if payload_length > 0 { payload.bytestr() } else { '' }
	if payload.cap > 0 {
		unsafe { payload.free() }
	}
	return unsafe { AppCommand(command_value) }, width, height, state, text
}

fn send_app_response(fd int, ok bool, state AppWireState, payload []u8) bool {
	if payload.len > app_protocol_max_payload {
		return false
	}
	mut header := []u8{cap: app_response_header_size}
	wire_put_u32(mut header, app_protocol_magic)
	wire_put_u8(mut header, app_protocol_version)
	wire_put_u8(mut header, if ok { u8(0) } else { u8(1) })
	wire_put_u8(mut header, 0)
	wire_put_u8(mut header, 0)
	wire_put_state(mut header, state)
	wire_put_u32(mut header, u32(payload.len))
	written := header.len == app_response_header_size
		&& desktop_write_all(fd, header.data, u64(header.len))
		&& (payload.len == 0 || desktop_write_all(fd, payload.data, u64(payload.len)))
	unsafe { header.free() }
	return written
}

fn send_app_error(fd int, state AppWireState, message string) bool {
	mut payload := message.bytes()
	written := send_app_response(fd, false, state, payload)
	unsafe { payload.free() }
	return written
}

fn receive_app_response(fd int) !AppReply {
	mut header := []u8{len: app_response_header_size}
	if !desktop_read_all(fd, header.data, u64(header.len)) {
		unsafe { header.free() }
		return error('application response pipe closed')
	}
	mut reader := WireReader{ data: header }
	magic := reader.take_u32()!
	version := reader.take_u8()!
	status := reader.take_u8()!
	reader.take_u8()!
	reader.take_u8()!
	state := wire_take_state(mut reader)!
	payload_length := int(reader.take_u32()!)
	unsafe { header.free() }
	if magic != app_protocol_magic || version != app_protocol_version || status > 1
		|| payload_length < 0 || payload_length > app_protocol_max_payload {
		return error('invalid application response')
	}
	mut payload := []u8{len: payload_length}
	if payload_length > 0 && !desktop_read_all(fd, payload.data, u64(payload_length)) {
		unsafe { payload.free() }
		return error('short application response payload')
	}
	return AppReply{
		ok: status == 0
		state: state
		payload: payload
	}
}

fn app_reply_error(reply AppReply) IError {
	message := if reply.payload.len > 0 {
		reply.payload.bytestr()
	} else {
		'application request failed'.clone()
	}
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
	return error(message)
}

fn free_app_payload(payload string) {
	if payload.len > 0 {
		unsafe { payload.free() }
	}
}

// run_app_process is the client half of the display protocol. It is reached
// before the normal desktop opens a framebuffer, so an app can never become a
// second compositor by accident.
fn run_app_process(options AppProcessOptions) {
	desktop_set_cloexec(options.request_fd, true)
	desktop_set_cloexec(options.response_fd, true)
	mut desktop := Desktop{
		tz_offset_seconds: options.tz_offset
	}
	factory := app_factory_named(options.name) or {
		send_app_error(options.response_fd, app_current_state(desktop), 'unknown application ${options.name}')
		return
	}
	if factory.open == unsafe { nil } {
		send_app_error(options.response_fd, app_current_state(desktop), '${factory.title} cannot run as a native app')
		return
	}
	mut app := factory.open(mut desktop) or {
		send_app_error(options.response_fd, app_current_state(desktop), err.msg())
		return
	}
	if !send_app_response(options.response_fd, true, app_current_state(desktop), []u8{}) {
		return
	}

	mut encoded := []u8{cap: 16 * 1024}
	for {
		command, width, height, state, payload := receive_app_request(options.request_fd) or {
			break
		}
		desktop.settings = state.settings
		desktop_request_scale(state.requested_scale)
		match command {
			.build {
				tree := app.build(ui2.rect(0, 0, f64(width), f64(height))) or {
					send_app_error(options.response_fd, app_current_state(desktop), err.msg())
					free_app_payload(payload)
					continue
				}
				encoded.clear()
				encode_app_element(tree, mut encoded) or {
					free_tree(tree)
					send_app_error(options.response_fd, app_current_state(desktop), err.msg())
					free_app_payload(payload)
					continue
				}
				free_tree(tree)
				if !send_app_response(options.response_fd, true, app_current_state(desktop), encoded) {
					free_app_payload(payload)
					break
				}
			}
			.handle {
				app.handle(payload) or {
					send_app_error(options.response_fd, app_current_state(desktop), err.msg())
					free_app_payload(payload)
					continue
				}
				if !send_app_response(options.response_fd, true, app_current_state(desktop), []u8{}) {
					free_app_payload(payload)
					break
				}
			}
			.key_input {
				if mut app is KeyboardApp {
					app.key_input(payload)
				}
				if !send_app_response(options.response_fd, true, app_current_state(desktop), []u8{}) {
					free_app_payload(payload)
					break
				}
			}
			.poll {
				changed := if mut app is PollingApp { app.poll() } else { false }
				poll_payload := [u8(if changed { 1 } else { 0 })]
				if !send_app_response(options.response_fd, true, app_current_state(desktop), poll_payload) {
					free_app_payload(payload)
					break
				}
			}
			.pointer {
				if payload.len != sizeof(AppPointerPayload) {
					send_app_error(options.response_fd, app_current_state(desktop), 'invalid pointer event')
					free_app_payload(payload)
					continue
				}
				mut pointer := AppPointerPayload{}
				unsafe { C.memcpy(&pointer, payload.str, sizeof(AppPointerPayload)) }
				if pointer.kind < int(AppPointerPhase.move) || pointer.kind > int(AppPointerPhase.up)
					|| pointer.width <= 0 || pointer.height <= 0 {
					send_app_error(options.response_fd, app_current_state(desktop), 'invalid pointer geometry')
					free_app_payload(payload)
					continue
				}
				if mut app is PointerApp {
					app.pointer_event(unsafe { AppPointerPhase(pointer.kind) }, pointer.x, pointer.y, pointer.width, pointer.height)
				}
				if !send_app_response(options.response_fd, true, app_current_state(desktop), []u8{}) {
					free_app_payload(payload)
					break
				}
			}
			.close {
				if mut app is ClosingApp {
					app.close_app()
				}
				send_app_response(options.response_fd, true, app_current_state(desktop), []u8{})
				free_app_payload(payload)
				break
			}
		}
		free_app_payload(payload)
	}
	unsafe { encoded.free() }
	desktop_close(options.request_fd)
	desktop_close(options.response_fd)
}

@[heap]
struct RemoteApp {
mut:
	pid         int
	request_fd  int
	response_fd int
	polling     bool
	keyboard    bool
	pointer     bool
	closed      bool
	desktop     &Desktop = unsafe { nil }
}

fn start_remote_app(factory AppFactory, mut desktop Desktop) !NativeApp {
	path := native_app_directory + factory.process_name
	app := start_remote_app_at(path, factory, mut desktop) or {
		unsafe { path.free() }
		return err
	}
	unsafe { path.free() }
	return app
}

// Kept separate from the installed-path wrapper so the protocol can be
// exercised by a host integration binary that execs itself as the client.
fn start_remote_app_at(path string, factory AppFactory, mut desktop Desktop) !NativeApp {
	process := desktop_spawn_app(path, factory.process_name, desktop.tz_offset_seconds) or {
		return error('cannot execute ${path}')
	}
	mut remote := &RemoteApp{
		pid: process.pid
		request_fd: process.to_child
		response_fd: process.from_child
		polling: factory.polling
		keyboard: factory.keyboard
		pointer: factory.pointer
		desktop: desktop
	}
	reply := receive_app_response(remote.response_fd) or {
		remote.close_transport()
		return error('cannot start ${factory.title}: ${err}')
	}
	if !reply.ok {
		remote.close_transport()
		return app_reply_error(reply)
	}
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
	return remote
}

fn (mut a RemoteApp) transact(command AppCommand, width int, height int, payload string) !AppReply {
	if a.closed || a.request_fd < 0 || a.response_fd < 0 {
		return error('application process has exited')
	}
	state := if unsafe { a.desktop != nil } {
		app_current_state(a.desktop)
	} else {
		AppWireState{}
	}
	if !send_app_request(a.request_fd, command, width, height, state, payload) {
		a.close_transport()
		return error('application request pipe closed')
	}
	reply := receive_app_response(a.response_fd) or {
		a.close_transport()
		return err
	}
	if unsafe { a.desktop != nil } {
		apply_app_state(mut a.desktop, reply.state)
	}
	return reply
}

fn (mut a RemoteApp) build(size ui2.Rect) !ui2.Element {
	reply := a.transact(.build, int(size.width), int(size.height), '')!
	if !reply.ok {
		return app_reply_error(reply)
	}
	tree := decode_app_tree(reply.payload) or {
		if reply.payload.cap > 0 {
			unsafe { reply.payload.free() }
		}
		return err
	}
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
	return tree
}

fn (mut a RemoteApp) handle(event_id string) ! {
	reply := a.transact(.handle, 0, 0, event_id)!
	if !reply.ok {
		return app_reply_error(reply)
	}
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
}

fn (mut a RemoteApp) key_input(text string) {
	if !a.keyboard {
		return
	}
	reply := a.transact(.key_input, 0, 0, text) or { return }
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
}

fn (a &RemoteApp) pointer_input_enabled() bool {
	return a.pointer && !a.closed
}

fn (mut a RemoteApp) pointer_event(phase AppPointerPhase, x int, y int, width int, height int) {
	if !a.pointer || a.closed {
		return
	}
	pointer := AppPointerPayload{
		kind: int(phase)
		x: x
		y: y
		width: width
		height: height
	}
	payload := unsafe { tos(&u8(&pointer), int(sizeof(AppPointerPayload))) }
	reply := a.transact(.pointer, 0, 0, payload) or { return }
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
}

fn (mut a RemoteApp) poll() bool {
	if !a.polling || a.closed {
		return false
	}
	reply := a.transact(.poll, 0, 0, '') or { return true }
	if !reply.ok {
		if reply.payload.cap > 0 {
			unsafe { reply.payload.free() }
		}
		return true
	}
	changed := reply.payload.len == 1 && reply.payload[0] != 0
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
	return changed
}

fn (mut a RemoteApp) close_transport() {
	if a.request_fd >= 0 {
		desktop_close(a.request_fd)
		a.request_fd = -1
	}
	if a.response_fd >= 0 {
		desktop_close(a.response_fd)
		a.response_fd = -1
	}
	if a.pid > 0 {
		desktop_wait_child(a.pid)
		a.pid = -1
	}
	a.closed = true
}

fn (mut a RemoteApp) close() {
	if a.closed {
		return
	}
	reply := a.transact(.close, 0, 0, '') or {
		a.close_transport()
		return
	}
	if reply.payload.cap > 0 {
		unsafe { reply.payload.free() }
	}
	a.close_transport()
}
