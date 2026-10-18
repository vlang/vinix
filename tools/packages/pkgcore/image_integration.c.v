// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.rand

fn C.symlinkat(&char, int, &char) int

const image_integration_sources = ['tools/packages/signing/LICENSE', 'tools/packages/appsdk/LICENSE',
	'tools/accounts/actions/packages-change', 'tools/accounts/actions/packages-launch']!
const image_integration_parents = ['usr/share/licenses/vinix-packages', 'usr/share/licenses/vinix-packages',
	'usr/bin', 'usr/share/vinix/actions', 'usr/share/vinix/actions', 'usr/share/applications']!
const image_integration_names = ['ed25519-MIT.txt', 'application-sdk-MIT.txt', 'vinix-software',
	'packages-change', 'packages-launch', 'vinix-packages']!

// Captured source bytes and image identity, independent of subsequent compiler
// activity. No destination directories are created during preparation.
pub struct ImageIntegration {
	root string
	fd int = -1
	device u64
	inode u64
	bytes [][]u8
}

struct ImageIntegrationOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
	write fn (int, voidptr, usize) isize = atomic_write_bytes
	flush fn (int) int = atomic_flush
}

fn image_integration_directory(info &C.stat, device u64) bool {
	return info.st_mode & 0o170000 == 0o040000 && u64(info.st_dev) == device && info.st_mode & 0o022 == 0
		&& (info.st_uid == 0 || info.st_uid == u32(C.geteuid()))
}

// Rewalk every component through the captured root; an alias at any image
// directory level refuses, even if it points back to the original directory.
fn image_integration_parent(root int, relative string, device u64, create bool) !int {
	mut directory := C.dup(root)
	if directory < 0 { return error('cannot retain image integration root') }
	mut accepted := false
	defer { if !accepted { C.close(directory) } }
	parts := relative.split('/')
	defer { unsafe { parts.free() } }
	for name in parts {
		if name == '' || name == '.' || name == '..' { return error('invalid image integration directory component') }
		mut created := false
		if create {
			if C.mkdirat(directory, name.str, 0o755) == 0 { created = true }
			else if C.errno != C.EEXIST { return error('cannot create image integration directory: ' + relative) }
		}
		next := C.openat(directory, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if next < 0 { return error('image integration requires ordinary controlled directories without aliases: ' + relative) }
		mut info := C.stat{}
		if C.fstat(next, unsafe { &info }) != 0 || !image_integration_directory(unsafe { &info }, device) {
			C.close(next)
			return error('image integration requires controlled directories on the image filesystem: ' + relative)
		}
		// Normalize newly created directories despite the builder's umask. Retain
		// existing controlled modes, including a more private package state root.
		if created && (C.fchmod(next, 0o755) != 0 || C.fsync(next) != 0 || C.fsync(directory) != 0) {
			C.close(next)
			return error('cannot flush newly created image integration directory: ' + relative)
		}
		C.close(directory); directory = next
	}
	accepted = true
	return directory
}

fn image_integration_read(root int, device u64, relative string) ![]u8 {
	split := relative.last_index('/') or { return error('invalid image integration source') }
	parent_name := relative[..split]; name := relative[split + 1..]
	defer { unsafe { parent_name.free(); name.free() } }
	parent := image_integration_parent(root, parent_name, device, false)!
	defer { C.close(parent) }
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot capture ordinary image integration source: ' + relative) }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000
		|| info.st_mode & 0o022 != 0 || info.st_nlink != 1 || info.st_size <= 0 || info.st_size > 64 * 1024
		|| (info.st_uid != 0 && info.st_uid != u32(C.geteuid())) {
		return error('image integration source must be a controlled single-link file of 1 byte to 64 KiB: ' + relative)
	}
	mut bytes := []u8{len: int(info.st_size)}
	mut accepted := false
	defer { if !accepted { unsafe { bytes.free() } } }
	digest := hash_opened(fd, u64(bytes.len), relative, HashReadOptions{})!
	defer { unsafe { digest.free() } }
	profile_read_at(fd, 0, mut bytes)!
	captured := index_digest(unsafe { tos(bytes.data, bytes.len) })
	defer { unsafe { captured.free() } }
	mut after := C.stat{}
	mut named := C.stat{}
	if captured != digest || C.fstat(fd, unsafe { &after }) != 0
		|| C.fstatat(parent, name.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| after.st_size != info.st_size || after.st_mode != info.st_mode || after.st_nlink != 1
		|| after.st_uid != info.st_uid || named.st_dev != info.st_dev || named.st_ino != info.st_ino
		|| named.st_size != info.st_size || named.st_mode != info.st_mode || named.st_nlink != 1 || named.st_uid != info.st_uid {
		return error('image integration source changed during capture: ' + relative)
	}
	accepted = true
	return bytes
}

pub fn (configuration &ImageConfiguration) prepare_integration(repository string) !ImageIntegration {
	mut plan := ImageIntegration{ root: configuration.root.clone(), device: configuration.device, inode: configuration.inode }
	mut accepted := false
	defer { if !accepted { plan.close() } }
	plan = ImageIntegration{ ...plan, fd: capture_prepared_root(plan.root, 'image integration')! }
	unsafe { &plan }.check()!
	source := capture_prepared_root(repository, 'image integration source')!
	defer { C.close(source) }
	mut info := C.stat{}
	if C.fstat(source, unsafe { &info }) != 0 || !image_integration_directory(unsafe { &info }, u64(info.st_dev)) {
		return error('image integration repository must be an ordinary controlled directory')
	}
	mut bytes := [][]u8{cap: 4}
	defer { if !accepted { for data in bytes { unsafe { data.free() } }; unsafe { (&array(&bytes)).free() } } }
	for path in image_integration_sources {
		data := image_integration_read(source, u64(info.st_dev), path)!
		pointer := unsafe { &data }; unsafe { bytes.push_many(pointer, 1) }
	}
	unsafe { &plan }.check()!
	plan = ImageIntegration{ ...plan, bytes: bytes }
	accepted = true
	return plan
}

fn (plan &ImageIntegration) check() ! {
	mut info := C.stat{}
	if plan.fd < 0 || !image_configuration_root_matches(plan.root, plan.device, plan.inode)
		|| C.fstat(plan.fd, unsafe { &info }) != 0 || !image_integration_directory(unsafe { &info }, plan.device)
		|| u64(info.st_ino) != plan.inode {
		return error('package image root changed during integration; restore it and retry')
	}
}

struct ImageIntegrationOutput {
	parent int = -1
	fd int = -1
	relative string
	leaf string
	device u64
	inode u64
	temporary_device u64
	temporary_inode u64
	bytes int
	link string
	keep bool
mut:
	published bool
}

fn (output &ImageIntegrationOutput) matches(name string) bool {
	if name == '' { return false }
	mut info := C.stat{}
	if C.fstatat(output.parent, name.str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| u64(info.st_dev) != output.temporary_device || u64(info.st_ino) != output.temporary_inode
		|| info.st_uid != u32(C.geteuid()) || info.st_nlink != 1 { return false }
	if output.link == '' { return output.fd >= 0 && atomic_name_matches(output.parent, name, output.fd) }
	if info.st_mode & 0o170000 != 0o120000 { return false }
	mut target := [128]u8{}
	count := C.readlinkat(output.parent, name.str, unsafe { &target[0] }, usize(target.len))
	return count == output.link.len && unsafe { tos(&target[0], int(count)) } == output.link
}

fn (mut output ImageIntegrationOutput) close() {
	if !output.published && output.matches(output.leaf) { C.unlinkat(output.parent, output.leaf.str, 0) }
	if output.fd >= 0 { C.close(output.fd) }
	if output.parent >= 0 { C.close(output.parent) }
	unsafe { output.leaf.free() }
	output = ImageIntegrationOutput{}
}

fn (plan &ImageIntegration) check_parent(output &ImageIntegrationOutput) ! {
	plan.check()!
	parent := image_integration_parent(plan.fd, output.relative, plan.device, false)!
	defer { C.close(parent) }
	mut info := C.stat{}
	if C.fstat(parent, unsafe { &info }) != 0 || u64(info.st_dev) != output.device || u64(info.st_ino) != output.inode {
		return error('image integration parent changed: ' + output.relative)
	}
}

fn (plan &ImageIntegration) check_output(output &ImageIntegrationOutput) ! {
	plan.check_parent(output)!
	if output.keep { return }
	if !output.matches(output.leaf) { return error('image integration temporary changed; inspect ' + output.relative + '/' + output.leaf) }
	if output.link == '' {
		mut info := C.stat{}
		check_atomic_temporary(output.parent, output.leaf, output.fd, output.bytes)!
		if C.fstat(output.fd, unsafe { &info }) != 0 || info.st_mode & 0o7777 != 0o644 { return error('image integration temporary permissions changed') }
	}
}

fn image_integration_link(parent int, target string) !string {
	for _ in 0 .. 16 {
		random := rand.bytes(16)!; suffix := random.hex(); unsafe { random.free() }
		name := '.package-' + suffix + '.tmp'; unsafe { suffix.free() }
		if C.symlinkat(target.str, parent, name.str) == 0 { return name }
		collision := C.errno == C.EEXIST
		unsafe { name.free() }
		if !collision { return error('cannot create private image integration link') }
	}
	return error('cannot allocate a unique image integration link')
}

pub fn (plan &ImageIntegration) publish() ! {
	plan.publish_with(ImageIntegrationOptions{}) or {
		cause := err.msg()
		message := 'package image integration incomplete; inspect saved files and rebuild before distribution: ' + cause
		unsafe { cause.free(); err.free() }
		return error(message)
	}
}

fn (plan &ImageIntegration) publish_with(options ImageIntegrationOptions) ! {
	plan.check()!
	if plan.bytes.len != 4 { return error('image integration inputs are not prepared') }
	mut needed := u64(0)
	for data in plan.bytes { needed += u64(data.len) }
	disk_check(options.available_space(plan.root)!, needed + 4096, 64 * 1024 * 1024)!
	plan.check()!
	mut outputs := []ImageIntegrationOutput{cap: 6}
	defer { for mut output in outputs { output.close() }; unsafe { (&array(&outputs)).free() } }
	for i, relative in image_integration_parents {
		plan.check()!
		parent := image_integration_parent(plan.fd, relative, plan.device, true)!
		mut output := ImageIntegrationOutput{ parent: parent, relative: relative }
		mut accepted := false
		defer { if !accepted { output.close() } }
		mut info := C.stat{}
		if C.fstat(parent, unsafe { &info }) != 0 { return error('cannot inspect image integration destination') }
		output = ImageIntegrationOutput{ ...output, device: u64(info.st_dev), inode: u64(info.st_ino) }
		present := C.fstatat(parent, image_integration_names[i].str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) == 0
		if !present && C.errno != C.ENOENT { return error('cannot inspect image integration entry') }
		if i >= 3 && present { output = ImageIntegrationOutput{ ...output, keep: true } }
		else {
			if present && info.st_mode & 0o170000 !in [0o100000, 0o120000]! { return error('image integration destination must be a file or leaf alias: ' + image_integration_names[i]) }
			if i in [2, 5]! {
				link := if i == 2 { '/usr/bin/vinix-desktop' } else { '/var/lib/vinix-packages/current/share/applications' }
				output = ImageIntegrationOutput{ ...output, leaf: image_integration_link(parent, link)!, link: link }
			} else {
				fd, leaf := create_atomic_file(parent)!
				data := plan.bytes[if i < 2 { i } else { i - 1 }]
				output = ImageIntegrationOutput{ ...output, fd: fd, leaf: leaf, bytes: data.len }
			}
			if C.fstatat(parent, output.leaf.str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0 { return error('cannot capture image integration temporary') }
			output = ImageIntegrationOutput{ ...output, temporary_device: u64(info.st_dev), temporary_inode: u64(info.st_ino) }
			path := plan.root + '/' + relative + '/' + output.leaf
			defer { unsafe { path.free() } }
			options.checkpoint('created', path)!
			if !output.matches(output.leaf) { return error('image integration temporary replaced before writing; inspect ' + path) }
			if output.fd >= 0 {
				data := plan.bytes[if i < 2 { i } else { i - 1 }]
				mut offset := 0
				for offset < data.len {
					count := options.write(output.fd, unsafe { &u8(data.data) + offset }, usize(data.len - offset))
					if count < 0 && C.errno == C.EINTR { continue }
					if count <= 0 || count > data.len - offset { return error('cannot write image integration temporary; check disk space') }
					offset += int(count)
				}
				if C.fchmod(output.fd, 0o644) != 0 || options.flush(output.fd) != 0 { return error('cannot flush image integration file before publication') }
			}
		}
		pointer := unsafe { &output }; unsafe { outputs.push_many(pointer, 1) }
		accepted = true
	}
	state := image_integration_parent(plan.fd, 'var/lib/vinix-packages', plan.device, true)!
	defer { C.close(state) }
	mut state_info := C.stat{}
	if C.fstat(state, unsafe { &state_info }) != 0 { return error('cannot capture image package state directory') }
	state_output := ImageIntegrationOutput{ relative: 'var/lib/vinix-packages', device: u64(state_info.st_dev), inode: u64(state_info.st_ino), keep: true }
	options.checkpoint('ready', plan.root)!
	for output in outputs { plan.check_output(unsafe { &output })! }
	// Recheck package state too; a substituted alias must not survive a reported
	// successful build even though no consumer state is written here.
	plan.check_parent(unsafe { &state_output })!
	for i, mut output in outputs {
		plan.check_output(unsafe { &output })!
		if output.keep { continue }
		name := image_integration_names[i]
		code := if i >= 3 { atomic_publish_new(output.parent, output.leaf, name) }
			else { C.renameat(output.parent, output.leaf.str, output.parent, name.str) }
		if code != 0 { return error('cannot publish image integration entry; existing overrides are retained: ' + name) }
		output.published = true
		path := plan.root + '/' + output.relative + '/' + name
		defer { unsafe { path.free() } }
		options.checkpoint('published', path)!
		if options.flush(output.parent) != 0 || !output.matches(name) {
			return error('image integration entry saved, but flush or final identity check failed: ' + name)
		}
		// The temporary name no longer exists. Recheck the full parent chain.
		plan.check_parent(output)!
	}
	for output in outputs { plan.check_parent(unsafe { &output })! }
	plan.check_parent(unsafe { &state_output })!
}

pub fn (mut plan ImageIntegration) close() {
	if plan.fd >= 0 { C.close(plan.fd) }
	for data in plan.bytes { unsafe { data.free() } }
	unsafe { (&array(&plan.bytes)).free(); plan.root.free() }
	plan = ImageIntegration{}
}
