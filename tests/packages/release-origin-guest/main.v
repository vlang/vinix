// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import net
import os
import time
import tools.packages.pkgprotocol

#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>

fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int

const store = '/var/lib/vinix-packages'
const config = '/etc/vinix-packages/config.json'
const checkpoint_path = '/root/release-origin-checkpoint.json'
const lock_path = pkgprotocol.image_applications_path
const assets = '/usr/share/release-origin/'
const runtime_id = 'org.vinix.sqlite-runtime'

struct Checkpoint {
	phase   string
	files   map[string]string
	current string
}

fn require(condition bool, reason string) ! {
	if !condition { return error(reason) }
}

fn run_program(program string, args []string, status int, diagnostic string) !string {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	if child.code != status || !output.contains(diagnostic) {
		return error('unexpected ${program} ${args.join(' ')} status ${child.code}: ${output}')
	}
	return output
}

fn package_command(args []string, status int, diagnostic string) !string {
	output := run_program('/usr/bin/vinix-package', args, status, diagnostic)!
	println('HWTEST INFO package command ${args.join(' ')} status ${status}')
	return output
}

fn installed_root() ! {
	device := (os.stat('/')!).dev
	require(os.read_file('/proc/mounts')!.split_into_lines().any(it.starts_with('/dev/root / ext2 ')),
		'guest requires the installer-selected disk root')!
	require(os.read_file('/.vinix-image-id')!.trim_space() == 'vinix-release-origin-installed-1',
		'installed disk has the wrong release origin image ID')!
	for file in ['/sbin/init', '/usr/bin/vinix-package', '/usr/bin/curl', config, lock_path,
		assets + 'ca.pem']! {
		info := os.lstat(file)!
		require(info.dev == device && info.uid == 0 && info.nlink == 1 && info.mode & 0o170022 == 0o100000,
			'expected controlled input on installed root: ' + file)!
	}
}

fn checkpoint(phase string) !Checkpoint {
	device := (os.stat('/')!).dev
	mut files := map[string]string{}
	for file in [config, lock_path, store + '/catalog.json', store + '/trust-history.json',
		store + '/current/state.json']! {
		info := os.lstat(file)!
		require(info.dev == device && info.uid == 0 && info.nlink == 1 && info.mode & 0o170022 == 0o100000,
			'expected controlled retained state on installed root: ' + file)!
		files[file] = sha256.hexhash(os.read_file(file)!)
	}
	return Checkpoint{ phase: phase, files: files, current: os.readlink(store + '/current')! }
}

fn audit(document pkgprotocol.DeploymentDocument, updated bool) ! {
	result := package_command(['--json', 'deployment-audit', lock_path], if updated { 3 } else { 0 }, '')!
	mut report := pkgprotocol.decode_deployment_audit(result)!
	defer { report.close() }
	require(report.architecture == document.architecture && report.rows.len == 10 && report.matches == !updated,
		'deployment audit differs from the installed release')!
	for row in report.rows {
		if updated && row.id == runtime_id {
			require(row.status == 'changed' && row.expected_version == '1.0.0' && row.installed_version == '1.1.0'
				&& row.differences == ['metadata_sha256', 'version'], 'unexpected SQLite runtime change')!
		} else {
			require(row.status == 'match', 'unexpected change to ' + row.id)!
		}
	}
	println('HWTEST INFO deployment audit ' + result.trim_space())
}

fn install(document pkgprotocol.DeploymentDocument) ! {
	require(!os.exists(store + '/current') && !os.is_link(store + '/current'), 'the disk already has an active package generation')!
	package_command(['--offline', 'update'], 0, '')!
	mut review := pkgprotocol.decode_review(package_command(['--offline', 'deployment-review',
		lock_path], 0, '')!)!
	defer { review.close() }
	require(review.operation == 'deploy' && review.generation == 0 && review.requested == document.packages
		&& review.rows.len == 10 && review.rows.all(it.action == 'install'), 'unexpected initial release deployment review')!
	package_command(['--offline', 'deployment-apply', review.fingerprint, lock_path], 0, '')!
	package_command(['--json', 'verify'], 0, '')!
	audit(document, false)!
	os.write_file(checkpoint_path, json2.encode(checkpoint('offline')!) + '\n')!
	println('HWTEST PASS seven release roots installed offline on a clean disk')
}

fn ready(endpoint string) ! {
	for _ in 0 .. 45 {
		mut conn := net.dial_tcp(endpoint) or {
			time.sleep(time.second)
			continue
		}
		conn.close()!
		return
	}
	return error('guest could not reach the loopback TLS repository')
}

fn reject_replay(endpoint string, id string, key string) ! {
	package_command(['repo-review', 'enroll', id, 'https://' + endpoint + '/origin/older', key],
		1, 'repository rollback or sequence equivocation refused')!
}

fn migrate(document pkgprotocol.DeploymentDocument, previous Checkpoint, endpoint string, id string, key string) ! {
	audit(document, false)!
	version := run_program('/usr/bin/curl', ['--disable', '--version'], 0, 'OpenSSL/')!
	println('HWTEST INFO ' + version.split_into_lines()[0])
	ready(endpoint)!
	url := 'https://' + endpoint + '/origin/online'
	args := ['enroll', id, url, key]
	package_command(['--offline', 'repo-review', ...args], 1, 'offline mode')!
	mut review := pkgprotocol.decode_repository_review(package_command(['repo-review', ...args], 0, '')!)!
	defer { review.close() }
	require(review.id == id && review.url == url && review.public_key == key && review.previous_public_key == key
		&& review.previous_url == 'file:///usr/share/vinix-packages/repositories/' + id
		&& review.sequence == 2 && review.remembered_sequence == 1, 'unexpected repository transition review')!
	package_command(['repo-apply', review.fingerprint, ...args], 0, '')!
	changed := checkpoint('offline')!
	for file in [lock_path, store + '/catalog.json', store + '/current/state.json']! {
		require(changed.files[file]! == previous.files[file]!, 'enrollment changed ' + file)!
	}
	require(changed.current == previous.current, 'enrollment activated a generation')!
	package_command(['update'], 0, '')!
	mut upgrade := pkgprotocol.decode_review(package_command(['review', 'upgrade'], 0, '')!)!
	defer { upgrade.close() }
	require(upgrade.rows.len == 10 && upgrade.rows.filter(it.action == 'update').map(it.id) == [runtime_id],
		'unexpected signed upgrade review')!
	package_command(['apply', upgrade.fingerprint, 'upgrade'], 0, '')!
	package_command(['--json', 'verify'], 0, '')!
	audit(document, true)!
	mut rollback := pkgprotocol.decode_review(package_command(['review', 'rollback'], 0, '')!)!
	defer { rollback.close() }
	package_command(['apply', rollback.fingerprint, 'rollback'], 0, '')!
	package_command(['--json', 'verify'], 0, '')!
	audit(document, false)!
	retained := checkpoint('online')!
	require(retained.files[lock_path]! == previous.files[lock_path]! && retained.current != previous.current,
		'rollback changed the release declaration or failed to activate')!
	reject_replay(endpoint, id, key)!
	require(checkpoint('online')! == retained, 'refused replay changed installed state')!
	os.write_file(checkpoint_path, json2.encode(retained) + '\n')!
	println('HWTEST PASS HTTPS origin has the same publisher, updates SQLite and refuses replay after rollback')
}

fn run() ! {
	installed_root()!
	mut document := pkgprotocol.decode_deployment_document(os.read_file(lock_path)!)!
	defer { document.close() }
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	require(document.format == 2 && document.architecture == arch && document.packages.len == 7
		&& document.locked.len == 10, 'unexpected installed release declaration')!
	if !os.exists(checkpoint_path) {
		install(document)!
		return
	}
	previous := json2.decode[Checkpoint](os.read_file(checkpoint_path)!)!
	require(checkpoint(previous.phase)! == previous, 'cold boot changed retained disk state')!
	endpoint := os.read_file(assets + 'endpoint')!.trim_space()
	os.setenv('CURL_CA_BUNDLE', assets + 'ca.pem', true)
	publisher := document.locked[0]
	if previous.phase == 'offline' {
		migrate(document, previous, endpoint, publisher.repository, publisher.public_key)!
	} else {
		require(previous.phase == 'online', 'unexpected installed checkpoint')!
		package_command(['--json', 'verify'], 0, '')!
		audit(document, false)!
		ready(endpoint)!
		reject_replay(endpoint, publisher.repository, publisher.public_key)!
		require(checkpoint('online')! == previous, 'post-boot replay changed retained bytes')!
		println('HWTEST PASS restored release and HTTPS trust survived cold boot')
	}
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	run() or { eprintln('HWTEST FAIL installed release origin: ${err}') }
	C.sync()
	C.reboot(0x4321fedc)
	for { time.sleep(time.second) }
}
