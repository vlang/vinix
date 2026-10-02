/*
 * Portable single-thread allocation benchmark for identical guest workloads.
 *
 * Build with real GCC on each guest:
 *   gcc -std=c11 -O2 -fno-builtin -Wall -Wextra -Werror bench.c -o alloc-bench
 *
 * malloc measures the guest's user-space allocator; anonymous mmap and pipe
 * creation also exercise the kernel. None directly measures kernel kalloc.
 * Volatile payload accesses keep every allocation and touch observable.
 */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE 1
#define _DARWIN_C_SOURCE 1

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MAP_ANONYMOUS
#error "This benchmark requires anonymous mmap support"
#endif

#define MAX_SAMPLES 31
#define BATCH_SIZE 64
#define LARGE_BYTES 262144
#define TOUCH_STRIDE 4096

struct options {
	uint64_t iterations;
	unsigned samples;
	const char *label;
};

struct outcome {
	uint64_t checksum;
	uint64_t expected;
};

struct workload {
	const char *name;
	const char *operation;
	const char *category;
	unsigned divisor;
	size_t bytes;
	size_t batch;
	size_t touch_stride;
	int (*run)(uint64_t, struct outcome *);
};

static volatile uint64_t observed_checksum;

static int fail(const char *action) {
	fprintf(stderr, "ALLOC-ERROR action=%s errno=%d message=%s\n",
	        action, errno, strerror(errno));
	return -1;
}

static int now_ns(uint64_t *value) {
	struct timespec time;
	if (clock_gettime(CLOCK_MONOTONIC, &time) != 0)
		return fail("clock_gettime");
	*value = (uint64_t)time.tv_sec * UINT64_C(1000000000) +
	         (uint64_t)time.tv_nsec;
	return 0;
}

static unsigned char value_for(uint64_t iteration, size_t offset) {
	return (unsigned char)(iteration * UINT64_C(17) + (uint64_t)offset);
}

/* One allocation/free pair, with two endpoint writes and verified reads. */
static int malloc_hot(uint64_t iterations, struct outcome *out) {
	for (uint64_t i = 0; i < iterations; ++i) {
		unsigned char *allocation = malloc(64);
		if (allocation == NULL)
			return fail("malloc_hot_64");
		volatile unsigned char *payload = allocation;
		unsigned char first = value_for(i, 0);
		unsigned char last = (unsigned char)(first ^ 0x5aU);
		payload[0] = first;
		payload[63] = last;
		out->checksum += (uint64_t)payload[0] + payload[63];
		out->expected += (uint64_t)first + last;
		free(allocation);
	}
	return 0;
}

/* Keep up to 64 differently sized objects live, then free in reverse order. */
static int malloc_mixed(uint64_t iterations, struct outcome *out) {
	static const size_t sizes[] = {
		16, 32, 64, 96, 128, 256, 512, 1024, 2048, 4096, 8192, 16384
	};
	unsigned char *allocations[BATCH_SIZE];
	size_t live_sizes[BATCH_SIZE];
	for (uint64_t completed = 0; completed < iterations;) {
		uint64_t remaining = iterations - completed;
		size_t count = remaining < BATCH_SIZE ? (size_t)remaining : BATCH_SIZE;
		for (size_t j = 0; j < count; ++j) {
			uint64_t i = completed + (uint64_t)j;
			size_t size = sizes[i % (sizeof sizes / sizeof sizes[0])];
			allocations[j] = malloc(size);
			if (allocations[j] == NULL) {
				while (j != 0)
					free(allocations[--j]);
				return fail("malloc_mixed_batch_64");
			}
			live_sizes[j] = size;
			volatile unsigned char *payload = allocations[j];
			payload[0] = value_for(i, 0);
			payload[size - 1] = value_for(i, size - 1);
		}
		for (size_t j = count; j != 0;) {
			--j;
			uint64_t i = completed + (uint64_t)j;
			size_t size = live_sizes[j];
			volatile unsigned char *payload = allocations[j];
			out->checksum += (uint64_t)payload[0] + payload[size - 1];
			out->expected += (uint64_t)value_for(i, 0) + value_for(i, size - 1);
			free(allocations[j]);
		}
		completed += (uint64_t)count;
	}
	return 0;
}

/* Fixed 4 KiB spacing makes the bytes accessed equal across guest page sizes. */
static void touch_pages(unsigned char *allocation, uint64_t iteration,
                        struct outcome *out) {
	volatile unsigned char *payload = allocation;
	for (size_t offset = 0; offset < LARGE_BYTES; offset += TOUCH_STRIDE)
		payload[offset] = value_for(iteration, offset / TOUCH_STRIDE);
	for (size_t offset = 0; offset < LARGE_BYTES; offset += TOUCH_STRIDE) {
		out->checksum += payload[offset];
		out->expected += value_for(iteration, offset / TOUCH_STRIDE);
	}
}

static int malloc_touch(uint64_t iterations, struct outcome *out) {
	for (uint64_t i = 0; i < iterations; ++i) {
		unsigned char *allocation = malloc(LARGE_BYTES);
		if (allocation == NULL)
			return fail("malloc_touch_262144");
		touch_pages(allocation, i, out);
		free(allocation);
	}
	return 0;
}

static int mmap_no_touch(uint64_t iterations, struct outcome *out) {
	(void)out;
	for (uint64_t i = 0; i < iterations; ++i) {
		void *allocation = mmap(NULL, TOUCH_STRIDE, PROT_READ | PROT_WRITE,
		                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (allocation == MAP_FAILED)
			return fail("mmap_anon_4096");
		if (munmap(allocation, TOUCH_STRIDE) != 0)
			return fail("munmap_anon_4096");
	}
	return 0;
}

static int mmap_touch(uint64_t iterations, struct outcome *out) {
	for (uint64_t i = 0; i < iterations; ++i) {
		unsigned char *allocation = mmap(NULL, LARGE_BYTES, PROT_READ | PROT_WRITE,
		                                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (allocation == MAP_FAILED)
			return fail("mmap_touch_262144");
		touch_pages(allocation, i, out);
		if (munmap(allocation, LARGE_BYTES) != 0)
			return fail("munmap_touch_262144");
	}
	return 0;
}

static int pipe_create_close(uint64_t iterations, struct outcome *out) {
	(void)out;
	for (uint64_t i = 0; i < iterations; ++i) {
		int descriptors[2];
		if (pipe(descriptors) != 0)
			return fail("pipe");
		int first_result = close(descriptors[0]);
		int first_errno = errno;
		int second_result = close(descriptors[1]);
		if (first_result != 0) {
			errno = first_errno;
			return fail("pipe_close_read");
		}
		if (second_result != 0)
			return fail("pipe_close_write");
	}
	return 0;
}

static const struct workload workloads[] = {
	{"malloc_hot_64", "alloc_free_pair", "userspace", 1, 64, 1, 0, malloc_hot},
	{"malloc_mixed_batch_64", "alloc_free_pair", "userspace", 1, 0, BATCH_SIZE,
	 0, malloc_mixed},
	{"malloc_touch_262144", "alloc_free_pair", "userspace", 20, LARGE_BYTES,
	 1, TOUCH_STRIDE, malloc_touch},
	{"mmap_anon_4096", "map_unmap_pair", "kernel_syscall", 20, TOUCH_STRIDE,
	 1, 0, mmap_no_touch},
	{"mmap_touch_262144", "map_unmap_pair", "kernel_syscall", 20, LARGE_BYTES,
	 1, TOUCH_STRIDE, mmap_touch},
	{"pipe_create_close", "create_close_pair", "kernel_syscall", 20, 0, 1,
	 0, pipe_create_close}
};

static int compare_u64(const void *left, const void *right) {
	uint64_t a = *(const uint64_t *)left;
	uint64_t b = *(const uint64_t *)right;
	return (a > b) - (a < b);
}

static int verify(const struct workload *workload, const struct outcome *out) {
	observed_checksum ^= out->checksum;
	if (out->checksum != out->expected) {
		fprintf(stderr, "ALLOC-ERROR action=verify workload=%s checksum=%" PRIu64
		        " expected=%" PRIu64 "\n", workload->name, out->checksum,
		        out->expected);
		return -1;
	}
	return 0;
}

static int measure(const struct workload *workload, const struct options *options) {
	uint64_t count = (options->iterations + workload->divisor - 1) /
	                 workload->divisor;
	uint64_t elapsed[MAX_SAMPLES];
	struct outcome warmup = {0, 0};
	if (workload->run(count, &warmup) != 0 || verify(workload, &warmup) != 0)
		return -1;
	for (unsigned sample = 0; sample < options->samples; ++sample) {
		struct outcome out = {0, 0};
		uint64_t start, end;
		if (now_ns(&start) != 0)
			return -1;
		int result = workload->run(count, &out);
		if (now_ns(&end) != 0 || result != 0 || verify(workload, &out) != 0)
			return -1;
		if (end <= start) {
			fprintf(stderr, "ALLOC-ERROR action=timer workload=%s start_ns=%" PRIu64
			        " end_ns=%" PRIu64 "\n", workload->name, start, end);
			return -1;
		}
		elapsed[sample] = end - start;
		printf("ALLOC-SAMPLE label=%s workload=%s sample=%u pairs=%" PRIu64
		       " elapsed_ns=%" PRIu64 " ns_per_pair=%.3f checksum=%" PRIu64 "\n",
		       options->label, workload->name, sample + 1, count, elapsed[sample],
		       (double)elapsed[sample] / (double)count, out.checksum);
		fflush(stdout);
	}
	qsort(elapsed, options->samples, sizeof elapsed[0], compare_u64);
	unsigned middle = options->samples / 2;
	double median = (double)elapsed[middle];
	if (options->samples % 2 == 0)
		median = ((double)elapsed[middle - 1] + median) / 2.0;
	printf("ALLOC-RESULT label=%s workload=%s category=%s operation=%s"
	       " pairs=%" PRIu64 " samples=%u warmup_pairs=%" PRIu64
	       " bytes=%zu batch=%zu touch_stride=%zu"
	       " median_ns_per_pair=%.3f min_ns_per_pair=%.3f max_ns_per_pair=%.3f\n",
	       options->label, workload->name, workload->category, workload->operation,
	       count, options->samples, count, workload->bytes, workload->batch,
	       workload->touch_stride, median / (double)count,
	       (double)elapsed[0] / (double)count,
	       (double)elapsed[options->samples - 1] / (double)count);
	fflush(stdout);
	return 0;
}

static void usage(const char *program) {
	printf("Usage: %s [--iterations N] [--samples N] [--quick] [--label NAME]\n"
	       "  --iterations N  malloc pairs (default 20000, range 1..1000000000);\n"
	       "                  large malloc, mmap and pipe pairs are ceil(N/20)\n"
	       "  --samples N     measured samples (default 7, range 5..31)\n"
	       "  --quick         set iterations=2000 and samples=5\n"
	       "  --label NAME    letters, digits, underscores, dots or dashes\n"
	       "Options apply in order. Each workload also gets one full warmup.\n"
	       "Build: gcc -std=c11 -O2 -fno-builtin -Wall -Wextra -Werror "
	       "bench.c -o alloc-bench\n", program);
}

static int parse_number(const char *text, uint64_t minimum, uint64_t maximum,
                        uint64_t *value) {
	if (*text == '\0')
		return -1;
	for (const char *cursor = text; *cursor != '\0'; ++cursor)
		if (*cursor < '0' || *cursor > '9')
			return -1;
	errno = 0;
	char *end;
	unsigned long long parsed = strtoull(text, &end, 10);
	if (errno != 0 || *end != '\0' || parsed < minimum || parsed > maximum)
		return -1;
	*value = (uint64_t)parsed;
	return 0;
}

static int valid_label(const char *label) {
	if (*label == '\0' || strlen(label) > 64)
		return 0;
	for (const char *cursor = label; *cursor != '\0'; ++cursor) {
		char c = *cursor;
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		      (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.'))
			return 0;
	}
	return 1;
}

/* uname strings and compiler versions contain spaces on some systems. */
static void print_token(const char *value) {
	for (const unsigned char *cursor = (const unsigned char *)value;
	     *cursor != '\0'; ++cursor) {
		unsigned char c = *cursor;
		putchar((c > 32 && c < 127 && c != '=') ? c : '_');
	}
}

static int print_metadata(const struct options *options) {
	struct utsname identity;
	struct timespec resolution;
	if (uname(&identity) != 0)
		return fail("uname");
	if (clock_getres(CLOCK_MONOTONIC, &resolution) != 0)
		return fail("clock_getres");
	long page_size = sysconf(_SC_PAGESIZE);
	if (page_size <= 0)
		return fail("sysconf_pagesize");
	printf("ALLOC-META schema=1 label=%s platform=", options->label);
	print_token(identity.sysname);
	printf(" release=");
	print_token(identity.release);
	printf(" arch=");
	print_token(identity.machine);
#if defined(__clang__)
	printf(" compiler=clang compiler_major=%d compiler_minor=%d compiler_patch=%d",
	       __clang_major__, __clang_minor__, __clang_patchlevel__);
#elif defined(__GNUC__)
	printf(" compiler=gcc compiler_major=%d compiler_minor=%d compiler_patch=%d",
	       __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
#else
	printf(" compiler=unknown");
#endif
#if defined(__VERSION__)
	printf(" compiler_version=");
	print_token(__VERSION__);
#endif
	printf(" pointer_bits=%zu page_size=%ld clock=CLOCK_MONOTONIC"
	       " clock_resolution_ns=%" PRIu64 " threads=1 iterations=%" PRIu64
	       " samples=%u touch_stride=%d large_bytes=%d mixed_sizes="
	       "16,32,64,96,128,256,512,1024,2048,4096,8192,16384\n",
	       sizeof(void *) * 8, page_size,
	       (uint64_t)resolution.tv_sec * UINT64_C(1000000000) +
	       (uint64_t)resolution.tv_nsec,
	       options->iterations, options->samples, TOUCH_STRIDE, LARGE_BYTES);
	fflush(stdout);
	return 0;
}

int main(int argc, char **argv) {
	struct options options = {20000, 7, "default"};
	for (int i = 1; i < argc; ++i) {
		if (strcmp(argv[i], "--help") == 0) {
			usage(argv[0]);
			return 0;
		}
		if (strcmp(argv[i], "--quick") == 0) {
			options.iterations = 2000;
			options.samples = 5;
			continue;
		}
		if (i + 1 >= argc) {
			fprintf(stderr, "Missing value or unknown argument: %s\n", argv[i]);
			return 2;
		}
		if (strcmp(argv[i], "--iterations") == 0) {
			if (parse_number(argv[++i], 1, UINT64_C(1000000000),
			                 &options.iterations) != 0) {
				fprintf(stderr, "Invalid iteration count: %s\n", argv[i]);
				return 2;
			}
		} else if (strcmp(argv[i], "--samples") == 0) {
			uint64_t samples;
			if (parse_number(argv[++i], 5, MAX_SAMPLES, &samples) != 0) {
				fprintf(stderr, "Invalid sample count: %s (expected 5..31)\n", argv[i]);
				return 2;
			}
			options.samples = (unsigned)samples;
		} else if (strcmp(argv[i], "--label") == 0) {
			options.label = argv[++i];
			if (!valid_label(options.label)) {
				fprintf(stderr, "Invalid label: expected 1..64 letters, digits, _ . -\n");
				return 2;
			}
		} else {
			fprintf(stderr, "Unknown argument: %s\n", argv[i]);
			return 2;
		}
	}
	if (print_metadata(&options) != 0)
		return 1;
	for (size_t i = 0; i < sizeof workloads / sizeof workloads[0]; ++i)
		if (measure(&workloads[i], &options) != 0)
			return 1;
	printf("ALLOC-DONE label=%s workloads=%zu checksum=%" PRIu64 "\n",
	       options.label, sizeof workloads / sizeof workloads[0], observed_checksum);
	return 0;
}
