// SPDX-License-Identifier: GPL-2.0-or-later
module main
import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn record(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	mut file := os.open_file(os.getenv('VINIX_VERIFY_EVENTS'), 'a', 0o600) or { panic(err) }
	file.writeln(json2.encode(event)) or { panic(err) }; file.close()
	root := os.getenv('VINIX_VERIFY_WRITER')
	if root != '' && event.phase == 'verify' && event.package != '' {
		if _ := (pkgcore.Service{ root: root }).transact('remove', ['app'], pkgcore.TransactionOptions{}) { panic('verification did not hold its reader lock') }
		else { assert err.msg().contains('transaction') }
		os.write_file(os.getenv('VINIX_VERIFY_LOCKED'), 'writer refused') or { panic(err) }
	}
}

fn frames(text string, framed bool) ![]pkgprotocol.Progress {
	mut result := []pkgprotocol.Progress{}
	for line in text.split_into_lines() {
		if framed {
			if !line.starts_with(pkgprotocol.progress_prefix) { continue }
			result << pkgprotocol.decode_progress(line[pkgprotocol.progress_prefix.len..])!
		} else { result << pkgprotocol.decode_progress(line)! }
	}
	return result
}

fn command(binary string, root string, args []string) (int, string) {
	mut p := os.new_process(binary); p.set_args(['--root', root, ...args]); p.set_redirect_stdio_merged(); p.run()
	text := p.stdout_slurp(); p.wait(); code := p.code; p.close(); return code, text
}

fn check() ! {
	if os.args.len !in [2, 3, 4] { return error('usage: verify-progress-check NEW_WORK [CLI | --before OLD_CLI]') }
	before := os.args.len == 4 && os.args[2] == '--before'
	if os.args.len == 4 && !before { return error('four arguments require --before') }
	binary := if before { os.real_path(os.args[3]) } else if os.args.len == 3 { os.real_path(os.args[2]) } else { '' }
	work := os.abs_path(os.args[1]); if os.exists(work) || os.is_link(work) { return error('qualification directory must be new') }
	root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	config := pkgcore.Config{ architecture: arch, repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }], policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	configuration := root + '/etc/vinix-packages/config.json'; os.write_file(configuration, json2.encode(config))!
	log := work + '/events'; os.write_file(log, '')!; os.setenv('VINIX_VERIFY_EVENTS', log, true)
	defer { os.unsetenv('VINIX_VERIFY_EVENTS'); os.unsetenv('VINIX_VERIFY_WRITER'); os.unsetenv('VINIX_VERIFY_LOCKED') }
	observed := pkgcore.Service{ root: root, progress: record }; setup := pkgcore.Service{ root: root }
	assert observed.verify()!.generation == 0 && !os.exists(pkgcore.state_directory(root))
	if !before { assert frames(os.read_file(log)!, false)!.map(it.phase) == ['verify', 'complete'] }
	for id in ['app', 'runtime', 'assets'] {
		source := work + '/source-' + id; os.mkdir_all(source + '/bin')!; os.write_file(source + '/bin/app', 'signed payload ' + id)!
		os.chmod(source + '/bin/app', if id == 'assets' { 0o644 } else { 0o755 })!
		p := pkgcore.Package{ id: id, name: id, version: '1.0.0', architecture: if id == 'assets' { 'all' } else { arch },
			kind: if id == 'app' { 'native' } else if id == 'runtime' { 'runtime' } else { 'data' }, license: 'MIT',
			entrypoint: if id == 'app' { 'bin/app' } else { '' }, dependencies: if id == 'app' { [pkgcore.Dependency{ id: 'runtime' }, pkgcore.Dependency{ id: 'assets' }] } else { []pkgcore.Dependency{} } }
		os.write_file(work + '/manifest.json', json2.encode(p))!; pkgcore.pack(work + '/manifest.json', source, work + '/repository')!
	}
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!; setup.refresh()!
	installed := setup.transact('install', ['app'], pkgcore.TransactionOptions{})!
	store := pkgcore.state_directory(root); state := os.read_file(store + '/current/state.json')!
	catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	os.write_file(log, '')!; assert observed.state()! == installed && os.read_file(log)! == ''
	os.write_file(log, '')!; assert observed.verify()! == installed
	if before {
		assert os.read_file(log)! == ''
		code, text := command(binary, root, ['--progress', 'verify'])
		assert code != 0 && text.contains('--progress supports') && !text.contains(pkgprotocol.progress_prefix)
		println('VERIFY PROGRESS BEFORE Service.verify emits no progress and the CLI refuses --progress verify')
		return
	}
	healthy := frames(os.read_file(log)!, false)!
	assert healthy.len == 6 && healthy.first().phase == 'verify' && healthy.last().phase == 'complete'
	assert healthy.any(it.package == 'app' && it.path == 'share/applications/vinix-app.desktop')
	assert healthy.filter(it.path == 'bin/app').map(it.package) == ['app', 'assets', 'runtime']
	os.setenv('VINIX_VERIFY_WRITER', root, true); os.setenv('VINIX_VERIFY_LOCKED', work + '/lock-observed', true)
	os.write_file(log, '')!; assert observed.verify()!.generation == 1
	assert os.read_file(work + '/lock-observed')! == 'writer refused'; os.unsetenv('VINIX_VERIFY_WRITER')
	if binary != '' {
		code, text := command(binary, root, ['--progress', 'verify']); assert code == 0
		cli_frames := frames(text, true)!; assert cli_frames == healthy && text.contains('Installed package files and launchers verified.')
		plain_code, plain := command(binary, root, ['verify']); assert plain_code == 0 && !plain.contains(pkgprotocol.progress_prefix)
		json_code, document := command(binary, root, ['--json', 'verify']); assert json_code == 0 && json2.decode[pkgcore.State](document)! == installed
		bad_code, rejected := command(binary, root, ['--json', '--progress', 'verify']); assert bad_code != 0 && !rejected.contains(pkgprotocol.progress_prefix)
		os.write_file(work + '/cli.txt', text + '\nLegacy text:\n' + plain + '\nJSON:\n' + document)!
	}
	app := store + '/current/apps/app/bin/app'; entry := store + '/current/share/applications/vinix-app.desktop'; entry_bytes := os.read_file(entry)!
	for fault in ['payload', 'mode', 'registration'] {
		if fault == 'payload' { os.write_file(app, 'x'.repeat(os.read_file(app)!.len))! }
		if fault == 'mode' { os.chmod(app, 0o644)! }
		if fault == 'registration' { os.rm(entry)! }
		os.write_file(log, '')!
		if _ := observed.verify() { assert false } else { assert err.msg().contains('verification failed') && err.msg().contains('Repair / install') }
		failed := frames(os.read_file(log)!, false)!; assert failed.len >= 2 && failed.all(it.phase == 'verify')
		if binary != '' {
			code, text := command(binary, root, ['--progress', 'verify']); assert code != 0 && text.contains('Repair / install')
			assert frames(text, true)!.all(it.phase != 'complete')
			json_code, document := command(binary, root, ['--json', 'verify']); assert json_code != 0 && !document.contains('"generation"')
		}
		assert os.read_file(store + '/current/state.json')! == state && os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
		os.write_file(app, os.read_file(work + '/source-app/bin/app')!)!; os.chmod(app, 0o755)!
		if fault == 'registration' { os.write_file(entry, entry_bytes)!; os.chmod(entry, 0o644)! }
	}
	// Integrity verification is independent of current catalog/trust/policy and
	// does not make an execution or repository-authentication claim.
	os.write_file(configuration, json2.encode(pkgcore.Config{ ...config, repositories: [], policy: pkgcore.Policy{ ...config.policy, allowed: ['other'] } }))!
	os.write_file(store + '/catalog.json', 'damaged catalog')!; os.write_file(store + '/trust-history.json', 'damaged history')!
	os.rename(work + '/repository', work + '/hidden-repository')!
	os.write_file(log, '')!; assert observed.verify()! == installed
	assert frames(os.read_file(log)!, false)!.last().phase == 'complete'
	assert os.read_file(store + '/catalog.json')! == 'damaged catalog' && os.read_file(store + '/trust-history.json')! == 'damaged history'
	assert os.read_file(store + '/current/state.json')! == state
	if binary != '' { code, text := command(binary, root, ['--progress', 'verify']); assert code == 0 && frames(text, true)!.last().phase == 'complete' }
	os.write_file(configuration, json2.encode(config))!; os.write_file(store + '/catalog.json', catalog)!; os.write_file(store + '/trust-history.json', history)!
	assert setup.state()!.generation == 1
	println('VERIFY PROGRESS signed service/CLI, read-only locking/state, compatible frames, legacy text/JSON, offline catalog independence and payload/mode/launcher failure recovery PASS')
}
fn main() { check() or { eprintln(err); exit(1) } }
