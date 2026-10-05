// SPDX-License-Identifier: GPL-2.0-or-later
// Query native virtio GPU capabilities without Vulkan or Linux sysfs.
@[translated]
module availablecore

#include <drm.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <virtgpu_drm.h>

struct C.drm_version { name_len usize, name &char }
struct C.drm_virtgpu_getparam { param u64, value u64 }
fn C.snprintf(&char, usize, &char, ...voidptr) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.ioctl(i32, usize, ...voidptr) i32
fn C.close(i32) i32
fn C.strcmp(&char, &char) i32

@[export: 'main']
pub fn probe() i32 {
    unsafe {
        for index := u32(128); index < 144; index++ {
            mut path := [40]char{}
            mut name := [32]char{}
            C.snprintf(&path[0], sizeof(path), c'/dev/dri/renderD%u', index)
            fd := C.open(&path[0], C.O_RDWR | C.O_CLOEXEC)
            if fd < 0 { continue }
            mut version := C.drm_version{name: &name[0], name_len: sizeof(name) - 1}
            mut ready := C.ioctl(fd, usize(C.DRM_IOCTL_VERSION), &version) == 0 &&
                C.strcmp(&name[0], c'virtio_gpu') == 0
            params := [u32(C.VIRTGPU_PARAM_RESOURCE_BLOB), u32(C.VIRTGPU_PARAM_HOST_VISIBLE),
                u32(C.VIRTGPU_PARAM_CONTEXT_INIT)]!
            for parameter := 0; ready && parameter < 3; parameter++ {
                mut value := u64(0)
                mut query := C.drm_virtgpu_getparam{param: u64(params[parameter]), value: u64(usize(&value))}
                ready = C.ioctl(fd, usize(C.DRM_IOCTL_VIRTGPU_GETPARAM), &query) == 0 && value != 0
            }
            mut capsets := u64(0)
            mut caps := C.drm_virtgpu_getparam{param: u64(C.VIRTGPU_PARAM_SUPPORTED_CAPSET_IDs),
                value: u64(usize(&capsets))}
            ready = ready && C.ioctl(fd, usize(C.DRM_IOCTL_VIRTGPU_GETPARAM), &caps) == 0 &&
                (capsets & (u32(1) << 4)) != 0
            C.close(fd)
            if ready { return 0 }
        }
        return 1
    }
}
