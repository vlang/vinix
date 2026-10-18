// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn C.getenv(&char) &char

fn import_temporary_directory() string {
	// Match os.temp_dir on the supported hosts without allocating its ignored
	// TMPDIR value before the macOS early return.
	$if macos { return '/tmp'.clone() }
	value := C.getenv(c'TMPDIR')
	if value == unsafe { nil } || unsafe { value[0] } == 0 { return '/tmp'.clone() }
	return unsafe { cstring_to_vstring(value) }
}

// This private import tree is independently owned from its source and published
// package. Retire only admitted entries through the captured parent/root.
struct ImportWorkspace {
mut:
	stage ExportStage
	payload ProfileDirectory
	manifest int = -1
	manifest_bytes u64
	manifest_digest string
}

fn create_import_workspace() !ImportWorkspace {
	temporary := import_temporary_directory()
	defer { unsafe { temporary.free() } }
	parent := publisher_real_path(temporary)!
	defer { unsafe { parent.free() } }
	return create_import_workspace_at(parent)
}

fn create_import_workspace_at(parent string) !ImportWorkspace {
	process := os.getpid().str()
	prefix := 'vinix-pack-root-' + process
	defer { unsafe { process.free(); prefix.free() } }
	mut stage := create_export_stage(parent, prefix, 'prepared import')!
	mut accepted := false
	defer { if !accepted { stage.close() } }
	// An unadmitted child is retained for inspection if capture fails.
	payload := create_profile_directory(stage, 'payload') or {
		cause := err.msg()
		message := 'cannot initialize private import workspace at ' + stage.path + ': ' + cause + '; retain recovery data for inspection'
		unsafe { cause.free(); err.free() }
		return error(message)
	}
	accepted = true
	return ImportWorkspace{ stage: stage, payload: payload }
}

fn (work ImportWorkspace) check_manifest() ! {
	mut info := C.stat{}
	if !atomic_name_matches(work.stage.root, 'manifest.json', work.manifest)
		|| C.fstat(work.manifest, unsafe { &info }) != 0 || info.st_uid != u32(C.geteuid())
		|| info.st_mode & 0o7777 != 0o644 || info.st_nlink != 1 || info.st_size < 0 || u64(info.st_size) != work.manifest_bytes {
		return error('private import manifest identity, mode or length changed; retain recovery data')
	}
	if C.lseek(work.manifest, 0, C.SEEK_SET) != 0 { return error('cannot seek private import manifest; retain recovery data') }
	digest := hash_opened(work.manifest, work.manifest_bytes, 'private import manifest', HashReadOptions{})!
	defer { unsafe { digest.free() } }
	if digest != work.manifest_digest { return error('private import manifest contents changed; retain recovery data') }
}

fn (work ImportWorkspace) check_children() ! {
	work.payload.check(work.stage)!
	// dup shares a directory cursor. Each repeated admission and failure
	// cleanup needs a new open description so added entries cannot be missed.
	directory := C.openat(work.stage.root, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if directory < 0 { return error('cannot enumerate private import workspace; retain recovery data') }
	defer { C.close(directory) }
	names := import_names(directory)!
	defer { unsafe { names.free() } }
	for name in names {
		if name != 'payload' && (name != 'manifest.json' || work.manifest < 0) {
			return error('private import workspace contains an unadmitted entry; retain recovery data: ' + name)
		}
	}
	if work.manifest >= 0 { work.check_manifest()! }
}

fn (work ImportWorkspace) check() ! {
	work.stage.check()!
	work.check_children()!
}

fn (work ImportWorkspace) checkpoint(phase string, options PackSourceOptions) ! {
	options.checkpoint(phase, work.stage.path)!
	work.check()!
}

fn (mut work ImportWorkspace) write_manifest(text string) ! {
	work.check()!
	path := work.stage.path + '/manifest.json'
	defer { unsafe { path.free() } }
	atomic_write_new(path, text)!
	work.manifest = C.openat(work.stage.root, c'manifest.json', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if work.manifest < 0 { return error('cannot capture private import manifest; retain recovery data') }
	work.manifest_bytes = u64(text.len)
	work.manifest_digest = index_digest(text)
	work.check()!
}

fn (work ImportWorkspace) retire() ! {
	// A moved visible parent does not redirect cleanup. Replaced payload or
	// manifest identities and unexpected root entries preserve the whole tree.
	work.check_children()!
	work.stage.retire()!
}

fn (work ImportWorkspace) failure(cause IError) IError {
	work.retire() or {
		primary := cause.msg(); secondary := err.msg()
		message := primary + '; private import cleanup refused at ' + work.stage.path + ': ' + secondary + '; retain recovery data for inspection'
		unsafe { primary.free(); secondary.free(); cause.free(); err.free() }
		return error(message)
	}
	return cause
}

fn (mut work ImportWorkspace) close() {
	if work.manifest >= 0 { C.close(work.manifest) }
	if work.payload.fd >= 0 { C.close(work.payload.fd) }
	unsafe { work.manifest_digest.free() }
	work.stage.close()
	work = ImportWorkspace{}
}
