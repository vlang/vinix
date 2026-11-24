// SPDX-License-Identifier: GPL-2.0-or-later
// Runs the actual Software controller against the staged services in a guest.
// ui2 constructs real element trees; presentation and Terminal are not exercised.
module main

import desktop.packagecore
import crypto.sha256
import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

struct Desktop { tz_offset_seconds i64 }
interface NativeApp { mut: build(ui2.Rect) !ui2.Element handle(string) ! }
const console_filter_limit = 256
const body_text = u32(0x111111)
const body_panel = u32(0xeeeeee)
const settings_choice_bg = u32(0xccccff)
const app_surface = u32(0xffffff)
const app_accent = u32(0x4060b0)
const body_rule = u32(0xcccccc)
const workflow_owned_text_key = 'owned'
const workflow_owned_id_text_key = 'owned-id-text'

fn editor_bytes_text(bytes []u8) string { return if bytes.len == 0 { '' } else { unsafe { tos(bytes.data, bytes.len) } } }
fn console_sanitize(text string) string { return text.clone() }
fn console_backspace(mut bytes []u8, selected bool) {
	if selected { bytes.clear(); return }
	if bytes.len > 0 {
		mut end := bytes.len - 1
		for end > 0 && bytes[end] & 0xc0 == 0x80 { end-- }
		bytes.trim(end)
	}
}
fn console_paste_field(mut bytes []u8, text string, limit int, selected bool) {
	if selected { bytes.clear() }
	for byte in text { if bytes.len < limit && byte >= 32 { bytes << byte } }
}
fn console_field(id string, text string, x int, y int, width int, _ bool) ui2.Element {
	return ui2.button(id, text, ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{}, ui2.TextStyle{})
}
fn frame_elements(capacity int) []ui2.Element { return []ui2.Element{cap: capacity} }

fn image_free_tree(tree ui2.Element) {
	for child in tree.children { image_free_tree(child) }
	unsafe {
		if tree.key in [workflow_owned_text_key, workflow_owned_id_text_key]! { tree.text.free() }
		if tree.key == workflow_owned_id_text_key { tree.id.free() }
		(&array(&tree.children)).free()
	}
}
fn image_tree_has(tree ui2.Element, id string) bool {
	if tree.id == id { return true }
	for child in tree.children { if image_tree_has(child, id) { return true } }
	return false
}
fn image_control(mut app SoftwareApp, id string) ! {
	image_control_at(mut app, id, ui2.rect(0, 0, 960, 720))!
}
fn image_control_at(mut app SoftwareApp, id string, size ui2.Rect) ! {
	eprintln('SOFTWARE CONTROL ' + id)
	tree := app.build(size)!
	defer { image_free_tree(tree) }
	assert image_tree_has(tree, id), 'missing visible control: ' + id + '; ' + app.status
	app.handle(id)!
}
fn image_compact_deployment_action(mut app SoftwareApp, id string) ! {
	size := ui2.rect(0, 0, 320, 240)
	image_free_tree(app.build(size)!)
	for _ in 0 .. 8 { app.key_input('\x1b[5~') }
	for _ in 0 .. 8 {
		tree := app.build(size)!
		found := image_tree_has(tree, id)
		image_free_tree(tree)
		if found { image_control_at(mut app, id, size)!; return }
		image_control_at(mut app, 'software.deployment.action.next', size)!
	}
	return error('compact deployment action unavailable: ' + id)
}
fn image_wait(mut app SoftwareApp) !bool {
	mut progress := false
	for _ in 0 .. 6000 {
		app.poll()
		progress = progress || app.progress_seen
		if app.worker == unsafe { nil } { return progress }
		if app.admin_prompt { return error('unexpected pending administrator prompt') }
		time.sleep(5 * time.millisecond)
	}
	return error('Software worker timeout: ' + app.status)
}
fn image_frame(mut app SoftwareApp, sequence u64) ! {
	for _ in 0 .. 6000 {
		app.poll()
		if app.window_frame.sequence == sequence { return }
		if app.worker == unsafe { nil } { break }
		time.sleep(5 * time.millisecond)
	}
	return error('Software window timeout: ' + app.status)
}
fn image_submit_password(mut app SoftwareApp, password string) ! {
	image_submit_password_at(mut app, password, ui2.rect(0, 0, 960, 720))!
}
fn image_submit_password_at(mut app SoftwareApp, password string, size ui2.Rect) ! {
	assert app.admin_prompt
	image_control_at(mut app, 'software.admin.password', size)!
	app.paste_input(password)
	assert app.admin_password_len == password.len && editor_bytes_text(app.admin_mask) != password
	image_control_at(mut app, 'software.admin.approve', size)!
	assert !app.admin_prompt && app.admin_password_len == 0 && app.admin_password.all(it == 0)
	assert !app.prepare_close()
}
fn image_approve(mut app SoftwareApp, password string) !bool {
	image_submit_password(mut app, password)!
	return image_wait(mut app)!
}

fn image_enroll_and_refresh(mut app SoftwareApp, password string) ! {
	repository := json2.decode[pkgprotocol.Repository](os.read_file('/usr/share/native-catalog/releases/field-repository.json')!)!
	image_control(mut app, 'software.repositories')!
	image_wait(mut app)!
	assert app.repository_status.repositories.len == 1 && app.repository_status.repositories[0].id == 'native'
	image_control(mut app, 'software.offline')!
	image_control(mut app, 'software.repository.new')!
	app.paste_input(repository.id)
	image_control(mut app, 'software.repository.url')!
	app.paste_input(repository.url)
	image_control(mut app, 'software.repository.key')!
	app.paste_input(repository.public_key)
	image_control(mut app, 'software.repository.enroll')!
	image_wait(mut app)!
	assert app.repository_review_ready && app.repository_review.id == repository.id
	assert app.repository_review.public_key == repository.public_key && app.repository_review.sequence == 2
	image_control(mut app, 'software.repository.confirm')!
	assert app.admin_prompt && app.repository_worker == .enroll
	image_submit_password(mut app, password)!
	for _ in 0 .. 6000 {
		app.poll()
		if app.admin_prompt || app.worker == unsafe { nil } { break }
		time.sleep(5 * time.millisecond)
	}
	assert app.admin_prompt && app.repository_worker == .refresh, app.status
	assert app.worker.args == ['admin', '--progress', '--offline', 'update', repository.id,
		pkgprotocol.repository_refresh_fingerprint(repository)]
	assert app.status.contains('trust was saved') && app.admin_password_len == 0
	image_approve(mut app, password)!
	assert app.status == 'Repository trusted and its catalog refreshed.' && app.repository_mode
	assert app.selected_repository_refresh_id() == repository.id
	image_control(mut app, 'software.repository.back')!
	image_wait(mut app)!
	assert app.catalog_error == '' && app.rows.len == 3 && app.rows.all(it.installed_version == '1.1.0')
}
fn image_select(mut app SoftwareApp, id string) ! {
	image_control(mut app, 'software.catalog')!
	image_control(mut app, 'software.search')!
	app.key_input('\x01')
	app.paste_input(id)
	assert app.matching.len == 1 && app.rows[app.matching[0]].id == id
	image_control(mut app, 'software.row.0')!
	app.focus = false
}
fn image_apply(mut app SoftwareApp, action string, password string) ! {
	if app.catalog_browser_mode {
		image_control_at(mut app, action, ui2.rect(0, 0, 320, 240))!
		assert !app.catalog_browser_mode && app.worker_review && !app.admin_prompt
	} else {
		image_control(mut app, action)!
	}
	image_wait(mut app)!
	assert app.review_ready, app.status
	for row in app.review_snapshot.rows {
		assert row.repository == 'native' && row.public_key.len == 64 && row.license == 'MIT'
	}
	image_control(mut app, 'software.confirm')!
	assert image_approve(mut app, password)!, 'missing structured transaction progress'
	assert !app.worker_failed && app.catalog_error == '', app.status
}
fn image_close_window(mut app SoftwareApp) ! {
	image_control(mut app, 'software.window.close')!
	image_wait(mut app)!
	assert app.status.contains('finished'), app.status
	image_control(mut app, 'software.window.back')!
	image_wait(mut app)!
}
fn image_counter(mut app SoftwareApp) ! {
	image_select(mut app, 'org.vinix.counter')!
	image_control(mut app, 'software.run')!
	assert !app.admin_prompt && app.window_protocol == 1
	image_frame(mut app, 1)!
	assert app.window_frame.elements.any(it.text == 'Count: 0')
	image_control(mut app, software_window_action + 'increase')!
	image_frame(mut app, 2)!
	assert app.window_frame.elements.any(it.text == 'Count: 1')
	image_close_window(mut app)!
}
fn image_memo(mut app SoftwareApp, edit bool) ! {
	// Use the same request a Start/Open With client sends to a Software window.
	app.handle(packagecore.request_prefix + json2.encode(packagecore.Request{ id: 'org.vinix.memo' }))!
	image_frame(mut app, 1)!
	assert app.window_protocol == 2 && !app.admin_prompt
	if edit {
		image_control(mut app, software_window_input_action + software_window_sequence(1) + 'memo')!
		app.paste_input('Saved through ordinary Software')
		app.key_input('\r')
		image_frame(mut app, 2)!
		image_control(mut app, software_window_control(2, 2, 'save'))!
		image_frame(mut app, 3)!
	} else { assert app.window_frame.elements.any(it.kind == 'input' && it.text == 'Saved through ordinary Software') }
	image_close_window(mut app)!
}

fn image_counter_reopen(mut app SoftwareApp) ! {
	image_select(mut app, 'org.vinix.counter')!
	image_control(mut app, 'software.run')!
	image_frame(mut app, 1)!
	assert app.window_protocol == 1 && app.window_frame.elements.any(it.text == 'Count: 1')
	image_close_window(mut app)!
}

fn image_release_observation() ![]string {
	mut result := []string{}
	for path in ['/etc/vinix-packages/config.json', pkgprotocol.image_applications_path,
		'/var/lib/vinix-packages/current/state.json', '/var/lib/vinix-packages/catalog.json',
		'/var/lib/vinix-packages/trust-history.json']! {
		if !os.exists(path) { result << 'absent'; continue }
		bytes := os.read_bytes(path)!
		defer { unsafe { bytes.free() } }
		result << sha256.sum(bytes).hex()
	}
	result << os.readlink('/var/lib/vinix-packages/current') or { '' }
	return result
}

fn image_release_audit(mut app SoftwareApp, phase string, version string) ! {
	before := image_release_observation()!
	failures := app.failure_pages.len
	image_control(mut app, 'software.deployment')!
	assert app.release_deployment_available
	image_compact_deployment_action(mut app, 'software.deployment.release-audit')!
	assert app.worker_audit && !app.admin_prompt && app.review == ''
	arguments := ['--json', 'deployment-audit', pkgprotocol.image_applications_path]
	assert app.worker.args == if app.offline_requested { ['--offline', ...arguments] } else { arguments }
	image_wait(mut app)!
	assert app.audit_ready && app.audit_snapshot.rows.len == 3 && !app.worker_failed, app.status
	assert app.audit_snapshot.matches == (version == '1.0.0')
	assert app.failure_pages.len == failures, 'a complete audit must preserve prior diagnostics without adding a failure'
	for row in app.audit_snapshot.rows {
		assert row.expected_version == '1.0.0' && row.installed_version == version
		assert row.status == if version == '' { 'missing' } else if version == '1.0.0' { 'match' } else { 'changed' }
		if version == '1.1.0' { assert 'version' in row.differences && 'metadata_sha256' in row.differences }
	}
	bytes := os.read_bytes(pkgprotocol.image_applications_path)!
	defer { unsafe { bytes.free() } }
	assert app.audit_snapshot.deployment_sha256 == sha256.sum(bytes).hex()
	assert !app.admin_prompt && app.review == '' && before == image_release_observation()!
	image_control(mut app, 'software.audit.back')!
	image_control(mut app, 'software.deployment.back')!
	println('SOFTWARE RELEASE audit ' + phase + ' installed=' + (if version == '' { 'absent' } else { version })
		+ ' exact-baseline unchanged-state ordinary-read PASS')
}

fn image_cold_maintenance(mut app SoftwareApp, phase string, password string) ! {
	expected := if phase == 'cold-upgrade' { '1.0.0' } else { '1.1.0' }
	assert app.rows.len == 3 && app.rows.all(it.installed_version == expected), app.status
	image_release_audit(mut app, phase, expected)!
	image_counter_reopen(mut app)!
	image_memo(mut app, false)!
	if phase == 'cold-reopen' { return }
	if phase == 'cold-upgrade' {
		image_control(mut app, 'software.refresh')!
		assert image_approve(mut app, password)!
		image_control(mut app, 'software.catalog')!
		image_control(mut app, 'software.search')!
		app.key_input('\x01'); app.key_input('\x7f'); app.focus = false
		image_control(mut app, 'software.updates')!
		assert app.matching.len == 3 && app.rows.all(it.updatable)
		image_apply(mut app, 'software.upgrade', password)!
		assert app.rows.all(it.installed_version == '1.1.0'), app.status + '\n' + app.rows.map(it.id + '=' + it.installed_version).join(', ') + '\n' + app.failure_pages.map(it.text).join('\n')
		image_release_audit(mut app, 'cold-upgraded', '1.1.0')!
	} else {
		assert phase == 'cold-maintain'
		image_apply(mut app, 'software.rollback', password)!
		assert app.rows.all(it.installed_version == '1.0.0')
		image_release_audit(mut app, 'cold-rollback', '1.0.0')!
		for id in ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']! {
			image_select(mut app, id)!
			image_apply(mut app, 'software.remove', password)!
			assert !os.exists('/var/lib/vinix-packages/current/share/applications/vinix-' + id + '.desktop')
		}
		assert app.rows.all(it.installed_version == '')
		image_release_audit(mut app, 'cold-removed', '')!
		for id in ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']! {
			image_select(mut app, id)!
			image_apply(mut app, 'software.install', password)!
		}
		assert app.rows.all(it.installed_version == '1.1.0')
		image_release_audit(mut app, 'cold-reinstalled', '1.1.0')!
	}
	image_counter_reopen(mut app)!
	image_memo(mut app, false)!
}

fn image_run() ! {
	assert os.geteuid() in [1000, 1001]
	password := if os.geteuid() == 1000 { 'alex has a password' } else { 'sam has another' }
	mut app := &SoftwareApp{ administration_required: true, rows: []SoftwareRow{cap: 128}, matching: []int{cap: 128},
		query: []u8{cap: 256}, output: []u8{cap: 8192} }
	defer { app.close_app(); unsafe { free(app) } }
	unsafe { app.rows.flags |= .noslices; app.matching.flags |= .noslices; app.query.flags |= .noslices; app.output.flags |= .noslices }
	app.start(['view'], true)
	image_wait(mut app)!
	assert app.launch_label == 'Launch' // the root image's launch_user cannot change this identity
	phase := os.args[1]
	bundled_https := os.exists('/usr/share/package-fixtures/bundled-https')
	manual_refresh := os.exists('/usr/share/package-fixtures/manual-release-refresh')
	if bundled_https && phase !in ['install', 'targeted-refresh', 'enrollment-refresh']! {
		assert !app.offline && !app.offline_requested
		compact := ui2.rect(0, 0, 320, 240)
		image_control_at(mut app, 'software.offline', compact)!
		assert app.offline_requested && app.worker == unsafe { nil }
	}
	if phase.starts_with('cold-') {
		image_cold_maintenance(mut app, phase, password)!
	} else if phase == 'install' {
		compact := ui2.rect(0, 0, 320, 240)
		image_control_at(mut app, 'software.mirror', compact)!
		assert app.mirror_mode && app.worker == unsafe { nil } && !app.admin_prompt
		export_form := app.build(compact)!
		assert image_tree_has(export_form, 'software.mirror.path') && image_tree_has(export_form, 'software.mirror.review')
		assert !image_tree_has(export_form, 'software.confirm')
		image_free_tree(export_form)
		image_control_at(mut app, 'software.mirror.back', compact)!
		assert !app.mirror_mode && app.worker == unsafe { nil }
		println('SOFTWARE IMAGE compact catalog opened Export offline and returned without starting work PASS')
		refresh := if bundled_https { 'software.release.catalog.offline' } else { 'software.refresh' }
		if manual_refresh {
			assert bundled_https
			image_control_at(mut app, 'software.deployment', compact)!
			image_compact_deployment_action(mut app, 'software.deployment.release')!
			assert app.release_catalog_mode && app.deployment_mode
			image_control(mut app, 'software.release.catalog.back')!
			assert app.deployment_mode && !app.release_catalog_mode && app.worker == unsafe { nil }
			image_compact_deployment_action(mut app, 'software.deployment.release')!
			assert app.release_catalog_mode && !app.admin_prompt && app.worker == unsafe { nil }
		} else if bundled_https {
			app.handle(software_first_run_release_action)!
			assert app.release_catalog_mode && !app.admin_prompt && app.worker == unsafe { nil }
		}
		image_control_at(mut app, refresh, if bundled_https { ui2.rect(0, 0, 320, 240) } else { ui2.rect(0, 0, 960, 720) })!
		image_control(mut app, 'software.admin.cancel')!
		assert app.worker == unsafe { nil } && app.status.contains('cancelled')
		image_control(mut app, refresh)!
		image_approve(mut app, 'incorrect fixture password')!
		assert app.failure_pages.len > 0 && app.rows.len == 0
		image_control(mut app, refresh)!
		assert image_approve(mut app, password)!
		assert app.rows.len == 3 && app.offline && app.catalog_error == '', app.status
		if bundled_https {
			assert app.review_ready && app.deployment_pending == pkgprotocol.image_applications_path && !app.admin_prompt
			assert !os.exists('/var/lib/vinix-packages/current')
			println(if manual_refresh { 'SOFTWARE IMAGE manual offline refresh resumed exact release review before activation PASS' }
				else { 'SOFTWARE IMAGE first-run offline refresh resumed exact release review before activation PASS' })
			image_control(mut app, 'software.cancel')!
			image_control(mut app, 'software.deployment.back')!
		}
		image_release_audit(mut app, 'initial-empty', '')!
		image_control_at(mut app, 'software.deployment', compact)!
		assert app.release_deployment_available && editor_bytes_text(app.deployment_path) == pkgprotocol.image_applications_path
		image_compact_deployment_action(mut app, 'software.deployment.release')!
		assert app.worker_review && !app.admin_prompt && !app.review_ready
		image_wait(mut app)!
		assert app.review_ready && app.review_snapshot.rows.len == 3 && app.review_snapshot.rows.all(it.action == 'install')
		assert app.review_snapshot.rows.all(it.repository == 'native' && it.public_key.len == 64 && it.version == '1.0.0')
		image_control(mut app, 'software.confirm')!
		assert image_approve(mut app, password)!
		assert app.rows.all(it.installed_version == '1.0.0') && !app.worker_failed
		if bundled_https {
			println('SOFTWARE IMAGE selected offline mode and installed the bundled HTTPS catalog with separate approval PASS')
		}
		println('SOFTWARE IMAGE staged-release-catalog discovered full-set review separate administrator approval exact offline install PASS')
		image_release_audit(mut app, 'initial-installed', '1.0.0')!
		println('SOFTWARE IMAGE compact-deployment 320x240 keyboard paging visible release review and audit separate approval PASS')
		println('SOFTWARE IMAGE compact catalog opened Deployment for signed release review and separate approval PASS')
		image_counter(mut app)!
		image_memo(mut app, true)!
		document := os.home_dir() + '/software document ; $literal.txt'
		os.write_file(document, 'Explicit ordinary-user document grant')!
		app.handle(packagecore.request_prefix + json2.encode(packagecore.Request{ id: 'org.vinix.package-hello', document: document }))!
		image_wait(mut app)!
		assert app.status.contains('Explicit ordinary-user document grant'), app.status
		println('SOFTWARE IMAGE ordinary-admin real-refresh cancel bad-password review install progress native-window-1-2 document-grant PASS')
	} else if phase == 'enrollment-refresh' {
		image_enroll_and_refresh(mut app, password)!
	} else if phase == 'targeted-refresh' {
		compact := ui2.rect(0, 0, 320, 240)
		image_control_at(mut app, 'software.repositories', compact)!
		image_wait(mut app)!
		assert app.repository_status.repositories.len == 2
		image_control_at(mut app, 'software.offline', compact)!
		image_control_at(mut app, 'software.repository.browse', compact)!
		image_control_at(mut app, 'software.report.package.next', compact)!
		field := app.repository_status.repositories[app.repository_browse_index]
		assert field.id == 'field'
		image_control_at(mut app, 'software.repository.browse.refresh', compact)!
		assert app.admin_prompt && app.worker.args == ['admin', '--progress', '--offline', 'update', 'field',
			pkgprotocol.repository_refresh_fingerprint(field)]
		image_submit_password_at(mut app, password, compact)!
		observed_progress := image_wait(mut app)!
		assert observed_progress && app.status == 'Selected repository refreshed.' && app.repository_mode
		image_control_at(mut app, 'software.repository.back', compact)!
		image_wait(mut app)!
		assert app.rows.len == 3 && app.rows.all(it.installed_version == '1.0.0') && app.catalog_error == ''
		println('SOFTWARE IMAGE compact repository browser and refresh approval PASS')
	} else if phase == 'standard' {
		image_release_audit(mut app, 'standard-account', '1.0.0')!
		image_select(mut app, 'org.vinix.counter')!
		image_apply_standard_refusal(mut app, password)!
		image_counter(mut app)!
		assert !os.exists('/home/alex/.local/share/vinix-apps/org.vinix.counter/counter.txt')
		println('SOFTWARE IMAGE standard-account denied-administration own-isolated-launch private-data PASS')
	} else if phase == 'updates' {
		image_control(mut app, 'software.refresh')!
		assert image_approve(mut app, password)!
		image_control(mut app, 'software.updates')!
		assert app.matching.len == 3 && app.rows.all(it.updatable)
		image_control_at(mut app, 'software.catalog.browse', ui2.rect(0, 0, 320, 240))!
		image_apply(mut app, 'software.catalog.review-upgrade', password)!
		assert app.rows.all(it.installed_version == '1.1.0')
		image_apply(mut app, 'software.rollback', password)!
		assert app.rows.all(it.installed_version == '1.0.0')
		image_memo(mut app, false)!
		println('SOFTWARE IMAGE reviewed-update rollback retained-memo PASS')
	} else {
		assert phase == 'reinstall'
		image_select(mut app, 'org.vinix.memo')!
		image_control_at(mut app, 'software.catalog.browse', ui2.rect(0, 0, 320, 240))!
		image_apply(mut app, 'software.catalog.review-remove', password)!
		image_select(mut app, 'org.vinix.memo')!
		assert app.rows[app.selected].installed_version == ''
		assert !os.exists('/var/lib/vinix-packages/current/share/applications/vinix-org.vinix.memo.desktop')
		image_control_at(mut app, 'software.catalog.browse', ui2.rect(0, 0, 320, 240))!
		image_apply(mut app, 'software.catalog.review-install', password)!
		image_memo(mut app, false)!
		println('SOFTWARE IMAGE updates rollback uninstall registration cached-reinstall retained-memo PASS')
	}
}
fn image_apply_standard_refusal(mut app SoftwareApp, password string) ! {
	image_control(mut app, 'software.remove')!
	image_wait(mut app)!
	assert app.review_ready
	image_control(mut app, 'software.confirm')!
	image_approve(mut app, password)!
	assert app.failure_pages.len > 0 && app.status.contains('cannot approve'), app.status
	image_control(mut app, 'software.reload')!
	image_wait(mut app)!
	assert app.rows.all(it.installed_version == '1.0.0')
}
fn main() { image_run() or { eprintln(err); exit(1) } }
