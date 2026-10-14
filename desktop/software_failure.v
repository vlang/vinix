// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import ui2

const software_failure_limit = 8192

struct SoftwareFailurePage {
	text string
mut:
	label string
}

fn (mut a SoftwareApp) clear_failure() {
	unsafe {
		for page in a.failure_pages { page.text.free(); page.label.free() }
		(&array(&a.failure_pages)).free()
		a.failure_heading.free()
	}
	a.failure_pages = []SoftwareFailurePage{}
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
			'repo-list', 'repo-review', 'repo-apply', 'repo-enroll', 'repo-revoke' { 'Repository administration' }
			'policy', 'policy-review', 'policy-apply' { 'Organization policy' }
			'deploy', 'deployment-review', 'deployment-apply' { 'Organization deployment' }
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

fn (mut a SoftwareApp) failure_add_page(lines []string) {
	page := SoftwareFailurePage{text: lines.join('\n')}
	pointer := unsafe { &page }
	unsafe { a.failure_pages.push_many(pointer, 1) }
}

fn (mut a SoftwareApp) capture_failure(arguments []string, code int) {
	a.clear_failure()
	a.failure_pages = []SoftwareFailurePage{cap: 16}
	unsafe { a.failure_pages.flags |= .noslices }
	number := code.str()
	a.failure_heading = if code == 0 && a.worker_failed && a.worker_verify { 'Verify installed software · incomplete response'.clone() }
		else if code == 0 && a.worker_failed { software_failure_operation(arguments) + ' · response too large' }
		else { software_failure_operation(arguments) + ' · exit ' + number }
	unsafe { number.free() }
	a.failure_truncated = a.output_truncated || a.output.len > software_failure_limit
	start := if a.output.len > software_failure_limit { a.output.len - software_failure_limit } else { 0 }
	input := if a.output.len > 0 { unsafe { tos(&a.output[start], a.output.len - start) } }
		else { 'The service returned no diagnostic text. Check administrator access, repository configuration and disk space.' }
	text := software_failure_text(input)
	defer { unsafe { text.free() } }
	mut lines := []string{cap: 14}
	unsafe { lines.flags |= .noslices }
	defer { software_policy_free_lines(mut lines) }
	mut position := 0
	for position < text.len {
		mut end := position
		for end < text.len && end - position < 48 && text[end] != `\n` { end++ }
		for end > position && end < text.len && text[end] & 0xc0 == 0x80 { end-- }
		part := unsafe { tos(text.str + position, end - position).clone() }
		pointer := unsafe { &part }
		unsafe { lines.push_many(pointer, 1) }
		position = end + if end < text.len && text[end] == `\n` { 1 } else { 0 }
		if lines.len == 14 {
			a.failure_add_page(lines)
			for line in lines { unsafe { line.free() } }; lines.clear()
		}
	}
	if lines.len > 0 { a.failure_add_page(lines) }
	total := a.failure_pages.len.str()
	defer { unsafe { total.free() } }
	for index in 0 .. a.failure_pages.len {
		page := (index + 1).str()
		a.failure_pages[index].label = page + ' of ' + total
		unsafe { page.free() }
	}
}

fn (mut a SoftwareApp) handle_failure(action string) {
	match action {
		'software.failure.back' { a.failure_mode = false }
		'software.failure.clear' { a.clear_failure() }
		'software.failure.previous' { if a.failure_page > 0 { a.failure_page-- } }
		'software.failure.next' { if a.failure_page + 1 < a.failure_pages.len { a.failure_page++ } }
		else {}
	}
}

fn (a &SoftwareApp) add_status_footer(mut children []ui2.Element, width int, height int, progress bool) {
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	y := height - if progress { 88 } else { 98 }
	children << software_label(a.status, 14, y, width - if available { 190 } else { 28 }, if progress { 80 } else { 90 }, false)
	if available { children << software_button('software.failure', 'Failure details', width - 162, y, 148) }
}

fn (a &SoftwareApp) build_failure(size ui2.Rect) ui2.Element {
	width := int(size.width); height := int(size.height)
	mut children := frame_elements(10)
	if width < 640 || height < 610 {
		children << software_label('Enlarge this window to read failure details.', 14, 8, if width > 28 { width - 28 } else { 1 }, 40, false)
		children << software_button('software.failure.back', 'Back', 14, 58, 110)
		return ui2.screen(app_surface, children)
	}
	children << software_label('Last service failure', 14, 8, width - 202, 28, false)
	children << software_button('software.failure.back', 'Back', width - 174, 8, 160)
	children << software_label(a.failure_heading, 14, 46, width - 28, 28, false)
	children << software_label(if a.failure_truncated { 'Some output was omitted. These pages show the retained diagnostic tail.' }
		else { 'Retained diagnostic output. Long lines continue on the next line or page.' }, 14, 82, width - 28, 44, false)
	if a.failure_page >= 0 && a.failure_page < a.failure_pages.len {
		page := a.failure_pages[a.failure_page]
		children << ui2.label('', page.text, ui2.rect(14, 142, f64(width - 28), f64(height - 306)), ui2.TextStyle{color: body_text, size: 12, lines: 14})
		children << software_label(page.label, 238, height - 138, width - 430, 28, false)
	}
	children << software_button('software.failure.previous', 'Previous', 14, height - 138, 100)
	children << software_button('software.failure.next', 'Next', 126, height - 138, 100)
	children << software_button('software.failure.clear', 'Clear failure', width - 174, height - 138, 160)
	children << software_label('Back returns to the same screen. The latest failure stays available across reloads until replaced by another failure, cleared or this window closes.', 14, height - 98, width - 28, 90, false)
	return ui2.screen(app_surface, children)
}
