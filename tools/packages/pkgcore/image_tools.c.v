// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const image_tool_names = ['vinix-package', 'vinix-session', 'vinix-linux-runner']!
const image_tool_parents = ['/usr/bin', '/usr/sbin', '/usr/libexec/vinix']!

// A private compiler workspace bound to one admitted image root. Compilation
// may use directory(), but publication captures every output before any rename.
pub struct ImageToolBuild {
	stage ExportStage
	root string
	architecture string
	device u64
	inode u64
}

struct ImageToolOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
	write fn (int, voidptr, usize) isize = atomic_write_bytes
	flush fn (int) int = atomic_flush
}

pub fn (configuration &ImageConfiguration) prepare_tool_build() !ImageToolBuild {
	temporary := import_temporary_directory()
	defer { unsafe { temporary.free() } }
	parent := publisher_real_path(temporary)!
	defer { unsafe { parent.free() } }
	return configuration.prepare_tool_build_at(parent)
}

fn (configuration &ImageConfiguration) prepare_tool_build_at(parent string) !ImageToolBuild {
	if !image_configuration_root_matches(configuration.root, configuration.device, configuration.inode) {
		return error('package image root changed before tool compilation')
	}
	stage := create_export_stage(parent, '.vinix-package-build', 'image tool compiler workspace')!
	return ImageToolBuild{ stage: stage, root: configuration.root.clone(), architecture: configuration.architecture.clone(),
		device: configuration.device, inode: configuration.inode }
}

pub fn (build &ImageToolBuild) check() ! {
	if build.root == '' || !image_configuration_root_matches(build.root, build.device, build.inode) {
		return error('package image root changed during tool staging; restore it and retry')
	}
	build.stage.check()!
}

// The caller owns this path and must check() before and after compiler calls.
pub fn (build &ImageToolBuild) directory() !string { build.check()!; return build.stage.path.clone() }

fn (build &ImageToolBuild) binary(name string) ![]u8 {
	fd := C.openat(build.stage.root, name.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NONBLOCK | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot capture compiled image tool without following aliases: ' + name) }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000
		|| info.st_uid != u32(C.geteuid()) || info.st_mode & 0o022 != 0 || info.st_mode & 0o111 == 0
		|| info.st_nlink != 1 || info.st_size < 64 || info.st_size > 64 * 1024 * 1024 {
		return error('compiled image tool must be an owned ordinary single-link executable of 64 bytes to 64 MiB: ' + name)
	}
	mut data := []u8{len: int(info.st_size)}
	mut accepted := false
	defer { if !accepted { unsafe { data.free() } } }
	digest := hash_opened(fd, u64(info.st_size), name, HashReadOptions{})!
	defer { unsafe { digest.free() } }
	profile_elf(build.stage.root, name, build.architecture, 'static', true)!
	profile_read_at(fd, 0, mut data)!
	captured_digest := index_digest(unsafe { tos(data.data, data.len) })
	defer { unsafe { captured_digest.free() } }
	if digest != captured_digest { return error('compiled image tool changed contents during capture: ' + name) }
	mut after := C.stat{}
	mut named := C.stat{}
	if C.fstat(fd, unsafe { &after }) != 0 || C.fstatat(build.stage.root, name.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_dev != info.st_dev || named.st_ino != info.st_ino || named.st_size != info.st_size
		|| named.st_mode != info.st_mode || named.st_nlink != 1 || named.st_uid != info.st_uid
		|| after.st_size != info.st_size || after.st_mode != info.st_mode || after.st_nlink != 1 {
		return error('compiled image tool changed during capture: ' + name)
	}
	// Check the captured bytes, rather than reopening the compiler output. The
	// trusted compiler supplies the executable; this is target/header admission.
	identity := [u8(127), `E`, `L`, `F`, 2, 1, 1]!
	for i, byte in identity { if data[i] != byte { return error('compiler produced an invalid ELF64 image tool: ' + name) } }
	machine := if build.architecture == 'aarch64' { 183 } else { 62 }
	if data[16] != 2 || data[17] != 0 || int(data[18]) + (int(data[19]) << 8) != machine
		|| data[20] != 1 || data[21] != 0 || data[22] != 0 || data[23] != 0 || data[52] != 64 || data[53] != 0 {
		return error('compiler produced the wrong target or nonstatic ELF image tool: ' + name)
	}
	accepted = true
	return data
}

fn image_tool_parent(root int, relative string, device u64) !int {
	mut directory := C.dup(root)
	if directory < 0 { return error('cannot retain image tool root') }
	mut accepted := false
	defer { if !accepted { C.close(directory) } }
	parts := relative.split('/')
	defer { unsafe { parts.free() } }
	for name in parts {
		if name == '' { continue }
		if C.mkdirat(directory, name.str, 0o755) != 0 && C.errno != C.EEXIST { return error('cannot create image tool parent: ' + relative) }
		next := C.openat(directory, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if next < 0 { return error('image tool parents must be ordinary controlled directories: ' + relative) }
		C.close(directory); directory = next
		mut info := C.stat{}
		if C.fstat(directory, unsafe { &info }) != 0 || u64(info.st_dev) != device || info.st_mode & 0o022 != 0
			|| (info.st_uid != 0 && info.st_uid != u32(C.geteuid())) {
			return error('image tool parents must be ordinary controlled directories: ' + relative)
		}
	}
	accepted = true
	return directory
}

struct ImageToolOutput {
	parent int = -1
	fd int = -1
	path string
	leaf string
	device u64
	inode u64
	bytes int
mut:
	published bool
}

fn (mut output ImageToolOutput) close() {
	if output.fd >= 0 {
		if !output.published && atomic_name_matches(output.parent, output.leaf, output.fd) { C.unlinkat(output.parent, output.leaf.str, 0) }
		C.close(output.fd)
	}
	if output.parent >= 0 { C.close(output.parent) }
	unsafe { output.path.free(); output.leaf.free() }
	output = ImageToolOutput{}
}

fn (output &ImageToolOutput) check() ! {
	if !atomic_parent_matches(output.path, output.device, output.inode) { return error('image tool parent changed before publication: ' + output.path) }
	mut parent := C.stat{}
	if C.fstat(output.parent, unsafe { &parent }) != 0 || parent.st_mode & 0o022 != 0
		|| (parent.st_uid != 0 && parent.st_uid != u32(C.geteuid())) {
		return error('image tool parent ownership or permissions changed: ' + output.path)
	}
	check_atomic_temporary(output.parent, output.leaf, output.fd, output.bytes)!
	mut info := C.stat{}
	if C.fstat(output.fd, unsafe { &info }) != 0 || info.st_mode & 0o7777 != 0o755 { return error('image tool temporary executable mode changed') }
}

pub fn (build &ImageToolBuild) publish() ! { build.publish_with(ImageToolOptions{})! }

fn (build &ImageToolBuild) publish_with(options ImageToolOptions) ! {
	build.check()!
	mut binaries := [][]u8{cap: 3}
	defer { for data in binaries { unsafe { data.free() } }; unsafe { (&array(&binaries)).free() } }
	mut needed := u64(0)
	for name in image_tool_names {
		data := build.binary(name)!
		needed += u64(data.len)
		pointer := unsafe { &data }
		unsafe { binaries.push_many(pointer, 1) }
	}
	options.checkpoint('captured', build.stage.path)!
	build.check()!
	disk_check(options.available_space(build.root)!, needed, 64 * 1024 * 1024)!
	root := capture_prepared_root(build.root, 'image tool publication')!
	defer { C.close(root) }
	mut root_info := C.stat{}
	if C.fstat(root, unsafe { &root_info }) != 0 || u64(root_info.st_dev) != build.device || u64(root_info.st_ino) != build.inode {
		return error('package image root changed before tool destination capture')
	}
	mut outputs := []ImageToolOutput{cap: 3}
	defer { for mut output in outputs { output.close() }; unsafe { (&array(&outputs)).free() } }
	for i, relative in image_tool_parents {
		parent := image_tool_parent(root, relative, build.device)!
		mut output := ImageToolOutput{ parent: parent, path: build.root + relative, bytes: binaries[i].len }
		mut accepted := false
		defer { if !accepted { output.close() } }
		mut info := C.stat{}
		if C.fstat(parent, unsafe { &info }) != 0 { return error('cannot inspect image tool destination') }
		output = ImageToolOutput{ ...output, device: u64(info.st_dev), inode: u64(info.st_ino) }
		mut existing := C.stat{}
		if C.fstatat(parent, image_tool_names[i].str, unsafe { &existing }, C.AT_SYMLINK_NOFOLLOW) == 0 {
			if existing.st_mode & 0o170000 !in [0o100000, 0o120000]! { return error('image tool destination must be a file or leaf alias: ' + image_tool_names[i]) }
		} else if C.errno != C.ENOENT { return error('cannot inspect image tool destination: ' + image_tool_names[i]) }
		fd, leaf := create_atomic_file(parent)!
		output = ImageToolOutput{ ...output, fd: fd, leaf: leaf }
		data := binaries[i]
		mut offset := 0
		for offset < data.len {
			count := options.write(fd, unsafe { &u8(data.data) + offset }, usize(data.len - offset))
			if count < 0 && C.errno == C.EINTR { continue }
			if count <= 0 || count > data.len - offset { return error('cannot write image tool temporary; check disk space') }
			offset += int(count)
		}
		if C.fchmod(fd, 0o755) != 0 || options.flush(fd) != 0 { return error('cannot flush image tool before publication; check storage') }
		output.check()!
		pointer := unsafe { &output }
		unsafe { outputs.push_many(pointer, 1) }
		accepted = true
	}
	options.checkpoint('ready', build.stage.path)!
	build.check()!
	for output in outputs { output.check()! }
	for i, mut output in outputs {
		build.check()!
		output.check()!
		if C.renameat(output.parent, output.leaf.str, output.parent, image_tool_names[i].str) != 0 { return error('cannot publish image tool: ' + image_tool_names[i] + '; image staging is incomplete') }
		output.published = true
		if options.flush(output.parent) != 0 || !atomic_parent_matches(output.path, output.device, output.inode) {
			return error('image tool saved at ' + output.path + '/' + image_tool_names[i] + ', but directory flush or identity check failed; inspect storage and retry the incomplete image build')
		}
	}
}

// A failed compiler/build may still leave a substituted recovery tree. Report
// that refusal alongside the primary failure instead of deleting the new tree.
pub fn (mut build ImageToolBuild) failure(cause IError) IError {
	defer { build.close_metadata() }
	return build.stage.failure(cause)
}

pub fn (mut build ImageToolBuild) retire() ! {
	defer { build.close_metadata() }
	if build.stage.path == '' { return }
	build.stage.retire() or {
		cause := err.msg()
		message := 'image tool workspace cleanup refused at ' + build.stage.path + ': ' + cause + '; retain recovery data for inspection'
		unsafe { cause.free(); err.free() }
		return error(message)
	}
}

fn (mut build ImageToolBuild) close_metadata() {
	build.stage.close()
	unsafe { build.root.free(); build.architecture.free() }
	build = ImageToolBuild{}
}

pub fn (mut build ImageToolBuild) close() { build.retire() or { message := err.msg(); unsafe { message.free(); err.free() } } }
