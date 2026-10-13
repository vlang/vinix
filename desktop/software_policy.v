// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol
import tools.packages.pkgadmin

enum SoftwarePolicyWorker { none list review apply }

struct SoftwarePolicyPage {
	section int
	title string
	text string
mut:
	label string
}

const software_policy_sections = ['software.policy.general', 'software.policy.allowed', 'software.policy.pins',
	'software.policy.permissions', 'software.policy.licenses', 'software.policy.source', 'software.policy.impacts']
const software_policy_section_labels = ['General', 'Allowed IDs', 'Version pins', 'Permissions', 'Licenses', 'Policy file']

fn (mut a SoftwareApp) clear_policy_pages() {
	unsafe {
		for page in a.policy_pages { page.title.free(); page.text.free(); page.label.free() }
		(&array(&a.policy_pages)).free()
	}
	a.policy_pages = []SoftwarePolicyPage{}
	a.policy_page = 0; a.policy_section = 0
	for index in 0 .. 7 { a.policy_starts[index] = -1 }
}

fn (mut a SoftwareApp) clear_policy_review() {
	a.policy_snapshot.close()
	unsafe { a.policy_pending.free() }
	a.policy_pending = ''
	a.policy_review_ready = false
}

fn (mut a SoftwareApp) clear_policy() {
	a.clear_policy_review()
	a.clear_policy_pages()
	a.policy_document.close()
	unsafe { a.policy_path.free(); a.policy_result.free() }
	a.policy_path = []u8{}
	a.policy_result = ''
	a.policy_ready = false
}

fn (mut a SoftwareApp) initialize_policy_path() {
	if a.policy_path.cap == 0 { a.policy_path = []u8{cap: software_deployment_path_limit} }
	unsafe { a.policy_path.flags |= .noslices }
}

fn (mut a SoftwareApp) read_policy() {
	a.initialize_policy_path()
	a.clear_policy_review()
	a.clear_policy_pages()
	a.policy_ready = false; a.focus = false; a.select_all = false
	mut arguments := ['policy']
	a.start(arguments, true)
	unsafe { (&array(&arguments)).free() }
	if a.worker != unsafe { nil } {
		a.policy_worker = .list
		a.set_status('Reading the active organization policy…')
	}
}

fn (mut a SoftwareApp) load_policy_document() {
	a.policy_ready = false
	document := pkgprotocol.decode_policy_document(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Invalid organization policy response. Reload before reviewing a change.')
		return
	}
	a.policy_document.close()
	a.policy_document = document
	a.policy_ready = true
	a.prepare_policy_pages(false)
	if a.policy_result != '' {
		a.set_status(a.policy_result)
		unsafe { a.policy_result.free() }; a.policy_result = ''
	} else {
		a.set_status('Browse the active restrictions, or enter a policy file to review a change. License acceptance and firmware permission are explicit settings.')
	}
}

fn (mut a SoftwareApp) begin_policy_review() {
	if !a.policy_ready { a.set_status('Reload the active policy before reviewing a change.'); return }
	path := editor_bytes_text(a.policy_path)
	if !software_deployment_path_valid(path) {
		a.set_status('Enter an absolute policy file path without control characters (at most 4096 bytes).'); return
	}
	a.clear_policy_review()
	a.policy_pending = path.clone()
	a.focus = false; a.select_all = false
	mut arguments := ['policy-review', a.policy_pending]
	a.start(arguments, false)
	unsafe { (&array(&arguments)).free() }
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.policy_worker = .review
		a.set_status('Reading previous and proposed settings and the effects on every installed application and runtime…')
	} else { a.clear_policy_review() }
}

fn (mut a SoftwareApp) load_policy_review() {
	mut review := pkgprotocol.decode_policy_review(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.clear_policy_review(); a.prepare_policy_pages(false)
		a.set_status('Invalid or incomplete policy review. Review the file again before confirming.'); return
	}
	if !a.policy_ready || review.architecture != a.policy_document.architecture || a.policy_pending == '' {
		review.close(); a.clear_policy_review(); a.prepare_policy_pages(false)
		a.set_status('The policy review does not match this system or request. Reload and review again.'); return
	}
	a.policy_snapshot.close()
	a.policy_snapshot = review
	a.policy_review_ready = true
	a.prepare_policy_pages(true)
	a.policy_section = 5; a.policy_page = a.policy_starts[5]
	a.set_status('Review the policy file, previous/proposed settings and installed-app effects. Confirm saves policy; deployment remains a separate reviewed operation.')
}

fn (mut a SoftwareApp) handle_policy(event_id string) {
	match event_id {
		'software.policy.path' { if !a.policy_review_ready { a.focus = true; a.select_all = false } }
		'software.policy.review' { if !a.policy_review_ready { a.begin_policy_review() } }
		'software.policy.reload' { if !a.policy_review_ready { a.read_policy() } }
		'software.policy.back' {
			if a.policy_review_ready { return }
			a.clear_policy(); a.policy_mode = false; a.deployment_mode = true
			a.focus = false; a.select_all = false
			a.set_status('Review a deployment file, or manage organization policy.')
		}
		'software.policy.cancel' {
			if !a.policy_review_ready { return }
			a.clear_policy_review(); a.prepare_policy_pages(false)
			a.set_status('Policy change cancelled before making changes.')
		}
		'software.policy.confirm' {
			if !a.policy_review_ready { return }
			if a.administration_required {
				// Check the real transport encoding before requesting a password.
				// A printable path can exceed the bound after JSON escaping.
				mut request := pkgadmin.Request{ nonce: '00000000000000000000000000000000',
					arguments: ['policy-apply'.clone(), a.policy_snapshot.fingerprint.clone(), a.policy_pending.clone()] }
				defer { request.close() }
				encoded := request.encode() or {
					unsafe { err.free() }
					a.set_status('This policy path exceeds the administrator request limit after encoding. Use a shorter path, then review it again.'); return
				}
				unsafe { encoded.free() }
			}
			mut arguments := ['policy-apply', a.policy_snapshot.fingerprint, a.policy_pending]
			a.start(arguments, false)
			unsafe { (&array(&arguments)).free() }
			if a.worker != unsafe { nil } {
				a.policy_worker = .apply
				a.clear_policy_review(); a.prepare_policy_pages(false)
				if !a.admin_prompt { a.set_status('Rechecking the reviewed policy and saving the confirmed change…') }
			}
		}
		'software.policy.previous', 'software.policy.next' {
			mut index := a.policy_page + if event_id == 'software.policy.next' { 1 } else { -1 }
			for index >= 0 && index < a.policy_pages.len {
				if a.policy_pages[index].section == a.policy_section { a.policy_page = index; break }
				index += if event_id == 'software.policy.next' { 1 } else { -1 }
			}
		}
		else {
			for section, action in software_policy_sections {
				if event_id == action && a.policy_starts[section] >= 0 {
					a.policy_section = section; a.policy_page = a.policy_starts[section]; a.focus = false
					return
				}
			}
		}
	}
}

fn (mut a SoftwareApp) policy_paste_input(input string) {
	if !a.focus || a.policy_review_ready || a.worker != unsafe { nil } { return }
	a.initialize_policy_path()
	length := if a.select_all { 0 } else { a.policy_path.len }
	if input.len > software_deployment_path_limit - length || !software_deployment_text_valid(input) {
		a.set_status('Policy path input was kept intact: use valid UTF-8 without control characters, at most 4096 bytes.'); return
	}
	if a.select_all { a.policy_path.clear() }
	for byte in input { a.policy_path << byte }
	a.select_all = false
}

fn (mut a SoftwareApp) policy_key_input(input string) {
	if !a.focus || a.policy_review_ready || a.worker != unsafe { nil } { return }
	match input {
		'\x01' { a.select_all = true }
		'\x7f', '\x08' { console_backspace(mut a.policy_path, a.select_all); a.select_all = false }
		'\x1b', '\r', '\n' { a.focus = false }
		else { a.policy_paste_input(input) }
	}
}

fn (mut a SoftwareApp) build_policy(width int, height int) ui2.Element {
	a.initialize_policy_path()
	mut children := frame_elements(20)
	children << software_label(if a.policy_review_ready { 'Review organization policy' } else { 'Organization policy' }, 14, 8, 360, 28, false)
	if a.worker == unsafe { nil } {
		children << software_button(if a.policy_review_ready { 'software.policy.impacts' } else { 'software.policy.back' },
			if a.policy_review_ready { 'Installed-app effects' } else { 'Back to deployment' }, width - 174, 8, 160)
	}
	children << software_label('Policy file', 14, 46, 110, 28, false)
	if a.policy_review_ready {
		children << software_label(a.policy_pending, 130, 46, width - 144, 28, false)
	} else {
		children << console_field('software.policy.path', editor_bytes_text(a.policy_path), 130, 46, width - 328, a.focus)
		if a.worker == unsafe { nil } {
			children << software_button(if a.policy_ready { 'software.policy.review' } else { 'software.policy.reload' },
				if a.policy_ready { 'Review policy' } else { 'Reload policy' }, width - 174, 46, 160)
		}
	}
	if a.policy_ready {
		for section in 0 .. 6 {
			children << software_button(if section == 5 && !a.policy_review_ready { 'software.policy.reload' } else { software_policy_sections[section] },
				if section == 5 && !a.policy_review_ready { 'Reload' } else { software_policy_section_labels[section] }, 14 + section * 100, 90, 94)
		}
		if a.policy_page >= 0 && a.policy_page < a.policy_pages.len {
			page := a.policy_pages[a.policy_page]
			children << software_label(page.title, 14, 132, width - 28, 28, false)
			children << ui2.label('', page.text, ui2.rect(14, 174, f64(width - 28), f64(height - 328)),
				ui2.TextStyle{ color: body_text, size: 12, lines: 14 })
			children << software_label(page.label, 238, height - 138, if a.policy_review_ready { 100 } else { width - 252 }, 28, false)
		}
	}
	if a.worker == unsafe { nil } {
		children << software_button('software.policy.previous', 'Previous', 14, height - 138, 100)
		children << software_button('software.policy.next', 'Next', 126, height - 138, 100)
		if a.policy_review_ready {
			children << software_button('software.policy.confirm', 'Confirm policy', width - 292, height - 138, 148)
			children << software_button('software.policy.cancel', 'Cancel', width - 132, height - 138, 118)
		}
	}
	a.add_status_footer(mut children, width, height, false)
	return ui2.screen(app_surface, children)
}
