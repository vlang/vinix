// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2

const software_row_actions = ['software.row.0', 'software.row.1', 'software.row.2', 'software.row.3',
	'software.row.4', 'software.row.5', 'software.row.6', 'software.row.7', 'software.row.8',
	'software.row.9', 'software.row.10', 'software.row.11', 'software.row.12', 'software.row.13',
	'software.row.14', 'software.row.15']
const software_output_limit = 8 * 1024 * 1024

struct SoftwareRow {
	id                string
	name              string
	description       string
	version           string
	installed_version string
	architecture      string
	kind              string
	repository        string
	public_key        string
	license           string
	proprietary       bool
	firmware          bool
	permissions       []string
	requested         bool
	updatable         bool
	diagnostic        string
}

struct SoftwareView {
	format        int
	generation    u64
	architecture  string
	offline       bool
	catalog_error string
	rows          []SoftwareRow
}

struct SoftwareApp {
mut:
	rows          []SoftwareRow
	matching      []int
	query         []u8
	output        []u8
	status        string
	catalog_error string
	selected      int = -1
	scroll        int
	page_rows     int = 10
	filter        int // 0 catalog, 1 installed, 2 updates
	focus         bool
	select_all    bool
	review        string
	worker        &os.Process = unsafe { nil }
	worker_view   bool
	worker_failed bool
	offline       bool
}

fn open_software(mut desktop Desktop) !NativeApp {
	_ = desktop.tz_offset_seconds
	mut app := &SoftwareApp{
		rows:     []SoftwareRow{cap: 128}
		matching: []int{cap: 128}
		query:    []u8{cap: console_filter_limit}
		output:   []u8{cap: 8192}
	}
	unsafe {
		app.rows.flags |= .noslices
		app.matching.flags |= .noslices
		app.query.flags |= .noslices
		app.output.flags |= .noslices
	}
	app.start(['view'], true)
	return app
}

fn (mut a SoftwareApp) set_status(text string) {
	next := text.clone()
	unsafe { a.status.free() }
	a.status = next
}

fn (mut a SoftwareApp) start(arguments []string, view bool) {
	if a.worker != unsafe { nil } { return }
	if C.access(c'/usr/bin/vinix-package', C.X_OK) != 0 {
		a.set_status('The package service is missing. Install the V package tools in this image.')
		return
	}
	a.output.clear()
	a.worker_failed = false
	a.worker_view = view
	a.worker = os.new_process('/usr/bin/vinix-package')
	mut owned := []string{cap: arguments.len}
	for argument in arguments { owned << argument.clone() }
	a.worker.set_args(owned)
	a.worker.set_redirect_stdio_merged()
	a.worker.run()
	a.set_status(if view {
		'Reading the software catalog…'
	} else {
		'Package operation started…'
	})
}

fn software_free_row(row SoftwareRow) {
	unsafe {
		row.id.free()
		row.name.free()
		row.description.free()
		row.version.free()
		row.installed_version.free()
		row.architecture.free()
		row.kind.free()
		row.repository.free()
		row.public_key.free()
		row.license.free()
		row.diagnostic.free()
		for permission in row.permissions { permission.free() }
		(&array(&row.permissions)).free()
	}
}

fn (mut a SoftwareApp) filter_rows() {
	a.matching.clear()
	query := editor_bytes_text(a.query).to_lower()
	defer { unsafe { query.free() } }
	for i, row in a.rows {
		if a.filter == 1 && row.installed_version == '' { continue }
		if a.filter == 2 && !row.updatable { continue }
		combined := '${row.id} ${row.name} ${row.description}'
		text := combined.to_lower()
		if query.len == 0 || text.contains(query) { a.matching << i }
		unsafe {
			text.free()
			combined.free()
		}
	}
	a.scroll = 0
}

fn (mut a SoftwareApp) load_view() {
	text := editor_bytes_text(a.output)
	view := json2.decode[SoftwareView](text) or {
		a.set_status('Invalid response from the package service. Reload the catalog or check its configuration.')
		return
	}
	if view.format != 1 || view.rows.len > 4096 {
		for row in view.rows { software_free_row(row) }
		unsafe {
			view.rows.free()
			view.architecture.free()
			view.catalog_error.free()
		}
		a.set_status('Unsupported package service response')
		return
	}
	for row in a.rows { software_free_row(row) }
	a.rows.clear()
	unsafe {
		// Transfer the decoded rows. A typed push may deep-clone their strings;
		// the app owns the original fields and releases them on reload/close.
		a.rows.push_many(view.rows.data, view.rows.len)
		view.rows.free()
		view.architecture.free()
		a.catalog_error.free()
	}
	a.catalog_error = view.catalog_error
	a.offline = view.offline
	a.selected = -1
	a.filter_rows()
	a.set_status(if a.catalog_error.len > 0 {
		a.catalog_error
	} else if a.offline {
		'Offline mode: verified caches and local repositories are available.'
	} else {
		'Select an application to review its publisher, license and permissions.'
	})
}

fn software_output_tail(bytes []u8) string {
	clean := console_sanitize(editor_bytes_text(bytes))
	mut end := clean.len
	for end > 0 && clean[end - 1] == `\n` { end-- }
	mut start := end
	mut lines := 0
	for start > 0 {
		if clean[start - 1] == `\n` {
			lines++
			if lines == 3 { break }
		}
		start--
	}
	result := unsafe { tos(clean.str + start, end - start).clone() }
	unsafe { clean.free() }
	return result
}

fn (mut a SoftwareApp) retire_worker() {
	if a.worker == unsafe { nil } { return }
	a.worker.close()
	unsafe {
		// Process owns the cloned arguments and inherited environment strings.
		a.worker.free()
		free(a.worker)
	}
	a.worker = unsafe { nil }
}

fn (mut a SoftwareApp) poll() bool {
	if a.worker == unsafe { nil } { return false }
	mut changed := false
	// Drain a bounded number of chunks per UI poll, including after exit.
	for _ in 0 .. 16 {
		chunk := a.worker.stdout_read()
		if chunk.len == 0 { break }
		changed = true
		if a.worker_view {
			if a.output.len + chunk.len <= software_output_limit {
				for byte in chunk { a.output << byte }
			} else {
				a.worker_failed = true
				a.set_status('Package catalog exceeds the supported size.')
			}
		} else {
			// Keep recent progress and diagnostics, without growing indefinitely.
			if a.output.len + chunk.len > 8192 { a.output.clear() }
			for byte in chunk { a.output << byte }
			tail := software_output_tail(a.output)
			a.set_status(tail)
			unsafe { tail.free() }
		}
		unsafe { chunk.free() }
	}
	if a.worker.is_alive() { return changed }
	// A full drain batch can leave more queued data. Finish it next poll.
	if a.worker.is_pending(.stdout) {
		if chunk := a.worker.pipe_read(.stdout) {
			if chunk.len > 0 {
				if a.worker_view && a.output.len + chunk.len <= software_output_limit {
					for byte in chunk { a.output << byte }
				} else if !a.worker_view {
					if a.output.len + chunk.len > 8192 { a.output.clear() }
					for byte in chunk { a.output << byte }
				} else {
					a.worker_failed = true
					a.set_status('Package catalog exceeds the supported size.')
				}
				unsafe { chunk.free() }
				return true
			}
		}
	}
	code := a.worker.code
	view := a.worker_view
	a.retire_worker()
	if code != 0 {
		diagnostic := software_output_tail(a.output)
		a.set_status(if diagnostic.len > 0 {
			diagnostic
		} else {
			'The package service failed. Check administrator access, repository configuration and disk space.'
		})
		unsafe { diagnostic.free() }
	} else if view {
		if !a.worker_failed { a.load_view() }
	} else {
		a.start(['view'], true)
	}
	return true
}

fn (a &SoftwareApp) next_poll_ms() u64 { return 100 }

fn (mut a SoftwareApp) handle(event_id string) ! {
	if event_id == 'software.search' {
		a.focus = true
		return
	}
	if a.worker != unsafe { nil } { return }
	for row, action in software_row_actions {
		if event_id == action && a.scroll + row < a.matching.len {
			a.selected = a.matching[a.scroll + row]
			a.review = ''
			return
		}
	}
	match event_id {
		'software.catalog' {
			a.filter = 0
			a.filter_rows()
		}
		'software.installed' {
			a.filter = 1
			a.filter_rows()
		}
		'software.updates' {
			a.filter = 2
			a.filter_rows()
		}
		'software.refresh' { a.start(['update'], false) }
		'software.reload' { a.start(['view'], true) }
		'software.up' { a.scroll = if a.scroll > a.page_rows { a.scroll - a.page_rows } else { 0 } }
		'software.down' {
			if a.scroll + a.page_rows < a.matching.len { a.scroll += a.page_rows }
		}
		'software.rollback' {
			a.review = 'rollback'
			a.set_status('Restore the previous package set. Your application data will be retained. Choose Confirm to continue.')
		}
		'software.upgrade' {
			a.review = 'upgrade'
			a.set_status('Update installed applications and their runtime dependencies from trusted repositories. Choose Confirm to continue.')
		}
		'software.install', 'software.remove' {
			if a.selected < 0 || a.selected >= a.rows.len { return }
			row := a.rows[a.selected]
			if event_id == 'software.install' && (row.diagnostic.len > 0 || a.catalog_error.len > 0) {
				a.set_status(if row.diagnostic.len > 0 { row.diagnostic } else { a.catalog_error })
				return
			}
			if event_id == 'software.remove' && !row.requested {
				a.set_status('This package is a dependency. Remove the applications that require it first.')
				return
			}
			a.review = if event_id == 'software.install' { 'install' } else { 'remove' }
			a.set_status(if a.review == 'install' {
				'Review the publisher, permissions and license above. Confirm installs the complete dependency set.'
			} else {
				'Confirm removes this application and unused dependencies. Personal data and the rollback copy are retained.'
			})
		}
		'software.confirm' {
			if a.review in ['install', 'remove'] && a.selected >= 0 {
				a.start([a.review, a.rows[a.selected].id], false)
			} else if a.review in ['upgrade', 'rollback'] {
				a.start([a.review], false)
			}
			a.review = ''
		}
		'software.cancel' {
			a.review = ''
			a.set_status('Operation cancelled before making changes.')
		}
		else {}
	}
}

fn (mut a SoftwareApp) key_input(input string) {
	if !a.focus { return }
	match input {
		'\x01' { a.select_all = true }
		'\x7f', '\x08' {
			console_backspace(mut a.query, a.select_all)
			a.select_all = false
			a.filter_rows()
		}
		'\x1b', '\r', '\n' { a.focus = false }
		else {
			console_paste_field(mut a.query, input, console_filter_limit, a.select_all)
			a.select_all = false
			a.filter_rows()
		}
	}
}

fn (mut a SoftwareApp) paste_input(input string) { if a.focus { a.key_input(input) } }

fn software_label(text string, x int, y int, width int, height int, owned bool) ui2.Element {
	return ui2.Element{
		...ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), f64(height)),
			ui2.TextStyle{ color: body_text, size: 12, lines: if height > 30 { 3 } else { 1 } })
		key: if owned { workflow_owned_text_key } else { '' }
	}
}

fn software_button(id string, text string, x int, y int, width int) ui2.Element {
	return ui2.button(id, text, ui2.rect(f64(x), f64(y), f64(width), 28),
		ui2.BoxStyle{ bg: body_panel, radius: 4 }, ui2.TextStyle{ color: body_text, size: 12, align: .center })
}

fn (mut a SoftwareApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	if width < 640 || height < 610 {
		mut compact := frame_elements(2)
		compact << software_label('Software', 14, 8, width - 28, 28, false)
		compact << software_label('Enlarge this window to view package details and controls.',
			14, 40, width - 28, 60, false)
		return ui2.screen(app_surface, compact)
	}
	a.page_rows = if height > 400 { (height - 236) / 30 } else { 5 }
	if a.page_rows > software_row_actions.len { a.page_rows = software_row_actions.len }
	mut children := frame_elements(48)
	children << software_label('Software', 14, 8, 150, 28, false)
	children << console_field('software.search', editor_bytes_text(a.query), 170, 8, width - 370, a.focus)
	children << software_button('software.refresh', 'Refresh repositories', width - 188, 8, 174)
	children << software_button('software.catalog', 'Catalog', 14, 46, 90)
	children << software_button('software.installed', 'Installed', 112, 46, 90)
	children << software_button('software.updates', 'Updates', 210, 46, 90)
	children << software_button('software.reload', 'Reload', 308, 46, 90)
	for slot in 0 .. a.page_rows {
		index := a.scroll + slot
		if index >= a.matching.len { break }
		row_index := a.matching[index]
		row := a.rows[row_index]
		children << ui2.button(software_row_actions[slot], row.name,
			ui2.rect(14, f64(90 + slot * 30), 236, 28),
			ui2.BoxStyle{ bg: if row_index == a.selected { settings_choice_bg } else { body_panel }, radius: 3 },
			ui2.TextStyle{ color: body_text, size: 12, align: .left })
	}
	children << software_button('software.up', 'Previous', 14, height - 138, 110)
	children << software_button('software.down', 'Next', 136, height - 138, 110)
	if a.selected >= 0 && a.selected < a.rows.len {
		row := a.rows[a.selected]
		children << software_label(row.name, 274, 90, width - 288, 28, false)
		children << software_label(row.description, 274, 124, width - 288, 72, false)
		children << software_label('Version: ${row.version}    Installed: ${row.installed_version}', 274, 204, width - 288, 28, true)
		children << software_label('Architecture: ${row.architecture}    Runtime: ${row.kind}', 274, 236, width - 288, 28, true)
		children << software_label('Repository: ${row.repository}', 274, 268, width - 288, 28, true)
		children << software_label('Publisher key: ${row.public_key}', 274, 300, width - 288, 48, true)
		permissions := row.permissions.join(', ')
		children << software_label('Permissions: ${permissions}', 274, 352, width - 288, 48, true)
		unsafe { permissions.free() }
		children << software_label('License: ${row.license}' + if row.proprietary {
			' (proprietary)'
		} else {
			''
		} + if row.firmware { ' — firmware' } else { '' }, 274, 404, width - 288, 28, true)
		children << software_button('software.install', if row.installed_version == '' {
			'Install'
		} else {
			'Repair / install'
		}, 274, height - 176, 160)
		if row.installed_version != '' {
			children << software_button('software.remove', 'Uninstall', 446, height - 176, 130)
		}
	}
	if a.review.len > 0 {
		children << software_button('software.confirm', 'Confirm', 274, height - 138, 130)
		children << software_button('software.cancel', 'Cancel', 416, height - 138, 110)
	} else {
		children << software_button('software.upgrade', 'Update all', 274, height - 138, 130)
		children << software_button('software.rollback', 'Rollback', 416, height - 138, 130)
	}
	children << software_label(a.status, 14, height - 98, width - 28, 90, false)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) prepare_close() bool {
	if a.worker != unsafe { nil } && !a.worker_view {
		a.set_status('Wait for the package transaction to finish before closing Software.')
		return false
	}
	return true
}

fn (mut a SoftwareApp) close_app() {
	if a.worker != unsafe { nil } {
		if a.worker.is_alive() {
			a.worker.signal_kill()
			a.worker.wait()
		}
		a.retire_worker()
	}
	for row in a.rows { software_free_row(row) }
	unsafe {
		a.rows.free()
		a.matching.free()
		a.query.free()
		a.output.free()
		a.status.free()
		a.catalog_error.free()
	}
	a = SoftwareApp{}
}
