// SPDX-License-Identifier: GPL-2.0-or-later
// This payload is signed and executed only through the production launcher.
module main

import json2
import os
import time
import tools.packages.pkgcore

fn package_policy_probe() int {
	assert C.getuid() == 1000 && C.geteuid() == 1000
	assert C.getgroups(0, unsafe { nil }) == 0
	assert os.args.len in [4, 5]
	mode := os.args[2]
	version := os.args[3]
	if mode == 'network-denied' || mode == 'network-allowed' {
		fd := C.socket(C.AF_INET, C.SOCK_STREAM, 0)
		if mode == 'network-denied' { return 91 } // must be killed before returning
		assert fd >= 0
		C.close(fd)
		println('PACKAGE NETWORK permitted socket')
		return 0
	}
	if mode == 'fork-denied' {
		C.fork()
		return 92 // must be killed before returning
	}
	if mode == 'fork-allowed' {
		child := C.fork()
		assert child >= 0
		if child == 0 { C._exit(23) }
		mut status := i32(0)
		assert C.waitpid(child, &status, 0) == child
		assert status == 23 << 8
		println('PACKAGE PROCESS permitted fork and wait')
		return 0
	}
	assert read_text(version) == '1.0.0\n'
	data := os.getenv('HOME')
	assert data.ends_with('/.local/share/vinix-apps/' + if mode == 'hold' {
		'leased'
	} else {
		'restricted'
	})
	assert C.open(c'/home/alex/outside.txt', C.O_RDONLY) == -1
	assert C.errno == C.ENOENT
	assert C.open(c'/usr/bin/vinix-package', C.O_RDONLY) == -1
	assert C.errno == C.ENOENT
	assert C.open(&char(version.str), C.O_WRONLY) == -1
	assert C.errno == C.EACCES
	if mode == 'hold' {
		assert os.args.len == 5
		assert read_text(os.args[4]) == '1.0.0\n'
		assert C.open(&char(os.args[4].str), C.O_WRONLY) == -1
		assert C.errno == C.EACCES
		assert os.getenv('PATH') == os.dir(os.args[4]) + '/bin'
	}
	os.write_file(data + '/private.txt', 'private application data\n') or { return 93 }
	if mode == 'hold' {
		os.write_file(data + '/ready', 'lease held\n') or { return 94 }
		for _ in 0 .. 10_000 {
			if os.exists(data + '/release') {
				assert read_text(version) == '1.0.0\n'
				assert read_text(os.args[4]) == '1.0.0\n'
				println('PACKAGE LEASE old application and runtime remain readable after maintenance')
				return 37
			}
			time.sleep(10 * time.millisecond)
		}
		return 95
	}
	println('PACKAGE FILES private-data permitted outside-read payload-write refused')
	return 0
}

fn package_success(arguments []string) !string {
	result := run(['/usr/bin/vinix-package', ...arguments], '', none, none)
	if result.status != 0 {
		return error('${arguments.join(' ')}: ${result.status}: ${result.output}')
	}
	return result.output
}

fn policy_package(id string, mode string, permissions []string, architecture string) pkgcore.Package {
	return pkgcore.Package{
		id:           id
		version:      '1.0.0'
		architecture: architecture
		name:         id
		license:      'MIT'
		kind:         'native'
		entrypoint:   'bin/app'
		permissions:  permissions
		arguments:    ['package-policy-probe', mode, '@APP@/version.txt']
	}
}

fn qualify_package_enforcement(mut t Test) ! {
	config := json2.decode[pkgcore.Config](os.read_file('/tmp/package-enforcement-config.json')!)!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(config))!
	os.write_file('/tmp/package-source/version.txt', '1.0.0\n')!
	os.write_file('/home/alex/outside.txt', 'belongs to the user but is not granted\n')!
	os.chown('/home/alex/outside.txt', 1000, 1000)!
	os.chmod('/home/alex/outside.txt', 0o600)!
	packages := [
		policy_package('restricted', 'files', [], config.architecture),
		policy_package('no-network', 'network-denied', [], config.architecture),
		policy_package('network', 'network-allowed', ['network'], config.architecture),
		policy_package('no-fork', 'fork-denied', [], config.architecture),
		pkgcore.Package{
			...policy_package('leased', 'hold', [], config.architecture)
			runtime:      'fixture-runtime'
			dependencies: [pkgcore.Dependency{
				id:      'fixture-runtime'
				minimum: '1.0.0'
				before:  '3.0.0'
			}]
			arguments:    ['package-policy-probe', 'hold', '@APP@/version.txt', '@RUNTIME@/version.txt']
		},
		pkgcore.Package{
			id:           'fixture-runtime'
			version:      '1.0.0'
			architecture: config.architecture
			name:         'Fixture runtime'
			license:      'MIT'
			kind:         'runtime'
		},
		policy_package('process', 'fork-allowed', ['process'], config.architecture),
	]
	os.mkdir_all('/tmp/package-assets')!
	os.write_file('/tmp/package-assets/version.txt', '1.0.0\n')!
	for package in packages {
		os.write_file('/tmp/package-manifest.json', json2.encode(package))!
		source := if package.id == 'leased' { '/tmp/package-assets' } else { '/tmp/package-source' }
		pkgcore.pack('/tmp/package-manifest.json', source, '/tmp/package-repository')!
	}
	pkgcore.publish('/tmp/package-repository', 'fixture', '/tmp/package-publisher/package-signing-seed', 2, time.now().unix() + 3600)!
	package_success(['update'])!
	package_success(['install', 'restricted', 'no-network', 'network', 'no-fork', 'leased', 'process'])!
	assert package_success(['run', 'restricted'])!.contains('PACKAGE FILES')
	assert package_success(['run', 'network'])!.contains('PACKAGE NETWORK')
	assert package_success(['run', 'process'])!.contains('PACKAGE PROCESS')
	for id in ['no-network', 'no-fork'] {
		denied := run(['/usr/bin/vinix-package', 'run', id], '', none, none)
		assert denied.status == 134, '${id}: ${denied.status} ${denied.output}'
	}
	// Explicit documents need the files permission even when the user owns them.
	no_files := run(['/usr/bin/vinix-package', 'run', 'restricted', '/home/alex/outside.txt'], '', none, none)
	assert no_files.status != 0 && no_files.output.contains('file permission is not declared'), no_files.output
	before := pkgcore.read_state('/var/lib/vinix-packages', config.architecture)!
	generation := '/var/lib/vinix-packages/generations/' + before.generation.str()
	assert before.packages.any(it.package.id == 'fixture-runtime')
	assert 'fixture-runtime' !in before.requested
	// Both the application and its runtime are verified before executing code.
	for id in ['restricted', 'fixture-runtime'] {
		path := generation + '/apps/' + id + '/version.txt'
		os.write_file(path, 'tampered\n')!
		application := if id == 'restricted' { id } else { 'leased' }
		changed := run(['/usr/bin/vinix-package', 'run', application], '', none, none)
		assert changed.status != 0 && changed.output.contains('installed application payload changed'), changed.output
		os.write_file(path, '1.0.0\n')!
	}
	data := '/home/alex/.local/share/vinix-apps/leased'
	mut holding := os.new_process('/usr/bin/vinix-package')
	holding.set_args(['run', 'leased'])
	holding.set_redirect_stdio_merged()
	holding.run()
	defer {
		if holding.is_alive() {
			holding.signal_kill()
			holding.wait()
		}
		holding.close()
	}
	for _ in 0 .. 5000 {
		if os.exists(data + '/ready') { break }
		if !holding.is_alive() {
			return error('leased application failed: ${holding.stdout_slurp()}')
		}
		C.usleep(10_000)
	}
	assert os.exists(data + '/ready')
	// Two activations make its leased generation older than the rollback slot.
	os.write_file('/tmp/package-source/version.txt', '2.0.0\n')!
	os.write_file('/tmp/package-assets/version.txt', '2.0.0\n')!
	os.write_file('/tmp/package-manifest.json', json2.encode(pkgcore.Package{ ...packages[4], version: '2.0.0' }))!
	pkgcore.pack('/tmp/package-manifest.json', '/tmp/package-assets', '/tmp/package-repository')!
	os.write_file('/tmp/package-manifest.json', json2.encode(pkgcore.Package{ ...packages[5], version: '2.0.0' }))!
	pkgcore.pack('/tmp/package-manifest.json', '/tmp/package-source', '/tmp/package-repository')!
	pkgcore.publish('/tmp/package-repository', 'fixture', '/tmp/package-publisher/package-signing-seed', 3, time.now().unix() + 3600)!
	package_success(['update'])!
	package_success(['upgrade'])!
	upgraded := pkgcore.read_state('/var/lib/vinix-packages', config.architecture)!
	assert upgraded.packages.any(it.package.id == 'fixture-runtime' && it.package.version == '2.0.0')
	package_success(['remove', 'leased'])!
	removed := pkgcore.read_state('/var/lib/vinix-packages', config.architecture)!
	assert !removed.packages.any(it.package.id in ['leased', 'fixture-runtime'])
	package_success(['gc'])!
	assert os.is_file(generation + '/apps/leased/version.txt')
	assert read_text(generation + '/apps/leased/version.txt') == '1.0.0\n'
	assert read_text(generation + '/apps/fixture-runtime/version.txt') == '1.0.0\n'
	os.write_file(data + '/release', 'finish\n')!
	os.chown(data + '/release', 1000, 1000)!
	output := holding.stdout_slurp()
	holding.wait()
	assert holding.code == 37 && output.contains('PACKAGE LEASE'), '${holding.code}: ${output}'
	package_success(['gc'])!
	assert !os.exists(generation)
	assert os.is_file(data + '/private.txt')
	t.say('PACKAGE ENFORCEMENT permissions literal-documents payload-trust runtime-update-remove leased-gc PASS')
}
