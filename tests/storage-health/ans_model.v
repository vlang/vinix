// SPDX-License-Identifier: GPL-2.0-or-later
// Independent MMIO/DMA model; submission, authorization and completion are real.
module anscore

import klock

#include <stdlib.h>

fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.posix_memalign(&voidptr, usize, usize) int

pub struct HealthModel {
pub mut:
	dma         &u8 = unsafe { nil }
	commands    int
	mode        int
	step        int
	warning     u8
	head        u32
	phase       u32 = 1
	clock       u64
	pre         int
	post        int
	invalidated int
	prepared    bool
}

pub fn model_setup(mode int, step int, warning u8) &HealthModel {
	mut pointer := unsafe { nil }
	health_model_require(C.posix_memalign(&pointer, 16384, 4587520) == 0)
	unsafe { C.memset(pointer, 0, 4587520) }
	mut model := unsafe { &HealthModel(C.calloc(1, sizeof(HealthModel))) }
	unsafe { *model = HealthModel{ dma: &u8(pointer), mode: mode, step: step, warning: warning } }
	// Ans includes every GPT partition: avoid a controller-sized stack
	// temporary in the opt-in kernel fixture's setup and retirement paths.
	unsafe { C.memset(&ans_controller, 0, sizeof(Ans)) }
	ans_controller.dma = model.dma
	ans_controller.physical = 0x800000000
	ans_controller.cookie = model
	ans_controller.nvme = 0x100000
	ans_controller.mailbox = 0x200000
	ans_controller.live = 1
	ans_controller.nns = 2
	ans_controller.queues[0].phase = 1
	ans_controller.queues[1].phase = 1
	ans_controller.ops = Ans_ops{
		read32:  health_read32
		read64:  health_read64
		write32: health_write32
		write64: health_write64
		now:     health_now
		delay:   health_delay
		sync:    health_sync
	}
	return model
}

pub fn model_free(model &HealthModel) {
	assert klock.depth == 0
	unsafe {
		C.free(model.dma)
		C.free(model)
	}
	unsafe { C.memset(&ans_controller, 0, sizeof(Ans)) }
}

fn health_read32(cookie voidptr, address u64) u32 {
	model := unsafe { &HealthModel(cookie) }
	if address == 0x200114 { return 1 << 17 } // Empty RTKit mailbox.
	if address == 0x10001c {
		return if model.mode == 8 && model.commands == model.step { u32(3) } else { u32(1) }
	}
	health_model_require(address == 0x128120)
	return if model.mode == 7 && model.commands == model.step { u32(1) } else { u32(0) }
}

fn health_read64(_ voidptr, _ u64) u64 {
	health_model_require(false)
	return 0
}

fn health_write64(_ voidptr, _ u64, _ u64) { health_model_require(false) }

fn health_write32(cookie voidptr, address u64, value u32) {
	unsafe {
		mut model := &HealthModel(cookie)
		assert klock.depth == 1
		if address == 0x101004 {
			health_model_require(value == model.head)
			return
		}
		if address == 0x128118 {
			health_model_require(value == 0)
			for i in 0 .. 128 { health_model_require(model.dma[32768 + i] == 0) }
			model.invalidated++
			return
		}
		health_model_require(address == 0x12490c && value == 0) // Admin queue, fixed tag 0.
		command := model.dma
		tcb := model.dma + 32768
		health_model_require(command[1] == 0 && a_le16(command + 2) == 0)
		health_model_require(a_le64(command + 24) == 0x800020000 && a_le64(command + 32) == 0)
		health_model_require(tcb[0] == 0 && tcb[1] == 1 && tcb[2] == 0)
		health_model_require(a_le16(tcb + 4) == 0)
		health_model_require(a_le64(tcb + 24) == 0x800020000 && a_le64(tcb + 32) == 0)
		for i in 8 .. 24 { health_model_require(command[i] == 0) }
		for i in 44 .. 64 { health_model_require(command[i] == 0) }
		for i in 40 .. 128 { health_model_require(tcb[i] == 0) }
		health_model_require(model.prepared)
		model.prepared = false
		bytes := if command[0] == 6 { 4096 } else { 512 }
		if command[0] == 6 {
			health_model_require(a_le32(command + 4) == 0 && a_le32(command + 40) == 1)
		} else {
			health_model_require(command[0] == 2 && a_le32(command + 4) == 0xffffffff)
			health_model_require(a_le32(command + 40) == 0x007f8002)
		}
		for i in 0 .. bytes { health_model_require(model.dma[131072 + i] == 0) }
		model.commands++
		if model.mode in [2, 3]! && model.commands == model.step { return }
		for i in 0 .. bytes { model.dma[131072 + i] = u8(i * 17 + int(command[0])) }
		if command[0] == 2 { model.dma[131072] = model.warning }
		entry := model.dma + 16384 + model.head * 16
		a_zero(entry, 16)
		a_put16(entry + 8, if model.mode == 6 && model.commands == model.step {
			u16(2)
		} else {
			u16(0)
		})
		a_put16(entry + 10, if model.mode == 5 && model.commands == model.step {
			u16(1)
		} else {
			u16(0)
		})
		a_put16(entry + 12, if model.mode == 4 && model.commands == model.step {
			u16(1)
		} else {
			u16(0)
		})
		status := if model.mode == 1 && model.commands == model.step { u16(2) } else { u16(0) }
		a_put16(entry + 14, status | u16(model.phase))
		model.head++
		if model.head == 2 {
			model.head = 0
			model.phase ^= 1
		}
	}
}

fn health_now(cookie voidptr) u64 {
	mut model := unsafe { &HealthModel(cookie) }
	if model.mode != 3 { model.clock += 1000000 }
	return model.clock
}

fn health_delay(_ voidptr, _ u32) {}

fn health_sync(cookie voidptr, buffer voidptr, count usize, cpu i32) {
	mut model := unsafe { &HealthModel(cookie) }
	assert klock.depth == 1
	address := usize(buffer) - usize(model.dma)
	health_model_require(address + count <= 4587520)
	if address == 131072 {
		health_model_require(count == 512 || count == 4096)
		if cpu == 0 {
			model.pre++
			model.prepared = true
		} else {
			model.post++
		}
	}
}

fn health_model_require(condition bool) {
	if !condition { panic('ANS health model oracle failed') }
}

@[export: 'vinix_account_disk_transfer']
fn account(_ u32, _ u64, _ i32) { health_model_require(false) }
