// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) deployment_review_running() bool {
	return a.deployment_mode && a.worker != unsafe { nil } && a.worker_review
		&& a.review == 'deploy' && a.deployment_pending != ''
}

fn (mut a SoftwareApp) stop_deployment_review() {
	// Proposals are read-only. This predicate excludes approved transactions,
	// snapshot writers and the independently managed audit worker.
	if !a.deployment_review_running() { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.worker_review = false
	a.clear_review(); a.output.clear(); a.output_truncated = false
	a.focus = false; a.select_all = false
	a.set_status('Deployment review stopped. No changes were started. Review again to continue.')
}

fn (mut a SoftwareApp) build_deployment_compact(width int, height int) ui2.Element {
	a.deployment_form_compact = false
	if a.deployment_form_idle() && !a.details_mode && width >= 320 && height >= 240 {
		return a.build_deployment_form(width, height)
	}
	mut children := frame_elements(9)
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil } && !a.details_mode
	readable := a.package_review_readable() && !a.details_mode
	children << software_label('Deployment · enlarge for details', 14, 8, width - 28, 28, false)
	if a.details_mode {
		children << software_button('software.details.back', 'Back to review', 14, 46, if width > 202 { 174 } else { width - 28 })
	} else if a.deployment_review_running() {
		children << software_button('software.deployment.stop', 'Stop review', 14, 46, if width > 202 { 174 } else { width - 28 })
	} else if a.worker == unsafe { nil } {
		children << software_button(if a.review != '' { 'software.cancel' } else { 'software.deployment.back' },
			if a.review != '' { 'Cancel review' } else { 'Back to catalog' }, 14, 46, if width > 202 { 174 } else { width - 28 })
	} else {
		children << software_label('Wait for deployment to finish.', 14, 46, width - 28, 28, false)
	}
	if readable { children << software_button('software.report.read', 'Read plan', 14, 84, if width > 202 { 174 } else { width - 28 }) }
	if available {
		children << software_button('software.failure', 'Failure details', 14, if readable { 122 } else { 84 }, if width > 202 { 174 } else { width - 28 })
	}
	progress := a.progress_seen && height >= 240
	if progress { children << a.progress_bar(width, height) }
	minimum := if readable && available { 160 } else if readable || available { 122 } else { 84 }
	footer := height - if progress { 88 } else { 98 }
	y := if footer > minimum { footer } else { minimum }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
