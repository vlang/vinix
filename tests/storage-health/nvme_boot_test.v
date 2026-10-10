// SPDX-License-Identifier: GPL-2.0-or-later
module nvme

import memory
import x86.hpet as hpet_clock

__global boot_pair &NVMEQueuePair
__global boot_commands int

fn boot_tick() {
	mut pair:=boot_pair
	previous:=if pair.sq_tail==0 { pair.entry_cnt-1 } else { pair.sq_tail-1 }
	command:=unsafe { pair.submission_queue[previous] }
	if command.opcode==opcode_create_cq {
		assert unsafe { command.private.create_cq.cq_flags==1
			&& command.private.create_cq.irq_vector==0
			&& command.private.create_cq.cqid==1 && command.private.create_cq.qsize==1 }
	} else {
		assert command.opcode==opcode_create_sq
		assert unsafe { command.private.create_sq.cqid==1 && command.private.create_sq.sqid==1
			&& command.private.create_sq.qsize==1 }
	}
	boot_commands++
	unsafe {
		pair.completion_queue[pair.cq_head]=NVMECompletion{cid:command.cid,sq_id:u16(pair.qid),
			sq_head:u16(pair.sq_tail),status:if pair.phase { u16(1) } else { u16(0) }}
	}
}

fn test_high_bar_mapping_is_uncached_bounded_and_propagates_mapping_failure() {
	kernel_pagemap=memory.Pagemap{}
	assert map_registers(0xc000004000,4112)==0xffff80c000004000
	assert kernel_pagemap.calls==2 && kernel_pagemap.last_phys==0xc000005000
	assert kernel_pagemap.last_virt==0xffff80c000005000
	assert kernel_pagemap.flags==memory.pte_present | memory.pte_writable | memory.pte_noexec | 24
	for pair in [[u64(0),4096]!,[u64(4096),0]!,[u64(4096),1024*1024+1]!,[u64(-1),4096]!]! {
		assert map_registers(pair[0],pair[1])==0 && kernel_pagemap.calls==2
	}
	kernel_pagemap.fail=true
	assert map_registers(0xc000004000,4096)==0 && kernel_pagemap.calls==3
	kernel_pagemap.fail=false
}

fn test_real_io_queue_creation_keeps_completion_interrupts_disabled() {
	memory.fail_alloc=false
	mut controller:=&NVMEController{regs:unsafe { &NVMERegisters(calloc(1,8192)) },
		controller_id:unsafe { nil },admin_queue:unsafe { nil },queue_entries:2}
	mut admin:=&NVMEQueuePair{qid:0,entry_cnt:2,phase:true,parent_controller:controller,
		submission_queue:unsafe { &NVMECommand(calloc(2,sizeof(NVMECommand))) },
		completion_queue:unsafe { &NVMECompletion(calloc(2,sizeof(NVMECompletion))) },
		submission_doorbell:unsafe { &u32(calloc(1,4)) },completion_doorbell:unsafe { &u32(calloc(1,4)) }}
	admin.cid_bitmap.initialise(2)
	controller.qid_bitmap.initialise(4)
	assert (controller.qid_bitmap.alloc() or { u64(-1) })==0
	controller.admin_queue=admin
	boot_pair=admin; boot_commands=0
	hpet_clock.set_hook(boot_tick)
	mut io:=NVMEQueuePair{parent_controller:unsafe { nil },submission_queue:unsafe { nil },
		completion_queue:unsafe { nil },submission_doorbell:unsafe { nil },completion_doorbell:unsafe { nil }}
	before:=memory.allocated_pages()
	assert io.initialise(mut controller,0,0,false)==0 && io.qid==1 && boot_commands==2
	assert memory.allocated_pages()==before+2
	memory.pmm_free(io.submission_queue,1)
	memory.pmm_free(io.completion_queue,1)
}

fn test_doorbells_accept_maximum_stride_without_mapping_gaps_or_trailing_stride() {
	kernel_pagemap=memory.Pagemap{}
	assert map_doorbells(0xc000004000,512*1024,15)
	assert kernel_pagemap.calls==4 && kernel_pagemap.last_phys==0xc000065000
	kernel_pagemap=memory.Pagemap{}
	assert map_doorbells(0xc000004000,4112,0) && kernel_pagemap.calls==1
	for pair in [[u64(4111),0]!,[u64(512*1024),16]!,[u64(0x61003),15]!]! {
		assert !map_doorbells(0xc000004000,pair[0],pair[1]) && kernel_pagemap.calls==1
	}
	assert !map_doorbells(u64(-1)-4096,8192,0) && kernel_pagemap.calls==1
	kernel_pagemap.fail=true
	assert !map_doorbells(0xc000004000,8192,0) && kernel_pagemap.calls==2
}
