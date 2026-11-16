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
	assert !gpu.query_lock_held(), 'GET_PARAMS must release the manager lock before formatting/copying'
	parameter_builds++
	mut value := ioctl.DrmAsahiParamsGlobal{}
	unsafe { C.memset(&value, 0xa7, sizeof(ioctl.DrmAsahiParamsGlobal)) }
	return value
}

fn check_global_params() {
	gpu.available(true)
	gpu.set_running(true)
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

fn check_global_params_device() {
	mut file := GpuFile{}
	mut cases := 0
	supported := u64(sizeof(ioctl.DrmAsahiParamsGlobal))
	for _ in 0 .. 200 {
		for state in [gpu.State.idle, .starting, .running, .error, .stopped]! {
			for size in [u64(0), 1, supported, ~u64(0)]! {
				for invalid_pointer in [false, true]! {
					gpu.available(true); gpu.set_query_state(state)
					mut buffer := [1024]u8{}
					assert supported <= u64(sizeof(buffer))
					pointer := if invalid_pointer { ~u64(0) } else { u64(unsafe { &buffer[0] }) }
					mut request := ioctl.DrmAsahiGetParams{ pointer: pointer, size: size }
					before := request; builds := parameter_builds; lookups := gpu.lookups()
					usercopy.configure(u64(unsafe { &buffer[0] }), sizeof(buffer), -1)
					lost := state in [.error, .stopped]
					expected := if lost { -19 } else if invalid_pointer && size != 0 { -14 } else { 0 }
					result := file.ioctl_get_params(unsafe { &request })
					assert result == expected, 'GET_PARAMS device expected ${expected}, got ${result}'
					assert request == before && gpu.lookups() == lookups + 1
					assert !gpu.query_lock_held()
					assert parameter_builds == builds + if lost { 0 } else { 1 }
					assert usercopy.calls() == if lost { 0 } else { 1 }
					for i := u64(0); i < u64(sizeof(buffer)); i++ {
						count := if size < supported { size } else { supported }
						assert buffer[i] == if !lost && !invalid_pointer && i < count { u8(0xa7) } else { u8(0) }
					}
					cases++
					// Header rejection still precedes device lookup even after loss.
					for invalid in 0 .. 3 {
						mut bad := before
						match invalid {
							0 { bad.extensions = 1 }
							1 { bad.pad = 1 }
							else { bad.param_group = 1 }
						}
						saved := bad; at_lookup := gpu.lookups(); at_build := parameter_builds
						usercopy.configure(0, 0, 0)
						assert file.ioctl_get_params(unsafe { &bad }) == -22 && bad == saved
						assert gpu.lookups() == at_lookup && parameter_builds == at_build && usercopy.calls() == 0
						assert !gpu.query_lock_held(); cases++
					}
				}
			}
		}
		// A transition after manager lookup but before acquiring its state lock
		// must win over even an invalid pointer or a zero-byte copy.
		for size in [u64(0), supported]! {
			for shutdown in [false, true]! {
				gpu.set_running(true)
				before_stops := gpu.stop_count()
				if shutdown { gpu.stop_during_mapping_lock() } else { gpu.fail_before_query_lock() }
				mut request := ioctl.DrmAsahiGetParams{ pointer: ~u64(0), size: size }
				before := request; builds := parameter_builds
				usercopy.configure(0, 0, 0)
				assert file.ioctl_get_params(unsafe { &request }) == -19
				assert request == before && parameter_builds == builds && usercopy.calls() == 0
				assert !gpu.query_lock_held()
				assert gpu.stop_count() == before_stops + if shutdown { 1 } else { 0 }
				cases++
			}
		}
	}
	gpu.set_running(true)
	println('AGX GET_PARAMS device loss: ${cases} ioctl checks; error/stopped ENODEV before formatting/copying, zero/invalid-pointer precedence, unchanged outputs, live-state controls, unlocked copies and deterministic failure/shutdown lock transitions passed')
}
