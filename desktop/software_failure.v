// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import ui2

const software_failure_limit = 8192

struct SoftwareFailurePage {
	text string
	source_page int
mut:
	label string
}

fn (mut a SoftwareApp) clear_failure() {
	unsafe {
		for page in a.failure_pages { page.text.free(); page.label.free() }
		(&array(&a.failure_pages)).free()
		for page in a.failure_compact_pages { page.text.free(); page.label.free() }
		(&array(&a.failure_compact_pages)).free()
		a.failure_heading.free()
	}
	a.failure_pages = []SoftwareFailurePage{}
	a.failure_compact_pages = []SoftwareFailurePage{}
	a.failure_compact_page = 0; a.failure_compact_mode = false
	a.failure_heading = ''
	a.failure_mode = false; a.failure_page = 0; a.failure_truncated = false
}

fn software_failure_operation(arguments []string) string {
	for argument in arguments {
		if argument in ['admin', '--progress', '--offline', '--json']! { continue }
		return match argument {
			'view' { 'Read software catalog' }
			'update' { 'Refresh repositories' }
			'review', 'apply' { 'Reviewed package change' }
			'install' { 'Install software' }
			'remove' { 'Remove software' }
			'upgrade' { 'Update software' }
			'rollback' { 'Roll back software' }
			'verify' { 'Verify installed software' }
			'health' { 'Inspect installed software health' }
			'cleanup-review', 'cleanup-apply' { 'Clean up obsolete package generations' }
			'repo-list', 'repo-review', 'repo-apply', 'repo-enroll', 'repo-revoke' { 'Repository administration' }
			'policy', 'policy-review', 'policy-apply' { 'Organization policy' }
			'deploy', 'deployment-review', 'deployment-apply' { 'Organization deployment' }
			'deployment-audit' { 'Check installed deployment' }
			'deployment-snapshot-save' { 'Save installed deployment' }
			'mirror', 'mirror-review', 'mirror-apply', 'mirror-deployment-review', 'mirror-deployment-apply' { 'Offline repository export' }
			'run', 'run-args' { 'Launch application' }
			else { 'Package service operation' }
		}
	}
	return 'Package service operation'
}

// Render arbitrary service bytes as valid UTF-8. Controls and invalid bytes are
// visible escapes; CRLF/newlines retain their layout and tabs become spaces.
fn software_failure_text(input string) string {
	mut bytes := []u8{cap: input.len * 4}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut at := 0
	for at < input.len {
		lead := input[at]
		if lead == `\r` {
			bytes << `\n`; at += if at + 1 < input.len && input[at + 1] == `\n` { 2 } else { 1 }
			continue
		}
		if lead == `\n` || lead == `\t` {
			bytes << if lead == `\t` { u8(` `) } else { lead }; at++; continue
		}
		length := if lead < 0x80 { 1 } else if lead >= 0xc2 && lead <= 0xdf { 2 }
			else if lead >= 0xe0 && lead <= 0xef { 3 } else if lead >= 0xf0 && lead <= 0xf4 { 4 } else { 0 }
		valid := length > 0 && at + length <= input.len
			&& utf8.validate_str(unsafe { tos(input.str + at, length) })
		if !valid || lead < 32 || lead == 127 || (lead == 0xc2 && input[at + 1] <= 0x9f) {
			bytes << `\\`; bytes << `x`; bytes << '0123456789abcdef'[lead >> 4]; bytes << '0123456789abcdef'[lead & 15]
			at++; continue
		}
		for index in 0 .. length { bytes << input[at + index] }
		at += length
	}
	return bytes.bytestr()
}

fn (mut a SoftwareApp) capture_failure(arguments []string, code int) {
	a.clear_failure()
	a.failure_pages = []SoftwareFailurePage{cap: 16}
	unsafe { a.failure_pages.flags |= .noslices }
	number := code.str()
	a.failure_heading = if code == 0 && a.worker_failed && a.worker_verify { 'Verify installed software · incomplete response'.clone() }
		else if a.worker_failed && a.worker_audit { 'Check installed deployment · incomplete response'.clone() }
		else if a.worker_failed && a.worker_snapshot { 'Save installed deployment · incomplete response'.clone() }
		else if code == 0 && a.worker_failed && a.worker_health { 'Inspect installed software health · incomplete response'.clone() }
		else if code == 0 && a.worker_failed { software_failure_operation(arguments) + ' · response too large' }
		else { software_failure_operation(arguments) + ' · exit ' + number }
	unsafe { number.free() }
	a.failure_truncated = a.output_truncated || a.output.len > software_failure_limit
	start := if a.output.len > software_failure_limit { a.output.len - software_failure_limit } else { 0 }
	input := if a.output.len > 0 { unsafe { tos(&a.output[start], a.output.len - start) } }
		else { 'The service returned no diagnostic text. Check administrator access, repository configuration and disk space.' }
	text := software_failure_text(input)
	defer { unsafe { text.free() } }
	software_failure_paginate(mut a.failure_pages, text, 48, 14, 0)
	software_failure_labels(mut a.failure_pages)
	a.failure_compact_pages = []SoftwareFailurePage{cap: 16}
	unsafe { a.failure_compact_pages.flags |= .noslices }
	// Keep a canonical-page anchor so compact -> full -> compact returns to
	// the exact short page. All prepared text is owned; redraw only borrows it.
	for index, page in a.failure_pages {
		software_failure_paginate(mut a.failure_compact_pages, page.text, 12, 3, index)
	}
	software_failure_labels(mut a.failure_compact_pages)
}

fn software_failure_paginate(mut pages []SoftwareFailurePage, text string, columns int, rows int, source_page int) {
	mut lines := []string{cap: rows}
	unsafe { lines.flags |= .noslices }
	defer { software_policy_free_lines(mut lines) }
	if text.len == 0 { lines << ''.clone() }
	mut position := 0
	for position < text.len {
		mut end := position
		for end < text.len && end - position < columns && text[end] != `\n` { end++ }
		for end > position && end < text.len && text[end] & 0xc0 == 0x80 { end-- }
		part := unsafe { tos(text.str + position, end - position).clone() }
		pointer := unsafe { &part }
		unsafe { lines.push_many(pointer, 1) }
		position = end + if end < text.len && text[end] == `\n` { 1 } else { 0 }
		if lines.len == rows {
			page := SoftwareFailurePage{text: lines.join('\n'), source_page: source_page}
			page_pointer := unsafe { &page }
			unsafe { pages.push_many(page_pointer, 1) }
			for line in lines { unsafe { line.free() } }; lines.clear()
		}
	}
	if lines.len > 0 {
		page := SoftwareFailurePage{text: lines.join('\n'), source_page: source_page}
		page_pointer := unsafe { &page }
		unsafe { pages.push_many(page_pointer, 1) }
	}
}

fn software_failure_labels(mut pages []SoftwareFailurePage) {
	total := pages.len.str()
	defer { unsafe { total.free() } }
	for index in 0 .. pages.len {
		page := (index + 1).str()
		pages[index].label = page + ' of ' + total
		unsafe { page.free() }
	}
}

fn (mut a SoftwareApp) handle_failure(action string) {
	match action {
		'software.failure.back' { a.failure_mode = false }
		'software.failure.clear' { a.clear_failure() }
		'software.failure.previous', 'software.failure.next' {
			step := if action == 'software.failure.next' { 1 } else { -1 }
			if a.failure_compact_mode {
				next := a.failure_compact_page + step
				if next >= 0 && next < a.failure_compact_pages.len {
					a.failure_compact_page = next
					a.failure_page = a.failure_compact_pages[next].source_page
				}
			} else {
				next := a.failure_page + step
				if next >= 0 && next < a.failure_pages.len { a.failure_page = next }
			}
		}
		else {}
	}
}

fn (mut a SoftwareApp) failure_key_input(input string) {
	match input {
		'\x1b' { a.handle_failure('software.failure.back') }
		'\x1b[D', '\x1b[5~' { a.handle_failure('software.failure.previous') }
		'\x1b[C', '\x1b[6~' { a.handle_failure('software.failure.next') }
		else {}
	}
}

fn (a &SoftwareApp) add_status_footer(mut children []ui2.Element, width int, height int, progress bool) {
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	y := height - if progress { 88 } else { 98 }
	children << software_label(a.status, 14, y, width - if available { 190 } else { 28 }, if progress { 80 } else { 90 }, false)
	if available { children << software_button('software.failure', 'Failure details', width - 162, y, 148) }
}

fn software_failure_lines(mut children []ui2.Element, text string, x int, y int, width int, line_height int) {
	// The native renderer draws each label as one line. Separate labels also
	// prevent backend word wrapping from hiding a prepared diagnostic fragment.
	mut start := 0
	mut row := 0
	for end in 0 .. text.len + 1 {
		if end == text.len || text[end] == `\n` {
			children << ui2.label('', unsafe { tos(text.str + start, end - start) },
				ui2.rect(f64(x), f64(y + row * line_height), f64(width), f64(line_height)),
				ui2.TextStyle{color: body_text, size: 12, font_family: 'mono'})
			start = end + 1; row++
		}
	}
}

fn (mut a SoftwareApp) build_failure(size ui2.Rect) ui2.Element {
	width := int(size.width); height := int(size.height)
	mut children := frame_elements(24)
	if width < 640 || height < 610 {
		a.failure_compact_mode = true
		if a.failure_compact_page < a.failure_compact_pages.len
			&& a.failure_compact_pages[a.failure_compact_page].source_page != a.failure_page {
			for index, page in a.failure_compact_pages {
				if page.source_page == a.failure_page { a.failure_compact_page = index; break }
			}
		}
		content_width := if width > 28 { width - 28 } else { 1 }
		back_width := if width >= 240 { 110 } else if content_width >= 56 { 56 } else { content_width }
		children << software_button('software.failure.back', 'Back', if width > back_width + 28 { width - back_width - 14 } else { 14 }, 8, back_width)
		if width < 180 || height < 200 {
			children << software_label('Enlarge to read diagnostics.', 14, 46, content_width, 28, false)
			return ui2.screen(app_surface, children)
		}
		children << software_label(a.failure_heading, 14, 46, content_width, 28, false)
		children << software_label(if a.failure_truncated { 'Earlier output omitted.' } else { 'Retained service output.' }, 14, 80, content_width, 20, false)
		if a.failure_compact_page >= 0 && a.failure_compact_page < a.failure_compact_pages.len {
			page := a.failure_compact_pages[a.failure_compact_page]
			children << software_label(page.label, 14, 8, if width > back_width + 42 { width - back_width - 42 } else { 1 }, 28, false)
			software_failure_lines(mut children, page.text, 14, 110, content_width, 16)
		}
		button_width := if width >= 240 { 90 } else { (width - 42) / 2 }
		children << software_button('software.failure.previous', 'Previous', 14, height - 36, button_width)
		children << software_button('software.failure.next', 'Next', width - 14 - button_width, height - 36, button_width)
		return ui2.screen(app_surface, children)
	}
	a.failure_compact_mode = false
	children << software_label('Last service failure', 14, 8, width - 202, 28, false)
	children << software_button('software.failure.back', 'Back', width - 174, 8, 160)
	children << software_label(a.failure_heading, 14, 46, width - 28, 28, false)
	children << software_label(if a.failure_truncated { 'Some output was omitted. These pages show the retained diagnostic tail.' }
		else { 'Retained diagnostic output. Long lines continue on the next line or page.' }, 14, 82, width - 28, 44, false)
	if a.failure_page >= 0 && a.failure_page < a.failure_pages.len {
		page := a.failure_pages[a.failure_page]
		software_failure_lines(mut children, page.text, 14, 142, width - 28, 20)
		children << software_label(page.label, 238, height - 138, width - 430, 28, false)
	}
	children << software_button('software.failure.previous', 'Previous', 14, height - 138, 100)
	children << software_button('software.failure.next', 'Next', 126, height - 138, 100)
	children << software_button('software.failure.clear', 'Clear failure', width - 174, height - 138, 160)
	children << software_label('Back returns to the same screen. The latest failure stays available across reloads until replaced by another failure, cleared or this window closes.', 14, height - 98, width - 28, 90, false)
	return ui2.screen(app_surface, children)
}
