// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tests.packages.applefixture
import tools.packages.pkgcore

const apple_id = 'org.vinix.apple-probe'
const apple_runtime_id = 'org.vinix.apple-runtime-probe'

fn apple_pack(version string, runtime_version string, status u8) ! {
	os.mkdir_all('/tmp/apple-application/Example.app')!
	os.write_file_array('/tmp/apple-application/Example.app/Example', applefixture.framework_image(status))!
	os.write_file('/tmp/apple-application/Example.app/Info.plist', '<plist><dict><key>CFBundleIdentifier</key><string>' + apple_id + '</string></dict></plist>')!
	os.mkdir_all('/tmp/apple-runtime/bin')!
	for name in ['launcher', 'run-ios'] {
		os.cp('/usr/share/apple-fixtures/' + name, '/tmp/apple-runtime/bin/' + name)!
		os.chmod('/tmp/apple-runtime/bin/' + name, 0o755)!
	}
	for recipe in [
		pkgcore.Package{ id: apple_id, version: version, architecture: 'aarch64', name: 'Isolated Apple probe',
			license: 'GPL-2.0-or-later AND MIT', kind: 'apple', runtime: apple_runtime_id,
			entrypoint: 'bin/launcher', permissions: ['files'], associations: ['text/plain'],
			dependencies: [pkgcore.Dependency{ id: apple_runtime_id, minimum: '1.0.0', before: '2.0.0' }] },
		pkgcore.Package{ id: apple_runtime_id, version: runtime_version, architecture: 'aarch64', name: 'Explicit Apple probe runtime',
			license: 'GPL-2.0-or-later AND MIT', kind: 'runtime' },
	] {
		source := if recipe.kind == 'apple' { '/tmp/apple-application' } else { '/tmp/apple-runtime' }
		os.cp('/usr/share/apple-fixtures/COPYING', source + '/COPYING')!
		os.cp('/usr/share/apple-fixtures/v-LICENSE', source + '/v-LICENSE')!
		os.cp('/usr/share/apple-fixtures/musl-COPYRIGHT', source + '/musl-COPYRIGHT')!
		os.write_file('/tmp/apple-manifest.json', json2.encode(recipe))!
		pkgcore.pack('/tmp/apple-manifest.json', source, '/tmp/apple-repository')!
	}
}

fn apple_run(status int, count int, document string, sam bool) ! {
	mut command := ['/usr/bin/vinix-package', 'run', apple_id]
	if document != '' { command << document }
	if sam { command = ['/usr/sbin/vinix-session', 'run', '--isolated', 'sam', ...command] }
	result := run(command, '', none, none)
	assert result.status == status, result.output
	assert result.output.contains('PACKAGE APPLE CONTEXT ') && result.output.contains('counter=' + count.str() + ' PASS'), result.output
	assert result.output.contains('PACKAGE APPLE FRAMEWORK counter=' + count.str() + ' paths files keychain PASS'), result.output
	assert !result.output.contains('still owned at shutdown'), result.output
	print(result.output)
}

fn apple_storage(data string, uid u32) ! {
	keychain := data + '/Keychains/' + apple_id
	for path in [data + '/boundary-counter.txt', keychain + '/items', keychain + '/key', keychain + '/lock'] {
		assert owner_of(path) == uid && mode_of(path) == 0o600
	}
	for directory in [data, data + '/Keychains', keychain] { assert mode_of(directory) == 0o700 && owner_of(directory) == uid }
	for path in [data + '/Documents/framework.txt', data + '/tmp/framework.tmp'] {
		assert owner_of(path) == uid && os.read_file(path)! == 'Mach-O Foundation wrote this\n'
	}
	bytes := os.read_bytes(keychain + '/items')!
	assert bytes.len >= 72 && bytes[..8].bytestr() == 'VNXKCH01'
	assert !bytes.bytestr().contains('vinix-package-framework')
}

fn qualify_package_apple(mut t Test) ! {
	assert $if arm64 { true } $else { false }, 'the current iOS runtime executes only on AArch64'
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	os.mkdir_all('/tmp/apple-publisher', mode: 0o700)!
	key := pkgcore.keygen('/tmp/apple-publisher/seed')!
	apple_pack('1.0.0', '1.0.0', 23)!
	pkgcore.publish('/tmp/apple-repository', 'apple', '/tmp/apple-publisher/seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: 'aarch64', launch_user: 'alex',
		repositories: [pkgcore.Repository{ id: 'apple', url: 'file:///tmp/apple-repository', public_key: key }],
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['--offline', 'update'])!
	reviewed_package_operation('install', [apple_id])!
	document := '/home/alex/Apple document ; $literal.txt'
	os.write_file(document, 'literal Apple document\n')!
	os.chown(document, int(alex.uid), int(alex.gid))!; os.chmod(document, 0o600)!
	os.setenv('VINIX_IOS_DOCUMENTS', '/root/forged/Documents', true)
	os.setenv('VINIX_IOS_KEYCHAIN', '/root/forged/Keychains', true)
	apple_run(23, 1, document, false)!
	apple_run(23, 1, '', true)!
	data := '/home/alex/.local/share/vinix-apps/' + apple_id
	sam_data := '/home/sam/.local/share/vinix-apps/' + apple_id
	apple_storage(data, alex.uid)!; apple_storage(sam_data, sam.uid)!
	assert !os.exists('/root/forged') && !os.exists('/root/.local/share/vinix-apps/' + apple_id)
	denied := run(['/usr/sbin/vinix-session', 'run', '--isolated', 'sam', '/usr/bin/vinix-package', 'run', apple_id, document], '', none, none)
	assert denied.status != 0 && os.read_file(sam_data + '/boundary-counter.txt')! == '1'
	t.say('PACKAGE APPLE signed Mach-O execution ordinary identities private containers literal document ambient overrides PASS')
	// Signed runtime and app updates keep the same personal container. A
	// different Mach-O return proves the new image actually executes.
	apple_pack('1.1.0', '1.1.0', 24)!
	pkgcore.publish('/tmp/apple-repository', 'apple', '/tmp/apple-publisher/seed', 2, time.now().unix() + 3600)!
	package_success(['--offline', 'update'])!
	reviewed_package_operation('upgrade', [])!
	apple_run(24, 2, document, false)!
	reviewed_package_operation('rollback', [])!
	apple_run(23, 3, document, false)!
	// Payload tampering is refused before the launcher can update private data.
	state := pkgcore.read_state('/var/lib/vinix-packages', 'aarch64')!
	runner := '/var/lib/vinix-packages/generations/' + state.generation.str() + '/apps/' + apple_runtime_id + '/bin/run-ios'
	bytes := os.read_bytes(runner)!
	os.write_file(runner, 'tampered runtime')!
	bad := run(['/usr/bin/vinix-package', 'run', apple_id], '', none, none)
	assert bad.status != 0 && bad.output.contains('payload changed'), bad.output
	assert os.read_file(data + '/boundary-counter.txt')! == '3'
	os.write_file_array(runner, bytes)!; os.chmod(runner, 0o755)!
	reviewed_package_operation('remove', [apple_id])!
	assert pkgcore.read_state('/var/lib/vinix-packages', 'aarch64')!.packages.len == 0
	assert !os.exists('/var/lib/vinix-packages/current/share/applications/vinix-' + apple_id + '.desktop')
	assert os.read_file(data + '/boundary-counter.txt')! == '3'
	assert os.is_file(data + '/Keychains/' + apple_id + '/items')
	// Remove repository objects too: reinstall must use the verified cache.
	os.rmdir_all('/tmp/apple-repository/objects')!
	reviewed_package_operation('install', [apple_id])!
	apple_run(24, 4, document, false)!
	assert os.read_file(sam_data + '/boundary-counter.txt')! == '1'
	apple_storage(data, alex.uid)!; apple_storage(sam_data, sam.uid)!
	// A damaged credential store must fail closed, without overwriting or
	// resetting it. This last attempted launch advances only the boundary
	// counter; the credential counter has already proved persistence at four.
	items := data + '/Keychains/' + apple_id + '/items'
	original := os.read_bytes(items)!
	mut corrupt := original.clone(); corrupt[24] ^= 1
	os.write_file_array(items, corrupt)!
	broken := run(['/usr/bin/vinix-package', 'run', apple_id], '', none, none)
	assert broken.status >= 70 && broken.status < 255, broken.output
	assert !broken.output.contains('PACKAGE APPLE FRAMEWORK') && !broken.output.contains('V panic:'), broken.output
	assert !broken.output.contains('still owned at shutdown'), broken.output
	assert os.read_bytes(items)! == corrupt
	os.write_file_array(items, original)!
	t.say('PACKAGE APPLE Foundation home Documents temporary files keychain CRUD persistence entitlement damaged-store refusal PASS')
	t.say('PACKAGE APPLE reviewed update rollback runtime tamper refusal clean uninstall cached reinstall retained private data PASS')
}

fn scenario_packages_apple(mut t Test) { qualify_package_apple(mut t) or { t.check(false, err.msg()) } }
