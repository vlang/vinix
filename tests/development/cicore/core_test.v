// SPDX-License-Identifier: GPL-2.0-or-later
module cicore

import crypto.sha256
import json2

fn test_ci_options_require_an_explicit_native_compiler_project() {
	assert !options('', [])! && !options('0', ['go'])! && options('1', ['go'])!
	for value in ['yes', '2'] { if _ := options(value, ['go']) { assert false } }
	for profiles in [[]string{}, ['http'], ['go', 'java']] { if _ := options('1', profiles) { assert false } }
}

fn test_ci_receipts_require_reserved_attempts_pins_credential_scope_and_failure() {
	builder := 'a'.repeat(64)
	plan := Plan{schema: 1, uid: 1000, jobs: [Job{id: 'ci', executable: Pin{'/usr/bin/vinix-build', builder},
		arguments: ['build', '/home/developer/reference-build.json', '/home/developer/ci-{attempt}'], expand_attempt: true,
		directory: '/home/developer', interval_seconds: 1, timeout_seconds: 1800, credential_files: {'CI_TOKEN': '/home/developer/token'}}]}
	text := json2.encode(plan)
	completed := State{schema: 1, uid: 1000, plan_sha256: sha256.sum(text.bytes()).hex(),
		jobs: {'ci': JobState{started: 10, finished: 11, next_due: 12, runs: 2, attempts: 2, detail: 'finished'}}}
	failed := State{...completed, jobs: {'ci': JobState{started: 12, finished: 13, next_due: 14,
		runs: 3, attempts: 3, exit_code: 1, detail: 'finished'}}}
	verify(text, json2.encode(completed), json2.encode(failed), builder)!
	for changed in [Job{...plan.jobs[0], expand_attempt: false},
		Job{...plan.jobs[0], arguments: ['build', '/home/developer/reference-build.json', '/home/developer/ci-1']},
		Job{...plan.jobs[0], environment: {'CI_TOKEN': 'public-value'}},
		Job{...plan.jobs[0], credential_files: {'CI_TOKEN': '/tmp/token'}}] {
		if _ := verify(json2.encode(Plan{...plan, jobs: [changed]}), json2.encode(completed), json2.encode(failed), builder) {
			assert false, 'CI scope or output template changed'
		}
	}
	for changed in [JobState{...completed.jobs['ci'], attempts: 1}, JobState{...completed.jobs['ci'], in_flight: true},
		JobState{...completed.jobs['ci'], exit_code: 1}] {
		if _ := verify(text, json2.encode(State{...completed, jobs: {'ci': changed}}), json2.encode(failed), builder) {
			assert false, 'unfinished or unreserved CI accepted'
		}
	}
	if _ := verify(text, json2.encode(completed), json2.encode(State{...failed, jobs: {'ci': JobState{...failed.jobs['ci'], exit_code: 0}}}), builder) {
		assert false, 'failed-output refusal changed to success'
	}
}
