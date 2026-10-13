// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.appsdk
import tools.packages.pkgcore

fn package_context_probe() !int {
	assert C.getuid() == 1000 && C.geteuid() == 1000 && C.getgroups(0, unsafe { nil }) == 0
	mut context := appsdk.load() or { eprintln(err); return 89 }
	defer { context.close() }
	assert context.kind == 'native' && context.declares('files') && !context.declares('process')
	assert os.read_file(context.app_directory + '/version.txt')!.trim_space() == context.version
	if context.runtime_id != '' { assert os.read_file(context.runtime_directory + '/version.txt')!.trim_space() == context.runtime_version }
	if os.args.len == 2 || os.args[2] == 'check' { println(json2.encode(context)); return 0 }
	assert os.args[2] == 'hold'
	snapshot := json2.encode(context)
	os.write_file(context.data_directory + '/ready', snapshot)!
	for _ in 0 .. 5000 {
		if os.exists(context.data_directory + '/release') {
			mut reloaded := appsdk.load()!
			defer { reloaded.close() }
			assert reloaded == context
			assert os.read_file(context.app_directory + '/version.txt')!.trim_space() == context.version
			assert os.read_file(context.runtime_directory + '/version.txt')!.trim_space() == context.runtime_version
			os.write_file(context.data_directory + '/result', json2.encode(reloaded))!
			println('PACKAGE CONTEXT running snapshot survives upgrade/remove/gc')
			return 37
		}
		time.sleep(10 * time.millisecond)
	}
	return 90
}

fn context_package(id string, version string, runtime string) pkgcore.Package {
	return pkgcore.Package{ id: id, version: version, architecture: $if arm64 { 'aarch64' } $else { 'x86_64' },
		name: id, license: 'GPL-2.0-or-later AND MIT', kind: if id == 'sdk-runtime' { 'runtime' } else { 'native' },
		entrypoint: if id == 'sdk-runtime' { '' } else { 'bin/app' },
		runtime: runtime, permissions: if id == 'sdk-runtime' { []string{} } else { ['files'] },
		arguments: if id == 'sdk-runtime' { []string{} } else { ['package-context-probe'] },
		dependencies: if runtime == '' { []pkgcore.Dependency{} } else { [pkgcore.Dependency{ id: runtime }] } }
}

fn assert_package_context(id string, architecture string) ! {
	state := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	installed := state.packages.filter(it.package.id == id)[0]
	mut context := json2.decode[appsdk.Context](package_success(['run', id])!)!
	defer { context.close() }
	context.validate()!
	assert context.id == id && context.version == installed.package.version && context.generation == state.generation
	assert context.repository == installed.repository && context.public_key == installed.public_key && context.sequence == installed.sequence
	assert context.architecture == architecture && context.permissions == installed.package.permissions
	assert context.data_directory == '/home/alex/.local/share/vinix-apps/' + id
	if context.runtime_id != '' {
		assert context.runtime_id == installed.package.runtime
		assert context.runtime_version == state.packages.filter(it.package.id == context.runtime_id)[0].package.version
	}
}

fn qualify_package_context(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	os.mkdir_all('/tmp/context-source/bin')!
	os.cp('/sbin/init', '/tmp/context-source/bin/app')!
	os.chmod('/tmp/context-source/bin/app', 0o755)!
	os.mkdir_all('/tmp/context-assets')!
	key := package_success(['keygen', '/tmp/context-seed'])!.trim_space()
	version := '1.0.0'
	os.write_file('/tmp/context-source/version.txt', version + '\n')!
	os.write_file('/tmp/context-assets/version.txt', version + '\n')!
	for p in [context_package('sdk-native', version, ''), context_package('sdk-leased', version, 'sdk-runtime'), context_package('sdk-runtime', version, '')] {
		os.write_file('/tmp/context-manifest.json', json2.encode(p))!
		pkgcore.pack('/tmp/context-manifest.json', if p.id == 'sdk-leased' { '/tmp/context-assets' } else { '/tmp/context-source' }, '/tmp/context-repository')!
	}
	os.mkdir_all('/tmp/hello-source/bin')!
	os.cp('/usr/share/context-fixtures/package-hello', '/tmp/hello-source/bin/package-hello')!
	os.chmod('/tmp/hello-source/bin/package-hello', 0o755)!
	pkgcore.pack('/usr/share/context-fixtures/manifest.json', '/tmp/hello-source', '/tmp/context-repository')!
	pkgcore.publish('/tmp/context-repository', 'context-fixture', '/tmp/context-seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture, launch_user: 'alex',
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['--offline', 'repo-enroll', 'context-fixture', 'file:///tmp/context-repository', key])!
	package_success(['--offline', 'update'])!
	apps := ['sdk-native', 'sdk-leased', 'org.vinix.package-hello']
	reviewed_package_operation('install', apps)!
	os.setenv('VINIX_APP_ID', 'ambient-forgery', true)
	os.setenv('VINIX_APP_GENERATION', '999', true)
	assert_package_context('sdk-native', architecture)!
	assert_package_context('sdk-leased', architecture)!
	document := '/home/alex/a space; $literal.txt'
	os.write_file(document, 'SDK sample document\n')!; os.chown(document, 1000, 1000)!; os.chmod(document, 0o600)!
	hello := package_success(['run', 'org.vinix.package-hello', document])!
	assert hello.contains('Application: org.vinix.package-hello 1.0.0') && hello.contains('SDK sample document'), hello
	denied := run(['/usr/bin/vinix-package', 'run-args', 'org.vinix.package-hello', '--', document], '', none, none)
	assert denied.status != 0 && denied.output.contains('Cannot read supplied document'), denied.output
	t.say('PACKAGE CONTEXT native-sdk-example ordinary-identity explicit-document-grants installed-provenance ambient-forgery-refusal PASS')
	initial := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	leased := '/var/lib/vinix-packages/generations/' + initial.generation.str()
	data := '/home/alex/.local/share/vinix-apps/sdk-leased'
	mut holding := os.new_process('/usr/bin/vinix-package')
	holding.set_args(['run-args', 'sdk-leased', '--', 'hold'])
	holding.set_redirect_stdio_merged(); holding.run()
	defer { if holding.is_alive() { holding.signal_kill(); holding.wait() }; holding.close() }
	for _ in 0 .. 5000 {
		if os.exists(data + '/ready') { break }
		assert holding.is_alive(), holding.stdout_slurp()
		time.sleep(10 * time.millisecond)
	}
	assert os.exists(data + '/ready') && os.stat(data + '/ready')!.uid == 1000
	before := os.read_file(data + '/ready')!
	for p in [context_package('sdk-native', '2.0.0', ''), context_package('sdk-leased', '2.0.0', 'sdk-runtime'), context_package('sdk-runtime', '2.0.0', '')] {
		os.write_file('/tmp/context-source/version.txt', '2.0.0\n')!
		os.write_file('/tmp/context-assets/version.txt', '2.0.0\n')!
		os.write_file('/tmp/context-manifest.json', json2.encode(p))!
		pkgcore.pack('/tmp/context-manifest.json', if p.id == 'sdk-leased' { '/tmp/context-assets' } else { '/tmp/context-source' }, '/tmp/context-repository')!
	}
	pkgcore.publish('/tmp/context-repository', 'context-fixture', '/tmp/context-seed', 2, time.now().unix() + 3600)!
	package_success(['--offline', 'update'])!
	reviewed_package_operation('upgrade', [])!
	assert_package_context('sdk-native', architecture)!
	assert_package_context('sdk-leased', architecture)!
	reviewed_package_operation('rollback', [])!
	assert_package_context('sdk-native', architecture)!
	assert_package_context('sdk-leased', architecture)!
	reviewed_package_operation('upgrade', [])!
	reviewed_package_operation('remove', apps)!
	package_success(['gc'])!
	assert os.is_file(leased + '/apps/sdk-leased/version.txt') && os.is_file(leased + '/apps/sdk-runtime/version.txt')
	os.write_file(data + '/release', 'finish\n')!; os.chown(data + '/release', 1000, 1000)!
	output := holding.stdout_slurp(); holding.wait()
	assert holding.code == 37 && output.contains('PACKAGE CONTEXT running snapshot'), output
	assert os.read_file(data + '/result')! == before && os.stat(data + '/result')!.uid == 1000
	package_success(['gc'])!
	assert !os.exists(leased) && pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0
	t.say('PACKAGE CONTEXT new-launch-upgrade rollback old-snapshot-reload leased-runtime-uninstall-gc retained-user-data PASS')
}

fn scenario_packages_context(mut t Test) { qualify_package_context(mut t) or { t.check(false, err.msg()) } }
