// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn facade_check(root string, work string, v string) ! {
	os.mkdir_all(work + '/fs/nfs')!
	os.write_file(work + '/v.mod', "Module { name: 'nfs_contract' }")!
	for path in os.walk_ext(root + '/tests/nfs/protocol/facade', '.vfixture') {
		rel := path.all_after('/facade/').all_before_last('.vfixture') + '.v'
		os.mkdir_all(os.dir(work + '/' + rel))!
		os.cp(path, work + '/' + rel)!
	}
	for path in os.walk_ext(root + '/kernel/fs/nfs', '.v') { os.cp(path, work + '/fs/nfs/' + os.file_name(path))! }
	os.cp(root + '/kernel/fs/nfs.v', work + '/fs/nfs.v')!
	os.cp(root + '/kernel/fs/rename_publication.v', work + '/fs/rename_publication.v')!
	storage := os.read_file(root + '/kernel/fs/overlay_storage.v')!
	// Normalize only the named multiline interface declaration for the host
	// compiler. Its method contract and all production bodies stay unchanged.
	os.write_file(work + '/fs/overlay_storage.v', storage.replace('rename_whiteout(old_parent &VFSNode, old_name string, new_parent &VFSNode,\n\t\tnew_name string, whiteout &VFSNode) ?', 'rename_whiteout(&VFSNode, string, &VFSNode, string, &VFSNode) ?'))!
	fs_source := os.read_file(root + '/kernel/fs/vfs.v')!
	// Exercise production publication and both syscall entry points, with only
	// path/fd/usercopy services stubbed. Do not copy the error-propagation logic.
	dots := 'pub fn (mut node VFSNode) create_dotentries' + fs_source.all_after('pub fn (mut node VFSNode) create_dotentries').all_before('\n}') + '\n}\n'
	adopt := 'fn adopt(' + fs_source.all_after('fn adopt(').all_before('\n}') + '\n}\n'
	syscalls := 'pub fn syscall_statfs(' + fs_source.all_after('pub fn syscall_statfs(').all_before('\npub const utime_now')
	os.write_file(work + '/fs/vfs_extract.v', 'module fs\nimport resource\nimport lib\nimport proc\nimport errno\nimport file\nimport usercopy\nimport stat\nimport katomic\n' + dots + adopt + syscalls)!
	r_cache := os.read_file(root + '/kernel/resource/cache.v')!
	stat_contract := 'pub struct FileSystemStat {' + r_cache.all_after('pub struct FileSystemStat {').all_before('\npub fn sync_resource')
	stat_dispatch := 'pub fn filesystem_stat(' + r_cache.all_after('pub fn filesystem_stat(').all_before('\n// A device aperture')
	os.write_file(work + '/resource/statfs.v', 'module resource\n#flag -Dvinix_stack_alloc=__builtin_alloca\nfn C.vinix_stack_alloc(u64) voidptr\n' + stat_contract + stat_dispatch)!
	publication_extracts(root, work, fs_source)!
	contract := fs_source.all_after('pub interface FileSystem {').all_before('\n}')
	os.write_file(work + '/fs/contract.v', 'module fs\npub interface FileSystem {${contract}\n}\n')!
	r_source := os.read_file(root + '/kernel/resource/resource.v')!
	r_contract := r_source.all_after('pub interface Resource {').all_before('\n}')
	os.write_file(work + '/resource/contract.v', 'module resource\nimport stat\nimport klock\nimport event.eventstruct\npub interface Resource {${r_contract}\n}\n')!
	os.mkdir_all(work + '/stat')!
	os.cp(root + '/kernel/stat/stat.v', work + '/stat/stat.v')!
	checked([v, '-enable-globals', '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/adapter.c', work])!
	checked([v, '-enable-globals', '-os', 'linux', '-arch', 'amd64', '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/adapter-linux.c', work])!
	checked([v, '-enable-globals', '-gc', 'none', '-manualfree', '-d', 'track_heap', '-o', work + '/adapter', work])!
	checked([work + '/adapter'])!
	if '--negative' in os.args { repair_negative_checks(work, v)! }
	// Some backends eliminate unused facade error paths. The standalone wire
	// fixture explicitly exercises EXPORT, so include its generated body too.
	generated := os.read_file(work + '/adapter-linux.c')! + '\n' + os.read_file(os.dir(work) + '/protocol-linux.c')!
	names := ['fs__nfs__Xdr_opaque', 'fs__nfs__Xdr_entry', 'fs__nfs__Client_request', 'fs__nfs__Client_call', 'fs__nfs__Client_record', 'fs__nfs__Client_read', 'fs__nfs__Client_write', 'fs__nfs__Client_getattr', 'fs__nfs__Client_readdirplus', 'fs__nfs__Client_exports', 'fs__NfsResource_read', 'fs__NfsResource_write_locked', 'fs__NfsResource_refresh_attr', 'fs__NFSFS_identity', 'fs__nfs_res', 'fs__NFSFS_destroy_failed', 'fs__NFSFS_rename_begin', 'fs__rename_before_publish', 'fs__rename_after_publish', 'resource__filesystem_stat', 'fs__NfsResource_try_filesystem_stat']
	for name in names {
		// V backends differ in module aliases and method-name separators.
		modern := name.replace('Xdr_', 'Xdr__').replace('Client_', 'Client__').replace('NfsResource_', 'NfsResource__').replace('NFSFS_', 'NFSFS__')
		aliases := [name, modern, name.replace('fs__nfs__', 'nfs__'), modern.replace('fs__nfs__', 'nfs__')]
		mut found := false
		for line in generated.split_into_lines() {
			if !aliases.any(line.contains(it + '(')) || !line.ends_with(' {') || line.starts_with('	') { continue }
			body := generated.all_after(line + '\n').all_before('\n}')
			for allocation in ['HEAP(', 'memdup(', '_v_malloc(', 'calloc(', 'string_clone('] {
				if body.contains(allocation) { return error('unexpected hot-path allocation in ' + name + ': ' + allocation) }
			}
			found = true
			break
		}
		if !found { return error('missing generated C definition: ' + name) }
	}
	println('NFS production adapter: actual FileSystem/Resource/Stat contracts, host and Linux C generation passed')
	println('NFS generated C: no hidden allocation in ${names.len} wire/resource/publication functions')
}
