// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import ui2
import crypto.sha256
import desktop.workflowcore

struct FilesPreviewWork {
	result workflowcore.Preview
	error string
}

fn (mut p FilesQuickLook) start_document_preview() bool {
	store := workflowcore.private_store(files_service_home(), '.vinix-previews') or { p.message = err.msg().clone(); return true }
	defer { unsafe { store.free() } }
	p.surface_serial++
	p.work_directory = '${store}/preview-${C.getpid()}-${p.surface_serial}'
	os.mkdir(p.work_directory, mode: 0o700) or { return false }
	pid := C.fork()
	if pid < 0 { return false }
	if pid == 0 {
		C.setpgid(0, 0)
		for fd in 3 .. 1024 { C.close(fd) }
		workflowcore.preview_worker_limits() or { C._exit(1) }
		mut work := FilesPreviewWork{}
		if result := workflowcore.preview_document(p.path, p.work_directory) { work = FilesPreviewWork{result: result} }
		else { work = FilesPreviewWork{error: err.msg()} }
		encoded := json2.encode(work)
		workflowcore.atomic_save(p.work_directory + '/result.json', encoded.bytes(), workflowcore.SaveOptions{}) or { C._exit(1) }
		C._exit(0)
	}
	C.setpgid(pid, pid)
	p.worker = pid
	p.message = 'Loading preview…'.clone()
	return true
}

fn (mut p FilesQuickLook) poll_document_preview() bool {
	if p.worker <= 0 { return false }
	mut status := 0
	if C.waitpid(p.worker, &status, C.WNOHANG) != p.worker { return false }
	p.worker = 0
	unsafe { p.message.free() }
	p.message = ''
	now := workflowcore.identify(p.path) or { p.message = 'File disappeared during preview.'.clone(); return true }
	if !p.source_identity.unchanged(now) { p.message = 'File changed during preview. Close and retry.'.clone(); return true }
	if status != 0 { p.message = 'Preview worker failed. Close and retry.'.clone(); return true }
	bytes := workflowcore.read_regular(p.work_directory + '/result.json', 2 * 1024 * 1024) or { p.message = err.msg().clone(); return true }
	defer { unsafe { bytes.free() } }
	text := editor_bytes_text(bytes)
	work := json2.decode[FilesPreviewWork](text) or { p.message = err.msg().clone(); return true }
	if work.error.len > 0 { p.message = work.error; unsafe { work.result.text.free(); work.result.image.free(); work.result.provider.free() }; return true }
	unsafe { work.error.free() }
	if work.result.image.len > 0 {
		original := p.path
		p.path = work.result.image
		if p.load_image() { p.kind = .image }
		p.path = original
	}
	lines := work.result.text.split_into_lines()
	defer { unsafe { lines.free() } }
	for line in lines {
		if p.lines.len >= files_quicklook_max_lines { p.truncated = true; break }
		p.lines << line.clone()
	}
	unsafe { work.result.text.free(); work.result.image.free(); work.result.provider.free() }
	if p.surface_path.len > 0 { files_store_thumbnail(p.path, p.surface_path, p.source_identity) or {} }
	return true
}

fn files_thumbnail_path(path string) !string {
	id := workflowcore.identify(path)!
	return files_thumbnail_identity_path(path, id)!
}

fn files_thumbnail_identity_path(path string, id workflowcore.Identity) !string {
	store := workflowcore.private_store(files_service_home(), '.vinix-thumbnails')!
	defer { unsafe { store.free() } }
	values := [id.device.str(), id.inode.str(), id.size.str(), id.modified.str(), id.modified_ns.str(), id.changed_ns.str(), id.mode.str()]!
	defer { for value in values { unsafe { value.free() } } }
	key := '${path}:${values[0]}:${values[1]}:${values[2]}:${values[3]}:${values[4]}:${values[5]}:${values[6]}'
	data := key.bytes()
	digest := sha256.sum(data).hex()
	defer { unsafe { key.free(); data.free(); digest.free() } }
	return store + '/' + digest + '.surface'
}

fn files_store_thumbnail(path string, surface string, expected workflowcore.Identity) ! {
	if !expected.unchanged(workflowcore.identify(path)!) { return error('thumbnail source changed') }
	target := files_thumbnail_identity_path(path, expected)!
	defer { unsafe { target.free() } }
	canonical_surface := workflowcore.canonical(surface)!
	defer { unsafe { canonical_surface.free() } }
	bytes := workflowcore.read_regular(canonical_surface, 32 * 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	if bytes.len < 48 { return error('invalid thumbnail source') }
	text := editor_bytes_text(bytes)
	w := int(color_meter_read_u32(text, 12))
	h := int(color_meter_read_u32(text, 16))
	stride := int(color_meter_read_u32(text, 20))
	if w < 1 || h < 1 || w > 8192 || h > 8192 || stride < w * 4 || i64(stride) * h + 48 > bytes.len { return error('invalid thumbnail dimensions') }
	width := if w > 192 || h > 192 { if w >= h { 192 } else { if w * 192 / h > 0 { w * 192 / h } else { 1 } } } else { w }
	out_height := if w > 192 || h > 192 { if h >= w { 192 } else { if h * 192 / w > 0 { h * 192 / w } else { 1 } } } else { h }
	mut thumb := []u8{len: 48 + width * out_height * 8}
	defer { unsafe { thumb.free() } }
	for i in 0 .. 48 { thumb[i] = bytes[i] }
	files_quicklook_put_u32(mut thumb, 12, u32(width))
	files_quicklook_put_u32(mut thumb, 16, u32(out_height))
	files_quicklook_put_u32(mut thumb, 20, u32(width * 4))
	files_quicklook_put_u32(mut thumb, 40, u32(width * out_height * 4))
	for y in 0 .. out_height { for x in 0 .. width { for c in 0 .. 4 { thumb[48 + (y * width + x) * 4 + c] = bytes[48 + (y * h / out_height) * stride + (x * w / width) * 4 + c] } } }
	for i in 0 .. width * out_height * 4 { thumb[48 + width * out_height * 4 + i] = thumb[48 + i] }
	workflowcore.atomic_save(target, thumb, workflowcore.SaveOptions{})!
	store := os.dir(target)
	defer { unsafe { store.free() } }
	mut names := os.ls(store)!
	defer { unsafe { names.free() } }
	names.sort()
	if names.len > 200 { for name in names[..names.len - 200] { os.rm(os.join_path(store, name)) or {} } }
}

fn files_thumbnail_image(path string) string {
	if C.access(&char(path.str), C.R_OK) != 0 { return '' }
	target := files_thumbnail_path(path) or { return '' }
	defer { unsafe { target.free() } }
	if !os.is_file(target) { return '' }
	return vinix_preview_image_prefix + target
}

fn (mut a FilesContextApp) start_visible_thumbnails() {
	if a.thumbnail_worker > 0 { return }
	mut browser := &a.files.browser
	if a.files.view_mode == .commander { browser = if a.files.active_pane == 0 { &a.files.dual_left } else { &a.files.dual_right } }
	else if a.files.view_mode == .columns && a.files.columns.len > 0 { browser = &a.files.columns[a.files.columns.len - 1].browser }
	if a.thumbnail_directory == browser.path && a.thumbnail_scroll == browser.scroll { return }
	unsafe { a.thumbnail_directory.free() }
	a.thumbnail_directory = browser.path.clone()
	a.thumbnail_scroll = browser.scroll
	mut paths := []string{}
	for i := browser.scroll; i < browser.entries.len && i < browser.scroll + 24; i++ {
		path := files_child_path(browser.path, browser.entries[i].name)
		if files_quicklook_kind(path) == .image {
			target := files_thumbnail_path(path) or { unsafe { path.free() }; continue }
			if !os.is_file(target) { paths << path.clone() }
			unsafe { target.free() }
		}
		unsafe { path.free() }
	}
	defer { unsafe { paths.free() } }
	if paths.len == 0 { return }
	pid := C.fork()
	if pid < 0 { return }
	if pid == 0 {
		for fd in 3 .. 1024 { C.close(fd) }
		workflowcore.preview_worker_limits() or { C._exit(1) }
		for path in paths { mut preview := FilesQuickLook{}; preview.show(path); preview.close() }
		C._exit(0)
	}
	a.thumbnail_worker = pid
}

fn (mut a FilesContextApp) poll_thumbnails() bool {
	if a.thumbnail_worker <= 0 { return false }
	mut status := 0
	if C.waitpid(a.thumbnail_worker, &status, C.WNOHANG) != a.thumbnail_worker { return false }
	a.thumbnail_worker = 0
	return true
}

// The normal image tools remain available. Non-image documents share Files'
// worker and read-only preview instead of entering the bitmap editing path.
__global preview_documents = FilesQuickLook{}

fn workflow_preview_poll() bool { return preview_documents.poll_document_preview() }

fn (mut a PreviewApp) open_workflow_preview(path string) bool {
	if files_quicklook_kind(path) != .document { preview_documents.close(); return false }
	preview_documents.show(path)
	record_recent_item('vinix-preview', path)
	return true
}

fn (mut a PreviewApp) workflow_preview_panel(size ui2.Rect) ?ui2.Element {
	if !preview_documents.open { return none }
	preview_documents.poll_document_preview()
	return preview_documents.build(size)
}
