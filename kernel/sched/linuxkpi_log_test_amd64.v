// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import errno

fn C.vinix_linuxkpi_printk_locked_probe() int

pub fn linuxkpi_test_log_capture() int {
	$if linuxkpi ? {
		scheduler_queue_lock.acquire()
		result := C.vinix_linuxkpi_printk_locked_probe()
		scheduler_queue_lock.release()
		return result
	}
	return -errno.eopnotsupp
}
