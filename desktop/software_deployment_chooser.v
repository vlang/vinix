// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import desktop.sessioncore
import desktop.sessionipc

const software_deployment_dialog_key = 'software.deployment'

fn software_deployment_choice_directory(path string, home string) string {
	// Session records have a smaller bound than the manually editable path.
	// Fall back to a navigable directory rather than truncate a filename.
	record := sessioncore.Text{}
	if software_deployment_path_valid(path) {
		directory := os.dir(path)
		if directory.len < record.bytes.len { return directory }
		unsafe { directory.free() }
	}
	if software_deployment_path_valid(home) && home.len < record.bytes.len { return home.clone() }
	return '/'.clone()
}

fn (mut a SoftwareApp) choose_deployment_file() {
	if a.deployment_choice_pending || !a.deployment_mode || a.review != '' || a.worker != unsafe { nil }
		|| a.snapshot_mode || a.audit_mode { return }
	home := os.home_dir()
	directory := software_deployment_choice_directory(editor_bytes_text(a.deployment_path), home)
	defer { unsafe { home.free(); directory.free() } }
	// No extension filter: organization manifests, exported locks and saved
	// installed snapshots are JSON documents with publisher-selected filenames.
	if !sessionipc.dialog_open(software_deployment_dialog_key, 0, 'Choose deployment file', directory, '', '') {
		a.set_status('The file dialog is unavailable. Enter an absolute deployment file path, then review it.')
		return
	}
	a.deployment_choice_pending = true
	a.deployment_choice_current = true
	a.focus = false; a.select_all = false
	a.set_status('Choose a deployment file. Selecting it fills the path; review the deployment before applying any changes.')
}

fn (mut a SoftwareApp) finish_deployment_choice(path string) bool {
	if !a.deployment_choice_pending { return false }
	current := a.deployment_choice_current && a.deployment_mode && a.review == '' && a.worker == unsafe { nil }
		&& !a.snapshot_mode && !a.audit_mode
	a.deployment_choice_pending = false
	a.deployment_choice_current = false
	// Navigation, typing or another operation owns the current form. Drain a
	// late dialog result without replacing that draft, review or status.
	if !current { return true }
	if path == '' {
		a.set_status('File selection cancelled or unavailable. The deployment path was kept intact.')
		return true
	}
	if !software_deployment_path_valid(path) {
		a.set_status('The selected deployment path is invalid. Enter an absolute path without control characters (at most 4096 bytes). The field was kept intact.')
		return true
	}
	a.initialize_deployment_field()
	software_repository_text(mut a.deployment_path, path)
	a.focus = false; a.select_all = false
	message := 'Deployment file selected: ' + path + '. Review deployment before applying any changes.'
	a.set_status(message)
	unsafe { message.free() }
	return true
}

fn (mut a SoftwareApp) poll_deployment_choice() bool {
	if !a.deployment_choice_pending { return false }
	if path := sessionipc.dialog_take(software_deployment_dialog_key) {
		defer { unsafe { path.free() } }
		return a.finish_deployment_choice(path)
	}
	return false
}
