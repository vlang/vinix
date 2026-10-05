/* Steam's i386 client asks glibc's syscall() for its thread robust-list head.
 * QEMU linux-user currently returns ENOSYS for get_robust_list. Glibc still
 * calls set_robust_list at thread creation. Steam treats ENOSYS
 * as an unusable pthread implementation and crashes during UI startup.
 *
 * This is the i386 glibc 2.36 thread layout shipped in the Debian Bookworm
 * runtime that scripts/build-steam-aarch64.sh stages. QEMU's set_robust_list trace
 * confirms that glibc registers pthread_self() + 0x6c with a 12-byte head.
 * Keep this preload confined to translated i386 programs; native programs and
 * the 64-bit Steam helper have different thread layouts. */

extern void *dlsym(void *, const char *);
extern void *pthread_self(void);

typedef long (*syscall_function)(long, ...);
typedef void *(*mmap_function)(void *, unsigned long, int, int, int, long);
typedef void *(*mmap64_function)(void *, unsigned long, int, int, int, long long);
typedef int (*munmap_function)(void *, unsigned long);
typedef int (*uname_function)(void *);

/* Valve's i386 UI calls Is64BitOS() before starting its x86-64 web helper.
 * QEMU correctly identifies the translated process as i686, but that check
 * needs the architecture of the available guest runtime, not this process.
 * Both translators and the x86-64 helper runtime are staged together. */
int uname(void *buffer) {
    uname_function next = (uname_function)dlsym((void *)-1, "uname");
    int result = next(buffer);
    if (result == 0 && buffer != 0) {
        /* Linux's struct utsname has five 65-byte fields before machine. */
        char *machine = (char *)buffer + 4 * 65;
        const char name[] = "x86_64";
        for (unsigned int i = 0; i < sizeof(name); ++i) {
            machine[i] = name[i];
        }
    }
    return result;
}

/* QEMU reserves a 32-bit VA range on Vinix's 16 KiB page kernel. In that
 * mode it rejects a writable MAP_SHARED mapping whose 4 KiB-rounded length
 * ends within a 16 KiB host page. Steam's IPC buffers have such lengths.
 * Pad only non-fixed shared file mappings, then undo that padding on munmap.
 * The caller still sees and uses its original requested size. */
static struct {
    void *address;
    unsigned long requested;
    unsigned long padded;
} shared_mappings[512];
static int mappings_lock;

static void lock_mappings(void) {
    while (__atomic_exchange_n(&mappings_lock, 1, __ATOMIC_ACQUIRE)) {}
}

static void unlock_mappings(void) {
    __atomic_store_n(&mappings_lock, 0, __ATOMIC_RELEASE);
}

static unsigned long shared_length(void *address, unsigned long length,
                                   int protection, int flags, int fd) {
    if (address != 0 || fd < 0 || (flags & 3) != 1 ||
        !(protection & 2) || length > 0xffffc000UL) {
        return length;
    }
    unsigned long guest_length = (length + 4095) & ~4095UL;
    return (guest_length + 16383) & ~16383UL;
}

static void remember_mapping(void *address, unsigned long requested,
                             unsigned long padded) {
    if (address == (void *)-1 || requested == padded) {
        return;
    }
    lock_mappings();
    for (int i = 0; i < 512; ++i) {
        if (shared_mappings[i].address == 0 ||
            shared_mappings[i].address == address) {
            shared_mappings[i].address = address;
            shared_mappings[i].requested = requested;
            shared_mappings[i].padded = padded;
            break;
        }
    }
    unlock_mappings();
}

static unsigned long unmap_length(void *address, unsigned long length) {
    lock_mappings();
    for (int i = 0; i < 512; ++i) {
        if (shared_mappings[i].address == address &&
            (shared_mappings[i].requested == length ||
             shared_mappings[i].padded == length)) {
            length = shared_mappings[i].padded;
            shared_mappings[i].address = 0;
            break;
        }
    }
    unlock_mappings();
    return length;
}

void *mmap(void *address, unsigned long length, int protection, int flags,
           int fd, long offset) {
    mmap_function next = (mmap_function)dlsym((void *)-1, "mmap");
    unsigned long padded = shared_length(address, length, protection, flags, fd);
    void *result = next(address, padded, protection, flags, fd, offset);
    remember_mapping(result, length, padded);
    return result;
}

void *mmap64(void *address, unsigned long length, int protection, int flags,
             int fd, long long offset) {
    mmap64_function next = (mmap64_function)dlsym((void *)-1, "mmap64");
    unsigned long padded = shared_length(address, length, protection, flags, fd);
    void *result = next(address, padded, protection, flags, fd, offset);
    remember_mapping(result, length, padded);
    return result;
}

int munmap(void *address, unsigned long length) {
    munmap_function next = (munmap_function)dlsym((void *)-1, "munmap");
    return next(address, unmap_length(address, length));
}

long syscall(long number, ...) {
    __builtin_va_list arguments;
    __builtin_va_start(arguments, number);
    long a1 = __builtin_va_arg(arguments, long);
    long a2 = __builtin_va_arg(arguments, long);
    long a3 = __builtin_va_arg(arguments, long);
    long a4 = __builtin_va_arg(arguments, long);
    long a5 = __builtin_va_arg(arguments, long);
    long a6 = __builtin_va_arg(arguments, long);
    __builtin_va_end(arguments);

    /* __NR_get_robust_list for Linux/i386. Steam asks for the current thread. */
    if (number == 312 && a1 == 0 && a2 != 0 && a3 != 0) {
        *(void **)a2 = (char *)pthread_self() + 0x6c;
        *(unsigned long *)a3 = 12;
        return 0;
    }

    syscall_function next = (syscall_function)dlsym((void *)-1, "syscall");
    return next(number, a1, a2, a3, a4, a5, a6);
}
