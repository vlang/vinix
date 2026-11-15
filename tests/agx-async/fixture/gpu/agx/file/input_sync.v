module file

import drm.ioctl
import drm.syncobj
import gpu.agx.gpu

// Exercise the real ioctl's snapshot of two inputs, in both orders and both
// signaling orders. The submission's own fault remains independent of either
// input's errno. Replacing the userspace syncobj cannot replace its snapshot.
fn check_input_sync_errors() {
	for error_first in [false, true]! {
		for signal_first in [false, true]! {
			for own_fault in [false, true]! {
				gpu.reset()
				mut file := new_file()
				mut manager := gpu.get_global_manager() or { panic('manager') }
				a, b, out := output(), output(), output()
				error_fence := syncobj.new_fence(1, 1)
				other_fence := syncobj.new_fence(2, 1)
				syncobj.replace_fence(a, error_fence)
				syncobj.replace_fence(b, other_fence)
				inputs := [ioctl.DrmAsahiSync{ handle: if error_first { a.handle } else { b.handle } },
					ioctl.DrmAsahiSync{ handle: if error_first { b.handle } else { a.handle } }]!
				output_sync := ioctl.DrmAsahiSync{ handle: out.handle }
				compute := ioctl.DrmAsahiCmdCompute{ encoder_ptr: 0x12340000 }
				command := ioctl.DrmAsahiCommand{
					cmd_type: ioctl.asahi_cmd_compute
					cmd_buffer: u64(&compute)
					cmd_buffer_size: sizeof(compute)
					barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]!
				}
				request := ioctl.DrmAsahiSubmit{
					queue_id: 1
					commands: u64(&command)
					command_count: 1
					in_syncs: unsafe { u64(&inputs) }
					in_sync_count: 2
					out_syncs: u64(&output_sync)
					out_sync_count: 1
				}
				assert file.ioctl_submit(&request) == 0
				service_file_work()
				assert manager.published.len == 0 && !syncobj.is_signaled(fence(out))
				if signal_first { syncobj.signal(other_fence) } else { syncobj.signal_error(error_fence, -5) }
				service_file_work()
				assert manager.published.len == 0 && !syncobj.is_signaled(fence(out))
				// A new signaled fence on the handle must not satisfy the old wait.
				replacement := syncobj.new_fence(3, 1)
				syncobj.signal_error(replacement, -22)
				syncobj.replace_fence(if signal_first { a } else { b }, replacement)
				service_file_work()
				assert manager.published.len == 0 && !syncobj.is_signaled(fence(out))
				if signal_first { syncobj.signal_error(error_fence, -5) } else { syncobj.signal(other_fence) }
				service_file_work()
				assert manager.published_order == [u32(0)] && !syncobj.is_signaled(fence(out))
				assert syncobj.get_error(error_fence) == -5
				assert manager.execute_firmware(0, if own_fault { 3 } else { 0 })
				manager.retire_firmware(0)
				service_file_work()
				assert syncobj.is_signaled(fence(out))
				assert syncobj.get_error(fence(out)) == if own_fault { -110 } else { 0 }
				assert_drained(file)
			}
		}
	}
	println('AGX input syncs: eight real-ioctl dependency/signal orders wait for all original fence snapshots, ignore input errno, and retain own GPU errors')
}
