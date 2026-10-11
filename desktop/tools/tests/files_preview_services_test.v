// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import hash.crc32
import compress.deflate
import encoding.base64
import desktop.workflowcore

fn preview_zip_fixture(name string, text string, packed bool) []u8 {
	data := text.bytes()
	compressed := if packed { deflate.compress_raw(data) or { panic(err) } } else { data.clone() }
	mut bytes := []u8{}
	write32 := fn (mut out []u8, n u32) { for i in 0 .. 4 { out << u8(n >> (i * 8)) } }
	write16 := fn (mut out []u8, n u16) { out << u8(n); out << u8(n >> 8) }
	write32(mut bytes, 0x04034b50); write16(mut bytes, 20); write16(mut bytes, 0); write16(mut bytes, if packed { 8 } else { 0 })
	write32(mut bytes, 0); write32(mut bytes, crc32.sum(data)); write32(mut bytes, u32(compressed.len)); write32(mut bytes, u32(data.len))
	write16(mut bytes, u16(name.len)); write16(mut bytes, 0); bytes << name.bytes(); bytes << compressed
	start := bytes.len
	write32(mut bytes, 0x02014b50); write16(mut bytes, 20); write16(mut bytes, 20); write16(mut bytes, 0); write16(mut bytes, if packed { 8 } else { 0 })
	write32(mut bytes, 0); write32(mut bytes, crc32.sum(data)); write32(mut bytes, u32(compressed.len)); write32(mut bytes, u32(data.len))
	write16(mut bytes, u16(name.len)); write16(mut bytes, 0); write16(mut bytes, 0); write16(mut bytes, 0); write16(mut bytes, 0); write32(mut bytes, 0); write32(mut bytes, 0); bytes << name.bytes()
	length := bytes.len - start
	write32(mut bytes, 0x06054b50); write16(mut bytes, 0); write16(mut bytes, 0); write16(mut bytes, 1); write16(mut bytes, 1); write32(mut bytes, u32(length)); write32(mut bytes, u32(start)); write16(mut bytes, 0)
	return bytes
}

fn test_office_and_archive_previews_are_bounded_read_only_and_validate_checksums() {
	root := os.real_path(os.temp_dir()) + '/vinix-office-preview-${os.getpid()}'
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	for packed in [false, true] {
		fixture := preview_zip_fixture('word/document.xml', '<w:p><w:t>Hello &amp; 世界</w:t></w:p>', packed)
		os.write_file_array(root + '/document.docx', fixture)!
		result := workflowcore.preview_document(root + '/document.docx', root)!
		assert result.text.contains('Hello & 世界')
		os.write_file_array(root + '/archive.zip', fixture)!
		listing := workflowcore.preview_document(root + '/archive.zip', root)!
		assert listing.text.contains('word/document.xml')
	}
	os.write_file(root + '/broken.docx', 'PK')!
	workflowcore.preview_document(root + '/broken.docx', root) or { assert err.msg().contains('Truncated'); return }
	assert false
}

fn test_office_preview_worker_finishes_without_blocking_files() {
	root := os.real_path(os.temp_dir()) + '/vinix-office-worker-${os.getpid()}'
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	old_home := desktop_user_home
	desktop_user_home = root
	defer { desktop_user_home = old_home }
	os.write_file_array(root + '/document.odt', preview_zip_fixture('content.xml', '<p>A recovered document</p>', true))!
	mut preview := FilesQuickLook{}
	defer { preview.close() }
	preview.show(root + '/document.odt')
	assert preview.worker > 0 && preview.open
	for _ in 0 .. 300 { if preview.poll_document_preview() { break }; desktop_sleep_ms(10) }
	assert preview.worker == 0 && preview.message == ''
	assert preview.lines.any(it.contains('A recovered document'))
}

fn test_cached_thumbnails_are_valid_surfaces_and_follow_source_identity() {
	root := os.real_path(os.temp_dir()) + '/vinix-thumbnail-${C.getpid()}'
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	old_home := desktop_user_home
	desktop_user_home = root
	defer { desktop_user_home = old_home }
	path := root + '/image.png'
	bytes := base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGP4z8DwHwgbABB5A359Y87XAAAAAElFTkSuQmCC')
	os.write_file_array(path, bytes)!
	mut preview := FilesQuickLook{}
	defer { preview.close() }
	preview.show(path)
	cache := files_thumbnail_path(path)!
	assert os.is_file(cache)
	surface := open_vinix_surface(cache) or { panic('thumbnail must contain both surface buffers') }
	assert surface.width == 2 && surface.height == 1
	assert surface.pixel(0, 0) == 0xff0000
	surface.close()
	os.write_file(path, 'changed')!
	assert files_thumbnail_image(path) == ''
}

fn test_office_content_is_indexed_without_rendering_or_extracting_into_the_source_tree() {
	root := os.real_path(os.temp_dir()) + '/vinix-office-index-${C.getpid()}'
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file_array(root + '/document.docx', preview_zip_fixture('word/document.xml', '<p>UniqueOfficePhrase</p>', true))!
	mut index := workflowcore.SearchIndex{}
	defer { index.close() }
	index.begin([workflowcore.SearchRoot{path: root, identity: workflowcore.identify(root)!, enabled: true, contents: true}])
	for index.indexing { index.tick() }
	assert index.query('uniqueofficephrase type:docx', 10).len == 1
	assert os.ls(root)!.len == 1
}
