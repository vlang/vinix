// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

#include <fcntl.h>
#include <grp.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.chown(&char, int, int) int
fn C.dup2(int, int) int
fn C.fork() int
fn C.setgroups(uint, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.mount(&char, &char, &char, u64, voidptr) int
fn C.umount(&char) int
fn C.reboot(int) int
fn C.sync()

const config = '/etc/vinix-packages/config.json'
const assets = '/usr/share/installed-media'
const store = '/var/lib/vinix-packages'
const phase_path = '/root/offline-media.phase'
const checkpoint_path = '/root/offline-media.state'
const mount_root = '/media/offline'
const media_directory = mount_root + '/release'
const bundled_lock = media_directory + '/' + pkgprotocol.deployment_mirror_filename
const home = '/home/offline-fixture'
const saved_lock = home + '/approved release.json'
const reviewed = home + '/review.json'
const sandbox_path = '/usr/bin/vinix-sandbox'

struct ImportBinding {
	receipt_sha256 string
	deployment_sha256 string
	configuration_sha256 string
	sandbox_sha256 string
}

fn require(condition bool, reason string) ! {
	if !condition { return error(reason) }
}

fn package_exchange(args []string, input string) (int, string) {
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn package_command(args []string, status int, diagnostic string) !string {
	code, output := package_exchange(['--offline', ...args], '')
	require(code == status && output.contains(diagnostic), 'package ${args[0]} returned ${code}: ${output}')!
	return output
}

fn as_ordinary(operation fn () !) ! {
	pid := C.fork()
	require(pid >= 0, 'cannot fork ordinary Software client')!
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(1) }
		operation() or { eprintln(err); C._exit(1) }
		C._exit(0)
	}
	mut status := 0
	require(C.waitpid(pid, &status, 0) == pid && status == 0, 'ordinary Software client failed')!
}

fn installed_root(binding ImportBinding) !u64 {
	device := u64((os.stat('/')!).dev)
	require(os.read_file('/proc/mounts')!.split_into_lines().any(it.starts_with('/dev/root / ext2 '))
		&& os.read_file('/.vinix-image-id')!.trim_space() == 'vinix-installed-offline-media-1',
		'expected the installer-selected VJFS root')!
	for path in ['/sbin/init', '/usr/bin/vinix-package', config, assets + '/receipt.json'] {
		info := os.lstat(path)!
		require(u64(info.dev) == device && info.uid == 0 && info.nlink == 1 && info.mode & 0o170022 == 0o100000,
			'expected an installed image input: ' + path)!
	}
	if binding.sandbox_sha256 != '' {
		info := os.lstat(sandbox_path)!
		require(u64(info.dev) == device && info.uid == 0 && info.nlink == 1 && info.mode & 0o177777 == 0o100755
			&& sha256.hexhash(os.read_file(sandbox_path)!) == binding.sandbox_sha256,
			'the package sandbox does not match the staged executable on the installed root')!
	}
	require(sha256.hexhash(os.read_file(config)!) == binding.configuration_sha256
		&& sha256.hexhash(os.read_file(assets + '/receipt.json')!) == binding.receipt_sha256,
		'installed publisher configuration or receipt changed')!
	require(!os.exists('/usr/share/vinix-packages/repositories'), 'a bundled repository would invalidate the cache-only control')!
	return device
}

fn mount_media(device u64, digest string) ! {
	os.mkdir_all(mount_root)!
	for name in os.ls('/dev')!.sorted() {
		path := '/dev/' + name
		if (os.lstat(path)!).mode & 0o170000 != 0o060000 { continue }
		if C.mount(path.str, mount_root.str, c'ext2', 1, unsafe { nil }) != 0 { continue }
		if os.is_file(bundled_lock) && u64((os.stat(bundled_lock)!).dev) != device
			&& sha256.hexhash(os.read_file(bundled_lock)!) == digest {
			println('HWTEST INFO read-only offline medium mounted from ' + path)
			return
		}
		require(C.umount(mount_root.str) == 0, 'cannot unmount a non-media device')!
	}
	return error('could not mount the receipt-bound offline medium')
}

fn import_media(binding ImportBinding, device u64) ! {
	mount_media(device, binding.deployment_sha256)!
	args := ['update-media', media_directory, assets + '/receipt.json']
	package_command([...args, '0'.repeat(64)], 1, 'ISO package receipt SHA-256 differs')!
	require(!os.exists(store + '/catalog.json') && !os.exists(store + '/trust-history.json')
		&& (!os.exists(store + '/objects') || os.ls(store + '/objects')!.len == 0),
		'a refused receipt changed authenticated package state')!
	package_command([...args, binding.receipt_sha256], 0, '')!
	as_ordinary(fn [binding] () ! {
		mut receipt := pkgprotocol.decode_deployment_media_saved(package_command(['--json', 'deployment-media-save',
			media_directory, saved_lock, binding.deployment_sha256], 0, '')!)!
		defer { receipt.close() }
		require(receipt.destination == saved_lock && receipt.sha256 == binding.deployment_sha256
			&& receipt.roots == 7 && receipt.packages == 10, 'ordinary media save receipt differs from the approved release')!
	})!
	require(os.read_file(saved_lock)! == os.read_file(bundled_lock)!, 'saved lock differs from the mounted media')!
	require(!os.is_link(store + '/current'), 'media import activated packages')!
	require(C.umount(mount_root.str) == 0, 'cannot unmount the offline medium')!
}

fn checked_saved_lock(binding ImportBinding, device u64) !pkgprotocol.DeploymentDocument {
	info := os.lstat(saved_lock)!
	text := os.read_file(saved_lock)!
	require(u64(info.dev) == device && info.uid == 1000 && info.gid == 1000
		&& info.nlink == 1 && info.mode & 0o170000 == 0o100000 && sha256.hexhash(text) == binding.deployment_sha256,
		'ordinary saved lock did not survive on the installed filesystem')!
	document := pkgprotocol.decode_deployment_document(text)!
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	require(document.format == 2 && document.architecture == arch && document.packages.len == 7
		&& document.locked.len == 10, 'expected seven release applications and ten locked packages')!
	return document
}

fn install_from_cache(binding ImportBinding, document pkgprotocol.DeploymentDocument) ! {
	as_ordinary(fn [binding] () ! {
		package_command(['deployment-add-review', saved_lock, '0'.repeat(64)], 1, 'SHA-256 differs')!
		result := package_command(['deployment-add-review', saved_lock, binding.deployment_sha256], 0, '')!
		os.write_file(reviewed, result)!
	})!
	mut review := pkgprotocol.decode_review(os.read_file(reviewed)!)!
	defer { review.close() }
	require(review.operation == 'deploy-add' && review.generation == 0 && review.requested == document.packages
		&& review.rows.map(it.id) == document.locked.map(it.id) && review.rows.all(it.action == 'install')
		&& !os.is_link(store + '/current'), 'ordinary review changed activation or differed from the locked closure')!
	package_command(['deployment-add-apply', review.fingerprint, saved_lock, binding.deployment_sha256], 0, '')!
}

fn verify_generation(binding ImportBinding, document pkgprotocol.DeploymentDocument) ! {
	mut coverage := pkgprotocol.decode_deployment_audit(package_command(['--json', 'deployment-add-audit',
		saved_lock, binding.deployment_sha256], 0, '')!)!
	defer { coverage.close() }
	require(coverage.matches && coverage.generation != 0 && coverage.rows.map(it.id) == document.locked.map(it.id),
		'installed generation differs from the complete saved deployment lock')!
	package_command(['verify'], 0, '')!
}

fn run() ! {
	binding := json2.decode[ImportBinding](os.read_file(assets + '/binding.json')!)!
	device := installed_root(binding)!
	phase := if os.exists(phase_path) { os.read_file(phase_path)! } else { '' }
	match phase {
		'' {
			require(!os.exists(store) && !os.exists(bundled_lock), 'fresh disk already has package state or offline media')!
			os.mkdir_all('/home')!
			os.mkdir(home, mode: 0o700)!
			require(C.chown(home.str, 1000, 1000) == 0, 'cannot prepare the ordinary destination')!
			os.write_file(phase_path, 'attach')!
			println('HWTEST PASS clean disk root before offline media attachment')
		}
		'attach' {
			import_media(binding, device)!
			os.write_file(phase_path, 'detached')!
			println('HWTEST PASS receipt-bound media imported and UID 1000 saved its lock on the installed disk')
		}
		'detached', 'verified' {
			require(!os.exists(bundled_lock), 'the release medium must be absent')!
			mut document := checked_saved_lock(binding, device)!
			defer { document.close() }
			if phase == 'detached' { install_from_cache(binding, document)! }
			verify_generation(binding, document)!
			if binding.sandbox_sha256 != '' { launch_installed_apps(phase == 'detached', device)! }
			state := sha256.hexhash(os.read_file(store + '/current/state.json')!)
			if phase == 'detached' {
				os.write_file(checkpoint_path, state)!
				os.write_file(phase_path, 'verified')!
				println('HWTEST PASS detached media and cold boot allowed exact reviewed cache-only installation')
			} else {
				require(state == os.read_file(checkpoint_path)!, 'installed generation changed across cold boot')!
				println('HWTEST PASS seven release roots and their complete closure survived another cold boot')
			}
		}
		else { return error('unexpected installed offline media checkpoint') }
	}
	C.sync()
	C.reboot(0x4321fedc)
	return error('guest shutdown returned')
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	run() or { eprintln('HWTEST FAIL ${err}'); C.reboot(0x4321fedc); exit(1) }
}
