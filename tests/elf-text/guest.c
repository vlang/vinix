// SPDX-License-Identifier: GPL-2.0-or-later
#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("ELF TEXT FAIL: line=%d errno=%d\n", __LINE__, errno); return 1; } } while (0)
// File-backed initialized storage for a synthetic PT_DYNAMIC table. A static
// executable needs no runtime linker, so its textrel policy is tested alone.
static volatile uint64_t dynamic_fixture[4] = { DT_FLAGS, 0, DT_NULL, 0 };
__attribute__((noinline, used, aligned(16384))) static int text_target(void) { return 73; }

static int check_text(int mutable)
{
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    uintptr_t address = (uintptr_t)text_target & ~(page - 1);
    errno = 0;
    int result = mprotect((void *)address, page, PROT_READ | PROT_EXEC);
    CHECK(mutable ? result == 0 : result == -1 && errno == EPERM);
    CHECK(text_target() == 73);
    return 0;
}

static int run_child(const char *path, const char *mode)
{
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        execl(path, path, mode, NULL);
        _exit(100);
    }
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return 0;
}

static int check_interpreter(void)
{
    uintptr_t base = getauxval(AT_BASE);
    CHECK(base != 0);
    Elf64_Ehdr *header = (void *)base;
    Elf64_Phdr *phdrs = (void *)(base + header->e_phoff);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    for (unsigned i = 0; i < header->e_phnum; ++i) {
        if (phdrs[i].p_type != PT_LOAD || !(phdrs[i].p_flags & PF_X)) continue;
        uintptr_t address = (base + phdrs[i].p_vaddr) & ~(page - 1);
        errno = 0;
        CHECK(mprotect((void *)address, page, PROT_READ | PROT_EXEC) == -1 && errno == EPERM);
        return 0;
    }
    CHECK(0);
}

static int make_fixture(const char *path, uint64_t tag, uint64_t value)
{
    int source = open("/proc/self/exe", O_RDONLY);
    int output = open(path, O_CREAT | O_TRUNC | O_RDWR, 0700);
    CHECK(source >= 0 && output >= 0);
    char buffer[8192];
    ssize_t length;
    while ((length = read(source, buffer, sizeof(buffer))) > 0)
        CHECK(write(output, buffer, length) == length);
    CHECK(length == 0 && close(source) == 0);
    Elf64_Ehdr header;
    CHECK(pread(output, &header, sizeof(header), 0) == sizeof(header));
    uint64_t offset = UINT64_MAX;
    off_t spare = -1;
    for (unsigned i = 0; i < header.e_phnum; ++i) {
        Elf64_Phdr ph;
        off_t at = header.e_phoff + i * header.e_phentsize;
        CHECK(pread(output, &ph, sizeof(ph), at) == sizeof(ph));
        uint64_t addr = (uintptr_t)dynamic_fixture;
        if (ph.p_type == PT_LOAD && addr >= ph.p_vaddr && addr - ph.p_vaddr < ph.p_filesz)
            offset = ph.p_offset + addr - ph.p_vaddr;
        if (ph.p_type == PT_GNU_STACK) spare = at;
    }
    CHECK(offset != UINT64_MAX && spare >= 0);
    uint64_t table[4] = { tag, value, DT_NULL, 0 };
    CHECK(pwrite(output, table, sizeof(table), offset) == sizeof(table));
    Elf64_Phdr ph = { .p_type = PT_DYNAMIC, .p_flags = PF_R | PF_W,
        .p_offset = offset, .p_vaddr = (uintptr_t)dynamic_fixture,
        .p_filesz = sizeof(table), .p_memsz = sizeof(table), .p_align = 8 };
    CHECK(pwrite(output, &ph, sizeof(ph), spare) == sizeof(ph));
    CHECK(close(output) == 0);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc > 1) {
        CHECK(check_text(!strcmp(argv[1], "mutable")) == 0);
        return !strcmp(argv[1], "interpreter") ? check_interpreter() : 0;
    }
    CHECK(check_text(0) == 0);
    CHECK(make_fixture("/tmp/elf-ordinary", DT_NULL, 0) == 0);
    CHECK(make_fixture("/tmp/elf-legacy", DT_TEXTREL, 0) == 0);
    CHECK(make_fixture("/tmp/elf-flags", DT_FLAGS, DF_TEXTREL) == 0);
    CHECK(run_child("/tmp/elf-ordinary", "frozen") == 0);
    CHECK(run_child("/tmp/elf-legacy", "mutable") == 0);
    CHECK(run_child("/tmp/elf-flags", "mutable") == 0);
    // This actual PIE uses musl's actual kernel-loaded interpreter.
    CHECK(run_child("/elf-pie", "interpreter") == 0);
    puts("ELF TEXT PASS: ordinary and both textrel encodings");
    puts("ELF TEXT PASS: PIE and interpreter boot");
    fflush(stdout);
    for (;;) pause();
}
