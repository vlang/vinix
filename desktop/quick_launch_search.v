// SPDX-License-Identifier: GPL-2.0-or-later
// Filesystem search never runs while accepting input or constructing the UI.
module main

import os
import json2
import desktop.workflowcore

__global launcher_index_worker = int(0)
__global launcher_index_home = ''
__global launcher_index_started = u64(0)

const quick_launch_search_delay = u64(150)
const quick_launch_reply_limit = 64 * 1024

struct QuickLaunchPath {
	path string
	directory bool
	identity workflowcore.Identity
}

struct QuickLaunchReply {
	results []QuickLaunchPath
	index_identity workflowcore.Identity
	has_index bool
	reloaded bool
}

struct QuickLaunchSearch {
mut:
	worker int
	fd int = -1
	bytes []u8
	generation u64
	worker_generation u64
	cancelled bool
	due u64
	refresh_at u64
	requested bool
	results []QuickLaunchPath
	index_identity workflowcore.Identity
	has_index bool
	cached_generation u64
	reload_at u64
}

fn (mut search QuickLaunchSearch) clear_results() {
	for result in search.results { unsafe { result.path.free() } }
	unsafe { search.results.free() }
	search.results = []QuickLaunchPath{}
}

fn (mut d Desktop) quick_launch_search_changed() {
	d.switcher.search.generation++
	d.switcher.search.clear_results()
	d.switcher.search.requested = false
	d.switcher.search.due = desktop_monotonic_ms() + quick_launch_search_delay
	d.switcher.search.refresh_at = 0
	d.dirty = true
}

fn (d &Desktop) quick_launch_search_pending() bool {
	return d.home.len > 0 && d.switcher.query.len > 0
		&& (!d.switcher.search.requested || d.switcher.search.worker > 0)
}

// Refresh the shared Files index in a separate process. Even loading its
// previous policy can involve a large JSON file, so that belongs here too.
fn (mut d Desktop) start_workflow_search() {
	if launcher_index_worker > 0 || d.home.len == 0 { return }
	now := desktop_monotonic_ms()
	if launcher_index_home == d.home && now >= launcher_index_started && now - launcher_index_started < 60000 { return }
	pid := C.fork()
	if pid < 0 { return }
	if pid == 0 {
		for fd in 3 .. 1024 { C.close(fd) }
		home := os.real_path(d.home)
		mut previous := workflowcore.load_index(home) or { workflowcore.SearchIndex{} }
		if previous.roots.len == 0 {
			if id := workflowcore.identify(home) {
				previous.roots << workflowcore.SearchRoot{path: home.clone(), identity: id, enabled: true, contents: true}
			} else { C._exit(1) }
		}
		mut index := workflowcore.SearchIndex{}
		index.begin(previous.roots)
		for index.indexing { index.tick() }
		mut settings := load_files_settings(home)
		for path, ids in settings.assignments {
			mut tags := []string{}
			for id in ids { for tag in settings.tags { if tag.id == id { tags << tag.name.clone() } } }
			index.set_tags(path, tags)
			unsafe { tags.free() }
		}
		index.publish(home) or { C._exit(1) }
		C._exit(0)
	}
	unsafe { launcher_index_home.free() }
	launcher_index_home = d.home.clone()
	launcher_index_started = now
	launcher_index_worker = pid
}

fn (mut d Desktop) start_quick_launch_query() {
	mut pipe := [2]i32{}
	if C.pipe(&pipe[0]) != 0 { return }
	if !desktop_set_cloexec(pipe[0], true) || !desktop_set_cloexec(pipe[1], true)
		|| !desktop_set_nonblocking(pipe[0], true) {
		C.close(pipe[0]); C.close(pipe[1])
		return
	}
	pid := C.fork()
	if pid < 0 { C.close(pipe[0]); C.close(pipe[1]); return }
	if pid == 0 {
		for fd in 3 .. 1024 { if fd != pipe[1] { C.close(fd) } }
		text := json2.encode(d.quick_launch_query_reply())
		if text.len > quick_launch_reply_limit { C._exit(1) }
		mut at := 0
		for at < text.len {
			written := C.write(pipe[1], unsafe { text.str + at }, usize(text.len - at))
			if written < 0 && C.errno == C.EINTR { continue }
			if written <= 0 { C._exit(1) }
			at += int(written)
		}
		C._exit(0)
	}
	C.close(pipe[1])
	d.switcher.search.worker = pid
	d.switcher.search.worker_generation = d.switcher.search.generation
	d.switcher.search.cancelled = false
	d.switcher.search.fd = pipe[0]
	d.switcher.search.bytes = []u8{cap: quick_launch_reply_limit}
	unsafe { d.switcher.search.bytes.flags |= .noslices }
	d.switcher.search.requested = true
}

// An idle panel checks permissions every second, but only decodes an unchanged
// index every ten seconds. Policy edits publish a new inode and bypass this
// shortcut. A changed query always gets a fresh search.
fn (d &Desktop) quick_launch_query_reply() QuickLaunchReply {
	index_path := os.join_path(d.home, '.vinix-search', 'index.json')
	defer { unsafe { index_path.free() } }
	mut identity := workflowcore.Identity{}
	mut has_index := false
	if current := workflowcore.identify(index_path) { identity = current; has_index = true }
	query := d.quick_launch_query_text()
	search := &d.switcher.search
	if search.cached_generation == search.generation && search.requested
		&& desktop_monotonic_ms() < search.reload_at && !query.starts_with('/') && !query.starts_with('~')
		&& search.has_index == has_index && (!has_index || search.index_identity.unchanged(identity)) {
		mut valid := true
		for result in search.results {
			current := workflowcore.identify(result.path) or { valid = false; break }
			if !result.identity.unchanged(current) || C.access(&char(result.path.str), C.R_OK | if result.directory { C.X_OK } else { 0 }) != 0 {
				valid = false
				break
			}
		}
		if valid { return QuickLaunchReply{results: search.results, index_identity: identity, has_index: has_index} }
	}
	mut index := workflowcore.load_index(d.home) or { workflowcore.SearchIndex{} }
	paths := index.launcher_query(query, d.home, quick_launch_max_results)
	mut results := []QuickLaunchPath{}
	for path in paths {
		if current := workflowcore.identify(path) {
			results << QuickLaunchPath{path: path, directory: current.directory(), identity: current}
		}
	}
	return QuickLaunchReply{results: results, index_identity: identity, has_index: has_index, reloaded: true}
}

fn (mut d Desktop) poll_quick_launch_query() {
	mut search := &d.switcher.search
	if search.worker <= 0 { return }
	if !search.cancelled && (!d.switcher.quick_launch || search.worker_generation != search.generation) {
		// Retain the PID until waitpid confirms exit, including after dismissal.
		C.kill(search.worker, C.SIGKILL)
		search.cancelled = true
	}
	if search.fd >= 0 {
		mut buffer := [4096]u8{}
		for _ in 0 .. 17 {
			count := C.read(search.fd, &buffer[0], usize(buffer.len))
			if count < 0 && C.errno == C.EINTR { continue }
			if count < 0 && (C.errno == C.EAGAIN || C.errno == C.EWOULDBLOCK) { break }
			if count <= 0 { C.close(search.fd); search.fd = -1; break }
			if search.bytes.len + int(count) > quick_launch_reply_limit {
				C.kill(search.worker, C.SIGKILL)
				search.cancelled = true
				C.close(search.fd); search.fd = -1
				break
			}
			for i in 0 .. int(count) { search.bytes << buffer[i] }
		}
	}
	mut status := i32(0)
	if C.waitpid(search.worker, unsafe { &status }, C.WNOHANG) != search.worker { return }
	search.worker = 0
	// The child may have written its final bytes between the drain and exit.
	if search.fd >= 0 {
		mut buffer := [4096]u8{}
		for _ in 0 .. 17 {
			count := C.read(search.fd, &buffer[0], usize(buffer.len))
			if count < 0 && C.errno == C.EINTR { continue }
			if count <= 0 { break }
			if search.bytes.len + int(count) > quick_launch_reply_limit { search.cancelled = true; break }
			for i in 0 .. int(count) { search.bytes << buffer[i] }
		}
		C.close(search.fd); search.fd = -1
	}
	if !search.cancelled && status == 0 && d.switcher.quick_launch && search.worker_generation == search.generation {
		text := unsafe { tos(search.bytes.data, search.bytes.len) }
		reply := json2.decode[QuickLaunchReply](text) or { QuickLaunchReply{} }
		mut results := unsafe { reply.results }
		if results.len <= quick_launch_max_results {
			mut app_count := 0
			for index in 0 .. desktop_menu_count() {
				if desktop_menu_matches(index, d.quick_launch_query_text()) { app_count++ }
			}
			// Refreshing filesystem matches must not move a user's application
			// selection. For a selected path, retain that exact row if present.
			selected := d.switcher.index - app_count
			if selected >= 0 && selected < search.results.len {
				mut found := -1
				for i, result in results {
					if result.path == search.results[selected].path { found = i; break }
				}
				d.switcher.index = if found >= 0 { app_count + found } else { 0 }
			}
			search.clear_results()
			search.results = results
			search.index_identity = reply.index_identity
			search.has_index = reply.has_index
			search.cached_generation = search.generation
			if reply.reloaded { search.reload_at = desktop_monotonic_ms() + 10000 }
			if d.switcher.index >= d.quick_launch_visible_count() { d.switcher.index = 0 }
		} else {
			for result in results { unsafe { result.path.free() } }
			unsafe { results.free() }
		}
		search.refresh_at = desktop_monotonic_ms() + 1000
		d.dirty = true
	} else if !search.cancelled {
		search.refresh_at = desktop_monotonic_ms() + 1000
	}
	unsafe { search.bytes.free() }
	search.bytes = []u8{}
}

fn (mut d Desktop) poll_workflow_search() {
	mut completed := false
	if launcher_index_worker > 0 {
		mut status := i32(0)
		if C.waitpid(launcher_index_worker, unsafe { &status }, C.WNOHANG) == launcher_index_worker {
			launcher_index_worker = 0
			completed = true
		}
	}
	d.poll_quick_launch_query()
	if !d.switcher.quick_launch || d.home.len == 0 { return }
	now := desktop_monotonic_ms()
	if completed { d.switcher.search.requested = false; d.switcher.search.refresh_at = 0 }
	// The panel has already been drawn before either filesystem worker starts.
	if now < d.switcher.search.due { return }
	d.start_workflow_search()
	if d.switcher.search.worker > 0 || d.switcher.query.len == 0 { return }
	if d.switcher.search.requested && now < d.switcher.search.refresh_at { return }
	d.start_quick_launch_query()
}

fn (mut d Desktop) close_quick_launch_search() {
	mut search := &d.switcher.search
	if search.worker > 0 {
		C.kill(search.worker, C.SIGKILL)
		mut status := i32(0)
		for {
			waited := C.waitpid(search.worker, unsafe { &status }, 0)
			if waited >= 0 || C.errno != C.EINTR { break }
		}
	}
	if search.fd >= 0 { C.close(search.fd) }
	search.clear_results()
	unsafe { search.bytes.free() }
	d.switcher.search = QuickLaunchSearch{}
	if launcher_index_worker > 0 {
		C.kill(launcher_index_worker, C.SIGKILL)
		mut status := i32(0)
		for {
			waited := C.waitpid(launcher_index_worker, unsafe { &status }, 0)
			if waited >= 0 || C.errno != C.EINTR { break }
		}
		launcher_index_worker = 0
	}
}
