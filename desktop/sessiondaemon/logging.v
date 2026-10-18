// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessioncore

// Print borrowed text directly. Interpolating an IError creates both its
// formatted representation and a log string under -gc none -manualfree.
fn session_log_error(prefix string, err IError) {
	message := err.msg()
	eprint(prefix)
	eprintln(message)
	session_release_error(err, message)
}

// Selector denials live in the immutable registry. Parser and handler errors
// are owned results; release their message and box after the last consumer.
fn session_release_error(err IError, message string) {
	if sessioncore.session_error_is_shared(err) { return }
	unsafe {
		message.free()
		err.free()
	}
}
