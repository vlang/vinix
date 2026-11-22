// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import file
import katomic
import lib
import proc
import resource

__global drm_last_client_id = u64(0)

// Track the description before publishing it in the fd table. A failed
// publication and a final close both release it through DrmNode.unref().
pub fn add_client(mut description file.Handle, opener &proc.Process) {
	if description.flags & resource.o_path != 0 { return }
	res := description.resource
	if res == unsafe { nil } { return }
	if res is DrmNode {
		mut dev := unsafe { res.dev }
		if dev == unsafe { nil } { return }

		proc.copy_process_command(opener, unsafe { &description.drm_client_command[0] })
		description.drm_client_tgid = opener.pid
		description.drm_client_uid = opener.euid
		description.drm_client_authenticated = proc.has_capability(opener, proc.cap_sys_admin)

		dev.clients_lock.acquire()
		description.drm_client_id = katomic.inc(mut &drm_last_client_id) + 1
		description.drm_client_prev = dev.clients_last
		if dev.clients_last == unsafe { nil } {
			dev.clients_first = description
		} else {
			dev.clients_last.drm_client_next = description
		}
		dev.clients_last = description
		dev.clients_count++
		dev.clients_lock.release()
	}
}

// The list borrows the handle through its final resource close callback.
// Readers copy its data while holding clients_lock; no handle escapes it.
fn (mut dev DrmDevice) remove_client(mut description file.Handle) {
	dev.clients_lock.acquire()
	mut prev := description.drm_client_prev
	mut next := description.drm_client_next
	if prev == unsafe { nil } {
		dev.clients_first = next
	} else {
		prev.drm_client_next = next
	}
	if next == unsafe { nil } {
		dev.clients_last = prev
	} else {
		next.drm_client_prev = prev
	}
	dev.clients_count--
	dev.clients_lock.release()
}

// The fixed widths in drm_clients_info(), with up to ten digits for a u32
// UID. Reserve the complete read before walking the list with IRQs masked.
const client_row_max = 20 + 1 + 5 + 1 + 3 + 3 + 1 + 4 + 1 + 1 + 10 + 1 + 10 + 1 +
	file.drm_client_name_max_len + 1 + 20 + 1

fn show_clients(context voidptr, mut text lib.Text) {
	mut dev := unsafe { &DrmDevice(context) }
	add_client_column(mut text, 'command', 20)
	text.add('  tgid dev master a   uid      magic ')
	add_client_column(mut text, 'name', file.drm_client_name_max_len)
	text.add_byte(` `)
	add_client_column(mut text, 'id', 20)
	text.add_byte(`\n`)

	mut reserved := 0
	dev.clients_lock.acquire()
	for dev.clients_count > reserved {
		reserved = dev.clients_count
		dev.clients_lock.release()
		text.reserve(reserved * client_row_max)
		dev.clients_lock.acquire()
	}
	mut description := dev.clients_first
	for description != unsafe { nil } {
		add_client_row(mut text, mut description)
		description = description.drm_client_next
	}
	dev.clients_lock.release()
}

fn add_client_row(mut text lib.Text, mut description file.Handle) {
	mut length := 0
	for length < description.drm_client_command.len && description.drm_client_command[length] != 0 {
		length++
	}
	command := unsafe { tos(&description.drm_client_command[0], length) }
	add_client_column(mut text, command, 20)
	text.add_byte(` `)
	add_client_number(mut text, u64(description.drm_client_tgid), 5)
	text.add_byte(` `)
	add_client_number(mut text, description.resource.stat.rdev & 0xff, 3)
	// Legacy DRM master and GET_MAGIC/AUTH_MAGIC are absent. The auth
	// bit records the same initial CAP_SYS_ADMIN check as drm_file_alloc().
	text.add('   n    ')
	text.add_byte(if description.drm_client_authenticated { `y` } else { `n` })
	text.add_byte(` `)
	add_client_number(mut text, u64(description.drm_client_uid), 5)
	text.add('          0 ')

	description.l.acquire()
	name_len := int(description.drm_client_name_len)
	name := description.drm_client_name
	description.l.release()
	client_name := if name_len == 0 { '<unset>' } else { unsafe { tos(&name[0], name_len) } }
	add_client_column(mut text, client_name, file.drm_client_name_max_len)
	text.add_byte(` `)
	add_client_number(mut text, description.drm_client_id, 20)
	text.add_byte(`\n`)
}

fn add_client_column(mut text lib.Text, value string, width int) {
	for _ in value.len .. width { text.add_byte(` `) }
	text.add(value)
}

fn add_client_number(mut text lib.Text, value u64, width int) {
	mut padding := width - 1
	mut rest := value
	for rest >= 10 {
		rest /= 10
		padding--
	}
	for _ in 0 .. padding { text.add_byte(` `) }
	text.add_unsigned(value)
}
