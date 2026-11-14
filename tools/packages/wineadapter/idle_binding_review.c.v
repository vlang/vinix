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
}

pub fn (mut capture IdleBindingReview) close() {
	capture.review.close()
	capture.server.close()
	capture.guard.close()
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
	capture.review = review_prefix_bindings(data, builtins, store)!
	capture.server.require_idle(&capture.guard, data)!
	accepted = true
	return capture
}

// Re-run structural inspection between idle/namespace checks, retaining the
// guard. This does not authenticate runtime bytes or freeze concurrent writes.
// Migration application still needs authenticated inputs, fresh checks at use,
// atomic binding changes and an interruption recovery policy.
pub fn (capture &IdleBindingReview) recheck() ! {
	capture.server.require_idle(&capture.guard, capture.data)!
	mut current := review_prefix_bindings(capture.data, capture.builtins, capture.store)!
	defer { current.close() }
	if current.generation != capture.review.generation || current.prior_generation != capture.review.prior_generation
		|| current.runtime_id != capture.review.runtime_id || current.bindings != capture.review.bindings {
		return error('Wine binding review changed while captured')
	}
	capture.server.require_idle(&capture.guard, capture.data)!
}
