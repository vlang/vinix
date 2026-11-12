// SPDX-License-Identifier: GPL-2.0-or-later
module workflowcore

import os
import json2
import time

pub enum ConflictChoice { ask skip keep_both replace }
pub enum TransferState { running conflict failed cancelled complete }
pub enum TransferKind { copy move }

pub struct TransferItem {
pub mut:
	source string
	destination string
	partial string
	backup string
	replace_expected ?Identity
	original Identity
	result ?Identity
	bytes u64
	done bool
	skipped bool
}

struct CopyNode {
mut:
	source string
	target string
	original Identity
	created ?Identity
}

// A cooperative worker: each tick performs one directory or at most 256 KiB.
// Callers can run this model in a worker process for blocking remote mounts.
pub struct Transfer {
pub mut:
	items []TransferItem
	state TransferState = .running
	kind TransferKind
	choice ConflictChoice
	index int
	completed_bytes u64
	total_bytes u64
	message string
mut:
	parent_path string
	parent_identity Identity
	nodes []CopyNode
	node_index int
	input int = -1
	output int = -1
	offset u64
	buffer []u8
}

pub fn new_transfer(paths []string, directory string, kind TransferKind) !Transfer {
	dir := os.real_path(directory)
	if dir == '' || !os.is_dir(dir) { return error('destination volume unavailable') }
	mut job := Transfer{kind: kind, parent_path: dir.clone(), parent_identity: identify(dir)!, buffer: []u8{len: 256 * 1024}}
	for i, path in paths {
		source := canonical(path)!
		original := identify(source)!
		if !original.regular() && !original.directory() && !original.link() { job.close(); return error('unsupported file type') }
		if source == dir || dir.starts_with(source + '/') { job.close(); return error('destination is inside source') }
		job.items << TransferItem{source: source, destination: os.join_path(dir, os.file_name(source)), partial: os.join_path(dir, '.vinix-copy-${os.getpid()}-${time.now().unix_micro()}-${i}'), original: original}
	}
	if job.items.len == 0 { job.close(); return error('no files selected') }
	return job
}

pub fn new_transfer_to(source string, destination string, kind TransferKind) !Transfer {
	full := canonical(destination)!
	directory := os.dir(full)
	defer { unsafe { directory.free() } }
	mut job := new_transfer([source], directory, kind) or { unsafe { full.free() }; return err }
	unsafe { job.items[0].destination.free() }
	job.items[0].destination = full
	if job.items[0].source == full { job.close(); return error('source and destination are the same') }
	return job
}

fn (mut job Transfer) stop(message string) {
	job.close_fds()
	unsafe { job.message.free() }
	job.message = message.clone()
	job.state = .failed
}

fn (mut job Transfer) close_fds() {
	if job.input >= 0 { C.close(job.input) }
	if job.output >= 0 { C.close(job.output) }
	job.input = -1
	job.output = -1
}

pub fn (mut job Transfer) cancel() { job.close_fds(); job.state = .cancelled }
pub fn (mut job Transfer) retry() {
	if job.state in [.cancelled, .failed] { job.state = .running }
}
pub fn (mut job Transfer) resolve(choice ConflictChoice) {
	if job.state != .conflict || choice == .ask { return }
	job.choice = choice
	job.state = .running
}

fn (mut job Transfer) clear_nodes() {
	for n in job.nodes { unsafe { n.source.free(); n.target.free() } }
	job.nodes.clear()
	job.node_index = 0
	job.offset = 0
}

pub fn (mut job Transfer) close() {
	job.close_fds()
	job.clear_nodes()
	for item in job.items { unsafe { item.source.free(); item.destination.free(); item.partial.free(); item.backup.free() } }
	unsafe { job.items.free(); job.nodes.free(); job.buffer.free(); job.parent_path.free(); job.message.free() }
	job = Transfer{}
}

pub fn (mut job Transfer) tick() bool {
	if job.state != .running { return false }
	job.step() or { job.stop(err.msg()) }
	return true
}

fn (mut job Transfer) check_destination() ! {
	mut item := &job.items[job.index]
	if exists := identify(item.destination) {
		if replaced := item.replace_expected {
			if replaced.unchanged(exists) && job.choice == .ask { return }
		}
		if job.choice == .ask { job.state = .conflict; return }
		if job.choice == .skip {
			// Only recorded private staging nodes may be discarded.
			for i := job.nodes.len - 1; i >= 0; i-- {
				if created := job.nodes[i].created { remove_node(job.nodes[i].target, created)! }
			}
			item.skipped = true
			item.done = true
			job.index++
			job.clear_nodes()
		} else if job.choice == .keep_both {
			mut found := false
			for attempt in 1 .. 1000 {
				candidate := os.join_path(job.parent_path, os.file_name(item.source) + ' (${attempt})')
				if !item_exists(candidate) { unsafe { item.destination.free() }; item.destination = candidate; found = true; break }
				unsafe { candidate.free() }
			}
			if !found { return error('no unused destination name') }
			item.replace_expected = none
		} else {
			if exists.same_node(item.original) { return error('cannot replace the source') }
			item.replace_expected = exists
		}
	} else { item.replace_expected = none }
	job.choice = .ask
}

fn (mut job Transfer) step() ! {
	if job.index >= job.items.len { job.state = .complete; return }
	if !job.parent_identity.same_node(identify(job.parent_path)!) { return error('destination volume disappeared') }
	mut item := &job.items[job.index]
	// A crash can occur after publication and before its journal is saved.
	// Recognize only the recorded staging inode, never an unrelated destination.
	if item.result == none && job.nodes.len > 0 && job.node_index >= job.nodes.len {
		if staged := job.nodes[0].created {
			if published := identify(item.destination) {
				if staged.same_node(published) {
					if replaced := item.replace_expected {
						previous := identify(item.partial)!
						if !previous.same_node(replaced) { return error('replacement backup changed') }
						item.backup = item.partial.clone()
					} else if item_exists(item.partial) { return error('staging path changed after publication') }
					item.result = published
				}
			}
		}
	}
	if item.result == none && job.kind == .move && job.nodes.len == 0 && !item_exists(item.source) {
		if published := identify(item.destination) { if item.original.same_node(published) { item.result = published } }
	}
	if result := item.result {
		if !result.unchanged(identify(item.destination)!) { return error('completed destination changed') }
		// A cross-volume move can fail while removing its source. Retry only
		// the remaining recorded nodes; the completed destination stays put.
		if job.kind == .move {
			for i := job.nodes.len - 1; i >= 0; i-- {
				if item_exists(job.nodes[i].source) { remove_node(job.nodes[i].source, job.nodes[i].original)! }
			}
		}
		item.done = true
		job.index++
		job.clear_nodes()
		return
	}
	if job.nodes.len == 0 {
		if !item.original.unchanged(identify(item.source)!) { return error('source changed or disappeared') }
		job.check_destination()!
		if job.state == .conflict || item.skipped { return }
		if job.kind == .move && item.original.device == job.parent_identity.device && item.replace_expected == none {
			rename_exclusive(item.source, item.destination, item.original)!
			item.result = identify(item.destination)!
			item.done = true
			job.index++
			return
		}
		if item_exists(item.partial) { return error('staging item already exists; choose a different destination') }
		job.nodes << CopyNode{source: item.source.clone(), target: item.partial.clone(), original: item.original}
	}
	if job.node_index >= job.nodes.len {
		job.check_destination()!
		if job.state == .conflict || item.skipped { return }
		// Verify every source again before publishing or deleting a moved tree.
		for n in job.nodes { if !n.original.unchanged(identify(n.source)!) { return error('source changed during copy') } }
		for n in job.nodes {
			if !n.original.directory() { continue }
			fd := C.open(&char(n.target.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
			if fd < 0 { return error('copied folder disappeared') }
			copy_metadata(fd, n.original) or { C.close(fd); return err }
			C.close(fd)
		}
		staged := identify(item.partial)!
		if replaced := item.replace_expected {
			exchange(item.partial, item.destination, staged, replaced)!
			item.backup = item.partial.clone()
		} else { rename_exclusive(item.partial, item.destination, staged)! }
		item.result = identify(item.destination)!
		if job.kind == .move {
			// Removal walks the exact recorded nodes backwards; newly added files
			// make rmdir fail and leave an explicit partial move result.
			for i := job.nodes.len - 1; i >= 0; i-- { remove_node(job.nodes[i].source, job.nodes[i].original)! }
		}
		item.done = true
		job.index++
		job.clear_nodes()
		return
	}
	mut n := &job.nodes[job.node_index]
	if !n.original.unchanged(identify(n.source)!) { return error('source changed during copy') }
	if n.original.directory() {
		parent, leaf := open_parent(n.target)!
		defer { C.close(parent); unsafe { leaf.free() } }
		if created := n.created {
			if !created.same_node(identify(n.target)!) { return error('partial folder changed') }
		} else if C.mkdirat(parent, &char(leaf.str), 0o700) != 0 { return error('cannot create copied folder') }
		n.created = identify(n.target)!
		names := os.ls(n.source)!
		defer { unsafe { names.free() } }
		if job.nodes.len + names.len > 100000 || n.target.count('/') > job.parent_path.count('/') + 64 { return error('copy tree exceeds limits') }
		// Growing nodes can move its backing array; retain the strings before
		// appending rather than keeping a pointer into that array.
		source_dir := n.source.clone()
		target_dir := n.target.clone()
		defer { unsafe { source_dir.free(); target_dir.free() } }
		mut children := []CopyNode{cap: names.len}
		mut transferred := false
		defer {
			if !transferred { for child in children { unsafe { child.source.free(); child.target.free() } } }
			unsafe { children.free() }
		}
		for name in names {
			src := os.join_path(source_dir, name)
			target := os.join_path(target_dir, name)
			original := identify(src) or { unsafe { src.free(); target.free() }; return err }
			if original.device != item.original.device { unsafe { src.free(); target.free() }; return error('copy crosses a mounted device') }
			children << CopyNode{source: src, target: target, original: original}
		}
		job.nodes << children
		transferred = true
		job.node_index++
		return
	}
	if n.original.link() {
		src, leaf := open_parent(n.source)!
		defer { C.close(src); unsafe { leaf.free() } }
		mut target := [4096]u8{}
		length := C.readlinkat(src, &char(leaf.str), &char(&target[0]), target.len - 1)
		if length < 0 || length >= target.len - 1 { return error('cannot read copied link') }
		dst, dest_leaf := open_parent(n.target)!
		defer { C.close(dst); unsafe { dest_leaf.free() } }
		if C.symlinkat(&char(&target[0]), dst, &char(dest_leaf.str)) != 0 { return error('cannot copy link') }
		n.created = identify(n.target)!
		job.node_index++
		return
	}
	if !n.original.regular() { return error('cannot copy special file') }
	if job.input < 0 {
		src, leaf := open_parent(n.source)!
		defer { C.close(src); unsafe { leaf.free() } }
		job.input = C.openat(src, &char(leaf.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0)
		if job.input < 0 || !n.original.unchanged(identify_fd(job.input)!) { return error('cannot open copy source') }
		dst, dest_leaf := open_parent(n.target)!
		defer { C.close(dst); unsafe { dest_leaf.free() } }
		first_open := n.created == none
		job.output = C.openat(dst, &char(dest_leaf.str), C.O_WRONLY | C.O_NOFOLLOW | C.O_CLOEXEC | (if first_open { C.O_CREAT | C.O_EXCL } else { 0 }), 0o600)
		if job.output < 0 { return error('cannot open copy staging file') }
		opened := identify_fd(job.output)!
		if created := n.created {
			if !created.same_node(opened) || opened.size < job.offset { return error('partial copy changed') }
			// A worker killed between writing and checkpointing may have a
			// longer private partial. Resume from the last synced checkpoint.
			if opened.size > job.offset && C.ftruncate(job.output, i64(job.offset)) != 0 { return error('cannot reset uncheckpointed copy tail') }
		}
		n.created = opened
		if first_open { job.total_bytes += n.original.size }
		if C.lseek(job.input, i64(job.offset), C.SEEK_SET) < 0 || C.lseek(job.output, i64(job.offset), C.SEEK_SET) < 0 { return error('cannot resume copy') }
	}
	count := C.read(job.input, job.buffer.data, uint(job.buffer.len))
	if count < 0 && C.errno == C.EINTR { return }
	if count < 0 { return error('copy read failed (${C.errno}); retry resumes the partial file') }
	if count > 0 {
		write_all(job.output, unsafe { job.buffer[..int(count)] })!
		job.offset += u64(count)
		item.bytes += u64(count)
		job.completed_bytes += u64(count)
		return
	}
	if job.offset != n.original.size || !n.original.unchanged(identify_fd(job.input)!) { return error('copy source changed') }
	copy_metadata(job.output, n.original)!
	n.created = identify_fd(job.output)!
	job.close_fds()
	job.offset = 0
	job.node_index++
}

fn remove_node(path string, expected Identity) ! {
	parent, name := open_parent(path)!
	defer { C.close(parent); unsafe { name.free() } }
	now := identify_at(parent, name)!
	if !(if expected.directory() { expected.same_node(now) } else { expected.unchanged(now) }) { return error('item changed; removal refused') }
	if C.unlinkat(parent, &char(name.str), if now.directory() { C.AT_REMOVEDIR } else { 0 }) != 0 { return error('cannot remove item; completed copy retained') }
}

// Journals are private service files. Descriptors are reopened and checked on
// resume. Keeping the file offset avoids restarting a cancelled large copy.
struct TransferJournal {
	items []TransferItem
	kind TransferKind
	index int
	nodes []CopyNode
	node_index int
	offset u64
	parent_path string
	parent_identity Identity
	completed_bytes u64
	total_bytes u64
}

pub fn (mut job Transfer) checkpoint(path string) ! {
	if job.output >= 0 && C.fsync(job.output) != 0 { return error('cannot sync partial copy') }
	data := json2.encode(TransferJournal{items: job.items, kind: job.kind, index: job.index, nodes: job.nodes, node_index: job.node_index, offset: job.offset, parent_path: job.parent_path, parent_identity: job.parent_identity, completed_bytes: job.completed_bytes, total_bytes: job.total_bytes})
	bytes := data.bytes()
	defer { unsafe { data.free(); bytes.free() } }
	atomic_save(path, bytes, SaveOptions{})!
}

pub fn resume_transfer(path string) !Transfer {
	bytes := read_regular(path, 16 * 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	j := json2.decode[TransferJournal](bytes.bytestr())!
	if j.items.len == 0 || j.index < 0 || j.index > j.items.len || j.node_index < 0 || j.node_index > j.nodes.len { return error('invalid copy journal') }
	if !j.parent_identity.same_node(identify(j.parent_path)!) { return error('destination volume changed') }
	for item in j.items { if !valid_path(item.source) || !valid_path(item.destination) || !item.partial.starts_with(j.parent_path + '/.vinix-copy-') { return error('invalid journal paths') } }
	return Transfer{items: j.items, kind: j.kind, index: j.index, nodes: j.nodes, node_index: j.node_index, offset: j.offset, parent_path: j.parent_path, parent_identity: j.parent_identity, completed_bytes: j.completed_bytes, total_bytes: j.total_bytes, buffer: []u8{len: 256 * 1024}}
}
