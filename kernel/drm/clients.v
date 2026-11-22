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

		description.drm_client_process = proc.process_identity(opener)
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

// After ioctl admission and copy-in, attribute the client to the caller.
// This only changes the identity displayed in debugfs.
fn update_client_process(handle voidptr) {
	if handle == unsafe { nil } { return }
	mut description := unsafe { &file.Handle(handle) }
	if description.drm_client_id == 0 { return }
	identity := proc.process_identity(proc.current_thread().process)
	description.l.acquire()
	description.drm_client_process = identity
	description.l.release()
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

// The fixed widths in drm_clients_info(), including the largest u32 UID.
const client_row_max = 20 + 1 + 5 + 1 + 3 + 3 + 1 + 4 + 1 + 1 + 10 + 1 + 10 + 1 +
	file.drm_client_name_max_len + 1 + 20 + 1

struct ClientRow {
mut:
	process proc.ProcessIdentity
	id u64
	minor u8
	authenticated bool
	name [file.drm_client_name_max_len]u8
	name_len u8
}

fn show_clients(context voidptr, mut text lib.Text) {
	mut dev := unsafe { &DrmDevice(context) }
	add_client_column(mut text, 'command', 20)
	text.add('  tgid dev master a   uid      magic ')
	add_client_column(mut text, 'name', file.drm_client_name_max_len)
	text.add_byte(` `)
	add_client_column(mut text, 'id', 20)
	text.add_byte(`\n`)

	// Copy only inline data under the list lock. Looking up processes and
	// building output afterwards keeps the list independent of their locks.
	mut rows := []ClientRow{} @[freed]
	defer { unsafe { rows.free() } }
	dev.clients_lock.acquire()
	for dev.clients_count > rows.len {
		count := dev.clients_count
		dev.clients_lock.release()
		unsafe { rows.free() }
		rows = []ClientRow{len: count} @[freed]
		dev.clients_lock.acquire()
	}
	mut description := dev.clients_first
	count := dev.clients_count
	for i in 0 .. count {
		mut row := unsafe { &rows[i] }
		row.id = description.drm_client_id
		row.minor = u8(description.resource.stat.rdev)
		row.authenticated = description.drm_client_authenticated
		description.l.acquire()
		row.process = description.drm_client_process
		row.name = description.drm_client_name
		row.name_len = description.drm_client_name_len
		description.l.release()
		description = description.drm_client_next
	}
	dev.clients_lock.release()
	text.reserve(count * client_row_max)
	for i in 0 .. count {
		add_client_row(mut text, unsafe { &rows[i] })
	}
}

fn add_client_row(mut text lib.Text, row &ClientRow) {
	mut comm := [16]u8{}
	pid, uid, live := proc.copy_process_identity(row.process, unsafe { &comm[0] })
	mut length := 0
	for length < comm.len && comm[length] != 0 {
		length++
	}
	command := if live { unsafe { tos(&comm[0], length) } } else { '<unknown>' }
	add_client_column(mut text, command, 20)
	text.add_byte(` `)
	add_client_number(mut text, u64(pid), 5)
	text.add_byte(` `)
	add_client_number(mut text, u64(row.minor), 3)
	// Legacy DRM master and GET_MAGIC/AUTH_MAGIC are absent. The auth
	// bit records the same initial CAP_SYS_ADMIN check as drm_file_alloc().
	text.add('   n    ')
	text.add_byte(if row.authenticated { `y` } else { `n` })
	text.add_byte(` `)
	add_client_number(mut text, u64(uid), 5)
	text.add('          0 ')

	client_name := if row.name_len == 0 { '<unset>' } else { unsafe { tos(&row.name[0], int(row.name_len)) } }
	add_client_column(mut text, client_name, file.drm_client_name_max_len)
	text.add_byte(` `)
	add_client_number(mut text, row.id, 20)
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
