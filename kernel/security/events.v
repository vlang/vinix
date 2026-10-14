// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module security

import klock
import krandom
import lib
import proc
import time

// Security decisions, as a stream a collector can keep.
//
// The seccomp ring beside this one (audit.v) records system calls a filter
// asked to have recorded. This one records what the kernel itself decided
// about who may do what: a privileged operation allowed or refused, a
// mandatory domain refused an object, a device of the seat refused, a login
// beginning, the seat changing hands, an identity change, a signal, a port
// or a link refused -- and what a trusted service reports of its own
// decisions, such as the authentication service on a password.
//
// Each record says who: the process and its ids, and the login it belongs
// to (proc/login.v), which stays the same whatever the process did to its
// ids afterwards and is how a decision is traced to the person who logged
// in.
//
// Like the seccomp ring, this one never allocates, never waits for a
// reader and keeps the newest records, counting what it overwrote. A record
// borrows nothing: the label is copied in, a few dozen bytes of it.
const event_capacity = 256
pub const event_label_bytes = 40

pub const event_policy = u32(1) // a privileged operation, by selector
pub const event_mac = u32(2) // a mandatory domain refused an object
pub const event_seat = u32(3) // a device of the seat refused; the seat given
pub const event_login = u32(4) // a login began
pub const event_identity = u32(5) // a change of user or group ids refused
pub const event_signal = u32(6) // a signal to another's process refused
pub const event_network = u32(7) // a bind the caller may not make
pub const event_file = u32(8) // a name for another's file refused
pub const event_service = u32(9) // reported by a trusted service
pub const event_kinds = u32(9)

pub const cap_audit_write = 29

struct SecurityEvent {
mut:
	sequence  u64
	timestamp u64
	kind      u32
	denied    bool
	pid       int
	tid       int
	uid       u32
	euid      u32
	login_uid u32
	session   u32
	arg       u64
	label     [event_label_bytes]u8
	label_len int
}

__global (
	event_lock    klock.Lock
	event_records [event_capacity]SecurityEvent
	event_total   u64
	event_dropped u64
)

// What a label may hold: printable, and no space, so that a record stays
// one line of fields whatever a caller or a service put in it.
fn event_label(mut record SecurityEvent, label string) {
	mut length := label.len
	if length > event_label_bytes {
		length = event_label_bytes
	}
	for i := 0; i < length; i++ {
		ch := label[i]
		record.label[i] = if ch > 0x20 && ch < 0x7f { ch } else { `_` }
	}
	record.label_len = length
}

fn event_store(mut record SecurityEvent) {
	record.timestamp = time.monotonic_ns()
	event_lock.acquire()
	event_total++
	record.sequence = event_total
	if record.sequence > u64(event_capacity) {
		event_dropped++
	}
	event_records[(record.sequence - 1) % u64(event_capacity)] = record
	event_lock.release()
}

// Record a decision about the calling process. The ids are read as they
// are, without the process table's lock: callers hold it as often as not,
// and a record that catches a concurrent change of ids half done is still a
// record of this process and this login.
pub fn event(kind u32, denied bool, arg u64, label string) {
	t := proc.current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } {
		return
	}
	p := t.process
	// The ring copies this record synchronously. A local value passed to the
	// mutable helpers is otherwise promoted to an unfreed heap allocation.
	mut record := unsafe { &SecurityEvent(C.vinix_stack_alloc(sizeof(SecurityEvent))) }
	unsafe { *record = SecurityEvent{
		kind:      kind
		denied:    denied
		pid:       p.pid
		tid:       t.tid
		uid:       p.uid
		euid:      p.euid
		login_uid: p.login_uid
		session:   p.login_session
		arg:       arg
	} }
	event_label(mut record, label)
	event_store(mut record)
}

// Whether the caller may add a record about another process: a service of
// the system, as root, with CAP_AUDIT_WRITE and outside any confinement.
pub fn event_may_report() bool {
	p := proc.current_thread().process
	return proc.mac_trusted() && p.euid == 0 && p.login_session == 0
		&& proc.is_initial_namespace(p.ns.user) && proc.has_capability(p, cap_audit_write)
}

// Record what a service decided about process `pid`, with that process'
// ids and login as they are now. The reporting service is the arg.
pub fn event_report(pid int, denied bool, label string) {
	reporter := proc.current_thread().process.pid
	uid, euid := proc.process_uids(pid)
	login_uid, session := proc.login_identity(pid)
	mut record := unsafe { &SecurityEvent(C.vinix_stack_alloc(sizeof(SecurityEvent))) }
	unsafe { *record = SecurityEvent{
		kind:      event_service
		denied:    denied
		pid:       pid
		uid:       uid
		euid:      euid
		login_uid: login_uid
		session:   session
		arg:       u64(reporter)
	} }
	event_label(mut record, label)
	event_store(mut record)
}

// The snapshot /proc/security_events shows. The text belongs to procfs's
// per-open copy; formatting happens outside the producers' lock.
pub fn events_text() string {
	mut records := [event_capacity]SecurityEvent{}
	audit_lock.acquire()
	if !audit_boot_identified {
		audit_boot_identified = krandom.fill(unsafe { &audit_boot_id[0] }, 16, true)
	}
	boot_id := audit_boot_id
	audit_lock.release()
	event_lock.acquire()
	total := event_total
	dropped := event_dropped
	retained := if total < u64(event_capacity) { total } else { u64(event_capacity) }
	for i := u64(0); i < retained; i++ {
		records[i] = event_records[(total - retained + i) % u64(event_capacity)]
	}
	event_lock.release()
	mut text := &lib.Text{} @[freed]
	unsafe { *text = lib.new_text(event_capacity * 160 + 256) }
	text.add('version=1 capacity=256 total=')
	text.add_unsigned(total)
	text.add(' retained=')
	text.add_unsigned(retained)
	text.add(' dropped=')
	text.add_unsigned(dropped)
	text.add(' boot=')
	for byte in boot_id {
		text.add_radix(u64(byte), 16, 2)
	}
	text.add('\n# sequence ns kind denied pid tid uid euid loginuid session arg label\n')
	for i := u64(0); i < retained; i++ {
		r := records[i]
		text.add_unsigned(r.sequence)
		text.add_byte(` `)
		text.add_unsigned(r.timestamp)
		text.add_byte(` `)
		text.add_unsigned(r.kind)
		text.add_byte(` `)
		text.add_unsigned(if r.denied { u64(1) } else { u64(0) })
		text.add_byte(` `)
		text.add_decimal(r.pid)
		text.add_byte(` `)
		text.add_decimal(r.tid)
		text.add_byte(` `)
		text.add_unsigned(r.uid)
		text.add_byte(` `)
		text.add_unsigned(r.euid)
		text.add_byte(` `)
		text.add_unsigned(r.login_uid)
		text.add_byte(` `)
		text.add_unsigned(r.session)
		text.add_byte(` `)
		text.add_unsigned(r.arg)
		text.add_byte(` `)
		if r.label_len == 0 {
			text.add_byte(`-`)
		}
		for k := 0; k < r.label_len; k++ {
			text.add_byte(r.label[k])
		}
		text.add_byte(`\n`)
	}
	result := text.str()
	unsafe { free(text) }
	return result
}
