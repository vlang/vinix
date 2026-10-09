// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

$if arm64 {
	#flag @VMODROOT/abi/dispatch.S
}

#include <stdlib.h>
#include "@VMODROOT/abi/dispatch.h"

fn C.calloc(usize, usize) voidptr
fn C.ios_ref_change(&i64, i64) i64
fn C.ios_ref_try_retain(&i64) i32
fn C.ios_objc_msgsend()
fn C.ios_objc_super()
fn C.ios_snprintf()
fn C.strtod(&char, &&char) f64
fn C.snprintf(&char, usize, &char, ...voidptr) int

struct AbiClass {
mut:
	isa    u64
	parent u64
	cache  [2]u64
	data   u64
}

struct ObjClass {
mut:
	name    string
	parent  u64
	size    u32
	meta    bool
	methods map[string]u64
	owned   bool
	load_imp u64
	initializing bool
	initialized bool
	method_info map[string]&ObjMethod
	ivars map[string]&ObjIvar
	dynamic bool
	registered bool
	instances i64
}

// The header is private to Vinix. The returned object still begins with the
// compiler's ordinary 8-byte isa and uses the Mach-O's nonfragile ivar offsets.
struct ObjHeader {
mut:
	refs        i64
	native_size u32
	text        &char = unsafe { nil }
	text_length int
	frame       ObjRect
	color       u32
	font_size   f64 = 17
	radius      f64
	tag         i64
	align       int
	target      u64 // UIControl targets are non-owning.
	action      u64
	fields      [9]u64
	children    [64]u64
	child_count int
	items       []u64
	keys        []u64
	cf_raw_keys bool // NULL CoreFoundation callbacks store non-owning pointers.
	cf_raw_values bool
	cf_boolean bool
	gestures    []u64
	mutation    u64
	parent_view u64 // Non-owning, cleared when detached.
	number      i64
	section     i64
	valid       bool
	deadline    i64
	repeat      bool
	loaded      bool
	data []u8
	file voidptr
	external_data u64
	external_size u64
	free_data bool
	provider_info voidptr
	provider_release u64
	real_number f64
	is_real bool
	graphics voidptr // Optional Mesa backend; never a native Objective-C ivar.
	font_face voidptr // Optional FreeType face, disposed before its descriptor.
	autoresizing u64
	multiple_touch bool
	content_scale f64 = 1
	deferred_system_edges u64
	home_indicator_hidden bool
	idle_timer_disabled bool
	accessibility &AccessibilityState = unsafe { nil }
	bitmap &BitmapState = unsafe { nil }
}

struct ObjRect {
mut:
	x      f64
	y      f64
	width  f64
	height f64
}

struct RegisterFrame {
mut:
	x     [10]u64
	q     [16]u64
	stack u64 // Original Darwin stack, including variadic arguments.
}

struct ObjRuntime {
mut:
	classes      map[u64]&ObjClass
	names        map[string]u64
	pool_key u64
	graphics_key u64
	window       u64
	screen       u64
	live         i64
	trace        bool
	constants    map[u64]bool
	constant_utf8 map[u64]string
	load_classes []u64
	load_categories []ObjLoad
	framework_data map[string]u64
	framework_objects []u64
	weak         map[u64]u64 // Location -> object; weak loads retain before returning.
	timers       []u64
	display_links []u64
	run_loop u64
	main_thread u64
	first_responder u64
	native_touch u64
	block_refs   map[u64]int
	block_isa    [3]u64
	transform    [6]f64
	bundle       string
	device u64
	bundle_object u64
	application u64
	notification_center u64
	audio_session u64
	audio_converters map[u64]&AudioConverter
	audio_units map[u64]&AudioUnit
	audio_graphs map[u64]&AudioGraph
	defaults u64
	locale u64
	empty_dictionary u64
	observers []&NotificationObserver
	selectors    []string
	selector_names map[string]u64
	dirty        bool
	pointer_down bool
	pointer_x    int
	pointer_y    int
	voice_over_running bool
	zoom_gesture_conflict bool
}

__global ios_runtime = &ObjRuntime(unsafe { nil })

fn objc_start() {
	ios_runtime = &ObjRuntime{ trace: os.getenv('VINIX_IOS_TRACE') == '1' }
	if C.ios_key_create(unsafe { &ios_runtime.pool_key }, unsafe { voidptr(objc_pool_free) }) != 0 {
		panic('iOS: cannot create autorelease TLS')
	}
	if C.ios_key_create(unsafe { &ios_runtime.graphics_key }, unsafe { voidptr(ui_context_cleanup) }) != 0 { panic('iOS: cannot create graphics TLS') }
	ios_runtime.timers.flags |= .noslices
	ios_runtime.load_classes.flags |= .noslices
	ios_runtime.load_categories.flags |= .noslices
	ios_runtime.display_links.flags |= .noslices
	ios_runtime.main_thread = u64(C.pthread_self())
	ios_runtime.observers.flags |= .noslices
	ios_runtime.selectors.flags |= .noslices
	ios_runtime.transform = [f64(1), 0, 0, 1, 0, 0]!
	for name in ['NSObject', 'NSString', 'NSNumber', 'NSIndexPath', 'NSArray', 'NSMutableArray',
		'NSDictionary', 'NSMutableDictionary', 'NSTimer', 'UIColor', 'UIFont', 'CALayer', 'UIResponder',
		'UIApplication', 'UIView', 'UILabel', 'UIControl', 'UIButton', 'UIWindow', 'UIViewController',
		'UIScreen', 'UIGestureRecognizer', 'UISwipeGestureRecognizer', 'UIAlertView',
        'NSData', 'NSMutableData', 'NSLocale', 'NSBundle', 'NSNotification', 'NSNotificationCenter', 'NSCharacterSet',
        'NSAttributedString', 'NSAssertionHandler', 'NSFileHandle', 'NSOperationQueue',
        'NSPropertyListSerialization', 'NSRunLoop', 'NSURL', 'NSURLComponents', 'NSUserDefaults',
        'UIDevice', 'UIScene', 'UIWindowScene', 'UISceneSession', 'UISceneConnectionOptions', 'UIOpenURLContext', 'NSSet', 'UITouch', 'UIEvent', 'UITraitCollection', 'UIImage', 'UIPasteboard',
        'UIActivityViewController', 'UIDocumentPickerViewController', 'UIImagePickerController',
        'UIScreenEdgePanGestureRecognizer', 'UISelectionFeedbackGenerator', 'CADisplayLink',
		'UIAccessibilityElement',
        'CAMetalLayer', 'GLKView', 'EAGLContext', 'CMMotionManager', 'CLLocationManager',
        'AVAudioSession', 'AVCaptureDevice', 'AVCaptureDeviceInput', 'AVCaptureSession',
        'AVCaptureVideoDataOutput', 'AVCaptureVideoPreviewLayer', 'PHPhotoLibrary',
		'VinixCTDescriptor', 'VinixCTFont', 'VinixCTLine', 'VinixCGContext', 'VinixCGColorSpace', 'VinixCGColor', 'VinixCGImage', 'VinixCGDataProvider', 'VinixSecCertificate', 'VinixSecKey', 'VinixSecPolicy', 'VinixCFError'] {
		parent := match name {
			'NSObject' { u64(0) }
			'UIView', 'UIViewController', 'UIApplication' { ios_runtime.names['UIResponder'] }
			'UILabel', 'UIControl', 'UIWindow', 'UIAlertView', 'GLKView' { ios_runtime.names['UIView'] }
			'UIActivityViewController', 'UIDocumentPickerViewController', 'UIImagePickerController' { ios_runtime.names['UIViewController'] }
            'CAMetalLayer', 'AVCaptureVideoPreviewLayer' { ios_runtime.names['CALayer'] }
            'UIScreenEdgePanGestureRecognizer' { ios_runtime.names['UIGestureRecognizer'] }
			'UIWindowScene' { ios_runtime.names['UIScene'] }
			'UIButton' { ios_runtime.names['UIControl'] }
			'UIAccessibilityElement' { ios_runtime.names['UIResponder'] }
			'NSMutableArray' { ios_runtime.names['NSArray'] }
			'NSMutableDictionary' { ios_runtime.names['NSDictionary'] }
			'NSMutableData' { ios_runtime.names['NSData'] }
			'UISwipeGestureRecognizer' { ios_runtime.names['UIGestureRecognizer'] }
			else { ios_runtime.names['NSObject'] }
		}
		cls := unsafe { &AbiClass(C.calloc(2, sizeof(AbiClass))) }
		meta := u64(cls) + sizeof(AbiClass)
		unsafe {
			cls.isa = meta
			cls.parent = parent
		}
		mut metaclass := unsafe { &AbiClass(meta) }
		metaclass.isa = if parent == 0 { meta } else { read64(parent) }
		metaclass.parent = if parent == 0 { u64(cls) } else { read64(parent) }
		ios_runtime.classes[u64(cls)] = &ObjClass{ name: name, parent: parent, size: 8, owned: true }
		ios_runtime.classes[meta] = &ObjClass{ name: name, parent: metaclass.parent, size: 40, meta: true }
		ios_runtime.names[name] = u64(cls)
	}
	mut root := ios_runtime.classes[ios_runtime.names['NSObject']] or { panic('iOS: missing NSObject') }
	root.ivars['isa'] = &ObjIvar{name: 'isa'.clone(), types: '#'.clone(), offset: 0, size: 8}
}

fn read64(address u64) u64 { return unsafe { *(&u64(address)) } }

fn read32(address u64) u32 { return unsafe { *(&u32(address)) } }

fn write32(address u64, value u32) {
	unsafe { *(&u32(address)) = value }
}

fn ctext(address u64) string {
	if address == 0 { return '' }
	return unsafe { tos(&u8(address), int(darwin_strlen(&char(address)))) }
}

fn obj_header(object u64) &ObjHeader {
	return unsafe { &ObjHeader(object - sizeof(ObjHeader)) }
}

fn objc_allocate(cls u64) u64 {
	objc_initialize(cls)
	info := ios_runtime.classes[cls] or { panic('iOS: allocation of an unknown class') }
	if info.dynamic && !info.registered { panic('iOS: allocating an instance of an unregistered class') }
	memory := C.calloc(1, sizeof(ObjHeader) + usize(info.size))
	if memory == unsafe { nil } { panic('iOS: out of memory') }
	mut header := unsafe { &ObjHeader(memory) }
	header.refs = 1
	header.native_size = info.size
	header.font_size = 17
	header.content_scale = 1
	// calloc does not initialize V array element sizes. Set them explicitly
	// before any collection/gesture push can grow these buffers.
	header.items = []u64{}
	header.keys = []u64{}
	header.gestures = []u64{}
	header.data = []u8{}
	header.items.flags |= .noslices
	header.keys.flags |= .noslices
	header.gestures.flags |= .noslices
	object := u64(memory) + sizeof(ObjHeader)
	unsafe { *(&u64(object)) = cls }
	if objc_is_kind(object, ios_runtime.names['NSOperationQueue']) { header.number = -1 }
	C.ios_ref_change(unsafe { &ios_runtime.live }, 1)
	C.ios_ref_change(unsafe { &info.instances }, 1)
	return objc_construct(object, cls)
}

fn objc_retain(object u64) u64 {
	if object != 0 && is_block(object) { return block_retain(object) }
	if object != 0 && object !in ios_runtime.classes && object !in ios_runtime.constants {
		mut header := obj_header(object)
		if C.ios_ref_try_retain(unsafe { &header.refs }) == 0 { panic('iOS: retaining a deallocated object') }
	}
	return object
}

type ObjVoid = fn (u64, &char)
type ObjInit = fn (u64, &char) u64
type ObjAction = fn (u64, &char, u64)
type ObjLaunch = fn (u64, &char, u64, u64) bool

fn native_method(cls u64, selector string) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut current := cls
	for _ in 0 .. 128 {
		if current == 0 { return 0 }
		info := ios_runtime.classes[current] or { panic('iOS: unknown Objective-C class') }
		if imp := info.methods[selector] { return imp }
		current = info.parent
	}
	panic('iOS: cyclic Objective-C superclass chain')
}

fn objc_release(object u64) {
	if object == 0 || object in ios_runtime.classes || object in ios_runtime.constants { return }
	if is_block(object) {
		block_release(object)
		return
	}
	mut header := obj_header(object)
	previous := C.ios_ref_change(unsafe { &header.refs }, -1)
	if previous <= 0 { panic('iOS: over-release') }
	if previous != 1 { return }
	// Zero weak slots before destructors can observe a dying object.
	C.ios_objc_initialize_lock()
	for location, referent in ios_runtime.weak {
		if referent == object {
			unsafe { *(&u64(location)) = 0 }
			ios_runtime.weak[location] = 0
		}
	}
	C.ios_objc_initialize_unlock()
	dealloc := native_method(read64(object), 'dealloc')
	if dealloc != 0 {
		unsafe { ObjVoid(voidptr(dealloc))(object, c'dealloc') }
	}
	// Invoke each class's compiler-generated ARC destructor once, derived first.
	mut cls := read64(object)
	for _ in 0 .. 128 {
		if cls == 0 { break }
		info := ios_runtime.classes[cls] or { panic('iOS: unknown object class') }
		if imp := info.methods['.cxx_destruct'] {
			destructor := unsafe { ObjVoid(voidptr(imp)) }
			destructor(object, c'.cxx_destruct')
		}
		cls = info.parent
	}
	$if ios_gles ? { gles_dispose(object) }
	$if ios_text ? { text_dispose(object) }
	accessibility_dispose(object)
	bitmap_dispose(object)
	cg_provider_dispose(object)
	for field in header.fields { objc_release(field) }
	for i in 0 .. header.child_count {
		mut child := obj_header(header.children[i])
		child.parent_view = 0
		objc_release(header.children[i])
	}
	if !header.cf_raw_values { for item in header.items { objc_release(item) } }
	if !header.cf_raw_keys { for key in header.keys { objc_release(key) } }
	for gesture in header.gestures { objc_release(gesture) }
	unsafe {
		header.items.free()
		header.keys.free()
		header.gestures.free()
		header.data.free()
	}
	if header.file != unsafe { nil } { C.fclose(header.file) }
	if header.free_data { C.free(unsafe { voidptr(header.external_data) }) }
	objc_destroy_weak(unsafe { &header.target })
	if ios_runtime.first_responder == object { ios_runtime.first_responder = 0 }
	C.free(header.text)
	info := ios_runtime.classes[read64(object)] or { panic('iOS: unknown released object class') }
	C.free(header)
	C.ios_ref_change(unsafe { &info.instances }, -1)
	C.ios_ref_change(unsafe { &ios_runtime.live }, -1)
}

fn objc_store_strong(location &u64, object u64) {
	old := unsafe { *location }
	objc_retain(object)
	unsafe { *location = object }
	objc_release(old)
}

fn objc_new(cls u64) u64 {
	object := objc_allocate(cls)
	imp := native_method(cls, 'init')
	if imp != 0 { return unsafe { ObjInit(voidptr(imp))(object, c'init') } }
	return object
}

fn objc_stop() {
	audio_stop()
	ui_context_stop()
	$if ios_gles ? { gles_set_current(0) }
	display_links_stop()
	dispatch_main_stop()
	objc_release(ios_runtime.native_touch)
	ios_runtime.native_touch = 0
	for timer in ios_runtime.timers {
		timer_invalidate(timer)
		objc_release(timer)
	}
	ios_runtime.timers.clear()
	objc_release(ios_runtime.window)
	objc_release(ios_runtime.screen)
	objc_release(ios_runtime.device)
	objc_release(ios_runtime.bundle_object)
	objc_release(ios_runtime.application)
	notification_stop()
	objc_release(ios_runtime.notification_center)
	objc_release(ios_runtime.audio_session)
	objc_release(ios_runtime.defaults)
	objc_release(ios_runtime.locale)
	objc_release(ios_runtime.run_loop)
	for object in ios_runtime.framework_objects { objc_release(object) }
	for _, address in ios_runtime.framework_data { C.free(unsafe { voidptr(address) }) }
	objc_pool_pop(1)
	objc_pool_free(C.pthread_getspecific(ios_runtime.pool_key))
	$if ios_text ? { text_stop() }
	C.pthread_setspecific(ios_runtime.pool_key, unsafe { nil })
	C.pthread_key_delete(ios_runtime.pool_key)
	if ios_runtime.live != 0 {
		eprintln('iOS: ${ios_runtime.live} Objective-C objects still owned at shutdown')
	}
	if ios_runtime.block_refs.len != 0 { eprintln('iOS: heap blocks still owned at shutdown') }
	for _, text in ios_runtime.constant_utf8 { unsafe { text.free() } }
	for address, info in ios_runtime.classes {
		objc_class_metadata_free(info)
		if info.owned { C.free(unsafe { voidptr(address) }) }
	}
	// V's []string.free() also frees the owned strings.
	unsafe { ios_runtime.selectors.free(); ios_runtime.selector_names.free() }
}

@[export: 'ios_format_double']
fn format_double(destination &char, size usize, format &char, value f64) int {
	if darwin_strcmp(format, c'%.12g') != 0 {
		panic('iOS: unsupported snprintf format: ' + ctext(u64(format)))
	}
	return C.snprintf(destination, size, c'%.12g', value)
}

fn runtime_symbol(library string, symbol string) !u64 {
	$if ios_text ? {
		if library in ['/System/Library/Frameworks/CoreText.framework/CoreText', '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics'] {
			if address := text_symbol(symbol) { return address }
		}
	}
	$if ios_gles ? {
		if library == '/usr/lib/libz.1.dylib' { if address := gles_zlib_symbol(symbol) { return address } }
		if library == '/System/Library/Frameworks/OpenGLES.framework/OpenGLES' {
			if address := gles_symbol(symbol) { return address }
		}
	}
	$if ios_cxx ? {
		if library == '/usr/lib/libc++.1.dylib' || (library == '/usr/lib/libSystem.B.dylib' && symbol == '__Unwind_Resume') {
			return cxx_symbol(symbol)
		}
	}
	if library == '/usr/lib/libSystem.B.dylib' {
		if address := system_data_symbol(symbol) { return address }
		if address := block_symbol(symbol) { return address }
		if symbol == '_strtod' { return u64(unsafe { voidptr(C.strtod) }) }
		return libsystem_symbol(library, symbol)
	}
	if library == '/usr/lib/libobjc.A.dylib' {
		if address := objc_runtime_symbol(symbol) { return address }
		if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'] {
			if symbol.starts_with(prefix) {
				cls := ios_runtime.names[symbol[prefix.len..]] or { break }
				return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			}
		}
		address := match symbol {
			'_objc_msgSend' { unsafe { voidptr(C.ios_objc_msgsend) } }
			'_objc_getClass' { unsafe { voidptr(objc_get_class) } }
			'_objc_msgSendSuper2' { unsafe { voidptr(C.ios_objc_super) } }
			'_objc_retain', '_objc_retainAutoreleasedReturnValue' {
				unsafe { voidptr(objc_retain) }
			}
			'_objc_release' { unsafe { voidptr(objc_release) } }
			'_objc_retainAutorelease', '_objc_retainAutoreleaseReturnValue' { unsafe { voidptr(objc_retain_autorelease) } }
			'_objc_setProperty_nonatomic' { unsafe { voidptr(objc_property_strong) } }
			'_objc_autoreleaseReturnValue' { unsafe { voidptr(objc_autorelease) } }
			'_objc_unsafeClaimAutoreleasedReturnValue' { unsafe { voidptr(objc_unsafe_claim) } }
			'_objc_alloc' { unsafe { voidptr(objc_allocate) } }
			'_objc_opt_new' { unsafe { voidptr(objc_new) } }
			'_objc_alloc_init' { unsafe { voidptr(objc_new) } }
			'_objc_opt_class' { unsafe { voidptr(objc_class) } }
			'_objc_opt_isKindOfClass' { unsafe { voidptr(objc_is_kind) } }
			'_objc_opt_respondsToSelector' { unsafe { voidptr(objc_responds) } }
			'_objc_retainBlock' { unsafe { voidptr(block_copy) } }
			'_objc_setProperty_nonatomic_copy' { unsafe { voidptr(objc_property_copy) } }
			'_objc_initWeak', '_objc_storeWeak' { unsafe { voidptr(objc_store_weak) } }
			'_objc_destroyWeak' { unsafe { voidptr(objc_destroy_weak) } }
			'_objc_loadWeakRetained' { unsafe { voidptr(objc_load_weak) } }
			'_objc_copyWeak' { unsafe { voidptr(objc_copy_weak) } }
			'_objc_enumerationMutation' { unsafe { voidptr(objc_enumeration_mutation) } }
			'_objc_storeStrong' { unsafe { voidptr(objc_store_strong) } }
			'_objc_autoreleasePoolPush' { unsafe { voidptr(objc_pool_push) } }
			'_objc_autoreleasePoolPop' { unsafe { voidptr(objc_pool_pop) } }
			'__objc_empty_cache' { unsafe { voidptr(ios_runtime) } } // Unused: lookup is in V.
			else { return error('iOS: Objective-C symbol is not implemented: ${symbol}') }
		}
		return u64(address)
	}
	if address := framework_symbol(library, symbol) { return address }
	if library !in ['/System/Library/Frameworks/Foundation.framework/Foundation',
		'/System/Library/Frameworks/UIKit.framework/UIKit',
		'/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics'] {
		return error('iOS: library is not implemented: ${library} (${symbol})')
	}
	if symbol == '_UIApplicationMain' { return u64(unsafe { voidptr(ui_application_main) }) }
	if symbol == '_NSStringFromClass' { return u64(unsafe { voidptr(ns_string_from_class) }) }
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	if symbol == '_CGAffineTransformIdentity' { return u64(unsafe { &ios_runtime.transform[0] }) }
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'] {
		if symbol.starts_with(prefix) {
			cls := ios_runtime.names[symbol[prefix.len..]] or { break }
			return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
		}
	}
	return error('iOS: framework symbol is not implemented: ${symbol}')
}

// Bounds are checked against loaded segments, not just the mmap reservation.
struct ObjMetadata {
	image  macho.Image
	layout macho.Layout
	base   u64
}

fn (m ObjMetadata) range(address u64, size u64, writable bool) ! {
	if size > m.layout.size { return error('iOS: invalid Objective-C metadata range') }
	for segment in m.image.segments {
		if segment.name == '__PAGEZERO' { continue }
		start := m.base + segment.address - m.layout.base
		if address >= start && address - start <= segment.filesize
			&& size <= segment.filesize - (address - start)
			&& (!writable || segment.prot & 2 != 0) {
			return
		}
	}
	return error('iOS: Objective-C metadata lies outside a loaded segment')
}

fn (m ObjMetadata) string_at(address u64) !string {
	for length in 0 .. 1024 {
		m.range(address + u64(length), 1, false)!
		if unsafe { *(&u8(address + u64(length))) } == 0 {
			return unsafe { tos(&u8(address), length) }
		}
	}
	return error('iOS: Objective-C metadata string exceeds 1023 bytes')
}

struct ObjImageMethod {
	imp u64
	types string
}

fn (m ObjMetadata) methods(list u64) !map[string]ObjImageMethod {
	mut methods := map[string]ObjImageMethod{}
	if list == 0 { return methods }
	m.range(list, 8, false)!
	flags := read32(list)
	stride := flags & 0xfffc
	count := read32(list + 4)
	small := flags & 0x80000000 != 0
	if count > 4096 || stride != if small { u32(12) } else { u32(24) } {
		return error('iOS: unsupported Objective-C method list')
	}
	m.range(list + 8, u64(count) * stride, false)!
	for i in 0 .. count {
		entry := list + 8 + u64(i) * stride
		mut name := u64(0)
		mut imp := u64(0)
		mut types := u64(0)
		if small {
			name = u64(i64(entry) + i64(i32(read32(entry))))
			if flags & 0x40000000 == 0 {
				m.range(name, 8, false)!
				name = read64(name)
			}
			imp = u64(i64(entry + 8) + i64(i32(read32(entry + 8))))
			types = u64(i64(entry + 4) + i64(i32(read32(entry + 4))))
		} else {
			name = read64(entry)
			imp = read64(entry + 16)
			types = read64(entry + 8)
		}
		m.range(imp, 4, false)!
		mut executable := false
		for segment in m.image.segments {
			start := m.base + segment.address - m.layout.base
			if imp >= start && imp - start < segment.filesize && segment.prot & 4 != 0 {
				executable = true
			}
		}
		if !executable || imp % 4 != 0 {
			return error('iOS: method implementation is not executable')
		}
		selector := m.string_at(name)!
		methods[selector] = ObjImageMethod{imp, if types == 0 { '' } else { m.string_at(types)! }}
	}
	return methods
}

fn (m ObjMetadata) register(cls u64, depth int) ! {
	if cls in ios_runtime.classes { return }
	if depth > 64 { return error('iOS: cyclic Objective-C class metadata') }
	m.range(cls, 40, false)!
	ro := read64(cls + 32) & ~u64(7)
	m.range(ro, 72, false)!
	flags := read32(ro)
	if flags & 0x40 != 0 { return error('iOS: Swift class metadata is not implemented') }
	parent := read64(cls + 8)
	if parent != 0 { m.register(parent, depth + 1)! }
	name := m.string_at(read64(ro + 24))!
	meta := flags & 1 != 0
	start := read32(ro + 4)
	mut size := read32(ro + 8)
	if size < start || size > 1024 * 1024 { return error('iOS: invalid Objective-C instance size') }
	if !meta && parent != 0 {
		parent_info := ios_runtime.classes[parent] or { return error('iOS: missing superclass') }
		parent_size := parent_info.size
		if parent_size > start {
			// Slide the compiler's exported ivar offset cells before sealing data.
			delta := (parent_size - start + 7) & ~u32(7)
			ivars := read64(ro + 48)
			if ivars != 0 {
				m.range(ivars, 8, false)!
				stride := read32(ivars)
				count := read32(ivars + 4)
				if stride != 32 || count > 4096 {
					return error('iOS: unsupported Objective-C ivar list')
				}
				m.range(ivars + 8, u64(count) * stride, false)!
				for i in 0 .. count {
					offset := read64(ivars + 8 + u64(i) * stride)
					m.range(offset, 4, true)!
					write32(offset, read32(offset) + delta)
				}
			}
			size += delta
		}
	}
	methods := m.methods(read64(ro + 32))!
	defer { unsafe { methods.free() } }
	ios_runtime.classes[cls] = &ObjClass{
		name:    name
		parent:  parent
		size:    size
		meta:    meta
		load_imp: if meta { methods['load'].imp } else { u64(0) }
	}
	for selector, method in methods {
		objc_record_method(cls, unsafe { &char(selector.str) }, method.imp, unsafe { &char(method.types.str) }, false)
	}
	ivars := read64(ro + 48)
	if ivars != 0 {
		m.range(ivars, 8, false)!
		count := read32(ivars + 4)
		if read32(ivars) != 32 || count > 4096 { return error('iOS: unsupported Objective-C ivar list') }
		m.range(ivars + 8, u64(count) * 32, false)!
		mut info := ios_runtime.classes[cls] or { return error('iOS: missing ivar class') }
		for index in 0 .. count {
			entry := ivars + 8 + u64(index) * 32
			offset_cell := read64(entry)
			m.range(offset_cell, 4, false)!
			offset := read32(offset_cell)
			ivar_size := read32(entry + 28)
			if offset > size || ivar_size > size - offset { return error('iOS: ivar exceeds instance layout') }
			ivar_name := m.string_at(read64(entry + 8))!
			ivar_types := m.string_at(read64(entry + 16))!
			info.ivars[ivar_name] = &ObjIvar{name: ivar_name.clone(), types: ivar_types.clone(), offset: i64(offset), size: ivar_size}
		}
	}
	if !meta { ios_runtime.names[name] = cls }
}

fn objc_register_image(image macho.Image, layout macho.Layout, base u64) ! {
	m := ObjMetadata{image, layout, base}
	mut classes := []u64{}
	for segment in image.segments {
		for section in segment.sections {
			if section.name == '__cfstring' {
				if section.size % 32 != 0 { return error('iOS: invalid constant string section') }
				start := base + section.address - layout.base
				m.range(start, section.size, false)!
				for offset := u64(0); offset < section.size; offset += 32 {
					address := start + offset
					m.constant_string(address)!
					ios_runtime.constants[address] = true
				}
			}
			if section.name !in ['__objc_classlist', '__objc_nlclslist'] { continue }
			if section.size % 8 != 0 || section.size > 32768 {
				return error('iOS: invalid Objective-C class list')
			}
			address := base + section.address - layout.base
			m.range(address, section.size, false)!
			for offset := u64(0); offset < section.size; offset += 8 {
				classes << read64(address + offset)
			}
		}
	}
	for cls in classes { m.register(cls, 0)! }
	for cls in classes { m.register(read64(cls), 0)! }
	ios_runtime.load_classes << classes
	unsafe { classes.free() }
	mut attached := map[u64]bool{}
	for segment in image.segments {
		for section in segment.sections {
			if section.name !in ['__objc_catlist', '__objc_nlcatlist'] { continue }
			if section.size % 8 != 0 || section.size > 32768 { return error('iOS: invalid Objective-C category list') }
			address := base + section.address - layout.base
			m.range(address, section.size, false)!
			for offset := u64(0); offset < section.size; offset += 8 {
				category := read64(address + offset)
				if category in attached { continue }
				attached[category] = true
				m.attach_category(category)!
			}
		}
	}
	unsafe { attached.free() }
	// Relative method lists may point indirectly through these slots. Read all
	// image metadata first, then replace slots with process-wide canonical SELs.
	for segment in image.segments {
		for section in segment.sections {
			if section.name != '__objc_selrefs' { continue }
			if section.size % 8 != 0 { return error('iOS: invalid Objective-C selector references') }
			address := base + section.address - layout.base
			m.range(address, section.size, true)!
			for offset := u64(0); offset < section.size; offset += 8 {
				name := m.string_at(read64(address + offset))!
				selector := objc_selector(unsafe { &char(name.str) })
				unsafe { *(&u64(address + offset)) = selector }
			}
		}
	}
}
