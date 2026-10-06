/* SPDX-License-Identifier: MIT
 * Iris's host-file IOMAN hooks, with handles owned by an IOP instance.
 * Copyright (c) 2025 Allkern/Lisandro Alarcon (original Iris implementation)
 */
#include <array>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include "iop/hle/ioman.h"

namespace {
using handles = std::array<FILE *, 64>;
std::map<iop_state *, handles> owners;
FILE *lookup(iop_state *iop) {
    unsigned fd = iop->r[4];
    auto found = owners.find(iop);
    if (fd < 0x100 || fd >= 0x140 || found == owners.end()) return nullptr;
    return found->second[fd - 0x100];
}
}

extern "C" void vinix_ps2_ioman_destroy(iop_state *iop) {
    auto found = owners.find(iop);
    if (found == owners.end()) return;
    for (FILE *file : found->second) if (file) fclose(file);
    owners.erase(found);
}

extern "C" int ioman_open(iop_state *iop) {
    char bytes[256] = {};
    unsigned length;
    for (length = 0; length < sizeof bytes - 1; ++length) {
        bytes[length] = iop_read8(iop, iop->r[4] + length);
        if (!bytes[length]) break;
    }
    if (length == sizeof bytes - 1) return 0;
    std::string path(bytes);
    size_t colon = path.find(':');
    if (colon == std::string::npos) return 0;
    std::string device = path.substr(0, colon);
    if (device != "host" && device != "host0" && device != "mass") return 0;
    std::string name = path.substr(colon + 1);
    size_t start = name.find_first_not_of(' ');
    if (start == std::string::npos) { iop_return(iop, -1); return 1; }
    name.erase(0, start);
    FILE *file = fopen(name.c_str(), "rb");
    if (!file) { iop_return(iop, -1); return 1; }
    auto &table = owners[iop];
    for (unsigned i = 0; i < table.size(); ++i) {
        if (!table[i]) {
            table[i] = file;
            iop_return(iop, 0x100 + i);
            return 1;
        }
    }
    fclose(file);
    iop_return(iop, -1);
    return 1;
}

extern "C" int ioman_close(iop_state *iop) {
    FILE *file = lookup(iop);
    if (!file) return 0;
    int result = fclose(file);
    owners[iop][iop->r[4] - 0x100] = nullptr;
    iop_return(iop, result ? -1 : 0);
    return 1;
}

extern "C" int ioman_read(iop_state *iop) {
    FILE *file = lookup(iop);
    if (!file) return 0;
    uint32_t pointer = iop->r[5], size = iop->r[6];
    if (size > 2 * 1024 * 1024 || pointer > UINT32_MAX - size) { iop_return(iop, -1); return 1; }
    unsigned char bytes[4096];
    uint32_t count = 0;
    while (count < size) {
        size_t requested = size - count;
        if (requested > sizeof bytes) requested = sizeof bytes;
        size_t got = fread(bytes, 1, requested, file);
        for (size_t i = 0; i < got; ++i) iop_write8(iop, pointer + count + i, bytes[i]);
        count += got;
        if (got < requested) break;
    }
    iop_return(iop, count);
    return 1;
}

extern "C" int ioman_write(iop_state *iop) {
    if (iop->r[4] != 1) return 0;
    uint32_t pointer = iop->r[5], size = iop->r[6] & 0xfff;
    for (uint32_t i = 0; i < size; ++i) {
        char value = iop_read8(iop, pointer + i);
        if (!value) break;
        if (iop->kputchar) iop->kputchar(iop->kputchar_udata, value);
    }
    iop_return(iop, size);
    return 1;
}

extern "C" int ioman_lseek(iop_state *iop) {
    FILE *file = lookup(iop);
    if (!file) return 0;
    uint32_t whence = iop->r[6];
    if (whence > 2) { iop_return(iop, -1); return 1; }
    const int origins[3] = {SEEK_SET, SEEK_CUR, SEEK_END};
    int result = fseek(file, int32_t(iop->r[5]), origins[whence]);
    iop_return(iop, result ? -1 : ftell(file));
    return 1;
}

#define UNHANDLED(name) extern "C" int name(iop_state *) { return 0; }
UNHANDLED(ioman_ioctl) UNHANDLED(ioman_remove) UNHANDLED(ioman_mkdir)
UNHANDLED(ioman_rmdir) UNHANDLED(ioman_dopen) UNHANDLED(ioman_dclose)
UNHANDLED(ioman_dread) UNHANDLED(ioman_getstat) UNHANDLED(ioman_chstat)
UNHANDLED(ioman_format) UNHANDLED(ioman_adddrv) UNHANDLED(ioman_deldrv)
UNHANDLED(ioman_stdioinit) UNHANDLED(ioman_rename) UNHANDLED(ioman_chdir)
UNHANDLED(ioman_sync) UNHANDLED(ioman_mount) UNHANDLED(ioman_umount)
UNHANDLED(ioman_lseek64) UNHANDLED(ioman_devctl) UNHANDLED(ioman_symlink)
UNHANDLED(ioman_readlink) UNHANDLED(ioman_ioctl2)
