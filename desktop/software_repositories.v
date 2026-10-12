// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import ui2
import tools.packages.pkgprotocol

enum SoftwareRepositoryWorker {
	none
	list
	review
	enroll
	revoke
	refresh
}

fn software_repository_text(mut buffer []u8, text string) {
	unsafe { buffer.flags |= .noslices }
	buffer.clear()
	for byte in text { buffer << byte }
}

fn (mut a SoftwareApp) initialize_repository_fields() {
	if a.repository_id.cap == 0 { a.repository_id = []u8{cap: 128} }
	if a.repository_url.cap == 0 { a.repository_url = []u8{cap: 4096} }
	if a.repository_key.cap == 0 { a.repository_key = []u8{cap: 64} }
	unsafe {
		a.repository_id.flags |= .noslices
		a.repository_url.flags |= .noslices
		a.repository_key.flags |= .noslices
	}
}

fn (mut a SoftwareApp) clear_repository_review() {
	a.repository_review.close()
	a.clear_repository_pages()
	unsafe {
		a.repository_operation.free()
		a.repository_pending.id.free()
		a.repository_pending.url.free()
		a.repository_pending.public_key.free()
	}
	a.repository_operation = ''
	a.repository_pending = pkgprotocol.Repository{}
	a.repository_review_ready = false
}

fn (mut a SoftwareApp) clear_repository_pages() {
	unsafe {
		a.repository_summary.free()
		for page in a.repository_url_pages { page.free() }
		(&array(&a.repository_url_pages)).free()
		for label in a.repository_page_labels { label.free() }
		(&array(&a.repository_page_labels)).free()
	}
	a.repository_summary = ''
	a.repository_url_pages = []string{}
	a.repository_page_labels = []string{}
	a.repository_url_page = 0
	a.repository_url_seen = 0
}

fn (mut a SoftwareApp) read_repositories() {
	a.initialize_repository_fields()
	a.start(['--json', 'repo-list'], true)
	if a.worker != unsafe { nil } {
		a.repository_worker = .list
		a.set_status('Reading configured repositories and retained sequence history…')
	}
}

fn (mut a SoftwareApp) load_repositories() {
	a.initialize_repository_fields()
	status := pkgprotocol.decode_repositories(editor_bytes_text(a.output)) or {
		a.set_status('Invalid repository status. Reload the list or check the package service.')
		return
	}
	a.repository_status.close()
	a.repository_status = status
	a.repository_selected = -1
	a.repository_scroll = 0
	for i, repository in status.repositories {
		if repository.id == editor_bytes_text(a.repository_id) { a.repository_selected = i }
	}
	if a.repository_result != '' {
		a.set_status(a.repository_result)
		unsafe { a.repository_result.free() }
		a.repository_result = ''
	} else {
		a.set_status('Select a repository or enter its ID, source URL and independently authenticated publisher key. Review every trust change before confirming.')
	}
}

fn (mut a SoftwareApp) begin_repository_review(operation string) {
	a.initialize_repository_fields()
	a.clear_repository_review()
	id := editor_bytes_text(a.repository_id)
	url := editor_bytes_text(a.repository_url)
	key := editor_bytes_text(a.repository_key)
	if operation == 'enroll' {
		pkgprotocol.validate_repository(id, url, key) or {
			a.set_status(err.msg())
			return
		}
	} else if id.len == 0 {
		a.set_status('Enter or select the repository ID to revoke.')
		return
	}
	a.repository_operation = operation.clone()
	a.repository_pending = pkgprotocol.Repository{ id: id.clone(), url: url.clone(), public_key: key.clone() }
	a.repository_focus = 0
	a.start(if operation == 'enroll' {
		['repo-review', 'enroll', id, url, key]
	} else {
		['repo-review', 'revoke', id]
	}, false)
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.repository_worker = .review
		a.set_status(if operation == 'enroll' {
			'Verifying the signed catalog with the supplied publisher key…'
		} else {
			'Reading the exact trust configuration to revoke…'
		})
	} else {
		a.clear_repository_review()
	}
}

fn (mut a SoftwareApp) repository_url_parts(url string, label string) {
	mut start := 0
	mut part := 1
	for start < url.len {
		mut end := if start + 96 < url.len { start + 96 } else { url.len }
		for end > start && end < url.len && url[end] & 0xc0 == 0x80 { end-- }
		if end == start { end = if start + 96 < url.len { start + 96 } else { url.len } }
		a.repository_url_pages << unsafe { tos(url.str + start, end - start).clone() }
		number := part.str()
		a.repository_page_labels << '${label} · part ${number}'
		unsafe { number.free() }
		start = end
		part++
	}
}

fn (mut a SoftwareApp) load_repository_review() {
	mut review := pkgprotocol.decode_repository_review(editor_bytes_text(a.output)) or {
		a.clear_repository_review()
		a.set_status('Unsupported or incomplete repository review. Review the trust change again.')
		return
	}
	if review.operation != a.repository_operation || review.id != a.repository_pending.id
		|| (review.operation == 'enroll' && (review.url != a.repository_pending.url || review.public_key != a.repository_pending.public_key)) {
		review.close()
		a.clear_repository_review()
		a.set_status('The service returned a different repository trust change. Review it again.')
		return
	}
	a.repository_review.close()
	a.clear_repository_pages()
	a.repository_review = review
	a.repository_review_ready = true
	a.repository_url_pages = []string{cap: 128}
	a.repository_page_labels = []string{cap: 128}
	unsafe {
		a.repository_url_pages.flags |= .noslices
		a.repository_page_labels.flags |= .noslices
	}
	a.repository_url_parts(review.url, 'Source URL')
	if review.previous_url != '' && review.previous_url != review.url {
		a.repository_url_parts(review.previous_url, 'Previous source URL')
	}
	if review.operation == 'enroll' {
		sequence := review.sequence.str()
		count := review.package_count.str()
		remembered := review.remembered_sequence.str()
		expiry := if review.expires <= 253402300799 {
			time.unix(review.expires).format_ss()
		} else {
			review.expires.str()
		}
		unit := if review.expires <= 253402300799 { ' UTC' } else { ' (Unix seconds)' }
		a.repository_summary = '${count} signed catalog entries · sequence ${sequence}\nRemembered sequence: ${remembered} · ${review.architecture}\nExpires: ${expiry}${unit}'
		unsafe {
			sequence.free()
			count.free()
			remembered.free()
			expiry.free()
		}
		a.set_status(if review.previous_public_key != '' && review.previous_public_key != review.public_key {
			'Confirming replaces this publisher key. Old-key apps lose launch and rollback trust. Compare the new key through your trusted channel before confirming.'
		} else {
			'Compare the exact publisher key through your trusted channel. Confirming enables trust and refreshes signed catalogs; it does not install applications.'
		})
	} else {
		a.repository_summary = 'Revocation disables acquisition, launch and rollback.'.clone()
		a.set_status('Confirming revokes this exact repository configuration. Installed payloads, personal data and sequence history remain; uninstall stays available.')
	}
}

fn (mut a SoftwareApp) handle_repositories(event_id string) {
	if a.repository_operation != '' {
		match event_id {
			'software.repository.cancel' {
				a.clear_repository_review()
				a.set_status('Repository trust change cancelled before publication.')
			}
			'software.repository.url-next' {
				if a.repository_url_page + 1 < a.repository_url_pages.len {
					a.repository_url_page++
					if a.repository_url_page > a.repository_url_seen {
						a.repository_url_seen = a.repository_url_page
					}
				}
			}
			'software.repository.url-previous' {
				if a.repository_url_page > 0 { a.repository_url_page-- }
			}
			'software.repository.confirm' {
				if !a.repository_review_ready || a.repository_url_seen + 1 < a.repository_url_pages.len {
					return
				}
				review := a.repository_review
				a.start(if review.operation == 'enroll' {
					['repo-apply', review.fingerprint, 'enroll', review.id, review.url,
						review.public_key]
				} else {
					['repo-apply', review.fingerprint, 'revoke', review.id]
				}, false)
				if a.worker != unsafe { nil } {
					a.repository_worker = if review.operation == 'enroll' {
						.enroll
					} else {
						.revoke
					}
					a.clear_repository_review()
				}
			}
			else {}
		}
		return
	}
	for slot, action in software_row_actions {
		if event_id == action && a.repository_scroll + slot < a.repository_status.repositories.len {
			a.repository_selected = a.repository_scroll + slot
			repository := a.repository_status.repositories[a.repository_selected]
			software_repository_text(mut a.repository_id, repository.id)
			software_repository_text(mut a.repository_url, repository.url)
			software_repository_text(mut a.repository_key, repository.public_key)
			a.repository_focus = 0
			return
		}
	}
	match event_id {
		'software.repository.back' {
			a.repository_mode = false
			a.start(['view'], true)
		}
		'software.repository.reload' { a.read_repositories() }
		'software.repository.new' {
			a.repository_id.clear()
			a.repository_url.clear()
			a.repository_key.clear()
			a.repository_selected = -1
			a.repository_focus = 1
			a.select_all = false
		}
		'software.repository.id' {
			a.repository_focus = 1
			a.select_all = false
		}
		'software.repository.url' {
			a.repository_focus = 2
			a.select_all = false
		}
		'software.repository.key' {
			a.repository_focus = 3
			a.select_all = false
		}
		'software.repository.enroll' { a.begin_repository_review('enroll') }
		'software.repository.revoke' { a.begin_repository_review('revoke') }
		'software.up' {
			a.repository_scroll = if a.repository_scroll > a.page_rows {
				a.repository_scroll - a.page_rows
			} else {
				0
			}
		}
		'software.down' {
			if a.repository_scroll + a.page_rows < a.repository_status.repositories.len {
				a.repository_scroll += a.page_rows
			}
		}
		else {}
	}
}

fn (mut a SoftwareApp) repository_key_input(input string) {
	if a.worker != unsafe { nil } { return }
	if a.repository_operation != '' {
		if input == '\x1b' { a.handle_repositories('software.repository.cancel') }
		return
	}
	match input {
		'\t' {
			a.repository_focus = a.repository_focus % 3 + 1
			a.select_all = false
			return
		}
		'\x1b[Z' {
			a.repository_focus = if a.repository_focus <= 1 { 3 } else { a.repository_focus - 1 }
			a.select_all = false
			return
		}
		'\x1b' {
			a.repository_focus = 0
			return
		}
		'\r', '\n' {
			a.begin_repository_review('enroll')
			return
		}
		'\x01' {
			a.select_all = true
			return
		}
		else {}
	}
	if a.repository_focus == 0 { return }
	mut field := match a.repository_focus {
		1 { &a.repository_id }
		2 { &a.repository_url }
		else { &a.repository_key }
	}
	unsafe { field.flags |= .noslices }
	if input in ['\x7f', '\x08'] {
		console_backspace(mut *field, a.select_all)
	} else {
		limit := match a.repository_focus {
			1 { 128 }
			2 { 4096 }
			else { 64 }
		}
		mut printable_bytes := 0
		for byte in input { if byte >= 32 { printable_bytes++ } }
		current_length := if a.select_all { 0 } else { field.len }
		if current_length + printable_bytes > limit {
			a.set_status('Repository field exceeds its supported length. Shorten it; input was not truncated.')
			return
		}
		console_paste_field(mut *field, input, limit, a.select_all)
	}
	a.select_all = false
}

fn (mut a SoftwareApp) build_repositories(width int, height int) ui2.Element {
	a.initialize_repository_fields()
	mut children := frame_elements(64)
	children << software_label('Software', 14, 8, 150, 28, false)
	children << software_label('Repositories', 170, 8, width - 358, 28, false)
	reviewing := a.repository_operation != ''
	if !reviewing {
		children << software_button('software.repository.back', 'Back to Software', width - 188, 8, 174)
		children << software_button('software.repository.reload', 'Reload list', 14, 46, 150)
		children << software_button('software.repository.new', 'New repository', 176, 46, 150)
	}
	for slot in 0 .. a.page_rows {
		index := a.repository_scroll + slot
		if index >= a.repository_status.repositories.len { break }
		children << software_button(software_row_actions[slot], a.repository_status.repositories[index].id, 14, 90 + slot * 30, 236)
	}
	if !reviewing {
		children << software_button('software.up', 'Previous', 14, height - 138, 110)
		children << software_button('software.down', 'Next', 136, height - 138, 110)
		children << software_label('Repository ID', 274, 90, width - 288, 22, false)
		children << console_field('software.repository.id', editor_bytes_text(a.repository_id), 274, 116, width - 288, a.repository_focus == 1)
		children << software_label('HTTPS URL or absolute file:// repository path', 274, 154, width - 288, 22, false)
		children << console_field('software.repository.url', editor_bytes_text(a.repository_url), 274, 180, width - 288, a.repository_focus == 2)
		children << software_label('Publisher public key (lowercase hexadecimal)', 274, 218, width - 288, 22, false)
		children << console_field('software.repository.key', editor_bytes_text(a.repository_key), 274, 244, width - 288, a.repository_focus == 3)
		children << software_label('Obtain the publisher key through a trusted channel. Compare it during review; the repository cannot choose its own key.', 274, 292, width - 288, 72, false)
		children << software_button('software.repository.enroll', 'Review trust', 274, height - 176, 150)
		children << software_button('software.repository.revoke', 'Review revocation', 436, height - 176, 174)
	} else if a.repository_review_ready {
		review := a.repository_review
		children << software_label('Repository: ${review.id}', 274, 90, width - 288, 60, true)
		if a.repository_url_pages.len > 0 {
			children << software_label(a.repository_page_labels[a.repository_url_page], 274, 154, width - 288, 22, false)
			children << software_label(a.repository_url_pages[a.repository_url_page], 274, 182, width - 288, 72, false)
		}
		if a.repository_url_pages.len > 1 {
			children << software_button('software.repository.url-previous', 'Previous URL part', 274, 260, 150)
			children << software_button('software.repository.url-next', 'Next URL part', 436, 260, 174)
		}
		children << software_label('Publisher key: ${review.public_key}', 274, 298, width - 288, 48, true)
		children << software_label(a.repository_summary, 274, 352, width - 288, 60, false)
		if review.previous_public_key != '' && review.previous_public_key != review.public_key {
			children << software_label('Previous key: ${review.previous_public_key}', 274, 414, width - 288, 48, true)
		}
		if a.repository_url_seen + 1 >= a.repository_url_pages.len {
			children << software_button('software.repository.confirm', if review.operation == 'enroll' {
				'Confirm trust'
			} else {
				'Confirm revocation'
			}, 274, height - 138, 174)
		} else {
			children << software_label('Review every URL part to enable confirmation.', 14, 46, width - 28, 28, false)
		}
	}
	if reviewing {
		children << software_button('software.repository.cancel', 'Cancel', width - 174, height - 138, 160)
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	children << software_label(a.status, 14, height - if a.progress_seen { 88 } else { 98 }, width - 28, if a.progress_seen { 80 } else { 90 }, false)
	return ui2.screen(app_surface, children)
}
