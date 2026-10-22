// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import authproto

// The manual-free manager owns errors it handles rather than propagates.
fn discard_manager_error(err IError) {
	message := err.msg()
	unsafe { message.free(); err.free() }
}

fn report_manager_error(err IError, prefix string) {
	message := err.msg()
	line := prefix + message
	eprintln(line)
	unsafe { line.free(); message.free(); err.free() }
}

fn manager_failure(err IError) authproto.Frame {
	message := err.msg()
	answer := authproto.text_frame(authproto.status_failed, message)
	unsafe { message.free(); err.free() }
	return answer
}
