// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import strconv
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const usage = 'usage: vinix-package [--root DIR] [--offline] [--json] [--progress] COMMAND [ARGS]\n' +
	'  update | search [QUERY] | info ID | list | status | updates | view\n' +
	'  install ID... | remove ID... | upgrade | rollback | gc | verify\n' +
	'  plan install|remove|upgrade|deploy [ID...] | deploy MANIFEST.json\n' +
	'  review install|remove|upgrade|deploy|rollback [ID...]\n' +
	'  repo-list | repo-enroll ID URL PUBLIC_KEY_HEX | repo-revoke ID\n' +
	'  repo-review enroll ID URL KEY | repo-review revoke ID\n' +
	'  repo-apply REVIEW_FINGERPRINT enroll ID URL KEY | repo-apply REVIEW_FINGERPRINT revoke ID\n' +
	'  apply REVIEW_FINGERPRINT OPERATION [ID...]\n' +
	'  policy | policy-review POLICY.json | policy-apply REVIEW_FINGERPRINT POLICY.json\n' +
	'  deployment-lock [ID...] | deployment-review FILE | deployment-apply REVIEW_FINGERPRINT FILE\n' +
	'  run ID [ABSOLUTE_FILE...] | purge-data ID | mirror NEW_DIRECTORY ID...\n' +
	'  keygen SEED_FILE | pack MANIFEST.json SOURCE_DIR REPOSITORY_DIR\n' +
	'  pack-root RECIPE.json PREPARED_GUEST_ROOT REPOSITORY_DIR\n' +
	'  publish REPOSITORY_DIR REPOSITORY_ID SEED_FILE SEQUENCE EXPIRES_UNIX\n' +
	'  publish-release REPOSITORY_DIR REPOSITORY_ID SEED_FILE SEQUENCE EXPIRES_UNIX NEW_DIRECTORY\n'

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
	if progress && (as_json || command !in ['update', 'install', 'remove', 'upgrade', 'apply', 'deploy', 'deployment-apply', 'rollback']) {
		return error('--progress supports update, install/remove/upgrade, apply, deploy/deployment-apply and rollback without --json')
	}
	names := args[1..].clone()
	match command {
		'keygen' {
			if names.len != 1 { return error('keygen requires a new signing seed filename') }
			println(pkgcore.keygen(names[0])!)
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
		progress: if progress { print_progress } else { ignore_progress } }
	match command {
		'deployment-lock', 'deployment-review' {
			if command == 'deployment-review' && names.len != 1 { return error('deployment-review requires a deployment document') }
			text := if command == 'deployment-lock' {
				json2.encode(service.lock_deployment(names)!)
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
			println(json2.encode(service.policy()!))
		}
		'policy-review' {
			if names.len != 1 { return error('policy-review requires an organization policy document') }
			println(json2.encode(service.review_policy(names[0])!))
		}
		'policy-apply' {
			if names.len != 2 { return error('policy-apply requires a review fingerprint and organization policy document') }
			println(json2.encode(service.apply_policy(names[1], names[0])!))
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
		'repo-list' {
			if names.len != 0 { return error('repo-list takes no arguments') }
			status := pkgcore.repository_status(root)!
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
			state := if command == 'verify' { service.verify()! } else { service.state()! }
			if as_json || command == 'status' {
				println(json2.encode(state))
				return 0
			}
			for installed in state.packages {
				p := installed.package
				println('${p.id} ${p.version} ${p.architecture} ${installed.repository}')
			}
		}
		'install', 'remove', 'upgrade' {
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
			if names.len < 2 || !pkgcore.digest_valid(names[0]) || names[1] !in ['install', 'remove', 'upgrade', 'deploy', 'rollback'] {
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
		'mirror' {
			if names.len < 2 {
				return error('mirror requires a new destination directory and package IDs')
			}
			service.mirror(names[0], names[1..])!
		}
		'run' {
			if root != '' {
				return error('application launch cannot use an alternate installation root')
			}
			if names.len < 1 { return error('run requires an application ID') }
			return service.run(names[0], names[1..])
		}
		'purge-data' {
			if root != '' || names.len != 1 || !pkgcore.identifier(names[0]) || os.geteuid() == 0 {
				return error('purge-data requires an application ID and an ordinary user session')
			}
			state := service.state()!
			if state.packages.any(it.package.id == names[0]) {
				return error('remove the application before purging its data')
			}
			path := os.home_dir().trim_right('/') + '/.local/share/vinix-apps/' + names[0]
			if os.is_link(path) { return error('application data directory is a symlink') }
			os.rmdir_all(path)!
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

fn main() {
	code := checked(os.args[1..]) or {
		eprintln('vinix-package: ${err}')
		exit(1)
	}
	exit(code)
}
