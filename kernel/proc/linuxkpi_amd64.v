// SPDX-License-Identifier: GPL-2.0-or-later
module proc

fn C.vinix_linuxkpi_task_init(voidptr, voidptr, int, int, voidptr, u64)
fn C.vinix_linuxkpi_task_inherit(voidptr, voidptr, int, int, voidptr)
fn C.vinix_linuxkpi_task_view(voidptr, voidptr, int, int, voidptr, u64, bool) voidptr

// Called by the three thread constructors before the thread can run.
// Fresh-process/exec construction owns the program name; clone inherits a
// snapshot from its running source rather than reading a mutable process name.
pub fn linuxkpi_init_task(mut t Thread, source &Thread) {
	$if linuxkpi ? {
		storage := voidptr(&t.linuxkpi_task[0])
		if source != unsafe { nil } {
			mut parent := unsafe { source }
			name := parent.comm
			view := C.vinix_linuxkpi_task_view(voidptr(&parent.linuxkpi_task[0]), voidptr(parent),
				parent.tid, parent.process.pid, name.str, u64(name.len), false)
			C.vinix_linuxkpi_task_inherit(storage, voidptr(t), t.tid, t.process.pid, view)
		} else {
			name := t.process.name
			start, end := command_name_bounds(name)
			if end > start {
				C.vinix_linuxkpi_task_init(storage, voidptr(t), t.tid, t.process.pid,
					unsafe { name.str + start }, u64(end - start))
			} else {
				C.vinix_linuxkpi_task_init(storage, voidptr(t), t.tid, t.process.pid, c'vinix',
					5)
			}
		}
	}
}
