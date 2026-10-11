// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

struct Reply {
	code int
	text string
}

fn command(binary string, arguments []string) !Reply {
	mut process := os.new_process(binary)
	process.set_args(arguments)
	process.set_redirect_stdio_merged()
	process.run()
	text := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return Reply{ code: code, text: text }
}

fn success(binary string, arguments []string) !string {
	result := command(binary, arguments)!
	if result.code != 0 { return error('CLI ${arguments.join(' ')} failed: ${result.text}') }
	return result.text
}

fn package_template(id string, version string) pkgcore.Package {
	return pkgcore.Package{
		id:           id
		version:      version
		architecture: 'aarch64'
		name:         id
		description:  'CLI distribution fixture'
		license:      'MIT'
		kind:         'native'
		entrypoint:   'bin/app'
	}
}

fn qualify(binary string) ! {
	work := os.temp_dir() + '/vinix-package-cli-' + os.getpid().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/payload/bin')!
	defer { os.rmdir_all(work) or {} }
	key := success(binary, ['keygen', work + '/seed'])!.trim_space()
	assert key.len == 64
	assert os.stat(work + '/seed')!.mode & 0o777 == 0o600
	root_args := ['--root', work + '/root']
	repository := work + '/repository'
	config := pkgcore.Config{ architecture: 'aarch64', repositories: [pkgcore.Repository{ id: 'fixture', url: 'file://' + repository, public_key: key }], policy: pkgcore.Policy{ reserve_bytes: 0 } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	for id in ['app', 'other'] {
		os.write_file(work + '/payload/bin/app', id + ' payload')!
		os.chmod(work + '/payload/bin/app', 0o755)!
		os.write_file(work + '/manifest.json', json2.encode(package_template(id, '1.0.0')))!
		success(binary, ['pack', work + '/manifest.json', work + '/payload', repository])!
	}
	success(binary, ['publish', repository, 'fixture', work + '/seed', '1',
		(time.now().unix() + 3600).str()])!
	success(binary, [...root_args, 'update'])!
	assert success(binary, [...root_args, 'search', 'distribution'])!.contains('app')
	assert command(binary, [...root_args, 'info', 'absent'])!.code != 0
	assert success(binary, [...root_args, 'plan', 'install', 'app'])!.contains('requested')
	success(binary, [...root_args, 'install', 'app'])!
	installed := json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!
	assert installed.generation == 1
	assert installed.packages[0].package.id == 'app'
	assert success(binary, [...root_args, 'view'])!.contains('installed_version')
	success(binary, [...root_args, 'verify'])!
	// A mirror is used by another completely clean installation, offline.
	success(binary, [...root_args, 'mirror', work + '/mirror', 'app'])!
	offline_root := work + '/offline'
	os.mkdir_all(offline_root + '/etc/vinix-packages')!
	offline := pkgcore.Config{ ...config, repositories: [pkgcore.Repository{ ...config.repositories[0], url: 'file://' + work + '/mirror/fixture' }], policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(offline_root + '/etc/vinix-packages/config.json', json2.encode(offline))!
	success(binary, ['--root', offline_root, 'update'])!
	success(binary, ['--root', offline_root, 'install', 'app'])!
	assert command(binary, ['--root', offline_root, 'install', 'other'])!.code != 0
	assert json2.decode[pkgcore.State](success(binary, ['--root', offline_root, 'status'])!)!.packages.len == 1
	// Deployment reconciles roots and rollback restores the previous set.
	os.write_file(work + '/deployment.json', '{"format":1,"architecture":"aarch64","packages":["other"]}')!
	success(binary, [...root_args, 'deploy', work + '/deployment.json'])!
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.requested == ['other']
	success(binary, [...root_args, 'rollback'])!
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.requested == ['app']
	// Acquisition fails after trust revocation, but uninstall remains usable.
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: 'aarch64' }))!
	assert command(binary, [...root_args, 'install', 'other'])!.code != 0
	assert success(binary, [...root_args, 'plan', 'remove', 'app'])!.contains('"requested":[]')
	success(binary, [...root_args, 'remove', 'app'])!
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.packages.len == 0
	success(binary, [...root_args, 'gc'])!
	println('Package CLI: publisher round-trip, clean offline install, missing payload diagnostics, deployment, rollback and revoked-publisher uninstall passed')
}

fn main() {
	if os.args.len != 2 {
		eprintln('usage: distribution-cli BINARY')
		exit(2)
	}
	qualify(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
