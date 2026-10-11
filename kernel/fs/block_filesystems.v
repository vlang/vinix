// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import klock
import resource

struct BlockFilesystemRegistration {
 kind string
 filesystem &FileSystem = unsafe { nil }
 backend voidptr
 identity resource.BlockIdentity
}

__global (
 block_filesystems [256]BlockFilesystemRegistration
 block_filesystems_count int
 block_filesystems_lock klock.Lock
)

// Boot-detected volumes retain their own cache and backing resource. Select
// by the actual resource and its exact physical extent, rather than a global
// ext2 template. A verified or read-only wrapper remains a distinct backend;
// sharing its underlying physical extent must not bypass that wrapper.
pub fn register_block_filesystem(kind string, source &VFSNode, filesystem &FileSystem, identity resource.BlockIdentity) {
 if !identity.valid() { return }
 block_filesystems_lock.acquire()
 defer { block_filesystems_lock.release() }
 for index in 0 .. block_filesystems_count {
  if block_filesystems[index].kind == kind && block_filesystems[index].backend == voidptr(source.resource) {
   block_filesystems[index] = BlockFilesystemRegistration{kind, unsafe { filesystem }, voidptr(source.resource), identity}
   return
  }
 }
 if block_filesystems_count == block_filesystems.len { return }
 block_filesystems[block_filesystems_count] = BlockFilesystemRegistration{kind, unsafe { filesystem }, voidptr(source.resource), identity}
 block_filesystems_count++
}

pub fn block_filesystem(kind string, source &VFSNode) &FileSystem {
 if source == unsafe { nil } || source.resource == unsafe { nil } { return unsafe { nil } }
 mut backend := unsafe { source.resource }
 identity := resource.block_identity(mut backend)
 if !identity.valid() { return unsafe { nil } }
 block_filesystems_lock.acquire()
 defer { block_filesystems_lock.release() }
 for index in 0 .. block_filesystems_count {
  if block_filesystems[index].kind == kind && block_filesystems[index].backend == voidptr(source.resource)
   && block_filesystems[index].identity == identity {
   return block_filesystems[index].filesystem
  }
 }
 return unsafe { nil }
}
