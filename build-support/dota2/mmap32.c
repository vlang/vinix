/* SPDX-License-Identifier: GPL-2.0-or-later
 * QEMU 9.1 linux-user accepts x86 MAP_32BIT but drops it when translating mmap.
 * Valve's low-address allocator then repeatedly maps and rejects ranges that
 * cross 2 GiB. Keep non-fixed mappings within the x86 range before translation.
 * This library belongs only in the translated x86-64 process, never in QEMU.
 */

extern void *dlsym(void *, const char *);
extern int *__errno_location(void);
extern int munmap(void *, unsigned long);
extern int open(const char *, int, ...);
extern long read(int, void *, unsigned long);
extern int close(int);

typedef void *(*mmap_function)(void *, unsigned long, int, int, int, long);

#define MAP_FAILED ((void *)-1)
#define MAP_FIXED 0x10
#define MAP_32BIT 0x40
#define MAP_FIXED_NOREPLACE 0x100000
#define EINVAL 22
#define ENOMEM 12
#define EEXIST 17
#define PAGE_SIZE 4096UL
#define LOW_MIN 0x10000UL
#define LOW_FALLBACK 0x40000000UL
#define LOW_END 0x80000000UL

/* Parse translated guest maps with bounded stack storage. This snapshot
 * only chooses a candidate; NOREPLACE below performs the atomic reservation.
 */
struct maps_gap_reader {
    unsigned long candidate, length, limit;
    unsigned long number, start, previous_start;
    int phase, digit, records, invalid;
};

static int maps_gap_hex(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static void maps_gap_record(struct maps_gap_reader *state) {
    unsigned long end = state->number;
    if (end <= state->start ||
        (state->records && state->start < state->previous_start)) {
        state->invalid = 1;
        return;
    }
    state->previous_start = state->start;
    state->records = 1;
    if (state->candidate >= state->limit) return;
    if (state->start < state->candidate + state->length &&
        end > state->candidate) {
        state->candidate = end >= state->limit ? state->limit :
            (end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    }
}

static void maps_gap_feed(struct maps_gap_reader *state,
                          const unsigned char *data, unsigned long count) {
    for (unsigned long index = 0; index < count && !state->invalid; ++index) {
        unsigned char value = data[index];
        if (value == '\n') {
            if (state->phase != 2 && (state->phase != 0 || state->digit))
                state->invalid = 1;
            state->phase = 0;
            state->digit = 0;
            state->number = 0;
        } else if (state->phase != 2) {
            int digit = maps_gap_hex(value);
            if (digit >= 0) {
                if (state->number > (~0UL - (unsigned long)digit) / 16)
                    state->invalid = 1;
                else {
                    state->number = state->number * 16 + (unsigned long)digit;
                    state->digit = 1;
                }
            } else if (state->phase == 0 && state->digit && value == '-') {
                state->start = state->number;
                state->phase = 1;
                state->number = 0;
                state->digit = 0;
            } else if (state->phase == 1 && state->digit &&
                       (value == ' ' || value == '\t')) {
                maps_gap_record(state);
                state->phase = 2;
            } else {
                state->invalid = 1;
            }
        }
    }
}

/* limit is the exclusive upper address, not the maximum candidate. */
static int next_gap(unsigned long start, unsigned long length, unsigned long limit,
                    unsigned long *output) {
    if (!output || !length || length > ~0UL - (PAGE_SIZE - 1)) return -1;
    unsigned long rounded = (length + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    if (limit > LOW_END) return -1;
    if (start < LOW_MIN) start = LOW_MIN;
    if (start >= limit || rounded > limit - start) return 0;
    struct maps_gap_reader state = {0};
    state.candidate = (start + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    state.length = rounded;
    state.limit = limit;
    int fd = open("/proc/self/maps", 0x80000); /* O_RDONLY | O_CLOEXEC, Linux */
    if (fd < 0) return -1;
    unsigned char buffer[256];
    int status = -1;
    for (;;) {
        long count = read(fd, buffer, sizeof buffer);
        if (count < 0) {
            if (*__errno_location() == 4) continue; /* EINTR */
            break;
        }
        if (!count) {
            if (!state.invalid && state.records &&
                (state.phase == 2 || (state.phase == 0 && !state.digit)))
                status = state.candidate <= limit - rounded;
            break;
        }
        maps_gap_feed(&state, buffer, (unsigned long)count);
        if (state.invalid) break;
    }
    /* Exactly one close for every successful open, including parse/read
     * failure. Do not retry close(EINTR): Linux may already have reused fd.
     */
    close(fd);
    if (status == 1) *output = state.candidate;
    return status;
}

static void *failed(int error) {
    *__errno_location() = error;
    return MAP_FAILED;
}

static void *low_mapping(mmap_function next, void *address, unsigned long length,
                         int protection, int flags, int fd, long offset) {
    if (!(flags & MAP_32BIT) || (flags & (MAP_FIXED | MAP_FIXED_NOREPLACE))) {
        return next(address, length, protection, flags, fd, offset);
    }
    if (!length) {
        return failed(EINVAL);
    }
    if (length > ~0UL - (PAGE_SIZE - 1)) {
        return failed(ENOMEM);
    }
    unsigned long rounded = (length + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    if (rounded > LOW_END - LOW_MIN) {
        return failed(ENOMEM);
    }

    /* Linux permits an available explicit hint below its usual 1..2 GiB
     * search window. NOREPLACE makes this safe when other threads mmap too.
     * In particular, never use MAP_FIXED to make room for a non-fixed call.
     */
    int low_flags = (flags & ~MAP_32BIT) | MAP_FIXED_NOREPLACE;
    unsigned long hint = (unsigned long)address & ~(PAGE_SIZE - 1);
    if (hint >= LOW_MIN && hint <= LOW_END - rounded) {
        void *result = next((void *)hint, length, protection, low_flags, fd, offset);
        if (result != MAP_FAILED) {
            /* An implementation that ignores NOREPLACE may choose elsewhere.
             * Return only the requested free range, never an out-of-range one.
             */
            if ((unsigned long)result == hint) {
                return result;
            }
            munmap(result, length);
        } else if (*__errno_location() != EEXIST) {
            return result;
        }
    }
    if (rounded > LOW_END - LOW_FALLBACK) {
        return failed(ENOMEM);
    }
    /* The engine's constructor fills this window with large reservations.
     * Jump past occupied regions instead of probing every page after each
     * collision. A fresh snapshot on each retry needs no cached map lifetime.
     * If maps are unavailable, retain the bounded per-page search.
     */
    int maps_available = 1;
    for (unsigned long candidate = LOW_FALLBACK;
         candidate <= LOW_END - rounded; candidate += PAGE_SIZE) {
        if (maps_available) {
            unsigned long gap;
            int status = next_gap(candidate, rounded, LOW_END, &gap);
            if (!status) return failed(ENOMEM);
            if (status > 0) candidate = gap;
            else maps_available = 0;
        }
        void *result = next((void *)candidate, length, protection, low_flags, fd, offset);
        if (result != MAP_FAILED) {
            if ((unsigned long)result == candidate) {
                return result;
            }
            munmap(result, length);
        } else if (*__errno_location() != EEXIST) {
            return result;
        }
    }
    return failed(ENOMEM);
}

void *mmap(void *address, unsigned long length, int protection, int flags,
           int fd, long offset) {
    mmap_function next = (mmap_function)dlsym((void *)-1, "mmap");
    return low_mapping(next, address, length, protection, flags, fd, offset);
}

void *mmap64(void *address, unsigned long length, int protection, int flags,
             int fd, long offset) {
    /* Linux x86-64 defines both off_t and off64_t as long. */
    mmap_function next = (mmap_function)dlsym((void *)-1, "mmap64");
    return low_mapping(next, address, length, protection, flags, fd, offset);
}
