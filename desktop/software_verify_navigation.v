// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn (a &SoftwareApp) verification_running() bool {
	return a.package_screen_active() && a.worker != unsafe { nil } && a.worker_verify
		&& !a.worker_view && !a.worker_review && !a.worker_run && a.review == ''
}

fn (mut a SoftwareApp) stop_verification() {
	// Verification is a read-only scan. Transaction progress can also contain
	// verify frames, so only the dedicated Verify worker may be stopped here.
	if !a.verification_running() { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.worker_verify = false
	a.clear_progress()
	a.output.clear(); a.output_truncated = false
	a.focus = false; a.select_all = false
	a.set_status('Verification stopped. No complete result was accepted. Run Verify installed again to retry.')
}
