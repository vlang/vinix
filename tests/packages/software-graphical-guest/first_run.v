// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os

const release_declaration = '/usr/share/vinix-packages/applications.json'
const release_decision = '/home/alex/.vinix-first-run-release'

fn check_first_run_inputs(fresh bool) ! {
	info := os.lstat(release_declaration)!
	if info.mode & 0o170000 != 0o100000 || info.uid != 0 || info.mode & 0o022 != 0 {
		return error('first-run declaration must be an ordinary root-owned immutable-to-user file')
	}
	document := json2.decode[json2.Any](os.read_file(release_declaration)!)!.as_map()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	if document.len != 3 || document['format']! != json2.Any(f64(1)) ||
		document['architecture']!.str() != architecture ||
		document['packages']!.as_array().map(it.str()) != ['org.vinix.counter'] {
		return error('first-run declaration is not the complete architecture-matched Counter set')
	}
	if os.exists('/usr/bin/pkg') || os.exists('/home/alex/.vinix-first-run-apps') {
		return error('first-run qualification must not depend on legacy pkg or pending marker')
	}
	if fresh {
		if os.exists(release_decision) || os.is_link(release_decision) {
			return error('first-run decision was already seeded before Review')
		}
		require_uninstalled()!
	}
}

fn check_first_run_decision() ! {
	info := os.lstat(release_decision)!
	if info.uid != 1000 || info.mode & 0o170000 != 0o100000 || info.mode & 0o777 != 0o600 ||
		os.read_file(release_decision)! != 'review\n' {
		return error('first-run Review decision is not exact, private and owned by alex')
	}
}

fn first_run_proposal() ! {
	check_first_run_decision()!
	require_uninstalled()!
	// An independent read-only oracle records the complete signed proposal.
	// The host separately captures Software's real proposal before Confirm.
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { child.close() }
	child.set_args(['deployment-review', release_declaration])
	child.set_redirect_stdio()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	diagnostic := child.stderr_slurp()
	child.wait()
	if child.code != 0 || output.len > 1024 * 1024 {
		return error('first-run read-only proposal failed: ' + diagnostic)
	}
	review := json2.decode[json2.Any](output)!.as_map()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	if review['operation']!.str() != 'deploy' || review['architecture']!.str() != architecture ||
		review['generation']!.f64() != 0 || review['fingerprint']!.str().len != 64 ||
		review['names']!.as_array().map(it.str()) != ['org.vinix.counter'] ||
		review['requested']!.as_array().map(it.str()) != ['org.vinix.counter'] ||
		review['rows']!.as_array().len != 1 {
		return error('first-run proposal differs from the complete declared Counter set')
	}
	row := review['rows']!.as_array()[0].as_map()
	if row['id']!.str() != 'org.vinix.counter' || row['version']!.str() != '1.0.0' ||
		row['installed_version']!.str() != '' || row['architecture']!.str() != architecture ||
		row['kind']!.str() != 'native' || row['repository']!.str() != 'native' ||
		row['license']!.str() != 'MIT' || row['public_key']!.str().len != 64 ||
		row['permissions']!.as_array().map(it.str()) != ['display'] ||
		row['requested']! != json2.Any(true) || row['action']!.str() != 'install' {
		return error('first-run proposal has incomplete publisher, permission or install details')
	}
	require_uninstalled()!
	println('SOFTWARE FIRST RUN PROPOSAL ' + json2.encode(review))
	println('SOFTWARE FIRST RUN private decision owner=1000 mode=0600 value=review PASS')
}
