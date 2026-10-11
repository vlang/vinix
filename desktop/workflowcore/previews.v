// SPDX-License-Identifier: GPL-2.0-or-later
module workflowcore

import os
import time
import compress.deflate
import hash.crc32
import strings

#include <sys/resource.h>

struct C.rlimit {
mut:
	rlim_cur u64
	rlim_max u64
}

fn C.setrlimit(int, &C.rlimit) int

pub fn preview_worker_limits() ! {
	mut cpu := C.rlimit{rlim_cur: 20, rlim_max: 20}
	mut output := C.rlimit{rlim_cur: 8 * 1024 * 1024, rlim_max: 8 * 1024 * 1024}
	if C.setrlimit(C.RLIMIT_CPU, &cpu) != 0 || C.setrlimit(C.RLIMIT_FSIZE, &output) != 0 { return error('Preview resource limits unavailable') }
	$if linux {
		mut memory := C.rlimit{rlim_cur: 512 * 1024 * 1024, rlim_max: 512 * 1024 * 1024}
		if C.setrlimit(C.RLIMIT_AS, &memory) != 0 { return error('Preview memory limit unavailable') }
	}
}

pub struct Preview {
pub:
	text string
	image string
	provider string
}

fn preview_program(name string, args []string) !string {
	program := os.find_abs_path_of_executable(name) or { return error('Preview requires ${name}. Install its package, then retry.') }
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_redirect_stdio()
	p.run()
	defer { p.close() }
	deadline := time.sys_mono_now() + 15 * time.second
	mut output := strings.new_builder(4096)
	defer { unsafe { output.free() } }
	mut failure := strings.new_builder(1024)
	defer { unsafe { failure.free() } }
	for {
		for kind in [os.ChildProcessPipeKind.stdout, .stderr] {
			if !p.is_pending(kind) { continue }
			chunk := if kind == .stdout { p.stdout_read() } else { p.stderr_read() }
			defer { unsafe { chunk.free() } }
			if kind == .stdout { output.write_string(chunk) } else { failure.write_string(chunk) }
		}
		if output.len > 1024 * 1024 || failure.len > 65536 || time.sys_mono_now() > deadline {
			p.signal_kill(); p.wait()
			return error('Preview exceeded time or output limit')
		}
		if !p.is_alive() {
			for p.is_pending(.stdout) { chunk := p.stdout_read(); if chunk.len == 0 { break }; output.write_string(chunk); unsafe { chunk.free() }; if output.len > 1024 * 1024 { return error('Preview output limit reached') } }
			p.wait()
			if p.code != 0 { return error('Preview provider failed: ' + failure.str()) }
			return output.str()
		}
		time.sleep(10 * time.millisecond)
	}
}

fn zip_u16(bytes []u8, at int) u16 { return u16(bytes[at]) | u16(bytes[at + 1]) << 8 }
fn zip_u32(bytes []u8, at int) u32 { return u32(bytes[at]) | u32(bytes[at + 1]) << 8 | u32(bytes[at + 2]) << 16 | u32(bytes[at + 3]) << 24 }

struct PreviewZipEntry {
	name string
	method u16
	flags u16
	crc u32
	compressed u32
	size u32
	offset u32
}

fn zip_entries(bytes []u8) ![]PreviewZipEntry {
	if bytes.len < 22 { return error('Truncated ZIP archive') }
	mut end := -1
	for i := bytes.len - 22; i >= 0 && i >= bytes.len - 65557; i-- {
		if zip_u32(bytes, i) == 0x06054b50 && i + 22 + int(zip_u16(bytes, i + 20)) == bytes.len { end = i; break }
	}
	if end < 0 || zip_u16(bytes, end + 4) != 0 || zip_u16(bytes, end + 6) != 0 { return error('ZIP directory unavailable or split archive') }
	count := int(zip_u16(bytes, end + 10))
	mut at := u64(zip_u32(bytes, end + 16))
	boundary := at + u64(zip_u32(bytes, end + 12))
	if count > 4096 || boundary > u64(end) { return error('ZIP directory exceeds limits') }
	mut entries := []PreviewZipEntry{}
	for _ in 0 .. count {
		if at + 46 > boundary || zip_u32(bytes, int(at)) != 0x02014b50 { return error('Malformed ZIP directory') }
		i := int(at)
		length := int(zip_u16(bytes, i + 28))
		next := at + 46 + u64(length) + u64(zip_u16(bytes, i + 30)) + u64(zip_u16(bytes, i + 32))
		if next > boundary { return error('Truncated ZIP entry') }
		entries << PreviewZipEntry{name: bytes[i + 46..i + 46 + length].bytestr(), method: zip_u16(bytes, i + 10), flags: zip_u16(bytes, i + 8), crc: zip_u32(bytes, i + 16), compressed: zip_u32(bytes, i + 20), size: zip_u32(bytes, i + 24), offset: zip_u32(bytes, i + 42)}
		at = next
	}
	return entries
}

struct PreviewInflate {
mut:
	bytes []u8
}

fn preview_inflate_chunk(chunk []u8, user voidptr) int {
	mut sink := unsafe { &PreviewInflate(user) }
	if sink.bytes.len + chunk.len > 1024 * 1024 { return 0 }
	sink.bytes << chunk
	return chunk.len
}

fn zip_content(bytes []u8, entry PreviewZipEntry) ![]u8 {
	i := u64(entry.offset)
	if entry.flags & 1 != 0 || entry.size > 1024 * 1024 || (entry.method == 0 && entry.compressed != entry.size) || i + 30 > u64(bytes.len) || zip_u32(bytes, int(i)) != 0x04034b50 { return error('Encrypted, oversized or invalid office document entry') }
	start := i + 30 + u64(zip_u16(bytes, int(i) + 26)) + u64(zip_u16(bytes, int(i) + 28))
	end := start + u64(entry.compressed)
	if end > u64(bytes.len) { return error('Truncated ZIP content') }
	mut sink := PreviewInflate{bytes: []u8{cap: int(entry.size)}}
	unsafe { sink.bytes.flags |= .noslices }
	if entry.method == 0 { sink.bytes << bytes[int(start)..int(end)] }
	else if entry.method == 8 {
		deflate.decompress_with_callback(bytes[int(start)..int(end)], preview_inflate_chunk, unsafe { &sink }) or { unsafe { sink.bytes.free() }; return err }
	} else { return error('Unsupported office compression') }
	if sink.bytes.len != int(entry.size) || crc32.sum(sink.bytes) != entry.crc { unsafe { sink.bytes.free() }; return error('ZIP content checksum mismatch') }
	return sink.bytes
}

pub fn readable_markup(xml string) string {
	mut out := strings.new_builder(xml.len)
	defer { unsafe { out.free() } }
	mut tag := false
	for ch in xml {
		if ch == `<` { tag = true; out.write_u8(` `) }
		else if ch == `>` { tag = false }
		else if !tag { out.write_u8(ch) }
	}
	return out.str().replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>').replace('&quot;', '"').replace('&apos;', "'")
}

pub fn preview_document(path string, cache_directory string) !Preview {
	before := identify(path)!
	if !before.regular() { return error('Preview needs a readable ordinary file') }
	ext := os.file_ext(path).to_lower()
	defer { unsafe { ext.free() } }
	mut text := ''
	mut image := ''
	mut provider := ''
	if ext in ['.zip', '.docx', '.xlsx', '.pptx', '.odt', '.ods', '.odp', '.epub'] {
		bytes := read_regular(path, 32 * 1024 * 1024)!
		defer { unsafe { bytes.free() } }
		entries := zip_entries(bytes)!
		defer { for entry in entries { unsafe { entry.name.free() } }; unsafe { entries.free() } }
		mut out := strings.new_builder(4096)
		defer { unsafe { out.free() } }
		for entry in entries {
			if ext == '.zip' { out.writeln('${entry.name} (${entry.size} bytes)'); continue }
			if entry.name == 'word/document.xml' || entry.name == 'content.xml' || entry.name == 'xl/sharedStrings.xml' || entry.name.starts_with('xl/worksheets/') || entry.name.starts_with('ppt/slides/slide') || (ext == '.epub' && entry.name.ends_with('.xhtml')) {
				data := zip_content(bytes, entry)!
				markup := data.bytestr()
				plain := readable_markup(markup)
				out.writeln(plain)
				unsafe { data.free(); markup.free(); plain.free() }
				if out.len > 1024 * 1024 { break }
			}
		}
		text = out.str()
		provider = 'Office / ZIP'
	} else if ext == '.pdf' {
		text = preview_program('pdftotext', ['-f', '1', '-l', '8', '-layout', path, '-'])!
		provider = 'Poppler'
		if cache_directory.len > 0 {
			prefix := os.join_path(cache_directory, 'page')
			defer { unsafe { prefix.free() } }
			if _ := preview_program('pdftoppm', ['-f', '1', '-l', '1', '-singlefile', '-scale-to', '640', '-png', path, prefix]) { image = prefix + '.png' }
		}
	} else if ext in ['.mp4', '.mkv', '.webm', '.mov', '.avi', '.mp3', '.wav', '.ogg', '.flac', '.m4a'] {
		text = preview_program('ffprobe', ['-v', 'error', '-show_format', '-show_streams', path])!
		provider = 'FFmpeg'
		if ext in ['.mp4', '.mkv', '.webm', '.mov', '.avi'] {
			image = os.join_path(cache_directory, 'frame.png')
			preview_program('ffmpeg', ['-nostdin', '-v', 'error', '-i', path, '-frames:v', '1', '-vf', 'scale=640:640:force_original_aspect_ratio=decrease', '-y', image]) or { unsafe { image.free() }; image = '' }
		}
	} else if ext in ['.tar', '.tgz', '.gz', '.bz2', '.xz', '.7z', '.rar'] {
		text = preview_program(if ext in ['.7z', '.rar'] { 'bsdtar' } else { 'tar' }, ['-tf', path])!
		provider = 'Archive'
	} else if ext in ['.doc', '.xls', '.ppt', '.rtf'] {
		text = preview_program(if ext == '.xls' { 'xls2csv' } else if ext == '.ppt' { 'catppt' } else { 'catdoc' }, [path])!
		provider = 'Office'
	} else { return error('No preview provider for this file type') }
	if !before.unchanged(identify(path)!) { unsafe { text.free(); image.free() }; return error('File changed during preview') }
	return Preview{text: text, image: image, provider: provider}
}
