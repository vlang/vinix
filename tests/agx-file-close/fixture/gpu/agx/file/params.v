// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.ioctl
import gpu.agx.gpu
import usercopy

__global parameter_builds = 0

// The response layout/content formatter is injected; the production request
// handler and shared checked-copy helper execute unchanged.
fn make_global_params(manager &gpu.GpuManager) ioctl.DrmAsahiParamsGlobal {
	_ = manager
	parameter_builds++
	mut value := ioctl.DrmAsahiParamsGlobal{}
	unsafe { C.memset(&value, 0xa7, sizeof(ioctl.DrmAsahiParamsGlobal)) }
	return value
}

fn check_global_params() {
	gpu.available(true)
	supported := u64(sizeof(ioctl.DrmAsahiParamsGlobal))
	assert supported + 64 <= 1024
	mut cases := 0
	mut file := GpuFile{}
	for _ in 0 .. 200 {
		for size in [u64(0), 1, 7, 63, supported - 1, supported, supported + 1, ~u64(0)]! {
			for offset in [u64(0), 1, 7]! {
				for fault in [-1, 0, 17, int(supported / 2)]! {
					mut buffer := [1024]u8{}
					unsafe { C.memset(&buffer[0], 0x5c, sizeof(buffer)) }
					pointer := u64(unsafe { &buffer[0] }) + offset
					mut request := ioctl.DrmAsahiGetParams{ pointer: pointer, size: size }
					before := request
					usercopy.configure(u64(unsafe { &buffer[0] }), u64(sizeof(buffer)), fault)
					count := if size < supported { size } else { supported }
					copied := if fault >= 0 && u64(fault) < count { u64(fault) } else { count }
					expected := if copied == count { 0 } else { -14 }
					lookups := gpu.lookups(); builds := parameter_builds
					result := file.ioctl_get_params(unsafe { &request })
					assert result == expected, 'GET_PARAMS copy expected ${expected}, got ${result}'
					assert request == before, 'GET_PARAMS size and request fields must remain input-only'
					assert usercopy.calls() == 1 && usercopy.bytes() == count && usercopy.address() == pointer
					assert gpu.lookups() == lookups + 1 && parameter_builds == builds + 1
					for i := u64(0); i < u64(sizeof(buffer)); i++ {
						assert buffer[i] == if i >= offset && i - offset < copied { u8(0xa7) } else { u8(0x5c) }
					}
					cases++
				}
			}
			// Zero length does not inspect even a null/invalid address. Any
			// nonzero prefix faults and keeps both the input header and buffer.
			for pointer in [u64(0), 1, u64(1) << 63, ~u64(0)]! {
				mut buffer := [32]u8{}
				usercopy.configure(u64(unsafe { &buffer[0] }), sizeof(buffer), -1)
				mut request := ioctl.DrmAsahiGetParams{ pointer: pointer, size: size }
				before := request
				assert file.ioctl_get_params(unsafe { &request }) == if size == 0 { 0 } else { -14 }
				assert request == before && usercopy.calls() == 1
				for byte in buffer { assert byte == 0 }
				cases++
			}
			for invalid in 0 .. 4 {
				mut request := ioctl.DrmAsahiGetParams{ pointer: ~u64(0), size: size }
				match invalid {
					0 { request.extensions = 1 }
					1 { request.pad = 1 }
					2 { request.param_group = 1 }
					else { request.param_group = ~u32(0) }
				}
				before := request
				lookups := gpu.lookups(); builds := parameter_builds
				usercopy.configure(0, 0, 0)
				assert file.ioctl_get_params(unsafe { &request }) == -22 && request == before
				assert usercopy.calls() == 0 && gpu.lookups() == lookups && parameter_builds == builds
				cases++
			}
			gpu.available(false)
			mut request := ioctl.DrmAsahiGetParams{ pointer: 0, size: size }
			before := request; builds := parameter_builds
			usercopy.configure(0, 0, 0)
			assert file.ioctl_get_params(unsafe { &request }) == -19 && request == before
			assert usercopy.calls() == 0 && parameter_builds == builds
			gpu.available(true); cases++
		}
	}
	println('AGX GET_PARAMS copies: ${cases} ioctl checks; zero/null queries, bounded aligned/unaligned prefixes, oversized inputs, unchanged headers/tails, partial EFAULT output and header/device precedence passed')
}
