// SPDX-License-Identifier: GPL-2.0-or-later
module anscore

import klock

fn query(index u32, identify &u8, data &u8) i32 {
	mut operation_lock := klock.Lock{}
	operation_lock.acquire()
	defer { operation_lock.release() }
	return health(index, identify, data)
}

fn test_ans_payloads_cache_ownership_and_200_query_phase_wraps() {
	model := model_setup(0, 0, 0x80)
	defer { model_free(model) }
	mut identify := [514]u8{}
	mut data := [514]u8{}
	identify[0] = 0xa5
	identify[513] = 0xa5
	data[0] = 0xa5
	data[513] = 0xa5
	for cycle in 0 .. 200 {
		assert query(u32(cycle % 2), unsafe { &identify[1] }, unsafe { &data[1] }) == 0
		for i in 0 .. 512 {
			assert identify[i + 1] == u8(i * 17 + 6)
			assert data[i + 1] == if i == 0 { u8(0x80) } else { u8(i * 17 + 2) }
		}
	}
	assert identify[0] == 0xa5 && identify[513] == 0xa5 && data[0] == 0xa5 && data[513] == 0xa5
	assert model.commands == 400 && model.pre == 400 && model.post == 400 && model.invalidated == 400
	assert ans_controller.queues[0].head == model.head && ans_controller.queues[0].phase == model.phase
	assert ans_controller.dead == 0 && ans_controller.write_enabled == 0
}

fn test_ans_log_whitelist_rejects_every_command_extension_before_doorbell() {
	model := model_setup(0, 0, 0)
	defer { model_free(model) }
	mut command := [64]u8{}
	command[0] = 2
	a_put32(unsafe { &command[4] }, 0xffffffff)
	a_put64(unsafe { &command[24] }, 0x800020000)
	a_put32(unsafe { &command[40] }, 0x007f8002)
	assert a_authorize(unsafe { &ans_controller }, 0, unsafe { &command[0] }) == 1
	for byte in 0 .. 64 {
		if byte in [2, 3]! { continue } // Submission replaces the command tag.
		for bit in 0 .. 8 {
			command[byte] ^= u8(1 << bit)
			assert a_authorize(unsafe { &ans_controller }, 0, unsafe { &command[0] }) == 0
			assert a_submit(unsafe { &ans_controller }, 0, unsafe { &command[0] }, unsafe { nil }) == -ans_read_only
			command[byte] ^= u8(1 << bit)
		}
	}
	assert model.commands == 0 && ans_controller.dead == 0
}

fn test_ans_completed_errors_allow_retry_but_fatal_failures_pin_dma() {
	for mode in 1 .. 9 {
		for step in 1 .. 3 {
			mut model := model_setup(mode, step, 0)
			mut identify := [512]u8{}
			mut data := [512]u8{}
			result := query(0, unsafe { &identify[0] }, unsafe { &data[0] })
			assert result < 0
			if mode == 1 {
				assert result == -ans_completion && ans_controller.dead == 0
				model.mode = 0
				assert query(0, unsafe { &identify[0] }, unsafe { &data[0] }) == 0
			} else {
				assert ans_controller.dead != 0
				commands := model.commands
				pre := model.pre
				mut saved := [4096]u8{}
				unsafe { C.memcpy(&saved[0], model.dma + 131072, 4096) }
				for _ in 0 .. 200 {
					assert query(0, unsafe { &identify[0] }, unsafe { &data[0] }) == result
				}
				assert model.commands == commands && model.pre == pre
				assert unsafe { C.memcmp(&saved[0], model.dma + 131072, 4096) } == 0
			}
			model_free(model)
		}
	}
}

fn test_ans_invalid_arguments_and_shutdown_touch_no_dma() {
	model := model_setup(0, 0, 0)
	defer { model_free(model) }
	mut identify := [512]u8{}
	mut data := [512]u8{}
	assert query(2, unsafe { &identify[0] }, unsafe { &data[0] }) == -ans_namespace
	assert query(0, unsafe { nil }, unsafe { &data[0] }) == -ans_range
	assert query(0, unsafe { &identify[0] }, unsafe { nil }) == -ans_range
	ans_controller.stopping = 1
	assert query(0, unsafe { &identify[0] }, unsafe { &data[0] }) == -ans_stopped
	ans_controller.stopping = 0
	ans_controller.stopped = 1
	assert query(0, unsafe { &identify[0] }, unsafe { &data[0] }) == -ans_stopped
	ans_controller.stopped = 0
	ans_controller.live = 0
	assert query(0, unsafe { &identify[0] }, unsafe { &data[0] }) == -ans_namespace
	assert model.commands == 0 && model.pre == 0
}
