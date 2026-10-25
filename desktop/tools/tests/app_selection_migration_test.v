// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import desktop.packagecore
import desktop.sessioncore
import desktop.sessionipc

fn migration_root(name string) string {
	root := os.real_path(os.temp_dir()) + '/vinix-setup-migration-${os.getpid()}-${name}'
	os.mkdir_all(root + '/usr/share/vinix-packages') or { panic(err) }
	for part in ['', '/usr', '/usr/share', '/usr/share/vinix-packages']! { os.chmod(root + part, 0o755) or { panic(err) } }
	return root
}

fn migration_document(root string, explicit bool) string {
	path := root + '/usr/share/vinix-packages/applications.json'
	roots := if explicit { '"org.neovim.editor"' } else { '"other"' }
	os.write_file(path, '{"format":2,"architecture":"aarch64","packages":[${roots}],"locked":[{"id":"org.neovim.editor","version":"1.0.0","architecture":"aarch64","repository":"release","public_key":"' + 'a'.repeat(64) + '","minimum_sequence":1,"metadata_sha256":"' + 'b'.repeat(64) + '"}]}') or { panic(err) }
	os.chmod(path, 0o644) or { panic(err) }
	return path
}

fn migration_enqueue_spy() ! {
	mut log := os.open_append(os.getenv('VINIX_SETUP_REVIEW_LOG'))!
	defer { log.close() }
	log.writeln('readonly-release-review')!
}

fn migration_enqueue_refused() ! { return error('broker unavailable') }

fn migration_route(root string) FirstRunReleaseRoute {
	return FirstRunReleaseRoute{root: root, owner: u32(os.geteuid()), architecture: 'aarch64', enqueue: migration_enqueue_spy}
}

fn migration_install_refused(route FirstRunReleaseRoute) bool {
	first_run_install_vendor_with_release('neovim', route) or { return true }
	return false
}

fn migration_review_message() SessionMessage {
	mut message := SessionMessage{count: 1}
	message.fields[0] = sessioncore.text(first_run_release_review_action) or { panic(err) }
	return message
}

fn migration_review_refused(route FirstRunReleaseRoute) bool {
	admitted := first_run_release_review_requested(migration_review_message(), route) or { return true }
	return !admitted
}

fn test_signed_neovim_declaration_replaces_actual_legacy_acquisition_installed_or_not() {
	root := migration_root('acquire')
	defer { os.rmdir_all(root) or {} }
	tool_log := os.getenv('VINIX_SETUP_TOOL_LOG')
	review_log := root + '/reviews'
	os.write_file(tool_log, '')!; os.write_file(review_log, '')!
	os.setenv('VINIX_SETUP_REVIEW_LOG', review_log, true)
	route := migration_route(root)
	path := migration_document(root, true)
	for installed in [false, true]! {
		if installed { os.mkdir_all(root + '/usr/bin')!; os.write_file(root + '/usr/bin/nvim', 'untrusted executable')!; os.chmod(root + '/usr/bin/nvim', 0o755)! }
		first_run_install_vendor_with_release('neovim', route)!
		assert os.read_file(tool_log)! == ''
	}
	assert os.read_file(review_log)! == 'readonly-release-review\n'.repeat(2)
	// Without a declaration the existing pkg install remains intact, even if a
	// binary happens to be present. A dependency does not select this app.
	os.rm(path)!
	first_run_install_vendor_with_release('neovim', route)!
	assert os.read_file(tool_log)! == 'install|neovim\n'
	migration_document(root, false)
	first_run_install_vendor_with_release('neovim', route)!
	assert os.read_file(tool_log)! == 'install|neovim\n'.repeat(2)
	// Present broken declarations and failed review delivery never run pkg.
	migration_document(root, true)
	assert migration_install_refused(FirstRunReleaseRoute{...route, enqueue: migration_enqueue_refused})
	for invalid in ['', '{}', '{"format":2', '{"format":1,"architecture":"aarch64","packages":["org.neovim.editor"]}',
		os.read_file(path)!.replace('"architecture":"aarch64"', '"architecture":"x86_64"'),
		os.read_file(path)!.replace('"packages":["org.neovim.editor"]', '"packages":["org.neovim.editor","org.neovim.editor"]'),
		os.read_file(path)!.replace('"id":"org.neovim.editor"', '"id":"other"')] {
		os.write_file(path, invalid)!
		assert migration_install_refused(route)
		// Unrelated legacy choices still work when this mapped app refuses.
		first_run_install_vendor_with_release('mpv', route)!
	}
	assert os.read_file(tool_log)! == 'install|neovim\n'.repeat(2) + 'install|mpv\n'.repeat(7)
}

fn test_release_routing_refuses_aliases_unsafe_metadata_and_replacement() {
	root := migration_root('paths')
	defer { os.rmdir_all(root) or {} }
	route := migration_route(root)
	path := migration_document(root, true)
	os.write_file(os.getenv('VINIX_SETUP_TOOL_LOG'), '')!
	os.write_file(root + '/reviews', '')!; os.setenv('VINIX_SETUP_REVIEW_LOG', root + '/reviews', true)
	assert packagecore.release_requirement_at(root, route.owner, 'aarch64', 'org.neovim.editor')!
	assert migration_install_refused(FirstRunReleaseRoute{...route, owner: route.owner + 1})
	for target in [path, root + '/usr/share/vinix-packages', root + '/usr/share', root + '/usr', root] {
		os.chmod(target, 0o777)!
		assert migration_install_refused(route)
		assert migration_review_refused(route)
		os.chmod(target, if target == path { 0o644 } else { 0o755 })!
	}
	os.rename(path, path + '.real')!; os.symlink(path + '.real', path)!
	assert migration_install_refused(route)
	assert migration_review_refused(route)
	os.rm(path)!; os.rename(path + '.real', path)!
	os.rename(root + '/usr/share/vinix-packages', root + '/usr/share/real')!
	os.symlink('real', root + '/usr/share/vinix-packages')!
	assert migration_install_refused(route)
	assert migration_review_refused(route)
	os.rm(root + '/usr/share/vinix-packages')!; os.rename(root + '/usr/share/real', root + '/usr/share/vinix-packages')!
	// A request captured before publication cannot bypass the execution guard.
	os.rm(path)!
	request := root + '/pending-request'
	os.write_file(request, 'neovim mpv')!
	claimed := desktop_take_first_run_install_at(request, route)
	assert !os.exists(request)
	os.write_file(request, 'firefox neovim;evil')!
	assert claimed.contains('neovim|vscodium') && claimed.contains('--install-setup-app')
	assert claimed.contains('for app in neovim mpv;') && !claimed.contains('for app in firefox') && !claimed.contains('evil')
	migration_document(root, true)
	first_run_install_vendor_with_release('neovim', route)!
	assert os.read_file(os.getenv('VINIX_SETUP_TOOL_LOG'))! == ''
	// Replacement by an invalid declaration also refuses; replacement request
	// text cannot introduce unoffered names or undo the independent recheck.
	os.write_file(path + '.new', '{}')!; os.rename(path + '.new', path)!
	assert migration_install_refused(route)
	filtered := first_run_install_command_with_release('neovim mpv neovim;evil', route)
	assert filtered.contains('for app in mpv;') && !filtered.contains('neovim mpv') && !filtered.contains('evil')
}

fn test_stale_signed_request_queues_once_and_never_restores_mapped_pkg_on_delivery_failure() {
	root := migration_root('stale')
	defer { os.rmdir_all(root) or {} }
	migration_document(root, true)
	os.write_file(root + '/reviews', '')!; os.setenv('VINIX_SETUP_REVIEW_LOG', root + '/reviews', true)
	route := migration_route(root)
	assert first_run_install_command_with_release('neovim neovim unknown', route) == ''
	assert os.read_file(root + '/reviews')! == 'readonly-release-review\n'
	assert first_run_install_command_with_release('neovim', FirstRunReleaseRoute{...route, enqueue: migration_enqueue_refused}) == ''
	command := first_run_install_command_with_release('neovim mpv', route)
	assert command.contains('for app in mpv;')
}

fn test_release_review_action_uses_real_same_account_application_broker() {
	root := migration_root('broker')
	base := root + '/runtime'
	os.mkdir(base)!; os.chmod(base, 0o700)!
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	defer { os.unsetenv('VINIX_SESSION_RUNTIME'); os.rmdir_all(root) or {} }
	broker := sessionipc.session_start_broker_at(root, os.getenv('VINIX_SETUP_BROKER')) or { panic('broker launch failed') }
	defer {
		C.kill(broker, C.SIGKILL)
		mut status := 0
		C.waitpid(broker, &status, 0)
		sessionipc.session_close_control()
	}
	mut ready := false
	for _ in 0 .. 200 {
		if sessionipc.session_call_ok('ping', []) { ready = true; break }
		time.sleep(10 * time.millisecond)
	}
	assert ready && sessionipc.session_call_ok('attach', [])
	// Fork discards the compositor capability. The real public socket stamps
	// the same-account kernel PID; application cannot take/apply/approve.
	child := C.fork()
	if child == 0 {
		sessionipc.session_close_control()
		if sessionipc.session_call_ok('take', []) { C._exit(5) }
		first_run_enqueue_release_review() or { C._exit(6) }
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child && status == 0
	reply := sessionipc.session_call('take', [])!
	defer { unsafe { reply.free() } }
	fields := sessioncore.fields(reply)!
	assert fields.count == 3 && fields.values[0] == 'action' && fields.values[1] == child.str()
	assert sessioncore.unfield(fields.values[2])!.str() == first_run_release_review_action
	assert sessionipc.session_call('take', [])! == 'empty'
	// The global account filter also refuses root and another UID.
	for uid in [u32(0), u32(os.geteuid()) + 1]! {
		if uid == u32(os.geteuid()) { continue }
		if _ := sessioncore.authorize_session('action', 2,
			sessioncore.SessionCaller{pid: 123, uid: uid, session_uid: u32(os.geteuid())}, &sessioncore.Policy{}) {
			assert false, 'cross-account action admitted'
		}
	}
}
