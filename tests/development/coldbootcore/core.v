// SPDX-License-Identifier: GPL-2.0-or-later
module coldbootcore

import desktop.sessioncore
import encoding.hex
import json2

pub struct Proof {
pub:
	schema int
	uid int
	phase int
	guardian int
	watcher int
	parent int
	child int
	stop_millis u64
	before string
	running string
	after string
}

struct JobState {
	in_flight bool
	next_due i64
	started i64
	finished i64
	exit_code int
	detail string
	runs u64
	attempts u64
}

struct Schedule {
	schema int
	uid int
	plan_sha256 string
	jobs map[string]JobState
}

pub fn enabled_record() !string {
	unit := '[Service]\nType=simple\nExecStart="/usr/bin/vinix-jobs" watch "/home/developer/service-state"\n'
		+ 'Restart=on-failure\nRestartSec=1s\nTimeoutStopSec=10s\n'
	mut supervisor := sessioncore.Supervisor{count: 1}
	supervisor.services[0] = sessioncore.import_linux_service('vinix-jobs.service', unit, true)!
	supervisor.validate()!
	return supervisor.encode()
}

fn verify_state(body string, runs int, pin string) ! {
	schedule := json2.decode[Schedule](body, strict: true)!
	if schedule.schema != 1 || schedule.uid != 1000 || schedule.plan_sha256 != pin
		|| schedule.jobs.len != 1 || 'fixture' !in schedule.jobs {
		return error('cold boot changed the schedule account or plan identity')
	}
	job := schedule.jobs['fixture']
	if job.in_flight || job.runs != u64(runs) || job.attempts != u64(runs)
		|| job.exit_code != -1 || job.detail != 'job interrupted' || job.started <= 0
		|| job.finished < job.started || job.next_due != job.finished + 1 {
		return error('cold boot lost, duplicated or failed to retire a scheduled attempt')
	}
}

pub fn verify(receipts map[string]string, phase int, pin string) !Proof {
	if phase !in [1, 2, 3] || pin.len != 64 || !pin.bytes().all(it.is_hex_digit()) {
		return error('invalid cold boot phase or plan pin')
	}
	prefix := '/home/developer/'
	if receipts.len != if phase == 1 { 2 } else { 3 } {
		return error('missing cold boot receipts')
	}
	proof := json2.decode[Proof](receipts[prefix + 'service-cold-proof.json'], strict: true)!
	if proof.schema != 1 || proof.uid != 1000 || proof.phase != phase || proof.stop_millis >= 10000 {
		return error('invalid cold boot process retirement proof')
	}
	mut seen := map[int]bool{}
	for pid in [proof.guardian, proof.watcher, proof.parent, proof.child] {
		if pid <= 1 || pid in seen { return error('invalid cold boot process identities') }
		seen[pid] = true
	}
	enabled := enabled_record()!
	if hex.decode(proof.running)!.bytestr() != enabled
		|| hex.decode(proof.before)!.bytestr() != if phase == 1 { '' } else { enabled }
		|| hex.decode(proof.after)!.bytestr() != if phase == 3 { 'vinix-services\t1\n' } else { enabled } {
		return error('cold boot changed the persisted service definition')
	}
	verify_state(receipts[prefix + 'service-after.json'], phase, pin)!
	if phase > 1 { verify_state(receipts[prefix + 'service-state/state.json'], phase - 1, pin)! }
	return proof
}
