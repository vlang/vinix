// Independent ownership/failure fixture for the unchanged V sampler.
@[has_globals]
module samplerfixture

#include <fixture-native-abi.h>

@[typedef]
struct C.vsampler_native_va {}
fn C.assert(bool)
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.vsnprintf(&char, usize, &char, C.vsampler_native_va) i32
fn C.strstr(&char, &char) &char
fn C.alloc_kernel_bench() i32
fn C.kmod_alloc_start(voidptr, voidptr) i32
fn C.kmod_alloc_stop(voidptr, voidptr) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

__global (
	sampler_attempts usize
	sampler_frees usize
	sampler_live usize
	sampler_fail_at = usize(C.SIZE_MAX)
	sampler_poison_at = usize(C.SIZE_MAX)
	sampler_tick u64
	sampler_constant_clock i32
	sampler_output [16384]char
	sampler_output_size usize
)

@[export: 'vkb_test_alloc']
pub fn allocate(size usize) voidptr {
	unsafe {
		attempt := sampler_attempts
		sampler_attempts++
		if attempt == sampler_fail_at { return nil }
		pointer := &u8(C.calloc(1, size))
		C.assert(pointer != nil)
		sampler_live++
		if attempt == sampler_poison_at { pointer[size - 1] = 0x7e }
		return pointer
	}
}

@[export: 'vkb_test_free']
pub fn release(pointer voidptr) {
	C.assert(pointer != nil && sampler_live != 0)
	sampler_live--
	sampler_frees++
	C.free(pointer)
}

@[export: 'vkb_test_ticks']
pub fn ticks() u64 {
	if sampler_constant_clock == 0 { sampler_tick += 1000 }
	return sampler_tick
}

// Native assembly captures va_list; libc borrows it until this call returns.
@[export: 'vsampler_capture_log']
pub fn capture_log(format &char, native_va voidptr) i32 {
	unsafe {
		length := C.vsnprintf(&sampler_output[sampler_output_size], sizeof(sampler_output) - sampler_output_size, format, *(&C.vsampler_native_va(native_va)))
		C.assert(length > 0 && usize(length) < sizeof(sampler_output) - sampler_output_size)
		sampler_output_size += usize(length)
		return length
	}
}

fn reset() {
	C.assert(sampler_live == 0)
	sampler_attempts = 0
	sampler_frees = 0
	sampler_fail_at = usize(C.SIZE_MAX)
	sampler_poison_at = usize(C.SIZE_MAX)
	sampler_tick = 0
	sampler_constant_clock = 0
	sampler_output_size = 0
	sampler_output[0] = 0
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		reset()
		C.assert(C.alloc_kernel_bench() == 0 && sampler_live == 0)
		C.assert(sampler_attempts == 674496 && sampler_frees == sampler_attempts)
		C.assert(C.strstr(&sampler_output[0], c'KALLOC-DONE platform=vinix phases=3 checksum=27358432\n') != nil)
		C.assert(C.strstr(&sampler_output[0], c'phase=hot64 pairs=100000 samples=5 warmup_pairs=100000 median_ticks=1000 min_ticks=1000 max_ticks=1000 median_ticks_per_pair=0 checksum=25486688\n') != nil)
		C.assert(C.strstr(&sampler_output[0], c'phase=mixed256 pairs=12288 samples=5 warmup_pairs=12288 median_ticks=1000 min_ticks=1000 max_ticks=1000 median_ticks_per_pair=0 checksum=1855488\n') != nil)
		C.assert(C.strstr(&sampler_output[0], c'phase=big262144 pairs=128 samples=5 warmup_pairs=128 median_ticks=1000 min_ticks=1000 max_ticks=1000 median_ticks_per_pair=7 checksum=16256\n') != nil)
		failures := [usize(0), 600019, 673745]!
		for i in 0 .. 3 {
			reset()
			sampler_fail_at = failures[i]
			C.assert(C.alloc_kernel_bench() == 1 && sampler_live == 0 && sampler_frees + 1 == sampler_attempts)
			C.assert(C.strstr(&sampler_output[0], c'reason=allocation_failed') != nil)
			C.assert(C.strstr(&sampler_output[0], c'KALLOC-DONE') == nil)
		}
		poison := [usize(7), 600019, 673745]!
		for i in 0 .. 3 {
			reset()
			sampler_poison_at = poison[i]
			C.assert(C.alloc_kernel_bench() == 1 && sampler_live == 0 && sampler_frees == sampler_attempts)
			C.assert(C.strstr(&sampler_output[0], c'reason=nonzero_allocation') != nil)
			C.assert(C.strstr(&sampler_output[0], c'value=126\n') != nil)
		}
		reset()
		sampler_constant_clock = 1
		C.assert(C.alloc_kernel_bench() == 1 && sampler_live == 0 && sampler_frees == sampler_attempts)
		C.assert(C.strstr(&sampler_output[0], c'reason=nonmonotonic_tsc') != nil)
		reset()
		sampler_fail_at = 0
		C.assert(C.kmod_alloc_start(nil, nil) == 5 && sampler_live == 0)
		C.assert(C.kmod_alloc_stop(nil, nil) == 0)
		C.puts(c'Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed')
		$if sampler_guest ? {
			C.fflush(nil)
			for { C.pause() }
		}
		return 0
	}
}
