// SPDX-License-Identifier: GPL-2.0-or-later
module corevm
import corevm.corepolicy

const core_pass_marker = corepolicy.core_pass_marker
const core_persist_marker = corepolicy.core_persist_marker
const core_fail_markers = corepolicy.core_fail_markers

pub fn required(verification bool, amd64 bool) []string { return corepolicy.required(verification, amd64) }

pub fn results(run Run, verification bool, amd64 bool) ([]string, []string) {
	mut missing := []string{}
	for marker in required(verification, amd64) {
		if run.output.count(marker) != 1 { missing << marker }
	}
	mut failures := []string{}
	for marker in core_fail_markers { if run.output.contains(marker) { failures << marker } }
	if amd64 {
		if !run.finished { failures << 'the test did not finish before the timeout' }
	} else {
		if run.has_status && run.status != 0 {
			failures << 'VM runner exit status ' + run.status.str()
		}
		if run.forced { failures << 'VM did not exit after the test' }
	}
	return missing, failures
}
