// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol
import tools.packages.appsdk
import tools.packages.pkgadmin

const software_row_actions = ['software.row.0', 'software.row.1', 'software.row.2', 'software.row.3',
	'software.row.4', 'software.row.5', 'software.row.6', 'software.row.7', 'software.row.8',
	'software.row.9', 'software.row.10', 'software.row.11', 'software.row.12', 'software.row.13',
	'software.row.14', 'software.row.15']
const software_output_limit = 8 * 1024 * 1024

type SoftwareRow = pkgprotocol.SoftwareRow
type SoftwareView = pkgprotocol.SoftwareView

struct SoftwareApp {
mut:
	rows            []SoftwareRow
	matching        []int
	query           []u8
	output          []u8
	output_truncated bool
	failure_pages []SoftwareFailurePage
	failure_heading string
	failure_mode bool
	failure_page int
	failure_truncated bool
	status          string
	catalog_error   string
	update_error    string
	selected        int = -1
	scroll          int
	page_rows       int = 10
	filter          int // 0 catalog, 1 installed, 2 updates
	focus           bool
	select_all      bool
	review          string
	review_names    []string
	review_snapshot pkgprotocol.Review
	review_ready    bool
	review_selected int = -1
	review_scroll   int
	review_summary  string
	details_mode    bool
	details_review  bool
	details_pages   []SoftwareDetailsPage
	details_page    int
	details_section int
	details_starts  [6]int
	worker          &os.Process = unsafe { nil }
	worker_view     bool
	worker_review   bool
	worker_run      bool
	worker_verify   bool
	worker_health   bool
	worker_failed   bool
	health_mode bool
	health_ready bool
	health_snapshot pkgprotocol.HealthReport
	health_matching []int
	health_summary string
	health_selected int = -1
	health_scroll int
	data_mode       bool
	data_status     pkgprotocol.PersonalDataStatus
	data_ready      bool
	data_selected   int = -1
	data_scroll     int
	data_pending    string // frozen ID shown in the deletion confirmation
	data_result     string
	data_worker     SoftwareDataWorker
	policy_mode     bool
	policy_document pkgprotocol.PolicyDocument
	policy_snapshot pkgprotocol.PolicyReview
	policy_ready    bool
	policy_review_ready bool
	policy_path     []u8
	policy_pending  string
	policy_worker   SoftwarePolicyWorker
	policy_pages    []SoftwarePolicyPage
	policy_page     int
	policy_section  int
	policy_starts   [7]int
	policy_result   string
	progress_snapshot pkgprotocol.Progress
	progress_pending []u8
	progress_seen bool
	progress_skip bool
	launch_request  string
	launch_label    string = 'Launch'
	service_path    string = '/usr/bin/vinix-package'
	offline         bool
	repository_mode bool
	repository_status pkgprotocol.RepositoryConfiguration
	repository_selected int = -1
	repository_scroll int
	repository_focus int
	repository_id []u8
	repository_url []u8
	repository_key []u8
	repository_operation string
	repository_pending pkgprotocol.Repository
	repository_review pkgprotocol.RepositoryReview
	repository_review_ready bool
	repository_summary string
	repository_url_pages []string
	repository_page_labels []string
	repository_url_page int
	repository_url_seen int
	repository_result string
	repository_worker SoftwareRepositoryWorker
	deployment_mode bool
	deployment_path []u8
	deployment_pending string // frozen file path for deployment-review/apply
	mirror_mode bool
	mirror_path []u8
	mirror_all bool
	mirror_locked bool
	mirror_lock_path []u8
	mirror_lock_focus bool
	mirror_lock_pending string
	mirror_lock_sha256 string
	mirror_pending string
	mirror_snapshot pkgprotocol.MirrorReview // review rows are owned by review_snapshot
	mirror_details bool
	mirror_pages []string
	mirror_page_labels []string
	mirror_page int
	mirror_seen int
	mirror_summary string
	worker_mirror bool
	terminal_app &TerminalApp = unsafe { nil }
	launch_mode bool
	launch_id string
	launch_name string
	launch_arguments []u8
	launch_file []u8
	launch_documents []string
	launch_focus int
	launch_file_selected int = -1
	launch_file_scroll int
	launch_data_cwd bool = true
	launch_files_allowed bool
	window_mode bool
	window_protocol int = 1
	window_frame appsdk.WindowFrame
	window_pending []u8
	window_skip bool
	window_closing bool
	window_writable bool
	window_failure string
	window_input_id string
	window_input []u8
	window_input_dirty bool
	window_input_select_all bool
	administration_required bool
	admin_prompt bool
	admin_focus bool
	admin_select_all bool
	admin_password [pkgadmin.password_limit]u8
	admin_password_len int
	admin_mask []u8
}

fn open_software(mut desktop Desktop) !NativeApp {
	_ = desktop.tz_offset_seconds
	mut app := &SoftwareApp{
		administration_required: C.geteuid() != 0
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

fn (mut a SoftwareApp) set_update_status() {
	text := 'Updates unavailable: ' + a.update_error
	a.set_status(text)
	unsafe { text.free() }
}

fn (mut a SoftwareApp) start(arguments []string, view bool) {
	if a.worker != unsafe { nil } { return }
	if C.access(&char(a.service_path.str), C.X_OK) != 0 {
		a.set_status('The package service is missing. Install the V package tools in this image.')
		return
	}
	a.clear_details()
	a.output.clear()
	a.output_truncated = false
	a.failure_mode = false
	a.clear_progress()
	a.worker_failed = false
	a.worker_view = view
	a.worker_review = false
	a.worker_run = false
	a.worker_verify = arguments.len == 1 && arguments[0] == 'verify'
	a.worker_health = arguments == ['--json', 'health']
	a.worker_mirror = false
	a.repository_worker = .none
	a.data_worker = .none
	a.policy_worker = .none
	a.worker = os.new_process(a.service_path.clone())
	mut owned := []string{cap: arguments.len + 1}
	authorized := a.administration_required && pkgadmin.administrative(arguments)
	if authorized { owned << 'admin'.clone() }
	if software_progress_command(arguments) { owned << '--progress'.clone() }
	for argument in arguments { owned << argument.clone() }
	a.worker.set_args(owned)
	a.worker.set_redirect_stdio_merged()
	a.worker.run()
	if authorized { a.begin_admin_prompt() }
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
		row.installed_name.free()
		row.installed_kind.free()
		for permission in row.installed_permissions { permission.free() }
		(&array(&row.installed_permissions)).free()
		row.architecture.free()
		row.kind.free()
		row.runtime.free()
		row.repository.free()
		row.public_key.free()
		row.license.free()
		row.diagnostic.free()
		row.update_action.free()
		for permission in row.permissions { permission.free() }
		(&array(&row.permissions)).free()
	}
}

// The pinned string.to_lower keeps its rune buffer and the rune-to-string
// builder descriptor under manualfree. Stream Unicode scalar values into one
// owned byte buffer instead; lowercasing can change the UTF-8 byte length.
fn software_search_lower(value string) string {
	if value.len == 0 { return '' }
	mut bytes := []u8{cap: value.len}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut iterator := value.runes_iterator()
	for {
		character := iterator.next() or { break }
		lower := u32(character.to_lower())
		if lower < 0x80 { bytes << u8(lower) }
		else if lower < 0x800 { bytes << u8(0xc0 | (lower >> 6)); bytes << u8(0x80 | (lower & 63)) }
		else if lower < 0x10000 {
			bytes << u8(0xe0 | (lower >> 12)); bytes << u8(0x80 | ((lower >> 6) & 63)); bytes << u8(0x80 | (lower & 63))
		} else {
			bytes << u8(0xf0 | (lower >> 18)); bytes << u8(0x80 | ((lower >> 12) & 63)); bytes << u8(0x80 | ((lower >> 6) & 63)); bytes << u8(0x80 | (lower & 63))
		}
	}
	return bytes.bytestr()
}

fn (mut a SoftwareApp) filter_rows() {
	a.matching.clear()
	query := software_search_lower(editor_bytes_text(a.query))
	defer { unsafe { query.free() } }
	for i, row in a.rows {
		if a.filter == 1 && row.installed_version == '' { continue }
		if a.filter == 2 && !row.updatable { continue }
		combined := '${row.id} ${row.name} ${row.description}'
		text := software_search_lower(combined)
		if query.len == 0 || text.contains(query) { a.matching << i }
		unsafe {
			text.free()
			combined.free()
		}
	}
	a.scroll = 0
}

fn (mut a SoftwareApp) load_view() {
	a.clear_details()
	a.clear_launch_options()
	a.clear_review()
	a.deployment_mode = false
	a.mirror_mode = false
	text := editor_bytes_text(a.output)
	view := pkgprotocol.decode_software_view(text) or {
		message := 'Invalid response from the package service: ' + err.msg() + '. Reload the catalog or check its configuration.'
		a.set_status(message)
		unsafe { message.free(); err.free() }
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
		a.update_error.free()
	}
	a.catalog_error = view.catalog_error
	a.update_error = view.update_error
	unsafe { a.launch_label.free() }
	a.launch_label = if view.launch_user == '' { 'Launch' } else { 'Launch as ' + view.launch_user }
	unsafe { view.launch_user.free() }
	a.offline = view.offline
	a.selected = -1
	a.filter_rows()
	if a.catalog_error.len > 0 {
		a.set_status(a.catalog_error)
	} else if a.update_error.len > 0 {
		a.set_update_status()
	} else {
		a.set_status(if a.offline {
			'Offline mode: verified caches and local repositories are available.'
		} else {
			'Select an application to review its publisher, license and permissions.'
		})
	}
}

fn (mut a SoftwareApp) clear_review() {
	a.clear_details()
	a.clear_mirror_review()
	a.review_snapshot.close()
	unsafe {
		a.review.free()
		for name in a.review_names { name.free() }
		(&array(&a.review_names)).free()
		a.review_summary.free()
		a.deployment_pending.free()
	}
	a.review = ''
	a.review_names = []string{}
	a.review_summary = ''
	a.deployment_pending = ''
	a.review_ready = false
	a.review_selected = -1
	a.review_scroll = 0
}

fn (mut a SoftwareApp) begin_review(operation string, names []string) {
	a.clear_review()
	a.review = operation.clone()
	for name in names { a.review_names << name.clone() }
	a.focus = false
	a.start(['review', operation, ...names], false)
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.set_status('Resolving the complete package set for review…')
	}
}

fn (mut a SoftwareApp) load_review() {
	mut review := if a.mirror_pending != '' {
		a.decode_mirror_output() or {
			unsafe { err.free() }
			a.clear_review()
			a.set_status('Unsupported or different offline export review. Review the export again.')
			return
		}
	} else { pkgprotocol.decode_review(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.clear_review()
		a.set_status('Unsupported or invalid package review response. Review the operation again.')
		return
	} }
	review.validate() or {
		unsafe { err.free() }
		review.close()
		a.clear_review()
		a.set_status('Unsupported or incomplete package review. Review the operation again.')
		return
	}
	if review.operation != a.review || (a.deployment_pending == '' && review.names != a.review_names) {
		review.close()
		a.clear_review()
		a.set_status('The service returned a different package operation. Review it again.')
		return
	}
	a.review_snapshot.close()
	a.review_snapshot = review
	a.review_ready = true
	a.review_selected = if review.rows.len > 0 { 0 } else { -1 }
	// Cache numerical formatting once per review, outside the redraw path.
	count := review.rows.len.str()
	needed := (review.disk_needed / 1024 + if review.disk_needed % 1024 != 0 {
		u64(1)
	} else {
		u64(0)
	}).str()
	available := (review.disk_available / 1024).str()
	reserve := (review.disk_reserve / 1024).str()
	unsafe { a.review_summary.free() }
	a.review_summary = '${count} packages · ${needed} KiB needed · ${available} KiB free · ${reserve} KiB reserved'
	unsafe {
		count.free()
		needed.free()
		available.free()
		reserve.free()
	}
	if a.mirror_pending != '' {
		a.set_status(if a.mirror_lock_pending != '' {
			'Review the destination, deployment source and digest, then every application and dependency. Export preserves the exact locked versions and bundles _deployment.json.'
		} else { 'Review the destination and every application and dependency. Export uses the authenticated catalog versions; it preserves the installed application set.' })
	} else if a.deployment_pending != '' {
		message := 'Deployment file: ' + a.deployment_pending + '\nReview all dependencies and removals. This replaces the installed application set; personal data stays on disk.'
		a.set_status(message)
		unsafe { message.free() }
	} else if a.review == 'repair' {
		a.set_status('Repair preserves installed versions, permissions and the application set. Rows marked repair need rebuilding from authenticated payloads. Review every dependency before confirming; personal data stays on disk.')
	} else {
		a.set_status('Review every application and dependency, including retained packages and removals. Personal data stays on disk. Confirm applies this exact package set.')
	}
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
	if a.window_mode { return a.poll_window() }
	if a.terminal_app != unsafe { nil } { return a.terminal_app.poll() }
	if a.worker == unsafe { nil } { return false }
	mut changed := false
	// Drain a bounded number of chunks per UI poll, including after exit.
	for _ in 0 .. 16 {
		chunk := a.worker.stdout_read()
		if chunk.len == 0 { break }
		changed = true
		if a.worker_view || a.worker_review {
			if a.output.len + chunk.len <= software_output_limit {
				for byte in chunk { a.output << byte }
			} else {
				a.worker_failed = true
				a.output_truncated = true
				a.set_status('Package response exceeds the supported size.')
			}
		} else {
			a.operation_output(chunk)
		}
		unsafe { chunk.free() }
	}
	if a.worker.is_alive() { return changed }
	// A full drain batch can leave more queued data. Finish it next poll.
	if a.worker.is_pending(.stdout) {
		if chunk := a.worker.pipe_read(.stdout) {
			if chunk.len > 0 {
				if (a.worker_view || a.worker_review) && a.output.len + chunk.len <= software_output_limit {
					for byte in chunk { a.output << byte }
				} else if !a.worker_view && !a.worker_review {
					a.operation_output(chunk)
				} else {
					a.worker_failed = true
					a.output_truncated = true
					a.set_status('Package response exceeds the supported size.')
				}
				unsafe { chunk.free() }
				return true
			}
		}
	}
	code := a.worker.code
	if !a.worker_view && !a.worker_review { a.finish_operation_output() }
	if a.worker_verify && code == 0 && (!a.progress_seen || a.progress_snapshot.phase != 'complete') {
		a.operation_line('Verification ended without a complete result. Retry Verify installed.')
		a.worker_failed = true
	}
	if code != 0 || a.worker_failed { a.capture_failure(a.worker.args, code) }
	view := a.worker_view
	reviewing := a.worker_review
	running := a.worker_run
	verifying := a.worker_verify
	health := a.worker_health
	repository_worker := a.repository_worker
	data_worker := a.data_worker
	policy_worker := a.policy_worker
	mirroring := a.worker_mirror
	a.retire_worker()
	a.clear_admin_prompt()
	if code != 0 || (verifying && a.worker_failed) {
		if policy_worker == .review { a.clear_policy_review(); a.prepare_policy_pages(false) }
		if policy_worker == .apply { a.policy_ready = false; a.clear_policy_pages() }
		if repository_worker == .review { a.clear_repository_review() }
		if reviewing && repository_worker == .none { a.clear_review() }
		diagnostic := software_output_tail(a.output)
		if repository_worker == .refresh {
			unsafe { a.repository_result.free() }
			a.repository_result = 'Repository trust was saved, but catalog refresh failed: ' + diagnostic
			a.read_repositories()
			unsafe { diagnostic.free() }
			return true
		}
		if verifying && diagnostic.len > 0 {
			// Preserve the final failure rather than an earlier success-looking
			// line from an incomplete or failed verification worker.
			start := (diagnostic.last_index('\n') or { -1 }) + 1
			a.set_status(unsafe { tos(diagnostic.str + start, diagnostic.len - start) })
		} else { a.set_status(if diagnostic.len > 0 {
			diagnostic
		} else {
			'The package service failed. Check administrator access, repository configuration and disk space.'
		}) }
		unsafe { diagnostic.free() }
	} else if health {
		if !a.worker_failed { a.load_health() }
	} else if policy_worker == .list {
		if !a.worker_failed { a.load_policy_document() }
	} else if policy_worker == .review {
		if a.worker_failed { a.clear_policy_review(); a.prepare_policy_pages(false) } else { a.load_policy_review() }
	} else if policy_worker == .apply {
		unsafe { a.policy_result.free() }
		a.policy_result = 'Organization policy saved. Subsequent launches and maintenance use it; existing applications and personal data are retained.'.clone()
		a.read_policy()
	} else if data_worker == .list {
		if !a.worker_failed { a.load_personal_data() }
	} else if data_worker == .purge {
		unsafe { a.data_result.free() }
		a.data_result = 'Personal data deleted for ' + a.data_pending + '.'
		a.read_personal_data()
	} else if repository_worker == .list {
		if !a.worker_failed { a.load_repositories() }
	} else if repository_worker == .review {
		if a.worker_failed { a.clear_repository_review() } else { a.load_repository_review() }
	} else if repository_worker == .enroll {
		a.start(['update'], false)
		if a.worker != unsafe { nil } { a.repository_worker = .refresh }
		a.set_status('Repository trust was saved. Refreshing authenticated catalogs…')
	} else if repository_worker in [.revoke, .refresh] {
		unsafe { a.repository_result.free() }
		a.repository_result = if repository_worker == .revoke {
			'Repository revoked. Installed payloads, personal data and trust history were retained.'.clone()
		} else { 'Repository trusted and authenticated catalogs refreshed.'.clone() }
		a.read_repositories()
	} else if view {
		if !a.worker_failed { a.load_view() }
	} else if reviewing {
		if a.worker_failed { a.clear_review() } else { a.load_review() }
	} else if running {
		tail := software_output_tail(a.output)
		a.set_status(if tail.len > 0 { tail } else { 'Application finished successfully.' })
		unsafe { tail.free() }
	} else if mirroring {
		tail := software_output_tail(a.output)
		a.set_status(if tail.len > 0 { tail } else { 'Offline repository export completed.' })
		unsafe { tail.free() }
	} else if verifying {
		a.set_status('Installed files and launchers verified. Trust and organization policy still apply at launch.')
	} else {
		a.start(['view'], true)
	}
	if view && a.launch_request.len > 0 { a.run_requested() }
	return true
}

fn (mut a SoftwareApp) run_requested() {
	if a.worker != unsafe { nil } || a.launch_request.len == 0 { return }
	request := json2.decode[packagecore.Request](a.launch_request) or {
		a.set_status('Invalid application launch request.')
		unsafe { a.launch_request.free() }
		a.launch_request = ''
		return
	}
	defer {
		unsafe {
			request.id.free()
			request.document.free()
			a.launch_request.free()
		}
		a.launch_request = ''
	}
	request.validate() or {
		a.set_status(err.msg())
		return
	}
	a.clear_review()
	a.clear_repository_review()
	a.repository_mode = false
	a.deployment_mode = false
	a.mirror_mode = false
	for row in a.rows {
		if row.id == request.id && row.installed_version != '' && row.installed_window_protocol in [1, 2] {
			a.open_window(request, row.installed_window_protocol) or { a.set_status(err.msg()); unsafe { err.free() } }
			return
		}
	}
	a.start(if request.document.len > 0 {
		['run', request.id, request.document]
	} else {
		['run', request.id]
	}, false)
	if a.worker != unsafe { nil } {
		a.worker_run = true
		a.set_status('Starting application through its isolated runtime…')
	}
}

fn (a &SoftwareApp) next_poll_ms() u64 { return 100 }

fn (mut a SoftwareApp) handle(event_id string) ! {
	if a.admin_prompt { a.handle_admin(event_id); return }
	if a.window_mode { a.handle_window(event_id); return }
	if a.terminal_app != unsafe { nil } {
		if event_id == 'software.terminal-back' {
			if !a.terminal_app.exited { a.set_status('Exit the application before returning to Software.'); return }
			a.close_terminal()
			mut view_args := ['view']
			a.start(view_args, true)
			unsafe { (&array(&view_args)).free() }
		} else { a.terminal_app.handle(event_id)! }
		return
	}
	if a.failure_mode { a.handle_failure(event_id); return }
	if a.details_mode { a.handle_details(event_id); return }
	if event_id == 'software.failure' {
		if a.worker == unsafe { nil } && a.failure_pages.len > 0 { a.failure_mode = true; a.focus = false }
		return
	}
	if a.health_mode {
		if a.worker == unsafe { nil } { a.handle_health(event_id) }
		return
	}
	if event_id.starts_with(packagecore.request_prefix) {
		if a.policy_mode { a.set_status('Return to the catalog before opening an application.'); return }
		if a.data_mode { a.set_status('Return to the catalog before opening an application.'); return }
		if a.launch_mode { a.set_status('Close launch options before opening another application.'); return }
		if a.launch_request.len > 0 || (a.worker != unsafe { nil } && !a.worker_view) {
			a.set_status('An operation is already running in this window.')
			return
		}
		if event_id.len > 8192 { return }
		a.launch_request = unsafe { tos(event_id.str + packagecore.request_prefix.len, event_id.len - packagecore.request_prefix.len).clone() }
		// Initial catalog reading is asynchronous. Deliver the launch after it
		// finishes, including when the catalog is expired or unavailable.
		a.run_requested()
		return
	}
	if event_id == 'software.search' && !a.policy_mode && !a.data_mode && !a.deployment_mode && !a.mirror_mode {
		a.focus = true
		return
	}
	if a.worker != unsafe { nil } { return }
	if a.policy_mode { a.handle_policy(event_id); return }
	if a.data_mode { a.handle_personal_data(event_id); return }
	if a.launch_mode { a.handle_launch_options(event_id); return }
	if event_id == 'software.policy' {
		a.clear_review()
		a.clear_repository_review()
		a.repository_mode = false
		a.deployment_mode = false
		a.mirror_mode = false
		a.focus = false; a.select_all = false
		a.policy_mode = true
		a.read_policy()
		return
	}
	if event_id == 'software.data' {
		a.clear_review()
		a.clear_repository_review()
		a.repository_mode = false
		a.deployment_mode = false
		a.mirror_mode = false
		a.focus = false
		a.data_mode = true
		a.read_personal_data()
		return
	}
	if event_id == 'software.mirror' {
		a.clear_review()
		a.repository_mode = false
		a.deployment_mode = false
		a.mirror_mode = true
		a.initialize_mirror_field()
		a.focus = false
		a.select_all = false
		a.set_status('Choose a catalog application, installed application roots or an organization deployment lock, then enter a new export directory.')
		return
	}
	if a.mirror_mode && (a.review == '' || a.mirror_details) { a.handle_mirror(event_id); return }
	if event_id == 'software.repositories' {
		a.clear_review()
		a.deployment_mode = false
		a.repository_mode = true
		a.repository_focus = 0
		a.read_repositories()
		return
	}
	if a.repository_mode { a.handle_repositories(event_id); return }
	if event_id == 'software.deployment' {
		a.clear_review()
		a.deployment_mode = true
		a.initialize_deployment_field()
		a.focus = false
		a.select_all = false
		a.set_status('Enter an absolute deployment file path. Review the complete application set and removals before applying it.')
		return
	}
	if a.deployment_mode && a.review == '' { a.handle_deployment(event_id); return }
	for row, action in software_row_actions {
		if event_id == action {
			if a.review_ready && a.review_scroll + row < a.review_snapshot.rows.len {
				a.review_selected = a.review_scroll + row
			} else if a.review.len == 0 && a.scroll + row < a.matching.len {
				a.selected = a.matching[a.scroll + row]
				if a.rows[a.selected].diagnostic.len > 0 { a.set_status(a.rows[a.selected].diagnostic) }
			}
			return
		}
	}
	match event_id {
		'software.details' { a.open_details() }
		'software.run-options' { a.open_launch_options() }
		'software.run-terminal' {
			if a.selected < 0 || a.selected >= a.rows.len { return }
			row := a.rows[a.selected]
			if row.installed_version == '' || software_launch_kind(row) in ['runtime', 'data'] { return }
			a.open_terminal_request(packagecore.Request{ id: row.id })!
		}
		'software.run' {
			if a.launch_request.len > 0 || (a.worker != unsafe { nil } && !a.worker_view) {
				a.set_status('An operation is already running in this window.')
				return
			}
			if a.selected < 0 || a.selected >= a.rows.len || a.rows[a.selected].installed_version == '' {
				return
			}
			a.launch_request = json2.encode(packagecore.Request{ id: a.rows[a.selected].id })
			a.run_requested()
		}
		'software.catalog' {
			a.clear_review()
			a.filter = 0
			a.filter_rows()
		}
		'software.installed' {
			a.clear_review()
			a.filter = 1
			a.filter_rows()
		}
		'software.updates' {
			a.clear_review()
			a.filter = 2
			a.filter_rows()
			if a.update_error.len > 0 { a.set_update_status() }
		}
		'software.refresh' {
			a.clear_review()
			a.start(['update'], false)
		}
		'software.reload' {
			a.clear_review()
			a.start(['view'], true)
		}
		'software.verify' {
			if a.worker != unsafe { nil } || a.review != '' { return }
			a.start(['verify'], false)
		}
		'software.health' {
			if a.review != '' { return }
			a.read_health()
		}
		'software.repair' {
			if a.worker != unsafe { nil } || a.review != '' { return }
			a.begin_review('repair', [])
		}
		'software.up' {
			if a.review_ready {
				a.review_scroll = if a.review_scroll > a.page_rows {
					a.review_scroll - a.page_rows
				} else {
					0
				}
			} else {
				a.scroll = if a.scroll > a.page_rows { a.scroll - a.page_rows } else { 0 }
			}
		}
		'software.down' {
			if a.review_ready {
				if a.review_scroll + a.page_rows < a.review_snapshot.rows.len {
					a.review_scroll += a.page_rows
				}
			} else if a.scroll + a.page_rows < a.matching.len {
				a.scroll += a.page_rows
			}
		}
		'software.rollback' {
			a.begin_review('rollback', [])
		}
		'software.upgrade' {
			a.begin_review('upgrade', [])
		}
		'software.install', 'software.remove' {
			if a.selected < 0 || a.selected >= a.rows.len { return }
			row := a.rows[a.selected]
			if event_id == 'software.install' && row.updatable {
				a.begin_review('upgrade', [])
				return
			}
			if event_id == 'software.install' && (row.diagnostic.len > 0 || a.catalog_error.len > 0) {
				a.set_status(if row.diagnostic.len > 0 { row.diagnostic } else { a.catalog_error })
				return
			}
			if event_id == 'software.remove' && !row.requested {
				a.set_status('This package is a dependency. Remove the applications that require it first.')
				return
			}
			if event_id == 'software.install' && row.installed_version != '' && !row.requested {
				a.set_status('This package is a dependency. Use Update all to maintain the complete application set.')
				return
			}
			a.begin_review(if event_id == 'software.install' { 'install' } else { 'remove' }, [row.id])
		}
		'software.confirm' {
			if a.review_ready {
				mirroring := a.mirror_pending != ''
				a.start(if a.mirror_lock_pending != '' {
					['mirror-deployment-apply', a.review_snapshot.fingerprint, a.mirror_pending, a.mirror_lock_pending]
				} else if mirroring {
					['mirror-apply', a.review_snapshot.fingerprint, a.mirror_pending, ...a.review_snapshot.names]
				} else if a.deployment_pending != '' {
					['deployment-apply', a.review_snapshot.fingerprint, a.deployment_pending]
				} else {
					['apply', a.review_snapshot.fingerprint, a.review_snapshot.operation,
						...a.review_snapshot.names]
				}, false)
				if a.worker != unsafe { nil } {
					a.worker_mirror = mirroring
					a.clear_review()
				}
			}
		}
		'software.mirror.details' { a.mirror_details = true }
		'software.cancel' {
			a.clear_review()
			a.set_status('Operation cancelled before making changes.')
		}
		else {}
	}
}

fn (mut a SoftwareApp) key_input(input string) {
	if a.admin_prompt { a.admin_key_input(input); return }
	if a.window_mode { a.window_key_input(input); return }
	if a.terminal_app != unsafe { nil } { a.terminal_app.key_input(input); return }
	if a.failure_mode { if input == '\x1b' { a.failure_mode = false }; return }
	if a.details_mode { if input == '\x1b' { a.clear_details() }; return }
	if a.health_mode { if input == '\x1b' && a.worker == unsafe { nil } { a.clear_health() }; return }
	if a.policy_mode { a.policy_key_input(input); return }
	if a.data_mode { return }
	if a.launch_mode { a.launch_key_input(input); return }
	if a.repository_mode { a.repository_key_input(input); return }
	if a.mirror_mode { a.mirror_key_input(input); return }
	if a.deployment_mode { a.deployment_key_input(input); return }
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

fn (mut a SoftwareApp) paste_input(input string) {
	if a.admin_prompt { a.admin_paste_input(input); return }
	if a.window_mode { a.window_paste_input(input); return }
	if a.terminal_app != unsafe { nil } { a.terminal_app.paste_input(input); return }
	if a.failure_mode { return }
	if a.details_mode { return }
	if a.health_mode { return }
	if a.policy_mode { a.policy_paste_input(input); return }
	if a.data_mode { return }
	if a.launch_mode { a.launch_key_input(input); return }
	if a.repository_mode { a.repository_key_input(input) } else if a.deployment_mode {
		a.deployment_key_input(input)
	} else if a.mirror_mode {
		a.mirror_key_input(input)
	} else if a.focus { a.key_input(input) }
}

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

fn software_review_row(row pkgprotocol.ReviewPackage) SoftwareRow {
	return SoftwareRow{
		id:                row.id
		name:              row.name
		description:       row.description
		version:           row.version
		installed_version: row.installed_version
		architecture:      row.architecture
		kind:              row.kind
		runtime:           row.runtime
		repository:        row.repository
		public_key:        row.public_key
		license:           row.license
		proprietary:       row.proprietary
		firmware:          row.firmware
		permissions:       row.permissions
		requested:         row.requested
	}
}

fn (mut a SoftwareApp) build(size ui2.Rect) !ui2.Element {
	if a.admin_prompt { return a.build_admin(size) }
	if a.window_mode { return a.build_window(size) }
	if a.terminal_app != unsafe { nil } { return a.build_terminal(size) }
	if a.failure_mode { return a.build_failure(size) }
	width := int(size.width)
	height := int(size.height)
	if width < 640 || height < 610 {
		mut compact := frame_elements(2)
		compact << software_label('Software', 14, 8, width - 28, 28, false)
		compact << software_label('Enlarge this window to view package details and controls.',
			14, 40, width - 28, 60, false)
		return ui2.screen(app_surface, compact)
	}
	a.page_rows = if height > 400 { (height - if a.review != '' { 274 } else { 310 }) / 30 } else { 5 }
	if a.page_rows > software_row_actions.len { a.page_rows = software_row_actions.len }
	if a.details_mode { return a.build_details(width, height) }
	if a.health_mode { return a.build_health(width, height) }
	if a.policy_mode { return a.build_policy(width, height) }
	if a.data_mode { return a.build_personal_data(width, height) }
	if a.launch_mode { return a.build_launch_options(width, height) }
	if a.repository_mode { return a.build_repositories(width, height) }
	if a.mirror_mode && (a.review == '' || a.mirror_details) { return a.build_mirror(width, height) }
	if a.deployment_mode && a.review == '' { return a.build_deployment(width, height) }
	mut children := frame_elements(48)
	reviewing := a.review.len > 0
	children << software_label('Software', 14, 8, 150, 28, false)
	if reviewing {
		children << software_label(if a.deployment_pending != '' { 'Review deployment'.clone() } else {
			'Review ${a.review}'
		}, 170, 8, if a.mirror_pending != '' { width - 340 } else { width - 188 }, 28, true)
		children << software_label(a.review_summary, 14, 40, width - 28, 44, false)
	} else {
		children << console_field('software.search', editor_bytes_text(a.query), 170, 8, width - 492, a.focus)
		children << software_button('software.mirror', 'Export offline', width - 308, 8, 98)
		children << software_button('software.deployment', 'Deployment', width - 202, 8, 96)
		children << software_button('software.refresh', 'Refresh', width - 98, 8, 84)
		children << software_button('software.catalog', 'Catalog', 14, 46, 90)
		children << software_button('software.installed', 'Installed', 112, 46, 90)
		children << software_button('software.updates', 'Updates', 210, 46, 90)
		children << software_button('software.reload', 'Reload', 308, 46, 90)
		children << software_button('software.repositories', 'Repositories', 406, 46, 142)
	}
	for slot in 0 .. a.page_rows {
		if reviewing {
			index := a.review_scroll + slot
			if !a.review_ready || index >= a.review_snapshot.rows.len { break }
			row := a.review_snapshot.rows[index]
			children << ui2.Element{
				...ui2.button(software_row_actions[slot], '${if a.review == 'repair' && row.action == 'update' { 'repair' } else { row.action }}: ${row.name}',
					ui2.rect(14, f64(90 + slot * 30), 236, 28),
					ui2.BoxStyle{ bg: if index == a.review_selected {
						settings_choice_bg
					} else {
						body_panel
					}, radius: 3 },
					ui2.TextStyle{ color: body_text, size: 12, align: .left })
				key: workflow_owned_text_key
			}
		} else {
			index := a.scroll + slot
			if index >= a.matching.len { break }
			row_index := a.matching[index]
			row := a.rows[row_index]
			children << ui2.button(software_row_actions[slot], row.name,
				ui2.rect(14, f64(90 + slot * 30), 236, 28),
				ui2.BoxStyle{ bg: if row_index == a.selected {
					settings_choice_bg
				} else {
					body_panel
				}, radius: 3 },
				ui2.TextStyle{ color: body_text, size: 12, align: .left })
		}
	}
	children << software_button('software.up', 'Previous', 14, height - 138, 110)
	children << software_button('software.down', 'Next', 136, height - 138, 110)
	if (reviewing && a.review_ready && a.review_selected >= 0 && a.review_selected < a.review_snapshot.rows.len)
		|| (!reviewing && a.selected >= 0 && a.selected < a.rows.len) {
		row := if reviewing {
			software_review_row(a.review_snapshot.rows[a.review_selected])
		} else {
			a.rows[a.selected]
		}
		children << software_button('software.details', if reviewing { 'Package details…' } else { 'Details…' }, 14, height - 176, if reviewing { 232 } else { 110 })
		children << software_label(row.name, 274, 90, if !reviewing && row.installed_version != '' && software_launch_kind(row) !in ['runtime', 'data'] { width - 466 } else { width - 288 }, 28, false)
		children << software_label(row.description, 274, 124, if !reviewing && row.installed_version != '' && software_launch_kind(row) !in ['runtime', 'data'] { width - 466 } else { width - 288 }, 72, false)
		children << software_label(if !reviewing && row.update_action == 'remove' {
			'Installed: ${row.installed_version}    Removed by Update all'
		} else if !reviewing && row.updatable {
			'Planned: ${row.version}    Installed: ${row.installed_version}'
		} else {
			'Version: ${row.version}    Installed: ${row.installed_version}'
		}, 274, 204, width - 288, 28, true)
		children << software_label('Architecture: ${row.architecture}    Kind: ${row.kind}    Runtime: ${row.runtime}', 274, 236, width - 288, 28, true)
		children << software_label('Repository: ${row.repository}', 274, 268, width - 288, 28, true)
		children << software_label('Publisher key: ${row.public_key}', 274, 300, width - 288, 48, true)
		permissions := row.permissions.join(', ')
		children << software_label('Permissions: ${permissions}', 274, 352, width - 288, 48, true)
		unsafe { permissions.free() }
		proprietary := if row.proprietary { ' (proprietary)' } else { '' }
		firmware := if row.firmware { ' — firmware' } else { '' }
		children << software_label('License: ${row.license}${proprietary}${firmware}', 274, 404, width - 288, 28, true)
		if reviewing {
			children << software_label(if row.requested {
				'Requested application'
			} else {
				'Dependency or removed package'
			},
				274, height - 176, width - 288, 28, false)
		} else {
			if row.updatable || row.installed_version == '' {
				children << software_button('software.install', if row.updatable {
					'Review updates'
				} else { 'Install' }, 274, height - 176, 160)
			}
			if row.installed_version != '' {
				children << software_button('software.remove', 'Uninstall', 446, height - 176, 130)
				if software_launch_kind(row) !in ['runtime', 'data'] {
					children << software_button('software.run', a.launch_label, width - 174, 46, 160)
					if row.installed_window_protocol == 0 {
						children << software_button('software.run-terminal', 'Launch in Terminal', width - 174, 78, 160)
						children << software_button('software.run-options', 'Launch options…', width - 174, 110, 160)
					}
				}
			}
		}
	}
	if a.review.len > 0 {
		if a.review_ready {
			children << software_button('software.confirm', 'Confirm', 274, height - 138, 130)
		}
		children << software_button('software.cancel', 'Cancel', 416, height - 138, 110)
		if a.mirror_pending != '' {
			children << software_button('software.mirror.details', 'Export details', width - 150, 8, 136)
		}
	} else {
		children << software_button('software.upgrade', 'Update all', 274, height - 138, 112)
		children << software_button('software.rollback', 'Rollback', 394, height - 138, 100)
		children << software_button('software.data', 'Personal data', 502, height - 138, 124)
		children << software_button('software.verify', 'Verify installed', 136, height - 176, 110)
		if a.rows.any(it.installed_version != '') {
			children << software_button('software.repair', 'Repair installed', 14, height - 214, 110)
		}
		children << software_button('software.health', 'Health report', 136, height - 214, 110)
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, a.progress_seen)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) prepare_close() bool {
	if a.admin_prompt { a.cancel_admin(); return true }
	if a.window_mode && a.worker != unsafe { nil } {
		a.request_window_close()
		return false
	}
	if a.terminal_app != unsafe { nil } && !a.terminal_app.exited {
		a.set_status('Exit the application before closing Software.')
		return false
	}
	if a.worker != unsafe { nil } && !a.worker_view && !a.worker_review && !a.worker_verify {
		a.set_status(if a.data_worker == .purge {
			'Wait for personal data deletion to finish before closing Software.'
		} else if a.worker_run {
			'Close the application first, then close Software.'
		} else {
			'Wait for the package transaction to finish before closing Software.'
		})
		return false
	}
	return true
}

fn (mut a SoftwareApp) close_app() {
	a.clear_admin_prompt()
	a.clear_window()
	a.clear_launch_options()
	a.close_terminal()
	if a.worker != unsafe { nil } {
		// Forced desktop retirement must not kill the lease holder while its
		// sandbox child can still use runtime files. Detach it for PID 1 to reap.
		if !a.worker_run && a.worker.is_alive() {
			a.worker.signal_kill()
			a.worker.wait()
		}
		a.retire_worker()
	}
	for row in a.rows { software_free_row(row) }
	a.clear_review()
	a.clear_repository_review()
	a.repository_status.close()
	a.clear_personal_data()
	a.clear_policy()
	a.clear_progress()
	a.clear_failure()
	a.clear_health()
	unsafe {
		a.launch_request.free()
		a.service_path.free()
		a.launch_label.free()
		a.rows.free()
		a.matching.free()
		a.query.free()
		a.output.free()
		a.progress_pending.free()
		a.status.free()
		a.catalog_error.free()
		a.update_error.free()
		a.repository_id.free()
		a.repository_url.free()
		a.repository_key.free()
		a.repository_result.free()
		a.deployment_path.free()
		a.mirror_path.free()
		a.mirror_lock_path.free()
	}
	a = SoftwareApp{}
}
