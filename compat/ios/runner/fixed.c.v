// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <locale.h>
#include <wctype.h>
#include <wchar.h>
#include <setjmp.h>
fn C.setjmp(voidptr) i32
fn C.longjmp(voidptr, i32)
fn C._setjmp(voidptr) i32
fn C._longjmp(voidptr, i32)
fn C.towlower(u32) u32
fn C.towupper(u32) u32
fn C.wmemchr(&i32, i32, usize) &i32
fn C.wmemcmp(&i32, &i32, usize) i32
fn C.wmemcpy(&i32, &i32, usize) &i32
fn C.wmemmove(&i32, &i32, usize) &i32
fn C.wmemset(&i32, i32, usize) &i32
fn C.wcslen(&i32) usize

fn darwin_rune_lower(value i32) i32 { return i32(C.towlower(u32(value))) }
fn darwin_rune_upper(value i32) i32 { return i32(C.towupper(u32(value))) }
fn C.setlocale(i32, &char) &char

fn darwin_setlocale(category i32, locale &char) &char {
	$if linux {
		kind := match category {
			0 { i32(C.LC_ALL) }
			1 { i32(C.LC_COLLATE) }
			2 { i32(C.LC_CTYPE) }
			3 { i32(C.LC_MONETARY) }
			4 { i32(C.LC_NUMERIC) }
			5 { i32(C.LC_TIME) }
			6 { i32(C.LC_MESSAGES) }
			else { darwin_set_errno(22); return unsafe { nil } }
		}
		return C.setlocale(kind, locale)
	}
	return C.setlocale(category, locale)
}

fn C.floor(f64) f64

fn C.realloc(voidptr, usize) voidptr
fn C.strcpy(&char, &char) &char
fn C.strncpy(&char, &char, usize) &char
fn C.strdup(&char) &char
fn C.strchr(&char, i32) &char
fn C.strrchr(&char, i32) &char
fn C.strstr(&char, &char) &char
fn C.strpbrk(&char, &char) &char
fn C.strspn(&char, &char) usize
fn C.strcat(&char, &char) &char
fn C.strcoll(&char, &char) i32
fn C.strncmp(&char, &char, usize) i32
fn C.strncasecmp(&char, &char, usize) i32
fn C.strnlen(&char, usize) usize
fn C.strtol(&char, &&char, i32) i64
fn C.strtoll(&char, &&char, i32) i64
fn C.strtoul(&char, &&char, i32) u64
fn C.strtoull(&char, &&char, i32) u64
fn C.strtof(&char, &&char) f32
fn C.getpid() i32
fn C.getenv(&char) &char
fn C.setenv(&char, &char, i32) i32
fn C.unsetenv(&char) i32
fn C.abs(i32) i32
fn C.qsort(voidptr, usize, usize, voidptr)
fn C.rand() i32
fn C.srand(u32)
fn C.time(voidptr) i64
fn C.usleep(u32) i32
fn C.sleep(u32) u32
fn C.remove(&char) i32
fn C.rename(&char, &char) i32
fn C.unlink(&char) i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.gettimeofday(voidptr, voidptr) i32
fn C.ceil(f64) f64
fn C.ceilf(f32) f32
fn C.sqrt(f64) f64
fn C.sqrtf(f32) f32
fn C.round(f64) f64
fn C.roundf(f32) f32
fn C.trunc(f64) f64
fn C.truncf(f32) f32
fn C.log2(f64) f64
fn C.log2f(f32) f32
fn C.log10(f64) f64
fn C.log10f(f32) f32
fn C.exp2(f64) f64
fn C.exp2f(f32) f32
fn darwin_exp10(value f64) f64 { return C.pow(10, value) }
fn darwin_exp10_float(value f32) f32 { return C.powf(10, value) }
fn C.acosf(f32) f32
fn C.asinf(f32) f32
fn C.atanf(f32) f32
fn C.cosf(f32) f32
struct DarwinSinCosFloat {
	sine f32
	cosine f32
}
fn darwin_sincos_float(value f32) DarwinSinCosFloat { return DarwinSinCosFloat{C.sinf(value), C.cosf(value)} }
struct DarwinSinCosDouble {
	sine f64
	cosine f64
}
fn darwin_sincos_double(value f64) DarwinSinCosDouble { return DarwinSinCosDouble{C.sin(value), C.cos(value)} }
fn C.coshf(f32) f32
fn C.expf(f32) f32
fn C.fabsf(f32) f32
fn C.logf(f32) f32
fn C.sinf(f32) f32
fn C.sinhf(f32) f32
fn C.tanf(f32) f32
fn C.tanhf(f32) f32
fn C.pow(f64, f64) f64
fn C.powf(f32, f32) f32
fn C.fmod(f64, f64) f64
fn C.fmodf(f32, f32) f32
fn C.atan2(f64, f64) f64
fn C.atan2f(f32, f32) f32
fn C.ldexp(f64, i32) f64
fn C.ldexpf(f32, i32) f32
fn C.frexp(f64, &i32) f64
fn C.modf(f64, &f64) f64
fn C.modff(f32, &f32) f32
fn C.hypot(f64, f64) f64
fn C.cbrt(f64) f64
fn C.cbrtf(f32) f32
fn C.expm1(f64) f64
fn C.lrint(f64) i64
fn C.lrintf(f32) i64
fn C.llrint(f64) i64
fn C.llrintf(f32) i64
fn C.ios_signal(i32, voidptr) voidptr
fn darwin_signal(number i32, handler voidptr) voidptr {
    if number !in [i32(2), 4, 6, 8, 9, 11, 13, 15] { darwin_set_errno(22); return unsafe { voidptr(-1) } }
    return C.ios_signal(number, handler)
}
fn darwin_mach_absolute_time() u64 { return u64(time.sys_mono_now()) }
fn darwin_timebase_info(info &u32) i32 {
    if info == unsafe { nil } { return 4 }
    unsafe { info[0] = 1; info[1] = 1 }
    return 0
}
fn darwin_stack_fail() { panic('iOS: native stack protector detected corruption') }
fn darwin_memset_pattern(destination voidptr, pattern voidptr, length usize, width usize) {
	if length == 0 { return }
	mut bytes := [16]u8{}
	unsafe { C.memcpy(&bytes[0], pattern, width) }
	mut offset := usize(0)
	for offset < length {
		count := if width < length - offset { width } else { length - offset }
		unsafe { C.memcpy(voidptr(usize(destination) + offset), &bytes[0], count) }
		offset += count
	}
}
fn darwin_memset_pattern4(destination voidptr, pattern voidptr, length usize) { darwin_memset_pattern(destination, pattern, length, 4) }
fn darwin_memset_pattern8(destination voidptr, pattern voidptr, length usize) { darwin_memset_pattern(destination, pattern, length, 8) }
fn darwin_memset_pattern16(destination voidptr, pattern voidptr, length usize) { darwin_memset_pattern(destination, pattern, length, 16) }
fn fixed_symbol(symbol string) ?u64 {
    return match symbol {
		// wchar_t is signed 32-bit in both Darwin ARM64 and the native libc.
		'_wmemchr' { u64(unsafe { voidptr(C.wmemchr) }) }
		'_wmemcmp' { u64(unsafe { voidptr(C.wmemcmp) }) }
		'_wmemcpy' { u64(unsafe { voidptr(C.wmemcpy) }) }
		'_wmemmove' { u64(unsafe { voidptr(C.wmemmove) }) }
		'_wmemset' { u64(unsafe { voidptr(C.wmemset) }) }
		'_wcslen' { u64(unsafe { voidptr(C.wcslen) }) }
		'_memset_pattern4' { u64(unsafe { voidptr(darwin_memset_pattern4) }) }
		'_memset_pattern8' { u64(unsafe { voidptr(darwin_memset_pattern8) }) }
		'_memset_pattern16' { u64(unsafe { voidptr(darwin_memset_pattern16) }) }
		// The ARM64 native routines touch only the first 176 bytes of their
		// opaque buffer, inside Darwin's 192-byte jmp_buf. Resolve their entry
		// points directly: a V wrapper would save a frame that has returned.
		'_setjmp' { u64(unsafe { voidptr(C.setjmp) }) }
		'_longjmp' { u64(unsafe { voidptr(C.longjmp) }) }
		'__setjmp' { u64(unsafe { voidptr(C._setjmp) }) }
		'__longjmp' { u64(unsafe { voidptr(C._longjmp) }) }
		'___exp10' { u64(unsafe { voidptr(darwin_exp10) }) }
		'___exp10f' { u64(unsafe { voidptr(darwin_exp10_float) }) }
		'___sincosf_stret' { u64(unsafe { voidptr(darwin_sincos_float) }) }
		'___sincos_stret' { u64(unsafe { voidptr(darwin_sincos_double) }) }
		'_ldexp' { u64(unsafe { voidptr(C.ldexp) }) }
		'_ldexpf' { u64(unsafe { voidptr(C.ldexpf) }) }
		'_frexp' { u64(unsafe { voidptr(C.frexp) }) }
		'_modf' { u64(unsafe { voidptr(C.modf) }) }
		'_modff' { u64(unsafe { voidptr(C.modff) }) }
		'_hypot' { u64(unsafe { voidptr(C.hypot) }) }
		'_cbrt' { u64(unsafe { voidptr(C.cbrt) }) }
		'_cbrtf' { u64(unsafe { voidptr(C.cbrtf) }) }
		'_expm1' { u64(unsafe { voidptr(C.expm1) }) }
		'_lrint' { u64(unsafe { voidptr(C.lrint) }) }
		'_lrintf' { u64(unsafe { voidptr(C.lrintf) }) }
		'_llrint' { u64(unsafe { voidptr(C.llrint) }) }
		'_llrintf' { u64(unsafe { voidptr(C.llrintf) }) }
		'_setlocale' { u64(unsafe { voidptr(darwin_setlocale) }) }
        '_realloc' { u64(unsafe { voidptr(C.realloc) }) }
        '_strcpy' { u64(unsafe { voidptr(C.strcpy) }) }
        '_strncpy' { u64(unsafe { voidptr(C.strncpy) }) }
        '_strdup' { u64(unsafe { voidptr(C.strdup) }) }
        '_strchr' { u64(unsafe { voidptr(C.strchr) }) }
        '_strrchr' { u64(unsafe { voidptr(C.strrchr) }) }
        '_strstr' { u64(unsafe { voidptr(C.strstr) }) }
        '_strpbrk' { u64(unsafe { voidptr(C.strpbrk) }) }
        '_strspn' { u64(unsafe { voidptr(C.strspn) }) }
        '_strcat' { u64(unsafe { voidptr(C.strcat) }) }
        '_strcoll' { u64(unsafe { voidptr(C.strcoll) }) }
        '_strncmp' { u64(unsafe { voidptr(C.strncmp) }) }
        '_strncasecmp' { u64(unsafe { voidptr(C.strncasecmp) }) }
        '_strnlen' { u64(unsafe { voidptr(C.strnlen) }) }
        '_strtol' { u64(unsafe { voidptr(C.strtol) }) }
        '_strtoll' { u64(unsafe { voidptr(C.strtoll) }) }
        '_strtoul' { u64(unsafe { voidptr(C.strtoul) }) }
        '_strtoull' { u64(unsafe { voidptr(C.strtoull) }) }
        '_strtof' { u64(unsafe { voidptr(C.strtof) }) }
        '_getpid' { u64(unsafe { voidptr(C.getpid) }) }
        '_getenv' { u64(unsafe { voidptr(C.getenv) }) }
        '_setenv' { u64(unsafe { voidptr(C.setenv) }) }
        '_unsetenv' { u64(unsafe { voidptr(C.unsetenv) }) }
        '_abs' { u64(unsafe { voidptr(C.abs) }) }
        '_qsort' { u64(unsafe { voidptr(C.qsort) }) }
        '_rand' { u64(unsafe { voidptr(C.rand) }) }
        '_srand' { u64(unsafe { voidptr(C.srand) }) }
        '_time' { u64(unsafe { voidptr(C.time) }) }
        '_usleep' { u64(unsafe { voidptr(C.usleep) }) }
        '_sleep' { u64(unsafe { voidptr(C.sleep) }) }
        '_remove' { u64(unsafe { voidptr(C.remove) }) }
        '_rename' { u64(unsafe { voidptr(C.rename) }) }
        '_unlink' { u64(unsafe { voidptr(C.unlink) }) }
        '_getuid' { u64(unsafe { voidptr(C.getuid) }) }
        '_geteuid' { u64(unsafe { voidptr(C.geteuid) }) }
        '_gettimeofday' { u64(unsafe { voidptr(C.gettimeofday) }) }
        '_ceil' { u64(unsafe { voidptr(C.ceil) }) }
        '_ceilf' { u64(unsafe { voidptr(C.ceilf) }) }
        '_sqrt' { u64(unsafe { voidptr(C.sqrt) }) }
        '_sqrtf' { u64(unsafe { voidptr(C.sqrtf) }) }
        '_round' { u64(unsafe { voidptr(C.round) }) }
        '_roundf' { u64(unsafe { voidptr(C.roundf) }) }
        '_trunc' { u64(unsafe { voidptr(C.trunc) }) }
        '_truncf' { u64(unsafe { voidptr(C.truncf) }) }
        '_log2' { u64(unsafe { voidptr(C.log2) }) }
        '_log2f' { u64(unsafe { voidptr(C.log2f) }) }
        '_log10' { u64(unsafe { voidptr(C.log10) }) }
        '_log10f' { u64(unsafe { voidptr(C.log10f) }) }
        '_exp2' { u64(unsafe { voidptr(C.exp2) }) }
        '_exp2f' { u64(unsafe { voidptr(C.exp2f) }) }
        '_acosf' { u64(unsafe { voidptr(C.acosf) }) }
        '_asinf' { u64(unsafe { voidptr(C.asinf) }) }
        '_atanf' { u64(unsafe { voidptr(C.atanf) }) }
        '_cosf' { u64(unsafe { voidptr(C.cosf) }) }
        '_coshf' { u64(unsafe { voidptr(C.coshf) }) }
        '_expf' { u64(unsafe { voidptr(C.expf) }) }
        '_fabsf' { u64(unsafe { voidptr(C.fabsf) }) }
        '_logf' { u64(unsafe { voidptr(C.logf) }) }
        '_sinf' { u64(unsafe { voidptr(C.sinf) }) }
        '_sinhf' { u64(unsafe { voidptr(C.sinhf) }) }
        '_tanf' { u64(unsafe { voidptr(C.tanf) }) }
        '_tanhf' { u64(unsafe { voidptr(C.tanhf) }) }
        '_pow' { u64(unsafe { voidptr(C.pow) }) }
        '_powf' { u64(unsafe { voidptr(C.powf) }) }
        '_fmod' { u64(unsafe { voidptr(C.fmod) }) }
        '_fmodf' { u64(unsafe { voidptr(C.fmodf) }) }
        '_atan2' { u64(unsafe { voidptr(C.atan2) }) }
        '_atan2f' { u64(unsafe { voidptr(C.atan2f) }) }
        '_calloc' { u64(unsafe { voidptr(C.calloc) }) }
        '_floor' { u64(unsafe { voidptr(C.floor) }) }
        '_signal' { u64(unsafe { voidptr(darwin_signal) }) }
        '_mach_absolute_time' { u64(unsafe { voidptr(darwin_mach_absolute_time) }) }
        '_mach_timebase_info' { u64(unsafe { voidptr(darwin_timebase_info) }) }
        '___memcpy_chk' { u64(unsafe { voidptr(darwin_memcpy_checked) }) }
        '___memmove_chk' { u64(unsafe { voidptr(darwin_memmove_checked) }) }
        '___memset_chk' { u64(unsafe { voidptr(darwin_memset_checked) }) }
        '___strcat_chk' { u64(unsafe { voidptr(darwin_strcat_checked) }) }
        '___strncpy_chk' { u64(unsafe { voidptr(darwin_strncpy_checked) }) }
        '___darwin_check_fd_set_overflow' { u64(unsafe { voidptr(darwin_check_fd_set_overflow) }) }
        '___stack_chk_fail' { u64(unsafe { voidptr(darwin_stack_fail) }) }
        else { return none }
    }
}
