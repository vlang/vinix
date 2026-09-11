@[manualfree]
module memory

fn C.printf_benchmark(charptr, ...voidptr)

// Opt-in, serial-console microbenchmark of the real kernel heap. It runs on
// the BSP after SMP has published CPU-cache readiness, so -d xnu_zone measures
// the magazine path as well as the shared zone core. TSC values are meaningful
// only as a relative comparison between otherwise identical boots.
const heap_benchmark_samples = 5
const heap_benchmark_hot_iterations = u64(100000)
const heap_benchmark_batch_rounds = u64(48)
const heap_benchmark_batch_width = u64(256)

fn heap_benchmark_ticks() u64 {
	mut low := u32(0)
	mut high := u32(0)
	asm volatile amd64 {
		lfence
		rdtsc
		; =a (low)
		  =d (high)
		;
		; memory
	}
	return u64(low) | (u64(high) << 32)
}

fn heap_benchmark_size(index u64) u64 {
	return match index % 14 {
		0 { u64(16) }
		1 { u64(32) }
		2 { u64(48) }
		3 { u64(64) }
		4 { u64(96) }
		5 { u64(128) }
		6 { u64(192) }
		7 { u64(256) }
		8 { u64(384) }
		9 { u64(512) }
		10 { u64(768) }
		11 { u64(1024) }
		12 { u64(1536) }
		else { u64(2048) }
	}
}

fn heap_benchmark_hot() (u64, u64) {
	mut checksum := u64(0)
	start := heap_benchmark_ticks()
	for i := u64(0); i < heap_benchmark_hot_iterations; i++ {
		ptr := malloc(64)
		unsafe { (&u8(ptr))[0] = u8(i) }
		checksum = (checksum << 7 | checksum >> 57) ^ u64(ptr)
		free(ptr)
	}
	stop := heap_benchmark_ticks()
	return stop - start, checksum
}

fn heap_benchmark_batch() (u64, u64) {
	mut objects := unsafe { [256]voidptr{} }
	mut checksum := u64(0)
	start := heap_benchmark_ticks()
	for round := u64(0); round < heap_benchmark_batch_rounds; round++ {
		for i := u64(0); i < heap_benchmark_batch_width; i++ {
			size := heap_benchmark_size(round * heap_benchmark_batch_width + i)
			ptr := malloc(size)
			unsafe {
				mut bytes := &u8(ptr)
				bytes[0] = u8(i)
				bytes[size - 1] = u8(round)
			}
			objects[int(i)] = ptr
		}
		// 73 is coprime to 256, so each round frees every slot exactly once
		// while avoiding the allocator-friendly allocation order.
		for i := u64(0); i < heap_benchmark_batch_width; i++ {
			index := (i * 73 + round * 19) & (heap_benchmark_batch_width - 1)
			ptr := objects[int(index)]
			checksum = (checksum << 9 | checksum >> 55) ^ u64(ptr)
			free(ptr)
		}
	}
	stop := heap_benchmark_ticks()
	return stop - start, checksum
}

fn heap_benchmark_report(phase &char, sample int, operations u64, ticks u64,
	checksum u64) {
	$if xnu_zone ? {
		C.printf_benchmark(c'heap-bench: allocator=xnu-zone phase=%s sample=%u operations=%llu ticks=%llu ticks_per_op=%llu checksum=%llx\n',
			phase, sample, operations, ticks, ticks / operations, checksum)
	} $else {
		C.printf_benchmark(c'heap-bench: allocator=vinix-bitmap phase=%s sample=%u operations=%llu ticks=%llu ticks_per_op=%llu checksum=%llx\n',
			phase, sample, operations, ticks, ticks / operations, checksum)
	}
}

pub fn heap_benchmark() {
	// Remove allocations retained by boot, then establish the selected
	// backend's steady state. The second pair creates XNU CPU-cache metadata;
	// heap_trim drains payload but intentionally does not destroy that metadata.
	heap_trim()
	baseline := free_bytes()
	for class := u64(0); class < 14; class++ {
		for _ in 0 .. 2 {
			ptr := malloc(heap_benchmark_size(class))
			free(ptr)
		}
	}
	heap_trim()
	// Warm instruction translation and both workload shapes before sampling.
	// This is particularly important for deterministic TCG comparisons.
	_, _ = heap_benchmark_hot()
	_, _ = heap_benchmark_batch()
	heap_trim()
	prepared := free_bytes()
	cache_bytes := if baseline >= prepared { baseline - prepared } else { u64(0) }

	// Ordinary printf is intentionally disabled in production kernels. This
	// one-shot, pre-scheduler benchmark uses an allocation-free serial writer
	// so the same records are observable in debug and production builds.
	C.printf_benchmark(c'heap-bench: version=1 timer=x86-tsc samples=%u hot_iterations=%llu batch_rounds=%llu batch_width=%llu\n',
		heap_benchmark_samples, heap_benchmark_hot_iterations, heap_benchmark_batch_rounds,
		heap_benchmark_batch_width)
	for sample in 0 .. heap_benchmark_samples {
		ticks, checksum := heap_benchmark_hot()
		heap_benchmark_report(c'hot', sample, heap_benchmark_hot_iterations * 2, ticks,
			checksum)
	}
	for sample in 0 .. heap_benchmark_samples {
		ticks, checksum := heap_benchmark_batch()
		heap_benchmark_report(c'batch', sample,
			heap_benchmark_batch_rounds * heap_benchmark_batch_width * 2, ticks, checksum)
	}

	before_trim := free_bytes()
	released := heap_trim()
	after_trim := free_bytes()
	retained := if prepared >= before_trim { prepared - before_trim } else { u64(0) }
	unreclaimed := if prepared >= after_trim { prepared - after_trim } else { u64(0) }
	$if xnu_zone ? {
		C.printf_benchmark(c'heap-bench: allocator=xnu-zone phase=memory cache_bytes=%llu burst_retained_bytes=%llu trim_released_bytes=%llu unreclaimed_bytes=%llu\n',
			cache_bytes, retained, released, unreclaimed)
	} $else {
		C.printf_benchmark(c'heap-bench: allocator=vinix-bitmap phase=memory cache_bytes=%llu burst_retained_bytes=%llu trim_released_bytes=%llu unreclaimed_bytes=%llu\n',
			cache_bytes, retained, released, unreclaimed)
	}
	C.printf_benchmark(c'heap-bench: done\n')
}
