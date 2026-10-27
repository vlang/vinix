// SPDX-License-Identifier: GPL-2.0-or-later
// Lossless cold storage for regular-file evidence, with an explicit prior bundle.
// Restore the complete tree and run its original auditor before removing anything.
// Decoder packaging targets this checkpoint's macOS ARM64/Homebrew environment;
// system dylibs and the original prior bundle remain restoration prerequisites.
module main

import crypto.sha256
import encoding.hex
import json2
import os

const chunk_size = u64(64 * 1024 * 1024)

struct Chunk {
	offset u64
	size u64
	hash string
	base_offset u64
	base_size u64
	base_hash string
	payload string
}

struct Entry {
	path string
	kind string
	mode int
	size u64
	hash string
	storage string
	base string
	base_hash string
	payload string
	gzip_header string
	tar_size u64
	tar_hash string
	chunks []Chunk
}

struct Recipe {
	version int = 2
	original string
	prior string
	prior_manifest string
	root_mode int
	zstd string
	zstd_hash string
	gzip_hash string
	gzip_source_hash string
	entries []Entry
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn safe(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains('\\')
		&& !path.contains('\n') && !path.contains('\r') && !path.contains('\t')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

// zstd patch mode cannot accept files above 2 GiB. Bound each input and
// concatenate decoded chunks before checking the original complete tar hash.
fn copy_range(source string, target string, offset u64, size u64) ! {
	length := os.file_size(source)
	if offset > u64(0x7fffffffffffffff) || offset > length || size > length - offset {
		return error('chunk reference outside input')
	}
	mut input := os.open(source)!
	defer { input.close() }
	input.seek(i64(offset), .start)!
	mut output := os.create(target)!
	defer { output.close() }
	append_range(mut input, mut output, size)!
}

struct TarSpan {
	key string
	offset u64
	size u64
}

fn tar_octal(bytes []u8) !u64 {
	mut value := u64(0)
	mut ended := false
	mut started := false
	for b in bytes {
		if b == 0 || b == ` ` {
			if started { ended = true }
			continue
		}
		if ended || b < `0` || b > `7` || value > (u64(0x7fffffffffffffff) - 7) / 8 {
			return error('unsupported tar number')
		}
		started = true
		value = value * 8 + u64(b - `0`)
	}
	return value
}

fn tar_text(bytes []u8) string {
	end := bytes.index(u8(0))
	return if end < 0 { bytes.bytestr() } else { bytes[..end].bytestr() }
}

// These are compression hints, never extraction instructions. Unsupported or
// malformed tar layouts use the original fixed-offset codec. All bytes are
// still covered by chunk, complete tar and original gzip hashes on restoration.
fn tar_spans(path string) ![]TarSpan {
	mut file := os.open(path)!
	defer { file.close() }
	length := os.file_size(path)
	mut offset := u64(0)
	mut header := []u8{len: 512}
	mut spans := []TarSpan{}
	mut occurrences := map[string]int{}
	mut long_name := ''
	for offset < length {
		if length - offset < 512 { return []TarSpan{} }
		file.seek(i64(offset), .start)!
		if file.read(mut header)! != 512 { return error('short tar header') }
		if header.all(it == 0) { break }
		stored_sum := tar_octal(header[148..156]) or { return []TarSpan{} }
		mut sum := u64(0)
		for i, b in header { sum += if i >= 148 && i < 156 { u64(32) } else { u64(b) } }
		if stored_sum != sum { return []TarSpan{} }
		size := tar_octal(header[124..136]) or { return []TarSpan{} }
		data := offset + 512
		if size > length - data { return []TarSpan{} }
		padded := (size + 511) / 512 * 512
		if padded > length - data { return []TarSpan{} }
		type_flag := header[156]
		if type_flag in [u8(`x`), `g`, `S`] { return []TarSpan{} }
		if type_flag == `L` {
			if size > 1024 * 1024 { return []TarSpan{} }
			mut name := []u8{len: int(size)}
			if size > 0 && file.read(mut name)! != int(size) { return error('short tar long name') }
			long_name = tar_text(name)
		} else if type_flag != `K` {
			mut name := tar_text(header[..100])
			if long_name != '' { name = long_name; long_name = '' }
			else if header[257..263] == 'ustar\x00'.bytes() {
				prefix := tar_text(header[345..500])
				if prefix != '' { name = prefix + '/' + name }
			}
			occurrence := occurrences[name]
			occurrences[name] = occurrence + 1
			if type_flag in [u8(0), `0`] && size >= 1024 * 1024 {
				spans << TarSpan{key: name + '\x00' + occurrence.str(), offset: data, size: padded}
			}
		}
		offset = data + padded
	}
	return spans
}

fn chunk_ranges(current string, prior string) ![]Chunk {
	mut bases := map[string]TarSpan{}
	for span in tar_spans(prior)! { bases[span.key] = span }
	mut regions := []Chunk{}
	mut offset := u64(0)
	prior_size := os.file_size(prior)
	total := os.file_size(current)
	for span in tar_spans(current)! {
		if span.key !in bases { continue }
		if span.offset > offset {
			regions << Chunk{offset: offset, size: span.offset - offset,
				base_offset: offset, base_size: if offset < prior_size { prior_size - offset } else { u64(0) }}
		}
		base := bases[span.key]
		regions << Chunk{offset: span.offset, size: span.size, base_offset: base.offset, base_size: base.size}
		offset = span.offset + span.size
	}
	if offset < total {
		regions << Chunk{offset: offset, size: total - offset,
			base_offset: offset, base_size: if offset < prior_size { prior_size - offset } else { u64(0) }}
	}
	mut chunks := []Chunk{}
	for region in regions {
		mut part := u64(0)
		for part < region.size {
			size := if region.size - part < chunk_size { region.size - part } else { chunk_size }
			available := if part < region.base_size { region.base_size - part } else { u64(0) }
			base_size := if available < size { available } else { size }
			chunks << Chunk{offset: region.offset + part, size: size, base_size: base_size,
				base_offset: if base_size > 0 { region.base_offset + part } else { u64(0) }}
			part += size
		}
	}
	return chunks
}

fn append_range(mut input os.File, mut output os.File, size u64) ! {
	mut remaining := size
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for remaining > 0 {
		limit := int(if remaining < u64(buffer.len) { remaining } else { u64(buffer.len) })
		count := input.read(mut buffer[..limit])!
		if count == 0 { return error('unexpected end of chunk input') }
		if output.write(buffer[..count])! != count { return error('short chunk write') }
		remaining -= u64(count)
	}
}

fn walk(root string, relative string) ![]Entry {
	mut entries := []Entry{}
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		path := if relative == '' { name } else { relative + '/' + name }
		full := root + '/' + path
		if !safe(path) || os.is_link(full) { return error('unsafe evidence path: ' + path) }
		info := os.stat(full)!
		mode := int(info.mode) & 0o7777
		if os.is_dir(full) {
			entries << Entry{path: path, kind: 'directory', mode: mode}
			entries << walk(root, path)!
		} else if os.is_file(full) {
			entries << Entry{path: path, kind: 'file', mode: mode, size: os.file_size(full), hash: digest(full)!}
		} else { return error('non-regular evidence: ' + path) }
	}
	return entries
}

fn run(args []string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	// Homebrew's zstd uses both @rpath and absolute library references.
	// Keep its three non-system libraries with the saved decoder.
	if args[0].ends_with('/tools/zstd') {
		mut env := os.environ()
		env['DYLD_LIBRARY_PATH'] = os.dir(os.dir(args[0])) + '/lib'
		p.set_environment(env)
	}
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 0 { return error('command failed (${code}): ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output) }
}

fn manifest(root string) !string {
	mut lines := []string{}
	for e in walk(root, '')! {
		if e.kind == 'file' && e.path != 'archive.sha256' { lines << e.hash + '  ' + e.path }
	}
	return lines.join('\n') + '\n'
}

fn load_archive(archive string) !Recipe {
	if manifest(archive)! != os.read_file(archive + '/archive.sha256')! {
		return error('archive inventory mismatch')
	}
	r := json2.decode[Recipe](os.read_file(archive + '/recipe.json')!)!
	if r.version !in [1, 2] || !os.is_abs_path(r.original) || !os.is_abs_path(r.prior)
		|| r.root_mode < 0 || r.root_mode > 0o7777
		|| digest(r.prior + '/manifest.sha256')! != r.prior_manifest {
		return error('wrong prior bundle or archive version')
	}
	if digest(archive + '/tools/zstd')! != r.zstd_hash
		|| digest(archive + '/tools/gzip')! != r.gzip_hash { return error('decoder executable changed') }
	mut seen := map[string]string{}
	for e in r.entries {
		if !safe(e.path) || e.path in seen || e.mode < 0 || e.mode > 0o7777
			|| e.kind !in ['file', 'directory'] { return error('invalid entry') }
		parent := os.dir(e.path)
		if parent != '.' && seen[parent] != 'directory' { return error('invalid entry parent') }
		seen[e.path] = e.kind
		if e.kind == 'directory' { continue }
		if e.storage !in ['prior', 'literal', 'gzip-prior-patch', 'bundle-patch']
			|| e.hash.len != 64 { return error('invalid storage or digest') }
		if e.storage != 'literal' && (!safe(e.base) || e.base_hash.len != 64) {
			return error('invalid base')
		}
		if e.storage !in ['prior', 'gzip-prior-patch'] && (!safe(e.payload) || !e.payload.starts_with('payload/')) {
			return error('invalid payload')
		}
		if e.storage == 'gzip-prior-patch' {
			if e.gzip_header.len != 20 || e.tar_hash.len != 64 || e.tar_size == 0
				|| e.chunks.len == 0 || e.payload != '' { return error('invalid gzip reconstruction') }
			header := hex.decode(e.gzip_header)!
			if header[..4] != [u8(31), 139, 8, 0] || header[8] !in [u8(2), 4] {
				return error('unsupported gzip header')
			}
			mut offset := u64(0)
			for chunk in e.chunks {
				if chunk.offset != offset || chunk.size == 0 || chunk.size > chunk_size
					|| offset > e.tar_size || chunk.size > e.tar_size - offset
					|| chunk.hash.len != 64 || chunk.base_size > chunk_size
					|| chunk.base_offset > u64(0x7fffffffffffffff)
					|| (r.version == 1 && chunk.base_offset != 0)
					|| (chunk.base_size == 0 && chunk.base_offset != 0)
					|| (chunk.base_size > 0 && chunk.base_hash.len != 64)
					|| (chunk.base_size == 0 && chunk.base_hash != '')
					|| !safe(chunk.payload) || !chunk.payload.starts_with('payload/') {
					return error('invalid gzip chunk')
				}
				offset += chunk.size
			}
			if offset != e.tar_size { return error('incomplete gzip chunks') }
		} else if e.chunks.len != 0 { return error('unexpected chunks')
		}
	}
	return r
}

fn restore(archive string, target string, work string) ! {
	r := load_archive(archive)!
	if os.exists(target) || os.is_link(target) || target.starts_with(r.prior + '/')
		|| target.starts_with(archive + '/') { return error('unsafe or existing restore target') }
	if os.exists(work) || os.is_link(work) || work.starts_with(target + '/')
		|| work.starts_with(r.prior + '/') || work.starts_with(archive + '/')
		|| target.starts_with(work + '/') { return error('unsafe scratch directory') }
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(target)!
	mut done := map[string]bool{}
	mut pending := map[string]bool{}
	for e in r.entries {
		if e.kind == 'directory' { os.mkdir_all(target + '/' + e.path)! }
		else { restore_entry(r, archive, target, work, e, mut done, mut pending)! }
	}
	// Apply directory permissions after populating the tree.
	for e in r.entries { if e.kind == 'directory' { os.chmod(target + '/' + e.path, e.mode)! } }
	os.chmod(target, r.root_mode)!
	compare(r, target)!
}

fn decode_gzip(gzip string, source string, output string) ! {
	os.cp(source, output + '.gz')!
	run([gzip, '-d', output + '.gz'])!
}

fn create(source string, prior string, archive string, zstd string, work string) ! {
	if os.exists(archive) { return error('archive already exists') }
	if archive.starts_with(source + '/') || archive.starts_with(prior + '/')
		|| os.is_link(source) || os.is_link(prior) { return error('unsafe archive location') }
	if os.exists(work) || os.is_link(work) || work.starts_with(source + '/')
		|| work.starts_with(prior + '/') || work.starts_with(archive + '/') { return error('unsafe scratch directory') }
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	if !os.is_file(source + '/manifest.sha256') { return error('source is not sealed') }
	prior_manifest := digest(prior + '/manifest.sha256')!
	current_vm := os.file_name(os.read_file(source + '/probe-no-ads-state.txt')!.trim_space())
	prior_vm := os.file_name(os.read_file(prior + '/probe-no-ads-state.txt')!.trim_space())
	mut entries := []Entry{}
	os.mkdir_all(archive + '/payload')!
	os.mkdir_all(archive + '/tools')!
	os.mkdir_all(archive + '/lib')!
	os.cp(zstd, archive + '/tools/zstd')!
	os.cp('/usr/bin/gzip', archive + '/tools/gzip')!
	for library in [os.dir(os.dir(zstd)) + '/lib/libzstd.1.dylib',
		'/opt/homebrew/opt/xz/lib/liblzma.5.dylib', '/opt/homebrew/opt/lz4/lib/liblz4.1.dylib'] {
		os.cp(os.real_path(library), archive + '/lib/' + os.file_name(library))!
	}
	os.chmod(archive + '/tools/zstd', 0o755)!
	os.chmod(archive + '/tools/gzip', 0o755)!
	// A copied Apple platform executable needs a local signature to run.
	run(['/usr/bin/codesign', '--force', '--sign', '-', archive + '/tools/gzip'])!
	for index, e in walk(source, '')! {
		if e.kind == 'directory' { entries << e; continue }
		candidate := if e.path.starts_with(current_vm + '/') {
			prior_vm + e.path[current_vm.len..]
		} else { e.path }
		base_path := prior + '/' + candidate
		if os.is_file(base_path) && !os.is_link(base_path)
			&& os.file_size(base_path) == e.size && digest(base_path)! == e.hash {
			entries << Entry{...e, storage: 'prior', base: candidate, base_hash: e.hash}
			continue
		}
		mut payload := 'payload/' + index.str() + '.zst'
		mut storage := 'literal'
		mut base := ''
		mut base_hash := ''
		mut input := source + '/' + e.path
		mut gzip_header := ''
		mut tar_size := u64(0)
		mut tar_hash := ''
		mut chunks := []Chunk{}
		mut args := [zstd, '-q', '-3', '--long=31']
		if e.path == current_vm + '/boot.img' {
			storage = 'bundle-patch'
			base = current_vm + '/initramfs.tar.gz'
			base_hash = digest(source + '/' + base)!
			args << '--patch-from=' + source + '/' + base
		} else if e.path == current_vm + '/initramfs.tar.gz' {
			storage = 'gzip-prior-patch'
			base = candidate
			base_hash = digest(base_path)!
			mut compressed := os.open(input)!
			mut header := []u8{len: 10}
			count := compressed.read(mut header) or { compressed.close(); return err }
			compressed.close()
			if count != 10 || header[..4] != [u8(31), 139, 8, 0]
				|| header[8] !in [u8(2), 4] { return error('unsupported gzip header') }
			gzip_header = header.hex()
			decode_gzip('/usr/bin/gzip', base_path, work + '/prior.tar')!
			decode_gzip('/usr/bin/gzip', input, work + '/current.tar')!
			input = work + '/current.tar'
			tar_size = os.file_size(input)
			tar_hash = digest(input)!
			for range in chunk_ranges(input, work + '/prior.tar')! {
				copy_range(input, work + '/current.chunk', range.offset, range.size)!
				mut patch_args := [zstd, '-q', '-3', '--long=31']
				mut chunk_base_hash := ''
				if range.base_size > 0 {
					copy_range(work + '/prior.tar', work + '/prior.chunk', range.base_offset, range.base_size)!
					chunk_base_hash = digest(work + '/prior.chunk')!
					patch_args << '--patch-from=' + work + '/prior.chunk'
				}
				chunk_payload := 'payload/' + index.str() + '-' + chunks.len.str() + '.zst'
				patch_args << [work + '/current.chunk', '-o', archive + '/' + chunk_payload]
				run(patch_args)!
				chunks << Chunk{...range, hash: digest(work + '/current.chunk')!,
					base_hash: chunk_base_hash, payload: chunk_payload}
			}
			payload = ''
		}
		if storage != 'gzip-prior-patch' {
			args << [input, '-o', archive + '/' + payload]
			run(args)!
		}
		entries << Entry{...e, storage: storage, base: base, base_hash: base_hash, payload: payload,
			gzip_header: gzip_header, tar_size: tar_size, tar_hash: tar_hash, chunks: chunks}
	}
	r := Recipe{original: source, prior: prior, prior_manifest: prior_manifest,
		root_mode: int(os.stat(source)!.mode) & 0o7777, zstd: zstd,
		zstd_hash: digest(zstd)!, gzip_hash: digest(archive + '/tools/gzip')!,
		gzip_source_hash: digest('/usr/bin/gzip')!, entries: entries}
	os.write_file(archive + '/recipe.json', json2.encode(r, prettify: true))!
	os.cp(@FILE, archive + '/archiver.v')!
	os.write_file(archive + '/archive.sha256', manifest(archive)!)!
	load_archive(archive)!
	println('Archive sealed: ' + digest(archive + '/archive.sha256')!)
}

fn restore_entry(r Recipe, archive string, target string, work string, e Entry, mut done map[string]bool,
	mut pending map[string]bool) ! {
	if e.path in done { return }
	if e.path in pending { return error('cyclic archive dependency') }
	pending[e.path] = true
	mut base_path := r.prior + '/' + e.base
	if e.storage == 'bundle-patch' {
		mut found := false
		for dependency in r.entries {
			if dependency.path == e.base && dependency.kind == 'file' {
				restore_entry(r, archive, target, work, dependency, mut done, mut pending)!
				found = true
				break
			}
		}
		if !found { return error('missing archive dependency') }
		base_path = target + '/' + e.base
	}
	if e.storage != 'literal' && (os.is_link(base_path) || digest(base_path)! != e.base_hash) {
		return error('changed base file: ' + e.base)
	}
	path := target + '/' + e.path
	os.mkdir_all(os.dir(path))!
	if e.storage == 'prior' { os.cp(base_path, path)! }
	else {
		mut output := path
		if e.storage == 'gzip-prior-patch' {
			decode_gzip(archive + '/tools/gzip', base_path, work + '/prior.tar')!
			base_path = work + '/prior.tar'
			output = work + '/current.tar'
			restore_chunks(r.version, archive, work, e)!
		} else {
			mut args := [archive + '/tools/zstd', '-q', '-d', '--memory=2048MB']
			if e.storage == 'bundle-patch' { args << '--patch-from=' + base_path }
			args << [archive + '/' + e.payload, '-o', output]
			run(args)!
		}
		if e.storage == 'gzip-prior-patch' {
			if os.file_size(output) != e.tar_size || digest(output)! != e.tar_hash {
				return error('reconstructed tar mismatch')
			}
			header := hex.decode(e.gzip_header)!
			level := if header[8] == 4 { '-1' } else { '-9' }
			run([archive + '/tools/gzip', level, '-n', output])!
			mut encoded := os.open_file(output + '.gz', 'r+')!
			encoded.write(hex.decode(e.gzip_header)!)!
			encoded.close()
			os.mv(output + '.gz', path)!
			os.rm(work + '/prior.tar')!
		}
	}
	if os.file_size(path) != e.size || digest(path)! != e.hash { return error('restored file mismatch: ' + e.path) }
	os.chmod(path, e.mode)!
	done[e.path] = true
	pending.delete(e.path)
}

fn restore_chunks(version int, archive string, work string, e Entry) ! {
	mut output := os.create(work + '/current.tar')!
	defer { output.close() }
	for chunk in e.chunks {
		mut args := [archive + '/tools/zstd', '-q', '-d', '-f', '--memory=2048MB']
		if chunk.base_size > 0 {
			base_offset := if version == 1 { chunk.offset } else { chunk.base_offset }
			copy_range(work + '/prior.tar', work + '/prior.chunk', base_offset, chunk.base_size)!
			if digest(work + '/prior.chunk')! != chunk.base_hash { return error('changed prior tar chunk') }
			args << '--patch-from=' + work + '/prior.chunk'
		}
		args << [archive + '/' + chunk.payload, '-o', work + '/current.chunk']
		run(args)!
		if os.file_size(work + '/current.chunk') != chunk.size
			|| digest(work + '/current.chunk')! != chunk.hash { return error('restored chunk mismatch') }
		mut input := os.open(work + '/current.chunk')!
		append_range(mut input, mut output, chunk.size) or { input.close(); return err }
		input.close()
	}
}

fn compare(r Recipe, target string) ! {
	actual := walk(target, '')!
	if actual.len != r.entries.len || int(os.stat(target)!.mode) & 0o7777 != r.root_mode {
		return error('restored tree size or root permissions mismatch')
	}
	for index, expected in r.entries {
		a := actual[index]
		if a.path != expected.path || a.kind != expected.kind || a.mode != expected.mode
			|| a.size != expected.size || a.hash != expected.hash { return error('restored inventory mismatch: ' + expected.path) }
	}
}

fn reject_load(archive string) ! {
	load_archive(archive) or { return }
	return error('selftest accepted invalid archive')
}

fn reject_restore(archive string, target string, work string) ! {
	restore(archive, target, work) or { return }
	return error('selftest accepted invalid restoration')
}

fn reject_compare(r Recipe, target string) ! {
	compare(r, target) or { return }
	return error('selftest accepted changed restored tree')
}

fn reseal(archive string, r Recipe) ! {
	os.write_file(archive + '/recipe.json', json2.encode(r, prettify: true))!
	os.write_file(archive + '/archive.sha256', manifest(archive)!)!
}

fn alignment_selftest(root string, zstd string) ! {
	prior := root + '/aligned-prior'
	source := root + '/aligned-source'
	archive := root + '/aligned-archive'
	work := root + '/aligned-work'
	large_name := 'large-' + 'a'.repeat(150)
	// Incompressible shared content spans two codec chunks and has a GNU long
	// name. Reorder it and shift both its header and data in the current tar.
	mut raw := []u8{len: int(chunk_size) + 513}
	mut random := u64(0x8bd27e145a936fc1)
	for i in 0 .. raw.len {
		random ^= random << 13
		random ^= random >> 7
		random ^= random << 17
		raw[i] = u8(random >> 32)
	}
	for base in [prior, source] {
		os.mkdir_all(base + '/probe-no-ads-aligned')!
		os.mkdir_all(base + '/inputs')!
		os.write_file(base + '/manifest.sha256', 'aligned synthetic fixture\n')!
		os.write_file(base + '/probe-no-ads-state.txt', base + '/probe-no-ads-aligned\n')!
		os.write_file_array(base + '/inputs/' + large_name, raw)!
		os.write_file(base + '/inputs/prefix', if base == prior { 'old' } else { 'changed'.repeat(2000) })!
		os.write_file_array(base + '/inputs/tail', raw[..2 * 1024 * 1024])!
		members := if base == prior { ['prefix', large_name, 'tail'] } else { ['tail', 'prefix', large_name] }
		mut tar_args := ['/usr/bin/tar', '--format=gnutar', '-cf', base + '/probe-no-ads-aligned/initramfs.tar',
			'-C', base + '/inputs']
		tar_args << members
		run(tar_args)!
		os.rmdir_all(base + '/inputs')!
		run(['/usr/bin/gzip', if base == source { '-1' } else { '-9' }, '-n', base + '/probe-no-ads-aligned/initramfs.tar'])!
	}
	create(source, prior, archive, zstd, work)!
	r := load_archive(archive)!
	e := r.entries.filter(it.storage == 'gzip-prior-patch')[0]
	if r.version != 2 || e.chunks.filter(it.base_size > 0 && it.base_offset != it.offset).len < 3 {
		return error('moved multi-chunk tar members not aligned')
	}
	mut payload_bytes := u64(0)
	for chunk in e.chunks { payload_bytes += os.file_size(archive + '/' + chunk.payload) }
	if payload_bytes >= 1024 * 1024 { return error('aligned shared random data was stored literally') }
	restore(archive, root + '/aligned-restored', work)!
	for base_offset in [u64(0x8000000000000000), u64(0x7fffffffffffffff), u64(1)] {
		mut chunks := e.chunks.clone()
		index := chunks.index(chunks.filter(it.base_size > 0 && it.base_offset != it.offset)[0])
		chunks[index] = Chunk{...chunks[index], base_offset: base_offset}
		mut entries := r.entries.clone()
		for i, entry in entries { if entry.path == e.path { entries[i] = Entry{...entry, chunks: chunks} } }
		reseal(archive, Recipe{...r, entries: entries})!
		if base_offset > u64(0x7fffffffffffffff) { reject_load(archive)! }
		else { reject_restore(archive, root + '/bad-aligned-' + base_offset.str(), work)! }
	}
	reseal(archive, r)!
	load_archive(archive)!
	compare(r, root + '/aligned-restored')!
	println('Selftest: shifted/reordered GNU long-name tar members, shared random data across multiple chunks, level-1 gzip from level-9 prior, exact restoration and three invalid reference offsets: PASS')
}

fn selftest(root string, zstd string) ! {
	if os.exists(root) || os.is_link(root) { return error('selftest requires a fresh directory') }
	source := root + '/source'
	prior := root + '/prior'
	archive := root + '/archive'
	target := root + '/restored'
	work := root + '/work'
	for base in [prior, source] {
		vm := if base == prior { 'probe-no-ads-old' } else { 'probe-no-ads-new' }
		os.mkdir_all(base + '/' + vm)!
		os.mkdir_all(base + '/empty')!
		os.write_file(base + '/manifest.sha256', 'synthetic sealed fixture\n')!
		os.write_file(base + '/probe-no-ads-state.txt', base + '/' + vm + '\n')!
		os.write_file(base + '/unchanged', 'shared evidence\n')!
		os.chmod(base + '/unchanged', 0o640)!
		os.chmod(base + '/empty', 0o750)!
		os.write_file(base + '/literal', if base == prior { 'old' } else { 'changed literal' })!
		// Compress a deterministic large shared input with a small content change.
		mut raw := []u8{len: int(chunk_size) + 129, init: u8(index % 251)}
		if base == source { raw[500_000] ^= 1 }
		os.write_file_array(base + '/' + vm + '/initramfs.tar', raw)!
		run(['/usr/bin/gzip', '-9', '-n', base + '/' + vm + '/initramfs.tar'])!
		mut boot := os.read_bytes(base + '/' + vm + '/initramfs.tar.gz')!
		boot << 'boot suffix'.bytes()
		os.write_file_array(base + '/' + vm + '/boot.img', boot)!
	}
	os.chmod(source, 0o750)!
	create(source, prior, archive, zstd, work)!
	r := load_archive(archive)!
	for storage in ['prior', 'literal', 'gzip-prior-patch', 'bundle-patch'] {
		if !r.entries.any(it.storage == storage) { return error('unexercised codec: ' + storage) }
	}
	gzip_entry := r.entries.filter(it.storage == 'gzip-prior-patch')[0]
	if gzip_entry.chunks.len != 2 { return error('multi-chunk reconstruction not exercised') }
	restore(archive, target, work)!
	compare(r, target)!
	println('Selftest: four storage modes, multiple chunks, exact gzip, modes, empty directory and complete inventory: PASS')
	// Version 1 recipes had no base_offset field and used each output offset.
	mut legacy_entries := r.entries.clone()
	for i, e in legacy_entries {
		if e.storage == 'gzip-prior-patch' {
			mut chunks := []Chunk{}
			for chunk in e.chunks { chunks << Chunk{...chunk, base_offset: 0} }
			legacy_entries[i] = Entry{...e, chunks: chunks}
		}
	}
	legacy := Recipe{...r, version: 1, entries: legacy_entries}
	reseal(archive, legacy)!
	restore(archive, root + '/legacy-restored', work)!
	compare(legacy, root + '/legacy-restored')!
	reseal(archive, r)!
	println('Selftest: version 1 fixed-offset recipe restoration: PASS')

	// Corruption without resealing must fail inventory validation.
	payload := archive + '/' + r.entries.filter(it.storage == 'literal')[0].payload
	saved_payload := os.read_bytes(payload)!
	os.write_file(payload, 'corrupt')!
	reject_load(archive)!
	os.write_file_array(payload, saved_payload)!
	saved_manifest := os.read_file(prior + '/manifest.sha256')!
	os.write_file(prior + '/manifest.sha256', 'changed')!
	reject_load(archive)!
	os.write_file(prior + '/manifest.sha256', saved_manifest)!
	os.write_file(prior + '/unchanged', 'changed base')!
	reject_restore(archive, root + '/bad-base', work)!
	os.write_file(prior + '/unchanged', 'shared evidence\n')!
	reject_restore(archive, target, work)!

	// Even resealed malformed recipes must fail before writing outside TARGET.
	for bad in [
		Recipe{...r, root_mode: -1},
		Recipe{...r, zstd_hash: 'invalid'},
		Recipe{...r, entries: [Entry{path: '../escape', kind: 'directory'}]},
		Recipe{...r, entries: [Entry{path: 'absent/child', kind: 'directory'}]},
		Recipe{...r, entries: [r.entries[0], r.entries[0]]},
		Recipe{...r, entries: [Entry{path: 'file', kind: 'file', storage: 'literal', hash: '0'.repeat(64), payload: '../escape'}]},
	] {
		reseal(archive, bad)!
		reject_load(archive)!
	}
	cyclic := r.entries.filter(it.storage == 'bundle-patch')[0]
	mut cyclic_entries := r.entries.clone()
	for i, e in cyclic_entries { if e.path == cyclic.path { cyclic_entries[i] = Entry{...e, base: e.path} } }
	reseal(archive, Recipe{...r, entries: cyclic_entries})!
	reject_restore(archive, root + '/cyclic', work)!
	reseal(archive, r)!
	for bad_chunk in [
		Chunk{...gzip_entry.chunks[0], offset: 1},
		Chunk{...gzip_entry.chunks[0], size: chunk_size + 1},
		Chunk{...gzip_entry.chunks[0], payload: '../escape'},
		Chunk{...gzip_entry.chunks[0], base_hash: ''},
	] {
		mut bad_entries := r.entries.clone()
		mut bad_chunks := gzip_entry.chunks.clone()
		bad_chunks[0] = bad_chunk
		for i, e in bad_entries { if e.path == gzip_entry.path { bad_entries[i] = Entry{...e, chunks: bad_chunks} } }
		reseal(archive, Recipe{...r, entries: bad_entries})!
		reject_load(archive)!
	}
	mut missing_entries := r.entries.clone()
	for i, e in missing_entries {
		if e.path == gzip_entry.path { missing_entries[i] = Entry{...e, chunks: [gzip_entry.chunks[0]]} }
	}
	reseal(archive, Recipe{...r, entries: missing_entries})!
	reject_load(archive)!
	reseal(archive, r)!

	os.write_file(target + '/extra', 'unexpected')!
	reject_compare(r, target)!
	os.rm(target + '/extra')!
	os.rm(target + '/literal')!
	reject_compare(r, target)!
	os.write_file(target + '/literal', 'wrong contents')!
	reject_compare(r, target)!
	os.write_file(target + '/literal', 'changed literal')!
	os.chmod(target + '/unchanged', 0o600)!
	reject_compare(r, target)!
	os.chmod(target + '/unchanged', 0o640)!
	os.rmdir(target + '/empty')!
	os.write_file(target + '/empty', '')!
	reject_compare(r, target)!
	os.rm(target + '/empty')!
	os.mkdir(target + '/empty')!
	os.chmod(target + '/empty', 0o750)!
	os.chmod(target, 0o755)!
	reject_compare(r, target)!
	os.chmod(target, 0o750)!
	compare(r, target)!
	println('Selftest: 22 negative controls rejected; final complete inventory: PASS')
	alignment_selftest(root, zstd)!
}

fn main() {
	if os.args.len < 3 { panic('usage: evidence-delta-archive create SOURCE PRIOR ARCHIVE ZSTD WORK | verify ARCHIVE | restore ARCHIVE TARGET WORK | compare ARCHIVE TARGET | selftest FRESH_DIR ZSTD') }
	match os.args[1] {
		'create' {
			if os.args.len != 7 { panic('create needs SOURCE PRIOR ARCHIVE ZSTD WORK') }
			create(os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.real_path(os.args[5]), os.abs_path(os.args[6]))!
		}
		'verify' {
			if os.args.len != 3 { panic('verify needs ARCHIVE') }
			load_archive(os.abs_path(os.args[2]))!
			println('Archive hashes and prior manifest: PASS')
		}
		'restore' {
			if os.args.len != 5 { panic('restore needs ARCHIVE TARGET WORK') }
			restore(os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]))!
			println('Complete restored typed inventory: PASS')
		}
		'compare' {
			if os.args.len != 4 { panic('compare needs ARCHIVE TARGET') }
			compare(load_archive(os.abs_path(os.args[2]))!, os.abs_path(os.args[3]))!
			println('Complete typed inventory: PASS')
		}
		'selftest' {
			if os.args.len != 4 { panic('selftest needs FRESH_DIR ZSTD') }
			selftest(os.abs_path(os.args[2]), os.real_path(os.args[3]))!
		}
		else { panic('unknown archive command') }
	}
}
