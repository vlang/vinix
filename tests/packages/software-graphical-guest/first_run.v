// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import crypto.sha256
import tools.packages.pkgprotocol

const release_declaration = '/usr/share/vinix-packages/applications.json'
const release_decision = '/home/alex/.vinix-first-run-release'
const release_catalog_cache = '/var/lib/vinix-packages/catalog.json'

fn first_run_refresh_enabled() bool {
	return os.exists('/etc/software-graphical-first-run-refresh')
}

fn staged_catalog_enabled() bool {
	return os.exists('/etc/software-graphical-staged-catalog')
}

fn first_run_packages() []string {
	return if staged_catalog_enabled() { ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello'] }
		else { ['org.vinix.counter'] }
}

fn check_staged_catalog(architecture string) ! {
	mut declaration := pkgprotocol.decode_deployment_document(os.read_file(release_declaration)!)!
	defer { declaration.close() }
	expected := first_run_packages()
	if declaration.format != 2 || declaration.architecture != architecture || declaration.packages != expected ||
		declaration.locked.map(it.id) != expected {
		return error('installed staged catalog does not declare the complete native SDK set')
	}
}

fn check_staged_catalog_installed() ! {
	output := read_package_report(['--json', 'deployment-audit', release_declaration],
		'staged deployment audit')!
	mut audit := pkgprotocol.decode_deployment_audit(output)!
	defer { audit.close() }
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	lock_digest := sha256.hexhash(os.read_file(release_declaration)!)
	if !audit.matches || audit.architecture != architecture || audit.generation == 0 ||
		audit.deployment_sha256 != lock_digest || audit.rows.map(it.id) != first_run_packages() ||
		audit.rows.any(it.status != 'match' || it.installed_version != '1.0.0') {
		return error('installed package metadata differs from the exact staged application lock')
	}
	check_first_run_refresh_approvals(2)!
	println('SOFTWARE FIRST RUN STAGED AUDIT ' + json2.encode(audit))
}

fn read_package_report(arguments []string, report string) !string {
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { child.close() }
	child.set_args(arguments)
	child.set_redirect_stdio()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	diagnostic := child.stderr_slurp()
	child.wait()
	if child.code != 0 || output.len > 1024 * 1024 {
		return error(report + ' failed: ' + diagnostic)
	}
	return output
}

fn check_first_run_refresh_approvals(count int) ! {
	approvals := package_approvals()
	if approvals.len != count || approvals.any(!it.contains('uid=1000 run packages-change as alex: exit 0')) {
		return error('unexpected first-run package approval audit')
	}
}

fn check_first_run_inputs(fresh bool) ! {
	info := os.lstat(release_declaration)!
	if info.mode & 0o170000 != 0o100000 || info.uid != 0 || info.mode & 0o022 != 0 {
		return error('first-run declaration must be an ordinary root-owned immutable-to-user file')
	}
	document := json2.decode[json2.Any](os.read_file(release_declaration)!)!.as_map()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	if release_routing_enabled() {
		check_release_routing_declaration(document, architecture)!
	} else if staged_catalog_enabled() {
		check_staged_catalog(architecture)!
	} else if document.len != 3 || document['format']! != json2.Any(f64(1)) ||
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
	choice := if release_routing_enabled() { 'skip' } else { 'review' }
	if info.uid != 1000 || info.mode & 0o170000 != 0o100000 || info.mode & 0o777 != 0o600 ||
		os.read_file(release_decision)! != choice + '\n' {
		return error('first-run Review decision is not exact, private and owned by alex')
	}
}

fn first_run_proposal() ! {
	check_first_run_decision()!
	refresh := first_run_refresh_enabled()
	if refresh {
		require_no_installation()!
		check_first_run_refresh_approvals(1)!
	} else { require_uninstalled()! }
	// An independent read-only oracle records the complete signed proposal.
	// The host separately captures Software's real proposal before Confirm.
	output := read_package_report(if refresh { ['--offline', 'deployment-review', release_declaration] }
		else { ['deployment-review', release_declaration] }, 'first-run read-only proposal')!
	review := json2.decode[json2.Any](output)!.as_map()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	expected := first_run_packages()
	rows := review['rows']!.as_array()
	if review['operation']!.str() != 'deploy' || review['architecture']!.str() != architecture ||
		review['generation']!.f64() != 0 || review['fingerprint']!.str().len != 64 ||
		review['names']!.as_array().map(it.str()) != expected ||
		review['requested']!.as_array().map(it.str()) != expected || rows.len != expected.len {
		return error('first-run proposal differs from the complete declared application set')
	}
	for i, value in rows {
		row := value.as_map()
		permissions := if expected[i] == 'org.vinix.package-hello' { ['files'] } else { ['display'] }
		if row['id']!.str() != expected[i] || row['version']!.str() != '1.0.0' ||
			row['installed_version']!.str() != '' || row['architecture']!.str() != architecture ||
			row['kind']!.str() != 'native' || row['repository']!.str() != 'native' ||
			row['license']!.str() != 'MIT' || row['public_key']!.str().len != 64 ||
			row['permissions']!.as_array().map(it.str()) != permissions ||
			row['requested']! != json2.Any(true) || row['action']!.str() != 'install' {
			return error('first-run proposal has incomplete publisher, permission or install details')
		}
	}
	if refresh {
		require_no_installation()!
		check_first_run_refresh_approvals(1)!
	} else { require_uninstalled()! }
	println('SOFTWARE FIRST RUN PROPOSAL ' + json2.encode(review))
	choice := if release_routing_enabled() { 'skip' } else { 'review' }
	println('SOFTWARE FIRST RUN private decision owner=1000 mode=0600 value=' + choice + ' PASS')
}
