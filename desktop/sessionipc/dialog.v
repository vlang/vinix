// SPDX-License-Identifier: GPL-2.0-or-later
module sessionipc

import desktop.sessioncore

pub fn dialog_open(key string, kind int, title string, directory string, filename string, filter string) bool {
	type_text := kind.str()
	args := [key, type_text, title, directory, filename, filter]
	defer {
		unsafe {
			type_text.free()
			(&array(&args)).free()
		}
	}
	return session_call_ok('dialog.open', args)
}

pub fn dialog_take(key string) ?string {
	args := [key]
	reply := session_call('dialog.take', args) or {
		unsafe { (&array(&args)).free() }
		return ''
	}
	defer {
		unsafe {
			(&array(&args)).free()
			reply.free()
		}
	}
	if reply == 'pending' { return none }
	f := sessioncore.fields(reply) or { return '' }
	if f.count != 2 || f.values[0] != 'selected' { return '' }
	path := sessioncore.unfield(f.values[1]) or { return '' }
	return path.str().clone()
}

pub fn offer_data(kind sessioncore.DataKind, data string, sensitive bool) bool {
	fd := session_connect() or { return false }
	defer { desktop_close(fd) }
	mut w := sessioncore.Writer{}
	w.add('clipboard.offer\t')
	w.number(int(kind))
	w.add('\t')
	w.number(int(sensitive))
	w.add('\t')
	w.field(data)
	request := w.finish()
	defer { unsafe { request.free() } }
	if !session_send_message(fd, request) { return false }
	reply := session_receive(fd) or { return false }
	defer { unsafe { reply.free() } }
	return reply == 'ok'
}
