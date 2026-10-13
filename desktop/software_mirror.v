// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn (mut a SoftwareApp) initialize_mirror_field() {
	if a.mirror_path.cap == 0 { a.mirror_path = []u8{cap: software_deployment_path_limit} }
	unsafe { a.mirror_path.flags |= .noslices }
}

fn (mut a SoftwareApp) clear_mirror_review() {
	a.mirror_snapshot.close()
	unsafe {
		a.mirror_pending.free()
		a.mirror_summary.free()
		for page in a.mirror_pages { page.free() }
		(&array(&a.mirror_pages)).free()
	}
	a.mirror_pending = ''
	a.mirror_summary = ''
	a.mirror_pages = []string{}
	a.mirror_page = 0
	a.mirror_seen = 0
	a.mirror_details = false
}

fn (mut a SoftwareApp) begin_mirror_review() {
	a.clear_review()
	path := editor_bytes_text(a.mirror_path)
	if !software_deployment_path_valid(path) {
		a.set_status('Enter an absolute new directory path without control characters (at most 4096 bytes).')
		return
	}
	a.review_names = []string{cap: a.rows.len}
	if a.mirror_all {
		for row in a.rows {
			if row.requested && row.installed_version != '' { a.review_names << row.id.clone() }
		}
	} else if a.selected >= 0 && a.selected < a.rows.len {
		a.review_names << a.rows[a.selected].id.clone()
	}
	if a.review_names.len == 0 {
		a.set_status('Select a catalog application or choose a nonempty installed application set.')
		return
	}
	a.review = 'mirror'.clone()
	a.mirror_pending = path.clone()
	a.focus = false
	a.start(['mirror-review', a.mirror_pending, ...a.review_names], false)
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.set_status('Checking authenticated catalog versions, dependencies, policy and export space…')
	} else { a.clear_review() }
}

fn (mut a SoftwareApp) mirror_path_parts(path string) {
	mut start := 0
	for start < path.len {
		mut end := if start + 80 < path.len { start + 80 } else { path.len }
		for end < path.len && end > start && path[end] & 0xc0 == 0x80 { end-- }
		// Canonical filesystem names can contain invalid UTF-8 even when the
		// typed path was valid. Always advance on a malformed byte sequence.
		if end == start { end = if start + 80 < path.len { start + 80 } else { path.len } }
		a.mirror_pages << unsafe { tos(path.str + start, end - start).clone() }
		start = end
	}
}

fn (mut a SoftwareApp) decode_mirror_output() !pkgprotocol.Review {
	mut envelope := pkgprotocol.decode_mirror_review(editor_bytes_text(a.output))!
	if envelope.input_destination != a.mirror_pending || envelope.review.names != a.review_names {
		envelope.close()
		return error('offline export intent changed')
	}
	review := envelope.review
	a.mirror_snapshot = pkgprotocol.MirrorReview{ ...envelope, review: pkgprotocol.Review{} }
	a.mirror_details = true
	a.mirror_pages = []string{cap: 128}
	unsafe { a.mirror_pages.flags |= .noslices }
	a.mirror_path_parts(envelope.destination)
	needed := (envelope.cache_needed / 1024 + if envelope.cache_needed % 1024 != 0 { u64(1) } else { u64(0) }).str()
	available := (envelope.cache_available / 1024).str()
	a.mirror_summary = if envelope.shared_disk {
		'Cache acquisition: ${needed} KiB, included in the destination requirement (same filesystem).'
	} else { 'Separate cache filesystem: ${needed} KiB needed · ${available} KiB free. The reserved space applies to each filesystem.' }
	unsafe { needed.free(); available.free() }
	return review
}

fn (mut a SoftwareApp) handle_mirror(event_id string) {
	if a.review != '' {
		match event_id {
			'software.cancel' { a.clear_review(); a.set_status('Offline export cancelled before publication.') }
			'software.mirror.next' {
				if a.mirror_page + 1 < a.mirror_pages.len {
					a.mirror_page++
					if a.mirror_page > a.mirror_seen { a.mirror_seen = a.mirror_page }
				}
			}
			'software.mirror.previous' { if a.mirror_page > 0 { a.mirror_page-- } }
			'software.mirror.packages' {
				if a.review_ready && a.mirror_seen + 1 >= a.mirror_pages.len { a.mirror_details = false }
			}
			else {}
		}
		return
	}
	match event_id {
		'software.mirror.path' { a.focus = true; a.select_all = false }
		'software.mirror.scope' { a.mirror_all = !a.mirror_all }
		'software.mirror.review' { a.begin_mirror_review() }
		'software.mirror.back' { a.mirror_mode = false; a.focus = false; a.select_all = false }
		else {}
	}
}

fn (mut a SoftwareApp) mirror_key_input(input string) {
	if !a.focus || a.review != '' || a.worker != unsafe { nil } { return }
	match input {
		'\x01' { a.select_all = true }
		'\x7f', '\x08' { console_backspace(mut a.mirror_path, a.select_all); a.select_all = false }
		'\x1b', '\r', '\n' { a.focus = false; a.select_all = false }
		else {
			length := if a.select_all { 0 } else { a.mirror_path.len }
			if input.len > software_deployment_path_limit - length || !software_deployment_text_valid(input) {
				a.set_status('The export path exceeds 4096 bytes or contains invalid text. The field was kept intact.')
				return
			}
			if a.select_all { a.mirror_path.clear() }
			for byte in input { a.mirror_path << byte }
			a.select_all = false
		}
	}
}

fn (mut a SoftwareApp) build_mirror(width int, height int) ui2.Element {
	a.initialize_mirror_field()
	mut children := frame_elements(24)
	children << software_label('Export offline repository', 14, 8, width - 28, 28, false)
	if a.review != '' {
		children << software_label(a.review_summary, 14, 46, width - 28, 44, false)
		children << software_label('Destination directory (complete path, shown in parts)', 14, 100, width - 28, 28, false)
		if a.mirror_pages.len > 0 {
			children << software_label(a.mirror_pages[a.mirror_page], 14, 138, width - 28, 72, false)
			children << software_button('software.mirror.previous', 'Previous path part', 14, 220, 160)
			children << software_button('software.mirror.next', 'Next path part', 186, 220, 160)
		}
		children << software_label(a.mirror_summary, 14, 262, width - 28, 60, false)
		children << software_label('Only the selected dependency closure has payloads on this media. Signed catalogs retain their original expiry. Consumers must enroll each file:// repository with its original publisher key.', 14, 338, width - 28, 72, false)
		children << software_button('software.cancel', 'Cancel', 14, height - 138, 110)
		if a.review_ready && a.mirror_seen + 1 >= a.mirror_pages.len {
			children << software_button('software.mirror.packages', 'Review packages', 136, height - 138, 170)
		}
	} else {
		children << software_label('New directory on local disk or mounted offline media', 14, 54, width - 28, 28, false)
		children << console_field('software.mirror.path', editor_bytes_text(a.mirror_path), 14, 90, width - 28, a.focus)
		children << software_button('software.mirror.scope', if a.mirror_all { 'All installed application roots' } else { 'Selected catalog application' }, 14, 138, 270)
		if !a.mirror_all && a.selected >= 0 && a.selected < a.rows.len {
			children << software_label(a.rows[a.selected].name, 14, 176, width - 28, 28, false)
		}
		children << software_label('Exports current authenticated catalog versions and their complete dependency closure. Review publishers, permissions, licenses and disk requirements before confirming. The installed applications stay as they are.', 14, 220, width - 28, 72, false)
		if a.worker == unsafe { nil } {
			children << software_button('software.mirror.review', 'Review export', 14, 326, 150)
			children << software_button('software.mirror.back', 'Back to catalog', 176, 326, 160)
		}
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	children << software_label(a.status, 14, height - 88, width - 28, 80, false)
	return ui2.screen(app_surface, children)
}
