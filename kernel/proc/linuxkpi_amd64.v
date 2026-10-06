// SPDX-License-Identifier: GPL-2.0-or-later
module proc

fn C.vinix_linuxkpi_task_init(voidptr, voidptr, i32, i32, voidptr, u64)
fn C.vinix_linuxkpi_task_inherit(voidptr, voidptr, i32, i32, voidptr)
fn C.vinix_linuxkpi_task_view(voidptr, voidptr, i32, i32, voidptr, u64, bool) voidptr
fn C.vinix_linuxkpi_task_dead(voidptr)

pub fn linuxkpi_mark_task_dead(mut t Thread) {
	$if linuxkpi ? {
		C.vinix_linuxkpi_task_dead(voidptr(&t.linuxkpi_task[0]))
	}
}

// Called by the three thread constructors before the thread can run.
// Fresh-process/exec construction owns the program name; clone inherits a
// snapshot from its running source rather than reading a mutable process name.
pub fn linuxkpi_init_task(mut t Thread, source &Thread) {
	$if linuxkpi ? {
		// A clone inherits ordinary task attributes, never its parent's live
		// kernel no-fault scope. Kernel workers and exec tasks also start clear.
		t.linuxkpi_fault_depth = 0
		storage := voidptr(&t.linuxkpi_task[0])
		if source != unsafe { nil } {
			mut parent := unsafe { source }
			name := parent.comm
			view := C.vinix_linuxkpi_task_view(voidptr(&parent.linuxkpi_task[0]), voidptr(parent),
				i32(parent.tid), i32(parent.process.pid), name.str, u64(name.len), false)
			C.vinix_linuxkpi_task_inherit(storage, voidptr(t), i32(t.tid), i32(t.process.pid), view)
		} else {
			name := t.process.name
			start, end := command_name_bounds(name)
			if end > start {
				C.vinix_linuxkpi_task_init(storage, voidptr(t), i32(t.tid), i32(t.process.pid),
					unsafe { name.str + start }, u64(end - start))
			} else {
				C.vinix_linuxkpi_task_init(storage, voidptr(t), i32(t.tid), i32(t.process.pid), c'vinix',
					5)
			}
		}
	}
}
