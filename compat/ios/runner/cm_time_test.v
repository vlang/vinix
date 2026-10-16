// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

struct CTAPI { native bool handle u64 }
struct CTCase { seconds f64 scale i32 expected CMTime }
type CTMake = fn (i64, i32) CMTime
type CTEpoch = fn (i64, i32, i64) CMTime
type CTSeconds = fn (f64, i32) CMTime
type CTGet = fn (CMTime) f64
type CTCreateSample = fn (u64,u64,u8,u64,u64,u64,i64,i64,&CMSampleTiming,i64,&u64,&u64) i32
type CTGetSampleTime = fn (u64) CMTime
type CTRelease = fn (u64)

fn ct_symbol(api CTAPI, name string) u64 {
	if api.native {
		address := u64(C.dlsym(unsafe { voidptr(api.handle) }, unsafe { &char(name.str + 1) }))
		assert address != 0, name
		return address
	}
	return runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia', name) or { panic(err) }
}
fn ct_equal(a f64, b f64) bool {
	return if math.is_nan(a) { math.is_nan(b) } else { math.f64_bits(a) == math.f64_bits(b) }
}
fn ct_cases(api CTAPI) {
	assert sizeof(CMTime) == 24
	time_make := unsafe { CTMake(voidptr(ct_symbol(api, '_CMTimeMake'))) }
	epoch_make := unsafe { CTEpoch(voidptr(ct_symbol(api, '_CMTimeMakeWithEpoch'))) }
	seconds_make := unsafe { CTSeconds(voidptr(ct_symbol(api, '_CMTimeMakeWithSeconds'))) }
	seconds_get := unsafe { CTGet(voidptr(ct_symbol(api, '_CMTimeGetSeconds'))) }
	for scale in [i32(-2147483647-1), -1, 0, 1, 30, 2147483647]! {
		for value in [i64(-9223372036854775807-1), -1, 0, 1, 9223372036854775807]! {
			assert time_make(value, scale) == if scale <= 0 { CMTime{} } else { CMTime{value,scale,1,0} }
			for epoch in [i64(-9223372036854775807-1), -9, 0, 19, 9223372036854775807]! {
				time := epoch_make(value, scale, epoch)
				assert time == if scale <= 0 { CMTime{} } else { CMTime{value,scale,1,epoch} }
				assert ct_equal(seconds_get(time), if scale <= 0 { math.nan() } else { f64(value)/f64(scale) })
			}
		}
	}
	for row in [CTCase{0,30,CMTime{0,30,1,0}}, CTCase{math.f64_from_bits(0x8000000000000000),30,CMTime{0,30,1,0}},
		CTCase{0.5,1,CMTime{0,1,3,0}}, CTCase{-0.5,1,CMTime{0,1,3,0}},
		CTCase{1.5,1,CMTime{1,1,3,0}}, CTCase{-1.5,1,CMTime{-1,1,3,0}},
		CTCase{2.5,1,CMTime{2,1,3,0}}, CTCase{-2.5,1,CMTime{-2,1,3,0}},
		CTCase{0.25,30,CMTime{7,30,3,0}}, CTCase{-0.25,30,CMTime{-7,30,3,0}},
		CTCase{0.1,30,CMTime{3,30,1,0}}, CTCase{-0.1,30,CMTime{-3,30,1,0}},
		CTCase{1.0/3.0,30,CMTime{10,30,1,0}}, CTCase{1.0/3.0,1000000000,CMTime{333333333,1000000000,3,0}},
		CTCase{0.5,2147483647,CMTime{1073741823,2147483647,3,0}},
		CTCase{math.f64_from_bits(1),30,CMTime{0,30,3,0}}, CTCase{math.f64_from_bits(0x8000000000000001),30,CMTime{0,30,3,0}},
		CTCase{1e10,1000000000,CMTime{5000000000000000000,500000000,1,0}},
		CTCase{-1e15,2147483647,CMTime{-8191000000000000000,8191,1,0}},
		CTCase{math.f64_from_bits(0x43dfffffffffffff),600,CMTime{9223372036854774784,1,1,0}},
		CTCase{math.f64_from_bits(0x43e0000000000000),3,CMTime{9223372036854775807,1,1,0}},
		CTCase{math.f64_from_bits(0xc3e0000000000000),3,CMTime{-9223372036854775807,1,1,0}},
		CTCase{math.f64_from_bits(0x43e0000000000001),3,CMTime{0,0,5,0}},
		CTCase{math.f64_from_bits(0xc3e0000000000001),3,CMTime{0,0,9,0}},
		CTCase{1e308,600,CMTime{0,0,5,0}}, CTCase{-1e308,600,CMTime{0,0,9,0}},
		CTCase{math.inf(1),1,CMTime{0,0,5,0}}, CTCase{math.inf(-1),1,CMTime{0,0,9,0}},
		CTCase{math.nan(),600,CMTime{0,600,3,0}}, CTCase{math.nan(),0,CMTime{}},
		CTCase{math.inf(1),-1,CMTime{}}, CTCase{1,-2147483647-1,CMTime{}}]! {
		assert seconds_make(row.seconds, row.scale) == row.expected, '${row}'
	}
	for flags in [u32(0),2,4,8,16,17,21,25,29,0xfffffffe,0xffffffff]! {
		assert math.is_nan(seconds_get(CMTime{99,30,flags,19}))
	}
	for flags in [u32(5),7,13,15,0x80000005]! {
		assert seconds_get(CMTime{-99,-30,flags,-19}) == math.inf(1)
	}
	for flags in [u32(9),11,0x80000009]! {
		assert seconds_get(CMTime{99,-30,flags,19}) == math.inf(-1)
	}
	assert ct_equal(seconds_get(CMTime{0,-30,1,0}), math.f64_from_bits(0x8000000000000000))
	assert math.is_nan(seconds_get(CMTime{0,0,1,0}))
	assert seconds_get(CMTime{1,0,1,0}) == math.inf(1)
	assert seconds_get(CMTime{-1,0,1,0}) == math.inf(-1)
	assert seconds_get(CMTime{75,-30,33,19}) == -2.5
	assert seconds_get(CMTime{-75,30,3,-19}) == -2.5
	// Runtime and native function pointers exercise aggregate ABI in both directions.
	mut timing := CMSampleTiming{time_make(1,30), seconds_make(2,30), CMTime{}}
	mut sample := u64(0)
	assert unsafe { CTCreateSample(voidptr(ct_symbol(api,'_CMSampleBufferCreate')))(0,0,1,0,0,0,3,1,&timing,0,nil,&sample) } == 0
	duration := unsafe { CTGetSampleTime(voidptr(ct_symbol(api,'_CMSampleBufferGetDuration')))(sample) }
	assert ct_equal(seconds_get(duration), 0.1)
	if api.native {
		$if macos {
			cf := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2)
			assert cf != unsafe { nil }
			unsafe { CTRelease(C.dlsym(cf,c'CFRelease'))(sample) }
		}
	} else { objc_release(sample) }
}

fn test_cm_time() {
	$if macos {
		api := CTAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreMedia.framework/CoreMedia',2))}
		assert api.handle != 0
		ct_cases(api)
		// Deterministic bit patterns cover fractions, subnormals, NaNs and overflow.
		seconds_make := unsafe { CTSeconds(voidptr(ct_symbol(api,'_CMTimeMakeWithSeconds'))) }
		seconds_get := unsafe { CTGet(voidptr(ct_symbol(api,'_CMTimeGetSeconds'))) }
		mut state := u64(0x4d595df4d0f33173)
		for i in 0..4096 {
			state = (state << 13) ^ state; state = (state >> 7) ^ state; state = (state << 17) ^ state
			seconds := math.f64_from_bits(state)
			scale := [i32(1),3,30,600,1000000000,2147483647]![i%6]
			assert seconds_make(seconds,scale) == cm_time_make_seconds(seconds,scale)
			time := CMTime{i64(state >> 1),i32(state>>32),u32(i%64),-19}
			assert ct_equal(seconds_get(time),cm_time_seconds(time))
		}
		println('IOS-CM-TIME-NATIVE: constructors,epochs,tick truncation,rounding flag,scale halving,symmetric saturation,NaN/infinity precedence,sample duration,4096 differential bit patterns')
	}
	for _ in 0..2 {
		objc_start(); ct_cases(CTAPI{})
		for name in ['_CMTimeAdd','_CMTimeSubtract','_CMTimeConvertScale']! {
			if _ := runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia',name) { assert false }
		}
		assert ios_runtime.live == ios_runtime.framework_objects.len
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-CM-TIME: 24-byte aggregate constructors and seconds conversion,native rounding and overflow,media sample composition,two drained runtimes;general time arithmetic remains unavailable')
}
