// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// Single owner. Do not copy, concurrently use/close, or transfer the borrowed
// review. This excludes cooperating managed launches while live, not arbitrary
// same-account writers. Requires an existing prefix; capturing may create
// launch/server coordination files and directories, never builtin bindings.
pub struct IdleBindingReview {
pub mut:
	review BindingReview
mut:
	guard LaunchGuard
	server ServerDirectory
	data string
	builtins string
	store string
	system_fd int = -1
	assets_fd int = -1
}

pub fn (mut capture IdleBindingReview) close() {
	capture.review.close()
	capture.server.close()
	capture.guard.close()
	if capture.system_fd >= 0 { C.close(capture.system_fd) }
	if capture.assets_fd >= 0 { C.close(capture.assets_fd) }
	unsafe { capture.data.free(); capture.builtins.free(); capture.store.free() }
	capture = IdleBindingReview{}
}

pub fn capture_idle_binding_review(data string, builtins string, store string) !IdleBindingReview {
	data_fd := absolute_directory(data)!
	mut prefix := Prefix{path: data + '/wine', data: data_fd}
	defer { prefix.close() }
	directory(prefix.data, u32(C.geteuid()), true)!
	prefix.directory = review_child(prefix.data, 'wine')!
	info := directory(prefix.directory, u32(C.geteuid()), true)!
	prefix.device = u64(info.st_dev); prefix.inode = u64(info.st_ino)
	mut capture := IdleBindingReview{data: data.clone(), builtins: builtins.clone(), store: store.clone()}
	mut accepted := false
	defer { if !accepted { capture.close() } }
	capture.guard = prefix.acquire_launch(data)!
	capture.server = capture.guard.prepare_server_directory(data)!
	system_path := data + '/wine/drive_c/windows/system32'
	defer { unsafe { system_path.free() } }
	capture.system_fd = absolute_directory(system_path)!
	capture.assets_fd = absolute_directory(builtins)!
	capture.review = review_prefix_bindings(data, builtins, store)!
	capture.recheck()!
	accepted = true
	return capture
}

fn binding_directory_unchanged(held int, path string, private bool) ! {
	current := absolute_directory(path)!
	defer { C.close(current) }
	a := directory(held, u32(C.geteuid()), private)!
	b := directory(current, u32(C.geteuid()), private)!
	if a.st_dev != b.st_dev || a.st_ino != b.st_ino {
		return error('Wine binding review captured directory identity changed')
	}
}

// Re-run structural inspection between idle/namespace checks, retaining the
// guard. This does not authenticate runtime bytes or freeze concurrent writes.
// Migration application still needs authenticated inputs, fresh checks at use,
// atomic binding changes and an interruption recovery policy.
pub fn (capture &IdleBindingReview) recheck() ! {
	capture.server.require_idle(&capture.guard, capture.data)!
	system_path := capture.data + '/wine/drive_c/windows/system32'
	defer { unsafe { system_path.free() } }
	binding_directory_unchanged(capture.system_fd, system_path, true)!
	binding_directory_unchanged(capture.assets_fd, capture.builtins, false)!
	mut current := review_prefix_bindings(capture.data, capture.builtins, capture.store)!
	defer { current.close() }
	if current.generation != capture.review.generation || current.prior_generation != capture.review.prior_generation
		|| current.runtime_id != capture.review.runtime_id || current.bindings != capture.review.bindings {
		return error('Wine binding review changed while captured')
	}
	capture.server.require_idle(&capture.guard, capture.data)!
	binding_directory_unchanged(capture.system_fd, system_path, true)!
	binding_directory_unchanged(capture.assets_fd, capture.builtins, false)!
}
