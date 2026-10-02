// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module security

import klock
import lib
import proc
import time

// Security records are never allowed to exhaust the heap or stall a syscall
// waiting for a collector. Keep the newest records, count each overwritten
// record, and give readers a consistent, non-destructive snapshot.
const audit_capacity = 128

struct AuditRecord {
mut:
	sequence  u64
	timestamp u64
	arch      u32
	syscall   u64
	ip        u64
	pid       int
	tid       int
	uid       u32
	euid      u32
	gid       u32
	egid      u32
	action    u32
	result    u64
	err       u64
	completed bool
}

__global (
	audit_lock    klock.Lock
	audit_records [audit_capacity]AuditRecord
	audit_total   u64
	audit_dropped u64
)

// Return a correlation number for the syscall exit hook. This copies scalar
// identity fields only: the record does not borrow process or thread storage.
pub fn audit_seccomp(nr u64, ip u64, action u32) u64 {
	t := proc.current_thread()
	p := t.process
	now := time.monotonic_ns()
	// Credential changes serialize through the process table. Capture one
	// coherent identity before taking the ring lock; records retain no pointer.
	proc.lock_table()
	identity := AuditRecord{
		pid: p.pid
		tid: t.tid
		uid: p.uid
		euid: p.euid
		gid: p.gid
		egid: p.egid
	}
	proc.unlock_table()
	audit_lock.acquire()
	defer { audit_lock.release() }
	audit_total++
	sequence := audit_total
	if sequence > u64(audit_capacity) {
		audit_dropped++
	}
	audit_records[(sequence - 1) % u64(audit_capacity)] = AuditRecord{
		sequence:  sequence
		timestamp: now
		arch:      proc.seccomp_audit_arch
		syscall:   nr
		ip:        ip
		pid:       identity.pid
		tid:       identity.tid
		uid:       identity.uid
		euid:      identity.euid
		gid:       identity.gid
		egid:      identity.egid
		action:    action
	}
	return sequence
}

pub fn audit_complete(sequence u64, result u64, err u64) {
	if sequence == 0 {
		return
	}
	audit_lock.acquire()
	index := (sequence - 1) % u64(audit_capacity)
	// The producer may have been descheduled while the ring wrapped. Never
	// attach its result to another syscall's newer record.
	if audit_records[index].sequence == sequence {
		audit_records[index].result = result
		audit_records[index].err = err
		audit_records[index].completed = true
	}
	audit_lock.release()
}

pub fn audit_may_read() bool {
	p := proc.current_thread().process
	return p.euid == 0 && proc.is_initial_namespace(p.ns.user)
		&& proc.has_capability(p, proc.cap_audit_read)
}

// The returned text belongs to procfs's per-open snapshot. The stack copy
// keeps formatting and heap allocation outside the producer lock.
pub fn audit_text() string {
	mut records := [audit_capacity]AuditRecord{}
	audit_lock.acquire()
	total := audit_total
	dropped := audit_dropped
	retained := if total < u64(audit_capacity) { total } else { u64(audit_capacity) }
	for i := u64(0); i < retained; i++ {
		records[i] = audit_records[(total - retained + i) % u64(audit_capacity)]
	}
	audit_lock.release()
	// V moves a mutable Text receiver to the heap. Make its ownership
	// explicit so the receiver itself is freed as well as its byte buffer.
	mut text := &lib.Text{} @[freed]
	unsafe { *text = lib.new_text(audit_capacity * 256 + 256) }
	text.add('version=1 capacity=128 total=')
	text.add_unsigned(total)
	text.add(' retained=')
	text.add_unsigned(retained)
	text.add(' dropped=')
	text.add_unsigned(dropped)
	text.add('\n# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n')
	for i := u64(0); i < retained; i++ {
		r := records[i]
		text.add_unsigned(r.sequence)
		text.add_byte(` `)
		text.add_unsigned(r.timestamp)
		text.add_byte(` `)
		text.add_unsigned(r.arch)
		text.add_byte(` `)
		text.add_unsigned(r.syscall)
		text.add_byte(` `)
		text.add_unsigned(r.ip)
		text.add_byte(` `)
		text.add_decimal(r.pid)
		text.add_byte(` `)
		text.add_decimal(r.tid)
		text.add_byte(` `)
		text.add_unsigned(r.uid)
		text.add_byte(` `)
		text.add_unsigned(r.euid)
		text.add_byte(` `)
		text.add_unsigned(r.gid)
		text.add_byte(` `)
		text.add_unsigned(r.egid)
		text.add_byte(` `)
		text.add_unsigned(r.action)
		text.add_byte(` `)
		text.add_unsigned(if r.completed { u64(1) } else { u64(0) })
		text.add_byte(` `)
		text.add_unsigned(r.result)
		text.add_byte(` `)
		text.add_unsigned(r.err)
		text.add_byte(`\n`)
	}
	result := text.str()
	unsafe { free(text) }
	return result
}
