module ext2

fn test_attributes_publish_with_backend_lock() {
 mut filesystem := EXT2Filesystem{}
 mut file := EXT2Resource{filesystem: &filesystem, attr_bits: 0x20}
 file.set_attribute_bits(0x10) or { panic('publication failed') }
 assert file.attr_bits == 0x10
 assert filesystem.inode_flags == 0x10
 assert file.l.depth == 0 && filesystem.l.depth == 0
}

fn test_attributes_fail_closed_on_ambiguous_publication() {
 for publication in [false, true] {
  mut filesystem := EXT2Filesystem{inode_flags: 0x20, fail_write: true, publish_on_failure: publication}
  mut file := EXT2Resource{filesystem: &filesystem, attr_bits: 0x20}
  mut failed := false
  file.set_attribute_bits(0x10) or { failed = true }
  assert failed
  assert file.attr_bits == 0x30
  assert filesystem.inode_flags == if publication { u32(0x10) } else { u32(0x20) }
  assert file.l.depth == 0 && filesystem.l.depth == 0
 }
}

fn test_read_failure_preserves_previous_policy() {
 mut filesystem := EXT2Filesystem{inode_flags: 0x20, fail_read: true}
 mut file := EXT2Resource{filesystem: &filesystem, attr_bits: 0x20}
 mut failed := false
 file.set_attribute_bits(0x10) or { failed = true }
 assert failed
 assert file.attr_bits == 0x20 && filesystem.inode_flags == 0x20
 assert file.l.depth == 0 && filesystem.l.depth == 0
}

fn test_shared_range_rejects_sealing_without_publication() {
 mut filesystem := EXT2Filesystem{}
 mut file := EXT2Resource{filesystem: &filesystem, shared_mapping_ranges: 1}
 mut failed := false
 file.set_attribute_bits(0x10) or { failed = true }
 assert failed
 assert file.attr_bits == 0 && filesystem.inode_flags == 0
 assert file.l.depth == 0 && filesystem.l.depth == 0
}

fn test_short_inode_transfer_fails_closed() {
 for publication in [false, true] {
  mut backing := BackingNode{resource: BackingResource{stat: Stat{size: 4096}}}
  mut filesystem := EXT2Filesystem{inode_flags: 0x20, short_write: true,
   fail_write: true, publish_on_failure: publication,
   backing_device: &backing, cache: FakeCache{result: 2}}
  mut file := EXT2Resource{filesystem: &filesystem, attr_bits: 0x20}
  mut failed := false
  file.set_attribute_bits(0x10) or { failed = true }
  assert failed
  assert file.attr_bits == 0x30
  assert filesystem.inode_flags == if publication { u32(0x10) } else { u32(0x20) }
  assert file.l.depth == 0 && filesystem.l.depth == 0
 }
}
