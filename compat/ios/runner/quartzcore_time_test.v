// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import time

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type MTClock = fn () f64
type MTTicks = fn () u64
type MTScale = fn (voidptr) i32
struct MTApi {
	clock MTClock = ca_current_media_time
	ticks MTTicks = darwin_mach_absolute_time
	scale MTScale = mt_runtime_scale
}
fn mt_runtime_scale(result voidptr) i32 { return darwin_timebase_info(unsafe { &u32(result) }) }
fn mt_reader(api MTApi) f64 {
	mut scale := [2]u32{}
	assert api.scale(unsafe { voidptr(&scale[0]) }) == 0 && scale[0] > 0 && scale[1] > 0
	mut previous := f64(0)
	for _ in 0 .. 1024 {
		before := api.ticks()
		value := api.clock()
		after := api.ticks()
		lower := f64(before) * f64(scale[0]) / f64(scale[1]) / 1e9
		upper := f64(after) * f64(scale[0]) / f64(scale[1]) / 1e9
		assert math.is_finite(value) && value >= previous
		assert value >= lower - 1e-6 && value <= upper + 1e-6
		previous = value
	}
	return previous
}
fn mt_shared(api MTApi) {
	mut workers := []thread f64{}
	for _ in 0 .. 8 { workers << spawn mt_reader(api) }
	for worker in workers { assert worker.wait() > 0 }
	unsafe { workers.free() }
	before := api.clock()
	ticks := api.ticks()
	time.sleep(25 * time.millisecond)
	after := api.clock()
	mut scale := [2]u32{}
	assert api.scale(unsafe { voidptr(&scale[0]) }) == 0
	elapsed := f64(api.ticks() - ticks) * f64(scale[0]) / f64(scale[1]) / 1e9
	assert after - before >= 0.02 && after - before < 2
	assert math.abs((after - before) - elapsed) < 0.01
}
fn test_quartzcore_media_time() {
	$if macos {
		handle := C.dlopen(c'/System/Library/Frameworks/QuartzCore.framework/QuartzCore', 2)
		assert handle != unsafe { nil }
		clock := unsafe { MTClock(C.dlsym(handle, c'CACurrentMediaTime')) }
		api := MTApi{clock: clock,
			ticks: unsafe { MTTicks(C.dlsym(voidptr(-2), c'mach_absolute_time')) },
			scale: unsafe { MTScale(C.dlsym(voidptr(-2), c'mach_timebase_info')) }}
		mt_shared(api)
		for _ in 0 .. 1024 {
			before := clock()
			value := ca_current_media_time()
			after := clock()
			assert value >= before - 1e-6 && value <= after + 1e-6
		}
		assert C.dlclose(handle) == 0
		println('IOS-MEDIA-TIME-NATIVE: finite double seconds,8192 concurrent Mach/timebase brackets,sleep progression and shared absolute uptime origin')
	}
	entry := runtime_symbol('/System/Library/Frameworks/QuartzCore.framework/QuartzCore', '_CACurrentMediaTime') or { panic(err) }
	assert entry == u64(unsafe { voidptr(ca_current_media_time) })
	if _ := quartzcore_time_symbol('_CACurrentMediaTimeInvented') { assert false }
	for library in ['/System/Library/Frameworks/Foundation.framework/Foundation',
		'/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
		'/usr/lib/libSystem.B.dylib']! {
		if _ := runtime_symbol(library, '_CACurrentMediaTime') { assert false }
	}
	api := MTApi{clock: unsafe { MTClock(voidptr(entry)) }}
	mt_shared(api) // Callable before Objective-C or dispatch initialization.
	for _ in 0 .. 2 {
		before := api.clock()
		objc_start()
		mt_shared(api)
		// Exercise existing Mach-based dispatch deadlines against this origin.
		deadline := darwin_dispatch_time(0, 20_000_000)
		assert dispatch_remaining(deadline) > 0
		limit := darwin_mach_absolute_time() + 2_000_000_000
		for dispatch_remaining(deadline) > 0 {
			assert darwin_mach_absolute_time() < limit
			time.sleep(time.millisecond)
		}
		assert api.clock() >= before + 0.015
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert api.clock() >= before
		mt_shared(api) // No runtime-owned state or cache to retire.
	}
	println('IOS-MEDIA-TIME: exact framework/function ABI,double seconds,Mach clock origin,concurrent monotonic calls,elapsed sleep,dispatch deadlines and availability before/after two drained runtimes')
}
