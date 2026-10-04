#ifndef MALLOC_META_H
#define MALLOC_META_H

#include <stdint.h>
#include <errno.h>
#include <limits.h>
#include "glue.h"

__attribute__((__visibility__("hidden")))
extern const uint16_t size_classes[];

#define MMAP_THRESHOLD 131052

/* Vinix anonymous mappings cost page tables, zeroing and TLB maintenance.
 * Reuse a bounded number of ordinary groups and large mappings. Set this
 * to zero at build time to retain upstream release policy. */
#ifndef VINIX_MALLOC_RETAIN
#define VINIX_MALLOC_RETAIN 1
#endif
#define LARGE_CACHE_COUNT 5
#define LARGE_CACHE_MAX_PAGES 512
#define RETAIN_GROUP_MAX_BYTES (128UL*1024)


#define UNIT 16
#define IB 4

struct group {
	struct meta *meta;
	unsigned char active_idx:5;
	char pad[UNIT - sizeof(struct meta *) - 1];
	unsigned char storage[];
};

struct meta {
	struct meta *prev, *next;
	struct group *mem;
	volatile int avail_mask, freed_mask;
	uintptr_t last_idx:5;
	uintptr_t freeable:1;
	uintptr_t sizeclass:6;
	uintptr_t maplen:8*sizeof(uintptr_t)-12;
};

struct meta_area {
	uint64_t check;
	struct meta_area *next;
	int nslots;
	struct meta slots[];
};

struct malloc_context {
	uint64_t secret;
#ifndef PAGESIZE
	size_t pagesize;
#endif
	int init_done;
	unsigned mmap_counter;
	struct meta *free_meta_head;
	struct meta *avail_meta;
	size_t avail_meta_count, avail_meta_area_count, meta_alloc_shift;
	struct meta_area *meta_area_head, *meta_area_tail;
	unsigned char *avail_meta_areas;
	struct meta *active[48];
	struct meta *large_cache[LARGE_CACHE_COUNT];
	size_t usage_by_class[48];
	uint8_t unmap_seq[32], bounces[32];
	uint8_t seq;
	uintptr_t brk;
};

__attribute__((__visibility__("hidden")))
extern struct malloc_context ctx;

#ifdef PAGESIZE
#define PGSZ PAGESIZE
#else
#define PGSZ ctx.pagesize
#endif

__attribute__((__visibility__("hidden")))
struct meta *alloc_meta(void);

__attribute__((__visibility__("hidden")))
int is_allzero(void *);

static inline void queue(struct meta **phead, struct meta *m)
{
	assert(!m->next);
	assert(!m->prev);
	if (*phead) {
		struct meta *head = *phead;
		m->next = head;
		m->prev = head->prev;
		m->next->prev = m->prev->next = m;
	} else {
		m->prev = m->next = m;
		*phead = m;
	}
}

static inline void dequeue(struct meta **phead, struct meta *m)
{
	if (m->next != m) {
		m->prev->next = m->next;
		m->next->prev = m->prev;
		if (*phead == m) *phead = m->next;
	} else {
		*phead = 0;
	}
	m->prev = m->next = 0;
}

static inline struct meta *dequeue_head(struct meta **phead)
{
	struct meta *m = *phead;
	if (m) dequeue(phead, m);
	return m;
}

static inline void free_meta(struct meta *m)
{
	*m = (struct meta){0};
	queue(&ctx.free_meta_head, m);
}

static inline uint32_t activate_group(struct meta *m)
{
	assert(!m->avail_mask);
	uint32_t mask, act = (2u<<m->mem->active_idx)-1;
	/* No other thread can publish frees while need_locks is zero. */
	if (!MT) {
		mask = m->freed_mask;
		m->freed_mask = mask & ~act;
	} else {
		do mask = m->freed_mask;
		while (a_cas(&m->freed_mask, mask, mask&~act)!=mask);
	}
	return m->avail_mask = mask & act;
}

static inline int get_slot_index(const unsigned char *p)
{
	return p[-3] & 31;
}

static inline struct meta *get_meta(const unsigned char *p)
{
	assert(!((uintptr_t)p & 15));
	int offset = *(const uint16_t *)(p - 2);
	int index = get_slot_index(p);
	if (p[-4]) {
		assert(!offset);
		offset = *(uint32_t *)(p - 8);
		assert(offset > 0xffff);
	}
	const struct group *base = (const void *)(p - UNIT*offset - UNIT);
	const struct meta *meta = base->meta;
	assert(meta->mem == base);
	assert(index <= meta->last_idx);
	assert(!(meta->avail_mask & (1u<<index)));
	assert(!(meta->freed_mask & (1u<<index)));
	const struct meta_area *area = (void *)((uintptr_t)meta & -4096);
	assert(area->check == ctx.secret);
	if (meta->sizeclass < 48) {
		assert(offset >= size_classes[meta->sizeclass]*index);
		assert(offset < size_classes[meta->sizeclass]*(index+1));
	} else {
		assert(meta->sizeclass == 63);
	}
	if (meta->maplen) {
		assert(offset <= meta->maplen*4096UL/UNIT - 1);
	}
	return (struct meta *)meta;
}

static inline size_t get_nominal_size(const unsigned char *p, const unsigned char *end)
{
	size_t reserved = p[-3] >> 5;
	if (reserved >= 5) {
		assert(reserved == 5);
		reserved = *(const uint32_t *)(end-4);
		assert(reserved >= 5);
		assert(!end[-5]);
	}
	assert(reserved <= end-p);
	assert(!*(end-reserved));
	// also check the slot's overflow byte
	assert(!*end);
	return end-reserved-p;
}

static inline size_t get_stride(const struct meta *g)
{
	if (!g->last_idx && g->maplen) {
		return g->maplen*4096UL - UNIT;
	} else {
		return UNIT*size_classes[g->sizeclass];
	}
}

static inline void set_size_at(unsigned char *p, unsigned char *end, size_t n, int idx)
{
	int reserved = end-p-n;
	if (reserved) end[-reserved] = 0;
	if (reserved >= 5) {
		*(uint32_t *)(end-4) = reserved;
		end[-5] = 0;
		reserved = 5;
	}
	p[-3] = idx + (reserved<<5);
}

static inline void set_size(unsigned char *p, unsigned char *end, size_t n)
{
	set_size_at(p, end, n, p[-3]&31);
}

static inline void *enframe(struct meta *g, int idx, size_t n, int ctr)
{
	size_t stride = get_stride(g);
	size_t slack = (stride-IB-n)/UNIT;
	unsigned char *p = g->mem->storage + stride*idx;
	unsigned char *end = p+stride-IB;
	// cycle offset within slot to increase interval to address
	// reuse, facilitate trapping double-free.
	int off = 0;
	assert(!p[-4]);
	/* With no whole unit of slack, clamping always chooses offset zero.
	 * Skip reading and cycling the old offset in that case. Slot selection
	 * still rotates, and positive-slack slots keep upstream offset cycling. */
	if (slack) {
		off = (p[-3] ? *(uint16_t *)(p-2) + 1 : ctr) & 255;
		if (off > slack) {
			size_t m = slack;
			m |= m>>1; m |= m>>2; m |= m>>4;
			off &= m;
			if (off > slack) off -= slack+1;
			assert(off <= slack);
		}
	}
	if (off) {
		// store offset in unused header at offset zero
		// if enframing at non-zero offset.
		*(uint16_t *)(p-2) = off;
		p[-3] = 7<<5;
		p += UNIT*off;
		// for nonzero offset there is no permanent check
		// byte, so make one.
		p[-4] = 0;
	}
	*(uint16_t *)(p-2) = (size_t)(p-g->mem->storage)/UNIT;
	/* idx is already known here; preserve it in the single final stamp. */
	set_size_at(p, end, n, idx);
	return p;
}

static inline int size_to_class(size_t n)
{
	n = (n+IB-1)>>4;
	if (n<10) return n;
	n++;
	int i = (28-__builtin_clz(n))*4 + 8;
	if (n>size_classes[i+1]) i+=2;
	if (n>size_classes[i]) i++;
	return i;
}

static inline int size_overflows(size_t n)
{
	if (n >= SIZE_MAX/2 - 4096) {
		errno = ENOMEM;
		return 1;
	}
	return 0;
}

/* One mapping in each power-of-two bucket, from 128 KiB to 2 MiB.
 * Their combined upper bounds total 3968 KiB. A larger mapping is never
 * cached. Metadata stays owned by the cache until it is reused or trimmed. */
static inline int large_cache_index(size_t maplen)
{
	if (!VINIX_MALLOC_RETAIN || maplen < 32 || maplen > LARGE_CACHE_MAX_PAGES)
		return -1;
	int i = 0;
	for (size_t upper = 32; maplen > upper; upper <<= 1) i++;
	return i;
}

static inline void step_seq(void)
{
	if (ctx.seq==255) {
		for (int i=0; i<32; i++) ctx.unmap_seq[i] = 0;
		ctx.seq = 1;
	} else {
		ctx.seq++;
	}
}

static inline void record_seq(int sc)
{
	if (sc-7U < 32) ctx.unmap_seq[sc-7] = ctx.seq;
}

static inline void account_bounce(int sc)
{
	if (sc-7U < 32) {
		int seq = ctx.unmap_seq[sc-7];
		if (seq && ctx.seq-seq < 10) {
			if (ctx.bounces[sc-7]+1 < 100)
				ctx.bounces[sc-7]++;
			else
				ctx.bounces[sc-7] = 150;
		}
	}
}

static inline void decay_bounces(int sc)
{
	if (sc-7U < 32 && ctx.bounces[sc-7])
		ctx.bounces[sc-7]--;
}

static inline int is_bouncing(int sc)
{
	return (sc-7U < 32 && ctx.bounces[sc-7] >= 100);
}

#endif
