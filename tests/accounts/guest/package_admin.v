// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import sessioncore
import authclient
import authproto
import tools.packages.pkgadmin
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn qualify_package_admin(mut t Test) ! {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	sessioncore.make_runtime_directory(alex)!
	sessioncore.make_runtime_directory(sam)!
	t.start_authd()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	resolver := run(['/sbin/init', 'package-resolver'], '', none, none)
	assert resolver.status == 0, resolver.output
	root := '/tmp/admin-payload'
	repository := '/tmp/admin-repository'
	os.mkdir_all(root + '/share')!
	os.write_file(root + '/share/fixture', 'signed administrator package data')!
	manifest := '/tmp/admin-manifest.json'
	os.write_file(manifest, json2.encode(pkgcore.Package{ id: 'admin-fixture', version: '1.0.0', architecture: 'all',
		name: 'Administrator fixture', description: 'Signed data only', license: 'MIT', kind: 'data' }))!
	pkgcore.pack(manifest, root, repository)!
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	key := pkgcore.keygen('/tmp/package-publisher/admin-seed')!
	pkgcore.publish(repository, 'admin-publisher', '/tmp/package-publisher/admin-seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture,
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['repo-enroll', 'admin-publisher', 'file://' + repository, key])!
	package_success(['update'])!
	service := pkgcore.Service{}
	mut review := service.review('install', ['admin-fixture'])!
	defer { review.close() }
	ordinary_review := run(['/usr/bin/vinix-package', 'review', 'install', 'admin-fixture'], '', db, alex)
	assert ordinary_review.status == 0, ordinary_review.output
	mut displayed := pkgprotocol.decode_review(ordinary_review.output.trim_space())!
	assert displayed.fingerprint == review.fingerprint && displayed.rows.len == review.rows.len
	displayed.close()
	command := ['/usr/bin/vinix-package', 'admin', '--progress', 'apply', review.fingerprint, 'install', 'admin-fixture']
	not_admin := run(command, sam_password + '\n', db, sam)
	assert not_admin.status != 0 && not_admin.output.contains('cannot approve'), not_admin.output
	wrong := run(command, 'wrong password\n', db, alex)
	assert wrong.status != 0 && service.state()!.generation == 0, wrong.output
	// A root listener planted in the caller's directory must not receive the
	// authorized stream: its kernel peer identity is not that ordinary caller.
	mut planted := pkgadmin.listen_private('/run/user/1000', 1000, 'd'.repeat(32))!
	peer_probe := run(['/sbin/init', 'package-admin-peer-probe', 'd'.repeat(32), review.fingerprint], '', db, alex)
	planted.close()
	assert peer_probe.status == 0 && service.state()!.generation == 0, peer_probe.output
	installed := run(command, alex_password + '\n', db, alex)
	assert installed.status == 0 && installed.output.contains(pkgprotocol.progress_prefix) && installed.output.contains('Activated package generation 1'), installed.output
	assert service.state()!.generation == 1 && owner_of('/var/lib/vinix-packages/current/state.json') == 0
	assert !installed.output.contains(alex_password) && !installed.output.contains('VINIX-PACKAGE-ADMIN ')
	stale := run(command, alex_password + '\n', db, alex)
	assert stale.status != 0 && stale.output.contains('stale') && service.state()!.generation == 1, stale.output
	for args in [['run', 'admin-fixture'], ['--root', '/tmp', 'update'], ['install', 'admin-fixture']] {
		refused := run(['/usr/bin/vinix-package', 'admin', ...args], alex_password + '\n', db, alex)
		assert refused.status != 0 && service.state()!.generation == 1, refused.output
	}
	assert os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	t.say('PACKAGE ADMIN ordinary-admin password-required peer-bound reviewed-install progress stale-refusal no-launch PASS')
	qualify_package_metadata(mut t, db, alex, sam)!
	qualify_package_policy_admin(mut t, db, alex, sam)!
	// Keep the adversarial metadata loop independent of PID 1's accumulated
	// graph/account mapping charge, using the same fresh-worker service model.
	index_schema := run(['/sbin/init', 'package-index-schema'], '', none, none)
	assert index_schema.status == 0, index_schema.output
	mut removal := service.review('remove', ['admin-fixture'])!
	defer { removal.close() }
	removed := run(['/usr/bin/vinix-package', 'admin', 'apply', removal.fingerprint, 'remove', 'admin-fixture'], alex_password + '\n', db, alex)
	assert removed.status == 0 && service.state()!.packages.len == 0, removed.output
	mut rollback := service.review('rollback', [])!
	defer { rollback.close() }
	restored := run(['/usr/bin/vinix-package', 'admin', 'apply', rollback.fingerprint, 'rollback'], alex_password + '\n', db, alex)
	assert restored.status == 0 && service.state()!.packages.len == 1, restored.output
	mut disconnected_review := service.review('remove', ['admin-fixture'])!
	defer { disconnected_review.close() }
	disconnected := run(['/sbin/init', 'package-admin-disconnect', disconnected_review.fingerprint], '', db, alex)
	assert disconnected.status == 0, disconnected.output
	mut completed := false
	// A detached worker can still be scheduled behind the authentication child
	// under TCG. Bound completion by 30 seconds without weakening state checks.
	for _ in 0 .. 600 {
		state := service.state() or { C.usleep(50_000); continue }
		if state.packages.len == 0 { completed = true; break }
		C.usleep(50_000)
	}
	if !completed {
		t.say('PACKAGE ADMIN disconnected-worker state: ' + json2.encode(service.state()!))
		for pid in os.ls('/proc')! {
			command_line := os.read_file('/proc/' + pid + '/cmdline') or { continue }
			if command_line.contains('vinix-package') {
				t.say('PACKAGE ADMIN disconnected-worker process: ' + pid + '\n' + (os.read_file('/proc/' + pid + '/status') or { '' }))
			}
		}
	}
	assert completed && service.verify()!.packages.len == 0
	mut revoke := pkgcore.review_repository('', 'revoke', pkgcore.Repository{ id: 'admin-publisher' }, false)!
	defer { revoke.close() }
	revoked := run(['/usr/bin/vinix-package', 'admin', 'repo-apply', revoke.fingerprint, 'revoke', 'admin-publisher'], alex_password + '\n', db, alex)
	assert revoked.status == 0 && pkgcore.load_config('')!.repositories.len == 0, revoked.output
	log := os.read_file('/var/log/vinix/auth.log')!
	assert log.contains('uid=1000 run packages-change as alex: exit 0') && !log.contains(alex_password)
	assert os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	t.say('PACKAGE ADMIN reviewed-remove rollback trust-revocation root-state audit no-password-log clean-runtime PASS')
}

fn package_admin_peer_probe(nonce string, fingerprint string) !int {
	request := pkgadmin.Request{ nonce: nonce, arguments: ['apply', fingerprint, 'install', 'admin-fixture'] }
	text := request.encode()!
	mut reply := authclient.ask(authclient.default_socket, authproto.op_run,
		pkgadmin.action.bytes(), alex_password.bytes(), text.bytes())!
	assert reply.code == authproto.status_failed && reply.text(1).contains('another account')
	return 0
}

fn package_admin_disconnect(fingerprint string) !int {
	request := pkgadmin.Request{ nonce: 'e'.repeat(32), arguments: ['--progress', 'apply', fingerprint, 'remove', 'admin-fixture'] }
	mut listener := pkgadmin.listen_private('/run/user/1000', 1000, request.nonce)!
	defer { listener.close() }
	text := request.encode()!
	mut reply := authclient.ask(authclient.default_socket, authproto.op_run,
		pkgadmin.action.bytes(), alex_password.bytes(), text.bytes())!
	assert reply.code == authproto.status_ok, reply.text(1)
	fd := listener.accept_root()!
	C.close(fd) // no output or completion read; the root transaction continues
	return 0
}

fn scenario_packages_admin(mut t Test) { qualify_package_admin(mut t) or { t.check(false, err.msg()) } }
