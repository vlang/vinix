// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

#include <sys/reboot.h>
fn C.sync()
fn C.reboot(int) int

const installed_proof = '/usr/share/mixed-release-image.json'
const installed_checkpoint = '/root/mixed-release-checkpoint.json'
const installed_id = 'vinix-mixed-release-installed-1'
const update_medium = '/usr/share/mixed-release-update'
const sqlite_runtime = 'org.vinix.sqlite-runtime'
const store = '/var/lib/vinix-packages'
const retained_files = ['/etc/passwd', '/etc/group', '/etc/shadow', declaration,
	'/etc/vinix-packages/config.json', store + '/current/state.json', store + '/catalog.json',
	store + '/trust-history.json', mixed_database, mixed_media, choice]

struct InstalledFile {
	digest string
	uid u32
	gid u32
	mode u32
}

struct InstalledCheckpoint {
	phase string
	generation string
	files map[string]InstalledFile
}

fn inspect_installed_file(path string, device u64) !InstalledFile {
	info := os.lstat(path)!
	if u64(info.dev) != device || info.mode & 0o170000 != 0o100000 || info.nlink != 1 {
		return error('expected a regular file on the installed root: ' + path)
	}
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return InstalledFile{digest: sha256.sum(bytes).hex(), uid: info.uid, gid: info.gid, mode: info.mode & 0o7777}
}

fn verify_installed_root() !u64 {
	device := u64((os.stat('/')!).dev)
	if device == 0 || !os.read_file('/proc/mounts')!.split_into_lines().any(it.starts_with('/dev/root / ext2 '))
		|| os.read_file('/.vinix-image-id')!.trim_space() != installed_id {
		return error('mixed release requires the installer-selected disk root')
	}
	proof := json2.decode[map[string]string](os.read_file(installed_proof)!)!
	if proof['/sbin/init'] == '' || proof[declaration] == '' { return error('incomplete installed image proof') }
	for path, expected in proof {
		file := inspect_installed_file(path, device)!
		if file.digest != expected || file.uid != 0 || file.mode & 0o022 != 0 {
			return error('installed image input identity changed: ' + path)
		}
	}
	return device
}

fn checkpoint_installed(phase string) ! {
	device := u64((os.stat('/')!).dev)
	mut files := map[string]InstalledFile{}
	for path in retained_files { files[path] = inspect_installed_file(path, device)! }
	os.write_file(installed_checkpoint, json2.encode(InstalledCheckpoint{
		phase: phase, generation: os.readlink(store + '/current')!, files: files
	}))!
}

fn mixed_package(args []string) !string {
	return checked(['/usr/bin/vinix-package', '--offline', ...args], '')
}

fn verify_mixed_audit(document pkgprotocol.DeploymentDocument, version string) ! {
	code, output := run_command(['/usr/bin/vinix-package', '--offline', '--json', 'deployment-audit', declaration], '')!
	mut audit := pkgprotocol.decode_deployment_audit(output)!
	defer { audit.close() }
	if code != (if version == '1.0.0' { 0 } else { 3 }) || audit.architecture != document.architecture
		|| audit.rows.len != document.locked.len || audit.generation == 0 {
		return error('unexpected installed release audit: ' + output)
	}
	for row in audit.rows {
		wanted := if version == '' { 'missing' } else if version == '1.1.0' && row.id == sqlite_runtime { 'changed' } else { 'match' }
		if row.status != wanted || (wanted == 'changed' && (row.installed_version != version
			|| 'version' !in row.differences || 'metadata_sha256' !in row.differences)) {
			return error('unexpected release audit row: ' + row.id + ' ' + row.status)
		}
	}
	state := json2.decode[VerifiedGeneration](mixed_package(['--json', 'verify'])!)!
	if state.generation != audit.generation || state.requested != (if version == '' { []string{} } else { document.packages }) {
		return error('verified installed closure differs from the audit')
	}
	println('HWTEST INFO installed release audit ' + output.trim_space())
}

fn reopen_mixed_data(math bool) ! {
	args := ['/usr/bin/vinix-package', '--offline', 'run', sqlite]
	query := checked(args, '.bail on\nSELECT sum(value) FROM saved; PRAGMA integrity_check;\n')!
	code, output := run_command(args, '.bail on\nSELECT ceil(1.25);\n')!
	if query.trim_space() != '42\nok' || (if math { code != 0 || output.trim_space() != '2.0' } else { code == 0 }) {
		return error('SQLite data or runtime capability differs: ' + query + output)
	}
	verify_mixed_media()!
}

fn maintain_installed(operation string, names []string, document pkgprotocol.DeploymentDocument) ! {
	current := os.readlink(store + '/current')!
	mut review := pkgprotocol.decode_review(mixed_package(['review', operation, ...names])!)!
	defer { review.close() }
	if review.operation != operation || review.architecture != document.architecture
		|| os.readlink(store + '/current')! != current {
		return error('installed review changed activation or differs from ' + operation)
	}
	if operation == 'upgrade' && review.rows.filter(it.action == 'update').map(it.id) != [sqlite_runtime] {
		return error('upgrade must change only the SQLite runtime')
	}
	println('HWTEST INFO reviewed mixed release ${operation} ${json2.encode(review)}')
	mixed_package(['apply', review.fingerprint, operation, ...names])!
	if os.readlink(store + '/current')! == current { return error('reviewed operation did not activate: ' + operation) }
}

fn resume_installed() !bool {
	device := verify_installed_root()!
	if !os.exists(installed_checkpoint) { return false }
	previous := json2.decode[InstalledCheckpoint](os.read_file(installed_checkpoint)!)!
	if os.readlink(store + '/current')! != previous.generation {
		return error('installed package generation changed across cold boot')
	}
	for path in retained_files {
		if inspect_installed_file(path, device)! != previous.files[path]! {
			return error('installed cold boot changed retained bytes or ownership: ' + path)
		}
	}
	mut document := pkgprotocol.decode_deployment_document(os.read_file(declaration)!)!
	defer { document.close() }
	if previous.phase == 'approved' {
		verify_mixed_audit(document, '1.0.0')!
		reopen_mixed_data(false)!
		repository := '/usr/share/vinix-packages/repositories/' + os.read_file('/etc/mixed-release-repository')!
		os.rename(repository, '/root/mixed-release-base')!
		os.rename(update_medium, repository)!
		mixed_package(['update'])!
		maintain_installed('upgrade', [], document)!
		verify_mixed_audit(document, '1.1.0')!
		reopen_mixed_data(true)!
		maintain_installed('rollback', [], document)!
		verify_mixed_audit(document, '1.0.0')!
		reopen_mixed_data(false)!
		maintain_installed('remove', document.packages, document)!
		verify_mixed_audit(document, '')!
		for id in document.packages {
			if os.exists(store + '/current/share/applications/vinix-' + id + '.desktop') {
				return error('removed application launcher remains active: ' + id)
			}
		}
		os.rename(repository + '/objects', '/root/mixed-release-hidden-objects')!
		maintain_installed('install', document.packages, document)!
		verify_mixed_audit(document, '1.1.0')!
		reopen_mixed_data(true)!
		for path in [mixed_database, mixed_media, declaration] {
			if inspect_installed_file(path, device)! != previous.files[path]! {
				return error('maintenance changed retained private data or the release baseline: ' + path)
			}
		}
		checkpoint_installed('cached')!
		println('HWTEST PASS mixed release update rollback uninstall and cached reinstall')
	} else if previous.phase == 'cached' {
		verify_mixed_audit(document, '1.1.0')!
		reopen_mixed_data(true)!
		println('HWTEST PASS mixed release cached generation and private data survived cold boot')
	} else {
		return error('unexpected installed checkpoint phase')
	}
	poweroff_installed()!
	return true
}

fn poweroff_installed() ! {
	C.sync()
	C.reboot(0x4321fedc)
	return error('guest poweroff returned')
}
