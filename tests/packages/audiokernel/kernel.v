// SPDX-License-Identifier: GPL-2.0-or-later
// The small local kernel copy depends on the original complete external audit.
module audiokernel

import json2
import hwhost
import os
import tests.packages.audioprepare

// The reviewed minimal copy remains dependent on its original complete audit.
const reviewed_seal = '7634b22ea52902e1d923f91543703398e46d3e679694f52c880fef7e25e44ddf'
const audit_root = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026'
const audit_manifest = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json'
const audit_checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const audit_checker_source = '/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v'
const critical_sources = {
	'kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
	'kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
	'kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
	'kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
	'kernel/socket/public/public.v': '19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a'
	'kernel/socket/socket.v': '98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8'
	'kernel/socket/unix/unix.v': 'c869568959cd09e16b58dbcc5400b49fdb0a1cb27275d0b73c430dce8f82f810'
}

pub struct Build {
pub:
	elf_path string
	elf_sha256 string
	generated_c_path string
	generated_c_sha256 string
	build_log_path string
	build_log_sha256 string
	build_flags []string
}

pub struct Audit {
pub:
	root string
	manifest_path string
	manifest_sha256 string
	checker_path string
	checker_sha256 string
	checker_source_path string
	checker_source_sha256 string
}

pub struct Seal {
pub:
	format int
	profile string
	source_revision string
	source_patch_path string
	source_patch_sha256 string
	source_inventory_path string
	source_inventory_sha256 string
	critical_sources map[string]string
	kernels map[string]Build
	audit Audit
}

struct Format {
	format int
}

struct AuditCheck {
	format int = 1
	result string = 'PASS'
	audit Audit
	log_sha256 string
}

fn hex(value string, size int) bool {
	return value.len == size && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path
		|| path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute kernel evidence path: ' + path)
	}
}

fn bounded(path string) !string {
	audioprepare.regular(path)!
	if os.lstat(path)!.size > 1024 * 1024 { return error('kernel metadata exceeds limit: ' + path) }
	return os.read_file(path)
}

fn sealed_file(root string, relative string, sum string) ! {
	if relative == '' || os.is_abs_path(relative) || relative.contains('\\')
		|| relative.split('/').any(it in ['', '.', '..']) || !hex(sum, 64) {
		return error('invalid matched kernel input: ' + relative)
	}
	path := root + '/' + relative
	canonical(path)!
	if audioprepare.digest(path)! != sum { return error('matched kernel input differs: ' + relative) }
}

fn absolute_file(path string, sum string) ! {
	canonical(path)!
	if !hex(sum, 64) || audioprepare.digest(path)! != sum {
		return error('required complete kernel audit input differs: ' + path)
	}
}

fn target_elf(path string, architecture string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 64}
	if file.read(mut header)! != header.len || header[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1]
		|| header[16] != 2 || header[17] != 0
		|| int(header[18]) + (int(header[19]) << 8) != if architecture == 'aarch64' { 183 } else { 62 } {
		return error('requires matched architecture ET_EXEC ELF64: ' + path)
	}
}

// A format probe selects a separate branch; format 1 remains the caller's
// historical implementation. Unknown formats are not admitted here.
pub fn matched(root string) !bool {
	return json2.decode[Format](bounded(root + '/kernel-seal.json')!)!.format == 2
}

// This is read-only, including on --verify-prepared. It establishes reviewed
// identity, not completeness of the external audit. Admission must also execute
// the pinned checker's fixed `check ROOT MANIFEST` command successfully.
pub fn validate(root string, architecture string, selected_kernel_sha256 string) !Seal {
	canonical(root)!
	if os.lstat(root)!.mode & 0o170000 != 0o040000 || architecture !in ['aarch64', 'x86_64'] {
		return error('requires ordinary matched kernel evidence and supported architecture')
	}
	path := root + '/kernel-seal.json'
	if !hex(reviewed_seal, 64) || audioprepare.digest(path)! != reviewed_seal {
		return error('requires independently reviewed matched kernel seal')
	}
	text := bounded(path)!
	seal := json2.decode[Seal](text)!
	// Exact typed encoding rejects unknown, ignored or repeated JSON fields.
	if text != json2.encode(seal) + '\n' || seal.format != 2
		|| seal.profile != 'matched-peer-frame-atomic-fresh-20261026'
		|| seal.source_revision != '9acefa77bee69247c837e97987a2377536aa41cc'
		|| seal.source_patch_path != 'source.patch' || seal.source_inventory_path != 'source-inputs.sha256'
		|| seal.critical_sources != critical_sources || seal.kernels.len != 2 {
		return error('matched kernel profile, schema or seven reviewed sources differ')
	}
	sealed_file(root, seal.source_patch_path, seal.source_patch_sha256)!
	sealed_file(root, seal.source_inventory_path, seal.source_inventory_sha256)!
	mut inventory := map[string]string{}
	for line in bounded(root + '/' + seal.source_inventory_path)!.split_into_lines() {
		if line.len < 67 || line[64..66] != '  ' { return error('invalid matched source inventory line') }
		name := line[66..]
		if name in inventory || critical_sources[name] != line[..64] { return error('matched source inventory differs') }
		inventory[name] = line[..64]
	}
	if inventory != critical_sources { return error('matched source inventory omits reviewed sources') }
	for source, sum in critical_sources { sealed_file(root, 'source/' + source, sum)! }
	for arch in ['aarch64', 'x86_64'] {
		build := seal.kernels[arch] or { return error('missing matched kernel architecture') }
		if build.elf_path != 'kernel-' + arch + '/bin/vinix'
			|| build.generated_c_path != 'kernel-' + arch + '/obj/blob.c'
			|| build.build_log_path != 'build-' + arch + '.log'
			|| build.build_flags != ['ARCH=' + arch, 'ALLOC_TRACK=1', 'PROD=true',
				if arch == 'aarch64' { 'LIMINE_MP=1' } else { 'LIMINE_MP=0' }] {
			return error('matched kernel build paths or four flags differ')
		}
		sealed_file(root, build.elf_path, build.elf_sha256)!
		sealed_file(root, build.generated_c_path, build.generated_c_sha256)!
		sealed_file(root, build.build_log_path, build.build_log_sha256)!
		target_elf(root + '/' + build.elf_path, arch)!
		if arch == architecture && build.elf_sha256 != selected_kernel_sha256 {
			return error('selected audio kernel differs from matched reviewed ELF')
		}
	}
	audit := seal.audit
	if audit.root != audit_root || audit.manifest_path != audit_manifest
		|| audit.checker_path != audit_checker || audit.checker_source_path != audit_checker_source {
		return error('requires original complete matched kernel audit at reviewed canonical paths')
	}
	canonical(audit.root)!
	if os.lstat(audit.root)!.mode & 0o170000 != 0o040000 { return error('missing original complete matched kernel audit') }
	absolute_file(audit.manifest_path, audit.manifest_sha256)!
	absolute_file(audit.checker_path, audit.checker_sha256)!
	absolute_file(audit.checker_source_path, audit.checker_source_sha256)!
	if os.lstat(audit.checker_path)!.mode & 0o111 == 0 { return error('complete kernel audit checker is not executable') }
	return seal
}

// The reviewed checker is a leaf: check only reads/lstats/hashes the complete
// original bundle and starts no descendants. run_tool bounds and reaps that
// child; it inherits the caller's process group so an outer nativeguard still
// owns it. Do not replace this with a nested group that can escape that owner.
pub fn check_audit(root string, architecture string, selected_kernel_sha256 string, log string) ! {
	seal := validate(root, architecture, selected_kernel_sha256)!
	canonical(os.dir(log))!
	if os.lstat(os.dir(log))!.mode & 0o170000 != 0o040000 || os.join_path(os.dir(log), os.base(log)) != log {
		return error('complete kernel audit log requires an ordinary canonical parent')
	}
	for path in [log, log + '.argv.json', log + '.checked.json'] {
		if os.exists(path) || os.is_link(path) { return error('complete kernel audit log must be fresh: ' + path) }
	}
	argv := [seal.audit.checker_path, 'check', seal.audit.root, seal.audit.manifest_path]
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	hwhost.run_tool(argv, map[string]string{}, log, 300)!
	if os.read_file(log)! != 'FRAME-PAGE COMPLETE STATE CHECK PASS\n' {
		return error('required complete kernel audit checker output differs')
	}
	validate(root, architecture, selected_kernel_sha256)!
	os.write_file(log + '.checked.json', json2.encode(AuditCheck{
		audit: seal.audit, log_sha256: audioprepare.digest(log)!
	}) + '\n')!
}
