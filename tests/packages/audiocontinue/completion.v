// SPDX-License-Identifier: GPL-2.0-or-later
module audiocontinue

// This interface is an in-process implementation boundary, never JSON input.
// Tests exercise the same publication order as the real preparation engine.
interface CompletionChecks2 {
	verify_candidate() !
	verify_resources() !
	verify_cancellation() !
	verify_deadline() !
}

fn complete_candidate2(root string, sha string, checks CompletionChecks2) !string {
	checks.verify_candidate()!
	checks.verify_resources()!
	checks.verify_cancellation()!
	checks.verify_deadline()!
	// No fallible I/O, verification, deadline or receipt writing follows this
	// exclusive publication. Failure reporting cannot create a completed file.
	publish_candidate2(root)!
	return sha
}
