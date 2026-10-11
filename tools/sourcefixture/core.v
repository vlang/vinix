// SPDX-License-Identifier: GPL-2.0-or-later
module sourcefixture

import encoding.hex
import hostclipboard
import net
import net.http
import os
import packageserver
import sourcecommand
import stagehost
import tarcore
import tarstream
import time

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
fn C.shutdown(i32, i32) i32
fn C.link(&char, &char) i32

fn git(root string, args []string) ! {
	mut argv := ['git', '-C', root]; argv << args
	result := sourcecommand.capture(argv, os.environ(), 10, 1024 * 1024, unsafe { nil })!
	assert result.status == 0, result.stderr
}

pub fn setup(work string) ! {
	root, ui := work + '/source', work + '/ui2'
	for name in ['desktop/tools', 'desktop/translations', 'desktop/assets'] { os.mkdir_all(root + '/' + name)! }
	for name in ['ui', 'appkit', 'examples/calculator'] { os.mkdir_all(ui + '/' + name)! }
	os.write_file(root + '/desktop/main.v', '// Copyright (c) 2026 Test. All rights reserved.\n// Use of this source code is governed by a GPL v2 license\n// that can be found in the LICENSE file.\n\n// SPDX-License-Identifier: GPL-2.0-or-later\nmodule main\n')!
	os.write_file(root + '/desktop/local.v', 'module main\n')!
	os.write_file(root + '/desktop/translations/en.tr', 'app.files\nFiles\n')!
	os.write_file_array(root + '/desktop/assets/terminal.qoi', hex.decode('716f696600000001000000010400ff112233ff0000000000000001')!)!
	for name in ['stage_app', 'stage_ui2'] { os.write_file(root + '/desktop/tools/' + name, 'native test fixture\n')! }
	os.write_file(root + '/desktop/tools/ui2_headless_bounds.v', 'module ui2\n')!
	os.write_file(root + '/.gitignore', 'ignored.txt\nthird_party/\n')!
	os.write_file(root + '/ignored.txt', 'not shared\n')!
	os.write_file(root + '/hard-a', 'native hard-link payload')!
	assert C.link((root + '/hard-a').str, (root + '/hard-b').str) == 0
	os.symlink('desktop/local.v', root + '/host-link')!
	os.write_file(ui + '/v.mod', 'Module { name: "ui2", subdirs: ["ui", "appkit"] }\n')!
	os.write_file(ui + '/ui/ui.v', 'module ui2\nconst selected_ui2_source = true\n')!
	os.write_file(ui + '/ui/scratch_tmp.v', 'module ui2\n')!
	os.write_file(ui + '/examples/calculator/main.v', 'module main\n\nstruct CalculatorModel {}\n\nfn main() {}\n')!
	git(root, ['init', '-q'])!
	git(root, ['add', '.gitignore', 'desktop/main.v'])!
}

fn copy_sources(source string, destination string) ! {
	os.mkdir_all(destination)!
	for name in os.ls(source)! {
		if name.ends_with('_test.v') { continue }
		if os.is_dir(source + '/' + name) { continue }
		if name.ends_with('.v') || name.ends_with('.h') { os.cp(source + '/' + name, destination + '/' + name)! }
	}
}

pub fn install_stagers(destination string) ! {
	root := os.real_path(@DIR + '/../..')
	os.mkdir_all(destination + '/desktop/tools')!
	for name in ['stage_app', 'stage_app.v', 'stage_ui2', 'stage_ui2.v'] {
		os.cp(root + '/desktop/tools/' + name, destination + '/desktop/tools/' + name)!
		if !name.ends_with('.v') { os.chmod(destination + '/desktop/tools/' + name, 0o755)! }
	}
	copy_sources(root + '/desktop/tools/stagehost', destination + '/desktop/tools/stagehost')!
	for item in [['hosttest', 'tests/linuxkpi/hosttest'], ['fixturehost', 'tests/qemu-core/fixturehost'], ['policyhost', 'tests/host-policy/policyhost']] {
		copy_sources(root + '/' + item[1], destination + '/desktop/tools/' + item[0])!
	}
	os.mkdir_all(destination + '/build-support')!
	for name in ['run-v-tool.sh', 'find-v.sh'] { os.cp(root + '/build-support/' + name, destination + '/build-support/' + name)! }
}

fn archive(path string, entries map[string]string) !string {
	mut writer := tarcore.create_stream(path)!
	defer { writer.close() }
	for name, data in entries { writer.add(tarcore.Member{name: name, size: data.len}, data.bytes())! }
	writer.finish()!; writer.close_checked()!
	return os.read_file(path)!
}

fn contents(path string) !map[string]string {
	mut reader := tarstream.open_plain(path)!; defer { reader.close() }
	mut output := map[string]string{}
	for {
		member := reader.next() or { if err is tarstream.End { break }; return err }
		if member.regular() {
			mut data := []u8{len: int(member.size)}
			mut position := 0
			for position < data.len { mut part := unsafe { data[position..] }; position += reader.read(mut part)! }
			output[member.name] = data.bytestr()
		} else { output[member.name] = '' }
	}
	return output
}

fn put(base string, data string) !int { return http.fetch(method: .put, url: base + '/packages', data: data)!.status_code }
fn get(base string, path string, status int) !http.Response {
	response := http.get(base + path)!
	assert response.status_code == status, '${path}: ${response.status_code}: ' + response.body
	return response
}

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn staging(work string) ! {
	// Independent original pattern vectors cover UTF-8 byte offsets, Unicode
	// boundaries, greedy embedded arguments, manifest quotes and cut failures.
	assert stagehost.module_subdirs("αsubdirs: ['ignored'] subdirs: ['ui', \"appkit\"]")! == ['ui', 'appkit']
	assert stagehost.module_subdirs("subdirs: ['ui\" \"linux']")! == ['ui', 'linux']
	assert stagehost.filter_manifest_subdirs("subdirs: ['appkit', 'ui', 'linux']")! == "subdirs: ['ui', 'linux']"
	assert stagehost.strip_main('module main\nimport ui2\n\nconst x_vml_source = \$embed_file(\'a\').to_string()\nfn main() {}\n', 'fixture')!.ends_with('module main\nimport ui2 as _\n\n')
	for bad in ['module main\n', 'fn main() {}\nfn main() {}\n', 'fn main() {}\npub fn after() {}\n'] {
		if _ := stagehost.strip_main(bad, 'fixture') { return error('bad main accepted') }
	}
	retained := stagehost.strip_main('module main\nconst x中_vml_source = \$embed_file(\'a\').to_string()\nconst αx中_vml_source = 1\nconst use = x中_vml_source\nfn main() {}\n', 'fixture')!
	assert retained.contains('const x中_vml_source')
	unused := stagehost.strip_main('module main\nconst x中_vml_source = \$embed_file(\'a\').to_string()\nconst αx中_vml_source = 1\nfn main() {}\n', 'fixture')!
	assert !unused.contains('const x中_vml_source')
	stagehost.app_main([work + '/app', work + '/source/desktop', work + '/ui2/examples/calculator'])!
	assert os.is_link(work + '/app/local.v')
	assert !os.is_link(work + '/app/main.v')
	assert os.read_file(work + '/app/translations_data.v')!.contains("'Files',")
	assert os.read_file(work + '/app/app_icon_data.h')!.fields().join(' ').contains('0xff, 0x11, 0x22, 0x33, 0xff')
	os.write_file(work + '/ui2/examples/calculator/main.v', 'module main\n')!
	if _ := stagehost.stage_example(work + '/app', work + '/ui2/examples/calculator') { return error('invalid example accepted') }
	assert os.file_size(work + '/app/app_calculator.v') == 0
	os.write_file(work + '/ui2/examples/calculator/main.v', 'module main\n\nstruct CalculatorModel {}\n\nfn main() {}\n')!
	stagehost.ui_main([work + '/staged-ui', work + '/ui2', work + '/source/desktop/tools/ui2_headless_bounds.v'])!
	assert os.is_link(work + '/staged-ui/ui/ui.v')
	assert !os.exists(work + '/staged-ui/appkit')
	assert !os.exists(work + '/staged-ui/ui/scratch_tmp.v')
	assert os.is_file(work + '/staged-ui/ui/vinix_headless_backend.v')
}

fn text_clipboard(_server &packageserver.Server) !string { return 'Привет\t😀\r\nsecond line' }
fn failed_clipboard(_server &packageserver.Server) !string { return error('unavailable') }

pub fn child(mode string) {
	match mode {
		'valid' { print('Привет\t😀\nsecond line\n') }
		'invalid' { mut out := os.stdout(); out.write([u8(255)]) or { exit(1) } }
		'large' { print('a'.repeat(hostclipboard.maximum + 1)) }
		'timeout' { time.sleep(10 * time.second) }
		'exit' { exit(1) }
		'locale' { assert os.getenv('LANG') == 'en_US.UTF-8'; assert os.getenv('LC_ALL') == 'en_US.UTF-8'; print('locale') }
		else { exit(2) }
	}
}

pub fn clipboard() ! {
	assert hostclipboard.read_command([os.executable(), '--child', 'valid'], unsafe { nil })! == 'Привет\t😀\nsecond line\n'
	assert hostclipboard.read_command([os.executable(), '--child', 'locale'], unsafe { nil })! == 'locale'
	for mode in ['invalid', 'large', 'timeout', 'exit'] {
		if _ := hostclipboard.read_command([os.executable(), '--child', mode], unsafe { nil }) { return error('bad clipboard accepted: ' + mode) }
	}
	if _ := hostclipboard.read_command(['/no/such/clipboard'], unsafe { nil }) { return error('missing clipboard accepted') }
	work := packageserver.temporary()!; defer { os.rmdir_all(work) or {} }
	mut server := packageserver.start(packageserver.Config{store: work + '/store', port: 0, clipboard: true})!
	server.clipboard_reader = text_clipboard
	task := spawn server.serve()
	defer { server.stop(); task.wait() or { eprintln(err) } }
	base := 'http://127.0.0.1:${server.port}'
	get(base, '/health', 204)!
	response := get(base, '/clipboard', 200)!
	assert response.body == 'Привет\t😀\r\nsecond line'
	assert response.header.get(.cache_control) or { '' } == 'no-store'
	mut unavailable := packageserver.start(packageserver.Config{store: work + '/store', port: 0, clipboard: true})!
	unavailable.clipboard_reader = failed_clipboard
	bad_task := spawn unavailable.serve()
	defer { unavailable.stop(); bad_task.wait() or { eprintln(err) } }
	get('http://127.0.0.1:${unavailable.port}', '/clipboard', 503)!
	println('PASS native clipboard reads and loopback endpoint')
}

pub fn packages() ! {
	work := packageserver.temporary()!; defer { os.rmdir_all(work) or {} }
	setup(work)!; staging(work)!
	parsed := packageserver.parse(['--store', work + '/store', '--source-root', work + '/source', '--ui2-source', work + '/ui2', '--source-extra', '././/'])!
	assert parsed.extras == ['.']
	os.symlink(work + '/ui2', work + '/source/outside')!
	if _ := packageserver.parse(['--store', work + '/store', '--source-root', work + '/source', '--ui2-source', work + '/ui2', '--source-extra', 'outside']) { return error('escaping extra accepted') }
	config := packageserver.Config{store: work + '/store/packages.tar', port: 0, maximum: 1024 * 1024, source: work + '/source', ui2: work + '/ui2'}
	mut server := packageserver.start(config)!
	task := spawn server.serve()
	defer { server.stop(); task.wait() or { eprintln(err) } }
	base := 'http://127.0.0.1:${server.port}'
	get(base, '/health', 204)!; get(base, '/clipboard', 404)!
	first := archive(work + '/first.tar', {'usr/bin/gtk3-demo': 'one'})!
	second := archive(work + '/second.tar', {'etc/apk/world': 'gtk\n'})!
	assert put(base, first)! == 204; assert put(base, second)! == 204
	assert contents(config.store)! == {'etc/apk/world': 'gtk\n'}
	before := os.read_bytes(config.store)!
	for name in ['../escape', '/absolute', '././../escape'] {
		bad := archive(work + '/bad.tar', {name: 'bad'})!
		assert put(base, bad)! == 400
		assert os.read_bytes(config.store)! == before
	}
	assert put(base, 'not a tar')! == 400
	assert http.fetch(method: .put, url: base + '/packages', header: http.new_header_from_map({http.CommonHeader.content_length: '0'}))!.status_code == 413
	get(base, '/vinix-files/binary', 404)!
	for app, directory in {'vinix-files': 'files-live', 'vinix-activity': 'activity-live', 'vinix-settings': 'settings-live'} {
		path := config.source + '/build-aarch64-desktop-apps/' + directory
		os.mkdir_all(path)!
		os.write_file(path + '/' + app, app + ' executable')!; os.write_file(path + '/version', '123 17\n')!
		assert get(base, '/' + app + '/binary', 200)!.body == app + ' executable'
		assert get(base, '/' + app + '/version', 200)!.body == '123 17\n'
	}
	for path in ['/vinix-terminal/binary', '/vinix-files/vinix-files', '/vinix-files/binary/x'] { get(base, path, 404)! }
	// Repeated complete source snapshots must have stable bytes and be live.
	initial := get(base, '/vinix-source.tar', 200)!.body
	os.write_file(work + '/snapshot.tar', initial)!
	members := contents(work + '/snapshot.tar')!
	mut reader := tarstream.open_plain(work + '/snapshot.tar')!
	mut hard := false; mut link := false
	for {
		member := reader.next() or { if err is tarstream.End { break }; return err }
		if member.name == 'hard-b' { assert member.kind == `1` && member.linkname == 'hard-a'; hard = true }
		if member.name == 'host-link' { assert member.kind == `2` && member.linkname == 'desktop/local.v'; link = true }
	}
	reader.close()
	assert hard && link
	assert 'desktop/local.v' in members && 'ignored.txt' !in members
	assert members['.vinix-build/desktop/main.v'].contains('SPDX-License-Identifier') && !members['.vinix-build/desktop/main.v'].contains('All rights reserved.')
	assert members['.vinix-build/vmodules/ui2/ui/ui.v'].contains('selected_ui2_source = true')
	assert '.vinix-build/vmodules/ui2/ui/scratch_tmp.v' !in members
	assert members['.vinix-build/desktop/app_icon_data.h'].contains('vinix_app_icon_terminal')
	time.sleep(1100 * time.millisecond)
	assert get(base, '/vinix-source.tar', 200)!.body == initial
	os.write_file(config.ui2 + '/ui/ui.v', 'module ui2\nconst selected_ui2_source = false\n')!
	os.write_file(config.source + '/desktop/main.v', 'module main\n// changed after server start\n')!
	updated := get(base, '/vinix-source.tar', 200)!.body
	os.write_file(work + '/updated.tar', updated)!
	changed := contents(work + '/updated.tar')!
	assert changed['desktop/main.v'].contains('changed after server start')
	assert changed['.vinix-build/vmodules/ui2/ui/ui.v'].contains('selected_ui2_source = false')
	mut sparse := os.create(config.source + '/.initramfs-desktop.tar.abc123')!
	sparse.seek(65 * 1024 * 1024, .start)!; sparse.write([u8(0)])!; sparse.close()
	os.write_file(work + '/sparse.tar', get(base, '/vinix-source.tar', 200)!.body)!
	assert '.initramfs-desktop.tar.abc123' !in contents(work + '/sparse.tar')!
	// The upload EOF path retains the old file and removes its owned temp.
	mut conn := net.dial_tcp('127.0.0.1:${server.port}')!
	conn.write_string('PUT /packages HTTP/1.0\r\nContent-Length: 100\r\n\r\nshort')!
	assert C.shutdown(conn.sock.handle, 1) == 0
	mut reply := []u8{len: 4096}; count := conn.read(mut reply)!
	assert reply[..count].bytestr().contains('400 Bad Request')
	conn.close()!
	assert os.read_bytes(config.store)! == before
	time.sleep(150 * time.millisecond)
	assert os.ls(os.dir(config.store))! == ['packages.tar']
	baseline := fd_count()
	for _ in 0 .. 100 { assert put(base, second)! == 204; get(base, '/health', 204)! }
	time.sleep(200 * time.millisecond)
	assert fd_count() == baseline, '${baseline} -> ${fd_count()}'
	println('PASS 6 original package cases, native staging, short upload and 100 descriptor cycles')
}

pub fn cli(argv []string) int {
	guard := packageserver.own_service(); defer { guard.close() }
	if argv.len == 2 && argv[0] == '--install-fixture' { os.cp(os.executable(), argv[1]) or { return 1 }; os.chmod(argv[1], 0o700) or { return 1 }; return 0 }
	if argv.len == 2 && argv[0] == '--child' { child(argv[1]); return 0 }
	if argv == ['--setup'] { return 2 }
	if argv.len == 2 && argv[0] == '--setup' { setup(argv[1]) or { eprintln(err); return 1 }; return 0 }
	if argv.len == 2 && argv[0] == '--write-icon' { os.write_file_array(argv[1], hex.decode('716f696600000001000000010400ff112233ff0000000000000001') or { return 1 }) or { return 1 }; return 0 }
	if argv.len == 2 && argv[0] == '--install-stagers' { install_stagers(argv[1]) or { eprintln(err); return 1 }; return 0 }
	if argv.len == 2 && argv[0] == '--clipboard-server' {
		mut server := packageserver.start(packageserver.Config{store: argv[1] + '.store', ready: argv[1], port: 0, clipboard: true}) or { eprintln(err); return 1 }
		server.clipboard_reader = text_clipboard
		server.serve() or { eprintln(err); return 1 }; return 0
	}
	if argv != ['--clipboard-only'] { packages() or { eprintln(err); return 1 } }
	clipboard() or { eprintln(err); return 1 }
	return 0
}
