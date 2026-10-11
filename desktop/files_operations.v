// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2
import desktop.workflowcore

struct FilesTransferReport {
mut:
	state workflowcore.TransferState
	bytes u64
	total u64
	index int
	count int
	message string
	label string
}

struct FilesBatchClipboard {
	cut bool
	paths []string
}

struct FilesUndo {
mut:
	source string
	destination string
	identity workflowcore.Identity
	copy bool
	trash_root string
	trash_bucket string
	backup string
	group u64
	permission bool
	old_mode u32
}

fn files_job_store() !string {
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	return workflowcore.private_store(home, '.vinix-file-jobs')!
}

fn (mut a FilesContextApp) selected_paths() []string {
	if a.selection.len > 0 { return a.selection.map(it.clone()) }
	if a.context_path.len > 0 { return [a.context_path.clone()] }
	return []string{}
}

fn (mut a FilesContextApp) clear_selection_paths() {
	for path in a.selection { unsafe { path.free() } }
	a.selection.clear()
}

fn (mut a FilesContextApp) toggle_selection(path string) {
	unsafe { a.selection_directory.free() }
	a.selection_directory = a.files.current_path().clone()
	index := a.selection.index(path)
	if index >= 0 { unsafe { a.selection[index].free() }; a.selection.delete(index) }
	else if a.selection.len < max_entries { a.selection << path.clone() }
}

fn (mut a FilesContextApp) batch_clipboard(mode FileClipboardMode) ! {
	paths := a.selected_paths()
	defer { unsafe { paths.free() } }
	if paths.len == 0 { return error('no items selected') }
	store := files_job_store()!
	defer { unsafe { store.free() } }
	data := json2.encode(FilesBatchClipboard{cut: mode == .cut, paths: paths})
	bytes := data.bytes()
	defer { unsafe { data.free(); bytes.free() } }
	workflowcore.atomic_save('${store}/clipboard.json', bytes, workflowcore.SaveOptions{})!
}

fn (mut a FilesContextApp) batch_paste() ! {
	store := files_job_store()!
	defer { unsafe { store.free() } }
	bytes := workflowcore.read_regular('${store}/clipboard.json', 2 * 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	clipboard := json2.decode[FilesBatchClipboard](bytes.bytestr())!
	defer { unsafe { clipboard.paths.free() } }
	a.start_transfer(clipboard.paths, a.files.current_path(), if clipboard.cut { .move } else { .copy })!
}

fn (mut a FilesContextApp) start_transfer(paths []string, directory string, kind workflowcore.TransferKind) ! {
	if a.worker_pid > 0 { return error('a file operation is already running') }
	mut job := workflowcore.new_transfer(paths, directory, kind)!
	defer { job.close() }
	a.undo_pending = false
	a.launch_transfer(mut job)!
}

fn (mut a FilesContextApp) launch_transfer(mut job workflowcore.Transfer) ! {
	store := files_job_store()!
	defer { unsafe { store.free() } }
	unsafe { a.job_path.free() }
	a.job_sequence++
	a.job_group = a.job_sequence
	a.job_path = '${store}/job-${C.getpid()}-${desktop_monotonic_ms()}-${a.job_sequence}.json'
	job.checkpoint(a.job_path)!
	a.spawn_transfer_worker()!
}

fn (mut a FilesContextApp) restore_transfer_checkpoint() {
	store := files_job_store() or { return }
	defer { unsafe { store.free() } }
	names := os.ls(store) or { return }
	defer { unsafe { names.free() } }
	mut newest := i64(-1)
	for name in names {
		if !name.starts_with('job-') || !name.ends_with('.json') { continue }
		path := files_child_path(store, name)
		defer { unsafe { path.free() } }
		id := workflowcore.identify(path) or { continue }
		if id.modified < newest { continue }
		lease := files_transfer_lease(path)
		if lease < 0 { continue }
		C.close(lease)
		mut job := workflowcore.resume_transfer(path) or { continue }
		unfinished := job.index < job.items.len
		job.close()
		if !unfinished { continue }
		newest = id.modified
		unsafe { a.job_path.free() }
		a.job_path = path.clone()
		a.job_sequence++
		a.job_group = a.job_sequence
		a.operation_error('An interrupted operation is available. Retry / Resume continues its saved checkpoint.')
	}
}

fn files_transfer_lease(journal string) int {
	path := journal + '.lease'
	defer { unsafe { path.free() } }
	fd := C.open(&char(path.str), C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return -1 }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) || info.st_uid != C.getuid() || u32(info.st_mode) & 0o077 != 0 || C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 { C.close(fd); return -1 }
	return fd
}

fn (mut a FilesContextApp) spawn_transfer_worker() ! {
	journal := a.job_path.clone()
	defer { unsafe { journal.free() } }
	pid := C.fork()
	if pid < 0 { return error('cannot start file operation worker') }
	if pid == 0 {
		// No application transport or compositor descriptor belongs to a worker.
		for fd in 3 .. 1024 { C.close(fd) }
		files_transfer_worker(journal)
		C._exit(0)
	}
	a.worker_pid = pid
	a.job_recorded = false
	a.operation_open = true
}

fn files_transfer_worker(journal string) {
	lease := files_transfer_lease(journal)
	if lease < 0 { return }
	defer { C.close(lease) }
	mut job := workflowcore.resume_transfer(journal) or { return }
	defer { job.close() }
	command_path := journal + '.command'
	report_path := journal + '.report'
	defer { unsafe { command_path.free(); report_path.free() } }
	for {
		if bytes := workflowcore.read_regular(command_path, 64) {
			command := bytes.bytestr()
			match command {
				'cancel' { job.cancel() }
				'retry' { job.retry() }
				'skip' { job.resolve(.skip) }
				'keep_both' { job.resolve(.keep_both) }
				'replace' { job.resolve(.replace) }
				else {}
			}
			C.unlink(&char(command_path.str))
			unsafe { bytes.free(); command.free() }
		}
		job.tick()
		job.checkpoint(journal) or { job.cancel(); job.message = err.msg().clone(); job.state = .failed }
		report := json2.encode(FilesTransferReport{state: job.state, bytes: job.completed_bytes, total: job.total_bytes, index: job.index, count: job.items.len, message: job.message})
		data := report.bytes()
		workflowcore.atomic_save(report_path, data, workflowcore.SaveOptions{}) or { unsafe { data.free(); report.free() }; return }
		unsafe { data.free(); report.free() }
		if job.state in [.complete, .cancelled, .failed] { return }
		if job.state == .conflict { desktop_sleep_ms(100) }
	}
}

fn (mut a FilesContextApp) transfer_command(command string) {
	if a.job_path.len == 0 { return }
	if command == 'retry' && a.worker_pid <= 0 { C.unlink(&char((a.job_path + '.command').str)); a.spawn_transfer_worker() or { a.operation_error(err.msg()) }; return }
	bytes := command.bytes()
	workflowcore.atomic_save(a.job_path + '.command', bytes, workflowcore.SaveOptions{}) or {}
	unsafe { bytes.free() }
}

fn (mut a FilesContextApp) poll() bool {
	index_changed := a.poll_index_search()
	preview_changed := a.preview.poll_document_preview()
	thumbnails_changed := a.poll_thumbnails()
	if a.job_path.len == 0 || !a.operation_open { return index_changed || preview_changed || thumbnails_changed }
	if a.worker_pid > 0 {
		mut status := 0
		if C.waitpid(a.worker_pid, &status, C.WNOHANG) == a.worker_pid { a.worker_pid = 0 }
	}
	bytes := workflowcore.read_regular(a.job_path + '.report', 65536) or {
		if a.worker_pid == 0 && a.operation.state == .running { a.operation_error('Worker stopped before reporting. Retry resumes its saved checkpoint.'); return true }
		return index_changed || preview_changed || thumbnails_changed
	}
	defer { unsafe { bytes.free() } }
	mut report := json2.decode[FilesTransferReport](bytes.bytestr()) or { return false }
	if a.worker_pid == 0 && report.state in [.running, .conflict] {
		report.state = if a.operation.state == .cancelled { .cancelled } else { .failed }
		unsafe { report.message.free() }
		report.message = 'Worker stopped. Retry resumes its saved checkpoint.'.clone()
	}
	label := files_report_label(report)
	if label == a.operation.label && (report.state != .complete || a.job_recorded || a.worker_pid > 0) { unsafe { label.free(); report.message.free() }; return index_changed || preview_changed || thumbnails_changed }
	unsafe { a.operation.label.free(); a.operation.message.free() }
	report.label = label
	a.operation = report
	if report.state == .complete && !a.job_recorded {
		if a.worker_pid > 0 { return true }
		mut job := workflowcore.resume_transfer(a.job_path) or { return true }
		if a.undo_pending {
			a.finish_transfer_undo(job) or { a.operation_error(err.msg()); job.close(); return true }
			job.close()
			return true
		}
		for item in job.items {
			if item.skipped { continue }
			if id := item.result {
				a.undo_operations << FilesUndo{source: item.source.clone(), destination: item.destination.clone(), identity: id, copy: job.kind == .copy, backup: item.backup.clone(), group: a.job_group}
				if job.kind == .move { a.files.settings.rebase_path(item.source, item.destination) }
				else { a.files.settings.copy_path(item.source, item.destination) }
			}
		}
		job.close()
		a.job_recorded = true
		a.files.settings.save(desktop_home)
		a.refresh_to(a.files.current_path().clone())
		a.clear_selection_paths()
	}
	return true
}

fn files_report_label(report FilesTransferReport) string {
	values := [report.state.str(), report.index.str(), report.count.str(), report.bytes.str(), report.total.str()]!
	defer { for value in values { unsafe { value.free() } } }
	return '${values[0]}: ${values[1]}/${values[2]} items, ${values[3]}/${values[4]} bytes. ${report.message}'
}

fn (a &FilesContextApp) next_poll_ms() u64 { return if a.worker_pid > 0 { u64(100) } else { u64(1000) } }

fn (mut a FilesContextApp) batch_delete() ! {
	paths := a.selected_paths()
	defer { unsafe { paths.free() } }
	a.job_sequence++
	for path in paths {
		a.trash_for_path(path)
		if !a.trash.move(path) { return error(tr(a.trash.status)) }
		for entry in a.trash.entries {
			full := files_child_path(a.trash.home, entry.path)
			if full == path { a.undo_operations << FilesUndo{source: path.clone(), trash_root: a.trash.home.clone(), trash_bucket: entry.bucket.clone(), group: a.job_sequence} }
			unsafe { full.free() }
		}
		// Tags stay attached to the original path and return with a restore.
	}
	a.clear_selection_paths()
	a.clear_context_path()
	a.refresh_to(a.files.current_path().clone())
}

fn (mut a FilesContextApp) undo_file_operation() ! {
	if a.worker_pid > 0 || a.undo_operations.len == 0 { return error('no completed operation to undo') }
	group := a.undo_operations.last().group
	for a.undo_operations.len > 0 && a.undo_operations.last().group == group { a.undo_one_file_operation()!; if a.undo_pending { return } }
}

fn (mut a FilesContextApp) undo_one_file_operation() ! {
	if a.worker_pid > 0 || a.undo_operations.len == 0 { return error('no completed operation to undo') }
	mut undo := &a.undo_operations[a.undo_operations.len - 1]
	if undo.trash_bucket.len > 0 {
		a.trash_for_path(undo.source)
		a.trash.reload()
		mut found := false
		for i, entry in a.trash.entries { if entry.bucket == undo.trash_bucket { a.trash.selected = i; found = true; break } }
		if !found { return error('Trash item unavailable') }
		a.trash.restore()
		if a.trash.status !in ['files.trash.restored', 'files.trash.unsynced'] { return error(tr(a.trash.status)) }
	} else {
		now := workflowcore.identify(undo.destination)!
		if !undo.identity.unchanged(now) { return error('item changed since operation; undo refused') }
		if undo.permission { workflowcore.chmod(undo.destination, now, undo.old_mode)! }
		else if undo.copy {
			a.trash_for_path(undo.destination)
			if !a.trash.move(undo.destination) { return error(tr(a.trash.status)) }
		} else {
			parent := os.dir(undo.source)
			defer { unsafe { parent.free() } }
			if workflowcore.identify(parent)!.device != now.device {
				mut job := workflowcore.new_transfer_to(undo.destination, undo.source, .move)!
				defer { job.close() }
				a.launch_transfer(mut job)!
				a.undo_pending = true
				return
			}
			workflowcore.rename_exclusive(undo.destination, undo.source, now)!
			a.files.settings.rebase_path(undo.destination, undo.source)
		}
		if undo.backup.len > 0 {
			original := workflowcore.identify(undo.backup)!
			workflowcore.rename_exclusive(undo.backup, undo.destination, original)!
		}
	}
	if undo.trash_bucket.len == 0 && !undo.copy {
		restored_path := if undo.permission { undo.destination } else { undo.source }
		if restored := workflowcore.identify(restored_path) {
			for i in 0 .. a.undo_operations.len - 1 {
				if a.undo_operations[i].identity.same_node(undo.identity) {
					a.undo_operations[i].identity = restored
					if a.undo_operations[i].destination == undo.destination { unsafe { a.undo_operations[i].destination.free() }; a.undo_operations[i].destination = restored_path.clone() }
				}
			}
		}
	}
	unsafe { undo.source.free(); undo.destination.free(); undo.trash_root.free(); undo.trash_bucket.free(); undo.backup.free() }
	a.undo_operations.delete_last()
	a.files.settings.save(desktop_home)
	a.refresh_to(a.files.current_path().clone())
}

fn (mut a FilesContextApp) workflow_permission_action(event string) bool {
	if event != 'files.permissions.apply' || !a.files.info.open { return a.files.permission_action(event) }
	path := a.files.info.path.clone()
	defer { unsafe { path.free() } }
	original := a.files.info.permission_identity
	handled := a.files.permission_action(event)
	if now := workflowcore.identify(path) {
		if original.same_node(now) && original.mode & 0o777 != now.mode & 0o777 {
			a.job_sequence++
			a.undo_operations << FilesUndo{destination: path.clone(), identity: now, permission: true, old_mode: original.mode & 0o777, group: a.job_sequence}
		}
	}
	return handled
}

fn (mut a FilesContextApp) finish_transfer_undo(job workflowcore.Transfer) ! {
	if a.undo_operations.len == 0 || job.items.len != 1 { return error('undo record unavailable') }
	item := job.items[0]
	if item.skipped { a.undo_pending = false; a.job_recorded = true; return error('Undo skipped; moved item retained.') }
	undo := a.undo_operations.last()
	if !item.done || item.source != undo.destination { return error('undo transfer incomplete') }
	if undo.backup.len > 0 {
		original := workflowcore.identify(undo.backup)!
		workflowcore.rename_exclusive(undo.backup, undo.destination, original)!
	}
	a.files.settings.rebase_path(undo.destination, item.destination)
	unsafe { undo.source.free(); undo.destination.free(); undo.trash_root.free(); undo.trash_bucket.free(); undo.backup.free() }
	a.undo_operations.delete_last()
	a.undo_pending = false
	a.job_recorded = true
	a.files.settings.save(desktop_home)
	a.refresh_to(a.files.current_path().clone())
	if a.undo_operations.len > 0 && a.undo_operations.last().group == undo.group { a.undo_file_operation()! }
}

fn (mut a FilesContextApp) operation_action(event string) bool {
	match event {
		'files.batch.copy' { a.batch_clipboard(.copy) or { a.operation_error(err.msg()) }; return true }
		'files.batch.cut' { a.batch_clipboard(.cut) or { a.operation_error(err.msg()) }; return true }
		'files.batch.paste' { a.batch_paste() or { a.operation_error(err.msg()) }; return true }
		'files.batch.delete' { a.batch_delete() or { a.operation_error(err.msg()) }; return true }
		'files.operation.undo' { a.undo_file_operation() or { a.operation_error(err.msg()) }; return true }
		'files.operation.cancel' { a.transfer_command('cancel'); if a.worker_pid > 0 { C.kill(a.worker_pid, C.SIGTERM) }; a.operation.state = .cancelled; return true }
		'files.operation.retry' { a.transfer_command('retry'); return true }
		'files.operation.skip' { a.transfer_command('skip'); return true }
		'files.operation.keep_both' { a.transfer_command('keep_both'); return true }
		'files.operation.replace' { a.transfer_command('replace'); return true }
		'files.operation.dismiss' { if a.worker_pid <= 0 { a.operation_open = false }; return true }
		else { return false }
	}
}

fn (mut a FilesContextApp) operation_error(message string) {
	unsafe { a.operation.label.free() }
	a.operation.label = message.clone()
	a.operation.state = .failed
	a.operation_open = true
}

fn (a &FilesContextApp) operation_panel(size ui2.Rect) ui2.Element {
	mut rows := frame_elements(8)
	rows << ui2.label('', a.operation.label, ui2.rect(8, 2, size.width - 16, 30), ui2.TextStyle{color: body_text, size: 11, lines: 2})
	for i, pair in [['files.operation.cancel', 'Cancel']!, ['files.operation.retry', 'Retry / Resume']!, ['files.operation.skip', 'Skip']!, ['files.operation.keep_both', 'Keep both']!, ['files.operation.replace', 'Replace']!, ['files.operation.dismiss', 'Dismiss']!]! {
		button_width := (int(size.width) - 16) / 6
		rows << ui2.button(pair[0], pair[1], ui2.rect(f64(8 + i * button_width), 34, f64(button_width - 4), 28), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11})
	}
	return ui2.view('files.operation.panel', ui2.rect(0, size.height - 100, size.width, 66), ui2.BoxStyle{bg: app_surface}, rows)
}
