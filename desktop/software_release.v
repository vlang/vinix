// SPDX-License-Identifier: GPL-2.0-or-later
module main

const software_first_run_release_action = 'software.first-run-release'

fn (a &SoftwareApp) can_review_first_run_release() bool {
	return a.review == '' && a.launch_request == '' && !a.policy_mode && !a.data_mode && !a.launch_mode
		&& !a.repository_mode && !a.mirror_mode && !a.audit_mode && !a.window_mode && !a.deployment_mode
		&& !a.health_mode && !a.cleanup_mode && !a.snapshot_mode && !a.details_mode && !a.failure_mode
		&& !a.report_reader_mode && !a.status_reader.mode && !a.catalog_browser_mode
		&& a.terminal_app == unsafe { nil }
}

// This compositor-originated request is only a read. Initial catalog loading
// must finish before the exact release declaration enters the existing review.
fn (mut a SoftwareApp) request_first_run_release_review() {
	if !a.can_review_first_run_release() || (a.worker != unsafe { nil } && !a.worker_view) {
		a.set_status('Return to the catalog before reviewing release applications.')
		return
	}
	a.release_review_requested = true
	a.take_first_run_release_review()
}

fn (mut a SoftwareApp) take_first_run_release_review() {
	if !a.release_review_requested || a.worker != unsafe { nil } { return }
	a.release_review_requested = false
	// A reader opened while the initial catalog loaded belongs to the user.
	// Retire the one-shot handoff rather than replace that intervening view.
	if !a.can_review_first_run_release() { return }
	a.deployment_mode = true
	a.focus = false
	a.select_all = false
	a.review_release_deployment()
}

fn (mut a SoftwareApp) find_release_deployment() {
	mut info := C.stat{}
	a.release_deployment_available = software_deployment_path_valid(a.release_deployment_path)
		&& C.lstat(a.release_deployment_path.str, unsafe { &info }) == 0
		&& info.st_mode & 0o170000 == 0o100000
}

fn (mut a SoftwareApp) select_release_deployment() bool {
	if a.worker != unsafe { nil } || a.review != '' || !a.deployment_mode { return false }
	a.find_release_deployment()
	if !a.release_deployment_available {
		a.set_status('The release application file is unavailable. Choose a deployment file or enter its absolute path.')
		return false
	}
	a.initialize_deployment_field()
	software_repository_text(mut a.deployment_path, a.release_deployment_path)
	return true
}

fn (mut a SoftwareApp) review_release_deployment() {
	if a.select_release_deployment() { a.begin_deployment_review() }
}

fn (mut a SoftwareApp) audit_release_deployment() {
	if a.select_release_deployment() { a.begin_deployment_audit() }
}
