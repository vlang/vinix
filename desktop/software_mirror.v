// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

const software_saved_deployment_changed = 'saved deployment changed; save a new snapshot before exporting it'

fn (mut a SoftwareApp) clear_mirror_source() {
	unsafe { a.mirror_source.free(); a.mirror_source_sha256.free() }
	a.mirror_source = ''; a.mirror_source_sha256 = ''
}

fn (mut a SoftwareApp) export_deployment_snapshot() {
	if !a.snapshot_ready || a.snapshot_saved.packages == 0 { return }
	// Capture receipt identity before retiring it. Choosing a destination does
	// not acquire payloads or authorize publication; the full review still runs.
	a.clear_mirror_source()
	a.mirror_source = a.snapshot_pending.clone()
	a.mirror_source_sha256 = a.snapshot_saved.sha256.clone()
	a.clear_deployment_snapshot()
	a.clear_review()
	a.repository_mode = false; a.deployment_mode = false; a.mirror_mode = true
	a.mirror_locked = true; a.mirror_all = false
	a.initialize_mirror_field()
	a.mirror_path.clear(); a.mirror_lock_path.clear()
	for byte in a.mirror_source { a.mirror_lock_path << byte }
	a.focus = true; a.select_all = false; a.mirror_lock_focus = false
	a.set_status('Choose a new offline export directory. Review will authenticate the exact saved deployment and check permissions, licenses and space before publication.')
}

fn (mut a SoftwareApp) initialize_mirror_field() {
	if a.mirror_path.cap == 0 { a.mirror_path = []u8{cap: software_deployment_path_limit} }
	if a.mirror_lock_path.cap == 0 { a.mirror_lock_path = []u8{cap: software_deployment_path_limit} }
	unsafe { a.mirror_path.flags |= .noslices; a.mirror_lock_path.flags |= .noslices }
}

fn (mut a SoftwareApp) clear_mirror_review() {
	a.mirror_snapshot.close()
	unsafe {
		a.mirror_pending.free()
		a.mirror_lock_pending.free()
		a.mirror_lock_sha256.free()
		a.mirror_summary.free()
		for page in a.mirror_pages { page.free() }
		for label in a.mirror_page_labels { label.free() }
		(&array(&a.mirror_pages)).free()
		(&array(&a.mirror_page_labels)).free()
	}
	a.mirror_pending = ''
	a.mirror_lock_pending = ''
	a.mirror_lock_sha256 = ''
	a.mirror_summary = ''
	a.mirror_pages = []string{}
	a.mirror_page_labels = []string{}
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
	if a.mirror_locked {
		source := if a.mirror_source != '' { a.mirror_source } else { editor_bytes_text(a.mirror_lock_path) }
		if !software_deployment_path_valid(source) {
			a.set_status('Enter an absolute organization deployment lock path without control characters (at most 4096 bytes).')
			return
		}
		a.mirror_lock_pending = source.clone()
	}
	a.review_names = []string{cap: a.rows.len}
	unsafe { a.review_names.flags |= .noslices }
	if a.mirror_locked {
		// The authenticated document determines the roots, independently of
		// the selected catalog row or this machine's installed applications.
	} else if a.mirror_all {
		for row in a.rows {
			if row.requested && row.installed_version != '' { a.review_names << row.id.clone() }
		}
	} else if a.selected >= 0 && a.selected < a.rows.len {
		a.review_names << a.rows[a.selected].id.clone()
	}
	if !a.mirror_locked && a.review_names.len == 0 {
		a.set_status('Select a catalog application or choose a nonempty installed application set.')
		return
	}
	a.review = 'mirror'.clone()
	a.mirror_pending = path.clone()
	a.focus = false
	a.select_all = false
	a.start(if a.mirror_locked {
		['mirror-deployment-review', a.mirror_pending, a.mirror_lock_pending]
	} else { ['mirror-review', a.mirror_pending, ...a.review_names] }, false)
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.set_status(if a.mirror_locked { 'Checking exact deployment versions, trusted publishers, dependencies, policy and export space…' }
			else { 'Checking authenticated catalog versions, dependencies, policy and export space…' })
	} else { a.clear_review() }
}

fn (mut a SoftwareApp) mirror_path_parts(path string) {
	a.mirror_review_parts(path, 'Destination directory')
}

fn (mut a SoftwareApp) mirror_review_parts(path string, label string) {
	mut start := 0
	for start < path.len {
		mut end := if start + 80 < path.len { start + 80 } else { path.len }
		for end < path.len && end > start && path[end] & 0xc0 == 0x80 { end-- }
		// Canonical filesystem names can contain invalid UTF-8 even when the
		// typed path was valid. Always advance on a malformed byte sequence.
		if end == start { end = if start + 80 < path.len { start + 80 } else { path.len } }
		a.mirror_pages << unsafe { tos(path.str + start, end - start).clone() }
		a.mirror_page_labels << label.clone()
		start = end
	}
}

fn (mut a SoftwareApp) decode_mirror_output() !pkgprotocol.Review {
	mut envelope := pkgprotocol.MirrorReview{}
	if a.mirror_lock_pending != '' {
		mut locked := pkgprotocol.decode_deployment_mirror_review(editor_bytes_text(a.output))!
		if locked.deployment != a.mirror_lock_pending || locked.mirror.input_destination != a.mirror_pending {
			locked.close()
			return error('deployment export intent changed')
		}
		if a.mirror_source_sha256 != '' && locked.deployment_sha256 != a.mirror_source_sha256 {
			locked.close()
			return error(software_saved_deployment_changed)
		}
		// Transfer the decoded envelope and digest. The frozen source path is
		// separately owned; closing the emptied wrapper retires its copy.
		envelope = locked.mirror
		a.mirror_lock_sha256 = locked.deployment_sha256
		locked = pkgprotocol.DeploymentMirrorReview{ deployment: locked.deployment }
		locked.close()
		unsafe { a.review_names.flags |= .noslices }
		for name in envelope.review.names { a.review_names << name.clone() }
	} else { envelope = pkgprotocol.decode_mirror_review(editor_bytes_text(a.output))! }
	if envelope.input_destination != a.mirror_pending || envelope.review.names != a.review_names {
		envelope.close()
		return error('offline export intent changed')
	}
	review := envelope.review
	a.mirror_snapshot = pkgprotocol.MirrorReview{ ...envelope, review: pkgprotocol.Review{} }
	a.mirror_details = true
	a.mirror_pages = []string{cap: 128}
	a.mirror_page_labels = []string{cap: 128}
	unsafe { a.mirror_pages.flags |= .noslices; a.mirror_page_labels.flags |= .noslices }
	a.mirror_path_parts(envelope.destination)
	if a.mirror_lock_pending != '' {
		a.mirror_review_parts(a.mirror_lock_pending, 'Organization deployment lock · source path')
		a.mirror_review_parts(a.mirror_lock_sha256, 'Organization deployment lock · SHA-256')
	}
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
		'software.mirror.path' { a.focus = true; a.mirror_lock_focus = false; a.select_all = false }
		'software.mirror.lock' {
			if a.mirror_locked && a.mirror_source == '' { a.focus = true; a.mirror_lock_focus = true; a.select_all = false }
		}
		'software.mirror.scope' {
			if a.mirror_source != '' { return }
			if a.mirror_locked { a.mirror_locked = false; a.mirror_all = false }
			else if a.mirror_all { a.mirror_all = false; a.mirror_locked = true }
			else { a.mirror_all = true }
			a.focus = false
			a.select_all = false
		}
		'software.mirror.review' { a.begin_mirror_review() }
		'software.mirror.back' { a.clear_mirror_source(); a.mirror_mode = false; a.focus = false; a.select_all = false }
		else {}
	}
}

fn (mut a SoftwareApp) mirror_key_input(input string) {
	if !a.focus || a.review != '' || a.worker != unsafe { nil } { return }
	if a.mirror_locked && a.mirror_lock_focus {
		if a.mirror_source == '' { a.mirror_field_input(mut a.mirror_lock_path, input) }
	}
	else { a.mirror_field_input(mut a.mirror_path, input) }
}

fn (mut a SoftwareApp) mirror_field_input(mut field []u8, input string) {
	match input {
		'\x01' { a.select_all = true }
		'\x7f', '\x08' { console_backspace(mut field, a.select_all); a.select_all = false }
		'\x1b', '\r', '\n' { a.focus = false; a.select_all = false }
		else {
			length := if a.select_all { 0 } else { field.len }
			if input.len > software_deployment_path_limit - length || !software_deployment_text_valid(input) {
				a.set_status('The path exceeds 4096 bytes or contains invalid text. The field was kept intact.')
				return
			}
			if a.select_all { field.clear() }
			for byte in input { field << byte }
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
		if a.mirror_pages.len > 0 {
			children << software_label(a.mirror_page_labels[a.mirror_page], 14, 100, width - 28, 28, false)
			children << software_label(a.mirror_pages[a.mirror_page], 14, 138, width - 28, 72, false)
			children << software_button('software.mirror.previous', 'Previous path part', 14, 220, 160)
			children << software_button('software.mirror.next', 'Next path part', 186, 220, 160)
		}
		children << software_label(a.mirror_summary, 14, 262, width - 28, 60, false)
		children << software_label(if a.mirror_lock_pending != '' {
			'The exact deployment lock is bundled as _deployment.json with its complete package and runtime closure. Signed catalogs retain their expiry; consumers enroll each repository with its original publisher key.'
		} else { 'Only the selected dependency closure has payloads on this media. Signed catalogs retain their original expiry. Consumers must enroll each file:// repository with its original publisher key.' }, 14, 338, width - 28, 72, false)
		children << software_button('software.cancel', 'Cancel', 14, height - 138, 110)
		if a.review_ready && a.mirror_seen + 1 >= a.mirror_pages.len {
			children << software_button('software.mirror.packages', 'Review packages', 136, height - 138, 170)
		}
	} else {
		children << software_label('New directory on local disk or mounted offline media', 14, 54, width - 28, 28, false)
		children << console_field('software.mirror.path', editor_bytes_text(a.mirror_path), 14, 90, width - 28, a.focus && !a.mirror_lock_focus)
		if a.mirror_source != '' {
			children << software_label('Exact saved deployment · fixed source', 14, 138, width - 28, 28, false)
		} else {
			children << software_button('software.mirror.scope', if a.mirror_locked { 'Organization deployment lock' }
				else if a.mirror_all { 'All installed application roots' } else { 'Selected catalog application' }, 14, 138, 270)
		}
		if a.mirror_locked {
			children << software_label('Organization deployment lock (absolute file path)', 14, 178, width - 28, 28, false)
			if a.mirror_source != '' {
				children << software_label(a.mirror_source, 14, 212, width - 28, 28, false)
			} else {
				children << console_field('software.mirror.lock', editor_bytes_text(a.mirror_lock_path), 14, 212, width - 28, a.focus && a.mirror_lock_focus)
			}
		} else if !a.mirror_all && a.selected >= 0 && a.selected < a.rows.len {
			children << software_label(a.rows[a.selected].name, 14, 176, width - 28, 28, false)
		}
		children << software_label(if a.mirror_source != '' {
			'Exports the exact saved versions and runtimes. The source must still match the saved digest. Review the full paths, publishers, permissions, licenses and space before confirming.'
		} else if a.mirror_locked {
			'Exports exact approved application and runtime versions from a nonempty format-2 lock, including older versions. Review the source, publishers, permissions, licenses and space. Installed applications stay as they are.'
		} else { 'Exports current authenticated catalog versions and their complete dependency closure. Review publishers, permissions, licenses and disk requirements before confirming. The installed applications stay as they are.' }, 14, 258, width - 28, 72, false)
		if a.worker == unsafe { nil } {
			children << software_button('software.mirror.review', 'Review export', 14, 354, 150)
			children << software_button('software.mirror.back', 'Back to catalog', 176, 354, 160)
		}
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, true)
	return ui2.screen(app_surface, children)
}
