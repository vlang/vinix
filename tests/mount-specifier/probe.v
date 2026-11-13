// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only probe: V /path/to/this/probe.v /absolute/repository/root
module main

import os

fn checked(args []string) ! {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.run()
	child.wait()
	code := child.code
	child.close()
	if code != 0 { return error('command failed: ${args} (${code})') }
}

fn main() {
	root := if os.args.len > 1 { os.abs_path(os.args[1]) } else { os.getwd() }
	work := os.join_path(os.temp_dir(), 'vinix-mount-specifier-${os.getpid()}')
	os.mkdir_all(work + '/errno')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/v.mod', "Module { name: 'mount_specifier_probe' }")!
	os.write_file(work + '/errno/errno.v', 'module errno
@[has_globals]
__global ( current = int(0) )
pub const einval = 22
pub const eio = 5
pub fn set(value int) { current = value }
pub fn get() int { return current }
')!
	contract := os.read_file(root + '/kernel/fs/vfs.v')!.all_after('pub interface FileSystem {').all_before('\n}')
	os.write_file(work + '/contract.v', 'module main\npub interface FileSystem {${contract}\n}\n')!
	hook := os.read_file(root + '/kernel/fs/mount_specifier.v')!
	os.write_file(work + '/mount_specifier.v', hook.replace('module fs', 'module main'))!
	mount := os.read_file(root + '/kernel/fs/mount.v')!
	probe := mount.all_after('\t// opt-in backends interpret source as a specifier rather than a VFS path.\n').all_before('\tif source.len != 0')
	assert probe.contains('template is MountSpecifier')
	os.write_file(work + '/probe.v', 'module main\nfn uses_specifier(kind string, filesystems map[string]&FileSystem) bool {\n${probe}\treturn raw_specifier\n}\n')!
	os.write_file(work + '/main.v', fixture)!
	compiler := os.getenv_opt('V') or { @VEXE }
	// A running V tool inherits VEXE; keep an override's library root paired
	// with its compiler rather than the compiler that built this runner.
	os.setenv('VEXE', compiler, true)
	flags := ['-nocache', '-cc', 'clang', '-enable-globals', '-gc', 'none', '-manualfree']
	checked([compiler, ...flags, '-o', work + '/probe', work])!
	checked([work + '/probe'])!
	checked([compiler, ...flags, '-o', work + '/probe.c', work])!
	generated := os.read_file(work + '/probe.c')!
	for name in ['uses_specifier', 'mount_filesystem_specifier'] {
		// Accept both V C backends' symbol prefixes and result type spelling.
		mut found := false
		for line in generated.split_into_lines() {
			if !line.contains(name + '(') || !line.ends_with(') {') || line.starts_with('\t') {
				continue
			}
			definition := generated.all_after(line + '\n').all_before('\n}\n')
			assert !definition.contains('memdup(')
			assert !definition.contains('malloc(')
			assert !definition.contains('heap(')
			assert !definition.contains('calloc(')
			found = true
			break
		}
		assert found, 'missing generated C definition: ' + name
	}
	println('Mount specifier generated C: no heap allocation in template probe or dispatch')
}

const fixture = 'module main

import errno

#flag -Dvinix_stack_alloc=__builtin_alloca
fn C.vinix_stack_alloc(usize) voidptr

struct VFSNode {}

struct LegacyFS {
mut:
 instance &FileSystem = unsafe { nil }
 instantiations int
 mounts int
}
fn (mut fs LegacyFS) instantiate() &FileSystem { fs.instantiations++; return fs.instance }
fn (mut fs LegacyFS) populate(_ &VFSNode) {}
fn (mut fs LegacyFS) mount(_ &VFSNode, _ string, _ &VFSNode) ?&VFSNode { fs.mounts++; return none }
fn (mut fs LegacyFS) create(_ &VFSNode, _ string, _ u32) &VFSNode { return unsafe { nil } }
fn (mut fs LegacyFS) symlink(_ &VFSNode, _ string, _ string) &VFSNode { return unsafe { nil } }
fn (mut fs LegacyFS) link(_ &VFSNode, _ string, mut _ VFSNode) ?&VFSNode { return none }
fn (mut fs LegacyFS) rename(_ &VFSNode, _ string, _ &VFSNode, _ string, _ int) ? {}

struct RawFS {
 LegacyFS
mut:
 calls int
 parent &VFSNode = unsafe { nil }
 name string
 source string
 flags u64
 options string
 fail bool
 root &VFSNode = unsafe { nil }
}
fn (mut fs RawFS) mount_specifier(parent &VFSNode, name string, source string, flags u64, options string) ?&VFSNode {
 fs.calls++
 fs.parent = unsafe { parent }
 fs.name = name
 fs.source = source
 fs.flags = flags
 fs.options = options
 if fs.fail { errno.set(errno.eio); return none }
 return fs.root
}

fn main() {
 mut legacy := &LegacyFS{}
 legacy_box := &FileSystem(legacy)
 mut backend := &RawFS{root: &VFSNode{}}
 backend_box := &FileSystem(backend)
 mut template := &RawFS{}
 template.instance = backend_box
 template_box := &FileSystem(template)
 registry := {"legacy": legacy_box, "remote": template_box, "nil": &FileSystem(unsafe { nil })}
 assert !uses_specifier("legacy", registry)
 assert !uses_specifier("missing", registry)
 assert !uses_specifier("nil", registry)
 for _ in 0 .. 10000 { assert uses_specifier("remote", registry) }
 assert template.instantiations == 0 && template.calls == 0 && backend.calls == 0
 mut instance := unsafe { template_box.instantiate() }
 assert voidptr(instance) == voidptr(backend_box)
 parent := &VFSNode{}
 source := "server:/export path?tag=raw"
 options := "version=1,token=a=b,wxallowed"
 flags := (u64(1) << 63) | 0x4001
 result := mount_filesystem_specifier(mut instance, parent, "mnt", source, flags, options) or { panic("raw dispatch failed") }
 assert voidptr(result) == voidptr(backend.root)
 assert template.instantiations == 1 && template.calls == 0
 assert backend.calls == 1 && backend.mounts == 0
 assert backend.parent == parent && backend.name == "mnt"
 assert backend.source == source && backend.source.str == source.str
 assert backend.options == options && backend.options.str == options.str && backend.flags == flags
 mount_filesystem_specifier(mut instance, parent, "mnt", "", 0, "") or { panic("empty arguments failed") }
 assert backend.source == "" && backend.options == "" && backend.flags == 0
 backend.fail = true
 mut failed := false
 mount_filesystem_specifier(mut instance, parent, "mnt", source, flags, options) or { failed = true }
 assert failed && errno.get() == errno.eio && backend.calls == 3
 mut mismatch := unsafe { legacy_box }
 failed = false
 mount_filesystem_specifier(mut mismatch, parent, "mnt", source, flags, options) or { failed = true }
 assert failed && errno.get() == errno.einval && legacy.mounts == 0
 println("Mount specifier host probes: PASS (opt-in, no probe instantiation, instance dispatch, borrowed raw arguments, empty source/options, errno, mismatch)")
}
'
