// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone V build, staging and VM orchestration for native ABI checks.
module main

import os
import time
import crypto.sha256
import encoding.binary

const llvm = '/opt/homebrew/opt/llvm/bin/clang'

fn put_be(mut bytes []u8, offset int, value u32) {
	for i in 0 .. 4 { bytes[offset + i] = u8(value >> u32((3 - i) * 8)) }
}

fn checked(args []string) {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.run()
	p.wait()
	defer { p.close() }
	if p.code != 0 { panic('${args[0]} exited ${p.code}') }
}

fn copy_file(source string, destination string) {
	os.mkdir_all(os.dir(destination)) or { panic(err) }
	os.cp(source, destination) or { panic(err) }
}

fn tree(source string, destination string) {
	os.mkdir_all(destination) or { panic(err) }
	checked(['cp', '-a', source + '/.', destination])
}

fn video_sdk(root string) string {
	return os.getenv_opt('VINIX_IOS_VIDEO_SDK') or { root + '/build/ios/video' }
}

fn video_enabled(root string) bool {
	return os.is_file(video_sdk(root) + '/build.status.txt')
}

fn compile_c(root string, generated string, output string, gles bool) {
	sysroot := root + '/build-aarch64-userland/staging'
	gcc := sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
	mesa := root + '/build-aarch64-x11/sysroot'
	mut args := [llvm, '--target=aarch64-linux-musl', '-nostdinc', '-nostdlib', '-isystem',
		root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include', '-isystem',
		sysroot + '/usr/include', '-O2', '-D_GNU_SOURCE', '-fno-stack-protector', '-w']
	if video_enabled(root) {
		args << ['-I' + video_sdk(root) + '/arm64', '-I' + video_sdk(root) + '/source']
	}
	if gles {
		args << ['-no-pie', '-isystem', mesa + '/usr/include', '-isystem',
			mesa + '/usr/include/freetype2']
	} else {
		args << '-static'
	}
	args << [sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o',
		gcc + if gles { '/crtbegin.o' } else { '/crtbeginT.o' }, generated]
	// Newer V toolchains keep these runtime helpers outside generated C.
	vroot := os.dir(os.real_path(os.find_abs_path_of_executable('v') or { panic(err) }))
	for helper in ['os/execute_capture_nix.c', 'builtin/segfault_handler_nix.c']! {
		path := vroot + '/vlib/' + helper
		if os.exists(path) { args << path }
	}
	args << '-DCUSTOM_DEFINE_no_backtrace'
	if !generated.ends_with('/native-init.c') { args << root + '/compat/ios/runner/abi/dispatch.S' }
	args << ['-ffixed-x18', '-L' + sysroot + '/usr/lib', '-L' + gcc,
		root + '/build/ios/cxx/libcxx-ios.a', root + '/build/ios/cxx/sysroot/usr/lib/libc++abi.a',
		root + '/build/ios/cxx/sysroot/usr/lib/libunwind.a']
	if gles {
		args << ['-L' + root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles', '-lEGL', '-lGLESv2',
			'-lfreetype', '-Wl,--dynamic-linker=/usr/lib/vinix/ios-gles/ld-musl-aarch64.so.1',
			'-Wl,-rpath,/usr/lib/vinix/ios-gles',
			'-Wl,-rpath-link,' + root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles']
	}
	if video_enabled(root) {
		for name in ['avcodec', 'swscale', 'avutil']! { args << video_sdk(root) + '/arm64/lib' + name + '/lib' + name + '.a' }
	}
	args << ['-lgcc_eh', '-lc', '-lgcc', '-lm', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o',
		'-fuse-ld=lld', '-B/opt/homebrew/opt/llvm/bin', '-o', output]
	checked(args)
}

fn native_fixture_source(item string) string {
	return match item {
		'objc-constant-dictionary-checks' { 'objc_constant_dictionary_test.v' }
		'layout-constraint-checks' { 'layout_constraints_test.v' }
		'json-serialization-checks' { 'json_serialization_test.v' }
		'nsuuid-checks' { 'ns_uuid_test.v' }
		'filemanager-checks' { 'ns_file_manager_test.v' }
		'home-directory-checks' { 'ns_home_directory_test.v' }
		'temp-directory-checks' { 'ns_temp_directory_test.v' }
		'url-error-checks' { 'ns_url_error_test.v' }
		'session-constants-checks' { 'ns_url_session_constants_test.v' }
		'foundation-keys-checks' { 'ns_foundation_keys_test.v' }
		'audio-services-checks' { 'audio_services_test.v' }
		'avfoundation-constants-checks' { 'avfoundation_constants_test.v' }
		'corevideo-checks' { 'corevideo_test.v' }
		'pixel-allocation-checks' { 'pixel_allocation_test.v' }
		'metal-cache-checks' { 'metal_cache_test.v' }
		'media-format-checks' { 'media_format_test.v' }
		'block-buffer-checks' { 'block_buffer_test.v' }
		'sample-buffer-checks' { 'sample_buffer_test.v' }
		'cm-time-checks' { 'cm_time_test.v' }
		'h264-format-checks' { 'h264_format_test.v' }
		'hevc-format-checks' { 'hevc_format_test.v' }
		'cg-font-checks' { 'cg_font_test.v' }
		'reachability-checks' { 'reachability_test.v' }
		'devicecheck-checks' { 'devicecheck_test.v' }
		'network-path-checks' { 'network_path_test.v' }
		'corehaptics-constants-checks' { 'corehaptics_constants_test.v' }
		'media-time-checks' { 'quartzcore_time_test.v' }
		'video-decode-checks' { 'video_decode_test.v' }
		'storefront-checks' { 'storefront_test.v' }
		'storefront-current-checks' { 'storefront_current_test.v' }
		'storefront-metadata-checks' { 'storefront_metadata_test.v' }
		'refund-checks' { 'refund_test.v' }
		'storekit-constants-checks' { 'storekit_constants_test.v' }
		'zlib-checksum-checks' { 'zlib_checksum_test.v' }
		'zlib-compress-checks' { 'zlib_compress_test.v' }
		'zlib-bound-checks' { 'zlib_bound_test.v' }
		'resolver-query-checks' { 'resolver_query_test.v' }
		'pbkdf-checks' { 'pbkdf_test.v' }
		'ndr-record-checks' { 'ndr_record_test.v' }
		'immediate-exit-checks' { 'immediate_exit_test.v' }
		'crt-environ-checks' { 'crt_environ_test.v' }
		'executable-path-checks' { 'executable_path_test.v' }
		'dispatch-timer-type-checks' { 'dispatch_timer_type_test.v' }
		'dyld-images-checks' { 'dyld_images_test.v' }
		'dyld-callbacks-checks' { 'dyld_callbacks_test.v' }
		'tlv-atexit-checks' { 'tlv_atexit_test.v' }
		'inverse-hyperbolic-checks' { 'inverse_hyperbolic_test.v' }
		'arc4random-checks' { 'arc4random_test.v' }
		'asl-checks' { 'asl_test.v' }
		'backtrace-checks' { 'backtrace_test.v' }
		'dispatch-data-checks' { 'dispatch_data_test.v' }
		'dispatch-specific-checks' { 'dispatch_specific_test.v' }
		'dispatch-group-checks' { 'dispatch_group_test.v' }
		'dispatch-source-checks' { 'dispatch_source_test.v' }
		'dispatch-semaphore-checks' { 'dispatch_semaphore_test.v' }
		'division-checks' { 'integer_division_test.v' }
		'mach-exception-checks' { 'mach_exception_test.v' }
		'flock-checks' { 'flock_test.v' }
		'progname-checks' { 'progname_test.v' }
		'host-page-size-checks' { 'host_page_size_test.v' }
		'host-statistics-checks' { 'host_statistics_test.v' }
		'logb-checks' { 'logb_test.v' }
		'memory-entry-checks' { 'mach_memory_entry_test.v' }
		'mach-message-checks' { 'mach_message_test.v' }
		'mach-port-set-checks' { 'mach_port_set_test.v' }
		'mach-notification-checks' { 'mach_notification_test.v' }
		'madvise-checks' { 'madvise_test.v' }
		'malloc-zone-checks' { 'malloc_zone_test.v' }
		'mkstemp-checks' { 'mkstemp_test.v' }
		'nextafter-checks' { 'nextafter_test.v' }
		'unfair-lock-checks' { 'unfair_lock_test.v' }
		'pause-checks' { 'pause_test.v' }
		'proc-rusage-checks' { 'proc_rusage_test.v' }
		'raise-checks' { 'raise_test.v' }
		'setrlimit-checks' { 'setrlimit_test.v' }
		'sigaltstack-checks' { 'sigaltstack_test.v' }
		'swscanf-checks' { 'swscanf_test.v' }
		'task-exception-ports-checks' { 'task_exception_ports_test.v' }
		'task-info-checks' { 'task_info_test.v' }
		'task-swap-exception-ports-checks' { 'task_swap_exception_ports_test.v' }
		'nslogv-checks' { 'ns_logv_test.v' }
		'protocol-lookup-checks' { 'objc_protocols_test.v' }
		'uncaught-handler-checks' { 'ns_uncaught_handler_test.v' }
		'protocol-name-checks' { 'ns_protocol_name_test.v' }
		'autopool-checks' { 'ns_autorelease_pool_test.v' }
		'processinfo-checks' { 'ns_process_info_test.v' }
		'date-checks' { 'ns_date_test.v' }
		'inputstream-checks' { 'ns_input_stream_test.v' }
		'connection-checks' { 'ns_url_connection_test.v' }
		'type-encoding-checks' { 'objc_type_encoding_test.v' }
		'dispatch-queue-class-checks' { 'dispatch_objc_test.v' }
		'oslog-checks' { 'os_log_test.v' }
		'secure-memory-checks' { 'secure_memory_test.v' }
		'keyboard-checks' { 'game_keyboard_test.v' }
		'image-view-checks' { 'image_view_test.v' }
		'auth-session-checks' { 'web_auth_test.v' }
		'thread-checks' { 'ns_thread_test.v' }
		'set-checks' { 'ns_set_test.v' }
		'alert-checks' { 'ui_alert_test.v' }
		'response-checks' { 'url_response_test.v' }
		'value-checks' { 'ns_value_test.v' }
		'request-checks' { 'url_request_test.v' }
		'webview-checks' { 'webkit_view_test.v' }
		'user-script-checks' { 'webkit_script_test.v' }
		'webkit-configuration-checks' { 'webkit_configuration_test.v' }
		'cookie-checks' { 'http_cookie_test.v' }
		'condition-checks' { 'ns_condition_test.v' }
		'module-lookup-checks' { 'module_lookup_test.v' }
		'select-checks' { 'select_test.v' }
		'semaphore-checks' { 'mach_semaphore_test.v' }
		'signal-checks' { 'signals_test.v' }
		'error-checks' { 'errors_test.v' }
		'sysctl-checks' { 'sysctl_test.v' }
		'terminal-checks' { 'terminal_test.v' }
		'file-time-checks' { 'file_times_test.v' }
		'uuid-checks' { 'uuid_test.v' }
		'audio-session-checks' { 'audio_session_test.v' }
		'cf-dictionary-checks' { 'core_foundation_test.v' }
		'objc-storage-checks' { 'objc_storage_test.v' }
		'objc-associated-checks' { 'objc_associated_test.v' }
		'objc-property-checks' { 'objc_properties_test.v' }
		'objc-sync-checks' { 'objc_sync_test.v' }
		'swift-unknown-value-checks' { 'swift_unknown_value_test.v' }
		'swift-string-checks' { 'swift_string_test.v' }
		'swift-empty-string-checks' { 'swift_empty_string_test.v' }
		'swift-describing-checks' { 'swift_describing_test.v' }
		'swift-cstring-checks' { 'swift_cstring_test.v' }
		'swift-foreign-count-checks' { 'swift_foreign_count_test.v' }
		'swift-foreign-index-checks' { 'swift_foreign_index_test.v' }
		'swift-foreign-offset-checks' { 'swift_foreign_offset_test.v' }
		'swift-foreign-subscript-checks' { 'swift_foreign_subscript_test.v' }
		'swift-utf16-offset-checks' { 'swift_utf16_offset_test.v' }
		'swift-sequence-checks' { 'swift_sequence_test.v' }
		'swift-array-sequence-checks' { 'swift_array_sequence_test.v' }
		'swift-collection-checks' { 'swift_collection_test.v' }
		'swift-set-checks' { 'swift_set_test.v' }
		'swift-metadata-checks' { 'swift_metadata_test.v' }
		'swift-protocol-checks' { 'swift_protocol_test.v' }
		'swift-hash-checks' { 'swift_hash_test.v' }
		'swift-hasher-checks' { 'swift_hasher_test.v' }
		'swift-raw-representable-checks' { 'swift_raw_representable_test.v' }
		'swift-array-checks' { 'swift_array_test.v' }
		'swift-integer-checks' { 'swift_integer_test.v' }
		'swift-integer-hash-checks' { 'swift_integer_hash_test.v' }
		'swift-fatal-checks' { 'swift_fatal_test.v' }
		'swift-interpolation-checks' { 'swift_interpolation_test.v' }
		'swift-array-storage-checks' { 'swift_array_storage_test.v' }
		'swift-vararg-checks' { 'swift_vararg_test.v' }
		'swift-void-checks' { 'swift_void_test.v' }
		'swift-version-checks' { 'swift_version_test.v' }
		'swift-initializer-checks' { 'swift_initializer_test.v' }
		'swift-empty-array-checks' { 'swift_empty_array_test.v' }
		'swift-any-checks' { 'swift_any_test.v' }
		'swift-byte-metadata-checks' { 'swift_byte_metadata_test.v' }
		'swift-raw-equality-checks' { 'swift_raw_equality_test.v' }
		'swift-array-class-checks' { 'swift_array_class_test.v' }
		'swift-shared-utf8-checks' { 'swift_shared_utf8_test.v' }
		'swift-string-guts-checks' { 'swift_string_guts_test.v' }
		'swift-foreign-copy-checks' { 'swift_foreign_copy_test.v' }
		'swift-set-algebra-checks' { 'swift_set_algebra_test.v' }
		'swift-raw-copy-checks' { 'swift_raw_copy_test.v' }
		'swift-pointer-alloc-checks' { 'swift_pointer_alloc_test.v' }
		'swift-pointer-deinit-checks' { 'swift_pointer_deinit_test.v' }
		'swift-raw-alloc-checks' { 'swift_raw_alloc_test.v' }
		'swift-dispatch-async-checks' { 'swift_dispatch_async_test.v' }
		'swift-dispatch-main-checks' { 'swift_dispatch_main_test.v' }
		'swift-dispatch-scheduler-checks' { 'dispatch_test.v' }
		'swift-dispatch-qos-checks' { 'swift_dispatch_qos_test.v' }
		'swift-dispatch-algebra-checks' { 'swift_dispatch_algebra_test.v' }
		'swift-dispatch-flags-checks' { 'swift_dispatch_test.v' }
		'swift-stack-checks' { 'swift_stack_test.v' }
		'swift-heap-checks' { 'swift_heap_test.v' }
		'swift-array-unbridge-checks' { 'swift_array_unbridge_test.v' }
		'swift-string-replace-checks' { 'swift_string_replace_test.v' }
		'swift-dictionary-bridge-checks' { 'swift_dictionary_bridge_test.v' }
		'swift-calendar-case-checks' { 'swift_calendar_case_test.v' }
		'swift-locale-checks' { 'swift_locale_test.v' }
		'swift-date-checks' { 'swift_date_test.v' }
		'swift-data-write-checks' { 'swift_data_write_test.v' }
		'swift-data-unbridge-checks' { 'swift_data_unbridge_test.v' }
		'swift-data-base64-checks' { 'swift_data_base64_test.v' }
		'swift-data-bridge-checks' { 'swift_data_bridge_test.v' }
		'swift-data-checks' { 'swift_data_test.v' }
		'swift-url-metadata-checks' { 'swift_url_metadata_test.v' }
		'swift-url-path-checks' { 'swift_url_path_test.v' }
		'swift-url-bridge-checks' { 'swift_url_bridge_test.v' }
		'swift-error-bridge-checks' { 'swift_error_bridge_test.v' }
		'swift-error-checks' { 'swift_error_test.v' }
		'swift-error-value-checks' { 'swift_error_value_test.v' }
		'swift-dynamic-cast-checks' { 'swift_dynamic_cast_test.v' }
		'swift-objc-cast-checks' { 'swift_objc_cast_test.v' }
		'swift-foreign-metadata-checks' { 'swift_foreign_metadata_test.v' }
		'swift-object-type-checks' { 'swift_object_type_test.v' }
		'swift-mangled-state-checks' { 'swift_mangled_state_test.v' }
		'swift-mangled-checks' { 'swift_mangled_test.v' }
		'swift-witness-checks' { 'swift_witness_test.v' }
		'swift-cocoa-match-checks' { 'swift_cocoa_match_test.v' }
		'swift-localized-error-checks' { 'swift_localized_error_test.v' }
		'swift-error-description-checks' { 'swift_error_description_test.v' }
		'swift-string-unbridge-checks' { 'swift_string_unbridge_test.v' }
		'swift-json-encoder-initializer-checks' { 'swift_json_encoder_initializer_test.v' }
		'swift-json-encoder-dispatch-checks' { 'swift_json_encoder_dispatch_test.v' }
		'swift-json-encoder-date-dispatch-checks' { 'swift_json_encoder_date_dispatch_test.v' }
		'swift-json-date-strategy-checks' { 'swift_json_date_strategy_test.v' }
		'swift-json-encoder-date-case-checks' { 'swift_json_encoder_date_case_test.v' }
		'swift-json-decoder-initializer-checks' { 'swift_json_decoder_initializer_test.v' }
		'swift-json-decoder-dispatch-checks' { 'swift_json_decoder_dispatch_test.v' }
		'swift-cocoa-error-protocol-checks' { 'swift_cocoa_error_test.v' }
		'swift-cocoa-error-code-checks' { 'swift_cocoa_error_code_test.v' }
		'swift-nslog-checks' { 'swift_foundation_test.v' }
		'swift-task-switch-checks' { 'swift_task_switch_test.v' }
		'swift-task-create-checks' { 'swift_task_create_test.v' }
		'swift-task-alloc-checks' { 'swift_task_alloc_test.v' }
		'swift-task-priority-checks' { 'swift_task_priority_test.v' }
		'swift-actor-executor-checks' { 'swift_actor_executor_test.v' }
		'swift-set-bridge-checks' { 'swift_set_bridge_test.v' }
		'swift-logger-checks' { 'swift_logger_test.v' }
		'swift-main-actor-witness-checks' { 'swift_main_actor_witness_test.v' }
		'swift-main-actor-checks' { 'swift_main_actor_test.v' }
		'swift-nsobject-hashable-checks' { 'swift_nsobject_hashable_test.v' }
		'swift-objc-bool-metadata-checks' { 'swift_objc_bool_metadata_test.v' }
		'swift-objc-bool-checks' { 'swift_objc_bool_test.v' }
		'swift-once-checks' { 'swift_once_test.v' }
		'thread-policy-checks' { 'thread_policy_test.v' }
		else { panic('unknown native fixture') }
	}
}

fn build(root string, out string, only string) {
	if only == 'video-decode-checks' || only == '' {
		assert video_enabled(root), 'build-video SDK required: set VINIX_IOS_VIDEO_SDK (see docs/ios.md)'
	}
	for item in ['run-ios', 'run-ios-gles', 'objc-constant-dictionary-checks', 'layout-constraint-checks', 'json-serialization-checks', 'condition-checks', 'cookie-checks', 'webkit-configuration-checks', 'user-script-checks', 'webview-checks', 'request-checks', 'value-checks', 'response-checks', 'alert-checks', 'set-checks', 'thread-checks', 'auth-session-checks', 'image-view-checks', 'keyboard-checks', 'nsuuid-checks', 'filemanager-checks', 'home-directory-checks', 'temp-directory-checks', 'url-error-checks', 'session-constants-checks', 'foundation-keys-checks', 'audio-services-checks', 'avfoundation-constants-checks', 'corevideo-checks', 'pixel-allocation-checks', 'metal-cache-checks', 'media-format-checks', 'block-buffer-checks', 'sample-buffer-checks', 'cm-time-checks', 'h264-format-checks', 'hevc-format-checks', 'cg-font-checks', 'reachability-checks', 'devicecheck-checks', 'network-path-checks', 'corehaptics-constants-checks', 'media-time-checks', 'video-decode-checks', 'storefront-checks', 'storefront-current-checks', 'storefront-metadata-checks', 'refund-checks', 'storekit-constants-checks', 'zlib-checksum-checks', 'zlib-compress-checks', 'zlib-bound-checks', 'resolver-query-checks', 'pbkdf-checks', 'ndr-record-checks', 'immediate-exit-checks', 'crt-environ-checks', 'executable-path-checks', 'dispatch-timer-type-checks', 'dyld-images-checks', 'dyld-callbacks-checks', 'tlv-atexit-checks', 'inverse-hyperbolic-checks', 'arc4random-checks', 'asl-checks', 'backtrace-checks', 'dispatch-data-checks', 'dispatch-specific-checks', 'dispatch-group-checks', 'dispatch-source-checks', 'dispatch-semaphore-checks', 'division-checks', 'mach-exception-checks', 'flock-checks', 'progname-checks', 'host-page-size-checks', 'host-statistics-checks', 'logb-checks', 'memory-entry-checks', 'mach-message-checks', 'mach-port-set-checks', 'mach-notification-checks', 'madvise-checks', 'malloc-zone-checks', 'mkstemp-checks', 'nextafter-checks', 'unfair-lock-checks', 'pause-checks', 'proc-rusage-checks', 'raise-checks', 'setrlimit-checks', 'sigaltstack-checks', 'swscanf-checks', 'task-exception-ports-checks', 'task-info-checks', 'task-swap-exception-ports-checks', 'nslogv-checks', 'protocol-lookup-checks', 'uncaught-handler-checks', 'protocol-name-checks', 'autopool-checks', 'processinfo-checks', 'date-checks', 'inputstream-checks', 'connection-checks', 'type-encoding-checks', 'dispatch-queue-class-checks', 'oslog-checks', 'secure-memory-checks', 'select-checks', 'semaphore-checks', 'signal-checks',
		'error-checks', 'sysctl-checks', 'terminal-checks', 'thread-policy-checks', 'file-time-checks', 'uuid-checks', 'audio-session-checks', 'cf-dictionary-checks', 'objc-storage-checks', 'objc-associated-checks', 'objc-property-checks', 'objc-sync-checks', 'swift-unknown-value-checks', 'swift-string-checks', 'swift-empty-string-checks', 'swift-describing-checks', 'swift-cstring-checks', 'swift-foreign-count-checks', 'swift-foreign-index-checks', 'swift-foreign-offset-checks', 'swift-foreign-subscript-checks', 'swift-utf16-offset-checks', 'swift-sequence-checks', 'swift-array-sequence-checks', 'swift-collection-checks', 'swift-set-checks', 'swift-metadata-checks', 'swift-protocol-checks', 'swift-hash-checks', 'swift-hasher-checks', 'swift-raw-representable-checks', 'swift-array-checks', 'swift-integer-checks', 'swift-integer-hash-checks', 'swift-fatal-checks', 'swift-interpolation-checks', 'swift-array-storage-checks', 'swift-vararg-checks', 'swift-void-checks', 'swift-version-checks', 'swift-initializer-checks', 'swift-empty-array-checks', 'swift-any-checks', 'swift-byte-metadata-checks', 'swift-raw-equality-checks', 'swift-array-class-checks', 'swift-shared-utf8-checks', 'swift-string-guts-checks', 'swift-foreign-copy-checks', 'swift-set-algebra-checks', 'swift-raw-copy-checks', 'swift-pointer-alloc-checks', 'swift-pointer-deinit-checks', 'swift-raw-alloc-checks', 'swift-dispatch-async-checks', 'swift-dispatch-main-checks', 'swift-dispatch-scheduler-checks', 'swift-dispatch-qos-checks', 'swift-dispatch-algebra-checks', 'swift-dispatch-flags-checks', 'swift-stack-checks', 'swift-heap-checks', 'swift-string-replace-checks', 'swift-array-unbridge-checks', 'swift-dictionary-bridge-checks','swift-calendar-case-checks', 'swift-locale-checks', 'swift-date-checks', 'swift-data-write-checks', 'swift-data-unbridge-checks', 'swift-data-base64-checks', 'swift-data-bridge-checks', 'swift-data-checks', 'swift-url-metadata-checks', 'swift-url-path-checks', 'swift-url-bridge-checks', 'swift-error-bridge-checks', 'swift-error-checks', 'swift-error-value-checks', 'swift-dynamic-cast-checks', 'swift-objc-cast-checks', 'swift-foreign-metadata-checks', 'swift-object-type-checks', 'swift-mangled-state-checks', 'swift-mangled-checks', 'swift-witness-checks', 'swift-once-checks', 'swift-set-bridge-checks', 'swift-logger-checks', 'swift-main-actor-witness-checks', 'swift-main-actor-checks', 'swift-nsobject-hashable-checks', 'swift-objc-bool-metadata-checks', 'swift-objc-bool-checks', 'swift-actor-executor-checks', 'swift-task-priority-checks', 'swift-task-alloc-checks', 'swift-task-create-checks', 'swift-task-switch-checks', 'swift-json-encoder-initializer-checks', 'swift-json-encoder-dispatch-checks', 'swift-json-encoder-date-dispatch-checks', 'swift-json-date-strategy-checks', 'swift-json-encoder-date-case-checks', 'swift-json-decoder-initializer-checks', 'swift-json-decoder-dispatch-checks', 'swift-cocoa-error-protocol-checks', 'swift-cocoa-error-code-checks', 'swift-nslog-checks', 'swift-string-unbridge-checks', 'swift-cocoa-match-checks', 'swift-localized-error-checks', 'swift-error-description-checks', 'module-lookup-checks', 'native-init'] {
		if only != '' && item != only { continue }
		generated := out + '/' + item + '.c'
		if item == 'native-init' {
			checked(['v', '-nocache', '-cc', 'clang', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-prod', '-d', 'no_backtrace',
				'-o', generated, root + '/tests/ios/native-init.v'])
		} else {
			mut args := ['v', '-nocache', '-cc', 'clang', '-os', 'linux', '-arch', 'arm64', '-enable-globals', '-gc', 'none',
				'-prod', '-d', 'glibc', '-d', 'no_backtrace', '-d', 'ios_cxx', '-path',
				'@vlib|' + root + '/compat/ios|@vmodules', '-o', generated]
			if item.ends_with('-checks') { args = args.filter(it != '-prod') }
			if video_enabled(root) { args << ['-d', 'ios_video'] }
			if item in ['run-ios-gles', 'zlib-bound-checks']! { args << ['-d', 'ios_gles', '-d', 'ios_text'] }
			args << root + if item.ends_with('-checks') {
				'/compat/ios/runner/' + native_fixture_source(item)
			} else {
				'/compat/ios/runner'
			}
			checked(args)
		}
		compile_c(root, generated, out + '/' + item, item in ['run-ios-gles', 'zlib-bound-checks']!)
		if item == 'module-lookup-checks' {
			checked(['v', '-nocache', '-cc', 'clang', '-cflags', '-O2', '-path',
				'@vlib|' + root + '/compat/ios|@vmodules', '-o', out + '/weak-lookup-native',
				root + '/tests/ios/weak-lookup-native.v'])
			checked([out + '/weak-lookup-native', out + '/lookup-native'])
		}
		println('Built ${item}')
	}
}

fn correct_legacy_stdio_sysctl(fs string, out string) {
	// Reuse the compiled Mach-O fixture while fixing its old short-buffer
	// expectation. Native Mac sysctl leaves the output untouched and reports
	// length zero on ENOMEM; the original fixture expected length four.
	// Pin the complete input and surrounding instructions before changing only
	// CMP x8,#4 to CMP x8,#0. All its return-value/errno/stdio checks remain.
	path := fs + '/opt/ios/stdio'
	mut bytes := os.read_bytes(path) or { panic(err) }
	original := sha256.sum(bytes).hex()
	assert original == '3cde2164c6bc81d4d509afc36254d456160717693716631bc646779c1cb91cfa'
	assert binary.little_endian_u32(bytes[0x4b28..0x4b2c]) == 0xf940ffe8
	assert binary.little_endian_u32(bytes[0x4b2c..0x4b30]) == 0xf100111f
	assert binary.little_endian_u32(bytes[0x4b30..0x4b34]) == 0x54ffab41
	bytes[0x4b2d] = 0x01
	assert binary.little_endian_u32(bytes[0x4b2c..0x4b30]) == 0xf100011f
	os.write_file_array(path, bytes) or { panic(err) }
	os.write_file(out + '/stdio-expectation.log', 'Native Mac ENOMEM old length: 0\n'
		+ 'Changed only instruction at file offset 0x4b2c: CMP x8,#4 -> CMP x8,#0\n'
		+ 'Original SHA256: ' + original + '\nCorrected SHA256: ' + sha256.sum(bytes).hex() + '\n') or { panic(err) }
}

fn copy_lookup_fixtures(out string, fs string) {
	if os.is_dir(out + '/lookup-native') { tree(out + '/lookup-native', fs + '/opt/ios/lookup-native') }
}

fn regression_root(root string, out string, fs string) {
	base := root + '/build/ios/fortnite'
	for name in ['root', 'sbin', 'proc', 'sys', 'dev', 'tmp', 'etc', 'opt/ios'] {
		os.mkdir_all(fs + '/' + name) or { panic(err) }
	}
	for name, value in {
		'hosts':     '127.0.0.1 localhost\n::1 localhost\n'
		'services':  'domain 53/tcp\ndomain 53/udp\n'
		'protocols': 'icmp 1 ICMP\ntcp 6 TCP\nudp 17 UDP\n'
		'passwd':    'root:*:0:0:Vinix iOS root:/root:/bin/sh\nios-fixture:*:1001:37:' + 'G'.repeat(8192) + ':/var/empty:/bin/false\n'
		'group':     'root:*:0:\nbase:*:37:\nfirst:*:8:ios-fixture\nunrelated:*:9:someone\nsecond:*:11:ios-fixture\n'
	} {
		os.write_file(fs + '/etc/' + name, value) or { panic(err) }
	}
	tree(base + '/fixtures', fs + '/opt/ios')
	correct_legacy_stdio_sysctl(fs, out)
	copy_file(out + '/run-ios-gles', fs + '/opt/ios/run-ios')
	tree(base + '/staging/usr/lib/vinix/ios-gles', fs + '/usr/lib/vinix/ios-gles')
	copy_file(base + '/objc/Calculator.app/Calculator', fs + '/opt/ios/UIKitCalculator')
	copy_file(base + '/ppsspp/unpacked/Payload/PPSSPP.app/assets/Roboto_Condensed-Regular.ttf', fs + '/opt/ios/TextFixture.app/font.ttf')
	tree(base + '/ppsspp/unpacked/Payload/PPSSPP.app', fs + '/usr/share/vinix/ios/PPSSPP.app')
	copy_file(out + '/run-ios-gles', fs + '/usr/bin/run-ios-gles')
	os.symlink('run-ios-gles', fs + '/usr/bin/vinix-ios-ppsspp') or { panic(err) }
	os.symlink('/usr/share/vinix/ios/PPSSPP.app/PPSSPP', fs + '/opt/ios/PPSSPP') or { panic(err) }
	os.write_file(fs + '/opt/ios/ppsspp-muted', '') or { panic(err) }
	os.symlink('permissions-loop', fs + '/opt/ios/permissions-loop') or { panic(err) }
	os.write_file(fs + '/opt/ios/launch name#é%?.bin', 'native file launch fixture\n') or { panic(err) }
	tree(fs + '/opt/ios/Modules.app', fs + '/opt/ios/ModulesMissing.app')
	os.rm(fs + '/opt/ios/ModulesMissing.app/Frameworks/Leaf.framework/Leaf') or { panic(err) }
	tree(fs + '/opt/ios/Modules.app', fs + '/opt/ios/ModulesArm64e.app')
	leaf := fs + '/opt/ios/ModulesArm64e.app/Frameworks/Leaf.framework/Leaf'
	mut bytes := os.read_bytes(leaf) or { panic(err) }
	bytes[8] = 2
	bytes[9] = 0
	bytes[10] = 0
	bytes[11] = 0
	os.write_file_array(leaf, bytes) or { panic(err) }
	calculator := os.read_bytes(fs + '/opt/ios/calculator') or { panic(err) }
	mut arm := calculator.clone()
	arm[8] = 2
	os.write_file_array(fs + '/opt/ios/calculator-arm64e', arm) or { panic(err) }
	second := (4096 + calculator.len + 4095) & ~4095
	mut fat := []u8{len: second + calculator.len}
	put_be(mut fat, 0, 0xcafebabe)
	put_be(mut fat, 4, 2)
	for offset in [8, 28] {
		put_be(mut fat, offset, 0x100000c)
		put_be(mut fat, offset + 4, if offset == 8 { u32(2) } else { u32(0) })
		put_be(mut fat, offset + 8, u32(if offset == 8 { 4096 } else { second }))
		put_be(mut fat, offset + 12, u32(calculator.len))
		put_be(mut fat, offset + 16, 12)
	}
	copy(mut fat[4096..4096 + arm.len], arm)
	copy(mut fat[second..], calculator)
	os.write_file_array(fs + '/opt/ios/calculator-fat', fat) or { panic(err) }
	os.write_file_array(fs + '/opt/ios/truncated', calculator[..31]) or { panic(err) }
	copy_file(out + '/select-checks', fs + '/opt/ios/select-checks')
	copy_file(out + '/semaphore-checks', fs + '/opt/ios/semaphore-checks')
	copy_file(out + '/signal-checks', fs + '/opt/ios/signal-checks')
	copy_file(out + '/error-checks', fs + '/opt/ios/error-checks')
	copy_file(out + '/sysctl-checks', fs + '/opt/ios/sysctl-checks')
	copy_file(out + '/terminal-checks', fs + '/opt/ios/terminal-checks')
	copy_file(out + '/thread-policy-checks', fs + '/opt/ios/thread-policy-checks')
	copy_file(out + '/file-time-checks', fs + '/opt/ios/file-time-checks')
	copy_file(out + '/uuid-checks', fs + '/opt/ios/uuid-checks')
	copy_file(out + '/audio-session-checks', fs + '/opt/ios/audio-session-checks')
	copy_file(out + '/cf-dictionary-checks', fs + '/opt/ios/cf-dictionary-checks')
	copy_file(out + '/objc-constant-dictionary-checks', fs + '/opt/ios/objc-constant-dictionary-checks')
	copy_file(out + '/layout-constraint-checks', fs + '/opt/ios/layout-constraint-checks')
	copy_file(out + '/json-serialization-checks', fs + '/opt/ios/json-serialization-checks')
	copy_file(out + '/condition-checks', fs + '/opt/ios/condition-checks')
	copy_file(out + '/cookie-checks', fs + '/opt/ios/cookie-checks')
	copy_file(out + '/webkit-configuration-checks', fs + '/opt/ios/webkit-configuration-checks')
	copy_file(out + '/user-script-checks', fs + '/opt/ios/user-script-checks')
	copy_file(out + '/webview-checks', fs + '/opt/ios/webview-checks')
	copy_file(out + '/request-checks', fs + '/opt/ios/request-checks')
	copy_file(out + '/value-checks', fs + '/opt/ios/value-checks')
	copy_file(out + '/response-checks', fs + '/opt/ios/response-checks')
	copy_file(out + '/alert-checks', fs + '/opt/ios/alert-checks')
	copy_file(out + '/set-checks', fs + '/opt/ios/set-checks')
	copy_file(out + '/thread-checks', fs + '/opt/ios/thread-checks')
	copy_file(out + '/auth-session-checks', fs + '/opt/ios/auth-session-checks')
	copy_file(out + '/image-view-checks', fs + '/opt/ios/image-view-checks')
	copy_file(out + '/keyboard-checks', fs + '/opt/ios/keyboard-checks')
	copy_file(out + '/nsuuid-checks', fs + '/opt/ios/nsuuid-checks')
	copy_file(out + '/filemanager-checks', fs + '/opt/ios/filemanager-checks')
	copy_file(out + '/home-directory-checks', fs + '/opt/ios/home-directory-checks')
	copy_file(out + '/temp-directory-checks', fs + '/opt/ios/temp-directory-checks')
	copy_file(out + '/url-error-checks', fs + '/opt/ios/url-error-checks')
	copy_file(out + '/session-constants-checks', fs + '/opt/ios/session-constants-checks')
	copy_file(out + '/foundation-keys-checks', fs + '/opt/ios/foundation-keys-checks')
	copy_file(out + '/audio-services-checks', fs + '/opt/ios/audio-services-checks')
	copy_file(out + '/avfoundation-constants-checks', fs + '/opt/ios/avfoundation-constants-checks')
	copy_file(out + '/corevideo-checks', fs + '/opt/ios/corevideo-checks')
	copy_file(out + '/pixel-allocation-checks', fs + '/opt/ios/pixel-allocation-checks')
	copy_file(out + '/metal-cache-checks', fs + '/opt/ios/metal-cache-checks')
	copy_file(out + '/media-format-checks', fs + '/opt/ios/media-format-checks')
	copy_file(out + '/block-buffer-checks', fs + '/opt/ios/block-buffer-checks')
	copy_file(out + '/sample-buffer-checks', fs + '/opt/ios/sample-buffer-checks')
	copy_file(out + '/cm-time-checks', fs + '/opt/ios/cm-time-checks')
	copy_file(out + '/h264-format-checks', fs + '/opt/ios/h264-format-checks')
	copy_file(out + '/hevc-format-checks', fs + '/opt/ios/hevc-format-checks')
	copy_file(out + '/cg-font-checks', fs + '/opt/ios/cg-font-checks')
	copy_file(out + '/reachability-checks', fs + '/opt/ios/reachability-checks')
	copy_file(out + '/devicecheck-checks', fs + '/opt/ios/devicecheck-checks')
	copy_file(out + '/network-path-checks', fs + '/opt/ios/network-path-checks')
	copy_file(out + '/corehaptics-constants-checks', fs + '/opt/ios/corehaptics-constants-checks')
	copy_file(out + '/media-time-checks', fs + '/opt/ios/media-time-checks')
	copy_file(out + '/video-decode-checks', fs + '/opt/ios/video-decode-checks')
	copy_file(out + '/storefront-checks', fs + '/opt/ios/storefront-checks')
	copy_file(out + '/storefront-current-checks', fs + '/opt/ios/storefront-current-checks')
	copy_file(out + '/storefront-metadata-checks', fs + '/opt/ios/storefront-metadata-checks')
	copy_file(out + '/refund-checks', fs + '/opt/ios/refund-checks')
	copy_file(out + '/storekit-constants-checks', fs + '/opt/ios/storekit-constants-checks')
	copy_file(out + '/zlib-checksum-checks', fs + '/opt/ios/zlib-checksum-checks')
	copy_file(out + '/zlib-compress-checks', fs + '/opt/ios/zlib-compress-checks')
	copy_file(out + '/zlib-bound-checks', fs + '/opt/ios/zlib-bound-checks')
	copy_file(out + '/resolver-query-checks', fs + '/opt/ios/resolver-query-checks')
	copy_file(out + '/pbkdf-checks', fs + '/opt/ios/pbkdf-checks')
	copy_file(out + '/ndr-record-checks', fs + '/opt/ios/ndr-record-checks')
	copy_file(out + '/immediate-exit-checks', fs + '/opt/ios/immediate-exit-checks')
	copy_file(out + '/crt-environ-checks', fs + '/opt/ios/crt-environ-checks')
	copy_file(out + '/executable-path-checks', fs + '/opt/ios/executable-path-checks')
	copy_file(out + '/dispatch-timer-type-checks', fs + '/opt/ios/dispatch-timer-type-checks')
	copy_file(out + '/dyld-images-checks', fs + '/opt/ios/dyld-images-checks')
	copy_file(out + '/dyld-callbacks-checks', fs + '/opt/ios/dyld-callbacks-checks')
	copy_file(out + '/tlv-atexit-checks', fs + '/opt/ios/tlv-atexit-checks')
	copy_file(out + '/inverse-hyperbolic-checks', fs + '/opt/ios/inverse-hyperbolic-checks')
	copy_file(out + '/arc4random-checks', fs + '/opt/ios/arc4random-checks')
	copy_file(out + '/asl-checks', fs + '/opt/ios/asl-checks')
	copy_file(out + '/backtrace-checks', fs + '/opt/ios/backtrace-checks')
	copy_file(out + '/dispatch-data-checks', fs + '/opt/ios/dispatch-data-checks')
	copy_file(out + '/dispatch-specific-checks', fs + '/opt/ios/dispatch-specific-checks')
	copy_file(out + '/dispatch-group-checks', fs + '/opt/ios/dispatch-group-checks')
	copy_file(out + '/dispatch-source-checks', fs + '/opt/ios/dispatch-source-checks')
	copy_file(out + '/dispatch-semaphore-checks', fs + '/opt/ios/dispatch-semaphore-checks')
	copy_file(out + '/division-checks', fs + '/opt/ios/division-checks')
	copy_file(out + '/mach-exception-checks', fs + '/opt/ios/mach-exception-checks')
	copy_file(out + '/flock-checks', fs + '/opt/ios/flock-checks')
	copy_file(out + '/progname-checks', fs + '/opt/ios/progname-checks')
	copy_file(out + '/host-page-size-checks', fs + '/opt/ios/host-page-size-checks')
	copy_file(out + '/host-statistics-checks', fs + '/opt/ios/host-statistics-checks')
	copy_file(out + '/logb-checks', fs + '/opt/ios/logb-checks')
	copy_file(out + '/memory-entry-checks', fs + '/opt/ios/memory-entry-checks')
	copy_file(out + '/mach-message-checks', fs + '/opt/ios/mach-message-checks')
	copy_file(out + '/mach-port-set-checks', fs + '/opt/ios/mach-port-set-checks')
	copy_file(out + '/mach-notification-checks', fs + '/opt/ios/mach-notification-checks')
	copy_file(out + '/madvise-checks', fs + '/opt/ios/madvise-checks')
	copy_file(out + '/malloc-zone-checks', fs + '/opt/ios/malloc-zone-checks')
	copy_file(out + '/mkstemp-checks', fs + '/opt/ios/mkstemp-checks')
	copy_file(out + '/nextafter-checks', fs + '/opt/ios/nextafter-checks')
	copy_file(out + '/unfair-lock-checks', fs + '/opt/ios/unfair-lock-checks')
	copy_file(out + '/pause-checks', fs + '/opt/ios/pause-checks')
	copy_file(out + '/proc-rusage-checks', fs + '/opt/ios/proc-rusage-checks')
	copy_file(out + '/raise-checks', fs + '/opt/ios/raise-checks')
	copy_file(out + '/setrlimit-checks', fs + '/opt/ios/setrlimit-checks')
	copy_file(out + '/sigaltstack-checks', fs + '/opt/ios/sigaltstack-checks')
	copy_file(out + '/swscanf-checks', fs + '/opt/ios/swscanf-checks')
	copy_file(out + '/task-exception-ports-checks', fs + '/opt/ios/task-exception-ports-checks')
	copy_file(out + '/task-info-checks', fs + '/opt/ios/task-info-checks')
	copy_file(out + '/task-swap-exception-ports-checks', fs + '/opt/ios/task-swap-exception-ports-checks')
	copy_file(out + '/nslogv-checks', fs + '/opt/ios/nslogv-checks')
	copy_file(out + '/protocol-lookup-checks', fs + '/opt/ios/protocol-lookup-checks')
	copy_file(out + '/uncaught-handler-checks', fs + '/opt/ios/uncaught-handler-checks')
	copy_file(out + '/protocol-name-checks', fs + '/opt/ios/protocol-name-checks')
	copy_file(out + '/autopool-checks', fs + '/opt/ios/autopool-checks')
	copy_file(out + '/processinfo-checks', fs + '/opt/ios/processinfo-checks')
	copy_file(out + '/date-checks', fs + '/opt/ios/date-checks')
	copy_file(out + '/inputstream-checks', fs + '/opt/ios/inputstream-checks')
	copy_file(out + '/connection-checks', fs + '/opt/ios/connection-checks')
	copy_file(out + '/type-encoding-checks', fs + '/opt/ios/type-encoding-checks')
	copy_file(out + '/dispatch-queue-class-checks', fs + '/opt/ios/dispatch-queue-class-checks')
	copy_file(out + '/oslog-checks', fs + '/opt/ios/oslog-checks')
	copy_file(out + '/secure-memory-checks', fs + '/opt/ios/secure-memory-checks')
	copy_file(out + '/objc-storage-checks', fs + '/opt/ios/objc-storage-checks')
	copy_file(out + '/objc-associated-checks', fs + '/opt/ios/objc-associated-checks')
	copy_file(out + '/objc-property-checks', fs + '/opt/ios/objc-property-checks')
	copy_file(out + '/objc-sync-checks', fs + '/opt/ios/objc-sync-checks')
	copy_file(out + '/swift-unknown-value-checks', fs + '/opt/ios/swift-unknown-value-checks')
	copy_file(out + '/swift-string-checks', fs + '/opt/ios/swift-string-checks')
	copy_file(out + '/swift-empty-string-checks', fs + '/opt/ios/swift-empty-string-checks')
	copy_file(out + '/swift-describing-checks', fs + '/opt/ios/swift-describing-checks')
	copy_file(out + '/swift-cstring-checks', fs + '/opt/ios/swift-cstring-checks')
	copy_file(out + '/swift-foreign-count-checks', fs + '/opt/ios/swift-foreign-count-checks')
	copy_file(out + '/swift-foreign-index-checks', fs + '/opt/ios/swift-foreign-index-checks')
	copy_file(out + '/swift-foreign-offset-checks', fs + '/opt/ios/swift-foreign-offset-checks')
	copy_file(out + '/swift-foreign-subscript-checks', fs + '/opt/ios/swift-foreign-subscript-checks')
	copy_file(out + '/swift-utf16-offset-checks', fs + '/opt/ios/swift-utf16-offset-checks')
	copy_file(out + '/swift-sequence-checks', fs + '/opt/ios/swift-sequence-checks')
	copy_file(out + '/swift-array-sequence-checks', fs + '/opt/ios/swift-array-sequence-checks')
	copy_file(out + '/swift-collection-checks', fs + '/opt/ios/swift-collection-checks')
	copy_file(out + '/swift-set-checks', fs + '/opt/ios/swift-set-checks')
	copy_file(out + '/swift-metadata-checks', fs + '/opt/ios/swift-metadata-checks')
	copy_file(out + '/swift-protocol-checks', fs + '/opt/ios/swift-protocol-checks')
	copy_file(out + '/swift-hash-checks', fs + '/opt/ios/swift-hash-checks')
	copy_file(out + '/swift-hasher-checks', fs + '/opt/ios/swift-hasher-checks')
	copy_file(out + '/swift-raw-representable-checks', fs + '/opt/ios/swift-raw-representable-checks')
	copy_file(out + '/swift-array-checks', fs + '/opt/ios/swift-array-checks')
	copy_file(out + '/swift-integer-checks', fs + '/opt/ios/swift-integer-checks')
	copy_file(out + '/swift-integer-hash-checks', fs + '/opt/ios/swift-integer-hash-checks')
	copy_file(out + '/swift-fatal-checks', fs + '/opt/ios/swift-fatal-checks')
	copy_file(out + '/swift-interpolation-checks', fs + '/opt/ios/swift-interpolation-checks')
	copy_file(out + '/swift-array-storage-checks', fs + '/opt/ios/swift-array-storage-checks')
	copy_file(out + '/swift-vararg-checks', fs + '/opt/ios/swift-vararg-checks')
	copy_file(out + '/swift-void-checks', fs + '/opt/ios/swift-void-checks')
	copy_file(out + '/swift-version-checks', fs + '/opt/ios/swift-version-checks')
	copy_file(out + '/swift-initializer-checks', fs + '/opt/ios/swift-initializer-checks')
	copy_file(out + '/swift-empty-array-checks', fs + '/opt/ios/swift-empty-array-checks')
	copy_file(out + '/swift-any-checks',fs + '/opt/ios/swift-any-checks')
	copy_file(out + '/swift-byte-metadata-checks',fs + '/opt/ios/swift-byte-metadata-checks')
	copy_file(out + '/swift-raw-equality-checks',fs + '/opt/ios/swift-raw-equality-checks')
	copy_file(out + '/swift-array-class-checks',fs + '/opt/ios/swift-array-class-checks')
	copy_file(out + '/swift-shared-utf8-checks',fs + '/opt/ios/swift-shared-utf8-checks')
	copy_file(out + '/swift-string-guts-checks',fs + '/opt/ios/swift-string-guts-checks')
	copy_file(out + '/swift-foreign-copy-checks',fs + '/opt/ios/swift-foreign-copy-checks')
	copy_file(out + '/swift-set-algebra-checks',fs + '/opt/ios/swift-set-algebra-checks')
	copy_file(out + '/swift-raw-copy-checks', fs + '/opt/ios/swift-raw-copy-checks')
	copy_file(out + '/swift-pointer-alloc-checks', fs + '/opt/ios/swift-pointer-alloc-checks')
	copy_file(out + '/swift-pointer-deinit-checks', fs + '/opt/ios/swift-pointer-deinit-checks')
	copy_file(out + '/swift-raw-alloc-checks', fs + '/opt/ios/swift-raw-alloc-checks')
	copy_file(out + '/swift-dispatch-async-checks', fs + '/opt/ios/swift-dispatch-async-checks')
	copy_file(out + '/swift-dispatch-main-checks', fs + '/opt/ios/swift-dispatch-main-checks')
	copy_file(out + '/swift-dispatch-scheduler-checks', fs + '/opt/ios/swift-dispatch-scheduler-checks')
	copy_file(out + '/swift-dispatch-qos-checks', fs + '/opt/ios/swift-dispatch-qos-checks')
	copy_file(out + '/swift-dispatch-algebra-checks', fs + '/opt/ios/swift-dispatch-algebra-checks')
	copy_file(out + '/swift-dispatch-flags-checks', fs + '/opt/ios/swift-dispatch-flags-checks')
	copy_file(out + '/swift-stack-checks',fs + '/opt/ios/swift-stack-checks')
	copy_file(out + '/swift-heap-checks', fs + '/opt/ios/swift-heap-checks')
	copy_file(out + '/swift-array-unbridge-checks', fs + '/opt/ios/swift-array-unbridge-checks')
	copy_file(out + '/swift-string-replace-checks', fs + '/opt/ios/swift-string-replace-checks')
	copy_file(out + '/swift-dictionary-bridge-checks', fs + '/opt/ios/swift-dictionary-bridge-checks')
	copy_file(out + '/swift-calendar-case-checks', fs + '/opt/ios/swift-calendar-case-checks')
	copy_file(out + '/swift-locale-checks', fs + '/opt/ios/swift-locale-checks')
	copy_file(out + '/swift-date-checks', fs + '/opt/ios/swift-date-checks')
	copy_file(out + '/swift-data-write-checks', fs + '/opt/ios/swift-data-write-checks')
	copy_file(out + '/swift-data-unbridge-checks', fs + '/opt/ios/swift-data-unbridge-checks')
	copy_file(out + '/swift-data-base64-checks', fs + '/opt/ios/swift-data-base64-checks')
	copy_file(out + '/swift-data-bridge-checks', fs + '/opt/ios/swift-data-bridge-checks')
	copy_file(out + '/swift-data-checks', fs + '/opt/ios/swift-data-checks')
	copy_file(out + '/swift-url-metadata-checks', fs + '/opt/ios/swift-url-metadata-checks')
	copy_file(out + '/swift-url-path-checks', fs + '/opt/ios/swift-url-path-checks')
	copy_file(out + '/swift-url-bridge-checks', fs + '/opt/ios/swift-url-bridge-checks')
	copy_file(out + '/swift-error-bridge-checks', fs + '/opt/ios/swift-error-bridge-checks')
	copy_file(out + '/swift-error-checks', fs + '/opt/ios/swift-error-checks')
	copy_file(out + '/swift-error-value-checks', fs + '/opt/ios/swift-error-value-checks')
	copy_file(out + '/swift-dynamic-cast-checks',fs + '/opt/ios/swift-dynamic-cast-checks')
	copy_file(out + '/swift-objc-cast-checks',fs + '/opt/ios/swift-objc-cast-checks')
	copy_file(out + '/swift-foreign-metadata-checks',fs + '/opt/ios/swift-foreign-metadata-checks')
	copy_file(out + '/swift-object-type-checks', fs + '/opt/ios/swift-object-type-checks')
	copy_file(out + '/swift-mangled-state-checks',fs + '/opt/ios/swift-mangled-state-checks')
	copy_file(out + '/swift-mangled-checks', fs + '/opt/ios/swift-mangled-checks')
	copy_file(out + '/swift-witness-checks', fs + '/opt/ios/swift-witness-checks')
	copy_file(out + '/swift-once-checks', fs + '/opt/ios/swift-once-checks')
	copy_file(out + '/swift-set-bridge-checks', fs + '/opt/ios/swift-set-bridge-checks')
	copy_file(out + '/swift-logger-checks', fs + '/opt/ios/swift-logger-checks')
	copy_file(out + '/swift-main-actor-witness-checks', fs + '/opt/ios/swift-main-actor-witness-checks')
	copy_file(out + '/swift-main-actor-checks', fs + '/opt/ios/swift-main-actor-checks')
	copy_file(out + '/swift-nsobject-hashable-checks', fs + '/opt/ios/swift-nsobject-hashable-checks')
	copy_file(out + '/swift-objc-bool-metadata-checks', fs + '/opt/ios/swift-objc-bool-metadata-checks')
	copy_file(out + '/swift-objc-bool-checks', fs + '/opt/ios/swift-objc-bool-checks')
	copy_file(out + '/swift-actor-executor-checks', fs + '/opt/ios/swift-actor-executor-checks')
	copy_file(out + '/swift-task-priority-checks', fs + '/opt/ios/swift-task-priority-checks')
	copy_file(out + '/swift-task-alloc-checks', fs + '/opt/ios/swift-task-alloc-checks')
	copy_file(out + '/swift-task-create-checks', fs + '/opt/ios/swift-task-create-checks')
	copy_file(out + '/swift-task-switch-checks', fs + '/opt/ios/swift-task-switch-checks')
	copy_file(out + '/swift-json-encoder-initializer-checks', fs + '/opt/ios/swift-json-encoder-initializer-checks')
	copy_file(out + '/swift-json-encoder-dispatch-checks', fs + '/opt/ios/swift-json-encoder-dispatch-checks')
	copy_file(out + '/swift-json-encoder-date-dispatch-checks', fs + '/opt/ios/swift-json-encoder-date-dispatch-checks')
	copy_file(out + '/swift-json-date-strategy-checks', fs + '/opt/ios/swift-json-date-strategy-checks')
	copy_file(out + '/swift-json-encoder-date-case-checks', fs + '/opt/ios/swift-json-encoder-date-case-checks')
	copy_file(out + '/swift-json-decoder-initializer-checks', fs + '/opt/ios/swift-json-decoder-initializer-checks')
	copy_file(out + '/swift-json-decoder-dispatch-checks', fs + '/opt/ios/swift-json-decoder-dispatch-checks')
	copy_file(out + '/swift-cocoa-error-protocol-checks', fs + '/opt/ios/swift-cocoa-error-protocol-checks')
	copy_file(out + '/swift-cocoa-error-code-checks', fs + '/opt/ios/swift-cocoa-error-code-checks')
	copy_file(out + '/swift-nslog-checks', fs + '/opt/ios/swift-nslog-checks')
	copy_file(out + '/swift-string-unbridge-checks', fs + '/opt/ios/swift-string-unbridge-checks')
	copy_file(out + '/swift-cocoa-match-checks', fs + '/opt/ios/swift-cocoa-match-checks')
	copy_file(out + '/swift-localized-error-checks', fs + '/opt/ios/swift-localized-error-checks')
	copy_file(out + '/swift-error-description-checks', fs + '/opt/ios/swift-error-description-checks')
	copy_file(out + '/module-lookup-checks', fs + '/opt/ios/module-lookup-checks')
	sysroot := root + '/build-aarch64-userland/sysroot'
	checked([llvm, '--target=aarch64-linux-musl', '--sysroot=' + sysroot, '-static', '-O2',
		'-fno-stack-protector', '-Wall', '-Wextra', '-Werror', root + '/tests/ios/guest.c',
		root + '/tests/ios/uikit-guest.c', root + '/tests/ios/gles-guest.c', '-L' + sysroot + '/lib',
		'-fuse-ld=lld', '-o', fs + '/opt/ios/regression'])
}

fn await_checks(mut p os.Process, log string, marker string) ! {
	for _ in 0 .. 1200 {
		text := os.read_file(log) or { '' }
		if text.contains('iOS FAIL:') || text.contains('IOS-NATIVE: FAIL')
			|| text.contains('KERNEL PANIC') || text.contains('FATAL EXCEPTION')
			|| (text.contains('EXCEPTION') && text.contains('pc=0xffffffff'))
			|| (marker != 'VINIX iOS GUEST: PASS' && text.contains('V panic:')) {
			return error(text)
		}
		if text.contains(marker) { return }
		if !p.is_alive() { return error('QEMU exited before ' + marker + ': ' + p.stderr_slurp()) }
		time.sleep(200 * time.millisecond)
	}
	return error('VM timeout: ' + log)
}

fn verify_monitor(out string) {
	mut process := os.new_process('/usr/bin/true')
	process.set_redirect_stdio()
	process.run()
	process.wait()
	defer { process.close() }
	log := out + '/monitor-fixture.log'
	defer { os.rm(log) or { panic(err) } }
	marker := 'VINIX iOS GUEST: PASS'
	os.write_file(log, '') or { panic(err) }
	mut rejected_exit := false
	await_checks(mut process, log, marker) or {
		assert err.msg().starts_with('QEMU exited before ' + marker)
		rejected_exit = true
	}
	assert rejected_exit
	interleaved := 'FATASlab: object freed L EXCEPTION interleaved pc=0xffffffff80149b2c\n'
	os.write_file(log, interleaved) or { panic(err) }
	mut rejected_fault := false
	await_checks(mut process, log, marker) or {
		assert err.msg() == interleaved
		rejected_fault = true
	}
	assert rejected_fault
	os.write_file(log, marker + '\n') or { panic(err) }
	await_checks(mut process, log, marker) or { panic(err) }
	println('IOS-MONITOR: rejects unmarked QEMU exit and interleaved kernel faults; accepts guest PASS')
}

fn vm(root string, out string, mode string) {
	if mode !in ['regression', 'swift', 'objc', 'probe', 'audit', 'static-audit'] {
		panic('invalid check mode: ' + mode)
	}
	state := out + '/' + mode + '-' + time.sys_mono_now().str()
	if os.exists(state) { panic('VM state already exists') }
	os.write_file(out + '/' + mode + '-state.txt', state) or { panic(err) }
	os.mkdir_all(state + '/rootfs') or { panic(err) }
	fs := state + '/rootfs'
	if mode == 'regression' {
		regression_root(root, out, fs)
		copy_lookup_fixtures(out, fs)
	} else if mode == 'objc' {
		for directory in ['sbin', 'proc', 'sys', 'dev', 'tmp', 'opt/ios'] { os.mkdir_all(fs + '/' + directory) or { panic(err) } }
		copy_file(root + '/build/ios/fortnite/local/Payload/FortniteClient-IOS-Shipping.app/Frameworks/EOSSDK.framework/EOSSDK', fs + '/opt/ios/constant-dictionary-image')
		for name in ['objc-constant-dictionary', 'layout-constraint', 'json-serialization', 'condition', 'cookie', 'webkit-configuration', 'user-script', 'webview', 'request', 'value', 'response', 'alert', 'set', 'thread', 'auth-session', 'image-view', 'keyboard', 'nsuuid', 'filemanager', 'home-directory', 'temp-directory', 'url-error', 'session-constants', 'foundation-keys', 'audio-services', 'avfoundation-constants', 'corevideo', 'pixel-allocation', 'metal-cache', 'media-format', 'block-buffer', 'sample-buffer', 'cm-time', 'h264-format', 'hevc-format', 'cg-font', 'reachability', 'devicecheck', 'network-path', 'corehaptics-constants', 'media-time', 'video-decode', 'storefront', 'storefront-current', 'storefront-metadata', 'refund', 'storekit-constants', 'zlib-checksum', 'zlib-compress', 'zlib-bound', 'resolver-query', 'pbkdf', 'ndr-record', 'immediate-exit', 'crt-environ', 'executable-path', 'dispatch-timer-type', 'dyld-images', 'dyld-callbacks', 'tlv-atexit', 'inverse-hyperbolic', 'arc4random', 'asl', 'backtrace', 'dispatch-data', 'dispatch-specific', 'dispatch-group', 'dispatch-source', 'dispatch-semaphore', 'division', 'mach-exception', 'flock', 'progname', 'host-page-size', 'host-statistics', 'logb', 'memory-entry', 'mach-message', 'mach-port-set', 'mach-notification', 'madvise', 'malloc-zone', 'mkstemp', 'nextafter', 'unfair-lock', 'pause', 'proc-rusage', 'raise', 'setrlimit', 'sigaltstack', 'swscanf', 'task-exception-ports', 'task-info', 'task-swap-exception-ports', 'nslogv', 'protocol-lookup', 'uncaught-handler', 'protocol-name', 'autopool', 'processinfo', 'date', 'inputstream', 'connection', 'type-encoding', 'oslog', 'secure-memory', 'cf-dictionary', 'objc-storage', 'objc-associated', 'objc-property', 'objc-sync'] {
			copy_file(out + '/' + name + '-checks', fs + '/opt/ios/' + name + '-checks')
		}
		tree(root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles', fs + '/usr/lib/vinix/ios-gles')
	} else if mode == 'swift' {
		copy_lookup_fixtures(out, fs)
		copy_file(out + '/module-lookup-checks', fs + '/opt/ios/module-lookup-checks')
		for directory in ['sbin', 'proc', 'sys', 'dev', 'tmp', 'opt/ios'] {
			os.mkdir_all(fs + '/' + directory) or { panic(err) }
		}
		for name in ['unknown-value', 'string', 'empty-string', 'describing', 'cstring', 'empty-array', 'any', 'byte-metadata', 'raw-equality', 'array-class', 'shared-utf8', 'string-guts', 'foreign-copy', 'foreign-count', 'foreign-index', 'foreign-offset', 'foreign-subscript', 'utf16-offset', 'sequence', 'array-sequence', 'collection', 'set', 'metadata', 'protocol', 'hash', 'hasher', 'raw-representable',
			'array', 'integer', 'integer-hash', 'fatal', 'interpolation', 'array-storage', 'vararg', 'void', 'version', 'initializer', 'set-algebra', 'raw-copy', 'pointer-alloc', 'pointer-deinit', 'raw-alloc', 'dispatch-async', 'dispatch-main', 'dispatch-scheduler', 'dispatch-qos', 'dispatch-algebra', 'dispatch-flags', 'stack', 'heap', 'calendar-case', 'locale', 'date', 'data-write', 'data-unbridge', 'data-base64', 'data-bridge', 'data', 'url-metadata', 'url-path', 'url-bridge', 'error-bridge', 'error', 'error-value', 'dynamic-cast', 'objc-cast', 'foreign-metadata', 'object-type', 'mangled-state', 'mangled', 'witness', 'once', 'set-bridge', 'logger', 'main-actor-witness', 'main-actor', 'nsobject-hashable', 'objc-bool-metadata', 'objc-bool', 'actor-executor', 'task-priority', 'task-alloc', 'task-create', 'task-switch', 'nslog', 'string-unbridge', 'error-description', 'cocoa-error-code', 'cocoa-error-protocol', 'json-decoder-dispatch', 'json-decoder-initializer', 'json-encoder-date-case', 'json-date-strategy', 'json-encoder-date-dispatch', 'json-encoder-dispatch', 'json-encoder-initializer', 'localized-error'] {
			copy_file(out + '/swift-' + name + '-checks', fs + '/opt/ios/swift-' + name + '-checks')
		}
		copy_file(out + '/dispatch-queue-class-checks', fs + '/opt/ios/dispatch-queue-class-checks')
	} else {
		os.mkdir_all(fs + '/opt/ios') or { panic(err) }
		tree(root + '/build/ios/fortnite/local/Payload/FortniteClient-IOS-Shipping.app/Frameworks', fs + '/opt/ios/Frameworks')
		copy_file(out + '/' + if mode == 'static-audit' { 'run-ios' } else { 'run-ios-gles' }, fs + '/opt/ios/run-ios')
		tree(root + '/build/ios/fortnite/staging/usr/lib/vinix/ios-gles', fs + '/usr/lib/vinix/ios-gles')
	}
	copy_file(out + '/native-init', fs + '/sbin/init')
	if mode in ['regression', 'swift', 'objc'] {
		os.mkdir_all(fs + '/etc') or { panic(err) }
		os.write_file(fs + '/etc/resolv.conf', 'nameserver 127.0.0.1\noptions timeout:1 attempts:1\n') or { panic(err) }
	}
	os.write_file(fs + '/opt/ios/check-mode', if mode.contains('audit') { 'audit' } else { mode }) or { panic(err) }
	archive := state + '/initramfs.tar.gz'
	if mode in ['probe', 'audit', 'static-audit'] {
		// This Mac's libarchive copies the preserved IPA executable directly
		// between archives. Omit its old runner; the overlay path starts ./
		// and supplies exactly one current replacement. No large extraction.
		checked(['tar', '--format=ustar', '-czf', archive, '-s', ',^opt/ios/run-ios$,,',
			'@' + root + '/build/ios/fortnite/probe-initramfs.tar.gz', '-C', fs, '.'])
	} else {
		checked(['tar', '--format=ustar', '-czf', archive, '-C', fs, '.'])
	}
	// These modes boot entirely from the archive. Release the extracted IPA
	// and staging copies before constructing the disk to limit host disk use.
	// Regression keeps its corrected stdio fixture for evidence collection.
	if mode != 'regression' { os.rmdir_all(fs) or { panic(err) } }
	disk := state + '/boot.img'
	checked(['mkfile', '-n', '640m', disk])
	checked(['mformat', '-F', '-i', disk, '::'])
	for path in ['::/EFI', '::/EFI/BOOT', '::/boot'] { checked(['mmd', '-i', disk, path]) }
	conf := state + '/limine.conf'
	os.write_file(conf, 'timeout: 0\nverbose: yes\n/Vinix\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: \$boot():/boot/initramfs.tar.gz\n    resolution: 1024x768x32\n    kaslr: no\n') or { panic(err) }
	for source, target in {
		root + '/boot-image/limine-bin/BOOTAA64.EFI':               '::/EFI/BOOT/BOOTAA64.EFI'
		conf:                                                       '::/boot/limine.conf'
		root + '/build/ios/fortnite/socket-kernel-arm64/bin/vinix': '::/boot/vinix'
		archive:                                                    '::/boot/initramfs.tar.gz'
	} {
		checked(['mcopy', '-i', disk, source, target])
	}
	vars := state + '/efivars.fd'
	checked(['mkfile', '-n', '64m', vars])
	log := state + '/serial.log'
	mut p := os.new_process('/opt/homebrew/bin/qemu-system-aarch64')
	p.set_args(['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '4096',
		'-smp', '4', '-device', 'ramfb', '-display', 'none', '-monitor', 'none', '-serial',
		'file:' + log, '-drive',
		'if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'-drive', 'if=pflash,format=raw,file=' + vars, '-drive', 'format=raw,file=' + disk, '-device',
		'virtio-keyboard-device', '-device', 'virtio-tablet-device'])
	p.set_redirect_stdio()
	p.run()
	marker := if mode == 'regression' { 'VINIX iOS GUEST: PASS' } else if mode == 'swift' { 'VINIX iOS SWIFT: PASS' } else if mode == 'objc' { 'VINIX iOS OBJC: PASS' } else { 'FORTNITE PROBE COMPLETE' }
	mut failure := ''
	await_checks(mut p, log, marker) or { failure = err.msg() }
	// V panics do not unwind defers. Close our VM before reporting failure.
	if p.is_alive() {
		p.signal_term()
		for _ in 0 .. 40 {
			if !p.is_alive() { break }
			time.sleep(50 * time.millisecond)
		}
		// HVF can leave the completed guest stuck while QEMU shuts down.
		if p.is_alive() { p.signal_kill() }
		p.wait()
	}
	p.close()
	if failure != '' { panic(failure) }
	println('${mode}: ${if mode in ['regression', 'swift', 'objc'] {
		'PASS'
	} else {
		'COMPLETE (see guest process status)'
	}}')
}

fn main() {
	if os.args.len < 2 {
		panic('usage: native-checks build|build-init|build-select|build-semaphore|build-signal|build-error|build-sysctl|build-terminal|build-thread-policy|build-file-time|build-uuid|build-audio-session|build-cf-dictionary|build-objc-storage|build-objc-associated|build-objc-property|build-objc-sync|build-objc-constant-dictionary|build-layout-constraint|build-json-serialization|build-condition|build-cookie|build-webkit-configuration|build-user-script|build-webview|build-request|build-value|build-response|build-alert|build-set|build-thread|build-auth-session|build-image-view|build-keyboard|build-nsuuid|build-filemanager|build-temp-directory|build-url-error|build-session-constants|build-foundation-keys|build-audio-services|build-avfoundation-constants|build-corevideo|build-pixel-allocation|build-metal-cache|build-media-format|build-block-buffer|build-sample-buffer|build-cm-time|build-h264-format|build-hevc-format|build-cg-font|build-reachability|build-devicecheck|build-network-path|build-corehaptics-constants|build-media-time|build-video-decode|build-storefront|build-storefront-current|build-storefront-metadata|build-refund|build-storekit-constants|build-zlib-checksum|build-zlib-compress|build-zlib-bound|build-resolver-query|build-pbkdf|build-ndr-record|build-immediate-exit|build-crt-environ|build-executable-path|build-dispatch-timer-type|build-dyld-images|build-dyld-callbacks|build-tlv-atexit|build-inverse-hyperbolic|build-arc4random|build-asl|build-backtrace|build-dispatch-data|build-dispatch-specific|build-dispatch-group|build-dispatch-source|build-dispatch-semaphore|build-division|build-mach-exception|build-flock|build-progname|build-host-page-size|build-host-statistics|build-logb|build-memory-entry|build-mach-message|build-mach-port-set|build-mach-notification|build-madvise|build-malloc-zone|build-mkstemp|build-nextafter|build-unfair-lock|build-pause|build-proc-rusage|build-raise|build-setrlimit|build-sigaltstack|build-swscanf|build-task-exception-ports|build-task-info|build-task-swap-exception-ports|build-nslogv|build-protocol-lookup|build-uncaught-handler|build-protocol-name|build-autopool|build-processinfo|build-date|build-inputstream|build-connection|build-type-encoding|build-dispatch-queue-class|build-oslog|build-secure-memory|build-swift-unknown-value|build-swift-string|build-swift-empty-string|build-swift-describing|build-swift-cstring|build-swift-foreign-count|build-swift-foreign-index|build-swift-foreign-offset|build-swift-foreign-subscript|build-swift-utf16-offset|build-swift-sequence|build-swift-array-sequence|build-swift-collection|build-swift-set|build-swift-metadata|build-swift-protocol|build-swift-hash|build-swift-hasher|build-swift-raw-representable|build-swift-array|build-swift-integer|build-swift-integer-hash|build-swift-fatal|build-swift-interpolation|build-swift-array-storage|build-swift-vararg|build-swift-void|build-swift-version|build-swift-initializer|build-swift-empty-array|build-swift-any|build-swift-byte-metadata|build-swift-raw-equality|build-swift-array-class|build-swift-shared-utf8|build-swift-string-guts|build-swift-foreign-copy|build-swift-set-algebra|build-swift-raw-copy|build-swift-pointer-alloc|build-swift-pointer-deinit|build-swift-raw-alloc|build-swift-dispatch-async|build-swift-dispatch-main|build-swift-dispatch-scheduler|build-swift-dispatch-qos|build-swift-dispatch-algebra|build-swift-dispatch-flags|build-swift-stack|build-swift-heap|build-swift-calendar-case|build-swift-locale|build-swift-date|build-swift-data-write|build-swift-data-unbridge|build-swift-data-base64|build-swift-data-bridge|build-swift-data|build-swift-url-metadata|build-swift-url-path|build-swift-url-bridge|build-swift-error-bridge|build-swift-error|build-swift-error-value|build-swift-dynamic-cast|build-swift-objc-cast|build-swift-foreign-metadata|build-swift-object-type|build-swift-mangled-state|build-swift-mangled|build-swift-witness|build-swift-once|build-swift-set-bridge|build-swift-logger|build-swift-main-actor-witness|build-swift-main-actor|build-swift-nsobject-hashable|build-swift-objc-bool-metadata|build-swift-objc-bool|build-swift-actor-executor|build-swift-task-priority|build-swift-task-alloc|build-swift-task-create|build-swift-task-switch|build-swift-json-encoder-initializer|build-swift-json-encoder-dispatch|build-swift-json-encoder-date-dispatch|build-swift-json-date-strategy|build-swift-json-encoder-date-case|build-swift-json-decoder-initializer|build-swift-json-decoder-dispatch|build-swift-cocoa-error-protocol|build-swift-cocoa-error-code|build-swift-nslog|build-swift-string-unbridge|build-swift-localized-error|build-swift-error-description|build-module-lookup|verify-monitor|regression|swift|objc|probe|audit|static-audit|hash FILE')
	}
	root := os.real_path(os.getwd())
	requested := os.getenv('VINIX_IOS_CHECK_NAME')
	check_name := if requested == '' { 'select-checks' } else { requested }
	if check_name.contains('/') || check_name in ['.', '..'] {
		panic('check name must be one directory component')
	}
	out := root + '/build/ios/fortnite/' + check_name
	os.mkdir_all(out + '/tmp') or { panic(err) }
	os.setenv('TMPDIR', out + '/tmp', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mode := os.args[1]
	if mode == 'build' {
		build(root, out, '')
	} else if mode == 'build-init' {
		build(root, out, 'native-init')
	} else if mode == 'build-module-lookup' {
		build(root, out, 'module-lookup-checks')
	} else if mode == 'build-select' {
		build(root, out, 'select-checks')
	} else if mode == 'build-semaphore' {
		build(root, out, 'semaphore-checks')
	} else if mode == 'build-signal' {
		build(root, out, 'signal-checks')
	} else if mode == 'build-error' {
		build(root, out, 'error-checks')
	} else if mode == 'build-sysctl' {
		build(root, out, 'sysctl-checks')
	} else if mode == 'build-terminal' {
		build(root, out, 'terminal-checks')
	} else if mode == 'build-thread-policy' {
		build(root, out, 'thread-policy-checks')
	} else if mode == 'build-file-time' {
		build(root, out, 'file-time-checks')
	} else if mode == 'build-uuid' {
		build(root, out, 'uuid-checks')
	} else if mode == 'build-audio-session' {
		build(root, out, 'audio-session-checks')
	} else if mode == 'build-cf-dictionary' {
		build(root, out, 'cf-dictionary-checks')
	} else if mode == 'build-objc-storage' {
		build(root, out, 'objc-storage-checks')
	} else if mode == 'build-objc-associated' {
		build(root, out, 'objc-associated-checks')
	} else if mode == 'build-objc-property' {
		build(root, out, 'objc-property-checks')
	} else if mode == 'build-objc-sync' {
		build(root, out, 'objc-sync-checks')
	} else if mode == 'build-objc-constant-dictionary' {
		build(root, out, 'objc-constant-dictionary-checks')
	} else if mode == 'build-layout-constraint' {
		build(root, out, 'layout-constraint-checks')
	} else if mode == 'build-json-serialization' {
		build(root, out, 'json-serialization-checks')
	} else if mode == 'build-secure-memory' {
		build(root, out, 'secure-memory-checks')
	} else if mode == 'build-dispatch-queue-class' {
		build(root,out,'dispatch-queue-class-checks')
	} else if mode == 'build-oslog' {
		build(root, out, 'oslog-checks')
	} else if mode == 'build-type-encoding' {
		build(root, out, 'type-encoding-checks')
	} else if mode == 'build-connection' {
		build(root, out, 'connection-checks')
	} else if mode == 'build-inputstream' {
		build(root, out, 'inputstream-checks')
	} else if mode == 'build-date' {
		build(root, out, 'date-checks')
	} else if mode == 'build-processinfo' {
		build(root, out, 'processinfo-checks')
	} else if mode == 'build-autopool' {
		build(root, out, 'autopool-checks')
	} else if mode == 'build-protocol-name' {
		build(root, out, 'protocol-name-checks')
	} else if mode == 'build-temp-directory' {
		build(root, out, 'temp-directory-checks')
	} else if mode == 'build-media-time' {
		build(root,out,'media-time-checks')
	} else if mode == 'build-division' {
		build(root, out, 'division-checks')
	} else if mode == 'build-dispatch-semaphore' {
		build(root, out, 'dispatch-semaphore-checks')
	} else if mode == 'build-dispatch-source' {
		build(root, out, 'dispatch-source-checks')
	} else if mode == 'build-dispatch-group' {
		build(root, out, 'dispatch-group-checks')
	} else if mode == 'build-dispatch-specific' {
		build(root, out, 'dispatch-specific-checks')
	} else if mode == 'build-dispatch-data' {
		build(root, out, 'dispatch-data-checks')
	} else if mode == 'build-backtrace' {
		build(root, out, 'backtrace-checks')
	} else if mode == 'build-asl' {
		build(root, out, 'asl-checks')
	} else if mode == 'build-arc4random' {
		build(root, out, 'arc4random-checks')
	} else if mode == 'build-inverse-hyperbolic' {
		build(root, out, 'inverse-hyperbolic-checks')
	} else if mode == 'build-tlv-atexit' {
		build(root, out, 'tlv-atexit-checks')
	} else if mode == 'build-dyld-callbacks' {
		build(root, out, 'dyld-callbacks-checks')
	} else if mode == 'build-dyld-images' {
		build(root, out, 'dyld-images-checks')
	} else if mode == 'build-dispatch-timer-type' {
		build(root,out,'dispatch-timer-type-checks')
	} else if mode == 'build-executable-path' {
		build(root,out,'executable-path-checks')
	} else if mode == 'build-crt-environ' {
		build(root,out,'crt-environ-checks')
	} else if mode == 'build-immediate-exit' {
		build(root,out,'immediate-exit-checks')
	} else if mode == 'build-ndr-record' {
		build(root,out,'ndr-record-checks')
	} else if mode == 'build-pbkdf' {
		build(root,out,'pbkdf-checks')
	} else if mode == 'build-resolver-query' {
		build(root,out,'resolver-query-checks')
	} else if mode == 'build-zlib-bound' {
		build(root,out,'zlib-bound-checks')
	} else if mode == 'build-zlib-compress' {
		build(root,out,'zlib-compress-checks')
	} else if mode == 'build-zlib-checksum' {
		build(root,out,'zlib-checksum-checks')
	} else if mode == 'build-storekit-constants' {
		build(root,out,'storekit-constants-checks')
	} else if mode == 'build-refund' {
		build(root,out,'refund-checks')
	} else if mode == 'build-storefront-metadata' {
		build(root,out,'storefront-metadata-checks')
	} else if mode == 'build-storefront-current' {
		build(root,out,'storefront-current-checks')
	} else if mode == 'build-storefront' {
		build(root,out,'storefront-checks')
	} else if mode == 'build-video-decode' {
		build(root,out,'video-decode-checks')
	} else if mode == 'build-corehaptics-constants' {
		build(root,out,'corehaptics-constants-checks')
	} else if mode == 'build-network-path' {
		build(root,out,'network-path-checks')
	} else if mode == 'build-devicecheck' {
		build(root,out,'devicecheck-checks')
	} else if mode == 'build-reachability' {
		build(root,out,'reachability-checks')
	} else if mode == 'build-cg-font' {
		build(root,out,'cg-font-checks')
	} else if mode == 'build-hevc-format' {
		build(root,out,'hevc-format-checks')
	} else if mode == 'build-h264-format' {
		build(root,out,'h264-format-checks')
	} else if mode == 'build-cm-time' {
		build(root, out, 'cm-time-checks')
	} else if mode == 'build-sample-buffer' {
		build(root, out, 'sample-buffer-checks')
	} else if mode == 'build-block-buffer' {
		build(root, out, 'block-buffer-checks')
	} else if mode == 'build-media-format' {
		build(root, out, 'media-format-checks')
	} else if mode == 'build-metal-cache' {
		build(root, out, 'metal-cache-checks')
	} else if mode == 'build-pixel-allocation' {
		build(root, out, 'pixel-allocation-checks')
	} else if mode == 'build-corevideo' {
		build(root, out, 'corevideo-checks')
	} else if mode == 'build-avfoundation-constants' {
		build(root, out, 'avfoundation-constants-checks')
	} else if mode == 'build-audio-services' {
		build(root, out, 'audio-services-checks')
	} else if mode == 'build-foundation-keys' {
		build(root, out, 'foundation-keys-checks')
	} else if mode == 'build-session-constants' {
		build(root, out, 'session-constants-checks')
	} else if mode == 'build-url-error' {
		build(root, out, 'url-error-checks')
	} else if mode == 'build-uncaught-handler' {
		build(root, out, 'uncaught-handler-checks')
	} else if mode == 'build-protocol-lookup' {
		build(root, out, 'protocol-lookup-checks')
	} else if mode == 'build-nslogv' {
		build(root, out, 'nslogv-checks')
	} else if mode == 'build-home-directory' {
		build(root, out, 'home-directory-checks')
	} else if mode == 'build-filemanager' {
		build(root, out, 'filemanager-checks')
	} else if mode == 'build-nsuuid' {
		build(root, out, 'nsuuid-checks')
	} else if mode == 'build-keyboard' {
		build(root, out, 'keyboard-checks')
	} else if mode == 'build-image-view' {
		build(root, out, 'image-view-checks')
	} else if mode == 'build-auth-session' {
		build(root, out, 'auth-session-checks')
	} else if mode == 'build-thread' {
		build(root, out, 'thread-checks')
	} else if mode == 'build-set' {
		build(root, out, 'set-checks')
	} else if mode == 'build-alert' {
		build(root, out, 'alert-checks')
	} else if mode == 'build-response' {
		build(root, out, 'response-checks')
	} else if mode == 'build-value' {
		build(root, out, 'value-checks')
	} else if mode == 'build-request' {
		build(root, out, 'request-checks')
	} else if mode == 'build-webview' {
		build(root, out, 'webview-checks')
	} else if mode == 'build-user-script' {
		build(root, out, 'user-script-checks')
	} else if mode == 'build-webkit-configuration' {
		build(root, out, 'webkit-configuration-checks')
	} else if mode == 'build-cookie' {
		build(root, out, 'cookie-checks')
	} else if mode == 'build-condition' {
		build(root, out, 'condition-checks')
	} else if mode == 'build-swift-unknown-value' {
		build(root, out, 'swift-unknown-value-checks')
	} else if mode == 'build-swift-sequence' {
		build(root, out, 'swift-sequence-checks')
	} else if mode == 'build-swift-array-sequence' {
		build(root, out, 'swift-array-sequence-checks')
	} else if mode == 'build-swift-set' {
		build(root, out, 'swift-set-checks')
	} else if mode == 'build-swift-collection' {
		build(root, out, 'swift-collection-checks')
	} else if mode == 'build-swift-utf16-offset' {
		build(root, out, 'swift-utf16-offset-checks')
	} else if mode == 'build-swift-foreign-subscript' {
		build(root, out, 'swift-foreign-subscript-checks')
	} else if mode == 'build-swift-foreign-offset' {
		build(root, out, 'swift-foreign-offset-checks')
	} else if mode == 'build-swift-foreign-index' {
		build(root, out, 'swift-foreign-index-checks')
	} else if mode == 'build-swift-foreign-count' {
		build(root, out, 'swift-foreign-count-checks')
	} else if mode == 'build-swift-cstring' {
		build(root, out, 'swift-cstring-checks')
	} else if mode == 'build-swift-describing' {
		build(root, out, 'swift-describing-checks')
	} else if mode == 'build-swift-empty-string' {
		build(root, out, 'swift-empty-string-checks')
	} else if mode == 'build-swift-string' {
		build(root, out, 'swift-string-checks')
	} else if mode == 'build-swift-metadata' {
		build(root, out, 'swift-metadata-checks')
	} else if mode == 'build-swift-protocol' {
		build(root, out, 'swift-protocol-checks')
	} else if mode == 'build-swift-hash' {
		build(root, out, 'swift-hash-checks')
	} else if mode == 'build-swift-hasher' {
		build(root, out, 'swift-hasher-checks')
	} else if mode == 'build-swift-raw-representable' {
		build(root, out, 'swift-raw-representable-checks')
	} else if mode == 'build-swift-array' {
		build(root, out, 'swift-array-checks')
	} else if mode == 'build-swift-integer' {
		build(root, out, 'swift-integer-checks')
	} else if mode == 'build-swift-integer-hash' {
		build(root, out, 'swift-integer-hash-checks')
	} else if mode == 'build-swift-fatal' {
		build(root, out, 'swift-fatal-checks')
	} else if mode == 'build-swift-interpolation' {
		build(root, out, 'swift-interpolation-checks')
	} else if mode == 'build-swift-array-storage' {
		build(root, out, 'swift-array-storage-checks')
	} else if mode == 'build-swift-vararg' {
		build(root, out, 'swift-vararg-checks')
	} else if mode == 'build-swift-void' {
		build(root, out, 'swift-void-checks')
	} else if mode == 'build-swift-version' {
		build(root, out, 'swift-version-checks')
	} else if mode == 'build-swift-initializer' {
		build(root, out, 'swift-initializer-checks')
	} else if mode == 'build-swift-empty-array' {
		build(root,out,'swift-empty-array-checks')
	} else if mode == 'build-swift-any' {
		build(root,out,'swift-any-checks')
	} else if mode == 'build-swift-byte-metadata' {
		build(root,out,'swift-byte-metadata-checks')
	} else if mode == 'build-swift-raw-equality' {
		build(root,out,'swift-raw-equality-checks')
	} else if mode == 'build-swift-array-class' {
		build(root,out,'swift-array-class-checks')
	} else if mode == 'build-swift-shared-utf8' {
		build(root,out,'swift-shared-utf8-checks')
	} else if mode == 'build-swift-string-guts' {
		build(root,out,'swift-string-guts-checks')
	} else if mode == 'build-swift-foreign-copy' {
		build(root,out,'swift-foreign-copy-checks')
	} else if mode == 'build-swift-set-algebra' {
		build(root,out,'swift-set-algebra-checks')
	} else if mode == 'build-swift-raw-copy' {
		build(root, out, 'swift-raw-copy-checks')
	} else if mode == 'build-swift-pointer-alloc' {
		build(root, out, 'swift-pointer-alloc-checks')
	} else if mode == 'build-swift-pointer-deinit' {
		build(root, out, 'swift-pointer-deinit-checks')
	} else if mode == 'build-swift-raw-alloc' {
		build(root, out, 'swift-raw-alloc-checks')
	} else if mode == 'build-swift-dispatch-async' {
		build(root,out,'swift-dispatch-async-checks')
	} else if mode == 'build-swift-dispatch-main' {
		build(root,out,'swift-dispatch-main-checks')
	} else if mode == 'build-swift-dispatch-scheduler' {
		build(root,out,'swift-dispatch-scheduler-checks')
	} else if mode == 'build-swift-dispatch-qos' {
		build(root,out,'swift-dispatch-qos-checks')
	} else if mode == 'build-swift-dispatch-algebra' {
		build(root,out,'swift-dispatch-algebra-checks')
	} else if mode == 'build-swift-dispatch-flags' {
		build(root,out,'swift-dispatch-flags-checks')
	} else if mode == 'build-swift-stack' {
		build(root,out,'swift-stack-checks')
	} else if mode == 'build-swift-heap' {
		build(root, out, 'swift-heap-checks')
	} else if mode == 'build-swift-string-replace' {
		build(root,out,'swift-string-replace-checks')
	} else if mode == 'build-swift-array-unbridge' {
		build(root,out,'swift-array-unbridge-checks')
	} else if mode == 'build-swift-dictionary-bridge' {
		build(root,out,'swift-dictionary-bridge-checks')
	} else if mode == 'build-swift-calendar-case' {
		build(root,out,'swift-calendar-case-checks')
	} else if mode == 'build-swift-locale' {
		build(root,out,'swift-locale-checks')
	} else if mode == 'build-swift-date' {
		build(root,out,'swift-date-checks')
	} else if mode == 'build-swift-data-write' {
		build(root,out,'swift-data-write-checks')
	} else if mode == 'build-swift-data-unbridge' {
		build(root,out,'swift-data-unbridge-checks')
	} else if mode == 'build-swift-data-base64' {
		build(root,out,'swift-data-base64-checks')
	} else if mode == 'build-swift-data-bridge' {
		build(root,out,'swift-data-bridge-checks')
	} else if mode == 'build-swift-data' {
		build(root,out,'swift-data-checks')
	} else if mode == 'build-swift-url-metadata' {
		build(root,out,'swift-url-metadata-checks')
	} else if mode == 'build-swift-url-path' {
		build(root,out,'swift-url-path-checks')
	} else if mode == 'build-swift-url-bridge' {
		build(root,out,'swift-url-bridge-checks')
	} else if mode == 'build-swift-error-bridge' {
		build(root,out,'swift-error-bridge-checks')
	} else if mode == 'build-swift-error' {
		build(root, out, 'swift-error-checks')
	} else if mode == 'build-swift-error-value' {
		build(root, out, 'swift-error-value-checks')
	} else if mode == 'build-swift-dynamic-cast' {
		build(root,out,'swift-dynamic-cast-checks')
	} else if mode == 'build-swift-objc-cast' {
		build(root,out,'swift-objc-cast-checks')
	} else if mode == 'build-swift-foreign-metadata' {
		build(root,out,'swift-foreign-metadata-checks')
	} else if mode == 'build-swift-object-type' {
		build(root, out, 'swift-object-type-checks')
	} else if mode == 'build-swift-mangled-state' {
		build(root,out,'swift-mangled-state-checks')
	} else if mode == 'build-swift-mangled' {
		build(root, out, 'swift-mangled-checks')
	} else if mode == 'build-swift-witness' {
		build(root, out, 'swift-witness-checks')
	} else if mode == 'build-swift-json-encoder-initializer' {
		build(root, out, 'swift-json-encoder-initializer-checks')
	} else if mode == 'build-swift-json-encoder-dispatch' {
		build(root, out, 'swift-json-encoder-dispatch-checks')
	} else if mode == 'build-swift-json-encoder-date-dispatch' {
		build(root, out, 'swift-json-encoder-date-dispatch-checks')
	} else if mode == 'build-swift-json-date-strategy' {
		build(root, out, 'swift-json-date-strategy-checks')
	} else if mode == 'build-swift-json-encoder-date-case' {
		build(root, out, 'swift-json-encoder-date-case-checks')
	} else if mode == 'build-swift-json-decoder-initializer' {
		build(root,out,'swift-json-decoder-initializer-checks')
	} else if mode == 'build-swift-json-decoder-dispatch' {
		build(root,out,'swift-json-decoder-dispatch-checks')
	} else if mode == 'build-swift-cocoa-error-protocol' {
		build(root,out,'swift-cocoa-error-protocol-checks')
	} else if mode == 'build-swift-cocoa-error-code' {
		build(root,out,'swift-cocoa-error-code-checks')
	} else if mode == 'build-swift-nslog' {
		build(root, out, 'swift-nslog-checks')
	} else if mode == 'build-swift-cocoa-match' {
		build(root, out, 'swift-cocoa-match-checks')
	} else if mode == 'build-swift-localized-error' {
		build(root, out, 'swift-localized-error-checks')
	} else if mode == 'build-swift-error-description' {
		build(root, out, 'swift-error-description-checks')
	} else if mode == 'build-swift-string-unbridge' {
		build(root, out, 'swift-string-unbridge-checks')
	} else if mode == 'build-swift-task-switch' {
		build(root, out, 'swift-task-switch-checks')
	} else if mode == 'build-swift-task-create' {
		build(root, out, 'swift-task-create-checks')
	} else if mode == 'build-swift-task-alloc' {
		build(root, out, 'swift-task-alloc-checks')
	} else if mode == 'build-swift-task-priority' {
		build(root, out, 'swift-task-priority-checks')
	} else if mode == 'build-swift-actor-executor' {
		build(root, out, 'swift-actor-executor-checks')
	} else if mode == 'build-swift-set-bridge' {
		build(root,out,'swift-set-bridge-checks')
	} else if mode == 'build-swift-logger' {
		build(root,out,'swift-logger-checks')
	} else if mode == 'build-swift-main-actor-witness' {
		build(root,out,'swift-main-actor-witness-checks')
	} else if mode == 'build-swift-main-actor' {
		build(root,out,'swift-main-actor-checks')
	} else if mode == 'build-swift-nsobject-hashable' {
		build(root,out,'swift-nsobject-hashable-checks')
	} else if mode == 'build-swift-objc-bool-metadata' {
		build(root,out,'swift-objc-bool-metadata-checks')
	} else if mode == 'build-swift-objc-bool' {
		build(root, out, 'swift-objc-bool-checks')
	} else if mode == 'build-swift-once' {
		build(root, out, 'swift-once-checks')
	} else if mode.starts_with('build-') {
		// New fixtures already register their source and build-list entry.
		// Route their individual build commands without another dispatch entry.
		fixture := mode[6..] + '-checks'
		native_fixture_source(fixture)
		build(root, out, fixture)
	} else if mode == 'verify-monitor' {
		verify_monitor(out)
	} else if mode == 'hash' {
		if os.args.len != 3 { panic('usage: native-checks hash FILE') }
		println(sha256.sum(os.read_bytes(os.args[2]) or { panic(err) }).hex())
	} else {
		vm(root, out, mode)
	}
}
