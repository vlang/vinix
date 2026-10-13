// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixture

import os

const memory_fixture = $embed_file('templates/memory.v').to_string()
const ext2_fixture = $embed_file('templates/model.v').to_string()
const resource_fixture = $embed_file('templates/resource.v').to_string()

pub fn prepare(root string, work string) ! {
	if os.exists(work) { return error('host test directory must be new') }
	for directory in ['ext2', 'errno', 'memory', 'time', 'fs', 'resource', 'posix_acl'] { os.mkdir_all(work + '/' + directory)! }
	os.write_file(work + '/v.mod', "Module { name: 'vinix_xattr_tests' }\n")!
	os.write_file(work + '/ext2/codec.v', os.read_file(root + '/kernel/fs/ext2/xattr_block.v')! + '\nfn C.memcpy(voidptr, voidptr, usize) voidptr\n')!
	codec := os.read_file(root + '/tests/ext2-xattr/codec_test.v')!
	marker := 'fn test_sorted_entries'
	cut := codec.index(marker) or { return error('production codec test entry point missing') }
	os.write_file(work + '/ext2/helper.v', codec[..cut])!
	os.write_file(work + '/ext2/codec_test.v', 'module ext2\n\n' + codec[cut..])!
	os.cp(root + '/kernel/fs/ext2/xattr.v', work + '/ext2/xattr.v')!
	os.cp(root + '/tests/ext2-xattr/persistence_test.v', work + '/ext2/persistence_test.v')!
	os.write_file(work + '/errno/errno.v', '@[has_globals]\nmodule errno\n__global current_errno = int(0)\npub const enospc = 28\npub const enodata = 61\npub const enotsup = 95\npub const eio = 5\npub const enomem = 12\npub const eexist = 17\npub const einval = 22\npub fn set(value int) { current_errno = value }\npub fn get() int { return current_errno }\n')!
	os.write_file(work + '/time/time.v', 'module time\npub struct TimeSpec { pub mut: tv_sec i64 }\n')!
	os.write_file(work + '/memory/memory.v', memory_fixture)!
	os.write_file(work + '/ext2/model.v', ext2_fixture)!
	copy_source := os.read_file(root + '/kernel/fs/xattr.v')!
	start := copy_source.index('fn copy_one_xattr') or { return error('production xattr copy function missing') }
	end := copy_source.index('// Called when a tmpfs file goes.') or { return error('production xattr copy boundary missing') }
	if end <= start { return error('production xattr copy boundaries are unordered') }
	os.write_file(work + '/fs/copy.v', 'module fs\nimport errno\nimport resource\n' + copy_source[start..end])!
	os.cp(root + '/tests/ext2-xattr/copy_test.v', work + '/fs/copy_test.v')!
	os.write_file(work + '/resource/resource.v', resource_fixture)!
	os.cp(root + '/kernel/posix_acl/acl.v', work + '/posix_acl/acl.v')!
	os.cp(root + '/tests/ext2-xattr/acl_test.v', work + '/posix_acl/acl_test.v')!
}
