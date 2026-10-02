// SPDX-License-Identifier: GPL-2.0-or-later
module kprint

import errno

fn C.vinix_linuxkpi_printk_locked_probe() int

pub fn linuxkpi_test_log_capture() int {
	$if linuxkpi ? {
		kprint_lock.acquire()
		result := C.vinix_linuxkpi_printk_locked_probe()
		kprint_lock.release()
		return result
	}
	return -errno.eopnotsupp
}
