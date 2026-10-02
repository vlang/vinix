/* SPDX-License-Identifier: GPL-2.0-or-later
 * QEMU 9.1 linux-user accepts x86 MAP_32BIT but drops it when translating mmap.
 * Valve's low-address allocator then repeatedly maps and rejects ranges that
 * cross 2 GiB. Keep non-fixed mappings within the x86 range before translation.
 * This library belongs only in the translated x86-64 process, never in QEMU.
 */

extern void *dlsym(void *, const char *);
extern int *__errno_location(void);
extern int munmap(void *, unsigned long);

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
    for (unsigned long candidate = LOW_FALLBACK;
         candidate <= LOW_END - rounded; candidate += PAGE_SIZE) {
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
