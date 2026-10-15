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
