// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import desktop.workflowcore

struct FilesTrashProgress {
mut:
	report_path string
	command_path string
	index int
	count int
	nodes u64
	remaining int
	last_report u64
	cancelled bool
	report_failed bool
}

fn (mut p FilesTrashProgress) stop_requested() bool {
	if p.command_path.len > 0 && C.access(&char(p.command_path.str), C.F_OK) == 0 { p.cancelled = true }
	return p.cancelled || p.report_failed
}

fn (mut p FilesTrashProgress) publish(force bool) {
	if p.report_path.len == 0 { return }
	now := desktop_monotonic_ms()
	if !force && now >= p.last_report && now - p.last_report < 100 { return }
	p.last_report = now
	nodes := p.nodes.str()
	message := 'Emptying Trash: ' + nodes + ' nodes removed. Cancel retains the remaining items.'
	defer { unsafe { nodes.free(); message.free() } }
	files_trash_write_report(p.report_path, FilesTransferReport{state: .running, index: p.index, count: p.count, message: message}) or { p.report_failed = true }
}

fn files_trash_write_report(path string, report FilesTransferReport) ! {
	text := json2.encode(report)
	bytes := text.bytes()
	defer { unsafe { text.free(); bytes.free() } }
	workflowcore.atomic_save(path, bytes, workflowcore.SaveOptions{})!
}

fn (mut a FilesContextApp) start_trash_empty() ! {
	if !a.trash.confirming { return }
	if a.worker_pid > 0 { return error('a file operation is already running') }
	store := files_job_store()!
	defer { unsafe { store.free() } }
	a.job_sequence++
	path := '${store}/empty-${C.getpid()}-${desktop_monotonic_ms()}-${a.job_sequence}'
	report := path + '.report'
	command := path + '.command'
	defer { unsafe { report.free(); command.free() } }
	pid := C.fork()
	if pid < 0 { unsafe { path.free() }; return error('cannot start Trash worker') }
	if pid == 0 {
		// The inherited Trash descriptors anchor exactly the approved catalog.
		for fd in 3 .. 1024 { if fd != a.trash.home_fd && fd != a.trash.store_fd { C.close(fd) } }
		a.trash.progress = FilesTrashProgress{report_path: report, command_path: command, count: a.trash.entries.len}
		a.trash.progress.publish(true)
		if !a.trash.progress.report_failed { a.trash.empty_confirmed() }
		state := if a.trash.progress.cancelled { workflowcore.TransferState.cancelled }
			else if a.trash.status in ['files.trash.emptied', 'files.trash.empty_unsynced']! { workflowcore.TransferState.complete }
			else { workflowcore.TransferState.failed }
		message := if state == .cancelled { 'Emptying cancelled. Review the remaining Trash before emptying again.' }
			else { tr(a.trash.status) }
		files_trash_write_report(report, FilesTransferReport{state: state, index: a.trash.progress.index, count: a.trash.progress.count, message: message}) or { C._exit(1) }
		C._exit(0)
	}
	unsafe { a.job_path.free(); a.operation.label.free(); a.operation.message.free() }
	a.job_path = path
	a.worker_pid = pid
	a.trash_job = true
	a.job_recorded = false
	a.operation_open = true
	a.operation = FilesTransferReport{state: .running, label: 'Emptying Trash in background…'.clone()}
	a.trash.confirming = false
	a.trash_open = false
}

fn (mut a FilesContextApp) poll_trash_empty() bool {
	mut exited := false
	mut status := 0
	if a.worker_pid > 0 && C.waitpid(a.worker_pid, unsafe { &status }, C.WNOHANG) == a.worker_pid { a.worker_pid = 0; exited = true }
	path := a.job_path + '.report'
	defer { unsafe { path.free() } }
	bytes := workflowcore.read_regular(path, 65536) or {
		if exited { a.operation_error('Trash worker failed. Review the remaining Trash before emptying again.'); a.trash.reload(); return true }
		return false
	}
	defer { unsafe { bytes.free() } }
	mut report := json2.decode[FilesTransferReport](editor_bytes_text(bytes)) or { return false }
	if a.worker_pid == 0 && report.state == .running {
		report.state = .failed
		unsafe { report.message.free() }
		report.message = 'Trash worker stopped. Review the remaining Trash before emptying again.'.clone()
	}
	label := files_report_label(report)
	if label == a.operation.label && !exited { unsafe { label.free(); report.message.free() }; return false }
	unsafe { a.operation.label.free(); a.operation.message.free() }
	a.operation = FilesTransferReport{...report, label: label}
	if a.worker_pid == 0 && !a.job_recorded { a.trash.reload(); a.job_recorded = true }
	return true
}
