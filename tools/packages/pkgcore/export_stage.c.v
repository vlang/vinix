// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.rand
import os

// One owner for the captured parent, private root and names. Published trees
// are never retired, including when the final directory flush fails.
struct ExportStage {
	parent int = -1
	root int = -1
	parent_path string
	path string
	name string
	kind string
	parent_device u64
	parent_inode u64
	device u64
	inode u64
mut:
	published bool
}

fn C.mkdirat(int, &char, u32) int

fn create_export_stage(parent_path string, prefix string, kind string) !ExportStage {
	check_export_parent(parent_path, kind)!
	parent := C.open(parent_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if parent < 0 { return error('cannot capture ${kind} parent directory') }
	mut accepted := false
	defer { if !accepted { C.close(parent) } }
	mut folder := C.stat{}
	if C.fstat(parent, unsafe { &folder }) != 0 || !atomic_parent_matches(parent_path, u64(folder.st_dev), u64(folder.st_ino)) {
		return error('${kind} parent directory changed before staging')
	}
	for _ in 0 .. 16 {
		bytes := rand.bytes(16)!
		suffix := bytes.hex()
		name := prefix + '-' + suffix
		unsafe { bytes.free(); suffix.free() }
		mut transferred := false
		defer { if !transferred { unsafe { name.free() } } }
		if C.mkdirat(parent, name.str, 0o700) != 0 {
			if C.errno == C.EEXIST { continue }
			return error('cannot create private ${kind} staging directory; check permissions and disk space')
		}
		root := C.openat(parent, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		mut info := C.stat{}
		if root < 0 { return error('cannot capture new ${kind} stage; retain ${parent_path}/${name} for inspection') }
		if C.fstat(root, unsafe { &info }) != 0 || info.st_uid != u32(C.geteuid()) || info.st_mode & 0o7777 != 0o700
			|| info.st_dev != folder.st_dev {
			C.close(root)
			return error('new ${kind} stage changed; retain ${parent_path}/${name} for inspection')
		}
		stage := ExportStage{ parent: parent, root: root, parent_path: parent_path.clone(), path: if parent_path == '/' { parent_path + name } else { parent_path + '/' + name },
			name: name, kind: kind.clone(), parent_device: u64(folder.st_dev), parent_inode: u64(folder.st_ino),
			device: u64(info.st_dev), inode: u64(info.st_ino) }
		stage.check() or {
			// The named root may have been replaced. Only descriptors and owned
			// strings can retire until the captured name is admitted again.
			C.close(root)
			unsafe { stage.parent_path.free(); stage.path.free(); stage.kind.free() }
			return err
		}
		accepted = true; transferred = true
		return stage
	}
	return error('cannot allocate a unique ${kind} staging directory')
}

fn (stage ExportStage) check() ! {
	if !atomic_parent_matches(stage.parent_path, stage.parent_device, stage.parent_inode) {
		return error('${stage.kind} parent path changed; restore it before retrying')
	}
	check_export_parent(stage.parent_path, stage.kind)!
	mut info := C.stat{}
	if C.fstat(stage.root, unsafe { &info }) != 0 || info.st_uid != u32(C.geteuid()) || info.st_mode & 0o022 != 0 {
		return error('${stage.kind} staging root ownership or permissions changed')
	}
	check_stage_name(stage.parent, stage.name, stage.device, stage.inode) or {
		message := err.msg()
		unsafe { message.free(); err.free() }
		return error('${stage.kind} staging root identity changed; retain it for inspection')
	}
}

fn (stage ExportStage) retire() ! {
	// The generation remover inventories the captured tree before unlinking,
	// refuses foreign directories/filesystems and never follows leaf aliases.
	// Resolve through the held parent even if its visible path was replaced.
	retire_stage(stage.parent, StageTarget{ name: stage.name, device: stage.device, inode: stage.inode })!
}

fn (stage ExportStage) failure(cause IError) IError {
	if !stage.published {
		stage.retire() or {
			primary := cause.msg(); secondary := err.msg()
			message := primary + '; unpublished ' + stage.kind + ' cleanup refused at ' + stage.path + ': ' + secondary + '; retain recovery data for inspection'
			unsafe { primary.free(); secondary.free(); cause.free(); err.free() }
			return error(message)
		}
	}
	return cause
}

fn (mut stage ExportStage) publish(target string) ! {
	stage.publish_with(target, atomic_flush)!
}

// In-process fault seam; production always uses fsync on the held parent.
fn (mut stage ExportStage) publish_with(target string, flush fn (int) int) ! {
	stage.check()!
	name := target.all_after_last('/')
	parent := os.dir(target)
	defer { unsafe { name.free(); parent.free() } }
	if parent != stage.parent_path || name in ['', '.', '..']! {
		return error('${stage.kind} destination must remain in its captured parent')
	}
	if atomic_publish_new(stage.parent, stage.name, name) != 0 {
		return error('cannot publish ${stage.kind} without replacing ${target}; destination must be new and the filesystem must support exclusive atomic rename')
	}
	stage.published = true
	if flush(stage.parent) != 0 {
		return error('${stage.kind} published at ${target}, but its directory flush failed; check storage and verify the export')
	}
	if !atomic_parent_matches(stage.parent_path, stage.parent_device, stage.parent_inode) {
		return error('${stage.kind} published in its captured directory, but the parent path changed; inspect storage before retrying')
	}
}

fn (mut stage ExportStage) close() {
	if stage.root >= 0 { C.close(stage.root) }
	if stage.parent >= 0 { C.close(stage.parent) }
	unsafe { stage.parent_path.free(); stage.path.free(); stage.name.free(); stage.kind.free() }
	stage = ExportStage{}
}
