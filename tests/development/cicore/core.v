// SPDX-License-Identifier: GPL-2.0-or-later
module cicore

import crypto.sha256
import json2

pub const account_proof = '{"schema":1,"uid":1000,"gid":1000,"credential_absent":true}\n'

pub fn options(value string, profiles []string) !bool {
	if value !in ['', '0', '1'] { return error('VINIX_DEVELOPMENT_REFERENCE_CI must be 0 or 1') }
	if value == '1' && profiles != ['go'] { return error('reference CI requires only the prepared native Go profile') }
	return value == '1'
}

pub fn outputs(enabled bool) []string {
	return if enabled { ['ci-1', 'ci-2'] } else { ['reference-a', 'reference-b'] }
}

struct Pin {
	path string
	sha256 string
}

struct Job {
	id string
	executable Pin
	arguments []string
	expand_attempt bool
	directory string
	interval_seconds int
	timeout_seconds int
	environment map[string]string
	credential_files map[string]string
}

struct Plan {
	schema int
	uid int
	jobs []Job
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

struct State {
	schema int
	uid int
	plan_sha256 string
	jobs map[string]JobState
}

fn state(text string, pin string, count u64, status int) !JobState {
	result := json2.decode[State](text, strict: true)!
	if result.schema != 1 || result.uid != 1000 || result.plan_sha256 != pin
		|| result.jobs.len != 1 || 'ci' !in result.jobs { return error('CI schedule identity or plan pin changed') }
	job := result.jobs['ci']
	if job.in_flight || job.runs != count || job.attempts != count || job.exit_code != status
		|| job.detail != 'finished' || job.started <= 0 || job.finished < job.started
		|| job.next_due != job.finished + 1 { return error('CI attempt, status or interval evidence changed') }
	return job
}

// Independent contracts for actual scheduled builds and failed-output refusal.
pub fn verify(plan_text string, completed string, failed string, builder_sha string) ! {
	plan := json2.decode[Plan](plan_text, strict: true)!
	if plan.schema != 1 || plan.uid != 1000 || plan.jobs.len != 1 { return error('CI plan identity changed') }
	job := plan.jobs[0]
	if job.id != 'ci' || job.executable != Pin{'/usr/bin/vinix-build', builder_sha}
		|| !job.expand_attempt || job.arguments != ['build', '/home/developer/reference-build.json', '/home/developer/ci-{attempt}']
		|| job.directory != '/home/developer' || job.interval_seconds != 1 || job.timeout_seconds != 1800
		|| job.environment.len != 0 || job.credential_files != {'CI_TOKEN': '/home/developer/token'} {
		return error('CI executable, arguments, environment or credential scope changed')
	}
	pin := sha256.sum(plan_text.bytes()).hex()
	good := state(completed, pin, 2, 0)!
	refused := state(failed, pin, 3, 1)!
	if refused.started < good.next_due { return error('CI retry ran before its interval') }
}
