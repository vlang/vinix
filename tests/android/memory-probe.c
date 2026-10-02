/* Exercise the page contract used by ART and its QEMU host. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

static void require(int condition, const char *operation) {
    if (!condition) {
        fprintf(stderr, "ANDROID-MEMORY-FAIL %s errno=%d\n", operation, errno);
        exit(1);
    }
}

int main(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    require(page == 4096 || page == 16384, "page size");
#if defined(__x86_64__)
    void *compressed = mmap(NULL, 64 * 1024 * 1024, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
    printf("ANDROID-MEMORY-MAP32 address=%p\n", compressed);
    require(compressed != MAP_FAILED, "MAP_32BIT allocation");
    require((uintptr_t)compressed + 64 * 1024 * 1024 <= UINT64_C(0x80000000),
            "MAP_32BIT compressed reference arena below two GiB");
    for (size_t offset = 0; offset < 64 * 1024 * 1024; offset += page)
        *(volatile uint32_t *)((char *)compressed + offset) = (uint32_t)offset + 1;
    for (size_t offset = 0; offset < 64 * 1024 * 1024; offset += page)
        require(*(volatile uint32_t *)((char *)compressed + offset) == (uint32_t)offset + 1,
                "compressed reference arena contents");
    require(munmap(compressed, 64 * 1024 * 1024) == 0, "release compressed reference arena");
#endif
    void *space = mmap((void *)(uintptr_t)0x20000000, 64 * 1024 * 1024,
                       PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    require(space != MAP_FAILED, "reserve ART-style low-address arena");
    require((uintptr_t)space % page == 0, "page-aligned reservation");
    require((uintptr_t)space + 64 * 1024 * 1024 <= UINT64_C(0x100000000), "low-address arena");
    require(mprotect(space, 2 * page, PROT_READ | PROT_WRITE) == 0, "commit two pages");
    ((volatile unsigned char *)space)[0] = 0x12;
    ((volatile unsigned char *)space)[page] = 0x34;
    require(madvise(space, page, MADV_DONTNEED) == 0, "discard one anonymous page");
    require(((volatile unsigned char *)space)[0] == 0 &&
            ((volatile unsigned char *)space)[page] == 0x34, "retain adjacent page after discard");
    ((volatile unsigned char *)space)[0] = 0x12;
    require(mprotect(space, 2 * page, PROT_READ) == 0, "protect committed pages");
    require(((volatile unsigned char *)space)[0] == 0x12 &&
            ((volatile unsigned char *)space)[page] == 0x34, "retain page contents");
    require(munmap(space, 64 * 1024 * 1024) == 0, "release sparse reservation");

    space = mmap(NULL, page, PROT_READ | PROT_WRITE | PROT_EXEC,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    require(space != MAP_FAILED, "scoped writable executable mapping");
    ((volatile unsigned char *)space)[0] = 0x56;
    require(mprotect(space, page, PROT_READ | PROT_EXEC) == 0, "make generated code executable");
    require(munmap(space, page) == 0, "release generated code mapping");

    int fd = open("/tmp/android-memory-file", O_CREAT | O_TRUNC | O_RDWR, 0600);
    require(fd >= 0, "create file mapping backing");
    require(ftruncate(fd, (off_t)(3 * page)) == 0, "size file mapping backing");
    unsigned char value = 0x78;
    require(pwrite(fd, &value, 1, (off_t)page) == 1, "write aligned file offset");
    space = mmap(NULL, page, PROT_READ, MAP_PRIVATE, fd, (off_t)page);
    require(space != MAP_FAILED, "map aligned file offset");
    require(((volatile unsigned char *)space)[0] == value, "read aligned file data");
    require(munmap(space, page) == 0, "release file mapping");
    close(fd);
    unlink("/tmp/android-memory-file");
    printf("ANDROID-MEMORY-PASS page_size=%zu\n", page);
    return 0;
}
