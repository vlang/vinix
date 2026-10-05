// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native DRM device model for the Venus capability probe.
@[translated]
module probefixture

#include <drm.h>
#include <virtgpu_drm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
$if probe_native_guest ? {
    #include <unistd.h>
    fn C.open(&char, i32, ...voidptr) i32
    fn C.dup2(i32, i32) i32
    fn C.close(i32) i32
}
struct C.drm_version { version_major i32, version_minor i32, version_patchlevel i32, name_len usize, name &char, date_len usize, date &char, desc_len usize, desc &char }
struct C.drm_virtgpu_getparam { param u64, value u64 }
fn C.vinix_venus_probe() i32
fn C.printf(&char, ...voidptr) i32
fn C.abort()
fn C.strncmp(&char, &char, usize) i32
fn C.strtol(&char, voidptr, i32) isize
fn C.memcpy(voidptr, voidptr, usize) voidptr
__global probe_failure i32
__global probe_opens i32
__global probe_closes i32
__global probe_queries i32
__global probe_active_fd i32
fn check(value bool) { if !value { C.abort() } }
@[export: 'vhs_open']
pub fn open(path &char, flags i32) i32 {
    unsafe {
        check(C.strncmp(path, c'/dev/dri/renderD', 16) == 0 && flags == (C.O_RDWR | C.O_CLOEXEC))
        index := i32(C.strtol(path + 16, nil, 10))
        check(index == 128 + probe_opens && probe_active_fd == 0)
        probe_opens++
        if probe_failure == 1 { return -1 }
        probe_active_fd = 64 + index
        return probe_active_fd
    }
}
@[export: 'vhs_close']
pub fn close(fd i32) i32 { check(fd != 0 && fd == probe_active_fd); probe_active_fd = 0; probe_closes++; return 0 }
fn ioctl_model(fd i32, request usize, storage voidptr) i32 {
    unsafe {
        check(fd != 0 && fd == probe_active_fd)
        probe_queries++
        if request == usize(C.DRM_IOCTL_VERSION) {
            mut version := &C.drm_version(storage)
            check(version.name_len == 31 && version.name != nil && version.version_major == 0 &&
                version.version_minor == 0 && version.version_patchlevel == 0 && version.date_len == 0 &&
                version.date == nil && version.desc_len == 0 && version.desc == nil)
            for index := 0; index < 32; index++ { check(version.name[index] == 0) }
            if probe_failure == 2 || (probe_failure == 11 && fd != 64 + 143) { return -1 }
            if probe_failure == 3 { C.memcpy(version.name, c'other_gpu', 10) }
            else { C.memcpy(version.name, c'virtio_gpu', 11) }
            return 0
        }
        check(request == usize(C.DRM_IOCTL_VIRTGPU_GETPARAM))
        mut query := &C.drm_virtgpu_getparam(storage)
        output := &u64(usize(query.value))
        check(output != nil && *output == 0)
        first := query.param == u64(C.VIRTGPU_PARAM_RESOURCE_BLOB)
        second := query.param == u64(C.VIRTGPU_PARAM_HOST_VISIBLE)
        third := query.param == u64(C.VIRTGPU_PARAM_CONTEXT_INIT)
        caps := query.param == u64(C.VIRTGPU_PARAM_SUPPORTED_CAPSET_IDs)
        check(first || second || third || caps)
        if (first && probe_failure == 4) || (second && probe_failure == 6) ||
            (third && probe_failure == 8) || (caps && probe_failure == 10) { return -1 }
        if (first && probe_failure == 5) || (second && probe_failure == 7) { return 0 }
        *output = if caps { if probe_failure == 9 { u64(1) } else { u64(16) } }
            else { if probe_failure == 12 { u64(1) << 63 } else { u64(1) } }
        return 0
    }
}
$if probe_darwin_arm64 ? {
    @[export: 'vhs_ioctl_body']
    pub fn ioctl(fd i32, request usize, storage voidptr) i32 { return ioctl_model(fd, request, storage) }
} $else {
    @[export: 'vhs_ioctl']
    pub fn ioctl(fd i32, request usize, storage voidptr) i32 { return ioctl_model(fd, request, storage) }
}
@[export: 'main']
pub fn fixture() i32 {
    $if probe_native_guest ? {
        // Only the fixture routes its verdict to native serial; production
        // probing keeps its original quiet return-value interface.
        serial := C.open(c'/dev/com1', C.O_WRONLY)
        if serial >= 0 { C.dup2(serial, 1); C.dup2(serial, 2); C.close(serial) }
    }
    for failure := i32(0); failure <= 12; failure++ {
        probe_failure = failure; probe_opens = 0; probe_closes = 0; probe_queries = 0
        outcome := C.vinix_venus_probe()
        success := failure == 0 || failure == 11 || failure == 12
        check(outcome == if success { 0 } else { 1 })
        check(probe_active_fd == 0 && probe_opens == if failure == 0 || failure == 12 { 1 } else { 16 })
        check(probe_closes == if failure == 1 { 0 } else { probe_opens })
        expected_queries := match failure {
            0, 12 { 5 } 1 { 0 } 2, 3 { 16 } 4, 5 { 32 } 6, 7 { 48 } 8 { 64 } 11 { 20 } else { 80 }
        }
        check(probe_queries == expected_queries)
        C.printf(c'VENUS CASE %d: %d opens=%d closes=%d queries=%d\n', failure, outcome, probe_opens, probe_closes, probe_queries)
    }
    C.printf(c'VENUS PROBE PASS\n'); return 0
}
