#ifndef VINIX_DESKTOP_HEAP_TRACKER_H
#define VINIX_DESKTOP_HEAP_TRACKER_H

// A deliberately allocation-free implementation of V's `-d track_heap`
// hooks. Tests enable it only around a frame, after the desktop's persistent
// buffers have been warmed up, so the result is exactly the allocations that
// frame failed to release.
struct vinix_heap_record {
	void *pointer;
	unsigned long long size;
};

static struct vinix_heap_record vinix_heap_records[16384];
static unsigned long long vinix_heap_live_bytes;
static unsigned int vinix_heap_record_count;
static int vinix_heap_tracking;

void vheap_alloc(void *pointer, unsigned long long size) {
	if (!vinix_heap_tracking || pointer == 0) return;
	if (vinix_heap_record_count >= 16384) __builtin_trap();
	vinix_heap_records[vinix_heap_record_count].pointer = pointer;
	vinix_heap_records[vinix_heap_record_count].size = size;
	vinix_heap_record_count++;
	vinix_heap_live_bytes += size;
}

void vheap_free(void *pointer) {
	if (!vinix_heap_tracking || pointer == 0) return;
	for (unsigned int i = 0; i < vinix_heap_record_count; i++) {
		if (vinix_heap_records[i].pointer != pointer) continue;
		vinix_heap_live_bytes -= vinix_heap_records[i].size;
		vinix_heap_record_count--;
		vinix_heap_records[i] = vinix_heap_records[vinix_heap_record_count];
		return;
	}
}

static void vinix_heap_begin(void) {
	vinix_heap_live_bytes = 0;
	vinix_heap_record_count = 0;
	vinix_heap_tracking = 1;
}

static unsigned long long vinix_heap_end(void) {
	vinix_heap_tracking = 0;
	return vinix_heap_live_bytes;
}

static unsigned int vinix_heap_count(void) {
	return vinix_heap_record_count;
}

static unsigned long long vinix_heap_size_at(unsigned int index) {
	return index < vinix_heap_record_count ? vinix_heap_records[index].size : 0;
}

#endif
