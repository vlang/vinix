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

// Metadata is private to Vinix and stored separately from object bytes. The
// object begins with the ordinary isa, including when its caller supplies it.
struct ObjHeader {
mut:
	refs        i64
	cls u64
	caller_storage bool
	image_dictionary bool // Immortal image bytes; owned metadata borrows its members.
	image_dictionary_next u64
	releasing bool
	destroying bool
	destroyed bool
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
	unsigned_number bool
	json_immutable bool
	set_owned bool
	set_initialized bool
	set_mutable bool
	set_reading int // Reject mutation while membership callbacks inspect storage.
	set_mutating bool
	condition_owned bool
	condition_initialized bool
	thread &FoundationThread = unsafe { nil }
	auth_owned bool
	auth &WebAuthState = unsafe { nil }
	image_view_owned bool
	image_view &ImageViewState = unsafe { nil }
	image_view_array bool
	process_arguments_array bool
	date_owned bool
	date_initialized bool
	input_stream_owned bool
	input_stream_initialized bool
	input_stream_file bool
	input_stream_directory bool
	input_stream_fd int
	input_stream_status u64
	input_stream_position u64
	connection_owned bool
	connection_initialized bool
	connection_started bool
	connection_pending bool
	connection_queued bool
	connection_running bool
	connection_scheduled bool
	connection_cancelled bool
	uuid_owned bool
	pool_owned bool
	pool_initialized bool
	pool_thread u64
	pool_token u64
	uuid_bytes [16]u8
	cookie_owned bool
	webkit &WebKitState = unsafe { nil }
	webkit_array bool // Read-only script list; its contents change through its controller.
	webview &WebViewState = unsafe { nil }
	webview_owned bool
	request &URLRequestState = unsafe { nil }
	request_owned bool
	response &URLResponseState = unsafe { nil }
	response_owned bool
	response_headers bool
	alert &AlertState = unsafe { nil }
	alert_owned bool
	alert_button bool
	presenter u64 // Weak: a presenter owns its presented controller in fields[8].
	value_owned bool
	value_initialized bool
	web_history bool
	web_history_array bool
	graphics voidptr // Optional Mesa backend; never a native Objective-C ivar.
	font_face voidptr // Optional FreeType face, disposed before its descriptor.
	autoresizing u64
	layout_anchors &LayoutAnchors = unsafe { nil }
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
	objects map[u64]&ObjHeader // Object address -> owned metadata; protected by the recursive runtime lock.
	null_object u64
	associations map[u64]&ObjAssociations // Object -> key/value table, under the same recursive lock.
	monitors map[u64]&ObjMonitor
	swift_buffers map[u64]u64 // Owned UTF-8 array allocation -> element count, under the runtime lock.
	swift_strings map[u64]u64 // Owned native-tail String allocation -> byte capacity, under the same lock.
	swift_arrays map[u64]SwiftArrayStorage // Typed tails and Element destruction witnesses, under the same lock.
	swift_heap map[u64]SwiftHeapStorage // Real app heap metadata and deallocation layout, under the same lock.
	swift_heap_sequence u64 // Distinguishes reentrant allocations that reuse a freed address.
	swift_empty_array u64 // Canonical sealed immortal empty storage, retired at quiescent shutdown.
	swift_arc_code u64 // Sealed ARM64 preserve-most entry points, released at quiescent teardown.
	swift_cstring_arena u64 // Sealed Swift closure/context/result adapter, retired after callbacks drain.
	swift_metadata_arena u64 // Adjacent sealed String metadata/accessor pages, under the runtime lock.
	swift_interpolation_arena u64 // Frozen interpolation metadata and TextOutputStream witnesses.
	swift_array_arena u64 // Array accessor/descriptor/witness pages and zero-filled generic cache.
	swift_array_metadata map[u64]u64 // Element metadata -> sealed Array metadata, under the runtime lock.
	swift_integer_arena u64 // Int metadata, value witnesses and Equatable/Hashable conformances.
	swift_foundation_arena u64 // Sealed CVarArg calls and Foundation's concrete String conformance.
	swift_void_arena u64 // Sealed empty-tuple full metadata and zero-size value witnesses.
	swift_unknown_value_arena u64 // Sealed Builtin.UnknownObject value witnesses.
	swift_error_arena u64 // Sealed ObjC value witnesses and the concrete CFError: Error conformance.
	swift_objc_metadata map[u64]u64 // Class -> canonical sealed Swift wrapper, under the runtime lock.
	swift_concurrency_code u64 // Sealed actor witness dispatcher and indirect priority getter.
	swift_concurrency_retired bool // Reject new resolution after quiescent teardown.
	swift_task_priority_arena u64 // Sealed TaskPriority accessor and read-only metadata/value witnesses.
	swift_task_alloc_top u64 // Shared no-current-task allocation stack; protected by the runtime lock.
	swift_task_alloc_count u64 // Live fallback allocations; shutdown requires the stack to drain.
	swift_tasks u64 // Intrusive owned task registry, under the runtime lock.
	swift_task_count u64
	swift_task_disposing u64 // Keep result destruction callbacks inside the runtime lifetime.
	swift_task_sequence u32
	swift_task_arena u64 // Sealed async adapters and read-only Task heap metadata.
	swift_task_key u64
	swift_task_key_live bool
	swift_task_sync u64 // Mutex/condition for queued and executing task callbacks.
	swift_task_jobs u64 // Protected by the task synchronization mutex.
	swift_hash_code u64 // Sealed generic Hashable forwarding entries, retired after callbacks drain.
	swift_fatal_code u64 // Assertion argument capture and BRK, retired at quiescent teardown.
	names        map[string]u64
	pool_key u64
	pool_sequence i64 = 2 // Globally distinct opaque tokens for this runtime lifetime.
	thread_key u64
	foundation_main_thread u64
	foundation_multithreaded bool
	foundation_thread_count int
	foundation_workers &FoundationWorker = unsafe { nil }
	foundation_worker_count int
	threads_stopping bool
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
	file_manager u64 // One owned NSFileManager cache reference, retired at shutdown.
	process_info u64 // One owned NSProcessInfo singleton reference.
	process_arguments u64 // Owned app arguments, configured before image initialization.
	distant_dates [2]u64 // Owned immutable date cache references, retired at shutdown.
	connections []u64 // Main-thread pending connections, one owning reference each.
	connection_callbacks int
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
	webkit_default_store u64
	webkit_worlds [128]u64 // Owned interned page/client/named worlds, retired at shutdown.
	webkit_world_count int = 2
	image_dictionaries u64 // Intrusive list retired after all collection/pool users.
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
	if C.ios_key_create(unsafe { &ios_runtime.thread_key }, unsafe { voidptr(ns_thread_cleanup) }) != 0 { panic('iOS: cannot create Foundation thread TLS') }
	ios_runtime.timers.flags |= .noslices
	ios_runtime.load_classes.flags |= .noslices
	ios_runtime.load_categories.flags |= .noslices
	ios_runtime.display_links.flags |= .noslices
	ios_runtime.connections.flags |= .noslices
	ios_runtime.main_thread = u64(C.pthread_self())
	ios_runtime.observers.flags |= .noslices
	ios_runtime.selectors.flags |= .noslices
	ios_runtime.transform = [f64(1), 0, 0, 1, 0, 0]!
	for name in ['NSObject', 'NSAutoreleasePool', 'NSFileManager', 'NSProcessInfo', 'NSDate', 'NSStream', 'NSInputStream', 'NSUUID', '_NSUUIDBridge', '__NSConcreteUUID', 'NSString', 'NSValue', 'NSConcreteValue', 'NSNumber', 'NSIndexPath', 'NSArray', 'NSMutableArray',
		'WKWebViewConfiguration', 'WKPreferences', 'WKUserContentController', 'WKProcessPool', 'WKWebsiteDataStore', 'WKWebpagePreferences', 'WKUserScript', 'WKContentWorld', 'WKNSArray',
		'NSDictionary', 'NSMutableDictionary', 'NSConstantDictionary', 'NSJSONSerialization', 'NSNull', 'NSError', 'NSCondition', 'NSThread', 'ASWebAuthenticationSession', 'GCKeyboard', 'NSHTTPCookie', 'NSHTTPCookieInternal', 'NSLayoutConstraint', 'NSLayoutAnchor',
		'NSLayoutXAxisAnchor', 'NSLayoutYAxisAnchor', 'NSLayoutDimension', 'NSTimer', 'UIColor', 'UIFont', 'CALayer', 'UIResponder',
		'UIApplication', 'UIView', 'UIImageView', 'UILabel', 'UIControl', 'UIButton', 'UIWindow', 'UIViewController',
		'UIScreen', 'UIGestureRecognizer', 'UISwipeGestureRecognizer', 'UIAlertView', 'UIAlertController', 'UIAlertAction',
        'NSData', 'NSMutableData', 'NSLocale', 'NSBundle', 'NSNotification', 'NSNotificationCenter', 'NSCharacterSet',
        'NSAttributedString', 'NSAssertionHandler', 'NSFileHandle', 'NSOperationQueue',
        'NSPropertyListSerialization', 'NSRunLoop', 'NSURL', 'NSURLComponents', 'NSURLRequest', 'NSMutableURLRequest', 'NSURLResponse', 'NSHTTPURLResponse', 'NSURLConnection', 'NSUserDefaults',
        'UIDevice', 'UIScene', 'UIWindowScene', 'UISceneSession', 'UISceneConnectionOptions', 'UIOpenURLContext', 'NSSet', 'NSMutableSet', 'UITouch', 'UIEvent', 'UITraitCollection', 'UIImage', 'UIPasteboard', 'WKWebView', 'WKBackForwardList',
        'UIActivityViewController', 'UIDocumentPickerViewController', 'UIImagePickerController',
        'UIScreenEdgePanGestureRecognizer', 'UISelectionFeedbackGenerator', 'CADisplayLink',
		'UIAccessibilityElement',
        'CAMetalLayer', 'GLKView', 'EAGLContext', 'CMMotionManager', 'CLLocationManager',
        'AVAudioSession', 'AVCaptureDevice', 'AVCaptureDeviceInput', 'AVCaptureSession',
        'AVCaptureVideoDataOutput', 'AVCaptureVideoPreviewLayer', 'PHPhotoLibrary',
		'VinixCTDescriptor', 'VinixCTFont', 'VinixCTLine', 'VinixCGContext', 'VinixCGColorSpace', 'VinixCGColor', 'VinixCGImage', 'VinixCGDataProvider', 'VinixSecCertificate', 'VinixSecKey', 'VinixSecPolicy', 'VinixSecTrust', 'VinixCFDate', 'VinixCFError'] {
		parent := match name {
			'NSObject' { u64(0) }
			'VinixCFDate' { ios_runtime.names['NSDate'] }
			'NSInputStream' { ios_runtime.names['NSStream'] }
			'NSNumber', 'NSConcreteValue' { ios_runtime.names['NSValue'] }
			'_NSUUIDBridge' { ios_runtime.names['NSUUID'] }
			'__NSConcreteUUID' { ios_runtime.names['_NSUUIDBridge'] }
			'UIView', 'UIViewController', 'UIApplication' { ios_runtime.names['UIResponder'] }
			'UIImageView', 'UILabel', 'UIControl', 'UIWindow', 'UIAlertView', 'GLKView' { ios_runtime.names['UIView'] }
			'WKWebView' { ios_runtime.names['UIView'] }
			'UIActivityViewController', 'UIDocumentPickerViewController', 'UIImagePickerController', 'UIAlertController' { ios_runtime.names['UIViewController'] }
            'CAMetalLayer', 'AVCaptureVideoPreviewLayer' { ios_runtime.names['CALayer'] }
            'UIScreenEdgePanGestureRecognizer' { ios_runtime.names['UIGestureRecognizer'] }
			'UIWindowScene' { ios_runtime.names['UIScene'] }
			'UIButton' { ios_runtime.names['UIControl'] }
			'UIAccessibilityElement' { ios_runtime.names['UIResponder'] }
			'NSMutableArray', 'WKNSArray' { ios_runtime.names['NSArray'] }
			'NSMutableSet' { ios_runtime.names['NSSet'] }
			'NSMutableDictionary', 'NSConstantDictionary' { ios_runtime.names['NSDictionary'] }
			'NSLayoutXAxisAnchor', 'NSLayoutYAxisAnchor', 'NSLayoutDimension' { ios_runtime.names['NSLayoutAnchor'] }
			'NSMutableData' { ios_runtime.names['NSData'] }
			'NSMutableURLRequest' { ios_runtime.names['NSURLRequest'] }
			'NSHTTPURLResponse' { ios_runtime.names['NSURLResponse'] }
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
		size := match name {
			'NSConstantDictionary' { u32(40) }
			'NSConcreteValue' { u32(24) }
			'NSError' { u32(sizeof(AbiNSError)) }
			'NSCondition' { u32(sizeof(AbiNSCondition)) }
			'NSThread' { u32(64) }
			'ASWebAuthenticationSession' { u32(136) }
			'UIImageView' { u32(512) }
			'GCKeyboard' { u32(32) }
			'NSFileManager' { u32(32) }
			'NSProcessInfo' { u32(48) }
			'NSDate', 'VinixCFDate' { u32(8) }
			'NSStream' { u32(8) }
			'NSInputStream' { u32(136) }
			'NSAutoreleasePool' { u32(40) }
			'NSUUID', '_NSUUIDBridge' { u32(8) }
			'__NSConcreteUUID' { u32(24) }
			'NSHTTPCookie' { u32(sizeof(AbiHTTPCookie)) }
			'NSURLRequest', 'NSMutableURLRequest' { u32(24) }
			'NSURLResponse' { u32(24) }
			'NSHTTPURLResponse' { u32(32) }
			'NSURLConnection' { u32(16) }
			'UIAlertController' { u32(1400) }
			'UIAlertAction' { u32(144) }
			'NSLayoutConstraint' { u32(sizeof(AbiLayoutConstraint)) }
			'NSLayoutAnchor', 'NSLayoutXAxisAnchor', 'NSLayoutYAxisAnchor', 'NSLayoutDimension' { u32(sizeof(AbiLayoutAnchor)) }
			else { webkit_size(name) }
		}
		ios_runtime.classes[u64(cls)] = &ObjClass{ name: name, parent: parent, size: size, owned: true }
		ios_runtime.classes[meta] = &ObjClass{ name: name, parent: metaclass.parent, size: 40, meta: true }
		ios_runtime.names[name] = u64(cls)
	}
	mut root := ios_runtime.classes[ios_runtime.names['NSObject']] or { panic('iOS: missing NSObject') }
	root.ivars['isa'] = &ObjIvar{name: 'isa'.clone(), types: '#'.clone(), offset: 0, size: 8}
	mut dictionary := ios_runtime.classes[ios_runtime.names['NSConstantDictionary']] or { panic('iOS: missing constant dictionary class') }
	for i, pair in [['_options', 'Q']!, ['_count', 'Q']!, ['_keys', 'r^@']!, ['_objects', 'r^@']!]! {
		dictionary.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64((i + 1) * 8), size: 8}
	}
	mut error_class := ios_runtime.classes[ios_runtime.names['NSError']] or { panic('iOS: missing NSError class') }
	for i, pair in [['_reserved', '^v']!, ['_code', 'q']!, ['_domain', '@"NSString"']!, ['_userInfo', '@"NSDictionary"']!]! {
		error_class.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64((i + 1) * 8), size: 8}
	}
	mut condition_class := ios_runtime.classes[ios_runtime.names['NSCondition']] or { panic('iOS: missing NSCondition class') }
	for i, pair in [['m', '{_opaque_pthread_mutex_t="__sig"q"__opaque"[56c]}']!, ['c', '{_opaque_pthread_cond_t="__sig"q"__opaque"[40c]}']!, ['n', '@"NSString"']!]! {
		condition_class.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: [i64(8), 72, 120]![i], size: [u64(64), 48, 8]![i]}
	}
	mut cookie_class := ios_runtime.classes[ios_runtime.names['NSHTTPCookie']] or { panic('iOS: missing cookie class') }
	mut thread_class := ios_runtime.classes[ios_runtime.names['NSThread']] or { panic('iOS: missing thread class') }
	thread_class.ivars['_private'] = &ObjIvar{name: '_private'.clone(), types: '@'.clone(), offset: 8, size: 8}
	thread_class.ivars['_bytes'] = &ObjIvar{name: '_bytes'.clone(), types: '[44C]'.clone(), offset: 16, size: 44}
	cookie_class.ivars['_cookiePrivate'] = &ObjIvar{name:'_cookiePrivate'.clone(), types:'@"NSHTTPCookieInternal"'.clone(), offset:8, size:8}
	webkit_metadata()
	mut request_class := ios_runtime.classes[ios_runtime.names['NSURLRequest']] or { panic('iOS: missing request class') }
	for i, pair in [['_internal', '@"NSURLRequestInternal"']!, ['_cookiePartitionIdentifier', '@"NSString"']!]! {
		request_class.ivars[pair[0]] = &ObjIvar{name:pair[0].clone(), types:pair[1].clone(), offset:i64(8 + i * 8), size:8}
	}
	mut response_class := ios_runtime.classes[ios_runtime.names['NSURLResponse']] or { panic('iOS: missing response class') }
	for i, pair in [['_internal', '@"NSURLResponseInternal"']!, ['__cf_resp_data', '^{URLResponse=^^?^{__CFURL}^{__CFString}^{__CFString}qdd^{__CFDictionary}^{__CFDictionary}i^{__CFData}^{HTTPResponse}{os_unfair_lock_s=I}}']!]! {
		response_class.ivars[pair[0]] = &ObjIvar{name:pair[0].clone(), types:pair[1].clone(), offset:i64(8 + i * 8), size:8}
	}
	mut http_response := ios_runtime.classes[ios_runtime.names['NSHTTPURLResponse']] or { panic('iOS: missing HTTP response class') }
	http_response.ivars['_httpInternal'] = &ObjIvar{name:'_httpInternal'.clone(), types:'@"NSHTTPURLResponseInternal"'.clone(), offset:24, size:8}
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
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return ios_runtime.objects[object] or { panic('iOS: object has no live runtime metadata') }
}

fn objc_allocate(cls u64) u64 {
	if connection_family(cls) && cls != ios_runtime.names['NSURLConnection'] { panic('iOS: custom connection subclass construction is not implemented') }
	ns_input_stream_require_class(cls)
	ns_pool_require_class(cls)
	allocation_class := ns_date_allocation_class(ns_uuid_allocation_class(cls))
	objc_initialize(allocation_class)
	info := ios_runtime.classes[allocation_class] or { panic('iOS: allocation of an unknown class') }
	if info.dynamic && !info.registered { panic('iOS: allocating an instance of an unregistered class') }
	object := u64(C.calloc(1, usize(info.size)))
	if object == 0 { panic('iOS: out of memory') }
	objc_install_storage(allocation_class, object, false)
	return objc_construct(object, allocation_class)
}

fn objc_retain(object u64) u64 {
	if os_log_is_handle(object) { return object }
	ns_pool_reject_ownership(object)
	if object != 0 && dispatch_objc_retain(object) { return object }
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
	if object != 0 && ns_pool_release(object) { return }
	objc_release_regular(object)
}

fn objc_release_regular(object u64) {
	if os_log_is_handle(object) { return }
	if object == 0 || object in ios_runtime.classes || object in ios_runtime.constants { return }
	if dispatch_objc_release(object) { return }
	if is_block(object) {
		block_release(object)
		return
	}
	mut header := obj_header(object)
	previous := C.ios_ref_change(unsafe { &header.refs }, -1)
	if previous <= 0 { panic('iOS: over-release') }
	if previous != 1 { return }
	header.releasing = true
	// Zero weak slots before destructors can observe a dying object.
	C.ios_objc_initialize_lock()
	for location, referent in ios_runtime.weak {
		if referent == object {
			unsafe { *(&u64(location)) = 0 }
			ios_runtime.weak[location] = 0
		}
	}
	C.ios_objc_initialize_unlock()
	dealloc := native_method(header.cls, 'dealloc')
	if dealloc != 0 {
		unsafe { ObjVoid(voidptr(dealloc))(object, c'dealloc') }
	}
	// A custom dealloc may explicitly destroy and free its supplied bytes.
	// Keep metadata until that callback returns and never free its buffer twice.
	explicitly_destroyed := header.destroyed
	objc_destroy_contents(object, mut header, true)
	objc_forget_storage(object, header)
	if !explicitly_destroyed { C.free(unsafe { voidptr(object) }) }
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
	game_keyboard_require_discovery(cls)
	if obj_header(object).pool_owned { ns_pool_initialize(object); return object }
	if obj_header(object).uuid_owned { ns_uuid_initialize(object, 0, true); return object }
	if obj_header(object).date_owned { ns_date_initialize(object, cf_absolute_time()); return object }
	if obj_header(object).input_stream_owned { panic('iOS: input stream requires designated construction') }
	if obj_header(object).connection_owned { panic('iOS: connection requires designated construction') }
	if obj_header(object).value_owned { objc_release(object); return 0 }
	if obj_header(object).auth_owned { panic('iOS: authentication session requires designated construction') }
	if obj_header(object).image_view_owned { image_view_initialize(object, 0, 0, ObjRect{}, false) }
	if objc_is_kind(object, ios_runtime.names['NSCondition']) { ns_condition_initialize(object) }
	if obj_header(object).thread != unsafe { nil } { ns_thread_initialize(object, 0, 0, 0, 0) }
	if objc_is_kind(object, ios_runtime.names['NSURLRequest']) { request_initialize(object, 0, 0, 60) }
	if obj_header(object).response_owned { response_initialize(object) }
	if obj_header(object).set_owned { ns_set_initialize(object, 0) }
	if obj_header(object).alert_owned { alert_initialize(object, 0, 0, if objc_is_kind(object, ios_runtime.names['UIAlertController']) { i64(1) } else { i64(0) }, 0, false) }
	name := webkit_object_name(object)
	if name == 'WKWebView' { webview_initialize(object, ObjRect{}, 0); return object }
	if name == 'WKWebsiteDataStore' { panic('iOS: use WebKit data store factories') }
	if name in ['WKUserScript', 'WKContentWorld', 'WKNSArray', 'WKBackForwardList'] { panic('iOS: WebKit object requires designated construction') }
	if name != '' { webkit_initialize(object, name) }
	return object
}

fn objc_stop() {
	connection_require_shutdown()
	ns_threads_join()
	swift_tasks_join()
	dispatch_stop()
	connection_stop()
	audio_stop()
	ui_context_stop()
	$if ios_gles ? { gles_set_current(0) }
	display_links_stop()
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
	objc_release(ios_runtime.file_manager)
	ios_runtime.file_manager = 0
	objc_release(ios_runtime.process_info)
	ios_runtime.process_info = 0
	objc_release(ios_runtime.process_arguments)
	ios_runtime.process_arguments = 0
	objc_release(ios_runtime.locale)
	objc_release(ios_runtime.run_loop)
	webkit_stop()
	ns_threads_stop()
	objc_associations_stop()
	// Keep the immortal empty dictionary available through all collection and
	// autorelease teardown. Release its cache reference after those users stop.
	for object in ios_runtime.framework_objects { if object != ios_runtime.empty_dictionary { objc_release(object) } }
	for _, address in ios_runtime.framework_data { C.free(unsafe { voidptr(address) }) }
	// Association releases and pool destructors can themselves autorelease or
	// attach values to immortal objects. Drain both before deleting the TLS pool.
	for {
		objc_associations_stop()
		ns_date_stop()
		objc_pool_drain_all()
		if ios_runtime.associations.len == 0 && ios_runtime.distant_dates[0] == 0 && ios_runtime.distant_dates[1] == 0 { break }
	}
	objc_pool_free(C.pthread_getspecific(ios_runtime.pool_key))
	$if ios_text ? { text_stop() }
	C.pthread_setspecific(ios_runtime.pool_key, unsafe { nil })
	C.pthread_key_delete(ios_runtime.pool_key)
	if ios_runtime.empty_dictionary != 0 {
		ios_runtime.constants.delete(ios_runtime.empty_dictionary)
		objc_release(ios_runtime.empty_dictionary)
		ios_runtime.empty_dictionary = 0
	}
	objc_constant_dictionaries_stop()
	if ios_runtime.live != 0 {
		eprintln('iOS: ${ios_runtime.live} Objective-C objects still owned at shutdown')
	}
	if ios_runtime.objects.len == 0 { unsafe { ios_runtime.objects.free() } }
	unsafe { ios_runtime.associations.free() }
	objc_monitors_stop()
	swift_buffers_stop()
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
	if library == '/usr/lib/swift/libswiftFoundation.dylib' { return swift_foundation_symbol(symbol) }
	if library == '/usr/lib/swift/libswiftos.dylib' && symbol == '_$sSo13os_log_type_ta0A0E5errorABvgZ' { return u64(unsafe { voidptr(swift_os_log_error_type) }) }
	if library == '/usr/lib/swift/libswift_Concurrency.dylib' { return swift_concurrency_symbol(symbol) }
	if library == '/usr/lib/swift/libswiftObjectiveC.dylib' {
		if address := swift_objc_bool_symbol(symbol) { return address }
		return error('iOS: Swift Objective-C symbol is not implemented: ${symbol}')
	}
	if library == '/usr/lib/swift/libswiftCore.dylib' {
		if address := swift_core_symbol(symbol) { return address }
		return error('iOS: Swift core symbol is not implemented: ${symbol}')
	}
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

// Compiler-emitted C++ aggregate encodings can be much longer than selectors
// or class names (EOSSDK has a 1605-byte method encoding). Keep those name
// limits intact; type encodings are opaque, borrowed image bytes with their
// own bound. Every byte, including the terminator, must be file-backed.
struct ObjTypeLimitFailure {}
fn (_failure &ObjTypeLimitFailure) msg() string { return 'iOS: Objective-C type encoding exceeds 65535 bytes' }
fn (_failure &ObjTypeLimitFailure) code() int { return 0 }
const objc_type_limit_failures = [ObjTypeLimitFailure{}]!
fn objc_type_limit_error() IError { return unsafe { &objc_type_limit_failures[0] } }

fn (m ObjMetadata) type_at(address u64) !string {
	for length in 0 .. 65536 {
		m.range(address + u64(length), 1, false)!
		if unsafe { *(&u8(address + u64(length))) } == 0 {
			return unsafe { tos(&u8(address), length) }
		}
	}
	return objc_type_limit_error()
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
		methods[selector] = ObjImageMethod{imp, if types == 0 { '' } else { m.type_at(types)! }}
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
			ivar_types := m.type_at(read64(entry + 16))!
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
	m.constant_dictionaries()!
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
