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
	protocols []u64 // Owned array of canonical adopted protocol identities.
	swift_ivar_list u64 // Owned copy; image class/descriptor/offset cells stay borrowed.
	swift_layout_complete bool
}

// Metadata is private to Vinix and stored separately from object bytes. The
// object begins with the ordinary isa, including when its caller supplies it.
struct ObjHeader {
mut:
	refs        i64
	cls u64
	allocation_cls u64 // Construction class; cls follows object_setClass.
	caller_storage bool
	image_integer bool // Immortal image bytes; separate numeric metadata.
	image_integer_next u64
	image_integer_encoding u8
	image_array bool // Immortal image bytes; owned metadata borrows its members.
	image_array_next u64
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
	storyboard_root &StoryboardNode = unsafe { nil } // Owns nodes borrowing data.
	file voidptr
	external_data u64
	external_size u64
	free_data bool
	swift_data_owner u64 // NSData bridge owns one Swift snapshot storage reference.
	cv_pixel &CVPixelState = unsafe { nil }
	cv_metal &CVMetalState = unsafe { nil }
	cm_format &CMFormatState = unsafe { nil }
	cm_block &CMBlockState = unsafe { nil }
	cm_sample &CMSampleState = unsafe { nil }
	reachability &ReachabilityState = unsafe { nil }
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
	foundation_lock_owned bool
	foundation_lock_retiring bool
	foundation_lock_calls u64
	foundation_lock &FoundationLockState = unsafe { nil }
	recursive_lock_owned bool
	recursive_lock_retiring bool
	recursive_lock_calls u64
	recursive_lock &RecursiveLockState = unsafe { nil }
	operation &FoundationOperation = unsafe { nil }
	invocation &FoundationInvocation = unsafe { nil }
	date_formatter &FoundationDateFormatter = unsafe { nil }
	number_formatter &FoundationNumberFormatter = unsafe { nil }
	calendar &FoundationCalendar = unsafe { nil }
	timezone_local bool
	predicate &FoundationPredicate = unsafe { nil }
	index_set &FoundationIndexSet = unsafe { nil }
	character_set &FoundationCharacterSet = unsafe { nil }
	scanner &FoundationScanner = unsafe { nil }
	user_activity &FoundationUserActivity = unsafe { nil }
	cache &FoundationCache = unsafe { nil }
	map_table &FoundationMapTable = unsafe { nil }
	telephony_owned bool
	telephony_initialized bool
	telephony_active int
	adsupport_owned bool
	adsupport_active int
	credential_owned bool
	credential_initialized bool
	credential_initializing bool
	credential_persistence u64
	bundle_resource_owned bool
	bundle_resource_initialized bool
	bundle_resource_initializing bool
	bundle_resource_priority f64
	notification_queue &FoundationNotificationQueue = unsafe { nil }
	un_trigger_owned bool
	un_trigger_initialized bool
	un_request_owned bool
	un_request_initialized bool
	un_sound_owned bool
	un_sound_initialized bool
	un_attachment_owned bool
	un_attachment_initialized bool
	un_attachment_initializing bool
	un_center_owned bool
	un_center_initialized bool
	un_content &UNContent = unsafe { nil }
	url_query_item_owned bool
	url_query_item_initialized bool
	url_query_item_initializing bool
	method_signature &FoundationMethodSignature = unsafe { nil }
	thread &FoundationThread = unsafe { nil }
	auth_owned bool
	auth &WebAuthState = unsafe { nil }
	image_view_owned bool
	image_view &ImageViewState = unsafe { nil }
	image_view_array bool
	text_field_owned bool
	text_field &TextFieldState = unsafe { nil }
	process_arguments_array bool
	date_owned bool
	date_initialized bool
	timezone_initialized bool
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
	url_session_owned bool
	url_session_configuration_owned bool
	url_session_task_owned bool
	sort_descriptor_owned bool
	sort_descriptor_initialized bool
	sort_descriptor_initializing bool
	regular_expression_owned bool
	regular_expression_initializing bool
	regular_expression &NSRegexProgram = unsafe { nil }
	regex_result_owned bool
	mutable_string_owned bool
	mutable_string_initialized bool
	uuid_owned bool
	pool_owned bool
	pool_initialized bool
	pool_thread u64
	pool_token u64
	uuid_bytes [16]u8
	cookie_owned bool
	snapshot_configuration_initialized bool
	match_request_initialized bool
	match_request_values [6]u64
	achievement_description_initialized bool
	achievement_initialized bool
	achievement_initializing bool
	achievement_percent f64
	achievement_banner bool
	gc_event_controller_initialized bool
	gc_event_controller_interaction bool
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
	capture_audio_delegate u64 // Zeroing weak; the output owns only its callback queue.
	capture_audio_queue u64
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
	swift_static_objects [1024]u64 // Borrowed immortal static headers, protected by the runtime lock.
	swift_static_object_count int // Fixed capacity; cleared after users drain, without touching storage.
	swift_empty_array u64 // Canonical sealed immortal empty storage, retired at quiescent shutdown.
	swift_arc_code u64 // Sealed ARM64 preserve-most entry points, released at quiescent teardown.
	swift_cstring_arena u64 // Sealed Swift closure/context/result adapter, retired after callbacks drain.
	swift_sequence_arena u64 // Sealed Sequence witness/throwing transform adapters, retired after callbacks drain.
	swift_metadata_arena u64 // Adjacent sealed String metadata/accessor pages, under the runtime lock.
	swift_keyed_container_arena u64 // Sealed keyed container accessor, descriptor and native-reference VWT.
	swift_keyed_container_metadata map[u64]SwiftKeyedContainerType // Owned RO page -> borrowed K/CodingKey identities.
	swift_keyed_container_retired bool
	swift_string_protocol_arena u64 // Sealed declaration graph; no StringProtocol witness table is published.
	swift_string_protocol_descriptor u64 // Kept through retirement for stale witness-lookup rejection.
	swift_foreign_metadata [64]SwiftForeignMetadataEntry // Borrowed complete imported scalar-enum identities.
	swift_foreign_metadata_count u64 // Bounded canonical cache, cleared after workers drain.
	swift_interpolation_arena u64 // Frozen interpolation metadata and TextOutputStream witnesses.
	swift_array_arena u64 // Array accessor/descriptor/witness pages and zero-filled generic cache.
	swift_array_metadata map[u64]u64 // Element metadata -> sealed Array metadata, under the runtime lock.
	swift_optional_arena u64 // Optional accessor/descriptor and writable generic cache.
	swift_optional_metadata map[u64]u64 // Wrapped metadata -> sealed complete Optional metadata/VWT.
	swift_optional_retired bool
	swift_optional_encoding_arena u64 // Encodable declaration, adapters and writable generic cache.
	swift_optional_encoding_descriptor u64 // Kept through retirement to reject stale conformance lookups.
	swift_optional_encoding map[u64]u64 // Optional metadata -> sealed table borrowing Wrapped:Encodable.
	swift_optional_decoding_arena u64 // Decodable declaration, adapters and writable generic cache.
	swift_optional_decoding_descriptor u64 // Retained identity for rejecting stale conformance lookups.
	swift_optional_decoding map[u64]u64 // Optional metadata -> sealed table borrowing Wrapped:Decodable.
	swift_object_any_arena u64 // RX bridge entry and RO AnyObject existential metadata.
	swift_object_any_retired bool
	swift_array_encoding_arena u64 // Encodable descriptor, dispatch adapters and generic cache pages.
	swift_array_encoding_descriptor u64 // Remembered through retirement before stale descriptor reads.
	swift_array_encoding map[u64]u64 // Array metadata -> sealed table with a private Element:Encodable word.
	swift_array_decoding_arena u64 // Separate Decodable descriptor, generic cache and call adapters.
	swift_array_decoding_descriptor u64 // Remembered for stale lookup rejection after quiescent retirement.
	swift_array_decoding map[u64]u64 // Array metadata -> sealed table borrowing Element:Decodable.
	swift_dictionary_metadata_arena u64 // Sealed Dictionary accessor/descriptor and writable generic cache.
	swift_dictionary_metadata map[u64]SwiftDictionaryType // Sealed page -> exact Key/Value/Hashable identities.
	swift_dictionary_metadata_retired bool
	swift_dictionary_encoding map[u64]u64 // Dictionary metadata -> sealed Encodable table (two private words).
	swift_dictionary_encoding_descriptor u64 // Remembered through retirement for stale lookup rejection.
	swift_dictionary_decoding map[u64]u64 // Separate Decodable tables; borrows metadata and conditional witnesses.
	swift_dictionary_decoding_descriptor u64 // Remembered through retirement before reading stale descriptors.
	swift_array_sequence_arena u64 // Array Sequence/iterator descriptors, adapters and generic pattern.
	swift_array_sequence_retired bool // Reject declaration recreation after quiescent metadata retirement.
	swift_array_sequence_metadata map[u64]u64 // Element -> sealed iterator metadata and complete Sequence tables.
	swift_collection_arena u64
	swift_collection_metadata map[u64]u64
	swift_case_iterable_arena u64 // Sealed CaseIterable declaration and default AllCases conformance adapter.
	swift_case_iterable_retired bool // Reject declaration recreation after quiescent metadata retirement.
	swift_custom_debug_arena u64 // Sealed CustomDebugStringConvertible declaration and resilient aliases.
	swift_custom_debug_retired bool // Reject declaration recreation after quiescent metadata retirement.
	swift_coding_key_protocol_arena u64 // Canonical CodingKey declaration shared by keyed container constraints.
	swift_coding_key_protocol_retired bool // Reject recreation after quiescent metadata retirement.
	swift_indexing_iterator_conformance_descriptor u64 // Remember for stale lookup rejection after retirement.
	swift_set_arena u64
	swift_set_metadata map[u64]SwiftSetType // Sealed specialization page -> exact Element/Hashable pair.
	swift_empty_set u64 // Immutable native empty singleton; retired with Set records.
	swift_bool_metadata_arena u64 // Sealed Swift.Bool nominal metadata, accessor and byte value witnesses.
	swift_bool_metadata_retired bool // Reject recreation after quiescent metadata retirement.
	swift_static_string_metadata_arena u64 // Frozen three-field POD metadata, witnesses and accessor.
	swift_static_string_metadata_retired bool
	swift_print_unlocked_retired bool // Printing callbacks drain before the shared interpolation adapter retires.
	swift_merge_error_metadata_arena u64 // Sealed _MergeError enum metadata, accessor and zero-size witnesses.
	swift_merge_error_metadata_retired bool
	swift_merge_error_conformance_descriptor u64 // Remember through retirement before any stale descriptor read.
	swift_integer_arena u64 // Int metadata, value witnesses and Equatable/Hashable conformances.
	swift_integer_description_arena u64 // Sealed Int description table/adapter using String's canonical protocol.
	swift_integer_description_retired bool // Reject description exports after quiescent retirement.
	swift_dispatch_flags_arena u64 // Sealed DispatchWorkItemFlags metadata/accessor pages.
	swift_dispatch_flags_retired bool // Reject resolution after quiescent metadata teardown.
	swiftui_vstack_arena u64 // Sealed nongeneric SwiftUI _VStackLayout descriptor/metadata and accessor.
	swiftui_vstack_retired bool
	swiftui_vstack_nominal_arena u64 // Sealed constrained VStack descriptor; no specialization.
	swiftui_vstack_nominal_retired bool
	swiftui_tree_arena u64 // Sealed generic Tree identity/signature; instantiation is unsupported.
	swiftui_tree_retired bool
	swiftui_zstack_arena u64 // Sealed nongeneric SwiftUI ZStack descriptor/metadata and accessor.
	swiftui_zstack_retired bool
	swiftui_zstack_nominal_arena u64 // Sealed constrained ZStack descriptor; no specialization.
	swiftui_zstack_nominal_retired bool
	swiftui_tuple_nominal_arena u64 // Sealed unconstrained TupleView descriptor; no specialization.
	swiftui_tuple_nominal_retired bool
	swiftui_tuple_init_arena u64 // Sealed consuming TupleView value initializer adapter.
	swiftui_tuple_init_retired bool
	swiftui_opacity_arena u64 // Sealed concrete ViewModifier table, opacity/Never metadata and diagnostics.
	swiftui_opacity_retired bool
	swiftui_state_value_arena u64 // Sealed State.wrappedValue adapter; values and locations stay borrowed.
	swiftui_state_value_retired bool
	swiftui_state_set_arena u64 // Sealed nonmutating State setter; nil locations consume only the incoming Value.
	swiftui_state_set_retired bool
	swiftui_state_nominal_arena u64 // Sealed generic State descriptor and diagnostic accessor, no specialization.
	swiftui_state_nominal_retired bool
	swiftui_button_nominal_arena u64 // Sealed constrained Button descriptor; no specialization.
	swiftui_button_nominal_retired bool
	swiftui_modified_arena u64 // Sealed generic ModifiedContent descriptor and diagnostic accessor.
	swiftui_modified_retired bool
	swiftui_environment_transform_arena u64 // Sealed generic environment modifier identity and diagnostic accessor.
	swiftui_environment_transform_retired bool
	swiftui_text_view_arena u64 // Sealed Text View conformance identity and diagnostic witnesses.
	swiftui_text_view_retired bool
	swiftui_localized_key_arena u64 // Sealed four-register literal-key initializer, borrowing empty Array storage.
	swiftui_localized_key_retired bool
	swift_objc_bool_arena u64 // Sealed ObjectiveC.ObjCBool metadata/accessor pages.
	swift_objc_bool_retired bool // Reject resolution after quiescent metadata teardown.
	swift_nsobject_hashable_arena u64 // Sealed NSObject conformance patterns/adapters and separate RW generic caches.
	swift_nsobject_hashable_tables map[u64]u64 // Canonical ObjC wrapper -> sealed Hashable/Equatable specialization page.
	swift_nsobject_hashable_retired bool
	swift_foundation_arena u64 // Sealed CVarArg calls and Foundation's concrete String conformance.
	swift_localized_error_protocol_arena u64 // Sealed LocalizedError declaration and nil default witnesses.
	swift_localized_error_protocol_retired bool
	swift_data_zero u64 // Immortal NSData cache, retired after pool and association drains.
	swift_json_encoder_arena u64 // Sealed base encoder construction and default constants.
	swift_json_encoder_retired bool
	swift_json_encoders map[u64]u64 // Initialized base encoder -> owned lock, under the runtime lock.
	swift_json_decoder_arena u64 // Sealed base class construction entries and default-option constants.
	swift_json_date_arena u64 // Sealed DateEncodingStrategy metadata and value witnesses.
	swift_json_date_retired bool
	swift_json_decoder_retired bool
	swift_json_decoders map[u64]u64 // Initialized base owner -> owned lock context, under the runtime lock.
	swift_cocoa_error_arena u64 // Sealed Code metadata/conformance and deferred stored-error guard.
	swift_cocoa_error_retired_arena u64 // Recognize retired descriptors before any unmapped read.
	swift_cocoa_error_retired bool
	swift_void_arena u64 // Sealed empty-tuple full metadata and zero-size value witnesses.
	swift_tuple_metadata_pages [64]u64 // Canonical, sealed inline tuple records, under the registry lock.
	swift_tuple_metadata_count u64
	swift_tuple_metadata_retired bool
	swift_unknown_value_arena u64 // Sealed Swift reference value witness tables.
	swift_error_arena u64 // Sealed ObjC value witnesses and the concrete CFError: Error conformance.
	swift_error_allocation_arena u64 // Private heap destructor and immutable error box metadata.
	swift_error_allocation_retired bool
	swift_errors map[u64]SwiftErrorStorage // Owned generic Error payloads; metadata/witnesses are borrowed.
	swift_box_code u64 // Shared Swift-self destructor thunk for generic value boxes.
	swift_box_metadata map[u64]SwiftBoxMetadata // Sealed per-value-type descriptors, under the registry lock.
	swift_box_retired bool
	swift_generic_value_allocations map[u64]u64 // Fresh mutable metadata mappings, retained until quiescent teardown.
	swift_generic_value_retired bool
	swift_generic_metadata_arena u64 // Bounded cache; returned metadata remains owned by its instantiator.
	swift_generic_metadata_count u64
	swift_generic_metadata_users u64
	swift_generic_metadata_retired bool
	swift_objc_metadata map[u64]u64 // Class -> canonical sealed Swift wrapper, under the runtime lock.
	swift_concurrency_code u64 // Sealed actor witness dispatcher and indirect priority getter.
	swift_concurrency_retired bool // Reject new resolution after quiescent teardown.
	network_retired bool // Reject monitor creation after the Network worker has retired.
	swift_main_actor_arena u64 // Sealed MainActor accessor, nominal class and immortal singleton.
	swift_main_actor_retired bool
	swift_logger_arena u64 // Sealed Swift os.Logger entries and nongeneric metadata.
	swift_logger_retired bool
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
	swift_access_key u64 // Per-thread head of caller-owned synchronous access records.
	swift_access_key_live bool
	swift_access_count u64 // Protected by the runtime lock; must drain before TLS retirement.
	swift_task_sync u64 // Mutex/condition for queued and executing task callbacks.
	swift_task_jobs u64 // Protected by the task synchronization mutex.
	swift_task_main_jobs u64 // Queued main-executor callbacks, under the same mutex.
	swift_hash_code u64 // Sealed generic Hashable forwarding entries, retired after callbacks drain.
	swift_fatal_code u64 // Assertion argument capture and BRK, retired at quiescent teardown.
	storefront_code u64 // Sealed Storefront getters/metadata, retired after Swift callers drain.
	storefront_retired bool
	names        map[string]u64
	protocol_names map[string]u64
	protocols map[u64]&ObjProtocol
	protocol_aliases map[u64]u64
	pool_key u64
	pool_sequence i64 = 2 // Globally distinct opaque tokens for this runtime lifetime.
	thread_key u64
	uncaught_exception_handler u64 // Borrowed process-wide C callback, cleared before image unmapping.
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
	url_error_arena u64 // Sealed NSString global cells; objects stay immortal until pools drain.
	url_session_constants_arena u64 // Mixed-width Foundation data and immortal resume-data keys.
	corevideo_constants_arena u64 // Sealed CoreVideo CFString cells and records.
	coremedia_constants_arena u64 // Sealed format-description CFString cells and records.
	avfoundation_constants_arena u64 // Sealed AVFoundation NSString cells and records.
	foundation_keys_arena u64 // Sealed Foundation key and calendar-identifier NSString cells.
	url_resource_keys_arena u64 // Shared NSURL/CFURL resource-key NSString cells and CFSTR records.
	ns_internal_exception_arena u64 // Sealed exception-name NSString cells and CFSTR records.
	ns_exception_type_arena u64 // Sealed Objective-C EH records and vtable; not NSObject storage.
	ns_locale_country_arena u64 // Sealed NS/CF country, currency-code and currency-symbol key cells/CFSTRs.
	devicecheck_arena u64 // Sealed DeviceCheck error-domain cell, CFSTR record and bytes.
	corehaptics_constants_arena u64 // Sealed CoreHaptics NSString cells, records and bytes.
	controller_constants_arena u64 // Sealed GameController NSString notification cells and records.
	controller_background_events bool // Shared across GCController and its subclasses.
	storekit_constants_arena u64 // Sealed StoreKit conversion NSString cells, records and bytes.
	file_manager u64 // One owned NSFileManager cache reference, retired at shutdown.
	process_info u64 // One owned NSProcessInfo singleton reference.
	process_arguments u64 // Owned app arguments, configured before image initialization.
	distant_dates [2]u64 // Owned immutable date cache references, retired at shutdown.
	adsupport_manager u64 // Cache-owned advertising manager, retired before pool teardown.
	adsupport_retired bool
	connections []u64 // Main-thread pending connections, one owning reference each.
	connection_callbacks int
	weak         map[u64]u64 // Location -> object; weak loads retain before returning.
	swift_unknown_weak map[u64]u64 // Opaque Swift weak cells, zeroed before referent teardown.
	timers       []u64
	display_links []u64
	run_loop u64
	main_thread u64
	first_responder u64
	native_touch u64
	block_refs   map[u64]int
	block_imps map[u64]ObjBlockImp // Copied Blocks and sealed executable adapters.
	block_imps_retired bool
	block_isa    [3]u64
	transform    [6]f64
	bundle       string
	device u64
	bundle_object u64
	application u64
	notification_center u64
	user_notification_center u64
	user_notification_center_initializing bool
	user_notification_center_retired bool
	notification_queue u64 // One main-thread default queue cache reference.
	notification_queue_initializing bool
	notification_queue_center_initializing bool
	notification_queues []u64 // One scheduler reference per pending queue.
	notification_queues_draining bool
	notification_queues_retired bool
	audio_session u64
	app_attest u64 // One factory-owned reference.
	app_attest_retired bool
	audio_application u64 // One factory-owned reference.
	audio_application_retired bool
	audio_converters map[u64]&AudioConverter
	audio_units map[u64]&AudioUnit
	audio_graphs map[u64]&AudioGraph
	defaults u64
	locale u64
	empty_dictionary u64
	empty_array u64 // Cache-owned immutable singleton, immortal to callers.
	empty_array_cell u64 // Read-only pointer cell, retired after pool/Swift users.
	predicates [2]u64 // Cache-owned immutable true/false predicates.
	predicates_retired bool
	webkit_default_store u64
	webkit_worlds [128]u64 // Owned interned page/client/named worlds, retired at shutdown.
	webkit_world_count int = 2
	image_integers u64 // Intrusive list retired after all collection/pool users.
	image_arrays u64 // Intrusive list retired after all collection/pool users.
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
	swift_access_start()
	ios_runtime.timers.flags |= .noslices
	ios_runtime.load_classes.flags |= .noslices
	ios_runtime.load_categories.flags |= .noslices
	ios_runtime.display_links.flags |= .noslices
	ios_runtime.connections.flags |= .noslices
	ios_runtime.main_thread = u64(C.pthread_self())
	ios_runtime.observers.flags |= .noslices
	ios_runtime.notification_queues.flags |= .noslices
	ios_runtime.selectors.flags |= .noslices
	ios_runtime.transform = [f64(1), 0, 0, 1, 0, 0]!
	for name in ['NSObject', 'VinixCVPixelBuffer', 'VinixIOSurface', 'VinixCVMetalTextureCache', 'VinixCVMetalTexture', 'MTLTextureDescriptor', 'VinixMetalTextureDescriptor', 'Protocol', 'OS_object', 'OS_dispatch_object', 'OS_dispatch_group', 'OS_dispatch_source', 'OS_dispatch_semaphore', 'OS_dispatch_queue', 'OS_dispatch_queue_serial_executor', 'OS_dispatch_queue_serial', 'OS_dispatch_queue_main', 'OS_dispatch_queue_global', 'NSAutoreleasePool', 'NSFileManager', 'NSProcessInfo', 'NSDate', 'NSFormatter', 'NSDateFormatter', 'NSNumberFormatter', 'NSStream', 'NSInputStream', 'NSUUID', '_NSUUIDBridge', '__NSConcreteUUID', 'NSString', 'NSValue', 'NSConcreteValue', 'NSNumber', 'NSIndexPath', 'NSArray', 'NSMutableArray',
		'NSMapTable', 'CTTelephonyNetworkInfo', 'ASIdentifierManager', 'NSPredicate', 'NSIndexSet', 'NSMutableIndexSet', 'NSScanner', 'NSUserActivity', 'NSConstantIntegerNumber', 'NSConstantArray', 'VinixCMFormatDescription', 'VinixCMBlockBuffer', 'VinixCMSampleBuffer', 'VinixVTDecompressionSession', 'WKSnapshotConfiguration', 'WKWebViewConfiguration', 'WKPreferences', 'WKUserContentController', 'WKProcessPool', 'WKWebsiteDataStore', 'WKWebpagePreferences', 'WKUserScript', 'WKContentWorld', 'WKNSArray',
		'NSMutableString', 'NSDictionary', 'NSMutableDictionary', 'NSConstantDictionary', 'NSJSONSerialization', 'NSCoder', 'NSKeyedArchiver', 'NSKeyedUnarchiver', 'NSNull', 'NSError', 'NSException', 'NSCondition', 'NSLock', 'NSRecursiveLock', 'NSCache', 'NSThread', 'ASWebAuthenticationSession', 'GCController', 'GCPhysicalInputProfile', 'GCExtendedGamepad', 'GCDualShockGamepad', 'GCDualSenseGamepad', 'GCColor', 'CHHapticDynamicParameter', 'CHHapticEventParameter', 'CHHapticEvent', 'CHHapticPattern', 'GCMouse', 'GCKeyboard', 'NSHTTPCookie', 'NSHTTPCookieInternal', 'NSLayoutConstraint', 'NSLayoutAnchor',
		'NSLayoutXAxisAnchor', 'NSLayoutYAxisAnchor', 'NSLayoutDimension', 'NSTimer', 'UIColor', 'UIFont', 'CALayer', 'UIResponder',
		'UIApplication', 'UIView', 'UIImageView', 'UILabel', 'UIControl', 'UIButton', 'UITextField', 'UIWindow', 'UIViewController', 'GCEventViewController', 'UINavigationController', 'GKGameCenterViewController', 'GKMatchRequest', 'GKAchievement', 'GKAchievementDescription', 'UIStoryboard', 'UITextPosition', 'UITextRange',
		'UIScreen', 'UIGestureRecognizer', 'UIPanGestureRecognizer', 'UIPinchGestureRecognizer', 'UILongPressGestureRecognizer', 'UITapGestureRecognizer', 'UIRotationGestureRecognizer', 'UISwipeGestureRecognizer', 'UIAlertView', 'UIAlertController', 'UIAlertAction',
        'NSData', '_NSDispatchData', 'OS_dispatch_data', 'OS_dispatch_data_empty', 'NSMutableData', '_NSZeroData', '_NSInlineData', 'Foundation.__NSSwiftData', 'NSLocale', 'NSTimeZone', 'NSCalendar', 'NSDateComponents', 'UNNotificationTrigger', 'UNCalendarNotificationTrigger', 'UNNotificationRequest', 'UNUserNotificationCenter', 'NSBundle', 'NSBundleResourceRequest', 'NSNotification', 'NSNotificationCenter', 'NSNotificationQueue', 'NSCharacterSet', 'NSMutableCharacterSet',
        'UNNotificationContent', 'UNMutableNotificationContent', 'UNNotificationSound', 'UNNotificationAttachment',
        'NSAttributedString', 'NSAssertionHandler', 'NSFileHandle', 'NSOperationQueue', 'NSOperation', 'NSInvocationOperation', 'NSInvocation', 'NSMethodSignature', 'NSSortDescriptor', 'NSRegularExpression', 'NSTextCheckingResult', 'VinixRegularExpressionCheckingResult',
        'NSPropertyListSerialization', 'NSRunLoop', 'NSURL', 'NSURLComponents', 'NSURLQueryItem', 'NSURLCredential', 'NSURLRequest', 'NSMutableURLRequest', 'NSURLResponse', 'NSHTTPURLResponse', 'NSURLConnection', 'NSURLSession', 'NSURLSessionConfiguration', 'NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask', 'NSUserDefaults',
        'UIDevice', 'UIScene', 'UIWindowScene', 'UISceneSession', 'UISceneConnectionOptions', 'UIOpenURLContext', 'NSSet', 'NSMutableSet', 'UITouch', 'UIEvent', 'UITraitCollection', 'UIImage', 'UIPasteboard', 'WKWebView', 'WKBackForwardList',
        'UIActivityViewController', 'UIDocumentPickerViewController', 'UIImagePickerController',
        'UIScreenEdgePanGestureRecognizer', 'UIFeedbackGenerator', 'UINotificationFeedbackGenerator', 'UISelectionFeedbackGenerator', 'UIImpactFeedbackGenerator', 'CADisplayLink',
		'UIAccessibilityElement',
        'CAMetalLayer', 'GLKView', 'EAGLContext', 'CMMotionManager', 'CLLocationManager',
        'AVAudioSession', 'AVAudioApplication', 'DCAppAttestService', 'AVCaptureDeviceDiscoverySession', 'AVCaptureDevice', 'AVCaptureDeviceInput', 'AVCaptureSession', 'AVCaptureOutput', 'AVCaptureAudioDataOutput',
        'AVCaptureVideoDataOutput', 'AVCaptureVideoPreviewLayer', 'PHPhotoLibrary',
		'VinixCTDescriptor', 'VinixCTFont', 'VinixCTLine', 'VinixCGFont', 'VinixReachability', 'VinixNWPath', 'VinixNWInterface', 'VinixNWPathMonitor', 'VinixCGContext', 'VinixCGColorSpace', 'VinixCGColor', 'VinixCGImage', 'VinixCGDataProvider', 'VinixSecCertificate', 'VinixSecKey', 'VinixSecPolicy', 'VinixSecTrust', 'VinixCFDate', 'VinixCFError', 'VinixCFUUID'] {
		parent := match name {
			'NSObject' { u64(0) }
			'NSURLSessionDownloadTask', 'NSURLSessionDataTask' { ios_runtime.names['NSURLSessionTask'] }
			'NSURLSessionUploadTask' { ios_runtime.names['NSURLSessionDataTask'] }
			'OS_dispatch_object' { ios_runtime.names['OS_object'] }
			'OS_dispatch_group' { ios_runtime.names['OS_dispatch_object'] }
			'OS_dispatch_source' { ios_runtime.names['OS_dispatch_object'] }
			'OS_dispatch_semaphore' { ios_runtime.names['OS_dispatch_object'] }
			'AVCaptureAudioDataOutput' { ios_runtime.names['AVCaptureOutput'] }
			'OS_dispatch_queue' { ios_runtime.names['OS_dispatch_object'] }
			'OS_dispatch_queue_serial_executor', 'OS_dispatch_queue_global' { ios_runtime.names['OS_dispatch_queue'] }
			'OS_dispatch_queue_serial' { ios_runtime.names['OS_dispatch_queue_serial_executor'] }
			'OS_dispatch_queue_main' { ios_runtime.names['OS_dispatch_queue_serial'] }
			'UNCalendarNotificationTrigger' { ios_runtime.names['UNNotificationTrigger'] }
			'UINotificationFeedbackGenerator', 'UISelectionFeedbackGenerator', 'UIImpactFeedbackGenerator' { ios_runtime.names['UIFeedbackGenerator'] }
			'UNMutableNotificationContent' { ios_runtime.names['UNNotificationContent'] }
			'VinixCFDate' { ios_runtime.names['NSDate'] }
			'VinixMetalTextureDescriptor' { ios_runtime.names['MTLTextureDescriptor'] }
			'NSInputStream' { ios_runtime.names['NSStream'] }
			'NSNumber', 'NSConcreteValue' { ios_runtime.names['NSValue'] }
			'NSInvocationOperation' { ios_runtime.names['NSOperation'] }
			'NSKeyedArchiver', 'NSKeyedUnarchiver' { ios_runtime.names['NSCoder'] }
			'NSConstantIntegerNumber' { ios_runtime.names['NSNumber'] }
			'VinixRegularExpressionCheckingResult' { ios_runtime.names['NSTextCheckingResult'] }
			'_NSUUIDBridge' { ios_runtime.names['NSUUID'] }
			'__NSConcreteUUID' { ios_runtime.names['_NSUUIDBridge'] }
			'UIView', 'UIViewController', 'UIApplication' { ios_runtime.names['UIResponder'] }
			'UINavigationController', 'GCEventViewController' { ios_runtime.names['UIViewController'] }
			'GKGameCenterViewController' { ios_runtime.names['UINavigationController'] }
			'UIImageView', 'UILabel', 'UIControl', 'UIWindow', 'UIAlertView', 'GLKView' { ios_runtime.names['UIView'] }
			'WKWebView' { ios_runtime.names['UIView'] }
			'UIActivityViewController', 'UIDocumentPickerViewController', 'UIImagePickerController', 'UIAlertController' { ios_runtime.names['UIViewController'] }
            'CAMetalLayer', 'AVCaptureVideoPreviewLayer' { ios_runtime.names['CALayer'] }
            'UIScreenEdgePanGestureRecognizer' { ios_runtime.names['UIPanGestureRecognizer'] }
			'UIWindowScene' { ios_runtime.names['UIScene'] }
			'NSDateFormatter', 'NSNumberFormatter' { ios_runtime.names['NSFormatter'] }
			'GCExtendedGamepad' { ios_runtime.names['GCPhysicalInputProfile'] }
			'GCDualShockGamepad', 'GCDualSenseGamepad' { ios_runtime.names['GCExtendedGamepad'] }
			'UIButton', 'UITextField' { ios_runtime.names['UIControl'] }
			'UIAccessibilityElement' { ios_runtime.names['UIResponder'] }
			'NSMutableArray', 'NSConstantArray', 'WKNSArray' { ios_runtime.names['NSArray'] }
			'NSMutableSet' { ios_runtime.names['NSSet'] }
			'NSMutableIndexSet' { ios_runtime.names['NSIndexSet'] }
			'NSMutableCharacterSet' { ios_runtime.names['NSCharacterSet'] }
			'NSMutableString' { ios_runtime.names['NSString'] }
			'NSMutableDictionary', 'NSConstantDictionary' { ios_runtime.names['NSDictionary'] }
			'NSLayoutXAxisAnchor', 'NSLayoutYAxisAnchor', 'NSLayoutDimension' { ios_runtime.names['NSLayoutAnchor'] }
			'NSMutableData', '_NSDispatchData' { ios_runtime.names['NSData'] }
			'OS_dispatch_data' { ios_runtime.names['_NSDispatchData'] }
			'OS_dispatch_data_empty' { ios_runtime.names['OS_dispatch_data'] }
			'_NSZeroData', '_NSInlineData', 'Foundation.__NSSwiftData' { ios_runtime.names['NSData'] }
			'NSMutableURLRequest' { ios_runtime.names['NSURLRequest'] }
			'NSHTTPURLResponse' { ios_runtime.names['NSURLResponse'] }
			'UIPanGestureRecognizer', 'UIPinchGestureRecognizer', 'UILongPressGestureRecognizer', 'UITapGestureRecognizer', 'UIRotationGestureRecognizer', 'UISwipeGestureRecognizer' { ios_runtime.names['UIGestureRecognizer'] }
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
			'UITextPosition', 'UITextRange' { u32(8) }
			'UITextField' { u32(1064) } // Opaque Catalyst-sized reserve; state is private to the shim.
			'GCEventViewController' { u32(1112) } // Opaque reserve; public iOS hierarchy, private shim state.
			'UNNotificationTrigger' { u32(16) }
			'UNCalendarNotificationTrigger' { u32(24) }
			'UNNotificationRequest' { u32(40) }
			'UNNotificationSound' { u32(104) }
			'UNNotificationAttachment' { u32(64) }
			'UNUserNotificationCenter' { u32(40) }
			'UNNotificationContent', 'UNMutableNotificationContent' { u32(296) }
			'NSMutableString' { u32(8) }
			'OS_object', 'OS_dispatch_object', 'OS_dispatch_group', 'OS_dispatch_source', 'OS_dispatch_semaphore', 'OS_dispatch_queue', 'OS_dispatch_queue_serial_executor', 'OS_dispatch_queue_serial', 'OS_dispatch_queue_main', 'OS_dispatch_queue_global' { u32(8) }
			'_NSDispatchData', 'OS_dispatch_data', 'OS_dispatch_data_empty' { u32(8) }
			'NSConstantDictionary' { u32(40) }
			'NSConstantArray', 'NSConstantIntegerNumber' { u32(24) }
			'_NSZeroData' { u32(8) }
			'_NSInlineData' { u32(16) }
			'Foundation.__NSSwiftData' { u32(40) }
			'NSConcreteValue' { u32(24) }
			'NSError' { u32(sizeof(AbiNSError)) }
			'NSCondition' { u32(sizeof(AbiNSCondition)) }
			'NSLock' { u32(sizeof(AbiNSLock)) }
			'NSRecursiveLock' { u32(sizeof(AbiNSRecursiveLock)) }
			'NSCache' { 48 }
			'CTTelephonyNetworkInfo' { 40 }
			'ASIdentifierManager' { 8 }
			'UIStoryboard', 'UIFeedbackGenerator', 'UINotificationFeedbackGenerator', 'UISelectionFeedbackGenerator', 'UIImpactFeedbackGenerator' { 8 }
			'NSThread' { u32(64) }
			'NSOperation' { u32(248) }
			'NSInvocationOperation' { u32(264) }
			'NSInvocation' { u32(64) }
			'NSMethodSignature' { u32(32) }
			'NSCoder' { u32(8) }
			'NSKeyedArchiver' { u32(136) }
			'NSKeyedUnarchiver' { u32(144) }
			'ASWebAuthenticationSession' { u32(136) }
			'UIImageView' { u32(512) }
			'GCKeyboard' { u32(32) }
			'GCMouse' { u32(40) }
			'GCColor', 'CHHapticEventParameter', 'AVAudioApplication' { u32(24) }
			'DCAppAttestService' { u32(16) } // Catalyst size; opaque shim storage.
			'AVCaptureDeviceDiscoverySession' { u32(48) } // Catalyst size; opaque shim storage.
			'AVCaptureOutput' { u32(16) }
			'AVCaptureAudioDataOutput' { u32(24) } // Catalyst sizes; opaque shim storage.
			'GKAchievementDescription' { u32(24) } // Opaque native metadata reserve.
			'GKAchievement' { u32(40) } // Opaque native reserve; local progress is private shim state.
			'GKMatchRequest' { u32(40) } // Opaque native reserve; configuration is private shim state.
			'WKSnapshotConfiguration' { u32(56) }
			'CHHapticDynamicParameter' { u32(32) }
			'CHHapticEvent' { u32(48) }
			'CHHapticPattern' { u32(72) }
			'GCController' { u32(232) } // Measured host layouts; physical profile construction is unavailable.
			'GCPhysicalInputProfile' { u32(680) }
			'GCExtendedGamepad' { u32(872) }
			'GCDualShockGamepad', 'GCDualSenseGamepad' { u32(896) }
			'NSFileManager' { u32(32) }
			'NSProcessInfo' { u32(48) }
			'NSDate', 'VinixCFDate', 'NSTimeZone', 'NSLocale', 'NSFormatter' { u32(8) }
			'NSDateFormatter' { u32(56) }
			'NSNumberFormatter' { u32(64) }
			'NSPredicate' { u32(16) }
			'NSIndexSet', 'NSMutableIndexSet' { u32(32) }
			'NSCharacterSet', 'NSMutableCharacterSet' { u32(8) }
			'NSScanner' { u32(8) }
			'NSUserActivity' { u32(32) }
			'NSNotificationQueue' { u32(32) }
			'NSURLQueryItem' { u32(24) }
			'NSURLCredential' { u32(16) }
			'NSBundleResourceRequest' { u32(48) }
			'NSStream' { u32(8) }
			'NSInputStream' { u32(136) }
			'NSAutoreleasePool' { u32(40) }
			'NSUUID', '_NSUUIDBridge' { u32(8) }
			'__NSConcreteUUID' { u32(24) }
			'VinixCFUUID' { u32(8) }
			'NSHTTPCookie' { u32(sizeof(AbiHTTPCookie)) }
			'NSURLRequest', 'NSMutableURLRequest' { u32(24) }
			'NSURLResponse' { u32(24) }
			'NSHTTPURLResponse' { u32(32) }
			'NSURLConnection' { u32(16) }
			'NSURLSession' { u32(160) }
			'NSURLSessionConfiguration' { u32(560) }
			'NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask' { u32(720) }
			'NSSortDescriptor' { u32(40) }
			'NSRegularExpression' { u32(40) }
			'NSTextCheckingResult', 'VinixRegularExpressionCheckingResult' { u32(8) }
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
	objc_protocols_start()
	dispatch_objc_publish_classes()
	mut root := ios_runtime.classes[ios_runtime.names['NSObject']] or { panic('iOS: missing NSObject') }
	root.ivars['isa'] = &ObjIvar{name: 'isa'.clone(), types: '#'.clone(), offset: 0, size: 8}
	mut integer := ios_runtime.classes[ios_runtime.names['NSConstantIntegerNumber']] or { panic('iOS: missing constant integer class') }
	for i, pair in [['_encoding', 'r*']!, ['_value', 'q']!]! {
		integer.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64((i + 1) * 8), size: 8}
	}
	mut array := ios_runtime.classes[ios_runtime.names['NSConstantArray']] or { panic('iOS: missing constant array class') }
	for i, pair in [['_count', 'Q']!, ['_objects', 'r^@']!]! {
		array.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64((i + 1) * 8), size: 8}
	}
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
	url_session_metadata()
	url_session_configuration_metadata()
	url_session_task_metadata()
	ns_lock_metadata()
	ns_recursive_lock_metadata()
	ns_operation_metadata()
	ns_invocation_metadata()
	ns_date_formatter_metadata()
	ns_number_formatter_metadata()
	ns_predicate_metadata()
	ns_index_set_metadata()
	un_trigger_metadata()
	un_request_metadata()
	un_center_metadata()
	un_content_metadata()
	un_sound_metadata()
	un_attachment_metadata()
	ns_cache_metadata()
	gc_color_metadata()
	snapshot_configuration_metadata()
	haptic_dynamic_parameter_metadata()
	haptic_parameter_metadata()
	haptic_pattern_metadata()
	haptic_event_metadata()
	game_controller_metadata()
	telephony_metadata()
	ns_credential_metadata()
	ns_bundle_resource_metadata()
	ns_url_query_item_metadata()
	ns_user_activity_metadata()
	ns_notification_queue_metadata()
	ns_keyed_archiver_metadata()
	ns_keyed_unarchiver_metadata()
	sort_descriptor_metadata()
	regular_expression_metadata()
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
	cv_metal_start()
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
	match_request_install(cls, false)
	achievement_install(cls, false)
	achievement_description_install(cls, false)
	snapshot_configuration_require_class(cls)
	haptic_dynamic_parameter_require_class(cls)
	haptic_parameter_require_class(cls)
	haptic_pattern_require_class(cls)
	haptic_event_require_class(cls)
	long_press_descriptor_require_recognition(cls)
	tap_descriptor_require_recognition(cls)
	rotation_descriptor_require_recognition(cls)
	pinch_descriptor_require_recognition(cls)
	pan_descriptor_require_recognition(cls)
	navigation_descriptor_require_ui(cls)
	ns_keyed_archiver_require_class(cls)
	ns_operation_require_class(cls)
	ns_lock_require_class(cls)
	ns_recursive_lock_require_class(cls)
	dispatch_objc_allocation_checked(cls) or { panic(err) }
	if connection_family(cls) && cls != ios_runtime.names['NSURLConnection'] { panic('iOS: custom connection subclass construction is not implemented') }
	url_session_require_class(cls)
	url_session_configuration_require_class(cls)
	url_session_task_require_class(cls)
	game_controller_require_discovery(cls)
	app_attest_require_factory(cls)
	capture_discovery_require_factory(cls)
	audio_application_require_factory(cls)
	storyboard_require_factory(cls)
	sort_descriptor_require_class(cls)
	regular_expression_require_class(cls)
	mutable_string_require_class(cls)
	ns_input_stream_require_class(cls)
	ns_pool_require_class(cls)
	ns_timezone_require_class(cls)
	ns_date_formatter_require_class(cls)
	ns_number_formatter_require_class(cls)
	un_trigger_require_class(cls)
	un_request_require_class(cls)
	un_center_require_class(cls)
	un_content_require_class(cls)
	un_sound_require_class(cls)
	un_attachment_require_class(cls)
	ns_cache_require_class(cls)
	ns_map_table_require_class(cls)
	telephony_require_class(cls)
	adsupport_require_class(cls)
	ns_credential_require_class(cls)
	ns_bundle_resource_require_class(cls)
	ns_calendar_require_class(cls)
	ns_predicate_require_class(cls)
	ns_index_set_require_class(cls)
	ns_character_set_require_class(cls)
	ns_scanner_require_class(cls)
	ns_user_activity_require_class(cls)
	ns_notification_queue_require_class(cls)
	ns_url_query_item_require_class(cls)
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
	if swift_data_bridge_is_zero(object) { return object }
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
	if swift_data_bridge_is_zero(object) { return }
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
	swift_unknown_weak_retire_locked(object)
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
	if object == 0 { return 0 }
	imp := native_method(cls, 'init')
	if imp != 0 { return unsafe { ObjInit(voidptr(imp))(object, c'init') } }
	if snapshot_configuration_family(cls) { return snapshot_configuration_initialize(object) }
	if match_request_family(cls) { return match_request_initialize(object) }
	if achievement_family(cls) { return achievement_initialize(object, 0, true) }
	if achievement_description_family(cls) { return achievement_description_initialize(object) }
	if gc_event_controller_family(cls) { return gc_event_controller_initialize(object) }
	game_keyboard_require_discovery(cls)
	if obj_header(object).pool_owned { ns_pool_initialize(object); return object }
	if obj_header(object).uuid_owned { ns_uuid_initialize(object, 0, true); return object }
	if obj_header(object).date_owned { ns_date_initialize(object, cf_absolute_time()); return object }
	if obj_header(object).date_formatter != unsafe { nil } { ns_date_formatter_initialize(object); return object }
	if obj_header(object).number_formatter != unsafe { nil } { ns_number_formatter_initialize(object); return object }
	if obj_header(object).calendar != unsafe { nil } { return ns_calendar_initialize(object, 0, false) }
	if obj_header(object).index_set != unsafe { nil } { return ns_index_set_initialize(object, 0, 0) }
	if obj_header(object).character_set != unsafe { nil } { return ns_character_set_initialize(object) }
	if obj_header(object).scanner != unsafe { nil } { return ns_scanner_default(object) }
	if obj_header(object).cache != unsafe { nil } { return ns_cache_initialize(object) }
	if obj_header(object).map_table != unsafe { nil } { return ns_map_table_initialize(object, 0, 0, 0) }
	if obj_header(object).telephony_owned { return telephony_initialize(object) }
	if obj_header(object).adsupport_owned { return adsupport_initialize(object) }
	if obj_header(object).credential_owned { panic('iOS: credential requires a designated initializer') }
	if obj_header(object).bundle_resource_owned { panic('iOS: resource request requires a designated initializer') }
	if obj_header(object).user_activity != unsafe { nil } { panic('iOS: user activity requires designated construction') }
	if obj_header(object).notification_queue != unsafe { nil } { return ns_notification_queue_initialize(object, 0, true) }
	if obj_header(object).un_trigger_owned { panic('iOS: notification trigger requires designated construction') }
	if obj_header(object).un_request_owned { panic('iOS: notification request requires designated construction') }
	if obj_header(object).un_sound_owned { panic('iOS: notification sound requires designated construction') }
	if obj_header(object).un_attachment_owned { panic('iOS: notification attachment requires designated construction') }
	if obj_header(object).un_center_owned { panic('iOS: user notification center requires currentNotificationCenter') }
	if obj_header(object).un_content != unsafe { nil } { return un_content_initialize(object) }
	if obj_header(object).url_query_item_owned { return ns_url_query_item_initialize(object, 0, 0) }
	if obj_header(object).mutable_string_owned { mutable_string_initialize(object, ''); return object }
	if ns_timezone_family(cls) { panic('iOS: default timezone construction is not implemented') }
	if obj_header(object).input_stream_owned { panic('iOS: input stream requires designated construction') }
	if obj_header(object).connection_owned { panic('iOS: connection requires designated construction') }
	if obj_header(object).value_owned { objc_release(object); return 0 }
	if obj_header(object).auth_owned { panic('iOS: authentication session requires designated construction') }
	if obj_header(object).image_view_owned { image_view_initialize(object, 0, 0, ObjRect{}, false) }
	if obj_header(object).text_field_owned { text_field_initialize(object, ObjRect{}) }
	if objc_is_kind(object, ios_runtime.names['NSCondition']) { ns_condition_initialize(object) }
	if ns_lock_family(read64(object)) { ns_lock_initialize(object) }
	if ns_recursive_lock_family(read64(object)) { ns_recursive_lock_initialize(object) }
	if obj_header(object).thread != unsafe { nil } { ns_thread_initialize(object, 0, 0, 0, 0) }
	if obj_header(object).operation != unsafe { nil } { return ns_operation_default_initialize(object) }
	if ns_invocation_family(cls) { objc_release(object); return 0 }
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
	nw_stop()
	reachability_stop()
	dispatch_stop()
	dispatch_sources_stop()
	dispatch_specific_stop()
	dispatch_group_stop()
	reachability_free()
	nw_free()
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
	ns_notification_queues_stop()
	un_center_stop()
	adsupport_stop()
	notification_stop()
	objc_release(ios_runtime.notification_center)
	objc_release(ios_runtime.audio_session)
	app_attest_stop()
	audio_application_stop()
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
	objc_block_imps_stop()
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
	dispatch_data_stop()
	objc_pool_drain_all()
	objc_pool_free(C.pthread_getspecific(ios_runtime.pool_key))
	$if ios_text ? { text_stop() }
	C.pthread_setspecific(ios_runtime.pool_key, unsafe { nil })
	C.pthread_key_delete(ios_runtime.pool_key)
	if ios_runtime.empty_dictionary != 0 {
		ios_runtime.constants.delete(ios_runtime.empty_dictionary)
		objc_release(ios_runtime.empty_dictionary)
		ios_runtime.empty_dictionary = 0
	}
	objc_constant_arrays_stop()
	objc_constant_dictionaries_stop()
	objc_constant_integers_stop()
	objc_protocols_stop()
	swift_data_bridge_stop()
	// Swift closure/context destruction can still read Foundation globals.
	// Drain those owners before retiring Foundation global cells and strings.
	swift_buffers_stop()
	ns_empty_array_stop()
	ns_predicate_stop()
	ns_url_error_stop()
	ns_url_session_constants_stop()
	ns_foundation_keys_stop()
	ns_url_resource_keys_stop()
	ns_internal_exception_stop()
	ns_exception_type_stop()
	ns_locale_country_stop()
	devicecheck_stop()
	corehaptics_constants_stop()
	game_controller_stop()
	storekit_constants_stop()
	avfoundation_constants_stop()
	corevideo_constants_stop()
	coremedia_constants_stop()
	if ios_runtime.live != 0 {
		eprintln('iOS: ${ios_runtime.live} Objective-C objects still owned at shutdown')
	}
	if ios_runtime.objects.len == 0 { unsafe { ios_runtime.objects.free() } }
	unsafe { ios_runtime.associations.free() }
	objc_monitors_stop()
	dispatch_data_free()
	if ios_runtime.block_refs.len != 0 { eprintln('iOS: heap blocks still owned at shutdown') }
	for _, text in ios_runtime.constant_utf8 { unsafe { text.free() } }
	for address, info in ios_runtime.classes {
		objc_class_metadata_free(info)
		if info.owned { C.free(unsafe { voidptr(address) }) }
	}
	// V's []string.free() also frees the owned strings.
	unsafe { ios_runtime.selectors.free(); ios_runtime.selector_names.free() }
	ns_uncaught_handler_stop()
	swift_access_stop()
}

@[export: 'ios_format_double']
fn format_double(destination &char, size usize, format &char, value f64) int {
	if darwin_strcmp(format, c'%.12g') != 0 {
		panic('iOS: unsupported snprintf format: ' + ctext(u64(format)))
	}
	return C.snprintf(destination, size, c'%.12g', value)
}

fn runtime_symbol(library string, symbol string) !u64 {
	$if ios_sqlite ? {
		if library == '/usr/lib/libsqlite3.dylib' {
			if address := sqlite_symbol(symbol) { return address }
		}
	}
	if library == '/usr/lib/libresolv.9.dylib' {
		if address := resolver_query_symbol(symbol) { return address }
	}
	if library == '/usr/lib/libz.1.dylib' {
		if address := zlib_checksum_symbol(symbol) { return address }
		if address := zlib_compress_symbol(symbol) { return address }
		if address := zlib_bound_symbol(symbol) { return address }
	}
	// Check before generic class fallbacks in libobjc and Foundation/UIKit.
	if symbol in ['_OBJC_CLASS_$_WKSnapshotConfiguration', '_OBJC_METACLASS_$_WKSnapshotConfiguration']! {
		if library != '/System/Library/Frameworks/WebKit.framework/WebKit' { return error('iOS: WKSnapshotConfiguration class import requires WebKit.framework') }
		cls := ios_runtime.names['WKSnapshotConfiguration']
		return if symbol.starts_with('_OBJC_METACLASS_') { read64(cls) } else { cls }
	}
	if symbol in ['_OBJC_CLASS_$_CHHapticPattern', '_OBJC_METACLASS_$_CHHapticPattern']! {
		if library != '/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics' {
			return error('iOS: CHHapticPattern class import requires CoreHaptics.framework')
		}
		cls := ios_runtime.names['CHHapticPattern']
		return if symbol.starts_with('_OBJC_METACLASS_') { read64(cls) } else { cls }
	}
	if symbol in ['_OBJC_CLASS_$_CHHapticEvent', '_OBJC_METACLASS_$_CHHapticEvent']! {
		if library != '/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics' {
			return error('iOS: CHHapticEvent class import requires CoreHaptics.framework')
		}
		cls := ios_runtime.names['CHHapticEvent']
		return if symbol.starts_with('_OBJC_METACLASS_') { read64(cls) } else { cls }
	}
	if symbol in ['_OBJC_CLASS_$_CHHapticDynamicParameter', '_OBJC_METACLASS_$_CHHapticDynamicParameter']! {
		if library != '/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics' {
			return error('iOS: CHHapticDynamicParameter class import requires CoreHaptics.framework')
		}
		cls := ios_runtime.names['CHHapticDynamicParameter']
		return if symbol.starts_with('_OBJC_METACLASS_') { read64(cls) } else { cls }
	}

	if symbol in ['_OBJC_CLASS_$_CHHapticEventParameter', '_OBJC_METACLASS_$_CHHapticEventParameter']! {
		if library != '/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics' {
			return error('iOS: CHHapticEventParameter class import requires CoreHaptics.framework')
		}
		cls := ios_runtime.names['CHHapticEventParameter']
		return if symbol.starts_with('_OBJC_METACLASS_') { read64(cls) } else { cls }
	}
	if symbol in ['_OBJC_CLASS_$_UILongPressGestureRecognizer', '_OBJC_METACLASS_$_UILongPressGestureRecognizer']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: long press gesture class import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UITapGestureRecognizer', '_OBJC_METACLASS_$_UITapGestureRecognizer']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: tap gesture class import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UIRotationGestureRecognizer', '_OBJC_METACLASS_$_UIRotationGestureRecognizer']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: rotation gesture class import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UIPinchGestureRecognizer', '_OBJC_METACLASS_$_UIPinchGestureRecognizer']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: pinch gesture class import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UIPanGestureRecognizer', '_OBJC_METACLASS_$_UIPanGestureRecognizer',
		'_OBJC_CLASS_$_UIScreenEdgePanGestureRecognizer', '_OBJC_METACLASS_$_UIScreenEdgePanGestureRecognizer']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: pan gesture class import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UITextRange', '_OBJC_METACLASS_$_UITextRange',
		'_OBJC_CLASS_$_UITextPosition', '_OBJC_METACLASS_$_UITextPosition',
		'_OBJC_CLASS_$_UITextField', '_OBJC_METACLASS_$_UITextField']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: text input class import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_GKGameCenterViewController', '_OBJC_METACLASS_$_GKGameCenterViewController', '_OBJC_CLASS_$_GKMatchRequest', '_OBJC_METACLASS_$_GKMatchRequest', '_OBJC_CLASS_$_GKAchievement', '_OBJC_METACLASS_$_GKAchievement', '_OBJC_CLASS_$_GKAchievementDescription', '_OBJC_METACLASS_$_GKAchievementDescription']!
		&& library != '/System/Library/Frameworks/GameKit.framework/GameKit' {
		return error('iOS: Game Center controller import requires GameKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UINavigationController', '_OBJC_METACLASS_$_UINavigationController']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: navigation controller import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UIStoryboard', '_OBJC_METACLASS_$_UIStoryboard']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: storyboard import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_AVCaptureDeviceDiscoverySession', '_OBJC_METACLASS_$_AVCaptureDeviceDiscoverySession']!
		&& library != '/System/Library/Frameworks/AVFoundation.framework/AVFoundation' {
		return error('iOS: capture discovery import requires AVFoundation.framework')
	}
	if symbol in ['_OBJC_CLASS_$_AVCaptureOutput', '_OBJC_METACLASS_$_AVCaptureOutput',
		'_OBJC_CLASS_$_AVCaptureAudioDataOutput', '_OBJC_METACLASS_$_AVCaptureAudioDataOutput']!
		&& library != '/System/Library/Frameworks/AVFoundation.framework/AVFoundation' {
		return error('iOS: capture output import requires AVFoundation.framework')
	}
	if symbol in ['_OBJC_CLASS_$_DCAppAttestService', '_OBJC_METACLASS_$_DCAppAttestService']!
		&& library != '/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck' {
		return error('iOS: App Attest import requires DeviceCheck.framework')
	}
	if symbol in ['_OBJC_CLASS_$_AVAudioApplication', '_OBJC_METACLASS_$_AVAudioApplication']!
		&& library != '/System/Library/Frameworks/AVFAudio.framework/AVFAudio' {
		return error('iOS: audio application import requires AVFAudio.framework')
	}
	if (game_controller_class_name(symbol) != none
		|| game_controller_constant_index(symbol) != none)
		&& library != '/System/Library/Frameworks/GameController.framework/GameController' {
		return error('iOS: controller import requires GameController.framework')
	}
	if ((symbol.starts_with('_OBJC_CLASS_$_') && url_session_task_name(symbol.all_after('_OBJC_CLASS_$_')))
		|| (symbol.starts_with('_OBJC_METACLASS_$_') && url_session_task_name(symbol.all_after('_OBJC_METACLASS_$_'))))
		&& library != '/System/Library/Frameworks/Foundation.framework/Foundation' {
		return error('iOS: URL session task import requires Foundation.framework')
	}
	if symbol in ['_OBJC_CLASS_$_UIFeedbackGenerator', '_OBJC_METACLASS_$_UIFeedbackGenerator',
		'_OBJC_CLASS_$_UINotificationFeedbackGenerator', '_OBJC_METACLASS_$_UINotificationFeedbackGenerator',
		'_OBJC_CLASS_$_UISelectionFeedbackGenerator', '_OBJC_METACLASS_$_UISelectionFeedbackGenerator',
		'_OBJC_CLASS_$_UIImpactFeedbackGenerator', '_OBJC_METACLASS_$_UIImpactFeedbackGenerator']!
		&& library != '/System/Library/Frameworks/UIKit.framework/UIKit' {
		return error('iOS: feedback generator import requires UIKit.framework')
	}
	if symbol in ['_OBJC_CLASS_$_ASIdentifierManager', '_OBJC_METACLASS_$_ASIdentifierManager']!
		&& library != '/System/Library/Frameworks/AdSupport.framework/AdSupport' {
		return error('iOS: advertising manager import requires AdSupport.framework')
	}
	if library == '/System/Library/Frameworks/AdSupport.framework/AdSupport' {
		cls := ios_runtime.names['ASIdentifierManager']
		if symbol == '_OBJC_CLASS_$_ASIdentifierManager' { return cls }
		if symbol == '_OBJC_METACLASS_$_ASIdentifierManager' { return read64(cls) }
		return error('iOS: AdSupport symbol is not implemented: ${symbol}')
	}
	if symbol in ['_OBJC_CLASS_$_NSBundleResourceRequest', '_OBJC_METACLASS_$_NSBundleResourceRequest']!
		&& library != '/System/Library/Frameworks/Foundation.framework/Foundation' {
		return error('iOS: resource request import requires Foundation.framework')
	}
	if symbol in ['_OBJC_CLASS_$_NSURLCredential', '_OBJC_METACLASS_$_NSURLCredential']!
		&& library != '/System/Library/Frameworks/Foundation.framework/Foundation' {
		return error('iOS: credential import requires Foundation.framework')
	}
	if symbol in ['_OBJC_CLASS_$_CTTelephonyNetworkInfo', '_OBJC_METACLASS_$_CTTelephonyNetworkInfo']!
		&& library != '/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony' {
		return error('iOS: telephony import requires CoreTelephony.framework')
	}
	if symbol in ['_OBJC_CLASS_$_MTLTextureDescriptor', '_OBJC_METACLASS_$_MTLTextureDescriptor']!
		&& library != '/System/Library/Frameworks/Metal.framework/Metal' {
		return error('iOS: Metal texture descriptor import requires Metal.framework')
	}
	if library == '/usr/lib/swift/libswiftDispatch.dylib' { return swift_dispatch_symbol(symbol) }
	if library == '/usr/lib/swift/libswiftFoundation.dylib' { return swift_foundation_symbol(symbol) }
	if library == '/usr/lib/swift/libswiftos.dylib' { return swift_os_symbol(symbol) }
	if library == '/usr/lib/swift/libswift_Concurrency.dylib' { return swift_concurrency_symbol(symbol) }
	if library == '/usr/lib/swift/libswiftObjectiveC.dylib' {
		if address := swift_nsobject_hashable_symbol(symbol) { return address }
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
		if address := dispatch_objc_symbol(symbol) { return address }
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
			if _ := dispatch_objc_import_name(symbol) { return error('iOS: dispatch class import requires libSystem or libobjc') }
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
	if !meta {
		m.protocol_list(read64(ro + 40), cls)!
		ios_runtime.names[name] = cls
	}
}

fn objc_register_image(image macho.Image, layout macho.Layout, base u64) ! {
	m := ObjMetadata{image, layout, base}
	m.protocols_register()!
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
	m.constant_collections()!
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
