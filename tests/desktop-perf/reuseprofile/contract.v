// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed immutable-media continuation. Historical adapters and receipts are inputs.
module reuseprofile

import crypto.sha256
import json2
import os

pub const runtime_root = '/Users/alex/code/vinix/build/package-perf-runtime-worktree'
pub const cache_root = '/Users/alex/Library/Caches/vinix-codex/section14'
pub const origin_root = cache_root + '/perf-six-x86-retry-20261105-01'
pub const origin_state = origin_root + '/prepared-atomic-01'
pub const retry_root = cache_root + '/perf-six-x86-reuse-20261105-01'
pub const origin_manifest = cache_root + '/perf-runtime-host-20261105-01/retry-runtime-inventory-01/primary.tsv'
pub const origin_manifest_sha = 'c1bb658176983b19d8c2f907f85a426fa9ac91006ed14e5b9f6ca7a63dd4a763'
pub const origin_prepared_sha = '3ff9312276e36f00a9802457b1c2eea99eeb51375ea42e6a0adee28c12488fc4'
pub const literal_tool = cache_root + '/literal-manifest-host-20261105-01/production-03/literal-manifest'
pub const literal_tool_sha = '30a48af5d270e03950314a66b1376a3b311ef100f0f6d59d01d388d048991001'
pub const base_root = '/Users/alex/code/vinix/build-release/work/amd64-desktop/initramfs-root'
pub const base_manifest_sha = 'fcb2e4351b11b733da9b6a1e5fb182097968773a7af71d3ae3274d77c949ea52'
pub const staged_manifest_sha = '489412638637a0ecec5af0013b75b0baed63165e970ba8cfa16473a0ec82cf77'
pub const sysroot = '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/x86_64-linux-musl'
pub const gcc_root = '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/lib/gcc/x86_64-linux-musl/14.2.0'
pub const sysroot_manifest_sha = 'd94776809a40e6ca417515710c5539f1c184ce29233e68f54545127f456eff24'
pub const gcc_manifest_sha = 'da171d36f66ed226bc0ea32fa8de4636fb1e72af4d5fb84899dfc69ad080a6e3'
pub const frozen_origin_disk_sha = '897cf727f24cb1922c34267095d669a372feaee3fd4b0e6a25b266f11cfeb526'
pub const original_disk_sha = '8868988513e6af3dfa9e63aa3b94b39a189f8b03400362203960f7484ece3ccf'
pub const mkfs_tool = '/opt/homebrew/Cellar/e2fsprogs/1.47.4/sbin/mkfs.ext2'
pub const mkfs_sha = '66298f2a13300c886212a39338b748c668339b4dffe270fa55d2126b77e55408'
pub const qemu = '/opt/homebrew/Cellar/qemu/11.1.1/bin/qemu-system-x86_64'
pub const firmware = '/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-x86_64-code.fd'
pub const desktop = cache_root + '/integration-20261026/routing-retained-inputs/desktop-x86_64/vinix-desktop'
pub const kernel = cache_root + '/matched-peer-frame-atomic-fresh-kernel-20261026/kernel-x86_64/bin/vinix'
const original_socket = '/tmp/vinix-perf-x86-3df78bfad57764f5.qmp'

pub struct Original {
pub:
	root string
	base string
	arguments []string
	command []string
	socket string
	inputs map[string]string
	base_manifest string
	staged_manifest string
	storage string
	sysroot string
	sysroot_manifest string
	gcc string
	gcc_manifest string
}

pub struct Prepared {
pub:
	arch string = 'x86_64'
	root string
	base string
	arguments []string
	command []string
	socket string
	inputs map[string]string
	base_manifest string
	staged_manifest string
	storage string = 'immutable-media-reuse'
	sysroot string
	sysroot_manifest string
	gcc string
	gcc_manifest string
	reuse_origin string
	reuse_prepared_sha256 string
	reuse_manifest_sha256 string
}

pub struct Contract {
pub:
	original Original
	state string
	adapter string
	adapter_sha256 string
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn inside(path string, root string) bool { return path == root || path.starts_with(root + '/') }
fn digest_text(text string) bool {
	return text.len == 64 && text.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn stable(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.size == b.size
		&& a.nlink == b.nlink && a.uid == b.uid && a.gid == b.gid
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

// Original pin maps contain both literal tool aliases and their referents.
// Follow an alias only for its content pin, checking both identities throughout.
pub fn hash(path string) !string {
	literal := os.lstat(path)!
	resolved := os.real_path(path)
	require(resolved != '', 'missing pinned file')!
	before := os.lstat(resolved)!
	require(before.get_filetype() == .regular, 'pinned content requires ordinary file')!
	mut file := os.open(resolved)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	mut count := u64(0)
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		require(count <= before.size && u64(n) <= before.size - count, 'pinned file grew')!
		count += u64(n)
		sum.write(buffer[..n])!
	}
	require(count == before.size && stable(before, os.lstat(resolved)!)
		&& stable(literal, os.lstat(path)!) && os.real_path(path) == resolved,
		'pinned file changed while hashing')!
	return sum.sum([]u8{}).hex()
}

pub fn arguments() []string {
	return ['new=' + desktop, '--scenarios=ops,churn,cache,idle,apps,drag', '--settle=3',
		'--seconds=5', '--rounds=1', '--mem=3072', '--timeout=2400']
}

pub fn charged_roots() []string {
	return [runtime_root, cache_root + '/perf-runtime-host-20261105-01',
		cache_root + '/perf-six-x86-20261105-01', origin_root, retry_root]
}

pub fn disk_path(state string) string { return state + '/root.ext2' }
pub fn socket_path(state string) string {
	return '/tmp/vinix-perf-x86-' + sha256.sum(state.bytes()).hex()[..16] + '.qmp'
}

fn command_for(disk string, socket string) []string {
	return [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-vga', 'std',
		'-device', 'qemu-xhci,id=gui-input', '-device', 'usb-kbd,bus=gui-input.0', '-device',
		'usb-tablet,bus=gui-input.0', '-m', '3072', '-smp', '2', '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware,
		'-cdrom', origin_state + '/test.iso', '-display', 'none', '-serial', 'mon:stdio',
		'-qmp', 'unix:' + socket + ',server=on,wait=off', '-no-reboot', '-nic', 'none',
		'-drive', 'if=ide,format=raw,file=' + disk]
}

pub fn expected_command(state string) []string {
	return command_for(disk_path(state), socket_path(state))
}

fn required_original_pins() map[string]string {
	return {
		origin_state + '/root.ext2': original_disk_sha
		origin_state + '/test.iso': '9dda69697a801514d1d5308f82e8a6613ebfd3aa9102fcce9a037a8715738792'
		origin_state + '/initramfs.tar': '46ec855d5ffdc22cefcd756295481d3d21359467db9caafc5f7d3dc8804ccbbb'
		origin_state + '/rootfs/opt/vinix-perf/measure': 'e7874d55c93a6bb1dd2e0821974885437778535a696ce8f14c9eb7e2df95d21f'
		origin_state + '/guest/init': 'a9cf1d430c195f0d475920b3353a1107cbb50e90bf95dadb202d2de22b2bcf6a'
		kernel: '2a7973b2dcb21c7b40aa4fb0fd1de6c9c29c8c6c246a4353445f5698b5150eac'
		desktop: '259613b8f95ddde359a70f338baeca27bd96f0ae2b56391f6d6c3cc35de67a83'
		qemu: '25afcb2986e4a0f2c567de17273f55de3c99792b78a07c99e923bb62024c088f'
		mkfs_tool: mkfs_sha
	}
}

pub fn validate_original(p Original) ! {
	require(p.root == runtime_root && p.base == base_root, 'original fixed roots differ')!
	require(p.arguments == arguments(), 'original workload arguments differ')!
	require(p.command == command_for(origin_state + '/root.ext2', original_socket)
		&& p.socket == original_socket, 'original fixed QEMU command differs')!
	require(p.storage == 'apfs-clone' && p.base_manifest == base_manifest_sha
		&& p.staged_manifest == staged_manifest_sha, 'original storage or guest manifest differs')!
	require(p.sysroot == sysroot && p.gcc == gcc_root && p.sysroot_manifest == sysroot_manifest_sha
		&& p.gcc_manifest == gcc_manifest_sha, 'original selected build closure differs')!
	for path, expected in required_original_pins() {
		require(p.inputs[path] == expected, 'original required pin differs: ' + path)!
	}
}

fn clean_absolute(path string) ! {
	require(path.starts_with('/') && !path.contains_any('\x00\r\n\t'), 'absolute clean path required')!
	parts := path.split('/')
	for i, part in parts { if i != 0 { require(part != '' && part !in ['.', '..'], 'noncanonical path component')! } }
}

fn canonical_destination(path string) !string {
	clean_absolute(path)!
	mut at := path
	mut missing := []string{}
	for !os.exists(at) && !os.is_link(at) {
		missing << os.file_name(at)
		next := os.dir(at)
		require(next != at, 'output ancestor is absent')!
		at = next
	}
	mut result := os.real_path(at)
	require(result != '', 'output ancestor cannot resolve')!
	for i := missing.len - 1; i >= 0; i-- { result += '/' + missing[i] }
	return result
}

pub fn fresh_destination(path string) ! {
	require(path == canonical_destination(path)! && !os.exists(path) && !os.is_link(path),
		'fresh canonical prepared destination required')!
}

fn validate_contract(c Contract) ! {
	validate_original(c.original)!
	clean_absolute(c.state)!
	require(inside(c.state, retry_root) && c.state != retry_root, 'new prepared state must be within fixed retry root')!
	require(c.state == canonical_destination(c.state)!, 'prepared output follows an alias')!
	require(c.adapter == os.real_path(c.adapter) && !inside(c.adapter, c.state)
		&& !inside(c.adapter, origin_root), 'canonical separate reuse adapter required')!
	require(digest_text(c.adapter_sha256), 'reuse adapter digest is invalid')!
}

pub fn load(state string, adapter string, fresh bool) !Contract {
	// The bounded receipt parser is deliberately separate from streaming media hashes.
	receipt := origin_state + '/prepared.json'
	require(os.file_size(receipt) <= 4 * 1024 * 1024 && hash(receipt)! == origin_prepared_sha,
		'fixed original prepared receipt differs')!
	original := decode_original(os.read_file(receipt)!)!
	c := Contract{original: original, state: state, adapter: adapter, adapter_sha256: hash(adapter)!}
	validate_contract(c)!
	require(os.lstat(adapter)!.get_filetype() == .regular && os.is_executable(adapter), 'ordinary executable reuse adapter required')!
	if fresh {
		fresh_destination(state)!
	} else {
		require(os.lstat(state)!.get_filetype() == .directory && os.real_path(state) == state,
			'existing canonical prepared directory required')!
	}
	require(hash(origin_manifest)! == origin_manifest_sha && hash(literal_tool)! == literal_tool_sha,
		'fixed literal inventory input/tool differs')!
	return c
}

fn decode_original(text string) !Original { return json2.decode[Original](text, strict: true)! }

fn literal_spec(c Contract, kind string) !(string, string) {
	if kind == 'origin' { return origin_root, origin_manifest_sha }
	if kind == 'base' { return c.original.base, base_manifest_sha }
	if kind == 'staged' { return origin_state + '/rootfs', staged_manifest_sha }
	if kind == 'sysroot' { return c.original.sysroot, sysroot_manifest_sha }
	if kind == 'gcc' { return c.original.gcc, gcc_manifest_sha }
	return error('unknown fixed literal inventory role')
}

pub fn literal_argv(c Contract, kind string, output string) ![]string {
	validate_contract(c)!
	root, _ := literal_spec(c, kind)!
	require(output == canonical_destination(output)! && inside(output, retry_root)
		&& !os.exists(output) && !os.is_link(output), 'fresh canonical literal output inside retry root required')!
	require(hash(literal_tool)! == literal_tool_sha, 'fixed literal inventory tool differs')!
	return [literal_tool, 'create', root, output]
}

// Shared with host alteration controls. Production callers select the expected
// digest only through literal_spec; this helper grants no alternative authority.
pub fn verify_manifest_digest(path string, expected string) ! {
	clean_absolute(path)!
	require(digest_text(expected), 'literal inventory digest is invalid')!
	require(os.real_path(path) == path, 'literal inventory path follows an alias')!
	i := os.lstat(path)!
	require(i.get_filetype() == .regular && i.nlink == 1,
		'literal inventory must be ordinary and unaliased')!
	require(i.size <= u64(32 * 1024 * 1024), 'literal inventory exceeds 32 MiB')!
	require(hash(path)! == expected, 'complete literal inventory digest differs')!
}

// Each caller invokes the fixed literal tool in its observed child scope. All five
// complete maps must be present, distinct and exact before a proof is accepted.
pub fn verify_original(c Contract, manifests map[string]string) ! {
	validate_contract(c)!
	require(manifests.len == 5, 'five complete original literal inventories required')!
	mut used := map[string]bool{}
	for kind in ['origin', 'base', 'staged', 'sysroot', 'gcc'] {
		_, expected := literal_spec(c, kind)!
		path := manifests[kind]
		require(path != '' && path !in used && inside(path, retry_root)
			&& os.real_path(path) == path && os.lstat(path)!.get_filetype() == .regular,
			'distinct canonical complete literal inventory required')!
		used[path] = true
		verify_manifest_digest(path, expected)!
	}
	require(os.lstat(origin_root)!.mode == u32(16877) && os.lstat(base_root)!.mode == u32(16877),
		'original literal root mode differs')!
	require(hash(origin_manifest)! == origin_manifest_sha && hash(origin_state + '/prepared.json')! == origin_prepared_sha,
		'original fixed authority differs')!
	for path, expected in c.original.inputs {
		if path == origin_state + '/root.ext2' { continue }
		require(hash(path)! == expected, 'original immutable content differs: ' + path)!
	}
	require(hash(origin_state + '/root.ext2')! == frozen_origin_disk_sha,
		'frozen historical workload disk differs')!
}

pub fn mkfs_argv(state string) []string {
	return [mkfs_tool, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', disk_path(state)]
}

pub fn verify_new_disk(state string) ! {
	path := disk_path(state)
	require(path == os.real_path(path), 'fresh workload disk path follows an alias')!
	i := os.lstat(path)!
	require(i.get_filetype() == .regular && i.nlink == 1, 'fresh workload disk must be ordinary and unaliased')!
	require(i.size == u64(256) << 20, 'fresh workload disk size differs')!
	require(i.mode == u32(0o100600), 'fresh workload disk mode differs')!
	old := os.lstat(origin_state + '/root.ext2')!
	require(i.dev != old.dev || i.inode != old.inode, 'fresh workload disk aliases historical disk')!
}

pub fn (c Contract) prepared(initial_disk_sha string) !Prepared {
	validate_contract(c)!
	require(digest_text(initial_disk_sha), 'initial workload disk digest is invalid')!
	mut pins := c.original.inputs.clone()
	pins[origin_state + '/root.ext2'] = frozen_origin_disk_sha
	pins[disk_path(c.state)] = initial_disk_sha
	pins[c.adapter] = c.adapter_sha256
	pins[origin_state + '/prepared.json'] = origin_prepared_sha
	pins[origin_manifest] = origin_manifest_sha
	pins[literal_tool] = literal_tool_sha
	for name, expected in {'base-before.tsv': base_manifest_sha, 'staged-before.tsv': staged_manifest_sha,
		'sysroot-before.tsv': sysroot_manifest_sha, 'gcc-before.tsv': gcc_manifest_sha} {
		pins[c.state + '/' + name] = expected
	}
	return Prepared{root: runtime_root, base: base_root, arguments: arguments(), command: expected_command(c.state),
		socket: socket_path(c.state), inputs: pins, base_manifest: base_manifest_sha, staged_manifest: staged_manifest_sha,
		sysroot: sysroot, sysroot_manifest: sysroot_manifest_sha, gcc: gcc_root, gcc_manifest: gcc_manifest_sha,
		reuse_origin: origin_root, reuse_prepared_sha256: origin_prepared_sha, reuse_manifest_sha256: origin_manifest_sha}
}

pub fn (c Contract) validate_document(p Prepared) ! {
	expected := c.prepared(p.inputs[disk_path(c.state)])!
	require(p.arch == expected.arch && p.root == expected.root && p.base == expected.base
		&& p.arguments == expected.arguments && p.command == expected.command && p.socket == expected.socket
		&& p.inputs == expected.inputs && p.base_manifest == expected.base_manifest
		&& p.staged_manifest == expected.staged_manifest && p.storage == expected.storage
		&& p.sysroot == expected.sysroot && p.sysroot_manifest == expected.sysroot_manifest
		&& p.gcc == expected.gcc && p.gcc_manifest == expected.gcc_manifest
		&& p.reuse_origin == expected.reuse_origin && p.reuse_prepared_sha256 == expected.reuse_prepared_sha256
		&& p.reuse_manifest_sha256 == expected.reuse_manifest_sha256, 'prepared reuse document differs')!
}

fn verify_prepared(c Contract, p Prepared, after bool) ! {
	c.validate_document(p)!
	verify_new_disk(c.state)!
	for path, expected in p.inputs {
		if after && path == disk_path(c.state) { continue }
		require(hash(path)! == expected, 'prepared reuse immutable input differs: ' + path)!
	}
}

pub fn (c Contract) validate_prepared(p Prepared) ! { verify_prepared(c, p, false)! }
pub fn (c Contract) verify_after(p Prepared) ! { verify_prepared(c, p, true)! }
