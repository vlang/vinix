// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import encoding.utf8
import desktop.packagecore
import tools.packages.pkgprotocol

const policy_fixture_path = '/private/tmp/company policy; $literal é.json'

fn fixture_policy_document() pkgprotocol.PolicyDocument {
	return pkgprotocol.PolicyDocument{ format: 1, architecture: 'aarch64', policy: pkgprotocol.PolicySettings{
		offline: true, allowed: ['app', 'runtime'], pins: [pkgprotocol.PolicyPin{ id: 'runtime', minimum: '1.0.0', before: '2.0.0' }],
		permissions: ['display', 'files'], licenses: ['Vendor «license» {"policy":"text"}'], allow_firmware: true, reserve_bytes: 65536 } }
}

fn fixture_policy_review() pkgprotocol.PolicyReview {
	return pkgprotocol.PolicyReview{ format: 1, architecture: 'aarch64', generation: 3, fingerprint: 'c'.repeat(64),
		previous: fixture_policy_document().policy, proposed: pkgprotocol.PolicySettings{ offline: true }, rows: [
		pkgprotocol.PolicyImpact{ id: 'app', name: 'Editor', version: '1.0.0', kind: 'native', license: 'MIT', repository: 'fixture', public_key: 'a'.repeat(64), requested: true, diagnostic_after: 'runtime: permissions blocked by organization policy' },
		pkgprotocol.PolicyImpact{ id: 'runtime', name: 'Shared runtime', version: '1.0.0', kind: 'runtime', license: 'Vendor', proprietary: true, firmware: true, repository: 'fixture', public_key: 'a'.repeat(64), diagnostic_after: 'runtime: permissions blocked by organization policy' }] }
}

fn software_policy_service_fixture(args []string) !bool {
	if args[1] == 'policy' {
		assert args.len == 2
		path := os.getenv('VINIX_SOFTWARE_POLICY_FIXTURE')
		println(if os.exists(path) { os.read_file(path)! } else { json2.encode(fixture_policy_document()) })
		return true
	}
	if args[1] == 'policy-review' {
		assert args.len == 3
		if args[2] == '/missing-policy' { eprintln('fixture: policy file is unavailable'); exit(17) }
		if args[2] == '/bad-policy' { println('{"format":2}'); return true }
		assert args[2] == policy_fixture_path || args[2].len > 300 || args[2] == '/stale-policy'
		println(json2.encode(fixture_policy_review()))
		return true
	}
	if args[1] == 'admin' && args.len > 2 && args[2] == 'policy-apply' {
		assert args.len == 5 && args[3] == 'c'.repeat(64)
		mut bytes := [257]u8{}
		mut count := 0
		for count < bytes.len {
			assert C.read(0, &bytes[count], 1) == 1
			if bytes[count] == `\n` { break }
			count++
		}
		assert unsafe { tos(&bytes[0], count) } == 'fixture secret é'
		for index in 0 .. bytes.len { bytes[index] = 0 }
		time.sleep(30 * time.millisecond)
		if args[4] == '/stale-policy' { eprintln('organization policy review is stale: configuration, installed state or proposed policy changed; review again'); exit(23) }
		assert args[4] == policy_fixture_path || args[4].len > 300
		document := pkgprotocol.PolicyDocument{ format: 1, architecture: 'aarch64', policy: fixture_policy_review().proposed }
		os.write_file(os.getenv('VINIX_SOFTWARE_POLICY_FIXTURE'), json2.encode(document))!
		println(json2.encode(document))
		return true
	}
	return false
}

fn check_software_policy() ! {
	receipt := os.temp_dir() + '/vinix-software-policy-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_POLICY_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_POLICY_FIXTURE') }
	mut app := SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	app.handle('software.deployment')!
	deployment := app.build(ui2.rect(0, 0, 640, 610))!
	assert deployment.children.any(it.id == 'software.policy')
	free_window_tree(deployment)
	app.handle('software.policy')!
	assert app.policy_mode && app.worker.args == ['policy'] && !app.admin_prompt && app.prepare_close()
	wait_for_software(mut app)
	assert app.policy_ready && app.policy_document.policy.allow_firmware && app.policy_pages.len >= 5
	check_software_policy_reader(mut app)!
	app.handle('software.policy.licenses')!
	assert app.policy_pages[app.policy_page].text.contains('Vendor')
	app.handle('software.policy.path')!; app.paste_input(policy_fixture_path)
	app.handle('software.policy.review')!
	assert app.worker.args == ['policy-review', policy_fixture_path] && app.prepare_close() && !app.admin_prompt
	wait_for_software(mut app)
	assert app.policy_review_ready && app.policy_snapshot.rows.len == 2 && app.policy_section == 5
	check_software_policy_reader(mut app)!
	assert app.policy_pages[app.policy_page].text.contains('company policy; $literal é.json')
	app.handle('software.policy.path')!; app.key_input('\x01'); app.paste_input('/changed')
	assert editor_bytes_text(app.policy_path) == policy_fixture_path && app.policy_pending == policy_fixture_path
	app.handle('software.policy.back')!; app.handle('software.policy.reload')!
	app.handle('software.confirm')!; app.handle('software.install')!
	assert app.policy_review_ready && app.worker == unsafe { nil } && app.policy_mode
	app.handle(packagecore.request_prefix + '{"id":"app"}')!
	assert app.launch_request == '' && app.worker == unsafe { nil }
	app.handle('software.policy.impacts')!
	assert app.policy_pages[app.policy_page].text.contains('ID: app')
	assert app.policy_pages.any(it.section == 6 && it.text.contains('Publisher key:'))
	assert app.policy_pages.any(it.section == 6 && it.text.contains('runtime: permissions'))
	app.handle('software.policy.permissions')!
	assert app.policy_pages[app.policy_page].title.contains('Previous')
	app.handle('software.policy.next')!
	assert app.policy_pages[app.policy_page].title.contains('Proposed') && app.policy_pages[app.policy_page].text.contains('No permissions')
	app.handle('software.policy.previous')!
	assert app.policy_pages[app.policy_page].title.contains('Previous')
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.policy.confirm') && !tree.children.any(it.id == 'software.policy.path')
	free_window_tree(tree)
	app.handle('software.policy.cancel')!
	assert !app.policy_review_ready && app.policy_pending == '' && app.status.contains('cancelled')
	app.handle('software.policy.review')!; wait_for_software(mut app)
	app.handle('software.policy.confirm')!
	assert app.admin_prompt && app.worker.args == ['admin', 'policy-apply', 'c'.repeat(64), policy_fixture_path]
	app.handle('software.admin.cancel')!
	assert app.worker == unsafe { nil } && !app.policy_review_ready && !os.exists(receipt)
	app.handle('software.policy.review')!; wait_for_software(mut app)
	app.handle('software.policy.confirm')!
	app.key_input('fixture secret é'); app.handle('software.admin.approve')!
	assert !app.admin_prompt && !app.prepare_close()
	app.handle('software.policy.back')!
	assert app.policy_mode && app.worker != unsafe { nil }
	wait_for_software(mut app)
	assert app.policy_ready && !app.policy_review_ready && !app.policy_document.policy.allow_firmware
	assert app.policy_document.policy.permissions.len == 0 && app.status.contains('policy saved')
	assert app.prepare_close()
	for path in ['/missing-policy', '/bad-policy', '/stale-policy'] {
		app.handle('software.policy.path')!; app.key_input('\x01'); app.paste_input(path)
		app.handle('software.policy.review')!; wait_for_software(mut app)
		if path == '/stale-policy' {
			assert app.policy_review_ready
			app.handle('software.policy.confirm')!; app.key_input('fixture secret é'); app.handle('software.admin.approve')!
			wait_for_software(mut app)
			assert app.status.contains('stale')
		} else { assert app.status.contains(if path == '/missing-policy' { 'unavailable' } else { 'incomplete policy review' }) }
		assert !app.policy_review_ready && app.policy_pending == ''
		if path == '/stale-policy' {
			assert !app.policy_ready && app.policy_pages.len == 0
			failed := app.build(ui2.rect(0, 0, 640, 610))!
			assert failed.children.any(it.id == 'software.policy.reload') && !failed.children.any(it.id == 'software.policy.confirm')
			free_window_tree(failed)
			app.handle('software.policy.reload')!; wait_for_software(mut app)
		}
	}
	app.handle('software.policy.path')!; app.key_input('\x01'); app.paste_input(policy_fixture_path)
	app.paste_input('\n'); app.paste_input('\xff'); app.paste_input('x'.repeat(4097))
	assert editor_bytes_text(app.policy_path) == policy_fixture_path
	app.key_input('\x01'); app.paste_input('/private/tmp/' + 'folder\\"/'.repeat(400) + 'policy.json')
	app.handle('software.policy.review')!; wait_for_software(mut app)
	assert app.policy_review_ready
	app.handle('software.policy.confirm')!
	assert app.worker == unsafe { nil } && !app.admin_prompt && app.status.contains('after encoding')
	app.handle('software.policy.cancel')!
	app.handle('software.policy.back')!
	assert !app.policy_mode && app.deployment_mode
	app.close_app()
	check_software_policy_long_disclosures()!
	println('Software organization policy: current restrictions, complete settings/impact paging, literal file review, frozen confirmation, administrator approval/cancel/wipe, stale/error refusal, reload and close guard passed')
}

fn check_software_policy_long_disclosures() ! {
	file := '/private/tmp/' + 'company é🚀'.repeat(80) + '; $literal.json'
	diagnostic := 'runtime: denied ' + 'long é🚀 reason '.repeat(170)
	mut rows := fixture_policy_review().rows
	rows[1] = pkgprotocol.PolicyImpact{ ...rows[1], diagnostic_before: diagnostic, diagnostic_after: diagnostic }
	text := json2.encode(pkgprotocol.PolicyReview{ ...fixture_policy_review(), rows: rows })
	mut app := SoftwareApp{ policy_mode: true, policy_ready: true, policy_review_ready: true,
		policy_pending: file.clone(), policy_snapshot: pkgprotocol.decode_policy_review(text)! }
	app.prepare_policy_pages(true)
	check_software_policy_reader(mut app)!
	mut shown := []u8{cap: file.len}
	for page in app.policy_pages {
		assert utf8.validate_str(page.text)
		for line in page.text.split('\n') {
			assert line.len <= 52
			if page.section == 5 {
				start := if line.starts_with('• ') { 4 } else { 2 }
				for index in start .. line.len { shown << line[index] }
			}
		}
	}
	assert shown == file.bytes() && app.policy_pages.filter(it.section == 5).len > 1
	assert app.policy_pages.filter(it.section == 6).len > 4
	app.close_app()
	unsafe { file.free(); diagnostic.free(); text.free(); (&array(&shown)).free() }
}

fn check_software_policy_reader(mut app SoftwareApp) ! {
	page := app.policy_page; section := app.policy_section; focused := app.focus; selection := app.select_all
	short_page := app.policy_compact_page
	path := editor_bytes_text(app.policy_path); pending := app.policy_pending; fingerprint := app.policy_snapshot.fingerprint
	status := app.status; reviewing := app.policy_review_ready; page_rows := app.page_rows; selected := app.selected
	storage := app.policy_compact_pages.data
	assert app.policy_compact_pages.len > app.policy_pages.len
	for canonical, full in app.policy_pages {
		mut bytes := []u8{cap: full.title.len + full.text.len}
		for short in app.policy_compact_pages {
			if short.source_page != canonical { continue }
			for byte in short.text { if byte != `\n` { bytes << byte } }
		}
		titled := full.title + full.text
		expected := titled.replace('\n', '')
		assert editor_bytes_text(bytes) == expected
		unsafe { bytes.free(); titled.free(); expected.free() }
	}
	home := app.build(ui2.rect(0, 0, 320, 240))!
	assert home.children.any(it.id == 'software.policy.read')
	assert home.children.any(it.id == if reviewing { 'software.policy.cancel' } else { 'software.policy.back' })
	free_window_tree(home)
	app.handle('software.policy.read')!; assert app.policy_reader_mode
	app.handle('software.policy.general')!
	for index, short in app.policy_compact_pages {
		canonical := app.policy_pages[short.source_page]
		if canonical.section != app.policy_section { app.key_input('\t'); assert app.policy_section == canonical.section }
		for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert app.policy_compact_mode && app.policy_compact_page == index && app.policy_page == short.source_page
			details_fixture_rendered_lines(&tree, short.text, 14, 118, int(size.width) - 28, 18, 12)
			for id in ['software.policy.reader.back', 'software.policy.previous', 'software.policy.next',
				'software.policy.section.previous', 'software.policy.section.next']! { assert tree.children.any(it.id == id) }
			assert tree.children.any(it.text == short.label) && tree.children.any(it.text == software_policy_reader_titles[canonical.section])
			assert !tree.children.any(it.id in ['software.policy.confirm', 'software.policy.cancel', 'software.policy.reload', 'software.failure'])
			for element in tree.children {
				assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
				assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
			}
			free_window_tree(tree)
		}
		if index % 3 == 0 { app.key_input('\x1b[C') }
		else if index % 3 == 1 { app.key_input('\x1b[6~') }
		else { app.handle('software.policy.next')! }
		next := if index + 1 < app.policy_compact_pages.len
			&& app.policy_pages[app.policy_compact_pages[index + 1].source_page].section == canonical.section { index + 1 } else { index }
		assert app.policy_compact_page == next
	}
	last_section := if reviewing { 6 } else { 4 }
	assert app.policy_section == last_section
	app.key_input('\t'); assert app.policy_section == last_section
	last := app.policy_compact_page
	app.key_input('\x1b[5~'); assert app.policy_compact_page == last - 1
	app.handle('software.policy.section.previous')!; assert app.policy_section == last_section - 1
	app.key_input('\x1b[Z'); assert app.policy_section == last_section - 2
	app.key_input('\x1b[A'); assert app.policy_section == last_section - 3
	app.key_input('\x1b[B'); assert app.policy_section == last_section - 2
	app.handle('software.policy.general')!
	app.key_input('\x1b[D'); assert app.policy_compact_page == 0
	app.key_input('\x1b[C'); app.key_input('\x1b[C')
	anchor := app.policy_compact_page; canonical := app.policy_page
	for size in [ui2.rect(0, 0, 900, 660), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 160, 240), ui2.rect(0, 0, 320, 240)]! {
		tree := app.build(size)!
		assert app.policy_compact_page == anchor && app.policy_page == canonical && app.policy_section == 0
		assert tree.children.any(it.id == 'software.policy.reader.back')
		if size.width < 180 || size.height < 220 {
			assert !tree.children.any(it.id == 'software.policy.next') && !tree.children.any(it.text_style.font_family == 'mono')
		} else if size.width >= 640 && size.height >= 610 {
			details_fixture_rendered_lines(&tree, app.policy_pages[canonical].text, 14, 174, int(size.width) - 28, 20, 52)
		}
		for element in tree.children {
			assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
			assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
		}
		free_window_tree(tree)
	}
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	app.key_input('\x1b[6~')
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	assert app.policy_compact_pages[app.policy_compact_page].source_page == app.policy_page
	if app.policy_page != canonical {
		assert app.policy_compact_page == 0 || app.policy_compact_pages[app.policy_compact_page - 1].source_page != app.policy_page
	}
	for action in ['software.policy.confirm', 'software.policy.cancel', 'software.policy.reload', 'software.policy.review',
		'software.policy.path', 'software.policy.back', 'software.install', 'software.row.0', 'software.failure',
		packagecore.request_prefix + '{"id":"editor"}'] { app.handle(action)! }
	app.key_input('typed'); app.key_input('\r'); app.key_input('\x01')
	app.paste_input('/changed'); app.paste_input('\x1b'); app.paste_input('\x1b[C')
	assert app.policy_reader_mode && app.policy_review_ready == reviewing && app.policy_snapshot.fingerprint == fingerprint
	assert editor_bytes_text(app.policy_path) == path && app.policy_pending == pending && app.status == status
	assert app.page_rows == page_rows && app.selected == selected && app.worker == unsafe { nil } && !app.admin_prompt
	assert app.policy_compact_pages.data == storage && !app.focus
	app.key_input('\x1b'); assert !app.policy_reader_mode && app.policy_review_ready == reviewing
	app.handle('software.policy.read')!; app.handle('software.policy.reader.back')!; assert !app.policy_reader_mode
	app.policy_page = page; app.policy_section = section; app.policy_compact_page = short_page
	app.focus = focused; app.select_all = selection
	println('Software policy reader: complete current/previous/proposed/source/impact titles and text, short UTF-8 pages, native lines, all-topic navigation, resize anchors, tiny Back and frozen modal state passed')
}

fn check_software_policy_memory() ! {
	$if !track_heap ? { return error('compile policy memory fixture with -d track_heap') }
	$if track_heap ? {
		mut policy := fixture_policy_document()
		mut owned_allowed := []string{cap: 32}
		for index in 0 .. 32 { owned_allowed << 'app-' + index.str() }
		owned_allowed.sort()
		unsafe { (&array(&policy.policy.allowed)).free() }
		policy = pkgprotocol.PolicyDocument{ ...policy, policy: pkgprotocol.PolicySettings{ ...policy.policy, allowed: owned_allowed } }
		text := json2.encode(policy)
		policy.close()
		review := json2.encode(fixture_policy_review())
		invalid := review.replace('"name":"Shared runtime"', '"name":"\\ud800"')
		long_path := '/private/tmp/' + 'long é'.repeat(100) + '; $literal.json'
		mut app := SoftwareApp{ policy_mode: true, administration_required: true, output: []u8{cap: 8192}, policy_path: long_path.bytes() }
		unsafe { app.output.flags |= .noslices; app.policy_path.flags |= .noslices }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.output.clear(); for byte in text { app.output << byte }
				app.load_policy_document()
				free_window_tree(app.build_policy(640, 610))
				app.policy_pending = long_path.clone()
				app.output.clear(); for byte in review { app.output << byte }
				app.load_policy_review()
				for action in ['software.policy.source', 'software.policy.general', 'software.policy.permissions', 'software.policy.impacts']! {
					app.handle_policy(action); free_window_tree(app.build_policy(640, 610))
				}
				app.handle_policy('software.policy.next'); app.handle_policy('software.policy.cancel')
				app.policy_pending = long_path.clone()
				app.output.clear(); for byte in invalid { app.output << byte }
				app.load_policy_review()
				assert !app.policy_review_ready
				app.clear_policy_review(); app.clear_policy_pages(); app.policy_document.close(); app.policy_ready = false
			}
			unsafe { app.status.free() }; app.status = ''
		}
		kept := C.vinix_heap_end()
		app.close_app()
		unsafe { text.free(); review.free(); invalid.free(); long_path.free() }
		assert kept == 0, 'policy workflow retained ${kept} bytes'
		println('Software organization policy: 1000 wide-document/valid-review/invalid-review/page/redraw/cancel/retire cycles retain zero tracked bytes')
	}
}
