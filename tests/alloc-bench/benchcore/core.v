// SPDX-License-Identifier: GPL-2.0-or-later
// Portable allocation workload. Compile the generated artifact with real GCC
// for comparative timing; native volatile fields preserve every payload access.
@[has_globals]
module benchcore

#include <bench-native-abi.h>

@[typedef]
struct C.FILE {}
@[typedef]
struct C.alloc_bench_const_void {}
struct C.alloc_bench_byte { value u8 }
struct C.alloc_bench_word { value u64 }
struct C.alloc_bench_observed { value u64 }
struct C.alloc_bench_outcome {
	checksum u64
	expected u64
}
struct C.timespec {
	tv_sec i64
	tv_nsec i64
}
struct C.utsname {
	sysname [65]char
	release [65]char
	machine [65]char
}
@[c_extern]
__global C.stdout &C.FILE
@[c_extern]
__global C.stderr &C.FILE
__global alloc_bench_observed C.alloc_bench_observed
__global alloc_bench_workloads [6]Workload
__global alloc_bench_workloads_ready bool

fn C.VAB_ERRNO() &i32
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32
fn C.strerror(i32) &char
fn C.clock_gettime(i32, &C.timespec) i32
fn C.clock_getres(i32, &C.timespec) i32
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.qsort(voidptr, usize, usize, fn (&C.alloc_bench_const_void, &C.alloc_bench_const_void) i32)
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.strtoull(&char, &&char, i32) u64
fn C.putchar(i32) i32
fn C.uname(&C.utsname) i32
fn C.sysconf(i32) isize

struct Options {
mut:
	iterations u64 = 20000
	samples u32 = 7
	label &char = c'default'
}
struct Workload {
	name &char
	operation &char
	category &char
	divisor u32
	bytes usize
	batch usize
	touch_stride usize
	@[required]
	run fn (u64, &C.alloc_bench_outcome) i32
}

const alloc_bench_sizes = [usize(16), 32, 64, 96, 128, 256, 512, 1024, 2048, 4096, 8192, 16384]!

fn fail(action &char) i32 {
	unsafe { C.fprintf(C.stderr, c'ALLOC-ERROR action=%s errno=%d message=%s\n', action, *C.VAB_ERRNO(), C.strerror(*C.VAB_ERRNO())) }
	return -1
}

fn now_ns(value &C.alloc_bench_word) i32 {
	unsafe {
		mut time := C.timespec{}
		if C.clock_gettime(C.CLOCK_MONOTONIC, &time) != 0 { return fail(c'clock_gettime') }
		value.value = u64(time.tv_sec) * 1000000000 + u64(time.tv_nsec)
	}
	return 0
}

fn value_for(iteration u64, offset usize) u8 { return u8(iteration * 17 + u64(offset)) }

fn malloc_hot(iterations u64, out &C.alloc_bench_outcome) i32 {
	unsafe {
		for i := u64(0); i < iterations; i++ {
			allocation := C.malloc(64)
			if allocation == nil { return fail(c'malloc_hot_64') }
			payload := &C.alloc_bench_byte(allocation)
			first := value_for(i, 0)
			last := u8(first ^ 0x5a)
			payload[0].value = first
			payload[63].value = last
			out.checksum += u64(payload[0].value) + payload[63].value
			out.expected += u64(first) + last
			C.free(allocation)
		}
	}
	return 0
}

fn malloc_mixed(iterations u64, out &C.alloc_bench_outcome) i32 {
	unsafe {
		mut allocations := [64]voidptr{}
		mut live_sizes := [64]usize{}
		mut completed := u64(0)
		for completed < iterations {
			remaining := iterations - completed
			count := if remaining < 64 { usize(remaining) } else { usize(64) }
			for j := usize(0); j < count; j++ {
				i := completed + u64(j)
				size := alloc_bench_sizes[i % 12]
				allocations[j] = C.malloc(size)
				if allocations[j] == nil {
					mut k := j
					for k != 0 { k--; C.free(allocations[k]) }
					return fail(c'malloc_mixed_batch_64')
				}
				live_sizes[j] = size
				payload := &C.alloc_bench_byte(allocations[j])
				payload[0].value = value_for(i, 0)
				payload[size - 1].value = value_for(i, size - 1)
			}
			mut j := count
			for j != 0 {
				j--
				i := completed + u64(j)
				size := live_sizes[j]
				payload := &C.alloc_bench_byte(allocations[j])
				out.checksum += u64(payload[0].value) + payload[size - 1].value
				out.expected += u64(value_for(i, 0)) + value_for(i, size - 1)
				C.free(allocations[j])
			}
			completed += u64(count)
		}
	}
	return 0
}

fn touch_pages(allocation voidptr, iteration u64, out &C.alloc_bench_outcome) {
	unsafe {
		payload := &C.alloc_bench_byte(allocation)
		for offset := usize(0); offset < 262144; offset += 4096 {
			payload[offset].value = value_for(iteration, offset / 4096)
		}
		for offset := usize(0); offset < 262144; offset += 4096 {
			out.checksum += payload[offset].value
			out.expected += value_for(iteration, offset / 4096)
		}
	}
}

fn malloc_touch(iterations u64, out &C.alloc_bench_outcome) i32 {
	for i := u64(0); i < iterations; i++ {
		allocation := C.malloc(262144)
		if allocation == unsafe { nil } { return fail(c'malloc_touch_262144') }
		touch_pages(allocation, i, out)
		C.free(allocation)
	}
	return 0
}

fn mmap_no_touch(iterations u64, out &C.alloc_bench_outcome) i32 {
	for _ in 0 .. iterations {
		allocation := C.mmap(unsafe { nil }, 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if allocation == voidptr(C.MAP_FAILED) { return fail(c'mmap_anon_4096') }
		if C.munmap(allocation, 4096) != 0 { return fail(c'munmap_anon_4096') }
	}
	return 0
}

fn mmap_touch(iterations u64, out &C.alloc_bench_outcome) i32 {
	for i := u64(0); i < iterations; i++ {
		allocation := C.mmap(unsafe { nil }, 262144, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if allocation == voidptr(C.MAP_FAILED) { return fail(c'mmap_touch_262144') }
		touch_pages(allocation, i, out)
		if C.munmap(allocation, 262144) != 0 { return fail(c'munmap_touch_262144') }
	}
	return 0
}

fn pipe_create_close(iterations u64, out &C.alloc_bench_outcome) i32 {
	unsafe {
		for _ in 0 .. iterations {
			mut descriptors := [2]i32{}
			if C.pipe(&descriptors[0]) != 0 { return fail(c'pipe') }
			first_result := C.close(descriptors[0])
			first_errno := *C.VAB_ERRNO()
			second_result := C.close(descriptors[1])
			if first_result != 0 { errno_ptr := C.VAB_ERRNO(); *errno_ptr = first_errno; return fail(c'pipe_close_read') }
			if second_result != 0 { return fail(c'pipe_close_write') }
		}
	}
	return 0
}

// qsort requires the actual exported wrapper with native const-void formals.
fn C.alloc_bench_compare(&C.alloc_bench_const_void, &C.alloc_bench_const_void) i32
@[export: 'alloc_bench_compare']
pub fn compare_u64(left &C.alloc_bench_const_void, right &C.alloc_bench_const_void) i32 {
	unsafe {
		a := (&C.alloc_bench_word(left)).value
		b := (&C.alloc_bench_word(right)).value
		return i32(a > b) - i32(a < b)
	}
}

fn verify(workload &Workload, out &C.alloc_bench_outcome) i32 {
	unsafe {
		alloc_bench_observed.value ^= out.checksum
		if out.checksum != out.expected {
			C.fprintf(C.stderr, c'ALLOC-ERROR action=verify workload=%s checksum=%llu expected=%llu\n', workload.name, out.checksum, out.expected)
			return -1
		}
	}
	return 0
}

fn measure(workload &Workload, options &Options) i32 {
	unsafe {
		count := C.alloc_bench_word{value: (options.iterations + workload.divisor - 1) / workload.divisor}
		mut elapsed := [31]C.alloc_bench_word{}
		mut warmup := C.alloc_bench_outcome{}
		if workload.run(count.value, &warmup) != 0 || verify(workload, &warmup) != 0 { return -1 }
		for sample := u32(0); sample < options.samples; sample++ {
			mut out := C.alloc_bench_outcome{}
			mut start := C.alloc_bench_word{}
			mut end := C.alloc_bench_word{}
			if now_ns(&start) != 0 { return -1 }
			result := workload.run(count.value, &out)
			if now_ns(&end) != 0 || result != 0 || verify(workload, &out) != 0 { return -1 }
			if end.value <= start.value {
				C.fprintf(C.stderr, c'ALLOC-ERROR action=timer workload=%s start_ns=%llu end_ns=%llu\n', workload.name, start.value, end.value)
				return -1
			}
			elapsed[sample].value = end.value - start.value
			C.printf(c'ALLOC-SAMPLE label=%s workload=%s sample=%u pairs=%llu elapsed_ns=%llu ns_per_pair=%.3f checksum=%llu\n', options.label, workload.name, sample + u32(1), count.value, elapsed[sample].value, f64(elapsed[sample].value) / f64(count.value), out.checksum)
			C.fflush(C.stdout)
		}
		C.qsort(&elapsed[0], options.samples, sizeof(C.alloc_bench_word), C.alloc_bench_compare)
		middle := options.samples / 2
		mut median := f64(elapsed[middle].value)
		if options.samples % 2 == 0 { median = (f64(elapsed[middle - 1].value) + median) / 2.0 }
		C.printf(c'ALLOC-RESULT label=%s workload=%s category=%s operation=%s pairs=%llu samples=%u warmup_pairs=%llu bytes=%zu batch=%zu touch_stride=%zu median_ns_per_pair=%.3f min_ns_per_pair=%.3f max_ns_per_pair=%.3f\n', options.label, workload.name, workload.category, workload.operation, count.value, options.samples, count.value, workload.bytes, workload.batch, workload.touch_stride, median / f64(count.value), f64(elapsed[0].value) / f64(count.value), f64(elapsed[options.samples - 1].value) / f64(count.value))
		C.fflush(C.stdout)
	}
	return 0
}

fn usage(program &char) {
	C.printf(c'Usage: %s [--iterations N] [--samples N] [--quick] [--label NAME]\n  --iterations N  malloc pairs (default 20000, range 1..1000000000);\n                  large malloc, mmap and pipe pairs are ceil(N/20)\n  --samples N     measured samples (default 7, range 5..31)\n  --quick         set iterations=2000 and samples=5\n  --label NAME    letters, digits, underscores, dots or dashes\nOptions apply in order. Each workload also gets one full warmup.\nBuild: generate bench.c with compile-v-bench.py, then gcc -std=c11 -O2 -fno-builtin -Wall -Wextra -Werror -I . bench.c -o alloc-bench\n', program)
}

fn parse_number(text &char, minimum u64, maximum u64, value &u64) i32 {
	unsafe {
		if *text == 0 { return -1 }
		mut cursor := text
		for *cursor != 0 { if *cursor < `0` || *cursor > `9` { return -1 }; cursor++ }
		errno_ptr := C.VAB_ERRNO(); *errno_ptr = 0
		mut end := &char(nil)
		parsed := C.strtoull(text, &end, 10)
		if *C.VAB_ERRNO() != 0 || *end != 0 || parsed < minimum || parsed > maximum { return -1 }
		*value = parsed
	}
	return 0
}

fn valid_label(label &char) bool {
	unsafe {
		if *label == 0 || C.strlen(label) > 64 { return false }
		mut cursor := label
		for *cursor != 0 {
			c := *cursor
			if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == char(`_`) || c == char(`-`) || c == char(`.`)) { return false }
			cursor++
		}
	}
	return true
}

fn print_token(value &char) {
	unsafe {
		mut cursor := &u8(value)
		for *cursor != 0 { c := *cursor; C.putchar(if c > 32 && c < 127 && c != `=` { i32(c) } else { i32(`_`) }); cursor++ }
	}
}

fn print_metadata(options &Options) i32 {
	unsafe {
		mut identity := C.utsname{}
		mut resolution := C.timespec{}
		if C.uname(&identity) != 0 { return fail(c'uname') }
		if C.clock_getres(C.CLOCK_MONOTONIC, &resolution) != 0 { return fail(c'clock_getres') }
		page_size := C.sysconf(C._SC_PAGESIZE)
		if page_size <= 0 { return fail(c'sysconf_pagesize') }
		C.printf(c'ALLOC-META schema=1 label=%s platform=', options.label)
		print_token(&identity.sysname[0])
		C.printf(c' release='); print_token(&identity.release[0])
		C.printf(c' arch='); print_token(&identity.machine[0])
		if C.VAB_COMPILER_KNOWN != 0 {
			C.printf(c' compiler=%s compiler_major=%d compiler_minor=%d compiler_patch=%d', C.VAB_COMPILER, i32(C.VAB_COMPILER_MAJOR), i32(C.VAB_COMPILER_MINOR), i32(C.VAB_COMPILER_PATCH))
		} else { C.printf(c' compiler=unknown') }
		if C.VAB_VERSION_KNOWN != 0 { C.printf(c' compiler_version='); print_token(&char(C.VAB_VERSION)) }
		ns := C.alloc_bench_word{value: u64(resolution.tv_sec) * 1000000000 + u64(resolution.tv_nsec)}
		iterations := C.alloc_bench_word{value: options.iterations}
		C.printf(c' pointer_bits=%zu page_size=%ld clock=CLOCK_MONOTONIC clock_resolution_ns=%llu threads=1 iterations=%llu samples=%u touch_stride=%d large_bytes=%d mixed_sizes=16,32,64,96,128,256,512,1024,2048,4096,8192,16384\n', usize(sizeof(voidptr) * 8), page_size, ns.value, iterations.value, options.samples, i32(4096), i32(262144))
		C.fflush(C.stdout)
	}
	return 0
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		mut options := Options{}
		for i := i32(1); i < argc; i++ {
			if C.strcmp(argv[i], c'--help') == 0 { usage(argv[0]); return 0 }
			if C.strcmp(argv[i], c'--quick') == 0 { options.iterations = 2000; options.samples = 5; continue }
			if i + 1 >= argc { C.fprintf(C.stderr, c'Missing value or unknown argument: %s\n', argv[i]); return 2 }
			if C.strcmp(argv[i], c'--iterations') == 0 {
				i++
				if parse_number(argv[i], 1, 1000000000, &options.iterations) != 0 { C.fprintf(C.stderr, c'Invalid iteration count: %s\n', argv[i]); return 2 }
			} else if C.strcmp(argv[i], c'--samples') == 0 {
				i++
				mut samples := u64(0)
				if parse_number(argv[i], 5, 31, &samples) != 0 { C.fprintf(C.stderr, c'Invalid sample count: %s (expected 5..31)\n', argv[i]); return 2 }
				options.samples = u32(samples)
			} else if C.strcmp(argv[i], c'--label') == 0 {
				i++; options.label = argv[i]
				if !valid_label(options.label) { C.fprintf(C.stderr, c'Invalid label: expected 1..64 letters, digits, _ . -\n'); return 2 }
			} else { C.fprintf(C.stderr, c'Unknown argument: %s\n', argv[i]); return 2 }
		}
		init_workloads()
		if print_metadata(&options) != 0 { return 1 }

		for j := usize(0); j < 6; j++ { if measure(&alloc_bench_workloads[j], &options) != 0 { return 1 } }
		C.printf(c'ALLOC-DONE label=%s workloads=%zu checksum=%llu\n', options.label, usize(6), alloc_bench_observed.value)
	}
	return 0
}

fn init_workloads() {
	unsafe {
		if alloc_bench_workloads_ready { return }
		alloc_bench_workloads = [
			Workload{c'malloc_hot_64', c'alloc_free_pair', c'userspace', 1, 64, 1, 0, malloc_hot},
			Workload{c'malloc_mixed_batch_64', c'alloc_free_pair', c'userspace', 1, 0, 64, 0, malloc_mixed},
			Workload{c'malloc_touch_262144', c'alloc_free_pair', c'userspace', 20, 262144, 1, 4096, malloc_touch},
			Workload{c'mmap_anon_4096', c'map_unmap_pair', c'kernel_syscall', 20, 4096, 1, 0, mmap_no_touch},
			Workload{c'mmap_touch_262144', c'map_unmap_pair', c'kernel_syscall', 20, 262144, 1, 4096, mmap_touch},
			Workload{c'pipe_create_close', c'create_close_pair', c'kernel_syscall', 20, 0, 1, 0, pipe_create_close}
		]!
		alloc_bench_workloads_ready = true
	}
}
