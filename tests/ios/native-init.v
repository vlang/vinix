// SPDX-License-Identifier: GPL-2.0-or-later
// PID 1 for the standalone V compatibility checks; no host interpreter.
module main

import os

#include <unistd.h>
#include <sys/wait.h>
#include <stdio.h>

fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pause() i32
fn C.fflush(voidptr) i32

fn run_child(path string, args []string) i32 {
	mut pointers := []&char{}
	pointers << path.str
	for arg in args { pointers << arg.str }
	pointers << &char(unsafe { nil })
	child := C.fork()
	if child < 0 { panic('fork') }
	if child == 0 {
		C.execv(path.str, pointers.data)
		exit(127)
	}
	mut status := i32(0)
	if C.waitpid(child, unsafe { &status }, 0) != child { panic('waitpid') }
	println('IOS-NATIVE: ${path} wait status ${status}')
	C.fflush(unsafe { nil })
	return status
}

fn require_child(path string) {
	if run_child(path, []) != 0 {
		println('IOS-NATIVE: FAIL ' + path)
		C.fflush(unsafe { nil })
		panic('native check failed')
	}
}

fn main() {
	mode := os.read_file('/opt/ios/check-mode') or { panic(err) }
	if mode == 'regression' {
		require_child('/opt/ios/select-checks')
		require_child('/opt/ios/semaphore-checks')
		require_child('/opt/ios/signal-checks')
		require_child('/opt/ios/error-checks')
		require_child('/opt/ios/sysctl-checks')
		require_child('/opt/ios/terminal-checks')
		require_child('/opt/ios/thread-policy-checks')
		require_child('/opt/ios/file-time-checks')
		require_child('/opt/ios/uuid-checks')
		require_child('/opt/ios/audio-session-checks')
		require_child('/opt/ios/cf-dictionary-checks')
		require_child('/opt/ios/objc-constant-dictionary-checks')
		require_child('/opt/ios/layout-constraint-checks')
		require_child('/opt/ios/json-serialization-checks')
		require_child('/opt/ios/condition-checks')
		require_child('/opt/ios/cookie-checks')
		require_child('/opt/ios/webkit-configuration-checks')
		require_child('/opt/ios/user-script-checks')
		require_child('/opt/ios/webview-checks')
		require_child('/opt/ios/request-checks')
		require_child('/opt/ios/value-checks')
		require_child('/opt/ios/response-checks')
		require_child('/opt/ios/alert-checks')
		require_child('/opt/ios/set-checks')
		require_child('/opt/ios/thread-checks')
		require_child('/opt/ios/auth-session-checks')
		require_child('/opt/ios/image-view-checks')
		require_child('/opt/ios/keyboard-checks')
		require_child('/opt/ios/nsuuid-checks')
		require_child('/opt/ios/filemanager-checks')
		require_child('/opt/ios/home-directory-checks')
		require_child('/opt/ios/temp-directory-checks')
		require_child('/opt/ios/url-error-checks')
		require_child('/opt/ios/session-constants-checks')
		require_child('/opt/ios/foundation-keys-checks')
		require_child('/opt/ios/audio-services-checks')
		require_child('/opt/ios/avfoundation-constants-checks')
		require_child('/opt/ios/corevideo-checks')
		require_child('/opt/ios/pixel-allocation-checks')
		require_child('/opt/ios/metal-cache-checks')
		require_child('/opt/ios/media-format-checks')
		require_child('/opt/ios/block-buffer-checks')
		require_child('/opt/ios/sample-buffer-checks')
		require_child('/opt/ios/cm-time-checks')
		require_child('/opt/ios/h264-format-checks')
		require_child('/opt/ios/hevc-format-checks')
		require_child('/opt/ios/cg-font-checks')
		require_child('/opt/ios/reachability-checks')
		require_child('/opt/ios/devicecheck-checks')
		require_child('/opt/ios/network-path-checks')
		require_child('/opt/ios/corehaptics-constants-checks')
		require_child('/opt/ios/media-time-checks')
		require_child('/opt/ios/video-decode-checks')
		require_child('/opt/ios/storefront-checks')
		require_child('/opt/ios/storefront-current-checks')
		require_child('/opt/ios/storefront-metadata-checks')
		require_child('/opt/ios/refund-checks')
		require_child('/opt/ios/storekit-constants-checks')
		require_child('/opt/ios/zlib-checksum-checks')
		require_child('/opt/ios/zlib-compress-checks')
		require_child('/opt/ios/zlib-bound-checks')
		require_child('/opt/ios/resolver-query-checks')
		require_child('/opt/ios/pbkdf-checks')
		require_child('/opt/ios/ndr-record-checks')
		require_child('/opt/ios/immediate-exit-checks')
		require_child('/opt/ios/crt-environ-checks')
		require_child('/opt/ios/executable-path-checks')
		require_child('/opt/ios/dispatch-timer-type-checks')
		require_child('/opt/ios/dyld-images-checks')
		require_child('/opt/ios/dyld-callbacks-checks')
		require_child('/opt/ios/tlv-atexit-checks')
		require_child('/opt/ios/inverse-hyperbolic-checks')
		require_child('/opt/ios/arc4random-checks')
		require_child('/opt/ios/asl-checks')
		require_child('/opt/ios/backtrace-checks')
		require_child('/opt/ios/dispatch-data-checks')
		require_child('/opt/ios/dispatch-specific-checks')
		require_child('/opt/ios/dispatch-group-checks')
		require_child('/opt/ios/dispatch-source-checks')
		require_child('/opt/ios/dispatch-semaphore-checks')
		require_child('/opt/ios/division-checks')
		require_child('/opt/ios/nslogv-checks')
		require_child('/opt/ios/protocol-lookup-checks')
		require_child('/opt/ios/uncaught-handler-checks')
		require_child('/opt/ios/protocol-name-checks')
		require_child('/opt/ios/autopool-checks')
		require_child('/opt/ios/processinfo-checks')
		require_child('/opt/ios/date-checks')
		require_child('/opt/ios/inputstream-checks')
		require_child('/opt/ios/connection-checks')
		require_child('/opt/ios/type-encoding-checks')
		require_child('/opt/ios/dispatch-queue-class-checks')
		require_child('/opt/ios/oslog-checks')
		require_child('/opt/ios/secure-memory-checks')
		require_child('/opt/ios/objc-storage-checks')
		require_child('/opt/ios/objc-associated-checks')
		require_child('/opt/ios/objc-property-checks')
		require_child('/opt/ios/objc-sync-checks')
		require_child('/opt/ios/swift-unknown-value-checks')
		require_child('/opt/ios/swift-string-checks')
		require_child('/opt/ios/swift-empty-string-checks')
		require_child('/opt/ios/swift-describing-checks')
		require_child('/opt/ios/swift-cstring-checks')
		require_child('/opt/ios/swift-empty-array-checks')
		require_child('/opt/ios/swift-any-checks')
		require_child('/opt/ios/swift-byte-metadata-checks')
		require_child('/opt/ios/swift-raw-equality-checks')
		require_child('/opt/ios/swift-array-class-checks')
		require_child('/opt/ios/swift-shared-utf8-checks')
		require_child('/opt/ios/swift-string-guts-checks')
		require_child('/opt/ios/swift-foreign-copy-checks')
		require_child('/opt/ios/swift-foreign-count-checks')
		require_child('/opt/ios/swift-foreign-index-checks')
		require_child('/opt/ios/swift-foreign-offset-checks')
		require_child('/opt/ios/swift-foreign-subscript-checks')
		require_child('/opt/ios/swift-utf16-offset-checks')
		require_child('/opt/ios/swift-sequence-checks')
		require_child('/opt/ios/swift-array-sequence-checks')
		require_child('/opt/ios/swift-collection-checks')
		require_child('/opt/ios/swift-set-checks')
		require_child('/opt/ios/swift-metadata-checks')
		require_child('/opt/ios/swift-protocol-checks')
		require_child('/opt/ios/swift-hash-checks')
		require_child('/opt/ios/swift-hasher-checks')
		require_child('/opt/ios/swift-raw-representable-checks')
		require_child('/opt/ios/swift-array-checks')
		require_child('/opt/ios/swift-integer-checks')
		require_child('/opt/ios/swift-integer-hash-checks')
		require_child('/opt/ios/swift-fatal-checks')
		require_child('/opt/ios/swift-interpolation-checks')
		require_child('/opt/ios/swift-array-storage-checks')
		require_child('/opt/ios/swift-vararg-checks')
		require_child('/opt/ios/swift-void-checks')
		require_child('/opt/ios/swift-version-checks')
		require_child('/opt/ios/swift-initializer-checks')
		require_child('/opt/ios/swift-set-algebra-checks')
		require_child('/opt/ios/swift-raw-copy-checks')
		require_child('/opt/ios/swift-pointer-alloc-checks')
		require_child('/opt/ios/swift-pointer-deinit-checks')
		require_child('/opt/ios/swift-raw-alloc-checks')
		require_child('/opt/ios/swift-dispatch-async-checks')
		require_child('/opt/ios/swift-dispatch-main-checks')
		require_child('/opt/ios/swift-dispatch-scheduler-checks')
		require_child('/opt/ios/swift-dispatch-qos-checks')
		require_child('/opt/ios/swift-dispatch-algebra-checks')
		require_child('/opt/ios/swift-dispatch-flags-checks')
		require_child('/opt/ios/swift-stack-checks')
		require_child('/opt/ios/swift-heap-checks')
		require_child('/opt/ios/swift-array-unbridge-checks')
		require_child('/opt/ios/swift-string-replace-checks')
		require_child('/opt/ios/swift-dictionary-bridge-checks')
		require_child('/opt/ios/swift-calendar-case-checks')
		require_child('/opt/ios/swift-locale-checks')
		require_child('/opt/ios/swift-date-checks')
		require_child('/opt/ios/swift-data-write-checks')
		require_child('/opt/ios/swift-data-unbridge-checks')
		require_child('/opt/ios/swift-data-base64-checks')
		require_child('/opt/ios/swift-data-bridge-checks')
		require_child('/opt/ios/swift-data-checks')
		require_child('/opt/ios/swift-url-metadata-checks')
		require_child('/opt/ios/swift-url-path-checks')
		require_child('/opt/ios/swift-url-bridge-checks')
		require_child('/opt/ios/swift-error-bridge-checks')
		require_child('/opt/ios/swift-error-checks')
		require_child('/opt/ios/swift-error-value-checks')
		require_child('/opt/ios/swift-dynamic-cast-checks')
		require_child('/opt/ios/swift-objc-cast-checks')
		require_child('/opt/ios/swift-foreign-metadata-checks')
		require_child('/opt/ios/swift-object-type-checks')
		require_child('/opt/ios/swift-mangled-state-checks')
		require_child('/opt/ios/swift-mangled-checks')
		require_child('/opt/ios/swift-witness-checks')
		require_child('/opt/ios/swift-once-checks')
		require_child('/opt/ios/swift-set-bridge-checks')
		require_child('/opt/ios/swift-logger-checks')
		require_child('/opt/ios/swift-main-actor-witness-checks')
		require_child('/opt/ios/swift-main-actor-checks')
		require_child('/opt/ios/swift-nsobject-hashable-checks')
		require_child('/opt/ios/swift-objc-bool-metadata-checks')
		require_child('/opt/ios/swift-objc-bool-checks')
		require_child('/opt/ios/swift-actor-executor-checks')
		require_child('/opt/ios/swift-task-priority-checks')
		require_child('/opt/ios/swift-task-alloc-checks')
		require_child('/opt/ios/swift-task-create-checks')
		require_child('/opt/ios/swift-task-switch-checks')
		require_child('/opt/ios/swift-json-encoder-initializer-checks')
		require_child('/opt/ios/swift-json-encoder-dispatch-checks')
		require_child('/opt/ios/swift-json-encoder-date-dispatch-checks')
		require_child('/opt/ios/swift-json-date-strategy-checks')
		require_child('/opt/ios/swift-json-encoder-date-case-checks')
		require_child('/opt/ios/swift-json-decoder-initializer-checks')
		require_child('/opt/ios/swift-json-decoder-dispatch-checks')
		require_child('/opt/ios/swift-cocoa-error-protocol-checks')
		require_child('/opt/ios/swift-cocoa-error-code-checks')
		require_child('/opt/ios/swift-nslog-checks')
		require_child('/opt/ios/swift-string-unbridge-checks')
		require_child('/opt/ios/swift-cocoa-match-checks')
		require_child('/opt/ios/swift-localized-error-checks')
		require_child('/opt/ios/swift-error-description-checks')
		if os.is_dir('/opt/ios/lookup-native') { os.setenv('VINIX_IOS_LOOKUP_NATIVE', '/opt/ios/lookup-native', true) }
		require_child('/opt/ios/module-lookup-checks')
		require_child('/opt/ios/regression')
	} else if mode == 'objc' {
		os.setenv('VINIX_IOS_CONSTANT_DICT_IMAGE', '/opt/ios/constant-dictionary-image', true)
		for name in ['objc-constant-dictionary', 'layout-constraint', 'json-serialization', 'condition', 'cookie', 'webkit-configuration', 'user-script', 'webview', 'request', 'value', 'response', 'alert', 'set', 'thread', 'auth-session', 'image-view', 'keyboard', 'nsuuid', 'filemanager', 'home-directory', 'temp-directory', 'url-error', 'session-constants', 'foundation-keys', 'audio-services', 'avfoundation-constants', 'corevideo', 'pixel-allocation', 'metal-cache', 'media-format', 'block-buffer', 'sample-buffer', 'cm-time', 'h264-format', 'hevc-format', 'cg-font', 'reachability', 'devicecheck', 'network-path', 'corehaptics-constants', 'media-time', 'video-decode', 'storefront', 'storefront-current', 'storefront-metadata', 'refund', 'storekit-constants', 'zlib-checksum', 'zlib-compress', 'zlib-bound', 'resolver-query', 'pbkdf', 'ndr-record', 'immediate-exit', 'crt-environ', 'executable-path', 'dispatch-timer-type', 'dyld-images', 'dyld-callbacks', 'tlv-atexit', 'inverse-hyperbolic', 'arc4random', 'asl', 'backtrace', 'dispatch-data', 'dispatch-specific', 'dispatch-group', 'dispatch-source', 'dispatch-semaphore', 'division', 'mach-exception', 'flock', 'progname', 'host-page-size', 'host-statistics', 'logb', 'memory-entry', 'mach-message', 'mach-port-set', 'mach-notification', 'madvise', 'malloc-zone', 'mkstemp', 'nextafter', 'unfair-lock', 'pause', 'proc-rusage', 'raise', 'setrlimit', 'sigaltstack', 'swscanf', 'task-exception-ports', 'task-info', 'task-swap-exception-ports', 'task-threads', 'thread-exception-ports', 'thread-state', 'thread-resume', 'thread-suspend', 'thread-swap-exception-ports', 'uname', 'vm-read-overwrite', 'vm-region-64', 'cf-locale-current', 'cf-preferred-languages', 'cf-locale-value', 'cf-preferences-sync', 'cf-preferences-value', 'cf-preferences-set', 'cf-run-loop-main', 'cf-string-compare', 'cf-uuid-create', 'cf-uuid-string', 'cf-uuid-bytes', 'cf-uuid-text', 'cf-uuid-read', 'ns-calendar-iso8601', 'ns-internal-exception', 'ns-invalid-argument', 'ns-locale-country', 'ns-locale-currency', 'ns-locale-currency-symbol', 'ns-url-creation-date', 'ns-url-file-size', 'ns-url-backup-exclusion', 'ns-url-regular-file', 'ns-url-important-capacity', 'ns-url-available-capacity', 'ns-url-total-capacity', 'ns-exception-type', 'ns-empty-array', 'swiftui-vstack', 'swiftui-tree', 'swiftui-zstack', 'swiftui-opacity', 'nslogv', 'protocol-lookup', 'uncaught-handler', 'protocol-name', 'autopool', 'processinfo', 'date', 'inputstream', 'connection', 'type-encoding', 'oslog', 'secure-memory', 'cf-dictionary', 'objc-storage', 'objc-associated', 'objc-property', 'objc-sync'] {
			require_child('/opt/ios/' + name + '-checks')
		}
		println('VINIX iOS OBJC: PASS')
		C.fflush(unsafe { nil })
	} else if mode == 'swift' {
		if os.is_dir('/opt/ios/lookup-native') { os.setenv('VINIX_IOS_LOOKUP_NATIVE', '/opt/ios/lookup-native', true) }
		require_child('/opt/ios/module-lookup-checks')
		for name in ['unknown-value', 'string', 'empty-string', 'describing', 'cstring', 'empty-array', 'any', 'byte-metadata', 'raw-equality', 'array-class', 'shared-utf8', 'string-guts', 'foreign-copy', 'foreign-count', 'foreign-index', 'foreign-offset', 'foreign-subscript', 'utf16-offset', 'sequence', 'array-sequence', 'collection', 'set', 'metadata', 'protocol', 'hash', 'hasher', 'raw-representable',
			'array', 'integer', 'integer-hash', 'fatal', 'interpolation', 'array-storage', 'vararg', 'void', 'version', 'initializer', 'set-algebra', 'raw-copy', 'pointer-alloc', 'pointer-deinit', 'raw-alloc', 'dispatch-async', 'dispatch-main', 'dispatch-scheduler', 'dispatch-qos', 'dispatch-algebra', 'dispatch-flags', 'stack', 'heap', 'calendar-case', 'locale', 'date', 'data-write', 'data-unbridge', 'data-base64', 'data-bridge', 'data', 'url-metadata', 'url-path', 'url-bridge', 'error-bridge', 'error', 'error-value', 'dynamic-cast', 'objc-cast', 'foreign-metadata', 'object-type', 'mangled-state', 'mangled', 'witness', 'once', 'set-bridge', 'logger', 'main-actor-witness', 'main-actor', 'nsobject-hashable', 'objc-bool-metadata', 'objc-bool', 'actor-executor', 'task-priority', 'task-alloc', 'task-create', 'task-switch', 'nslog', 'string-unbridge', 'error-description', 'cocoa-error-code', 'cocoa-error-protocol', 'json-decoder-dispatch', 'json-decoder-initializer', 'json-encoder-date-case', 'json-date-strategy', 'json-encoder-date-dispatch', 'json-encoder-dispatch', 'json-encoder-initializer', 'localized-error'] {
			require_child('/opt/ios/swift-' + name + '-checks')
		}
		require_child('/opt/ios/dispatch-queue-class-checks')
		require_child('/opt/ios/swift-cocoa-match-checks')
		println('VINIX iOS SWIFT: PASS')
		C.fflush(unsafe { nil })
	} else {
		args := if mode == 'audit' {
			['--audit', '/opt/ios/FortniteClient-IOS-Shipping']
		} else {
			['/opt/ios/FortniteClient-IOS-Shipping']
		}
		status := run_child('/opt/ios/run-ios', args)
		println('FORTNITE PROBE: process exit status ${if status & 127 == 0 {
			status >> 8
		} else {
			128 + (status & 127)
		}}')
		println('FORTNITE PROBE COMPLETE')
		C.fflush(unsafe { nil })
	}
	for { C.pause() }
}
