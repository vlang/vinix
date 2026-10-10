// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.CFGetTypeID(voidptr) u64
fn C.CFStringGetTypeID() u64
fn C.CFStringGetCString(voidptr, &char, i64, u32) bool

struct SessionConstantTest {
	name string
	value string
}

const session_constant_tests = [
	SessionConstantTest{'AVAudioSessionCategoryPlayAndRecord', 'AVAudioSessionCategoryPlayAndRecord'},
	SessionConstantTest{'AVAudioSessionCategoryRecord', 'AVAudioSessionCategoryRecord'},
	SessionConstantTest{'AVAudioSessionInterruptionOptionKey', 'AVAudioSessionInterruptionOptionKey'},
	SessionConstantTest{'AVAudioSessionInterruptionReasonKey', 'AVAudioSessionInterruptionReasonKey'},
	SessionConstantTest{'AVAudioSessionModeDefault', 'AVAudioSessionModeDefault'},
	SessionConstantTest{'AVAudioSessionModeVoiceChat', 'AVAudioSessionModeVoiceChat'},
	SessionConstantTest{'AVAudioSessionPortBuiltInReceiver', 'Receiver'},
	SessionConstantTest{'AVAudioSessionPortBuiltInSpeaker', 'Speaker'},
	SessionConstantTest{'AVAudioSessionPortHeadphones', 'Headphones'},
	SessionConstantTest{'AVAudioSessionRouteChangeNotification', 'AVAudioSessionRouteChangeNotification'},
	SessionConstantTest{'AVAudioSessionRouteChangeReasonKey', 'AVAudioSessionRouteChangeReasonKey'},
	SessionConstantTest{'AVAudioSessionSilenceSecondaryAudioHintNotification', 'AVAudioSessionSilenceSecondaryAudioHintNotification'},
	SessionConstantTest{'AVAudioSessionSilenceSecondaryAudioHintTypeKey', 'AVAudioSessionSilenceSecondaryAudioHintTypeKey'},
]!

fn audio_session_test_native() {
	$if macos {
		library := C.dlopen('/System/Library/Frameworks/AVFAudio.framework/AVFAudio'.str, C.RTLD_NOW | C.RTLD_LOCAL)
		assert library != unsafe { nil }
		defer { C.dlclose(library) }
		for sample in session_constant_tests {
			cell := C.dlsym(library, sample.name.str)
			assert cell != unsafe { nil }
			object := unsafe { *(&voidptr(cell)) }
			assert C.CFGetTypeID(object) == C.CFStringGetTypeID()
			mut buffer := [256]u8{init: 0xaa}
			assert C.CFStringGetCString(object, unsafe { &char(&buffer[8]) }, 240, 0x08000100)
			assert unsafe { tos_clone(&buffer[8]) } == sample.value
			for i in 0 .. 8 { assert buffer[i] == 0xaa && buffer[248 + i] == 0xaa }
			println('IOS-AUDIO-NATIVE: ${sample.name}=${sample.value}')
		}
	}
}

fn audio_session_test_worker() [13]u64 {
	mut cells := [13]u64{}
	for _ in 0 .. 50 {
		for i, sample in session_constant_tests {
			symbol := '_' + sample.name
			cell := runtime_symbol('/System/Library/Frameworks/AVFAudio.framework/AVFAudio', symbol) or { panic(err) }
			assert cell != 0 && cell & 7 == 0
			object := read64(cell) // A data import addresses an NSString pointer cell.
			assert cf_type_id(object) == cf_string_id()
			assert string_text(object) == sample.value
			mut buffer := [256]u8{init: 0xaa}
			assert cf_string_get_cstring(object, u64(unsafe { &buffer[8] }), 240, 0x08000100)
			assert unsafe { tos_clone(&buffer[8]) } == sample.value
			for j in 0 .. 8 { assert buffer[j] == 0xaa && buffer[248 + j] == 0xaa }
			alias := runtime_symbol('/System/Library/Frameworks/AVFoundation.framework/AVFoundation', symbol) or { panic(err) }
			assert alias == cell
			if cells[i] == 0 { cells[i] = cell } else { assert cells[i] == cell }
		}
	}
	return cells
}

fn test_audio_session_constants() {
	audio_session_test_native()
	for _ in 0 .. 2 {
		objc_start()
		assert ios_runtime.live == 0
		mut workers := []thread [13]u64{}
		for _ in 0 .. 8 { workers << spawn audio_session_test_worker() }
		results := workers.wait()
		for cells in results { assert cells == results[0] }
		assert ios_runtime.live == 13 && ios_runtime.framework_objects.len == 13
		assert ios_runtime.framework_data.len == 13
		pool := objc_pool_push()
		for cell in results[0] { objc_autorelease(objc_retain(read64(cell))) }
		objc_pool_pop(pool)
		for i, cell in results[0] { assert string_text(read64(cell)) == session_constant_tests[i].value }
		assert ios_runtime.live == 13
		assert framework_constant('_AVAudioSessionMissingConstant') == none
		objc_stop()
		assert ios_runtime.live == 0
	}
	println('IOS-AUDIO-SESSION: thirteen native strings, pointer cells, framework aliases, guarded UTF-8 conversion, eight concurrent first lookups, cache ownership and two clean teardowns')
}
