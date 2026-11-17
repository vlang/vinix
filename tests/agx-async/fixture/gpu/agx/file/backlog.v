module file

import drm.syncobj
import gpu.agx.gpu
import memory

fn check_queued_ioctl_backlog() {
	for render in [false, true]! {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		input := output()
		dependency := syncobj.new_fence(1, 1)
		syncobj.replace_fence(input, dependency)
		mut outputs := [8]&syncobj.SyncObj{}
		for index in 0 .. 8 {
			outputs[index] = output()
			commands := []ScheduledCommand{len: 64, init: ScheduledCommand{ compute: !render }}
			assert submit_scheduled_with_input(mut file, 1, commands, if index == 0 { input } else { unsafe { nil } }, outputs[index], false) == 0
		}
		independent := output()
		assert submit_scheduled_on_queue(mut file, 2, [ScheduledCommand{ compute: true }], independent, false) == 0
		assert file.vm.inflight == 522 && memory.outstanding() == 9
		service_file_work()
		assert manager.published_order == [u32(512)], 'a blocked512-job queue must not block another queue'
		assert manager.execute_firmware(512, 0)
		manager.retire_firmware(512)
		service_file_work()
		assert pending_count == 8 && file.vm.inflight == 520 && memory.outstanding() == 8
		syncobj.signal(dependency)
		service_file_work()
		for batch in 0 .. 8 {
			assert manager.published.len == 1 + (batch + 1) * 64
			for offset in 0 .. 64 { assert manager.execute_firmware(u32(batch * 64 + offset), 0) }
			service_file_work()
			assert manager.published.len == 1 + (batch + 1) * 64, 'firmware execution alone cannot grant host publication capacity'
			for offset := 63; offset >= 0; offset-- { manager.retire_firmware(u32(batch * 64 + offset)) }
			service_file_work()
			assert syncobj.is_signaled(fence(outputs[batch])) && syncobj.get_error(fence(outputs[batch])) == 0
		}
		assert_drained(file)
		syncobj.destroy_owner(file.owner_key)
	}
	println('AGX ioctl backlog: eight64-command compute/render batches snapshot input dependencies, keep FIFO/VM/node/fence ownership, admit by host credit and let independent queues progress')
}
