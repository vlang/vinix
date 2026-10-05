module ext2

import memory
import errno
import posix_acl

fn test_shared_block_cow_and_release() {
	mut filesystem := fixture()
	mut block := rebuilt(unsafe { nil }, 1, 'old', [u8(1)], false)
	mut header := unsafe { &EAHeader(block.data) }
	header.refs = 2
	filesystem.blocks[2] = block
	filesystem.allocated[2] = true
	filesystem.inode.eab = 2
	filesystem.inode.sector_cnt = 8
	mut file := EXT2Resource{filesystem: &filesystem}
	file.write_xattr('user.new', [u8(2)], 0) or { panic('write failed') }
	assert filesystem.inode.eab == 3
	assert filesystem.inode.sector_cnt == 8
	assert unsafe { &EAHeader(filesystem.blocks[2].data) }.refs == 1
	assert ea_find(filesystem.blocks[2].data, 1, 'new') < 0
	assert ea_find(filesystem.blocks[3].data, 1, 'old') >= 0
	file.delete_xattr('user.old') or { panic('delete failed') }
	assert filesystem.allocated[3]
	file.delete_xattr('user.new') or { panic('delete failed') }
	assert filesystem.inode.eab == 0
	assert filesystem.inode.sector_cnt == 0
	assert !filesystem.allocated[3]
	assert filesystem.allocated[2]
	assert memory.outstanding() == 0
}

fn test_prepublication_io_error_releases_private_block() {
	mut filesystem := fixture()
	filesystem.fail_block_write = true
	mut file := EXT2Resource{filesystem: &filesystem}
	mut failed := false
	file.write_xattr('user.new', [u8(2)], 0) or { failed = true }
	assert failed
	assert filesystem.inode.eab == 0
	assert !filesystem.allocated[2]
	assert memory.outstanding() == 0
}

fn test_ambiguous_inode_publication_quarantines_block() {
	mut filesystem := fixture()
	filesystem.fail_inode_write = true
	mut file := EXT2Resource{filesystem: &filesystem}
	mut failed := false
	file.write_xattr('user.new', [u8(2)], 0) or { failed = true }
	assert failed
	// Model a pointer published before the underlying operation reports EIO.
	assert filesystem.inode.eab == 2
	assert filesystem.allocated[2]
	assert ea_validate(filesystem.blocks[2].data, 4096)
	assert memory.outstanding() == 0
}

fn test_shared_release_io_error_does_not_free_live_old_block() {
	mut filesystem := fixture()
	mut block := rebuilt(unsafe { nil }, 1, 'old', [u8(1)], false)
	mut header := unsafe { &EAHeader(block.data) }
	header.refs = 2
	filesystem.blocks[2] = block
	filesystem.allocated[2] = true
	filesystem.inode.eab = 2
	filesystem.inode.sector_cnt = 8
	filesystem.fail_header_write = true
	mut file := EXT2Resource{filesystem: &filesystem}
	mut failed := false
	file.write_xattr('user.new', [u8(2)], 0) or { failed = true }
	assert failed
	assert filesystem.inode.eab == 3
	assert filesystem.allocated[2]
	assert filesystem.allocated[3]
	assert memory.outstanding() == 0
}

fn test_metadata_pointer_and_corrupt_header_fail_without_freeing_blocks() {
	mut filesystem := fixture()
	filesystem.inode.eab = 60 // The block bitmap, even if it contains an EA-looking header.
	filesystem.inode.sector_cnt = 8
	filesystem.allocated[60] = true
	filesystem.blocks[60] = rebuilt(unsafe { nil }, 1, 'old', [u8(1)], false)
	mut file := EXT2Resource{filesystem: &filesystem}
	mut failed := false
	file.delete_xattr('user.old') or { failed = true }
	assert failed
	assert filesystem.inode.eab == 60
	assert filesystem.allocated[60]
	assert memory.outstanding() == 0
	filesystem.inode.eab = 2
	filesystem.allocated[2] = true
	filesystem.blocks[2] = rebuilt(unsafe { nil }, 1, 'old', [u8(1)], false)
	mut header := unsafe { &EAHeader(filesystem.blocks[2].data) }
	header.refs = 0
	failed = false
	file.delete_xattr('user.old') or { failed = true }
	assert failed
	assert filesystem.inode.eab == 2
	assert filesystem.allocated[2]
	assert memory.outstanding() == 0
}

fn acl_fixture() []u8 {
	return [u8(2), 0, 0, 0, 1, 0, 6, 0, 255, 255, 255, 255,
		2, 0, 6, 0, 232, 3, 0, 0, 4, 0, 0, 0, 255, 255, 255, 255,
		16, 0, 6, 0, 255, 255, 255, 255, 32, 0, 0, 0, 255, 255, 255, 255]
}

fn test_acl_wire_disk_conversion_and_atomic_private_block() {
	mut filesystem := fixture()
	filesystem.inode.permissions = 0o100600
	mut file := EXT2Resource{filesystem: &filesystem, stat: Stat{mode: 0o100600}}
	file.write_xattr('user.keep', [u8(42)], 0) or { panic('write failed') }
	old := filesystem.inode.eab
	acl := acl_fixture()
	file.write_xattr(posix_acl.access_name, acl, 0) or { panic('ACL write failed') }
	assert filesystem.inode.eab != old
	assert !filesystem.allocated[int(old)]
	assert filesystem.inode.permissions == 0o100660
	assert file.stat.mode == 0o100660
	assert filesystem.inode.sector_cnt == 8
	position := ea_find(filesystem.blocks[int(filesystem.inode.eab)].data, 2, '')
	item := ea_entry(filesystem.blocks[int(filesystem.inode.eab)].data, position)
	assert item.value_size == 28 // Version 1's short object/mask entries.
	assert filesystem.blocks[int(filesystem.inode.eab)][int(item.value_offset)] == 1
	mut wire := []u8{}
	file.read_xattr(posix_acl.access_name, mut wire) or { panic('ACL read failed') }
	assert wire == acl
	assert ea_find(filesystem.blocks[int(filesystem.inode.eab)].data, 1, 'keep') >= 0
	assert memory.outstanding() == 0
}

fn test_acl_prepublication_error_preserves_old_mode_and_acl() {
	mut filesystem := fixture()
	filesystem.inode.permissions = 0o100600
	mut file := EXT2Resource{filesystem: &filesystem, stat: Stat{mode: 0o100600}}
	file.write_xattr(posix_acl.access_name, acl_fixture(), 0) or { panic('ACL write failed') }
	old := filesystem.inode.eab
	filesystem.fail_block_write = true
	mut acl := acl_fixture()
	posix_acl.chmod(mut acl, 0o100640)
	mut failed := false
	file.write_xattr(posix_acl.access_name, acl, 0) or { failed = true }
	assert failed && errno.get() == errno.eio
	assert filesystem.inode.eab == old && filesystem.inode.permissions == 0o100660
	assert file.stat.mode == 0o100660
	assert !filesystem.allocated[int(old + 1)]
	assert memory.outstanding() == 0
}

fn test_acl_ambiguous_inode_write_keeps_both_blocks_and_snapshot_matches_disk() {
	mut filesystem := fixture()
	filesystem.inode.permissions = 0o100600
	mut file := EXT2Resource{filesystem: &filesystem, stat: Stat{mode: 0o100600}}
	file.write_xattr(posix_acl.access_name, acl_fixture(), 0) or { panic('ACL write failed') }
	old := filesystem.inode.eab
	filesystem.fail_inode_write = true
	mut acl := acl_fixture()
	posix_acl.chmod(mut acl, 0o100640)
	mut failed := false
	file.write_xattr(posix_acl.access_name, acl, 0) or { failed = true }
	assert failed && errno.get() == errno.eio
	assert filesystem.inode.eab != old && filesystem.inode.permissions == 0o100640
	assert filesystem.allocated[int(old)] && filesystem.allocated[int(filesystem.inode.eab)]
	mut snapshot := []u8{}
	metadata := file.snapshot_permissions(mut snapshot) or { panic('snapshot failed') }
	assert metadata.mode == 0o100640 && snapshot == acl
	assert memory.outstanding() == 0
}

fn test_minimal_acl_changes_mode_without_allocating_or_sector_underflow() {
	mut filesystem := fixture()
	filesystem.inode.permissions = 0o100600
	mut file := EXT2Resource{filesystem: &filesystem, stat: Stat{mode: 0o100600}}
	minimal := [u8(2), 0, 0, 0, 1, 0, 6, 0, 255, 255, 255, 255,
		4, 0, 4, 0, 255, 255, 255, 255, 32, 0, 1, 0, 255, 255, 255, 255]
	file.write_xattr(posix_acl.access_name, minimal, 0) or { panic('minimal write failed') }
	assert filesystem.inode.permissions == 0o100641 && file.stat.mode == 0o100641
	assert filesystem.inode.eab == 0 && filesystem.inode.sector_cnt == 0
	assert !filesystem.allocated[2]
	assert memory.outstanding() == 0
}

fn test_malformed_acl_value_and_name_fail_closed() {
	mut filesystem := fixture()
	filesystem.blocks[2] = rebuilt(unsafe { nil }, 2, '', [u8(0), 0, 0, 0], false)
	filesystem.allocated[2] = true
	filesystem.inode.eab = 2
	filesystem.inode.sector_cnt = 8
	mut file := EXT2Resource{filesystem: &filesystem}
	mut value := []u8{}
	mut failed := false
	file.read_xattr(posix_acl.access_name, mut value) or { failed = true }
	assert failed && errno.get() == errno.eio
	assert memory.outstanding() == 0
	filesystem.blocks[2] = rebuilt(unsafe { nil }, 1, 'invalid', [u8(1)], false)
	mut descriptor := unsafe { &EAEntry(u64(filesystem.blocks[2].data) + ea_header_size) }
	descriptor.index = 2
	failed = false
	file.read_xattr(posix_acl.access_name, mut value) or { failed = true }
	assert failed && errno.get() == errno.eio
	assert memory.outstanding() == 0
}
