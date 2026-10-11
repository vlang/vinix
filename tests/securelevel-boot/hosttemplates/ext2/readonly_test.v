module ext2

fn test_readonly_attribute_failure_preserves_policy_and_releases_locks() {
 mut filesystem := EXT2Filesystem{inode_flags: 0x20, read_only: true}
 mut file := EXT2Resource{filesystem: &filesystem, attr_bits: 0x20}
 mut failed := false
 file.set_attribute_bits(0x10) or { failed = true }
 assert failed
 assert file.attr_bits == 0x20 && filesystem.inode_flags == 0x20
 assert file.l.depth == 0 && filesystem.l.depth == 0
}

fn test_readonly_raw_write_refuses_before_accessing_backing_device() {
 mut filesystem := EXT2Filesystem{read_only: true}
 mut value := u32(0)
 mut failed := false
 filesystem.raw_device_write(unsafe { &value }, 0, sizeof(value)) or { failed = true }
 assert failed
 assert filesystem.backing_device == unsafe { nil }
}
