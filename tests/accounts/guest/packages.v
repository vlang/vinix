// SPDX-License-Identifier: GPL-2.0-or-later
// The sandbox substitute observes credentials at the service's exec boundary.
// The real pledge/unveil enforcer has its own application-sandbox guest suite.
module main

import json2
import os
import tools.packages.pkgcore
import time

fn package_sandbox_handoff_probe() int {
	assert C.getuid() == 1000 && C.geteuid() == 1000 && C.getgid() == 1000
	assert C.getgroups(0, unsafe { nil }) == 0
	assert status_field('CapEff') == '0000000000000000'
	assert status_field('CapPrm') == '0000000000000000'
	assert status_field('CapBnd') == '0000000000000000'
	assert status_field('NoNewPrivs') == '1'
	assert os.getenv('HOME') == '/home/alex'
	assert read_text('/proc/self/loginuid').trim_space() == '1000'
	mut command := -1
	mut environment := []string{}
	for i in 1 .. os.args.len {
		if os.args[i] == '--env' { environment << os.args[i + 1] }
		if os.args[i] == '--' {
			command = i + 1
			break
		}
	}
	assert command > 0
	assert environment.contains('HOME=/home/alex/.local/share/vinix-apps/editor')
	mut argv := []&char{}
	for argument in os.args[command..] { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	mut envp := []&char{}
	for entry in environment { envp << &char(entry.str) }
	envp << &char(unsafe { nil })
	C.execve(argv[0], &argv[0], &envp[0])
	return 127
}

fn package_application_probe() int {
	assert os.args[2..] == ['/home/alex/Documents/a space; \$literal.txt']
	assert C.getuid() == 1000 && C.geteuid() == 1000
	assert C.getgroups(0, unsafe { nil }) == 0
	assert os.getenv('HOME') == '/home/alex/.local/share/vinix-apps/editor'
	assert os.getenv('VINIX_AUTH_UID') == ''
	assert read_text(os.args[2]) == 'document\n'
	os.write_file(os.getenv('HOME') + '/ran', 'ordinary account\n') or { return 89 }
	println('PACKAGE HANDOFF uid=1000 groups=0 nnp=1 literal-document')
	return 37
}

fn qualify_package_session(mut t Test, enforced bool) ! {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	assert alex.uid == 1000 && db.supplementary_gids(alex).len == 2
	os.mkdir_all('/tmp/package-source/bin')!
	os.mkdir_all('/etc/vinix-packages')!
	os.mkdir_all('/var/lib/vinix-packages')!
	os.cp('/sbin/init', '/tmp/package-source/bin/app')!
	os.chmod('/tmp/package-source/bin/app', 0o755)!
	if !enforced {
		os.cp('/sbin/init', '/usr/bin/vinix-sandbox')!
		os.chmod('/usr/bin/vinix-sandbox', 0o755)!
	}
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	public_key := pkgcore.keygen('/tmp/package-publisher/package-signing-seed')!
	package := pkgcore.Package{
		id:           'editor'
		version:      '1.0.0'
		architecture: architecture
		name:         'Session fixture'
		license:      'MIT'
		kind:         'native'
		entrypoint:   'bin/app'
		arguments:    ['package-probe']
		permissions:  ['files']
		associations: ['text/plain']
	}
	os.write_file('/tmp/package-manifest.json', json2.encode(package))!
	pkgcore.pack('/tmp/package-manifest.json', '/tmp/package-source', '/tmp/package-repository')!
	pkgcore.publish('/tmp/package-repository', 'fixture', '/tmp/package-publisher/package-signing-seed', 1, time.now().unix() + 3600)!
	config := pkgcore.Config{
		architecture: architecture
		launch_user:  'alex'
		repositories: [
			pkgcore.Repository{ id: 'fixture', url: 'file:///tmp/package-repository', public_key: public_key },
		]
		policy:       pkgcore.Policy{ reserve_bytes: 0 }
	}
	os.write_file('/etc/vinix-packages/config.json', json2.encode(config))!
	if enforced { os.write_file('/tmp/package-enforcement-config.json', json2.encode(config))! }
	for path in ['/etc/vinix-packages', '/var/lib/vinix-packages'] { os.chmod(path, 0o755)! }
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	document := '/home/alex/Documents/a space; \$literal.txt'
	os.write_file(document, 'document\n')!
	os.chown(document, int(alex.uid), int(alex.gid))!
	os.chmod(document, 0o600)!
	for args in [['update'], ['install', 'editor']] {
		reply := run(['/usr/bin/vinix-package', ...args], '', none, none)
		assert reply.status == 0, reply.output
	}
	launched := run(['/usr/bin/vinix-package', 'run', 'editor', document], '', none, none)
	assert launched.status == 37 && launched.output.contains('PACKAGE HANDOFF'), launched.output
	data := '/home/alex/.local/share/vinix-apps/editor'
	assert owner_of(data) == 1000 && mode_of(data) == 0o700
	assert owner_of(data + '/ran') == 1000
	assert read_text(data + '/ran') == 'ordinary account\n'
	// An ordinary caller keeps its own identity despite the desktop setting.
	// Sam cannot use it to read Alex's supplied document or write Alex's data.
	by_sam := run(['/usr/sbin/vinix-session', 'run', '--isolated', 'sam', '/usr/bin/vinix-package',
		'run', 'editor', document], '', none, none)
	assert by_sam.status != 0 && by_sam.output.contains('document must be an existing absolute regular file'), by_sam.output
	assert read_text(data + '/ran') == 'ordinary account\n'
	// Root's HOME never becomes package data; absent explicit identity fails.
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...config, launch_user: '' }))!
	missing := run(['/usr/bin/vinix-package', 'run', 'editor', document], '', none, none)
	assert missing.status != 0 && missing.output.contains('configure launch_user'), missing.output
	assert !os.exists('/root/.local/share/vinix-apps/editor')
	// The ordinary service rechecks trust rather than using root's earlier view.
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...config, repositories: [] }))!
	revoked := run(['/usr/bin/vinix-package', 'run', 'editor', document], '', none, none)
	assert revoked.status != 0 && revoked.output.contains('revoked'), revoked.output
	removed := run(['/usr/bin/vinix-package', 'remove', 'editor'], '', none, none)
	assert removed.status == 0, removed.output
	assert os.exists(data + '/ran')
	t.say('PACKAGE SESSION signed-install ordinary-identity private-data revocation uninstall PASS')
}

fn scenario_packages(mut t Test) {
	qualify_package_session(mut t, false) or { t.check(false, err.msg()) }
}

fn scenario_packages_enforced(mut t Test) {
	qualify_package_session(mut t, true) or { t.check(false, err.msg()) }
	qualify_package_enforcement(mut t) or { t.check(false, err.msg()) }
}
