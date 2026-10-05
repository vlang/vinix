// SPDX-License-Identifier: GPL-2.0-or-later
module linuxkpi

import kprint
import krandom
import sched

@[export: 'vinix_linuxkpi_log_write']
fn log_write(text &char, length usize) {
	assert may_sleep()
	kprint.kwrite(text, u64(length))
}

@[export: 'vinix_linuxkpi_log_key']
fn log_key(output &u64) bool {
	assert may_sleep()
	// The logger starts before the CSPRNG. Only the permanent drain worker
	// retries this call; producers use the original ptrval placeholder until
	// a secure key has been copied into immutable C storage.
	return krandom.fill(voidptr(output), 2 * sizeof(u64), false)
}

@[export: 'vinix_linuxkpi_log_caller']
fn log_caller() u64 {
	// Native kernel pthread TIDs are zero and Thread pointers can be reused.
	// Until a generation identity exists, preserve independent records.
	return 0
}

@[export: 'vinix_linuxkpi_test_printk_locks']
fn test_printk_locks() int {
	assert may_sleep()
	if sched.linuxkpi_test_log_capture() != 0 {
		return -1
	}
	return kprint.linuxkpi_test_log_capture()
}
