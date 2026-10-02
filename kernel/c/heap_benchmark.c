/*
 * Shared, opt-in x86_64 kernel allocator benchmark.
 *
 * Compile this C with the same real GCC version/options for both kernels.
 * The macOS build uses exported libkern allocation and IOKit logging APIs;
 * Vinix links its ordinary kernel malloc/free and allocation-free logger.
 * No metadata allocation, libc, SDK headers or borrowed allocator code.
 */
#if defined(__x86_64__)

#include <stddef.h>
#include <stdint.h>

#define KALLOC_SAMPLES 5
#define KALLOC_HOT_PAIRS UINT64_C(100000)
#define KALLOC_BATCH_ROUNDS UINT64_C(48)
#define KALLOC_BATCH_WIDTH 256
#define KALLOC_CLASSES 14
#define KALLOC_BIG_PAIRS UINT64_C(128)
#define KALLOC_BIG_BYTES 262144

#if defined(__clang__)
#define KALLOC_COMPILER "clang"
#define KALLOC_COMPILER_MAJOR __clang_major__
#define KALLOC_COMPILER_MINOR __clang_minor__
#define KALLOC_COMPILER_PATCH __clang_patchlevel__
#elif defined(__GNUC__)
#define KALLOC_COMPILER "gcc"
#define KALLOC_COMPILER_MAJOR __GNUC__
#define KALLOC_COMPILER_MINOR __GNUC_MINOR__
#define KALLOC_COMPILER_PATCH __GNUC_PATCHLEVEL__
#else
#define KALLOC_COMPILER "unknown"
#define KALLOC_COMPILER_MAJOR 0
#define KALLOC_COMPILER_MINOR 0
#define KALLOC_COMPILER_PATCH 0
#endif

#if defined(__APPLE__)
extern void *kern_os_malloc(size_t size);
extern void kern_os_free(void *pointer);
extern void IOLog(const char *format, ...);
#define kernel_alloc kern_os_malloc
#define kernel_free kern_os_free
#define kernel_log IOLog
#define KALLOC_PLATFORM "xnu"
#else
extern void *malloc(size_t size);
extern void free(void *pointer);
extern int printf_benchmark(const char *format, ...);
#define kernel_alloc malloc
#define kernel_free free
#define kernel_log printf_benchmark
#define KALLOC_PLATFORM "vinix"
#endif

struct kalloc_measurement {
	uint64_t ticks;
	uint64_t checksum;
	uint64_t expected;
};

struct kalloc_failure {
	const char *reason;
	uint64_t iteration;
	size_t size;
	size_t offset;
	unsigned char value;
};

int alloc_kernel_bench(void);
#if defined(__APPLE__)
int kmod_alloc_start(void *kmod_info, void *data);
int kmod_alloc_stop(void *kmod_info, void *data);
#endif

static const size_t kalloc_sizes[KALLOC_CLASSES] = {
	16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048
};

static uint64_t kalloc_ticks(void) {
	uint32_t low, high;
	__asm__ volatile("lfence\n\trdtsc\n\tlfence"
	                 : "=a" (low), "=d" (high) : : "memory");
	return (uint64_t)low | ((uint64_t)high << 32);
}

/* Verify the zero-filled allocation contract on every requested byte. */
static int kalloc_zeroed(const void *pointer, size_t size,
                         struct kalloc_failure *failure) {
	const volatile unsigned char *bytes = pointer;
	for (size_t offset = 0; offset < size; ++offset) {
		unsigned char value = bytes[offset];
		if (value != 0) {
			failure->reason = "nonzero_allocation";
			failure->size = size;
			failure->offset = offset;
			failure->value = value;
			return -1;
		}
	}
	return 0;
}

static int kalloc_hot(struct kalloc_measurement *measurement,
                      struct kalloc_failure *failure, int validate_zero) {
	uint64_t start = kalloc_ticks();
	for (uint64_t i = 0; i < KALLOC_HOT_PAIRS; ++i) {
		unsigned char *pointer = kernel_alloc(64);
		if (pointer == NULL) {
			failure->reason = "allocation_failed";
			failure->iteration = i;
			failure->size = 64;
			return -1;
		}
		if (validate_zero && kalloc_zeroed(pointer, 64, failure) != 0) {
			failure->iteration = i;
			kernel_free(pointer);
			return -1;
		}
		volatile unsigned char *bytes = pointer;
		unsigned char first = (unsigned char)i;
		unsigned char last = (unsigned char)(i ^ UINT64_C(0x5a));
		bytes[0] = first;
		bytes[63] = last;
		measurement->checksum += (uint64_t)bytes[0] + bytes[63];
		measurement->expected += (uint64_t)first + last;
		kernel_free(pointer);
	}
	uint64_t end = kalloc_ticks();
	if (end <= start) {
		failure->reason = "nonmonotonic_tsc";
		return -1;
	}
	measurement->ticks = end - start;
	return 0;
}

/* Exercise whole-page heap allocation and clearing without retaining a batch. */
static int kalloc_big(struct kalloc_measurement *measurement,
                      struct kalloc_failure *failure, int validate_zero) {
	uint64_t start = kalloc_ticks();
	for (uint64_t i = 0; i < KALLOC_BIG_PAIRS; ++i) {
		unsigned char *pointer = kernel_alloc(KALLOC_BIG_BYTES);
		if (pointer == NULL) {
			failure->reason = "allocation_failed";
			failure->iteration = i;
			failure->size = KALLOC_BIG_BYTES;
			return -1;
		}
		if (validate_zero && kalloc_zeroed(pointer, KALLOC_BIG_BYTES, failure) != 0) {
			failure->iteration = i;
			kernel_free(pointer);
			return -1;
		}
		volatile unsigned char *bytes = pointer;
		unsigned char first = (unsigned char)i;
		unsigned char last = (unsigned char)(i ^ UINT64_C(0x5a));
		bytes[0] = first;
		bytes[KALLOC_BIG_BYTES - 1] = last;
		measurement->checksum += (uint64_t)bytes[0] + bytes[KALLOC_BIG_BYTES - 1];
		measurement->expected += (uint64_t)first + last;
		kernel_free(pointer);
	}
	uint64_t end = kalloc_ticks();
	if (end <= start) {
		failure->reason = "nonmonotonic_tsc";
		return -1;
	}
	measurement->ticks = end - start;
	return 0;
}

static void kalloc_free_live(unsigned char **objects) {
	for (size_t i = 0; i < KALLOC_BATCH_WIDTH; ++i) {
		if (objects[i] != NULL) {
			kernel_free(objects[i]);
			objects[i] = NULL;
		}
	}
}

static int kalloc_batch(struct kalloc_measurement *measurement,
                        struct kalloc_failure *failure, int validate_zero) {
	unsigned char *objects[KALLOC_BATCH_WIDTH] = {NULL};
	uint64_t start = kalloc_ticks();
	for (uint64_t round = 0; round < KALLOC_BATCH_ROUNDS; ++round) {
		for (size_t i = 0; i < KALLOC_BATCH_WIDTH; ++i) {
			uint64_t iteration = round * KALLOC_BATCH_WIDTH + (uint64_t)i;
			size_t size = kalloc_sizes[iteration % KALLOC_CLASSES];
			unsigned char *pointer = kernel_alloc(size);
			if (pointer == NULL) {
				failure->reason = "allocation_failed";
				failure->iteration = iteration;
				failure->size = size;
				kalloc_free_live(objects);
				return -1;
			}
			objects[i] = pointer;
			if (validate_zero && kalloc_zeroed(pointer, size, failure) != 0) {
				failure->iteration = iteration;
				kalloc_free_live(objects);
				return -1;
			}
			volatile unsigned char *bytes = pointer;
			bytes[0] = (unsigned char)i;
			bytes[size - 1] = (unsigned char)round;
		}
		/* 73 is coprime to 256, so this frees each slot exactly once. */
		for (size_t i = 0; i < KALLOC_BATCH_WIDTH; ++i) {
			size_t index = (i * 73 + (size_t)round * 19) & (KALLOC_BATCH_WIDTH - 1);
			size_t size = kalloc_sizes[(round * KALLOC_BATCH_WIDTH + index) % KALLOC_CLASSES];
			volatile unsigned char *bytes = objects[index];
			measurement->checksum += (uint64_t)bytes[0] + bytes[size - 1];
			measurement->expected += (uint64_t)(unsigned char)index + (unsigned char)round;
			kernel_free(objects[index]);
			objects[index] = NULL;
		}
	}
	uint64_t end = kalloc_ticks();
	if (end <= start) {
		failure->reason = "nonmonotonic_tsc";
		return -1;
	}
	measurement->ticks = end - start;
	return 0;
}

static void kalloc_sort(uint64_t *values) {
	for (size_t i = 1; i < KALLOC_SAMPLES; ++i) {
		uint64_t value = values[i];
		size_t position = i;
		while (position != 0 && values[position - 1] > value) {
			values[position] = values[position - 1];
			--position;
		}
		values[position] = value;
	}
}

static int kalloc_phase(const char *phase, uint64_t pairs,
	                        int (*run)(struct kalloc_measurement *, struct kalloc_failure *, int),
                        uint64_t *total_checksum) {
	uint64_t samples[KALLOC_SAMPLES];
	uint64_t phase_checksum = 0;
	for (unsigned sample = 0; sample <= KALLOC_SAMPLES; ++sample) {
		struct kalloc_measurement measurement = {0, 0, 0};
		struct kalloc_failure failure = {"unknown", 0, 0, 0, 0};
		if (run(&measurement, &failure, sample == 0) != 0) {
			kernel_log("KALLOC-ERROR platform=%s phase=%s sample=%llu reason=%s"
			           " iteration=%llu size=%llu offset=%llu value=%llu\n",
			           KALLOC_PLATFORM, phase, (unsigned long long)sample, failure.reason,
			           (unsigned long long)failure.iteration, (unsigned long long)failure.size,
			           (unsigned long long)failure.offset, (unsigned long long)failure.value);
			return -1;
		}
		if (measurement.checksum != measurement.expected ||
		    (sample != 0 && measurement.checksum != phase_checksum)) {
			kernel_log("KALLOC-ERROR platform=%s phase=%s sample=%llu reason=payload_checksum"
			           " checksum=%llu expected=%llu\n", KALLOC_PLATFORM, phase,
			           (unsigned long long)sample, (unsigned long long)measurement.checksum,
			           (unsigned long long)measurement.expected);
			return -1;
		}
		phase_checksum = measurement.checksum;
		if (sample == 0)
			continue;
		samples[sample - 1] = measurement.ticks;
		kernel_log("KALLOC-SAMPLE platform=%s phase=%s sample=%llu pairs=%llu"
		           " ticks=%llu ticks_per_pair=%llu checksum=%llu\n", KALLOC_PLATFORM, phase,
		           (unsigned long long)sample, (unsigned long long)pairs,
		           (unsigned long long)measurement.ticks,
		           (unsigned long long)(measurement.ticks / pairs),
		           (unsigned long long)measurement.checksum);
	}
	kalloc_sort(samples);
	kernel_log("KALLOC-RESULT platform=%s phase=%s pairs=%llu samples=%llu"
	           " warmup_pairs=%llu median_ticks=%llu min_ticks=%llu max_ticks=%llu"
	           " median_ticks_per_pair=%llu checksum=%llu\n", KALLOC_PLATFORM, phase, (unsigned long long)pairs,
	           (unsigned long long)KALLOC_SAMPLES, (unsigned long long)pairs,
	           (unsigned long long)samples[KALLOC_SAMPLES / 2],
	           (unsigned long long)samples[0], (unsigned long long)samples[KALLOC_SAMPLES - 1],
	           (unsigned long long)(samples[KALLOC_SAMPLES / 2] / pairs),
	           (unsigned long long)phase_checksum);
	*total_checksum += phase_checksum;
	return 0;
}

int alloc_kernel_bench(void) {
	uint64_t checksum = 0;
	/* Catalina IOLog truncates a call at 256 bytes, including its newline. */
	kernel_log("KALLOC-META schema=3 platform=%s timer=x86-tsc samples=%llu"
	           " hot_pairs=%llu batch_rounds=%llu batch_width=%llu"
	           " big_pairs=%llu big_bytes=%llu"
	           " operation=alloc_free_pair\n",
	           KALLOC_PLATFORM, (unsigned long long)KALLOC_SAMPLES,
	           (unsigned long long)KALLOC_HOT_PAIRS, (unsigned long long)KALLOC_BATCH_ROUNDS,
	           (unsigned long long)KALLOC_BATCH_WIDTH, (unsigned long long)KALLOC_BIG_PAIRS,
	           (unsigned long long)KALLOC_BIG_BYTES);
	kernel_log("KALLOC-VALIDATION platform=%s"
	           " sizes=16,32,48,64,96,128,192,256,384,512,768,1024,1536,2048"
	           " zero_validation=warmup_every_requested_byte payload_validation=endpoints"
	           " timed_zero_validation=0\n", KALLOC_PLATFORM);
	kernel_log("KALLOC-COMPILER platform=%s compiler=%s"
	           " compiler_major=%llu compiler_minor=%llu compiler_patch=%llu\n",
	           KALLOC_PLATFORM, KALLOC_COMPILER,
	           (unsigned long long)KALLOC_COMPILER_MAJOR, (unsigned long long)KALLOC_COMPILER_MINOR,
	           (unsigned long long)KALLOC_COMPILER_PATCH);
	if (kalloc_phase("hot64", KALLOC_HOT_PAIRS, kalloc_hot, &checksum) != 0 ||
	    kalloc_phase("mixed256", KALLOC_BATCH_ROUNDS * KALLOC_BATCH_WIDTH,
	                 kalloc_batch, &checksum) != 0 ||
	    kalloc_phase("big262144", KALLOC_BIG_PAIRS, kalloc_big, &checksum) != 0)
		return 1;
	kernel_log("KALLOC-DONE platform=%s phases=3 checksum=%llu\n", KALLOC_PLATFORM,
	           (unsigned long long)checksum);
	return 0;
}

#if defined(__APPLE__)
/* kmod_start_func_t/kmod_stop_func_t use two opaque pointers and kern_return_t. */
int kmod_alloc_start(void *kmod_info, void *data) {
	(void)kmod_info;
	(void)data;
	return alloc_kernel_bench() == 0 ? 0 : 5;
}

int kmod_alloc_stop(void *kmod_info, void *data) {
	(void)kmod_info;
	(void)data;
	return 0;
}
#endif

#endif /* __x86_64__ */
