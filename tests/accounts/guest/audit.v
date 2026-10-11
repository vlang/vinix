// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The kernel's record of security decisions on a booted kernel: what an
// account was refused is there, attributed to the login it happened in;
// what the authentication service decided is there too; accounts can
// neither read the record nor add to it; and the collector keeps it on
// disk, once each, saying exactly what it missed.
module main

import eventcore
import os

fn C.socket(domain int, kind int, protocol int) int
fn C.bind(fd int, address voidptr, length u32) int

// Many refusals quickly: more than the kernel's ring holds.
fn probe_flood(count int) int {
	for _ in 0 .. count {
		fd := C.socket(C.AF_INET, C.SOCK_STREAM, 0)
		mut address := SockaddrIn{
			family: u16(C.AF_INET)
			port:   u16(80 << 8)
		}
		C.bind(fd, voidptr(&address), u32(sizeof(SockaddrIn)))
		C.close(fd)
	}
	println('flooded ${count}')
	return 0
}

fn events_now(mut t Test) eventcore.Snapshot {
	return eventcore.parse_snapshot(read_text('/proc/security_events')) or {
		t.check(false, 'the kernel\'s snapshot does not parse: ${err.msg()}')
		eventcore.Snapshot{}
	}
}

fn collect(mut t Test) {
	ran := run(['/usr/sbin/vinix-security-events', '--once'], '', none, none)
	t.check(ran.status == 0, 'the collector: ${ran.status} ${ran.output}')
}

fn scenario_audit(mut t Test) {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	t.start_authd()
	os.write_file('/tmp/swept-own', 'x') or {}
	os.chown('/tmp/swept-own', int(sam.uid), int(sam.gid)) or {}

	// Something root is allowed, for a record of an allowed decision.
	C.sethostname(c'audited', 7)
	// Sam logs in and is refused things.
	swept := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'sweep', '1',
		'1'], '', none, none)
	t.check(swept.output.contains('SWEEP bind-80 13'), 'the sweep did not run: ${swept.output}')
	run(['/usr/sbin/vinix-session', 'run', 'sam', '/usr/bin/vinix-auth', 'verify'], 'not the password\n',
		none, none)
	run(['/usr/sbin/vinix-session', 'run', 'alex', '/usr/bin/vinix-auth', 'run', 'hostname-set',
		'audited2'], alex_password + '\n', none, none)

	snapshot := events_now(mut t)
	t.check(snapshot.events.len > 20, 'only ${snapshot.events.len} events after a sweep')
	// What must be there, as (kind, denied, label prefix, uid): each with
	// the login of the account and a login session that is not the system's.
	mut sam_session := u32(0)
	for wanted in [
		['policy', 'system/hostname/set'],
		['policy', 'system/reboot'],
		['policy', 'filesystem/mount'],
		['policy', 'system/clock/set'],
		['network', 'bind'],
		['signal', 'kill'],
		['identity', 'setid'],
		['seat', 'fb0'],
		['file', 'link'],
	] {
		mut found := false
		for event in snapshot.events {
			if eventcore.kind_name(event.kind) == wanted[0] && event.label == wanted[1] && event.denied
				&& event.uid == sam.uid && event.login_uid == sam.uid && event.session != 0 {
				found = true
				sam_session = event.session
			}
		}
		t.check(found, 'no record of sam being refused ${wanted[0]} ${wanted[1]}')
	}
	mut bind_port := u64(0)
	mut killed := u64(0)
	mut logins := 0
	mut root_allowed := false
	mut auth_denied := false
	mut auth_ran := false
	for event in snapshot.events {
		kind := eventcore.kind_name(event.kind)
		if kind == 'network' && event.uid == sam.uid {
			bind_port = event.arg
		}
		if kind == 'signal' && event.uid == sam.uid {
			killed = event.arg
		}
		if kind == 'login' && !event.denied && event.arg in [u64(sam.uid), u64(alex.uid)] {
			logins++
		}
		if kind == 'policy' && event.label == 'system/hostname/set' && !event.denied && event.uid == 0
			&& event.login_uid == u32(0xffffffff) && event.session == 0 {
			root_allowed = true
		}
		// The service's own decisions, about the caller and in the caller's
		// login -- not the service's.
		if kind == 'service' && event.label == 'auth:verify_sam:denied' && event.denied
			&& event.login_uid == sam.uid && event.session != 0 && event.session != sam_session {
			auth_denied = true
		}
		if kind == 'service' && event.label == 'auth:run_hostname-set_as_alex:exit_0' && !event.denied
			&& event.login_uid == alex.uid && event.session != 0 {
			auth_ran = true
		}
	}
	t.check(bind_port == 80, 'the refused port is recorded as ${bind_port}')
	t.check(killed == 1, 'the process sam tried to signal is recorded as ${killed}')
	t.check(logins == 3, '${logins} logins recorded, not 3')
	t.check(root_allowed, 'no record of root, outside any login, being allowed to set the host name')
	t.check(auth_denied, 'no record of the service refusing sam\'s password, in sam\'s login')
	t.check(auth_ran, 'no record of the service running an action for alex')

	// Not for accounts to read, and not for them to write.
	for what in [['read', '/proc/security_events'], ['write', '/proc/security_events'],
		['read', '/proc/security_audit'], ['list', '/var/log/vinix-audit']] {
		got := probe(what, db, sam).output.trim_space()
		t.check(got.starts_with('errno'), 'sam: ${what.join(' ')}: ${got}')
	}
	before := events_now(mut t).total
	forged := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'report'],
		'', none, none)
	t.check(forged.output.trim_space() == 'refused', 'sam reporting a decision into the record: ${forged.output}')
	for event in events_now(mut t).events {
		t.check(event.label != 'forged', 'a record sam made up is in the stream')
	}
	_ = before

	// The collector: everything once, on disk, root's alone.
	collect(mut t)
	log := '/var/log/vinix-audit/events.log'
	first := read_text(log)
	kept := first.split_into_lines().filter(it.starts_with('event '))
	t.check(kept.len >= snapshot.events.len, 'the log has ${kept.len} records, the snapshot had ${snapshot.events.len}')
	t.check(mode_of(log) == 0o600 && owner_of(log) == 0 && mode_of('/var/log/vinix-audit') == 0o700,
		'the log is mode ${mode_of(log):o}, its directory ${mode_of('/var/log/vinix-audit'):o}')
	t.check(first.contains(' kind=network result=denied ') && first.contains(' login=${sam.uid} ')
		&& first.contains(' label=auth:verify_sam:denied'), 'the log does not read as expected')
	mut seen := map[string]bool{}
	for line in kept {
		sequence := line.all_after(' seq=').all_before(' ')
		t.check(sequence !in seen, 'record ${sequence} is in the log twice')
		seen[sequence] = true
	}
	// A second pass adds only what happened since: the collector's own
	// start is not an event, so nothing.
	collect(mut t)
	second := read_text(log).split_into_lines().filter(it.starts_with('event '))
	t.check(second.len - kept.len < 5, 'a second pass added ${second.len - kept.len} records')

	// More refusals than the ring holds between two passes: the gap is
	// written down, to the record.
	os.mkdir_all('/etc/vinix') or {}
	os.write_file('/etc/vinix/audit.conf', 'max_bytes = 8192\nkeep_files = 2\nmax_age_days = 0\n') or {}
	last_before := events_now(mut t).total
	run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'flood', '600'],
		'', none, none)
	after := events_now(mut t)
	t.check(after.total >= last_before + 600 && after.dropped > 0, 'the flood: total ${last_before} -> ${after.total}, overwritten ${after.dropped}')
	collect(mut t)
	mut text := ''
	for name in ['events.log.2', 'events.log.1', 'events.log'] {
		text += read_text('/var/log/vinix-audit/${name}')
	}
	loss := text.split_into_lines().filter(it.starts_with('loss '))
	t.check(loss.len == 1, '${loss.len} gaps recorded, not 1')
	if loss.len == 1 {
		first_lost := loss[0].all_after(' first=').all_before(' ').u64()
		last_lost := loss[0].all_after(' last=').all_before(' ').u64()
		count := loss[0].all_after(' count=').all_before(' ').u64()
		t.check(count == last_lost - first_lost + 1 && last_lost == after.total - 256
			&& count == after.total - 256 - (first_lost - 1), 'the gap is recorded as ${loss[0]} with the kernel at ${after.total}')
	}
	t.check(text.contains(' seq=${after.total} '), 'the newest record is not in the log')
	// Set aside by size -- at the pass after the one that outgrew it -- and
	// deleted by count.
	for _ in 0 .. 4 {
		run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'flood', '200'],
			'', none, none)
		collect(mut t)
	}
	final := os.ls('/var/log/vinix-audit') or { []string{} }
	t.check(final.len == 3 && 'events.log.2' in final && 'events.log.3' !in final, 'after more records the directory holds ${final}')
}
