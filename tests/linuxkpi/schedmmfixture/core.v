// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module schedmmfixture

#include "contract.h"

struct C.task_struct {}

fn C.in_vfork(&C.task_struct) bool
fn C.current_gfp_context(u32) u32
fn C.memalloc_noio_save() u32
fn C.memalloc_noio_restore(u32)
fn C.memalloc_nofs_save() u32
fn C.memalloc_nofs_restore(u32)
fn C.memalloc_noreclaim_save() u32
fn C.memalloc_noreclaim_restore(u32)
fn C.memalloc_pin_save() u32
fn C.memalloc_pin_restore(u32)

// This caller must retain all ten genuine unresolved MM services. A successful
// standalone link would mean the declaration boundary invented MM behavior.
@[export: 'vinix_sched_mm_requires_runtime']
pub fn requires_runtime(task &C.task_struct, flags u32) u32 {
	noio := C.memalloc_noio_save()
	nofs := C.memalloc_nofs_save()
	noreclaim := C.memalloc_noreclaim_save()
	pin := C.memalloc_pin_save()
	context := C.current_gfp_context(flags)
	vfork := C.in_vfork(task)
	C.memalloc_pin_restore(pin)
	C.memalloc_noreclaim_restore(noreclaim)
	C.memalloc_nofs_restore(nofs)
	C.memalloc_noio_restore(noio)
	return context ^ u32(vfork)
}
