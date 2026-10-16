// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import strconv
import tools.packages.pkgadmin
import tools.packages.pkglaunch
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const usage = 'usage: vinix-package [--root DIR] [--offline] [--json] [--progress] COMMAND [ARGS]\n' +
	'  update | search [QUERY] | info ID | list | status | updates | view\n' +
	'  admin [--progress] [--offline] update|apply|cleanup-apply|repo-apply|deployment-apply|policy-apply|mirror-apply|mirror-deployment-apply ...\n' +
	'  install ID... | remove ID... | upgrade | repair | rollback | gc | verify | health\n' +
	'  cleanup-review | cleanup-apply REVIEW_FINGERPRINT (obsolete generations only)\n' +
	'  plan install|remove|upgrade|repair|deploy [ID...] | deploy MANIFEST.json\n' +
	'  review install|remove|upgrade|repair|deploy|rollback [ID...]\n' +
	'  repo-list | repo-config | repo-enroll ID URL PUBLIC_KEY_HEX | repo-revoke ID\n' +
	'  repo-review enroll ID URL KEY | repo-review revoke ID\n' +
	'  repo-apply REVIEW_FINGERPRINT enroll ID URL KEY | repo-apply REVIEW_FINGERPRINT revoke ID\n' +
	'  apply REVIEW_FINGERPRINT OPERATION [ID...]\n' +
	'  policy | policy-review POLICY.json | policy-apply REVIEW_FINGERPRINT POLICY.json\n' +
	'  deployment-lock [ID...] | deployment-snapshot [INSTALLED_ID...]\n' +
	'  deployment-snapshot-save NEW_FILE [INSTALLED_ID...]\n' +
	'  deployment-audit FILE (read-only metadata drift; exit 0 match, 3 drift)\n' +
	'  deployment-review FILE | deployment-apply REVIEW_FINGERPRINT FILE\n' +
	'  run ID [ABSOLUTE_FILE...] | data-list | purge-data ID | mirror NEW_DIRECTORY ID...\n' +
	'  mirror-review NEW_DIRECTORY ID... | mirror-apply REVIEW_FINGERPRINT NEW_DIRECTORY ID...\n' +
	'  mirror-deployment-review NEW_DIRECTORY LOCK.json | mirror-deployment-apply REVIEW_FINGERPRINT NEW_DIRECTORY LOCK.json\n' +
	'  run-terminal ID [ABSOLUTE_FILE...] (terminal standard input/output required)\n' +
	'  run-window ID [ABSOLUTE_FILE...] (declared native window broker protocol)\n' +
	'  run-args|run-terminal-args ID [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]\n' +
	'  keygen NEW_SEED_FILE | key-public SEED_FILE | pack MANIFEST.json SOURCE_DIR REPOSITORY_DIR\n' +
	'  pack-root RECIPE.json PREPARED_GUEST_ROOT REPOSITORY_DIR\n' +
	'  pack-catalog CATALOG.json PREPARED_ROOTS NEW_WORKSPACE\n' +
	'  compose-catalog NEW_LOCK_DIRECTORY PROFILE CATALOG.json [PROFILE CATALOG.json...]\n' +
	'  compose-catalog-for ARCH NEW_LOCK_DIRECTORY PROFILE CATALOG.json [PROFILE CATALOG.json...]\n' +
	'  native-catalog VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY\n' +
	'  sqlite-catalog SQLITE_VERSION RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY\n' +
	'  ffmpeg-catalog RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY\n' +
	'  wine-catalog RECIPE_DIRECTORY PREPARED_ROOTS NEW_LOCK_DIRECTORY\n' +
	'  apple-catalog RECIPE_DIRECTORY PREPARED_ROOTS NEW_LOCK_DIRECTORY\n' +
	'  publish REPOSITORY_DIR REPOSITORY_ID SEED_FILE SEQUENCE EXPIRES_UNIX\n' +
	'  publish-release REPOSITORY_DIR REPOSITORY_ID SEED_FILE SEQUENCE EXPIRES_UNIX NEW_DIRECTORY\n'

fn publisher_reply[T](mut info T) {
	defer { info.close() }
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(info, mut bytes)
	text := bytes.bytestr()
	defer { unsafe { text.free() } }
	println(text)
}

fn checked(arguments []string) !int {
	mut args := arguments.clone()
	mut root := ''
	mut offline := false
	mut as_json := false
	mut progress := false
	for args.len > 0 && args[0].starts_with('--') {
		match args[0] {
			'--root' {
				if args.len < 2 || !args[1].starts_with('/') || args[1].contains('\x00') {
					return error('--root requires an absolute directory')
				}
				root = args[1].trim_right('/')
				args = args[2..].clone()
			}
			'--offline' {
				offline = true
				args = args[1..].clone()
			}
			'--json' {
				as_json = true
				args = args[1..].clone()
			}
			'--progress' { progress = true; args = args[1..].clone() }
			'--help' {
				print(usage)
				return 0
			}
			else { return error('unknown option: ${args[0]}') }
		}
	}
	if args.len == 0 {
		print(usage)
		return 2
	}
	command := args[0]
	if progress && ((as_json && command != 'health') || command !in ['update', 'install', 'remove', 'upgrade', 'repair', 'apply', 'deploy', 'deployment-apply', 'rollback', 'verify', 'health', 'mirror', 'mirror-apply', 'mirror-deployment-apply']) {
		return error('--progress supports update, install/remove/upgrade/repair, apply, deploy/deployment-apply, rollback, verify, health and mirror/mirror-apply/mirror-deployment-apply; only health also supports --json')
	}
	names := args[1..].clone()
	if command in ['run', 'run-terminal', 'run-window', 'run-args', 'run-terminal-args'] && os.geteuid() != 0 {
		if root != '' { return error('application launch does not support an alternate installation root') }
		if offline || as_json || progress { return error('application launches use the real root without administration/output options') }
		if command in ['run-terminal', 'run-terminal-args'] && (C.isatty(0) != 1 || C.isatty(1) != 1) {
			return error('terminal launch requires terminal standard input and output')
		}
		if pkglaunch.needs_isolation()! { return pkglaunch.run(args) }
	}
	if command in ['admin', 'admin-authorize'] {
		if root != '' || offline || as_json || progress { return error('administrator transport options follow admin, and cannot select another root') }
		if command == 'admin' { return pkgadmin.run(names) }
		if names.len != 0 { return error('admin-authorize takes no command-line request') }
		return admin_authorize()
	}
	match command {
		'keygen' {
			if names.len != 1 { return error('keygen requires a new signing seed filename') }
			println(pkgcore.keygen(names[0])!)
			return 0
		}
		'key-public' {
			if names.len != 1 { return error('key-public requires a private signing seed filename') }
			println(pkgcore.key_public(names[0])!)
			return 0
		}
		'pack' {
			if names.len != 3 {
				return error('pack requires a manifest, payload directory and repository directory')
			}
			println(json2.encode(pkgcore.pack(names[0], names[1], names[2])!))
			return 0
		}
		'pack-root' {
			if names.len != 3 { return error('pack-root requires a recipe, prepared guest root and repository directory') }
			println(json2.encode(pkgcore.pack_root(names[0], names[1], names[2])!))
			return 0
		}
		'pack-catalog' {
			if names.len != 3 { return error('pack-catalog requires a catalog recipe, prepared roots and a new workspace directory') }
			mut info := pkgcore.pack_catalog(names[0], names[1], names[2])!
			publisher_reply(mut info)
			return 0
		}
		'compose-catalog' {
			if names.len < 3 || names.len % 2 != 1 || names.len > 129 {
				return error('compose-catalog requires a new lock directory and 1 to 64 PROFILE CATALOG.json pairs')
			}
			mut sources := []pkgcore.CatalogSource{}
			defer { unsafe { (&array(&sources)).free() } }
			for i := 1; i < names.len; i += 2 { sources << pkgcore.CatalogSource{ id: names[i], catalog: names[i + 1] } }
			mut info := pkgcore.compose_catalog(sources, names[0])!
			publisher_reply(mut info)
			return 0
		}
		'compose-catalog-for' {
			if names.len < 4 || names.len % 2 != 0 || names.len > 130 {
				return error('compose-catalog-for requires aarch64 or x86_64, a new lock directory and 1 to 64 PROFILE CATALOG.json pairs')
			}
			mut sources := []pkgcore.CatalogSource{}
			defer { unsafe { (&array(&sources)).free() } }
			for i := 2; i < names.len; i += 2 { sources << pkgcore.CatalogSource{ id: names[i], catalog: names[i + 1] } }
			mut info := pkgcore.compose_catalog_for(names[0], sources, names[1])!
			publisher_reply(mut info)
			return 0
		}
		'native-catalog' {
			if names.len != 3 { return error('native-catalog requires version, prepared roots and a new lock directory') }
			mut info := pkgcore.native_catalog(names[0], names[1], names[2])!
			publisher_reply(mut info)
			return 0
		}
		'sqlite-catalog' {
			if names.len != 4 { return error('sqlite-catalog requires SQLite version, runtime version, prepared roots and a new lock directory') }
			println(json2.encode(pkgcore.sqlite_catalog(names[0], names[1], names[2], names[3])!))
			return 0
		}
		'ffmpeg-catalog' {
			if names.len != 3 { return error('ffmpeg-catalog requires runtime version, prepared roots and a new lock directory') }
			println(json2.encode(pkgcore.ffmpeg_catalog(names[0], names[1], names[2])!))
			return 0
		}
		'wine-catalog' {
			if names.len != 3 { return error('wine-catalog requires a recipe directory, prepared roots and a new lock directory') }
			println(json2.encode(pkgcore.wine_catalog(names[0], names[1], names[2])!))
			return 0
		}
		'apple-catalog' {
			if names.len != 3 { return error('apple-catalog requires a recipe directory, prepared roots and a new lock directory') }
			println(json2.encode(pkgcore.apple_catalog(names[0], names[1], names[2])!))
			return 0
		}
		'publish', 'publish-release' {
			count := if command == 'publish' { 5 } else { 6 }
			if names.len != count || names[3] == '' || names[4] == ''
				|| !names[3].bytes().all(it >= `0` && it <= `9`) || !names[4].bytes().all(it >= `0` && it <= `9`) {
				return error('${command} requires repository directory, ID, signing seed, sequence and expiry' + if count == 6 { ' and a new output directory' } else { '' })
			}
			sequence := strconv.parse_uint(names[3], 10, 64)!
			expires := strconv.parse_int(names[4], 10, 64)!
			if command == 'publish' {
				pkgcore.publish(names[0], names[1], names[2], sequence, expires)!
			} else {
				println(json2.encode(pkgcore.publish_release(names[0], names[1], names[2], sequence, expires, names[5])!))
			}
			return 0
		}
		else {}
	}
	service := pkgcore.Service{ root: root, offline: offline,
		progress: if progress && command == 'health' { print_health_progress } else if progress { print_progress } else { ignore_progress } }
	match command {
		'deployment-snapshot-save' {
			if names.len == 0 { return error('deployment-snapshot-save requires a new destination file and optional installed IDs') }
			mut saved := service.save_deployment_snapshot(names[0], names[1..])!
			defer { saved.close() }
			if as_json { println(json2.encode(saved)) }
			else { println('Installed deployment snapshot saved: ${saved.destination}\nGeneration: ${saved.generation}; application roots: ${saved.roots}; packages: ${saved.packages}\nSHA-256: ${saved.sha256}') }
		}
		'deployment-audit' {
			if names.len != 1 { return error('deployment-audit requires one exact deployment lock') }
			mut report := service.audit_deployment(names[0])!
			defer { report.close() }
			if as_json { println(json2.encode(report)) }
			else {
				println('Deployment metadata audit for generation ${report.generation}: ${if report.matches { 'match' } else { 'drift' }}')
				println('Captured lock SHA-256: ${report.deployment_sha256}')
				for row in report.rows {
					println('${row.id}: ${row.status}; expected ${if row.expected_version == '' { '(absent)' } else { row.expected_version }}, installed ${if row.installed_version == '' { '(absent)' } else { row.installed_version }}${if row.differences.len == 0 { '' } else { '; differences: ' + row.differences.join(', ') }}')
				}
				println('Metadata comparison only; use health for payload integrity and reviewed deployment for authorized changes.')
			}
			return if report.matches { 0 } else { 3 }
		}
		'deployment-lock', 'deployment-snapshot', 'deployment-review' {
			if command == 'deployment-review' && names.len != 1 { return error('deployment-review requires a deployment document') }
			text := if command == 'deployment-lock' {
				json2.encode(service.lock_deployment(names)!)
			} else if command == 'deployment-snapshot' {
				mut document := service.snapshot_deployment(names)!
				encoded := json2.encode(document)
				document.close()
				encoded
			} else {
				json2.encode(service.review_deployment(names[0])!)
			}
			if text.len > pkgcore.max_metadata { return error('deployment document/review exceeds metadata limit') }
			println(text)
		}
		'deployment-apply' {
			if names.len != 2 { return error('deployment-apply requires a review fingerprint and deployment document') }
			service.apply_deployment(names[1], names[0])!
		}
		'policy' {
			if names.len != 0 { return error('policy takes no arguments') }
			mut document := service.policy()!
			defer { document.close() }
			println(json2.encode(document))
		}
		'policy-review' {
			if names.len != 1 { return error('policy-review requires an organization policy document') }
			mut review := service.review_policy(names[0])!
			defer { review.close() }
			println(json2.encode(review))
		}
		'policy-apply' {
			if names.len != 2 { return error('policy-apply requires a review fingerprint and organization policy document') }
			mut document := service.apply_policy(names[1], names[0])!
			defer { document.close() }
			println(json2.encode(document))
		}
		'repo-review', 'repo-apply' {
			applying := command == 'repo-apply'
			offset := if applying { 1 } else { 0 }
			if names.len <= offset { return error('repository review/apply requires enroll or revoke') }
			if applying && !pkgcore.digest_valid(names[0]) { return error('repository apply requires a review fingerprint') }
			operation := names[offset]
			if (operation == 'enroll' && names.len != offset + 4) || (operation == 'revoke' && names.len != offset + 2)
				|| operation !in ['enroll', 'revoke'] { return error('use repo-review/apply enroll ID URL KEY or revoke ID') }
			repository := pkgcore.Repository{ id: names[offset + 1],
				url: if operation == 'enroll' { names[offset + 2] } else { '' },
				public_key: if operation == 'enroll' { names[offset + 3] } else { '' } }
			if !applying {
				println(json2.encode(pkgcore.review_repository(root, operation, repository, offline)!))
			} else if operation == 'enroll' {
				pkgcore.enroll_repository_reviewed(root, repository, offline, names[0])!
				println('Repository enrolled. Refresh repositories to load its authenticated catalog.')
			} else {
				pkgcore.revoke_repository_reviewed(root, repository.id, names[0])!
				println('Repository revoked; installed payloads, personal data and trust history were retained.')
			}
		}
		'repo-config' {
			if names.len != 0 { return error('repo-config takes no arguments') }
			mut configuration := pkgcore.repository_configuration(root)!
			defer { configuration.close() }
			if as_json {
				println(json2.encode(configuration))
			} else {
				println('Configured repositories; catalog and replay history have not been checked.')
				for repository in configuration.repositories {
					println('${repository.id} ${repository.url}\n  Publisher key: ${repository.public_key}')
				}
				if configuration.repositories.len == 0 { println('No repositories are configured.') }
			}
		}
		'repo-list' {
			if names.len != 0 { return error('repo-list takes no arguments') }
			mut status := pkgcore.repository_status(root)!
			defer { status.close() }
			if as_json {
				println(json2.encode(status))
			} else {
				for repository in status.repositories {
					println('${repository.id} ${repository.url}\n  Publisher key: ${repository.public_key}')
					for floor in status.history {
						if floor.id == repository.id && floor.public_key == repository.public_key {
							println('  Remembered sequence: ${floor.sequence}')
						}
					}
				}
				if status.repositories.len == 0 { println('No trusted repositories are enrolled.') }
			}
		}
		'repo-enroll' {
			if names.len != 3 { return error('repo-enroll requires ID, URL and an independently authenticated publisher key') }
			pkgcore.enroll_repository(root, pkgcore.Repository{ id: names[0], url: names[1], public_key: names[2] }, offline)!
			println('Enrolled repository ${names[0]}. Run update to load its verified catalog. A replaced key revokes launches and rollback of payloads signed with the old key.')
		}
		'repo-revoke' {
			if names.len != 1 { return error('repo-revoke requires one repository ID') }
			pkgcore.revoke_repository(root, names[0])!
			println('Revoked repository ${names[0]}; installed payloads and personal data were retained for inspection/removal. Trust history was retained.')
		}
		'update' {
			if names.len != 0 { return error('update takes no package IDs') }
			service.refresh()!
		}
		'view', 'search', 'info', 'updates' {
			view := pkgcore.software_view(root, offline)!
			if command == 'view' {
				text := json2.encode(view)
				if text.len > pkgcore.max_metadata { return error('software catalog exceeds metadata limit') }
				println(text)
				return 0
			}
			if command == 'info' && names.len != 1 { return error('info requires one package ID') }
			query := names.join(' ').to_lower()
			mut found := false
			for row in view.rows {
				if command == 'updates' && !row.updatable { continue }
				if command == 'info' && row.id != query { continue }
				if command == 'search' && query != '' && !('${row.id} ${row.name} ${row.description}'.to_lower().contains(query)) {
					continue
				}
				found = true
				if as_json {
					println(json2.encode(row))
				} else {
					println('${row.id} ${row.version} (${row.architecture}) — ${row.description}')
					if command == 'info' {
						println('Repository: ${row.repository}\nPublisher key: ${row.public_key}\nLicense: ${row.license}\nPermissions: ${row.permissions.join(', ')}\nInstalled: ${row.installed_version}\n${row.diagnostic}')
					}
				}
			}
			if command == 'info' && !found { return error('package not found: ${query}') }
			if view.catalog_error != '' { return error(view.catalog_error) }
			if command == 'updates' && view.update_error != '' { return error(view.update_error) }
		}
		'status', 'list', 'verify' {
			mut state := if command == 'verify' { service.verify()! } else { service.state()! }
			defer { state.close() }
			if as_json || command == 'status' {
				println(json2.encode(state))
				return 0
			}
			for installed in state.packages {
				p := installed.package
				println('${p.id} ${p.version} ${p.architecture} ${installed.repository}')
			}
			if command == 'verify' && progress { println('Installed package files and launchers verified.') }
		}
		'health' {
			if names.len != 0 { return error('health takes no package IDs') }
			mut report := service.health()!
			defer { report.close() }
			if as_json { println(json2.encode(report)) }
			else {
				println('Installed integrity report for generation ${report.generation}; trust and policy still apply at launch.')
				for row in report.rows {
					println('${row.id} ${row.version}: ${if row.issue == '' { 'verified' } else { row.issue }}${if row.diagnostic == '' { '' } else { ': ' + row.diagnostic }}')
				}
				println('Packages inspected: ${report.rows.len}; with issues: ${report.rows.filter(it.issue != '').len}. Use review repair to inspect recovery options.')
			}
		}
		'install', 'remove', 'upgrade', 'repair' {
			service.transact(command, names, pkgcore.TransactionOptions{})!
		}
		'plan' {
			if names.len < 1 { return error('plan requires an operation') }
			println(json2.encode(service.plan(names[0], names[1..])!))
		}
		'review' {
			if names.len < 1 { return error('review requires an operation') }
			text := json2.encode(service.review(names[0], names[1..])!)
			if text.len > pkgcore.max_metadata { return error('package review exceeds metadata limit') }
			println(text)
		}
		'apply' {
			if names.len < 2 || !pkgcore.digest_valid(names[0]) || names[1] !in ['install', 'remove', 'upgrade', 'repair', 'deploy', 'rollback'] {
				return error('apply requires a review fingerprint and operation')
			}
			if names[1] == 'rollback' {
				if names.len != 2 { return error('rollback takes no package IDs') }
				service.rollback(names[0])!
			} else {
				service.transact(names[1], names[2..], pkgcore.TransactionOptions{ expected_review: names[0] })!
			}
		}
		'deploy' {
			if names.len != 1 { return error('deploy requires a deployment manifest') }
			service.deploy(names[0])!
		}
		'rollback' {
			if names.len != 0 { return error('rollback takes no arguments') }
			service.rollback('')!
		}
		'gc' {
			if names.len != 0 { return error('gc takes no arguments') }
			service.collect()!
		}
		'cleanup-review' {
			if names.len != 0 { return error('cleanup-review takes no arguments') }
			mut review := service.review_cleanup()!
			defer { review.close() }
			println(json2.encode(review))
		}
		'cleanup-apply' {
			if names.len != 1 { return error('cleanup-apply requires a review fingerprint') }
			service.apply_cleanup(names[0])!
			println('Obsolete generation cleanup completed; active, rollback and leased generations, cached downloads and personal data were retained.')
		}
		'mirror' {
			if names.len < 2 {
				return error('mirror requires a new destination directory and package IDs')
			}
			service.mirror(names[0], names[1..])!
		}
		'mirror-review' {
			if names.len < 2 { return error('mirror-review requires a new destination directory and package IDs') }
			mut review := service.review_mirror(names[0], names[1..])!
			defer { review.close() }
			text := json2.encode(review)
			if text.len > pkgcore.max_metadata { return error('offline mirror review exceeds metadata limit') }
			println(text)
		}
		'mirror-apply' {
			if names.len < 3 { return error('mirror-apply requires a review fingerprint, new destination directory and package IDs') }
			service.apply_mirror(names[1], names[2..], names[0])!
		}
		'mirror-deployment-review' {
			if names.len != 2 { return error('mirror-deployment-review requires a new destination and format-2 deployment lock') }
			mut review := service.review_deployment_mirror(names[0], names[1])!
			defer { review.close() }
			text := json2.encode(review)
			if text.len > pkgcore.max_metadata { return error('deployment mirror review exceeds metadata limit') }
			println(text)
		}
		'mirror-deployment-apply' {
			if names.len != 3 { return error('mirror-deployment-apply requires a fingerprint, new destination and format-2 deployment lock') }
			service.apply_deployment_mirror(names[1], names[2], names[0])!
		}
		'run', 'run-terminal', 'run-window', 'run-args', 'run-terminal-args' {
			if root != '' {
				return error('application launch cannot use an alternate installation root')
			}
			if names.len < 1 { return error('run requires an application ID') }
			if command in ['run-args', 'run-terminal-args'] {
				mut input := pkgcore.command_launch(names[1..])!
				defer { input.close() }
				return service.run_command(names[0], input, command == 'run-terminal-args')
			}
			if command == 'run-terminal' { return service.run_terminal(names[0], names[1..]) }
			if command == 'run-window' { return service.run_window(names[0], names[1..]) }
			return service.run(names[0], names[1..])
		}
		'data-list' {
			if names.len != 0 { return error('data-list takes no arguments') }
			mut status := service.personal_data()!
			defer { status.close() }
			if as_json {
				text := json2.encode(status)
				if text.len > pkgcore.max_metadata { return error('personal data status exceeds metadata limit') }
				println(text)
			} else {
				for row in status.rows {
					println('${row.id}\t${if row.installed { 'installed' } else { 'uninstalled' }}\t${row.diagnostic}')
				}
			}
		}
		'purge-data' {
			if names.len != 1 {
				return error('purge-data requires an application ID and an ordinary user session')
			}
			service.purge_data(names[0])!
		}
		else { return error('unknown command: ${command}\n${usage}') }
	}
	return 0
}

fn ignore_progress(_ pkgprotocol.Progress) {}

fn print_progress(event pkgprotocol.Progress) {
	event.validate() or { return }
	text := json2.encode(event)
	frame := pkgprotocol.progress_prefix + text
	println(frame)
	flush_stdout()
	unsafe { text.free(); frame.free() }
}

// Keep the complete health snapshot on stdout, including with --json. Health
// is read-only, so its separate progress channel never needs admin transport.
fn print_health_progress(event pkgprotocol.Progress) {
	event.validate() or { return }
	text := json2.encode(event)
	frame := pkgprotocol.progress_prefix + text
	eprintln(frame)
	flush_stderr()
	unsafe { text.free(); frame.free() }
}

#include <sys/wait.h>
#include <signal.h>
fn C.fork() int
fn C.setsid() int
fn C.dup2(int, int) int
fn C._exit(int)
fn C.alarm(u32) u32

fn admin_authorize() !int {
	if os.geteuid() != 0 { return error('admin-authorize is an authentication-service action') }
	identity := os.getenv('VINIX_AUTH_UID')
	defer { unsafe { identity.free() } }
	if identity.len == 0 || identity.len > 10 || !identity.bytes().all(it >= `0` && it <= `9`)
		|| identity[0] == `0` || identity.u64() > 0xffffffff { return error('the authentication service supplied no ordinary caller identity') }
	uid := u32(identity.u64())
	mut bytes := [pkgadmin.request_limit + 1]u8{}
	mut used := 0
	for used < bytes.len {
		count := C.read(0, unsafe { &bytes[used] }, usize(bytes.len - used))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('administrator package request is unavailable') }
		if count == 0 { break }
		used += int(count)
	}
	mut request := pkgadmin.decode(unsafe { tos(&bytes[0], used) })!
	defer { request.close() }
	directory := pkgadmin.runtime_directory(uid)!
	defer { unsafe { directory.free() } }
	fd := pkgadmin.connect_private(directory, uid, request.nonce)!
	defer { C.close(fd) }
	child := C.fork()
	if child < 0 { return error('cannot start administrator package worker') }
	if child == 0 {
		C.alarm(0)
		if C.setsid() < 0 { C._exit(126) }
		stdin := C.open(c'/dev/null', C.O_RDONLY)
		if stdin < 0 || C.dup2(stdin, 0) != 0 || C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 { C._exit(126) }
		for descriptor in 3 .. 1024 { C.close(descriptor) }
		// The caller may close Software while the transaction completes. Ignore
		// a broken output stream; the normal state journal still owns recovery.
		unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
		code := checked(request.arguments) or { eprintln('vinix-package: ' + err.msg()); 1 }
		receipt := request.receipt(code)
		println(receipt); flush_stdout()
		C._exit(code)
	}
	println(request.nonce)
	return 0
}

fn main() {
	code := checked(os.args[1..]) or {
		eprintln('vinix-package: ${err}')
		exit(1)
	}
	exit(code)
}
