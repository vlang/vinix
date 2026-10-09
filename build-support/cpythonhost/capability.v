// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

// Host libraries select the CPython object backend at compile time.
pub fn enabled() bool {
	$if cpython_host ? {
		return true
	} $else {
		return false
	}
}
