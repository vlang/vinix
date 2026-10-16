// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const software_deployment_form_actions = ['software.deployment.choose', 'software.deployment.review',
	'software.deployment.audit', 'software.deployment.snapshot', 'software.policy',
	'software.deployment.release', 'software.deployment.release-audit', 'software.failure']
const software_deployment_form_titles = ['Choose file…', 'Review deployment', 'Check installed',
	'Save installed…', 'Organization policy', 'Review release apps', 'Check release apps', 'Failure details']
const software_deployment_form_help = [
	'Choose a file. Selection fills the path; it starts no package changes.',
	'Review the full app set and removals. Applying it needs separate approval.',
	'Compare exact installed metadata. Trust and health are separate checks.',
	'Save metadata to a new file. Payloads, trust and personal data stay out.',
	'Read organization policy before reviewing a change.',
	'Review all release apps and removals. Applying it needs separate approval.',
	'Compare the release baseline with installed metadata. Trust and health are separate.',
	'Read the complete failure report. This starts no package changes.',
]

fn (a &SoftwareApp) deployment_form_idle() bool {
	return a.deployment_mode && a.worker == unsafe { nil } && a.review == ''
		&& !a.audit_mode && !a.snapshot_mode && !a.policy_mode
}

fn (a &SoftwareApp) deployment_form_action_available(index int) bool {
	if index < 0 || index >= software_deployment_form_actions.len { return false }
	if index in [5, 6]! { return a.release_deployment_available }
	if index == 7 { return a.failure_pages.len > 0 }
	return true
}

fn (mut a SoftwareApp) normalize_deployment_action() {
	if !a.deployment_form_action_available(a.deployment_action) { a.deployment_action = 0 }
}

fn (mut a SoftwareApp) navigate_deployment_form(step int) {
	if !a.deployment_form_idle() || !a.deployment_form_compact { return }
	a.normalize_deployment_action()
	mut next := a.deployment_action + step
	for next >= 0 && next < software_deployment_form_actions.len {
		if a.deployment_form_action_available(next) {
			a.deployment_action = next
			a.focus = false; a.select_all = false
			return
		}
		next += step
	}
}

fn (mut a SoftwareApp) build_deployment_form(width int, height int) ui2.Element {
	a.initialize_deployment_field()
	a.normalize_deployment_action()
	a.deployment_form_compact = true
	mut children := frame_elements(10)
	content := width - 28
	children << software_label('Deployment', 14, 8, width - 98, 28, false)
	children << software_button('software.deployment.back', 'Back', width - 70, 8, 56)
	children << software_label('Deployment file (absolute path)', 14, 42, content, 18, false)
	children << console_field('software.deployment.path', editor_bytes_text(a.deployment_path), 14, 64, content, a.focus)
	if a.deployment_action == 0 && a.deployment_choice_pending {
		children << software_label('Choosing file…', 14, 104, content, 28, false)
	} else {
		children << software_button(software_deployment_form_actions[a.deployment_action],
			software_deployment_form_titles[a.deployment_action], 14, 104, content)
	}
	children << software_label(software_deployment_form_help[a.deployment_action], 14, 142, content, height - 186, false)
	button := (content - 16) / 3
	children << software_button('software.deployment.action.previous', 'Previous', 14, height - 36, button)
	if a.status_readable() { children << software_button('software.status', 'Status', 14 + button + 8, height - 36, button) }
	children << software_button('software.deployment.action.next', 'Next', width - 14 - button, height - 36, button)
	return ui2.screen(app_surface, children)
}
