// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn declaration(source string, needle string) !string {
	start := source.index(needle) or { return error('Missing ' + needle) }
	open := source.index_after('{', start) or { return error('Missing body') }
	mut depth := 1
	mut end := open + 1
	for depth != 0 && end < source.len {
		if source[end] == `{` { depth++ }
		if source[end] == `}` { depth-- }
		end++
	}
	if depth != 0 { return error('Unclosed body') }
	return source[start..end]
}

fn write(work string, path string, data string) ! {
	os.mkdir_all(os.dir(work + '/' + path))!
	os.write_file(work + '/' + path, data)!
}

fn run(argv []string) ! {
	mut process := os.new_process(argv[0])
	process.set_args(argv[1..])
	process.run()
	process.wait()
	if process.code != 0 { return error('Command failed: ' + argv.join(' ')) }
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}

fn check() ! {
	root := os.real_path(@DIR + '/../..')
	work := os.join_path(os.temp_dir(), 'vinix-ext-host-' + os.getpid().str())
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	write(work, 'v.mod', "Module { name: 'ext_mount_tests' }\n")!
	source := os.read_file(root + '/kernel/fs/ext2/ext2.v')!
	mut fixture := os.read_file(root + '/tests/ext2-sparse/blocks_test.v')!
	old := declaration(fixture, 'struct EXT2Superblock ')!
	fixture = fixture.replace(old, '@[packed]\n' + declaration(source, 'struct EXT2Superblock ')!)
	fixture = fixture.replace(declaration(fixture, 'struct EXT2Inode ')!,
		'@[packed]\n' + declaration(source, 'struct EXT2Inode ')!.replace('permissions   u16', 'permissions   u16 = 0x8180'))
	fixture = fixture.replace('block_size u64\n', 'block_size u64\n\tdescriptor_size u64 = 32\n\tbgd_cnt u64\n')
	fixture = fixture.replace('superblock &EXT2Superblock = &EXT2Superblock{}',
		'superblock &EXT2Superblock = &EXT2Superblock{version_maj: 1}')
	boundary := fixture.index('\nfn test_') or { return error('Missing sparse tests') }
	write(work, 'ext2/model.v', fixture[..boundary])!
	write(work, 'ext2/sparse_test.v', 'module ext2\n' + fixture[boundary..])!
	for name in ['blocks.v', 'layout.v', 'extents.v'] {
		write(work, 'ext2/' + name, os.read_file(root + '/kernel/fs/ext2/' + name)!)!
	}
	start := source.index('fn (inode &EXT2Inode) fast_symlink_target(') or { return error('Missing inode I/O') }
	end := source.index('fn (mut inode EXT2Inode) free_entry(') or { return error('Missing inode I/O end') }
	mut io := 'module ext2\nimport stat\nimport memory\nimport errno\nimport lib\nfn C.__builtin_alloca(usize) voidptr\n' + source[start..end]
	io += '\n@[packed]\n' + declaration(source, 'struct EXT2BlockGroupDescriptor ')!
	io += '\n' + declaration(source, 'fn (mut bgd EXT2BlockGroupDescriptor) read_entry(')!
	io += '\n' + declaration(source, 'fn (mut inode EXT2Inode) read_entry(')!
	write(work, 'ext2/io.v', io)!
	cache := os.read_file(root + '/kernel/fs/ext2/pagecache.v')!
	write(work, 'ext2/large.v', 'module ext2\n' + declaration(cache, 'fn (mut filesystem EXT2Filesystem) enable_large_files(')!)!
	write(work, 'ext2/mount_test.v', os.read_file(root + '/tests/ext-mount/mount_test.v')!)!
	write(work, 'partition/geometry.v', os.read_file(root + '/kernel/block/partition/geometry.v')!)!
	write(work, 'partition/geometry_test.v', os.read_file(root + '/tests/ext-mount/partition_test.v')!)!
	write(work, 'modules/errno/errno.v', 'module errno\npub const eio = 5\npub const enomem = 12\npub const einval = 22\npub const efbig = 27\npub const eopnotsupp = 95\npub const euclean = 117\npub fn set(_ int) {}\n')!
	write(work, 'modules/memory/memory.v', 'module memory\npub fn calloc(a u64, b u64) voidptr { return unsafe { C.calloc(a, b) } }\npub fn free(p voidptr) { unsafe { C.free(p) } }\n')!
	write(work, 'modules/lib/lib.v', 'module lib\npub fn div_roundup(a u64, b u64) u64 { return (a + b - 1) / b }\n')!
	write(work, 'modules/stat/stat.v', 'module stat\npub fn isreg(mode u32) bool { return mode & 0xf000 == 0x8000 }\npub fn islnk(mode u32) bool { return mode & 0xf000 == 0xa000 }\n')!
	tool := os.getenv_opt('MKE2FS') or {
		os.find_abs_path_of_executable('mke2fs') or { '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs' }
	}
	seed := work + '/seed'
	os.mkdir(seed)!
	os.write_file(seed + '/marker', 'external Linux volume\n')!
	// Five separated allocated ranges force an external extent-tree leaf.
	mut fragmented := os.create(seed + '/fragmented')!
	for i in 0 .. 9 {
		fragmented.write_to(u64(i * 8192), []u8{len: 4096, init: u8(i + 1)})!
	}
	fragmented.close()
	os.symlink('marker', seed + '/short-link')!
	os.symlink('this/is/a/long/symlink/target/with/more/than/sixty/bytes/to/exercise/extents', seed + '/long-link')!
	for kind in ['ext2', 'ext4'] {
		for block_size in [1024, 4096] {
			disk := work + '/' + kind + '-' + block_size.str() + '.img'
			os.write_file(disk, '')!
			run([tool, '-q', '-F', '-t', kind, '-b', block_size.str(), '-d', seed, disk, '65536'])!
		}
	}
	os.setenv('EXT_MOUNT_IMAGES', work, true)
	os.setenv('VMODULES', work + '/modules', true)
	compiler := os.getenv_opt('V') or { @VEXE }
	mut argv := [compiler, '-enable-globals', '-gc', 'none']
	if os.getenv('VINIX_HOST_SANITIZE') == '1' {
		argv << ['-cc', 'clang', '-cflags', '-fsanitize=address,undefined', '-ldflags',
			'-fsanitize=address,undefined']
	}
	argv << ['test', work + '/ext2', work + '/partition']
	run(argv)!
}
