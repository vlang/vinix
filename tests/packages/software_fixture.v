// SPDX-License-Identifier: GPL-2.0-or-later
// Compiled beside the actual Software app by distribution-check.v.
module main

import json2
import os
import ui2
import time
import desktop.packagecore
import tools.packages.pkgprotocol

struct Desktop {
	tz_offset_seconds i64
}

interface NativeApp {
mut:
	build(ui2.Rect) !ui2.Element
	handle(string) !
}

const console_filter_limit = 256
const body_text = u32(0x111111)
const body_panel = u32(0xeeeeee)
const settings_choice_bg = u32(0xccccff)
const app_surface = u32(0xffffff)
const workflow_owned_text_key = 'owned'

fn editor_bytes_text(bytes []u8) string { return unsafe { tos(bytes.data, bytes.len) } }

fn console_sanitize(text string) string { return text.clone() }

fn console_backspace(mut bytes []u8, selected bool) {
	if selected {
		bytes.clear()
	} else if bytes.len > 0 {
		bytes.delete_last()
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

fn fixture_review(operation string, names []string) pkgprotocol.Review {
	return pkgprotocol.Review{
		format: 1, operation: operation, names: names, architecture: 'aarch64', generation: 3,
		target_generation: if operation == 'rollback' { u64(2) } else { u64(0) },
		fingerprint: 'c'.repeat(64), requested: ['editor'], disk_needed: 4096, disk_available: 65536, disk_reserve: 1024,
		rows: [
			pkgprotocol.ReviewPackage{ id: 'editor', name: 'Editor', description: 'Write documents', version: '2.0.0', installed_version: '1.0.0', architecture: 'aarch64', kind: 'linux', runtime: 'runtime', repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT', permissions: ['files'], requested: true, action: 'update' },
			pkgprotocol.ReviewPackage{ id: 'runtime', name: 'Runtime', description: 'Required shared runtime', version: '2.0.0', installed_version: '1.0.0', architecture: 'aarch64', kind: 'runtime', repository: 'runtime-publisher', public_key: 'b'.repeat(64), license: 'Vendor-EULA', proprietary: true, firmware: true, permissions: ['network', 'process'], action: 'update' },
		]
	}
}

fn wait_for_software(mut app SoftwareApp) {
	for _ in 0 .. 500 {
		app.poll()
		if app.worker == unsafe { nil } { return }
		time.sleep(time.millisecond)
	}
	panic('Software fixture service did not finish')
}

fn check_package_review() {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192},
		rows: [SoftwareRow{ id: 'editor', requested: true, installed_version: '1.0.0' }] }
	app.selected = 0
	app.handle('software.install') or { panic(err) }
	assert app.worker_review && !app.review_ready
	assert app.prepare_close(), 'a read-only review is safe to close'
	pending := app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	assert !pending.children.any(it.id == 'software.confirm')
	app.handle('software.confirm') or { panic(err) }
	assert app.worker_review
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.rows.len == 2
	app.handle('software.row.1') or { panic(err) }
	assert app.review_selected == 1 && app.selected == 0
	tree := app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	assert tree.children.any(it.id == 'software.row.1' && it.text == 'update: Runtime')
	assert tree.children.any(it.text.contains('runtime-publisher'))
	assert tree.children.any(it.text.contains('Permissions: network, process'))
	assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)') && it.text.contains('firmware'))
	assert tree.children.any(it.text.contains('4 KiB needed') && it.text.contains('1 KiB reserved'))
	assert tree.children.any(it.id == 'software.confirm')
	assert !tree.children.any(it.id == 'software.install' || it.id == 'software.run')
	// Confirmation is tied to the returned intent, not the current list selection.
	app.selected = -1
	app.handle('software.confirm') or { panic(err) }
	assert !app.review_ready && app.worker != unsafe { nil }
	assert !app.prepare_close()
	wait_for_software(mut app)
	assert app.status.contains('stale') && app.review == ''
	assert app.review_snapshot.rows.len == 0
	// Each supported maintenance action goes through asynchronous plan review.
	for action in ['software.upgrade', 'software.rollback'] {
		app.handle(action) or { panic(err) }
		wait_for_software(mut app)
		assert app.review_ready
		app.handle('software.cancel') or { panic(err) }
		assert app.review_snapshot.rows.len == 0 && app.review_summary == ''
	}
	app.begin_review('install', ['broken'])
	wait_for_software(mut app)
	assert !app.review_ready && app.status.contains('dependency unavailable')
	app.begin_review('install', ['wrong-format'])
	wait_for_software(mut app)
	assert !app.review_ready && app.status.contains('Unsupported')
	app.begin_review('install', ['wrong-intent'])
	wait_for_software(mut app)
	assert !app.review_ready && app.status.contains('different package operation')
	// The preview list pages independently of the underlying catalog selection.
	a_snapshot := fixture_review('upgrade', [])
	mut rows := a_snapshot.rows.clone()
	for i in 0 .. 20 {
		rows << pkgprotocol.ReviewPackage{ ...a_snapshot.rows[1], id: 'z-runtime-' + i.str(), name: 'Additional runtime' }
	}
	app.review = 'upgrade'.clone()
	app.review_snapshot = json2.decode[pkgprotocol.Review](json2.encode(pkgprotocol.Review{ ...a_snapshot, rows: rows })) or { panic(err) }
	app.review_ready = true
	app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	app.handle('software.down') or { panic(err) }
	assert app.review_scroll > 0
	app.handle('software.row.0') or { panic(err) }
	assert app.review_selected == app.review_scroll
	app.handle('software.up') or { panic(err) }
	assert app.review_scroll == 0
	app.close_app()
}

fn main() {
	mut args := os.args.clone()
	if args.len > 1 && args[1] == '--progress' { args.delete(1) }
	// This same executable is a literal-argv service fixture for asynchronous
	// view/run transitions. It deliberately returns useful launch diagnostics.
	if args.len > 1 {
		if software_deployment_service_fixture(args) or { panic(err) } { return }
		if software_repository_service_fixture(args) or { panic(err) } { return }
		if args[1] == 'view' {
			println(json2.encode(SoftwareView{ format: 1, architecture: 'aarch64' }))
			return
		}
		if args[1] == 'run' {
			assert args[2..] == ['editor', '/private/tmp/document with spaces; \$literal.txt']
			eprintln('fixture: ordinary user session required')
			exit(19)
		}
		if args[1] == 'install' && args[2] == 'progress-app' {
			assert os.args[1] == '--progress'
			frame := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'download',
				package: 'progress-app', repository: 'trusted', path: 'bin/app', current: 128, total: 256 }) + '\n'
			print(frame[..7]); flush_stdout()
			time.sleep(20 * time.millisecond)
			print(frame[7..]); flush_stdout()
			time.sleep(200 * time.millisecond)
			eprintln('fixture: transfer interrupted; retained partial data for retry')
			exit(27)
		}
		if args[1] == 'review' {
			if args.len > 3 && args[3] == 'broken' { eprintln('fixture: dependency unavailable'); exit(17) }
			review := fixture_review(args[2], args[3..])
			println(json2.encode(if args.len > 3 && args[3] == 'wrong-format' {
				pkgprotocol.Review{ ...review, format: 2 }
			} else if args.len > 3 && args[3] == 'wrong-intent' {
				pkgprotocol.Review{ ...review, names: ['other'] }
			} else { review }))
			return
		}
		if args[1] == 'apply' {
			assert args[2..] == ['c'.repeat(64), 'install', 'editor']
			eprintln('fixture: package review is stale; review again')
			exit(23)
		}
		if args[1] == 'lease-hold' { time.sleep(200 * time.millisecond); return }
		panic('unexpected fixture service command')
	}
	mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
	view := SoftwareView{
		format:       1
		architecture: 'aarch64'
		launch_user: 'alex'
		rows:         [
			SoftwareRow{ id: 'editor', name: 'Editor', description: 'Write text documents', version: '2.0.0', installed_version: '1.0.0', requested: true, updatable: true, repository: 'trusted', public_key: 'a'.repeat(64), permissions: ['files'] },
			SoftwareRow{ id: 'browser', name: 'Browser', description: 'Browse websites', version: '1.0.0' },
			SoftwareRow{ id: 'runtime', name: 'Runtime', description: 'Shared runtime', installed_version: '1.0.0' },
			SoftwareRow{ id: 'blocked', name: 'Blocked', description: 'License required', version: '1.0.0', diagnostic: 'License acceptance required' },
		]
	}
	encoded := json2.encode(view)
	for byte in encoded { app.output << byte }
	app.load_view()
	// Reload frees the previous decoded permissions and transfers fresh rows.
	app.load_view()
	assert app.rows.len == 4
	assert app.matching.len == 4
	app.handle('software.installed') or { panic(err) }
	assert app.matching == [0, 2]
	app.handle('software.updates') or { panic(err) }
	assert app.matching == [0]
	app.handle('software.catalog') or { panic(err) }
	app.handle('software.search') or { panic(err) }
	app.key_input('websites')
	assert app.matching == [1]
	app.key_input('\x01')
	app.key_input('text')
	assert app.matching == [0]
	app.handle('software.row.0') or { panic(err) }
	assert app.selected == 0
	app.handle('software.install') or { panic(err) }
	assert app.review == 'upgrade'
	app.handle('software.cancel') or { panic(err) }
	assert app.review == ''
	app.selected = 2
	app.handle('software.remove') or { panic(err) }
	assert app.status.contains('dependency')
	app.selected = 3
	app.handle('software.install') or { panic(err) }
	assert app.review == ''
	assert app.status == 'License acceptance required'
	tail := software_output_tail('old progress\nolder progress\nnew progress\nchecksum mismatch\nretry from trusted repository\n'.bytes())
	assert !tail.contains('old progress')
	assert tail.contains('checksum mismatch')
	assert tail.ends_with('retry from trusted repository')
	app.selected = 0
	tree := app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	assert tree.children.any(it.id == 'software.search')
	assert tree.children.any(it.id == 'software.remove')
	assert tree.children.any(it.id == 'software.refresh')
	assert tree.children.any(it.id == 'software.run')
	assert tree.children.any(it.id == 'software.run' && it.text == 'Launch as alex')
	assert tree.children.any(it.id == 'software.run-terminal' && it.text == 'Launch in Terminal')
	app.handle('software.run-terminal') or { panic(err) }
	assert app.terminal_app != unsafe { nil } && app.terminal_app.argv == [app.service_path, 'run-terminal', 'editor']
	app.key_input('SELECT 42;\n')
	assert app.terminal_app.input == 'SELECT 42;\n'
	assert !app.prepare_close()
	app.handle('software.terminal-back') or { panic(err) }
	assert app.terminal_app != unsafe { nil }
	app.terminal_app.exited = true
	assert app.prepare_close()
	app.handle('software.terminal-back') or { panic(err) }
	assert app.terminal_app == unsafe { nil }
	wait_for_software(mut app)
	compact := app.build(ui2.rect(0, 0, 480, 300)) or { panic(err) }
	assert compact.children.len == 2
	assert !compact.children.any(it.id == 'software.install')
	app.worker = os.new_process(os.find_abs_path_of_executable('false') or { panic(err) })
	app.worker.set_args(['owned worker argument'.clone()])
	app.worker.wait()
	assert app.worker.code == 1
	assert !app.prepare_close()
	app.handle('software.run') or { panic(err) }
	assert app.launch_request == ''
	app.retire_worker()
	assert app.prepare_close()
	app.close_app()
	mut launched := SoftwareApp{ service_path: os.executable(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	launched.start(['view'], true)
	encoded_request := json2.encode(packagecore.Request{ id: 'editor', document: '/private/tmp/document with spaces; \$literal.txt' })
	launched.handle(packagecore.request_prefix + encoded_request) or { panic(err) }
	assert launched.launch_request.len > 0
	for _ in 0 .. 500 {
		launched.poll()
		if launched.worker == unsafe { nil } { break }
		time.sleep(time.millisecond)
	}
	assert launched.worker == unsafe { nil }
	assert launched.launch_request == ''
	assert launched.status.contains('ordinary user session required')
	assert launched.prepare_close()
	launched.launch_request = '{"id":"bad;command"}'.clone()
	launched.run_requested()
	assert launched.worker == unsafe { nil }
	assert launched.launch_request == ''
	assert launched.status.contains('invalid package launch request')
	launched.close_app()
	mut detached := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192} }
	detached.start(['lease-hold'], false)
	detached.worker_run = true
	pid := detached.worker.pid
	assert !detached.prepare_close()
	detached.close_app()
	assert C.kill(pid, 0) == 0, 'forced monitor retirement must retain the service lease holder'
	mut child_status := 0
	assert C.waitpid(pid, &child_status, 0) == pid
	check_package_review()
	check_resolved_updates() or { panic(err) }
	check_repository_management() or { panic(err) }
	check_software_progress() or { panic(err) }
	check_software_deployment() or { panic(err) }
	println('Software UI: catalog, package/trust review, literal confirmation, revocation, URL paging, diagnostics and close guard passed')
}

const deployment_fixture_path = '/private/tmp/deployment with spaces; \$literal.json'

fn software_deployment_service_fixture(args []string) !bool {
	if args[1] == 'deployment-review' {
		assert args.len == 3
		path := args[2]
		if path == '/missing.json' { eprintln('fixture: deployment file unavailable'); exit(18) }
		review := fixture_review('deploy', ['editor'])
		println(json2.encode(if path == '/wrong-format.json' {
			pkgprotocol.Review{ ...review, format: 2 }
		} else if path == '/wrong-operation.json' {
			pkgprotocol.Review{ ...review, operation: 'upgrade', names: [] }
		} else if path == '/empty.json' {
			pkgprotocol.Review{ ...review, names: [], requested: [], rows: [
				pkgprotocol.ReviewPackage{ ...review.rows[0], requested: false, action: 'remove' },
				pkgprotocol.ReviewPackage{ ...review.rows[1], action: 'remove' },
			] }
		} else { review }))
		return true
	}
	if args[1] == 'deployment-apply' {
		assert os.args[1] == '--progress', 'deployment transactions request live progress'
		assert args.len == 4 && args[2] == 'c'.repeat(64)
		if args[3] == '/stale.json' { eprintln('fixture: deployment review is stale; review again'); exit(23) }
		assert args[3] in [deployment_fixture_path, '/empty.json']
		os.write_file(os.getenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete' }))
		return true
	}
	return false
}

fn check_software_deployment() ! {
	receipt := os.temp_dir() + '/vinix-software-deployment-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	defer { app.close_app() }
	app.handle('software.deployment')!
	assert app.deployment_mode && app.worker == unsafe { nil }
	form := app.build(ui2.rect(0, 0, 640, 610))!
	assert form.children.any(it.id == 'software.deployment.review')
	assert form.children.any(it.text.contains('Empty deployments remove all packages'))
	app.handle('software.deployment.path')!
	app.paste_input('relative.json')
	app.handle('software.deployment.review')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute')
	app.key_input('\x01')
	app.paste_input(deployment_fixture_path)
	app.key_input('\x01')
	app.paste_input('/' + 'x'.repeat(4096))
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/two\nlines.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/invalid\xff.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/control\xc2\x85.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/部署/пакеты.json')
	assert editor_bytes_text(app.deployment_path) == '/部署/пакеты.json'
	app.key_input('\x01')
	app.paste_input(deployment_fixture_path)
	app.handle('software.deployment.review')!
	assert app.worker_review && !app.review_ready && app.prepare_close()
	app.handle('software.confirm')!
	assert !os.exists(receipt)
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.names == ['editor']
	assert app.review_snapshot.rows.len == 2 && app.status.contains(deployment_fixture_path)
	app.handle('software.row.1')!
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.text.contains('Permissions: network, process'))
	assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)'))
	assert tree.children.any(it.id == 'software.confirm')
	// A form edit cannot alter the reviewed literal argv. Normal typing is frozen.
	app.focus = true
	app.paste_input('/other.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	software_repository_text(mut app.deployment_path, '/other.json')
	app.handle('software.confirm')!
	assert !app.prepare_close() && app.deployment_pending == ''
	wait_for_software(mut app)
	assert json2.decode[[]string](os.read_file(receipt)!)! == ['c'.repeat(64), deployment_fixture_path]
	assert !app.deployment_mode && app.review == ''
	os.rm(receipt)!
	for path in ['/missing.json', '/wrong-format.json', '/wrong-operation.json', '/stale.json', '/empty.json'] {
		app.handle('software.deployment')!
		software_repository_text(mut app.deployment_path, path)
		app.handle('software.deployment.review')!
		wait_for_software(mut app)
		if path == '/missing.json' {
			assert !app.review_ready && app.status.contains('unavailable')
		} else if path == '/wrong-format.json' || path == '/wrong-operation.json' {
			assert !app.review_ready && app.review == '' && app.deployment_pending == ''
		} else if path == '/stale.json' {
			assert app.review_ready
			app.handle('software.confirm')!
			wait_for_software(mut app)
			assert app.deployment_mode && !app.review_ready && app.status.contains('stale')
		} else {
			assert app.review_ready && app.review_snapshot.requested.len == 0
			assert app.review_snapshot.rows.all(it.action == 'remove')
			app.handle('software.cancel')!
			assert !os.exists(receipt) && app.deployment_mode && app.deployment_pending == ''
			app.handle('software.deployment.review')!
			wait_for_software(mut app)
			app.handle('software.confirm')!
			wait_for_software(mut app)
			assert json2.decode[[]string](os.read_file(receipt)!)![1] == '/empty.json'
			os.rm(receipt)!
		}
		assert !os.exists(receipt)
	}
	app.handle('software.deployment')!
	app.handle('software.deployment.back')!
	assert !app.deployment_mode && app.worker == unsafe { nil }
	println('Software deployment: full closure, frozen literal path, empty removal, cancellation, bounds, stale/error diagnostics and close guard passed')
}

fn check_software_progress() ! {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	defer { app.close_app() }
	app.operation_output('\n\n')
	frame := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'download',
		package: 'app', path: 'bin/app', current: 64, total: 128 }) + '\n'
	for byte in frame {
		value := byte.ascii_str()
		app.operation_output(value)
		unsafe { value.free() }
	}
	assert app.progress_seen && app.progress_snapshot.current == 64 && app.output.len == 0
	assert app.status.contains('64 / 128 bytes')
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	bar := tree.children.filter(it.id == 'software.progress')[0]
	assert bar.accessibility_role == 'progressbar' && bar.children[0].frame.width == 436
	app.operation_output(pkgprotocol.progress_prefix + '{"format":2}\n')
	assert app.progress_snapshot.current == 64
	app.operation_output('x'.repeat(pkgprotocol.progress_limit + 32) + '\n')
	assert app.progress_pending.len == 0 && !app.progress_skip
	app.operation_output('checksum mismatch; retry from trusted repository')
	app.finish_operation_output()
	assert app.status.contains('checksum mismatch') && !app.status.contains(pkgprotocol.progress_prefix)
	// The real worker emits a fragmented frame before exiting with a diagnostic.
	app.start(['install', 'progress-app'], false)
	assert !app.prepare_close()
	for _ in 0 .. 500 {
		app.poll()
		if app.progress_seen { break }
		time.sleep(time.millisecond)
	}
	assert app.worker != unsafe { nil } && app.progress_snapshot.current == 128
	wait_for_software(mut app)
	assert app.status.contains('transfer interrupted') && app.status.contains('partial data')
	assert !app.status.contains(pkgprotocol.progress_prefix) && app.progress_snapshot.phase != 'complete'
	assert app.prepare_close()
	app.start(['view'], true)
	assert !app.progress_seen && app.progress_snapshot.phase == ''
	wait_for_software(mut app)
	println('Software progress: fragmented frames, bounded buffers, phase bar, diagnostics and worker retirement passed')
}

const repository_fixture_url = 'file:///private/tmp/repository with spaces; $literal'

fn repository_fixture_status() !pkgprotocol.RepositoryStatus {
	path := os.getenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE')
	if path != '' && os.exists(path) { return json2.decode[pkgprotocol.RepositoryStatus](os.read_file(path)!)! }
	return pkgprotocol.RepositoryStatus{ format: 1, architecture: 'aarch64',
		repositories: [pkgprotocol.Repository{ id: 'fixture', url: repository_fixture_url, public_key: 'a'.repeat(64) }],
		history: [pkgprotocol.RepositoryFloor{ id: 'fixture', public_key: 'a'.repeat(64), sequence: 7, index_sha256: 'c'.repeat(64) }] }
}

fn repository_fixture_review(operation string, id string, url string, key string) !pkgprotocol.RepositoryReview {
	status := repository_fixture_status()!
	previous := status.repositories.filter(it.id == id)
	old_url := if previous.len == 0 { '' } else { previous[0].url }
	old_key := if previous.len == 0 { '' } else { previous[0].public_key }
	return pkgprotocol.RepositoryReview{ format: 1, architecture: 'aarch64', operation: operation, id: id,
		url: if operation == 'enroll' { url } else { old_url },
		public_key: if operation == 'enroll' { key } else { old_key }, previous_url: old_url, previous_public_key: old_key,
		fingerprint: if id == 'stale' { 'e'.repeat(64) } else { 'd'.repeat(64) },
		index_sha256: if operation == 'enroll' { 'c'.repeat(64) } else { '' },
		sequence: if operation == 'enroll' { u64(7) } else { u64(0) },
		expires: if operation == 'enroll' { i64(2000000000) } else { i64(0) },
		package_count: if operation == 'enroll' { 3 } else { 0 } }
}

fn software_repository_service_fixture(args []string) !bool {
	if args[1] == '--json' {
		assert args[2..] == ['repo-list']
		println(json2.encode(repository_fixture_status()!))
		return true
	}
	if args[1] == 'repo-review' {
		operation := args[2]
		id := args[3]
		if id == 'bad-signature' { eprintln('fixture: repository signature verification failed'); exit(31) }
		review := repository_fixture_review(operation, id,
			if operation == 'enroll' { args[4] } else { '' },
			if operation == 'enroll' { args[5] } else { '' })!
		println(json2.encode(if id == 'wrong-format' {
			pkgprotocol.RepositoryReview{ ...review, format: 2 }
		} else if id == 'wrong-intent' { pkgprotocol.RepositoryReview{ ...review, id: 'other' } } else { review }))
		return true
	}
	if args[1] == 'repo-apply' {
		if args[2] == 'e'.repeat(64) { eprintln('fixture: repository review is stale; review again'); exit(32) }
		assert args[2] == 'd'.repeat(64)
		path := os.getenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE')
		assert path != ''
		current := repository_fixture_status()!
		operation := args[3]
		id := args[4]
		assert id == 'fixture'
		if operation == 'enroll' {
			assert args.len == 7 && args[5].starts_with(repository_fixture_url)
			assert args[6] == 'b'.repeat(64)
			next := pkgprotocol.RepositoryStatus{ ...current, repositories: [pkgprotocol.Repository{ id: id, url: args[5], public_key: args[6] }] }
			os.write_file(path, json2.encode(next))!
		} else {
			assert operation == 'revoke' && args.len == 5
			os.write_file(path, json2.encode(pkgprotocol.RepositoryStatus{ ...current, repositories: [] }))!
		}
		println('fixture: repository trust change saved')
		return true
	}
	if args[1] == 'update' {
		if repository_fixture_status()!.repositories.any(it.url.contains('refresh-fails')) {
			eprintln('fixture: catalog refresh failed: publisher unreachable')
			exit(33)
		}
		println('fixture: catalogs refreshed')
		return true
	}
	return false
}

fn check_repository_management() ! {
	path := os.temp_dir() + '/vinix-software-repositories-' + os.getpid().str()
	previous := os.getenv_opt('VINIX_SOFTWARE_REPOSITORY_FIXTURE')
	os.setenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE', path, true)
	defer {
		os.rm(path) or {}
		if value := previous { os.setenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE', value, true) } else { os.unsetenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE') }
	}
	mut app := SoftwareApp{ service_path: os.executable(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	app.handle('software.repositories')!
	assert app.worker_view && app.prepare_close()
	wait_for_software(mut app)
	assert app.repository_mode && app.repository_status.repositories.len == 1
	app.handle('software.row.0')!
	assert editor_bytes_text(app.repository_id) == 'fixture'
	assert editor_bytes_text(app.repository_url) == repository_fixture_url
	app.handle('software.repository.key')!
	app.key_input('\x01')
	app.paste_input('b'.repeat(64))
	app.paste_input('0')
	assert editor_bytes_text(app.repository_key) == 'b'.repeat(64) && app.status.contains('not truncated')
	app.key_input('\t')
	assert app.repository_focus == 1
	app.key_input('\x1b[Z')
	assert app.repository_focus == 3
	app.handle('software.repository.enroll')!
	assert app.worker_review && !app.repository_review_ready
	app.handle('software.repository.confirm')!
	assert app.worker_review
	wait_for_software(mut app)
	assert app.repository_review_ready && app.repository_review.public_key == 'b'.repeat(64)
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.id == 'software.repository.confirm')
	assert tree.children.any(it.text.contains('Previous key:') && it.text.contains('a'.repeat(64)))
	assert tree.children.any(it.text.contains('3 signed catalog entries'))
	assert !os.exists(path), 'review changed repository trust'
	// Confirmation uses the reviewed intent despite unrelated form-buffer edits.
	software_repository_text(mut app.repository_id, 'other')
	app.handle('software.repository.confirm')!
	assert !app.prepare_close()
	wait_for_software(mut app)
	assert repository_fixture_status()!.repositories[0].id == 'fixture'
	assert app.status.contains('trusted') && app.status.contains('refreshed')
	app.handle('software.row.0')!
	app.handle('software.repository.revoke')!
	wait_for_software(mut app)
	assert app.repository_review_ready && app.repository_review.operation == 'revoke'
	app.handle('software.repository.cancel')!
	assert repository_fixture_status()!.repositories.len == 1
	app.handle('software.repository.revoke')!
	wait_for_software(mut app)
	app.handle('software.repository.confirm')!
	wait_for_software(mut app)
	assert app.repository_status.repositories.len == 0 && app.status.contains('revoked')
	assert repository_fixture_status()!.history.len == 1
	// Invalid input, invalid response and changed intent never enable confirmation.
	for id in ['bad-signature', 'wrong-format', 'wrong-intent', 'stale'] {
		software_repository_text(mut app.repository_id, id)
		app.begin_repository_review('enroll')
		wait_for_software(mut app)
		if id == 'stale' {
			assert app.repository_review_ready
			app.handle('software.repository.confirm')!
			wait_for_software(mut app)
			assert app.status.contains('stale')
		} else {
			assert !app.repository_review_ready && app.repository_operation == ''
		}
		assert repository_fixture_status()!.repositories.len == 0
	}
	software_repository_text(mut app.repository_key, 'not a key')
	app.begin_repository_review('enroll')
	assert app.worker == unsafe { nil } && app.status.contains('publisher key')
	software_repository_text(mut app.repository_id, 'fixture')
	software_repository_text(mut app.repository_key, 'b'.repeat(64))
	software_repository_text(mut app.repository_url, repository_fixture_url + '/' + 'long-source-'.repeat(30) + '/refresh-fails')
	app.begin_repository_review('enroll')
	wait_for_software(mut app)
	assert app.repository_url_pages.len > 1
	assert !app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.repository.confirm')
	app.handle('software.repository.confirm')!
	assert app.worker == unsafe { nil }
	for app.repository_url_page + 1 < app.repository_url_pages.len { app.handle('software.repository.url-next')! }
	app.handle('software.repository.confirm')!
	wait_for_software(mut app)
	assert app.repository_status.repositories.len == 1
	assert app.status.contains('trust was saved') && app.status.contains('refresh failed')
	app.handle('software.repository.back')!
	wait_for_software(mut app)
	assert !app.repository_mode
	app.close_app()
}

fn check_resolved_updates() ! {
	mut app := SoftwareApp{ service_path: os.executable(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	view := SoftwareView{ format: 1, architecture: 'aarch64', rows: [
		SoftwareRow{ id: 'editor', name: 'Editor', kind: 'linux', version: '1.0.0', installed_version: '1.0.0', requested: true },
		SoftwareRow{ id: 'runtime', name: 'Explicit runtime', kind: 'runtime', version: '2.0.0', installed_version: '1.0.0', updatable: true, update_action: 'update' },
		SoftwareRow{ id: 'new-data', name: 'New data', kind: 'data', version: '1.0.0', updatable: true, update_action: 'install' },
		SoftwareRow{ id: 'old-data', name: 'Retired data', kind: 'data', version: '1.0.0', installed_version: '1.0.0', updatable: true, update_action: 'remove' },
		SoftwareRow{ id: 'unchanged-data', name: 'Retained dependency', kind: 'data', version: '1.0.0', installed_version: '1.0.0' },
	] }
	app.output << json2.encode(view).bytes()
	app.load_view()
	app.handle('software.updates')!
	assert app.matching == [1, 2, 3]
	for slot in 0 .. 3 {
		app.handle(software_row_actions[slot])!
		tree := app.build(ui2.rect(0, 0, 900, 660))!
		assert tree.children.any(it.id == 'software.install' && it.text == 'Review updates')
		assert !tree.children.any(it.id == 'software.run')
		if slot == 2 { assert tree.children.any(it.text.contains('Removed by Update all')) }
		app.handle('software.install')!
		assert app.worker_review && app.review == 'upgrade' && app.review_names.len == 0
		wait_for_software(mut app)
		assert app.review_ready && app.review_snapshot.operation == 'upgrade'
		app.handle('software.cancel')!
	}
	// Repairing an implicit dependency must not silently turn it into a root.
	app.selected = 4
	assert !app.build(ui2.rect(0, 0, 900, 660))!.children.any(it.id == 'software.install')
	app.handle('software.install')!
	assert app.review == '' && app.status.contains('complete application set')
	// A failed full plan is visible on reload and when selecting Updates.
	app.output.clear()
	app.output << json2.encode(SoftwareView{ ...view, update_error: 'runtime: permissions blocked by organization policy',
		rows: view.rows.map(SoftwareRow{ ...it, updatable: false, update_action: '' }) }).bytes()
	app.load_view()
	assert app.status.contains('Updates unavailable') && app.status.contains('permissions blocked')
	app.handle('software.updates')!
	assert app.matching.len == 0 && app.status.contains('permissions blocked')
	app.close_app()
}
