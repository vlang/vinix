// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const software_first_run_release_action = 'software.first-run-release'

fn (a &SoftwareApp) can_review_first_run_release() bool {
	return a.review == '' && a.launch_request == '' && !a.policy_mode && !a.data_mode && !a.launch_mode
		&& !a.repository_mode && !a.mirror_mode && !a.audit_mode && !a.window_mode && !a.deployment_mode
		&& !a.health_mode && !a.cleanup_mode && !a.snapshot_mode && !a.details_mode && !a.failure_mode
		&& !a.report_reader_mode && !a.status_reader.mode && !a.catalog_browser_mode && !a.release_catalog_mode
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
	a.open_release_deployment_review()
}

fn (mut a SoftwareApp) open_release_deployment_review() {
	a.open_release_deployment_review_mode(false)
}

fn (mut a SoftwareApp) open_release_deployment_review_mode(additions bool) {
	if !a.check_release_deployment() { return }
	if a.catalog_error != '' {
		a.focus = false
		a.select_all = false
		a.release_catalog_mode = true
		a.release_catalog_additions = additions
		a.set_status(a.catalog_error)
		return
	}
	a.deployment_mode = true
	a.load_release_deployment_path()
	a.begin_deployment_review_mode(additions)
}

fn (mut a SoftwareApp) handle_release_catalog(action string) {
	if a.worker != unsafe { nil } { return }
	match action {
		'software.release.catalog.back' {
			a.release_catalog_mode = false
			a.release_catalog_additions = false
			a.set_status(a.catalog_error)
		}
		'software.release.catalog.refresh', 'software.release.catalog.offline' {
			a.offline_requested = action == 'software.release.catalog.offline'
			a.start(['update'], false)
		}
		else {}
	}
}

fn (a &SoftwareApp) build_release_catalog(width int, height int) ui2.Element {
	mut children := frame_elements(8)
	content := if width > 480 { 452 } else { width - 28 }
	children << software_label('Release apps', 14, 8, content, 28, false)
	if a.worker != unsafe { nil } {
		progress := a.progress_seen && height >= 220
		bottom := height - if progress { 108 } else { 8 }
		children << software_label(a.status, 14, 46, content, if bottom > 74 { bottom - 46 } else { 28 }, false)
		if progress { children << a.progress_bar(width, height) }
	} else if width >= 180 && height >= 220 {
		children << software_label('Refresh the signed catalog to review release apps.', 14, 42, content, 54, false)
		children << software_button('software.release.catalog.offline', 'Refresh offline', 14, 102, content)
		children << software_button('software.release.catalog.refresh', 'Refresh with policy', 14, 138, content)
		half := (content - 8) / 2
		children << software_button('software.release.catalog.back', 'Back', 14, 174, half)
		has_failure := a.failure_pages.len > 0
		children << software_button(if has_failure { 'software.failure' } else { 'software.status' },
			if has_failure { 'Details' } else { 'Status' }, 22 + half, 174, half)
	} else {
		children << software_button('software.release.catalog.back', 'Back', 14, 42, content)
	}
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) find_release_deployment() {
	mut info := C.stat{}
	a.release_deployment_available = software_deployment_path_valid(a.release_deployment_path)
		&& C.lstat(a.release_deployment_path.str, unsafe { &info }) == 0
		&& info.st_mode & 0o170000 == 0o100000
}

fn (mut a SoftwareApp) check_release_deployment() bool {
	if a.worker != unsafe { nil } || a.review != '' { return false }
	a.find_release_deployment()
	if !a.release_deployment_available {
		a.set_status('The release application file is unavailable. Choose a deployment file or enter its absolute path.')
		return false
	}
	return true
}

fn (mut a SoftwareApp) load_release_deployment_path() {
	a.initialize_deployment_field()
	software_repository_text(mut a.deployment_path, a.release_deployment_path)
}

fn (mut a SoftwareApp) audit_release_deployment() {
	if !a.deployment_mode || !a.check_release_deployment() { return }
	a.load_release_deployment_path()
	a.begin_deployment_audit()
}
