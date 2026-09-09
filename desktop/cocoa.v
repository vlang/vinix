// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A deliberately small, userspace-only Objective-C/AppKit compatibility
// runtime. It loads a native AArch64 Mach-O, applies classic dyld pointer
// fixups, and translates the Cocoa objects it creates into ui2 elements.
module main

import compat.macos.bundle
import compat.macos.macho
import ui2

fn C.mprotect(base voidptr, length usize, protection int) int

const cocoa_calculator_bundle = $d('vinix_cocoa_calculator_bundle', '/Applications/Calculator.app')
const cocoa_executable_limit = u64(16 * 1024 * 1024)
const cocoa_action_prefix = 'cocoa.button.'

enum CocoaObjectKind {
	application
	window
	view
	button
	label
	instance
}

struct CocoaRect {
mut:
	x      f64
	y      f64
	width  f64
	height f64
}

@[heap]
struct CocoaClass {
	name string

mut:
	address u64
}

@[heap]
struct CocoaObject {
mut:
	kind          CocoaObjectKind
	class_address u64
	text          string
	frame         CocoaRect
	tag           i64
	target        u64
	action        u64
	children      []u64
	content_view  u64
	delegate      u64
}

struct CocoaMethod {
	class_name string
	selector   string
	address    u64
}

struct LoadedMachO {
mut:
	base       voidptr
	size       u64
	minimum_vm u64
	entry      u64
}

fn (mut image LoadedMachO) close() {
	if image.base != unsafe { nil } && image.size > 0 {
		C.munmap(image.base, usize(image.size))
		image.base = unsafe { nil }
		image.size = 0
	}
}

@[heap]
struct CocoaRuntime {
mut:
	image       LoadedMachO
	classes     []&CocoaClass
	objects     []&CocoaObject
	methods     []CocoaMethod
	window      u64
	application u64
}

__global (
	active_cocoa_runtime &CocoaRuntime
)

fn (mut runtime CocoaRuntime) add_class(name string) u64 {
	mut class := &CocoaClass{ name: name }
	class.address = u64(voidptr(class))
	runtime.classes << class
	return class.address
}

fn (runtime &CocoaRuntime) class_name(address u64) ?string {
	for class in runtime.classes {
		if class.address == address {
			return class.name
		}
	}
	return none
}

fn (mut runtime CocoaRuntime) add_object(kind CocoaObjectKind, class_address u64) u64 {
	object := &CocoaObject{
		kind: kind
		class_address: class_address
	}
	runtime.objects << object
	return u64(voidptr(object))
}

fn (runtime &CocoaRuntime) object(address u64) ?&CocoaObject {
	for object in runtime.objects {
		if u64(voidptr(object)) == address {
			return object
		}
	}
	return none
}

fn (runtime &CocoaRuntime) address_is_mapped(address u64, length u64) bool {
	if runtime.image.base == unsafe { nil } {
		return false
	}
	start := u64(runtime.image.base)
	return address >= start && length <= runtime.image.size && address - start <= runtime.image.size - length
}

fn (runtime &CocoaRuntime) mapped_cstring(address u64, maximum int) ?string {
	if !runtime.address_is_mapped(address, 1) {
		return none
	}
	start := u64(runtime.image.base)
	available := runtime.image.size - (address - start)
	limit := if available < u64(maximum) { int(available) } else { maximum }
	mut length := 0
	for length < limit && unsafe { *&u8(address + u64(length)) } != 0 {
		length++
	}
	if length == limit {
		return none
	}
	return unsafe { tos(&u8(address), length).clone() }
}

fn (runtime &CocoaRuntime) string_value(address u64) string {
	if address == 0 {
		return ''
	}
	if object := runtime.object(address) {
		return object.text
	}
	// clang's constant NSString layout is isa, flags, UTF-8 pointer, length.
	if !runtime.address_is_mapped(address, 32) {
		return ''
	}
	characters := unsafe { *&u64(address + 16) }
	length := unsafe { *&u64(address + 24) }
	if length > 4096 || !runtime.address_is_mapped(characters, length) {
		return ''
	}
	return unsafe { tos(&u8(characters), int(length)).clone() }
}

fn cocoa_runtime() ?&CocoaRuntime {
	if unsafe { active_cocoa_runtime == nil } {
		return none
	}
	return active_cocoa_runtime
}

fn cocoa_class_kind(name string) CocoaObjectKind {
	return match name {
		'NSApplication' { .application }
		'NSWindow' { .window }
		'NSView' { .view }
		'NSButton' { .button }
		'NSTextField' { .label }
		else { .instance }
	}
}

fn cocoa_allocate(class_address u64) u64 {
	mut runtime := cocoa_runtime() or { return 0 }
	name := runtime.class_name(class_address) or { return 0 }
	address := runtime.add_object(cocoa_class_kind(name), class_address)
	if name == 'NSApplication' {
		runtime.application = address
	}
	if name == 'NSWindow' {
		content_class := runtime.class_address('NSView') or { class_address }
		view := runtime.add_object(.view, content_class)
		mut object := runtime.object(address) or { return 0 }
		object.content_view = view
	}
	return address
}

fn (runtime &CocoaRuntime) class_address(name string) ?u64 {
	for class in runtime.classes {
		if class.name == name {
			return class.address
		}
	}
	return none
}

// These functions are reached from the loaded Mach-O through dyld binds. They
// intentionally use plain integer/pointer ABI values. The Objective-C caller
// independently places homogeneous NSRect values in d0-d3; declaring all FP
// registers after all GPR registers lets the dispatcher observe both banks.
fn cocoa_objc_alloc(class_address u64) u64 {
	return cocoa_allocate(class_address)
}

fn cocoa_objc_new(class_address u64) u64 {
	return cocoa_allocate(class_address)
}

type CocoaMethod3 = fn (u64, u64, u64) u64

type CocoaEntry = fn (int, voidptr) int

fn (runtime &CocoaRuntime) method(class_name string, selector string) ?u64 {
	for method in runtime.methods {
		if method.class_name == class_name && method.selector == selector {
			return method.address
		}
	}
	return none
}

fn (mut runtime CocoaRuntime) invoke(receiver u64, selector_address u64, argument u64) u64 {
	object := runtime.object(receiver) or { return 0 }
	class_name := runtime.class_name(object.class_address) or { return 0 }
	selector := runtime.mapped_cstring(selector_address, 256) or { return 0 }
	method_address := runtime.method(class_name, selector) or { return 0 }
	method := unsafe { CocoaMethod3(voidptr(method_address)) }
	return method(receiver, selector_address, argument)
}

fn cocoa_objc_msg_send(receiver u64, selector_address u64, argument2 u64, argument3 u64,
	argument4 u64, _argument5 u64, _argument6 u64, _argument7 u64, fp0 f64, fp1 f64,
	fp2 f64, fp3 f64, _fp4 f64, _fp5 f64, _fp6 f64, _fp7 f64) u64 {
	if receiver == 0 {
		return 0
	}
	mut runtime := cocoa_runtime() or { return 0 }
	selector := runtime.mapped_cstring(selector_address, 256) or { return 0 }

	if runtime.class_name(receiver) != none {
		match selector {
			'alloc', 'new' {
				return cocoa_allocate(receiver)
			}
			'sharedApplication' {
				if runtime.application == 0 {
					runtime.application = cocoa_allocate(receiver)
				}
				return runtime.application
			}
			'labelWithString:' {
				address := runtime.add_object(.label, receiver)
				mut label := runtime.object(address) or { return 0 }
				label.text = runtime.string_value(argument2)
				return address
			}
			'buttonWithTitle:target:action:' {
				address := runtime.add_object(.button, receiver)
				mut button := runtime.object(address) or { return 0 }
				button.text = runtime.string_value(argument2)
				button.target = argument3
				button.action = argument4
				return address
			}
			else {}
		}
		return 0
	}

	mut object := runtime.object(receiver) or { return 0 }
	match selector {
		'init' {
			return receiver
		}
		'initWithContentRect:styleMask:backing:defer:' {
			object.frame = CocoaRect{ x: fp0, y: fp1, width: fp2, height: fp3 }
			return receiver
		}
		'setFrame:' {
			object.frame = CocoaRect{ x: fp0, y: fp1, width: fp2, height: fp3 }
		}
		'setTitle:' {
			object.text = runtime.string_value(argument2)
		}
		'contentView' {
			return object.content_view
		}
		'addSubview:' {
			if runtime.object(argument2) != none {
				object.children << argument2
			}
		}
		'makeKeyAndOrderFront:' {
			runtime.window = receiver
		}
		'setDelegate:' {
			object.delegate = argument2
		}
		'run' {
			if object.delegate != 0 {
				delegate := runtime.object(object.delegate) or { return 0 }
				class_name := runtime.class_name(delegate.class_address) or { return 0 }
				method_address := runtime.method(class_name, 'applicationDidFinishLaunching:') or {
					return 0
				}
				method_function := unsafe { CocoaMethod3(voidptr(method_address)) }
				method_function(object.delegate, 0, 0)
			}
		}
		'setTag:' {
			object.tag = i64(argument2)
		}
		'tag' {
			return u64(object.tag)
		}
		'setIntegerValue:' {
			object.text = i64(argument2).str()
		}
		'setAlignment:' {}
		else {
			return runtime.invoke(receiver, selector_address, argument2)
		}
	}
	return 0
}

fn cocoa_noop() u64 {
	return 0
}

fn cocoa_symbol_address(symbol string) !u64 {
	mut runtime := cocoa_runtime() or { return error('Cocoa runtime is not active') }
	match symbol {
		'_objc_msgSend' {
			return u64(voidptr(cocoa_objc_msg_send))
		}
		'_objc_alloc' {
			return u64(voidptr(cocoa_objc_alloc))
		}
		'_objc_opt_new' {
			return u64(voidptr(cocoa_objc_new))
		}
		'dyld_stub_binder' {
			return u64(voidptr(cocoa_noop))
		}
		'__objc_empty_cache' {
			return u64(voidptr(cocoa_noop))
		}
		'___CFConstantStringClassReference' {
			return runtime.class_address('NSConstantString') or { return error('missing NSConstantString class') }
		}
		else {}
	}
	if symbol.starts_with('_OBJC_CLASS_\$_') {
		name := symbol['_OBJC_CLASS_\$_'.len..]
		return runtime.class_address(name) or { return error('unsupported Cocoa class ${name}') }
	}
	if symbol.starts_with('_OBJC_METACLASS_\$_') {
		name := symbol['_OBJC_METACLASS_\$_'.len..]
		return runtime.class_address(name) or { return error('unsupported Cocoa metaclass ${name}') }
	}
	return error('unsupported imported macOS symbol ${symbol}')
}

fn macho_stream(data []u8, offset u32, size u32) []u8 {
	if size == 0 {
		return []u8{}
	}
	return data[int(offset)..int(u64(offset) + u64(size))]
}

fn mapped_fixup_address(parsed &macho.Image, loaded &LoadedMachO, fixup macho.Fixup) !&u64 {
	if fixup.segment_index < 0 || fixup.segment_index >= parsed.segments.len {
		return error('Mach-O fixup references an invalid segment')
	}
	segment := parsed.segments[fixup.segment_index]
	if segment.vm_address < loaded.minimum_vm || fixup.offset > segment.vm_size
		|| segment.vm_size - fixup.offset < 8
		|| segment.vm_address - loaded.minimum_vm > loaded.size
		|| fixup.offset > loaded.size - (segment.vm_address - loaded.minimum_vm)
		|| loaded.size - (segment.vm_address - loaded.minimum_vm) - fixup.offset < 8 {
		return error('Mach-O fixup lies outside its segment')
	}
	address := u64(loaded.base) + segment.vm_address - loaded.minimum_vm + fixup.offset
	return unsafe { &u64(address) }
}

fn apply_macho_fixups(parsed &macho.Image, mut loaded LoadedMachO) ! {
	rebases := macho.decode_rebases(macho_stream(parsed.data, parsed.dyld.rebase_offset, parsed.dyld.rebase_size), parsed.segments.len)!
	for fixup in rebases {
		mut pointer := mapped_fixup_address(parsed, &loaded, fixup)!
		original := *pointer
		if original != 0 {
			if original < loaded.minimum_vm || original - loaded.minimum_vm >= loaded.size {
				return error('Mach-O rebase target lies outside the image')
			}
			unsafe { *pointer = u64(loaded.base) + original - loaded.minimum_vm }
		}
	}
	mut binds := macho.decode_binds(macho_stream(parsed.data, parsed.dyld.bind_offset, parsed.dyld.bind_size), parsed.segments.len, false)!
	if parsed.dyld.weak_bind_size > 0 {
		binds << macho.decode_binds(macho_stream(parsed.data, parsed.dyld.weak_bind_offset, parsed.dyld.weak_bind_size), parsed.segments.len, false)!
	}
	if parsed.dyld.lazy_bind_size > 0 {
		binds << macho.decode_binds(macho_stream(parsed.data, parsed.dyld.lazy_bind_offset, parsed.dyld.lazy_bind_size), parsed.segments.len, true)!
	}
	for fixup in binds {
		mut pointer := mapped_fixup_address(parsed, &loaded, fixup)!
		resolved := cocoa_symbol_address(fixup.symbol)!
		unsafe {
			*pointer = if fixup.addend >= 0 {
				if u64(fixup.addend) > ~u64(0) - resolved {
					return error('overflowing Mach-O bind addend')
				}
				resolved + u64(fixup.addend)
			} else {
				magnitude := u64(-(fixup.addend + 1)) + 1
				if magnitude > resolved {
					return error('underflowing Mach-O bind addend')
				}
				resolved - magnitude
			}
		}
	}
}

fn load_macho(parsed &macho.Image) !LoadedMachO {
	mut minimum := ~u64(0)
	mut maximum := u64(0)
	for segment in parsed.segments {
		if segment.vm_size == 0 || (segment.file_size == 0 && segment.initial_protection == 0) {
			continue
		}
		if segment.vm_address < minimum {
			minimum = segment.vm_address
		}
		if segment.vm_size > ~u64(0) - segment.vm_address {
			return error('overflowing Mach-O segment')
		}
		end := segment.vm_address + segment.vm_size
		if end > maximum {
			maximum = end
		}
	}
	if minimum == ~u64(0) || maximum <= minimum || maximum - minimum > cocoa_executable_limit {
		return error('unsupported Mach-O virtual address span')
	}
	size := maximum - minimum
	base := C.mmap(unsafe { nil }, usize(size), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANON, -1, 0)
	if base == voidptr(C.MAP_FAILED) {
		return error('cannot allocate Mach-O address space')
	}
	mut loaded := LoadedMachO{ base: base, size: size, minimum_vm: minimum }
	for segment in parsed.segments {
		if segment.vm_size == 0 || (segment.file_size == 0 && segment.initial_protection == 0) {
			continue
		}
		destination := unsafe { voidptr(u64(base) + segment.vm_address - minimum) }
		if segment.file_size > 0 {
			source := unsafe { voidptr(u64(parsed.data.data) + segment.file_offset) }
			unsafe { C.memcpy(destination, source, segment.file_size) }
		}
	}
	apply_macho_fixups(parsed, mut loaded) or {
		loaded.close()
		return err
	}
	entry_segment := parsed.segment_for_file_offset(parsed.entry_file_offset) or {
		loaded.close()
		return error('Mach-O entry point is not in a file-backed segment')
	}
	if entry_segment.initial_protection & C.PROT_EXEC == 0 {
		loaded.close()
		return error('Mach-O entry point is not executable')
	}
	loaded.entry = u64(base) + entry_segment.vm_address - minimum + parsed.entry_file_offset - entry_segment.file_offset
	for segment in parsed.segments {
		if segment.vm_size == 0 || (segment.file_size == 0 && segment.initial_protection == 0) {
			continue
		}
		if segment.initial_protection & ~7 != 0 || segment.max_protection & ~7 != 0 {
			loaded.close()
			return error('invalid Mach-O segment protection')
		}
		address := unsafe { voidptr(u64(base) + segment.vm_address - minimum) }
		if C.mprotect(address, usize(segment.vm_size), int(segment.initial_protection)) != 0 {
			loaded.close()
			return error('cannot protect Mach-O segment ${segment.name}')
		}
	}
	return loaded
}

fn read_cocoa_file(path string, maximum u64) ![]u8 {
	info := desktop_stat(path) or { return error('Cocoa bundle file not found: ${path}') }
	if info.is_dir || info.size == 0 || info.size > maximum {
		return error('invalid Cocoa file size: ${path}')
	}
	mut data := []u8{len: int(info.size)}
	if desktop_read_file(path, data.data, info.size) != i64(info.size) {
		unsafe { data.free() }
		return error('cannot read Cocoa bundle file: ${path}')
	}
	return data
}

fn register_macho_symbols(mut runtime CocoaRuntime, parsed &macho.Image) ! {
	symbols := parsed.symbols()!
	for symbol in symbols {
		if !symbol.defined || symbol.value < runtime.image.minimum_vm
			|| symbol.value - runtime.image.minimum_vm >= runtime.image.size {
			continue
		}
		address := u64(runtime.image.base) + symbol.value - runtime.image.minimum_vm
		if symbol.name.starts_with('_OBJC_CLASS_\$_') {
			name := symbol.name['_OBJC_CLASS_\$_'.len..]
			runtime.classes << &CocoaClass{ name: name, address: address }
		} else if symbol.name.starts_with('-[') && symbol.name.ends_with(']') {
			separator := symbol.name.index(' ') or { continue }
			runtime.methods << CocoaMethod{
				class_name: symbol.name[2..separator]
				selector: symbol.name[separator + 1..symbol.name.len - 1]
				address: address
			}
		}
	}
}

fn load_cocoa_runtime(bundle_path string) !&CocoaRuntime {
	mut plist := read_cocoa_file('${bundle_path}/Contents/Info.plist', 64 * 1024)!
	executable_name := bundle.executable_name(plist) or {
		unsafe { plist.free() }
		return err
	}
	unsafe { plist.free() }
	executable := '${bundle_path}/Contents/MacOS/${executable_name}'
	mut data := read_cocoa_file(executable, cocoa_executable_limit)!
	if data.len < 32 {
		unsafe { data.free() }
		return error('Cocoa executable is truncated')
	}
	defer {
		unsafe { data.free() }
	}
	parsed := macho.parse(data, macho.cpu_type_arm64)!
	mut runtime := &CocoaRuntime{}
	for name in ['NSObject', 'NSConstantString', 'NSApplication', 'NSWindow', 'NSView', 'NSButton',
		'NSTextField'] {
		runtime.add_class(name)
	}
	unsafe { active_cocoa_runtime = runtime }
	runtime.image = load_macho(&parsed) or {
		unsafe { active_cocoa_runtime = nil }
		return err
	}
	register_macho_symbols(mut runtime, &parsed) or {
		runtime.image.close()
		unsafe { active_cocoa_runtime = nil }
		return err
	}
	entry := unsafe { CocoaEntry(voidptr(runtime.image.entry)) }
	status := entry(0, unsafe { nil })
	unsafe { active_cocoa_runtime = nil }
	if status != 0 || runtime.window == 0 {
		runtime.image.close()
		return error('Cocoa application exited before creating a window')
	}
	return runtime
}

// CocoaApp is the same NativeApp boundary used by Vinix-native clients. The
// model and callbacks remain inside the loaded Objective-C process image.
@[heap]
struct CocoaApp {
mut:
	runtime &CocoaRuntime = unsafe { nil }
}

fn open_cocoa_calculator(mut desktop Desktop) !NativeApp {
	return open_cocoa_calculator_at(cocoa_calculator_bundle, mut desktop)
}

fn open_cocoa_calculator_at(bundle_path string, mut _ Desktop) !NativeApp {
	return &CocoaApp{ runtime: load_cocoa_runtime(bundle_path)! }
}

fn cocoa_ui_frame(frame CocoaRect, height f64) ui2.Rect {
	return ui2.rect(frame.x, height - frame.y - frame.height, frame.width, frame.height)
}

fn (mut app CocoaApp) build(size ui2.Rect) !ui2.Element {
	window := app.runtime.object(app.runtime.window) or { return error('Cocoa window disappeared') }
	content := app.runtime.object(window.content_view) or { return error('Cocoa content view disappeared') }
	mut children := []ui2.Element{cap: content.children.len}
	for address in content.children {
		object := app.runtime.object(address) or { continue }
		frame := cocoa_ui_frame(object.frame, size.height)
		match object.kind {
			.label {
				children << ui2.label('cocoa.display', object.text, frame, ui2.TextStyle{
					color: 0x111827
					size: 28
					align: .right
				})
			}
			.button {
				id := '${cocoa_action_prefix}${address}'
				operator := object.tag >= 11 && object.tag <= 15
				clear := object.tag == 100
				children << ui2.button(id, object.text, frame, ui2.BoxStyle{
					bg: if clear {
						u32(0xef4444)
					} else if operator { u32(0x3478d4) } else { u32(0xf8fafc) }
					radius: 8
				}, ui2.TextStyle{
					color: if clear || operator { u32(0xffffff) } else { u32(0x111827) }
					size: 18
					bold: object.tag == 15
					align: .center
				})
			}
			else {}
		}
	}
	return ui2.screen(0x1f2937, children)
}

fn (mut app CocoaApp) handle(event_id string) ! {
	if !event_id.starts_with(cocoa_action_prefix) {
		return error('unknown Cocoa action')
	}
	address := event_id[cocoa_action_prefix.len..].u64()
	button := app.runtime.object(address) or { return error('Cocoa button no longer exists') }
	if button.kind != .button || button.target == 0 || button.action == 0 {
		return error('Cocoa button has no target/action')
	}
	unsafe { active_cocoa_runtime = app.runtime }
	app.runtime.invoke(button.target, button.action, address)
	unsafe { active_cocoa_runtime = nil }
}

fn (mut app CocoaApp) close_app() {
	if unsafe { app.runtime != nil } {
		app.runtime.image.close()
	}
}
