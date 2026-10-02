module ext2

import memory

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
