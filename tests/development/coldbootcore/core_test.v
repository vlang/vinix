// SPDX-License-Identifier: GPL-2.0-or-later
module coldbootcore

import encoding.hex
import json2

fn state_fixture(runs int, pin string) string {
	return json2.encode(Schedule{schema: 1, uid: 1000, plan_sha256: pin,
		jobs: {'fixture': JobState{runs: u64(runs), attempts: u64(runs), started: 100,
			finished: 101, next_due: 102, exit_code: -1, detail: 'job interrupted'}}})
}

fn proof_fixture(phase int) !map[string]string {
	proof := Proof{schema: 1, uid: 1000, phase: phase, guardian: 10, watcher: 11, parent: 12, child: 13,
		stop_millis: 50, before: if phase == 1 { '' } else { hex.encode(enabled_record()!.bytes()) },
		running: hex.encode(enabled_record()!.bytes()),
		after: hex.encode((if phase == 3 { 'vinix-services\t1\n' } else { enabled_record()! }).bytes())}
	mut receipts := {'/home/developer/service-cold-proof.json': json2.encode(proof),
		'/home/developer/service-after.json': state_fixture(phase, 'a'.repeat(64))}
	if phase > 1 { receipts['/home/developer/service-state/state.json'] = state_fixture(phase - 1, 'a'.repeat(64)) }
	return receipts
}

fn test_cold_boot_requires_previous_and_next_attempt_under_the_same_plan() {
	for phase in [1, 2, 3] {
		receipts := proof_fixture(phase)!
		verify(receipts, phase, 'a'.repeat(64))!
		for replacement in [state_fixture(phase + 1, 'a'.repeat(64)), state_fixture(phase, 'b'.repeat(64))] {
			mut changed := receipts.clone()
			changed['/home/developer/service-after.json'] = replacement
			if _ := verify(changed, phase, 'a'.repeat(64)) { assert false, 'changed attempt or plan accepted' }
		}
		if phase > 1 {
			mut changed := receipts.clone()
			changed['/home/developer/service-state/state.json'] = state_fixture(0, 'a'.repeat(64))
			if _ := verify(changed, phase, 'a'.repeat(64)) { assert false, 'lost prior boot state accepted' }
		}
	}
}

fn test_cold_boot_rejects_incomplete_evidence_and_changed_service_policy() {
	receipts := proof_fixture(2)!
	proof := json2.decode[Proof](receipts['/home/developer/service-cold-proof.json'])!
	for replacement in [Proof{...proof, uid: 0}, Proof{...proof, phase: 1},
		Proof{...proof, guardian: proof.watcher}, Proof{...proof, child: 0},
		Proof{...proof, stop_millis: 10000}, Proof{...proof, before: ''},
		Proof{...proof, running: ''}, Proof{...proof, after: ''}] {
		mut changed := receipts.clone()
		changed['/home/developer/service-cold-proof.json'] = json2.encode(replacement)
		if _ := verify(changed, 2, 'a'.repeat(64)) { assert false, 'invalid cold boot proof accepted' }
	}
	mut missing := receipts.clone()
	missing.delete('/home/developer/service-state/state.json')
	if _ := verify(missing, 2, 'a'.repeat(64)) { assert false, 'missing prior boot receipt accepted' }
}

fn test_shutdown_options_reject_ambiguous_or_unbounded_controls() {
	assert options([]string{})! == Options{}
	assert options(['persistent'])! == Options{'persistent', 13, 0}
	assert options(['volatile', '0'])! == Options{'volatile', 0, 0}
	assert options(['persistent', '30'])! == Options{'persistent', 30, 0}
	assert options(['persistent', '0', '30'])! == Options{'persistent', 0, 30}
	for arguments in [['other'], ['persistent', '31'], ['volatile', '-1'],
		['volatile', ''], ['persistent', 'junk'], ['volatile', '07'],
		['persistent', '+7'], ['volatile', '7s'], ['volatile', '1', 'extra'],
		['persistent', '0', '31'], ['persistent', '0', '-1'], ['volatile', '0', '01'],
		['volatile', '0', '30', 'extra']] {
		if _ := options(arguments) { assert false, 'invalid shutdown options accepted' }
	}
}

fn test_shutdown_retries_require_complete_bounded_busy_evidence() {
	selected := options(['persistent', '0', '30'])!
	mut receipts := proof_fixture(1)!
	path := '/fixture/service-cold-shutdown.json'
	shutdown := Shutdown{schema: 2, phase: 1, runtime: 'persistent', settle_seconds: 0,
		unmounted: true, unmount_attempts: 101, busy_refusals: 100, unmount_millis: 11000}
	receipts[path] = json2.encode(shutdown)
	verify_shutdown(receipts, 1, 'a'.repeat(64), selected)!
	for changed in [Shutdown{...shutdown, schema: 1}, Shutdown{...shutdown, unmount_attempts: 0},
		Shutdown{...shutdown, busy_refusals: 99}, Shutdown{...shutdown, unmount_millis: 30001}] {
		receipts[path] = json2.encode(changed)
		if _ := verify_shutdown(receipts, 1, 'a'.repeat(64), selected) {
			assert false, 'missing, inconsistent or unbounded unmount retries accepted'
		}
	}
	receipts[path] = json2.encode(Shutdown{...shutdown, unmount_attempts: 1, busy_refusals: 0, unmount_millis: 0})
	verify_shutdown(receipts, 1, 'a'.repeat(64), selected)!
	verify_shutdown(receipts, 1, 'a'.repeat(64), options(['persistent', '0'])!)!
	receipts[path] = json2.encode(shutdown)
	if _ := verify_shutdown(receipts, 1, 'a'.repeat(64), options(['persistent', '0'])!) {
		assert false, 'unrequested retries accepted'
	}
}

fn test_shutdown_requires_measured_wait_selected_runtime_and_unmount() {
	for runtime in ['volatile', 'persistent'] {
		selected := options([runtime])!
		for phase in [1, 2, 3] {
			mut receipts := proof_fixture(phase)!
			path := '/fixture/service-cold-shutdown.json'
			shutdown := Shutdown{schema: 1, phase: phase, runtime: runtime, settle_seconds: 13,
				quiescence_millis: 13000, unmounted: true}
			receipts[path] = json2.encode(shutdown)
			verify_shutdown(receipts, phase, 'a'.repeat(64), selected)!
			for changed in [Shutdown{...shutdown, schema: 0}, Shutdown{...shutdown, phase: 0},
				Shutdown{...shutdown, runtime: if runtime == 'volatile' { 'persistent' } else { 'volatile' }},
				Shutdown{...shutdown, settle_seconds: 7}, Shutdown{...shutdown, quiescence_millis: 12999},
				Shutdown{...shutdown, unmounted: false}] {
				receipts[path] = json2.encode(changed)
				if _ := verify_shutdown(receipts, phase, 'a'.repeat(64), selected) {
					assert false, 'incomplete or mismatched shutdown accepted'
				}
			}
			receipts.delete(path)
			if _ := verify_shutdown(receipts, phase, 'a'.repeat(64), selected) {
				assert false, 'missing shutdown accepted'
			}
			receipts[path] = json2.encode(shutdown)
			receipts.delete('/home/developer/service-after.json')
			if _ := verify_shutdown(receipts, phase, 'a'.repeat(64), selected) {
				assert false, 'missing account evidence accepted'
			}
		}
	}
}
