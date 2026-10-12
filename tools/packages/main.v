// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.pkgcore

const usage = 'usage: vinix-package [--root DIR] [--offline] [--json] COMMAND [ARGS]\n' +
	'  update | search [QUERY] | info ID | list | status | updates | view\n' +
	'  install ID... | remove ID... | upgrade | rollback | gc | verify\n' +
	'  plan install|remove|upgrade|deploy [ID...] | deploy MANIFEST.json\n' +
	'  review install|remove|upgrade|deploy|rollback [ID...]\n' +
	'  repo-list | repo-enroll ID URL PUBLIC_KEY_HEX | repo-revoke ID\n' +
	'  repo-review enroll ID URL KEY | repo-review revoke ID\n' +
	'  repo-apply REVIEW_FINGERPRINT enroll ID URL KEY | repo-apply REVIEW_FINGERPRINT revoke ID\n' +
	'  apply REVIEW_FINGERPRINT OPERATION [ID...]\n' +
	'  run ID [ABSOLUTE_FILE...] | purge-data ID | mirror NEW_DIRECTORY ID...\n' +
	'  keygen SEED_FILE | pack MANIFEST.json SOURCE_DIR REPOSITORY_DIR\n' +
	'  pack-root RECIPE.json PREPARED_GUEST_ROOT REPOSITORY_DIR\n' +
	'  publish REPOSITORY_DIR REPOSITORY_ID SEED_FILE SEQUENCE EXPIRES_UNIX\n'

struct Deployment {
	format       int = 1
	architecture string
	packages     []string
}

fn checked(arguments []string) !int {
	mut args := arguments.clone()
	mut root := ''
	mut offline := false
	mut as_json := false
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
		'publish' {
			if names.len != 5 || !names[3].bytes().all(it >= `0` && it <= `9`) || !names[4].bytes().all(it >= `0` && it <= `9`) {
				return error('publish requires repository directory, ID, signing seed, sequence and expiry')
			}
			pkgcore.publish(names[0], names[1], names[2], names[3].u64(), names[4].i64())!
			return 0
		}
		else {}
	}
	initial := pkgcore.load_config(root)!
	if root == '' {
		$if arm64 {
			if initial.architecture != 'aarch64' {
				return error('package configuration targets another architecture')
			}
		}
		$if amd64 {
			if initial.architecture != 'x86_64' {
				return error('package configuration targets another architecture')
			}
		}
	}
	config := pkgcore.Config{ ...initial, policy: pkgcore.Policy{ ...initial.policy, offline: offline || initial.policy.offline } }
	directory := pkgcore.state_directory(root)
	match command {
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
			pkgcore.refresh(config, directory)!
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
			state := pkgcore.read_state(directory, config.architecture)!
			if as_json || command == 'status' {
				println(json2.encode(state))
				return 0
			}
			for installed in state.packages {
				p := installed.package
				if command == 'verify' {
					for file in p.files {
						if !pkgcore.verified_file(directory + '/generations/' + state.generation.str() + '/apps/' + p.id + '/' + file.path, file) {
							return error('${p.id}: installed payload verification failed: ${file.path}')
						}
					}
				}
				println('${p.id} ${p.version} ${p.architecture} ${installed.repository}')
			}
		}
		'install', 'remove', 'upgrade' {
			pkgcore.transact(config, directory, command, names, pkgcore.TransactionOptions{})!
		}
		'plan' {
			if names.len < 1 { return error('plan requires an operation') }
			println(json2.encode(pkgcore.preview_plan(config, directory, names[0], names[1..])!))
		}
		'review' {
			if names.len < 1 { return error('review requires an operation') }
			text := json2.encode(pkgcore.review_operation(config, directory, names[0], names[1..])!)
			if text.len > pkgcore.max_metadata { return error('package review exceeds metadata limit') }
			println(text)
		}
		'apply' {
			if names.len < 2 || !pkgcore.digest_valid(names[0]) || names[1] !in ['install', 'remove', 'upgrade', 'deploy', 'rollback'] {
				return error('apply requires a review fingerprint and operation')
			}
			if names[1] == 'rollback' {
				if names.len != 2 { return error('rollback takes no package IDs') }
				pkgcore.rollback_reviewed(config, directory, names[0])!
			} else {
				pkgcore.transact(config, directory, names[1], names[2..], pkgcore.TransactionOptions{ expected_review: names[0] })!
			}
		}
		'deploy' {
			if names.len != 1 { return error('deploy requires a deployment manifest') }
			deployment := json2.decode[Deployment](pkgcore.read_metadata(names[0])!)!
			if deployment.format != 1 || deployment.architecture != config.architecture {
				return error('deployment format or architecture mismatch')
			}
			pkgcore.transact(config, directory, 'deploy', deployment.packages, pkgcore.TransactionOptions{})!
		}
		'rollback' {
			if names.len != 0 { return error('rollback takes no arguments') }
			pkgcore.rollback(config, directory)!
		}
		'gc' {
			if names.len != 0 { return error('gc takes no arguments') }
			pkgcore.collect(config, directory)!
		}
		'mirror' {
			if names.len < 2 {
				return error('mirror requires a new destination directory and package IDs')
			}
			pkgcore.mirror(config, directory, names[0], names[1..])!
		}
		'run' {
			if root != '' {
				return error('application launch cannot use an alternate installation root')
			}
			if names.len < 1 { return error('run requires an application ID') }
			return pkgcore.run_application(config, directory, names[0], names[1..])
		}
		'purge-data' {
			if root != '' || names.len != 1 || !pkgcore.identifier(names[0]) || os.geteuid() == 0 {
				return error('purge-data requires an application ID and an ordinary user session')
			}
			state := pkgcore.read_state(directory, config.architecture)!
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

fn main() {
	code := checked(os.args[1..]) or {
		eprintln('vinix-package: ${err}')
		exit(1)
	}
	exit(code)
}
