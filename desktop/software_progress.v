// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn software_progress_command(arguments []string) bool {
	return arguments.len > 0 && arguments[0] in ['update', 'install', 'remove', 'upgrade', 'apply', 'deploy', 'deployment-apply', 'rollback', 'mirror', 'mirror-apply', 'mirror-deployment-apply']
}

fn (mut a SoftwareApp) clear_progress() {
	a.progress_snapshot.close()
	a.progress_pending.clear()
	a.progress_skip = false
	a.progress_seen = false
}

fn software_progress_text(event pkgprotocol.Progress) string {
	current := event.current.str()
	total := event.total.str()
	defer { unsafe { current.free(); total.free() } }
	return match event.phase {
		'resolve' { 'Resolved the reviewed package set.'.clone() }
		'metadata' { 'Reading signed metadata: ${event.repository}/${event.path} · ${current} bytes' }
		'download' { 'Downloading ${event.package}/${event.path} · ${current} / ${total} bytes' }
		'copy' { 'Copying ${event.package}/${event.path} · ${current} / ${total} bytes' }
		'verify' { 'Verifying ${event.package}/${event.path}…' }
		'stage' { 'Staged ${current} / ${total} packages' }
		'activate' { 'Activating the complete package set…'.clone() }
		'complete' { 'Package operation completed.'.clone() }
		else { ''.clone() }
	}
}

fn (mut a SoftwareApp) operation_line(line string) {
	if line.starts_with(pkgprotocol.progress_prefix) {
		mut event := pkgprotocol.decode_progress(unsafe { tos(line.str + pkgprotocol.progress_prefix.len, line.len - pkgprotocol.progress_prefix.len) }) or { return }
		a.progress_snapshot.close()
		a.progress_snapshot = event
		a.progress_seen = true
		text := software_progress_text(event)
		a.set_status(text)
		unsafe { text.free() }
		return
	}
	// Presentation events do not displace the useful human diagnostic tail.
	if line.len == 0 { return }
	if a.output.len + line.len + 1 > 8192 { a.output.clear() }
	for byte in line { a.output << byte }
	a.output << `\n`
	tail := software_output_tail(a.output)
	a.set_status(tail)
	unsafe { tail.free() }
}

fn (mut a SoftwareApp) operation_output(bytes string) {
	unsafe { a.progress_pending.flags |= .noslices }
	for byte in bytes {
		if byte == `\n` {
			if !a.progress_skip && a.progress_pending.len > 0 { a.operation_line(editor_bytes_text(a.progress_pending)) }
			a.progress_pending.clear()
			a.progress_skip = false
		} else if !a.progress_skip {
			if a.progress_pending.len >= pkgprotocol.progress_limit {
				a.progress_pending.clear()
				a.progress_skip = true
			} else { a.progress_pending << byte }
		}
	}
}

fn (mut a SoftwareApp) finish_operation_output() {
	if !a.progress_skip && a.progress_pending.len > 0 { a.operation_line(editor_bytes_text(a.progress_pending)) }
	a.progress_pending.clear()
	a.progress_skip = false
}

fn (a &SoftwareApp) progress_bar(width int, height int) ui2.Element {
	event := a.progress_snapshot
	fraction := if event.total > 0 { f64(event.current) / f64(event.total) } else { 0.0 }
	mut fill := frame_elements(1)
	fill << ui2.view('', ui2.rect(0, 0, f64(width - 28) * fraction, 6),
		ui2.BoxStyle{ bg: settings_choice_bg, radius: 3 }, [])
	return ui2.Element{
		...ui2.view('software.progress', ui2.rect(14, f64(height - 100), f64(width - 28), 6),
			ui2.BoxStyle{ bg: body_panel, radius: 3 }, fill)
		accessibility_role: 'progressbar'
		accessibility_label: 'Package operation progress'
		accessibility_value: a.status
	}
}
