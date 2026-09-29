// Which call sites allocated what is still live on the kernel heap, for
// hunting leaks: `make ALLOC_TRACK=1` builds it in, and then reading
// /proc/allocstart starts over and /proc/allocsites lists what has been
// allocated since and not freed, grouped by size and call chain, as
// "count size return-address...". tests/kernel-allocs/sites.py turns the
// addresses into functions. Only slab-class allocations are tracked.
#ifdef VINIX_ALLOC_TRACK
#include <stddef.h>
#include <stdint.h>

#define TRACK_SLOTS (1 << 16)
#define TRACK_DEPTH 10
#define AGG_SLOTS 4096

struct track_entry {
	uintptr_t ptr;
	uint64_t size;
	uintptr_t pc[TRACK_DEPTH];
};

struct agg_entry {
	uint64_t key;
	uint64_t size;
	uint64_t count;
	uintptr_t pc[TRACK_DEPTH];
};

static struct track_entry track_table[TRACK_SLOTS];
static struct agg_entry agg_table[AGG_SLOTS];
static volatile int track_on;
static volatile int track_lock;

static int try_lock(void) {
	return __atomic_exchange_n(&track_lock, 1, __ATOMIC_ACQUIRE) == 0;
}

static void spin_lock(void) {
	while (!try_lock()) {
	}
}

static void unlock(void) {
	__atomic_store_n(&track_lock, 0, __ATOMIC_RELEASE);
}

static uint64_t slot_of(uintptr_t p) {
	uint64_t h = (uint64_t)p >> 4;
	h ^= h >> 17;
	h *= 0x9e3779b97f4a7c15ull;
	return (h >> 20) & (TRACK_SLOTS - 1);
}

static int kaddr(uintptr_t a) {
	return a >= 0xffff000000000000ull && (a & 7) == 0;
}

void alloc_track(void *ptr, uint64_t size) {
	if (!track_on || ptr == NULL)
		return;
	uintptr_t pc[TRACK_DEPTH];
	uintptr_t *fp = __builtin_frame_address(0);
	for (int i = 0; i < TRACK_DEPTH; i++) {
		if (!kaddr((uintptr_t)fp)) {
			pc[i] = 0;
			continue;
		}
		pc[i] = fp[1];
		fp = (uintptr_t *)fp[0];
	}
	if (!try_lock())
		return;
	uint64_t s = slot_of((uintptr_t)ptr);
	for (uint64_t n = 0; n < TRACK_SLOTS - 1; n++, s = (s + 1) & (TRACK_SLOTS - 1)) {
		uintptr_t cur = track_table[s].ptr;
		if (cur == (uintptr_t)ptr || cur == 0) {
			track_table[s].ptr = (uintptr_t)ptr;
			track_table[s].size = size;
			for (int i = 0; i < TRACK_DEPTH; i++)
				track_table[s].pc[i] = pc[i];
			break;
		}
	}
	unlock();
}

void alloc_untrack(void *ptr) {
	if (!track_on || ptr == NULL)
		return;
	if (!try_lock())
		return;
	uint64_t i = slot_of((uintptr_t)ptr);
	for (uint64_t n = 0;; n++, i = (i + 1) & (TRACK_SLOTS - 1)) {
		if (n == TRACK_SLOTS || track_table[i].ptr == 0) {
			unlock();
			return;
		}
		if (track_table[i].ptr == (uintptr_t)ptr)
			break;
	}
	// Backward-shift deletion keeps every probe chain unbroken.
	uint64_t j = i;
	for (;;) {
		j = (j + 1) & (TRACK_SLOTS - 1);
		if (track_table[j].ptr == 0)
			break;
		uint64_t k = slot_of(track_table[j].ptr);
		int movable = (i <= j) ? (k <= i || k > j) : (k <= i && k > j);
		if (movable) {
			track_table[i] = track_table[j];
			i = j;
		}
	}
	track_table[i].ptr = 0;
	unlock();
}

void alloc_track_start(void) {
	spin_lock();
	track_on = 0;
	for (uint64_t i = 0; i < TRACK_SLOTS; i++)
		track_table[i].ptr = 0;
	track_on = 1;
	unlock();
}

static char *put_str(char *out, char *end, const char *s) {
	while (*s && out < end)
		*out++ = *s++;
	return out;
}

static char *put_hex(char *out, char *end, uint64_t v) {
	char tmp[17];
	int n = 0;
	do {
		tmp[n++] = "0123456789abcdef"[v & 15];
		v >>= 4;
	} while (v);
	while (n && out < end)
		*out++ = tmp[--n];
	return out;
}

static char *put_dec(char *out, char *end, uint64_t v) {
	char tmp[21];
	int n = 0;
	do {
		tmp[n++] = (char)('0' + v % 10);
		v /= 10;
	} while (v);
	while (n && out < end)
		*out++ = tmp[--n];
	return out;
}

// Groups what is live by size and call chain; writes the groups of at least
// min_count as "count size pc...".
uint64_t alloc_track_dump(char *buf, uint64_t cap, uint64_t min_count) {
	char *out = buf, *end = buf + cap;
	spin_lock();
	for (uint64_t i = 0; i < AGG_SLOTS; i++)
		agg_table[i].count = 0;
	uint64_t live = 0, dropped = 0;
	for (uint64_t i = 0; i < TRACK_SLOTS; i++) {
		struct track_entry *e = &track_table[i];
		if (e->ptr == 0)
			continue;
		live++;
		uint64_t key = e->size * 0x100000001b3ull;
		for (int d = 0; d < TRACK_DEPTH; d++)
			key = (key ^ e->pc[d]) * 0x100000001b3ull;
		uint64_t s = key & (AGG_SLOTS - 1);
		uint64_t n = 0;
		for (; n < AGG_SLOTS; n++, s = (s + 1) & (AGG_SLOTS - 1)) {
			struct agg_entry *a = &agg_table[s];
			if (a->count == 0) {
				a->key = key;
				a->size = e->size;
				for (int d = 0; d < TRACK_DEPTH; d++)
					a->pc[d] = e->pc[d];
				a->count = 1;
				break;
			}
			if (a->key == key) {
				a->count++;
				break;
			}
		}
		if (n == AGG_SLOTS)
			dropped++;
	}
	out = put_str(out, end, "live ");
	out = put_dec(out, end, live);
	out = put_str(out, end, " dropped ");
	out = put_dec(out, end, dropped);
	out = put_str(out, end, "\n");
	for (uint64_t i = 0; i < AGG_SLOTS; i++) {
		struct agg_entry *a = &agg_table[i];
		if (a->count < min_count)
			continue;
		out = put_dec(out, end, a->count);
		out = put_str(out, end, " ");
		out = put_dec(out, end, a->size);
		for (int d = 0; d < TRACK_DEPTH; d++) {
			out = put_str(out, end, " ");
			out = put_hex(out, end, a->pc[d]);
		}
		out = put_str(out, end, "\n");
	}
	unlock();
	return (uint64_t)(out - buf);
}
#endif
