// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import desktop.packagecore
import desktop.sessioncore

// Explicit checks remain active with -prod; assertions are deliberately absent.
fn routing_check(ok bool, condition string) {
	if !ok { panic('release routing: ' + condition) }
}

fn routing_root(name string) string {
	root := os.real_path(os.temp_dir()) + '/vinix-release-routing-${os.getpid()}-${name}'
	os.mkdir_all(root + '/usr/share/vinix-packages') or { panic(err) }
	for part in ['', '/usr', '/usr/share', '/usr/share/vinix-packages']! {
		os.chmod(root + part, 0o755) or { panic(err) }
	}
	return root
}

fn routing_pin(id string, architecture string) string {
	// Structural routing fixtures confer no publisher trust. Software owns
	// signature, repository-policy and complete closure validation afterwards.
	return '{"id":"${id}","version":"1.0.0","architecture":"${architecture}","repository":"release","public_key":"' + 'a'.repeat(64) + '","minimum_sequence":1,"metadata_sha256":"' + 'b'.repeat(64) + '"}'
}

fn routing_document(architecture string, roots []string, pins []string) string {
	mut packages := []string{cap: roots.len}
	for id in roots { packages << '"${id}"' }
	return '{"format":2,"architecture":"${architecture}","packages":[' + packages.join(',') + '],"locked":[' + pins.join(',') + ']}'
}

fn routing_write(root string, text string) string {
	path := root + '/usr/share/vinix-packages/applications.json'
	os.write_file(path, text) or { panic(err) }
	os.chmod(path, 0o644) or { panic(err) }
	return path
}

fn routing_route(root string, architecture string) FirstRunReleaseRoute {
	return FirstRunReleaseRoute{root: root, owner: u32(os.geteuid()), architecture: architecture, enqueue: routing_delivery_refused}
}

fn routing_message() SessionMessage {
	mut message := SessionMessage{count: 1}
	message.fields[0] = sessioncore.text(first_run_release_review_action) or { panic(err) }
	return message
}

fn routing_refused(route FirstRunReleaseRoute) bool {
	admitted := first_run_release_review_requested(routing_message(), route) or { return true }
	return !admitted
}

fn routing_delivery_refused() ! { return error('recorded review delivery refusal') }

fn routing_install_refused(route FirstRunReleaseRoute) bool {
	first_run_install_vendor_with_release('neovim', route) or { return true }
	return false
}

fn test_release_routing_admits_each_selected_root_and_the_complete_mixed_set() {
	root := routing_root('roots')
	defer { os.rmdir_all(root) or {} }
	message := routing_message()
	for architecture in ['aarch64', 'x86_64']! {
		route := routing_route(root, architecture)
		for id in ['org.neovim.editor', 'org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']! {
			text := routing_document(architecture, [id], [routing_pin(id, architecture)])
			path := routing_write(root, text)
			routing_check(first_run_release_review_requested(message, route)!, 'explicit root admits on ' + architecture + ': ' + id)
			routing_check(packagecore.release_requirement_at(root, route.owner, architecture, id)!, 'named reader agrees')
			routing_check(first_run_signed_release_required('neovim', route)! == (id == 'org.neovim.editor'), 'legacy mapping remains specific')
			routing_check(!first_run_signed_release_required('mpv', route)!, 'no second legacy mapping')
			routing_check(os.read_file(path)! == text, 'admission preserves declaration')
		}
		text := routing_document(architecture, ['org.neovim.editor', 'org.vinix.counter'], [routing_pin('org.neovim.editor', architecture), routing_pin('org.vinix.counter', architecture)])
		path := routing_write(root, text)
		routing_check(first_run_release_review_requested(message, route)!, 'complete mixed roots admit on ' + architecture)
		routing_check(os.read_file(path)! == text, 'mixed admission preserves declaration')
	}
}

fn test_release_routing_refuses_missing_invalid_and_incompletely_locked_declarations() {
	root := routing_root('invalid')
	defer { os.rmdir_all(root) or {} }
	message := routing_message()
	for architecture in ['aarch64', 'x86_64']! {
		route := routing_route(root, architecture)
		path := root + '/usr/share/vinix-packages/applications.json'
		if os.exists(path) { os.rm(path)! }
		routing_check(!first_run_release_review_requested(message, route)!, 'missing declaration is not a release route')
		text := routing_document(architecture, ['org.neovim.editor'], [routing_pin('org.neovim.editor', architecture)])
		other := if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' }
		for invalid in ['', '{}', '{"format":2', text.replace('"format":2', '"format":1'),
			routing_document(architecture, [], []), text.replace(architecture, other),
			routing_document(architecture, ['bad/id'], [routing_pin('bad/id', architecture)]),
			routing_document(architecture, ['org.neovim.editor', 'org.neovim.editor'], [routing_pin('org.neovim.editor', architecture)]),
			routing_document(architecture, ['org.neovim.editor', 'org.vinix.counter'], [routing_pin('org.neovim.editor', architecture)]),
			routing_document(architecture, ['org.neovim.editor'], [routing_pin('other', architecture)])] {
			routing_write(root, invalid)
			routing_check(routing_refused(route), 'invalid or missing root pin refuses on ' + architecture)
			routing_check(os.read_file(path)! == invalid, 'refusal preserves declaration')
		}
		routing_write(root, text)
		routing_check(routing_refused(FirstRunReleaseRoute{...route, architecture: 'other'}), 'unsupported target refuses')
		routing_check(routing_refused(FirstRunReleaseRoute{...route, owner: route.owner + 1}), 'unexpected owner refuses')
		routing_check(first_run_release_review_requested(message, route)!, 'valid replacement recovers')
	}
}

fn test_release_routing_action_has_no_caller_controlled_operands_or_apply_permission() {
	root := routing_root('action')
	defer { os.rmdir_all(root) or {} }
	// Rejected messages must return false before even opening an invalid root.
	unavailable := routing_route(root + '/absent', 'aarch64')
	routing_check(!first_run_release_review_requested(SessionMessage{}, unavailable)!, 'empty action refuses')
	mut message := routing_message()
	message.count = 2
	message.fields[1] = sessioncore.text('/caller/selected.json')!
	routing_check(!first_run_release_review_requested(message, unavailable)!, 'caller declaration operand refuses')
	message.count = 1
	message.fields[0] = sessioncore.text('software.apply')!
	routing_check(!first_run_release_review_requested(message, unavailable)!, 'apply action cannot open review')
	message.fields[0] = sessioncore.text(first_run_release_review_action)!
	routing_check(routing_refused(unavailable), 'exact action checks the protected declaration')
}

fn test_release_routing_rejects_writable_components_and_file_or_directory_aliases() {
	root := routing_root('paths')
	defer { os.rmdir_all(root) or {} }
	route := routing_route(root, 'aarch64')
	text := routing_document('aarch64', ['org.vinix.counter'], [routing_pin('org.vinix.counter', 'aarch64')])
	path := routing_write(root, text)
	for target in [path, root + '/usr/share/vinix-packages', root + '/usr/share', root + '/usr', root] {
		os.chmod(target, 0o777)!
		routing_check(routing_refused(route), 'writable component refuses: ' + target)
		os.chmod(target, if target == path { 0o644 } else { 0o755 })!
	}
	os.rename(path, path + '.real')!
	os.symlink(path + '.real', path)!
	routing_check(routing_refused(route), 'file symlink refuses')
	os.rm(path)!
	os.rename(path + '.real', path)!
	os.rename(root + '/usr/share/vinix-packages', root + '/usr/share/real')!
	os.symlink('real', root + '/usr/share/vinix-packages')!
	routing_check(routing_refused(route), 'directory symlink refuses')
	os.rm(root + '/usr/share/vinix-packages')!
	os.rename(root + '/usr/share/real', root + '/usr/share/vinix-packages')!
	routing_check(first_run_release_review_requested(routing_message(), route)!, 'safe components recover')
	routing_check(os.read_file(path)! == text, 'path refusals preserve declaration')
}

fn test_release_routing_admission_does_not_deliver_or_restore_legacy_fallback() {
	root := routing_root('delivery')
	defer { os.rmdir_all(root) or {} }
	tool_log := os.getenv('VINIX_SETUP_TOOL_LOG')
	os.write_file(tool_log, '')!
	for architecture in ['aarch64', 'x86_64']! {
		route := routing_route(root, architecture)
		text := routing_document(architecture, ['org.neovim.editor'], [routing_pin('org.neovim.editor', architecture)])
		path := routing_write(root, text)
		// Even a failing enqueue cannot affect read-only admission. The mapped
		// installer separately refuses failed delivery without executing pkg.
		routing_check(first_run_release_review_requested(routing_message(), route)!, 'admission is read only')
		routing_check(routing_install_refused(route), 'failed delivery refuses explicit Neovim acquisition')
		routing_check(first_run_install_command_with_release('neovim neovim', route) == '', 'failed delivery removes stale mapped choices')
		routing_check(os.read_file(tool_log)! == '', 'failed delivery never invokes pkg')
		routing_check(os.read_file(path)! == text, 'failed delivery preserves declaration')
	}
	// The missing-declaration branch must still execute the actual recording
	// legacy tool, proving the no-fallback checks above can observe a fallback.
	os.rm(root + '/usr/share/vinix-packages/applications.json')!
	first_run_install_vendor_with_release('neovim', routing_route(root, 'aarch64'))!
	routing_check(os.read_file(tool_log)! == 'install|neovim\n', 'recording legacy control executes')
}
