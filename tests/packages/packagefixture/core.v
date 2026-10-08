// SPDX-License-Identifier: GPL-2.0-or-later
module packagefixture

import androidhost as ah

fn unit_call(unit string, name string, args []ah.Value) !string {
	return method(unit, name, args, {})!
}

fn unit_field(unit string, name string) !string { return attribute(unit, name)! }

fn write_text(path string, contents string) ! {
	method(path, 'write_text', [v(ah.Value(contents))], { 'encoding': v(ah.Value('utf-8')) })!
}

fn assert_equal(unit string, actual string, expected ah.Value) ! {
	unit_call(unit, 'assertEqual', [o(actual), expected])!
}

fn archive_body(archive string, entries string) ! {
	iter := iterator(method(entries, 'items', [], {})!)!
	for {
		row := next(iter)!
		if row.done { break }
		name := call('operator.getitem', o(row.value), v(ah.Value(0)))!
		contents := call('operator.getitem', o(row.value), v(ah.Value(1)))!
		info := call('tarfile.TarInfo', o(name))!
		set_attr(info, 'size', o(call('builtins.len', o(contents))!))!
		set_attr(info, 'mode', v(ah.Value(0o644)))!
		method(archive, 'addfile', [o(info), o(call('io.BytesIO', o(contents))!)], {})!
	}
}

fn build_archive(entries string) !string {
	output := call('io.BytesIO')!
	manager := invoke('tarfile.open', [], {
		'fileobj': o(output)
		'mode': v(ah.Value('w'))
		'format': o(call('tarfile.USTAR_FORMAT')!)
	})!
	entered := enter(manager)!
	mut retired := false
	archive_body(entered, entries) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	return method(output, 'getvalue', [], {})!
}

fn setup(unit string) ! {
	temporary := call('tempfile.TemporaryDirectory')!
	set_attr(unit, 'temporary', o(temporary))!
	root := call('Path', o(attribute(temporary, 'name')!))!
	for name in ['store', 'ready', 'source', 'ui2'] {
		child := match name { 'store' { 'packages.tar' } 'ready' { 'ready' } 'source' { 'source' } else { 'ui2-source' } }
		set_attr(unit, name, o(join(root, child)!))!
	}
	source := unit_field(unit, 'source')!
	ui2 := unit_field(unit, 'ui2')!
	method(join(source, 'desktop')!, 'mkdir', [], { 'parents': v(ah.Value(true)) })!
	write_text(join(source, 'desktop/main.v')!, '// Copyright (c) 2026 Test. All rights reserved.\n// Use of this source code is governed by a GPL v2 license\n// that can be found in the LICENSE file.\n\n// SPDX-License-Identifier: GPL-2.0-or-later\nmodule main\n')!
	write_text(join(source, 'desktop/local.v')!, 'module main\n')!
	method(join(source, 'desktop/translations')!, 'mkdir', [], {})!
	write_text(join(source, 'desktop/translations/en.tr')!, 'app.files\nFiles\n')!
	method(join(source, 'desktop/assets')!, 'mkdir', [], {})!
	method(join(source, 'desktop/assets/terminal.qoi')!, 'write_bytes', [b('716f696600000001000000010400ff112233ff0000000000000001')], {})!
	method(join(source, 'desktop/tools')!, 'mkdir', [], {})!
	repo := call('REPOSITORY')!
	for name in ['stage_app.py', 'stage_ui2.py', 'ui2_headless_bounds.v'] {
		call('shutil.copyfile', o(join(join(repo, 'desktop/tools')!, name)!), o(join(join(source, 'desktop/tools')!, name)!))!
	}
	for name in ['_stage_native.py', 'stage_query.v'] {
		call('shutil.copyfile', o(join(join(repo, 'desktop/tools')!, name)!), o(join(join(source, 'desktop/tools')!, name)!))!
	}
	call('shutil.copytree', o(join(repo, 'desktop/tools/stagehost')!), o(join(source, 'desktop/tools/stagehost')!))!
	method(join(source, 'build-support')!, 'mkdir', [], {})!
	for name in ['run-v-tool.sh', 'find-v.sh'] {
		call('shutil.copy2', o(join(join(repo, 'build-support')!, name)!), o(join(join(source, 'build-support')!, name)!))!
	}
	write_text(join(source, '.gitignore')!, 'ignored.txt\nthird_party/\n')!
	write_text(join(source, 'ignored.txt')!, 'not shared\n')!
	method(join(ui2, 'ui')!, 'mkdir', [], { 'parents': v(ah.Value(true)) })!
	method(join(ui2, 'examples/calculator')!, 'mkdir', [], { 'parents': v(ah.Value(true)) })!
	write_text(join(ui2, 'v.mod')!, 'Module { name: "ui2", subdirs: ["ui"] }\n')!
	write_text(join(ui2, 'ui/ui.v')!, 'module ui2\nconst selected_ui2_source = true\n')!
	write_text(join(ui2, 'examples/calculator/main.v')!, 'module main\n\nstruct CalculatorModel {}\n\nfn main() {}\n')!
	git_init := collection('list', [literal(ah.Value('git'))!, literal(ah.Value('init'))!, literal(ah.Value('-q'))!, call('builtins.str', o(source))!])!
	invoke('subprocess.run', [o(git_init)], { 'check': v(ah.Value(true)) })!
	git_add := collection('list', [literal(ah.Value('git'))!, literal(ah.Value('-C'))!, call('builtins.str', o(source))!, literal(ah.Value('add'))!, literal(ah.Value('.gitignore'))!, literal(ah.Value('desktop/main.v'))!])!
	invoke('subprocess.run', [o(git_add)], { 'check': v(ah.Value(true)) })!
	command := collection('list', [literal(ah.Value('python3'))!, call('builtins.str', o(call('SERVER')!))!, literal(ah.Value('--store'))!, call('builtins.str', o(unit_field(unit, 'store')!))!, literal(ah.Value('--port'))!, literal(ah.Value('0'))!, literal(ah.Value('--ready-file'))!, call('builtins.str', o(unit_field(unit, 'ready')!))!, literal(ah.Value('--max-bytes'))!, call('builtins.str', o(literal(ah.Value(1024 * 1024))!))!, literal(ah.Value('--source-root'))!, call('builtins.str', o(source))!, literal(ah.Value('--ui2-source'))!, call('builtins.str', o(ui2))!])!
	server := invoke('subprocess.Popen', [o(command)], {
		'stdout': o(call('subprocess.PIPE')!)
		'stderr': o(call('subprocess.STDOUT')!)
		'text': v(ah.Value(true))
	})!
	set_attr(unit, 'server', o(server))!
	ready := unit_field(unit, 'ready')!
	for _ in 0 .. 100 {
		if truth(method(ready, 'exists', [], {})!)! && truth(attribute(method(ready, 'stat', [], {})!, 'st_size')!)! { break }
		if !compare('is_', method(server, 'poll', [], {})!, null()!)! {
			unit_call(unit, 'fail', [o(method(attribute(server, 'stdout')!, 'read', [], {})!)])!
		}
		call('time.sleep', o(call('builtins.float', v(ah.Value('0.01')))!) )!
	}
	mut condition := method(ready, 'exists', [], {})!
	if truth(condition)! { condition = attribute(method(ready, 'stat', [], {})!, 'st_size')! }
	unit_call(unit, 'assertTrue', [o(condition)])!
	set_attr(unit, 'port', o(call('builtins.int', o(method(ready, 'read_text', [], {})!))!))!
}

fn teardown(unit string) ! {
	server := unit_field(unit, 'server')!
	method(server, 'terminate', [], {})!
	method(server, 'wait', [], { 'timeout': v(ah.Value(5)) })!
	method(attribute(server, 'stdout')!, 'close', [], {})!
	method(unit_field(unit, 'temporary')!, 'cleanup', [], {})!
}

fn address(unit string, path string) !string { return 'http://127.0.0.1:' + text(unit_field(unit, 'port')!)! + path }

fn response_body(response string, mode string) !string {
	return if mode == 'status' { attribute(response, 'status')! } else { method(response, 'read', [], {})! }
}

fn request_value(request string, mode string) !string {
	manager := call('urllib.request.urlopen', o(request))!
	entered := enter(manager)!
	value := response_body(entered, mode) or {
		failure := err
		if retire(manager, failure)! { return null()! }
		return failure
	}
	retire(manager, none)!
	return value
}

fn upload(unit string, body string) !string {
	request := invoke('urllib.request.Request', [v(ah.Value(address(unit, '/packages')!))], {
		'data': o(body)
		'method': v(ah.Value('PUT'))
	})!
	return request_value(request, 'status')!
}

fn snapshot_bytes(unit string) !string { return request_value(literal(ah.Value(address(unit, '/vinix-source.tar')!))!, 'read')! }

fn snapshot(unit string) !string {
	manager := call('urllib.request.urlopen', v(ah.Value(address(unit, '/vinix-source.tar')!)))!
	response := enter(manager)!
	value := invoke('tarfile.open', [], {
		'fileobj': o(call('io.BytesIO', o(method(response, 'read', [], {})!))!)
		'mode': v(ah.Value('r:'))
	}) or {
		failure := err
		if retire(manager, failure)! { return null()! }
		return failure
	}
	retire(manager, none)!
	return value
}

fn fetch(unit string, path string) !string { return request_value(literal(ah.Value(address(unit, text(path)!)!))!, 'read')! }

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	result := match ah.field(row, 'operation').text() {
		'fixture_archive' { build_archive(args[0])! }
		'fixture_setUp' { setup(args[0])!; null()! }
		'fixture_tearDown' { teardown(args[0])!; null()! }
		'fixture_upload' { upload(args[0], args[1])! }
		'fixture_source_snapshot' { snapshot(args[0])! }
		'fixture_source_snapshot_bytes' { snapshot_bytes(args[0])! }
		'fixture_fetch' { fetch(args[0], args[1])! }
		else { testcase(args[0], ah.field(row, 'operation').text().all_after('fixture_'))!; null()! }
	}
	return ah.Value(result)
}
