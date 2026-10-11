@[has_globals]
module fs
import memory
import resource
import security
import kbudget
__global (nodes [64]&resource.Resource reject_publication bool)
pub fn devtmpfs_add_volume(r &resource.Resource, _ string) ? { if reject_publication { return none }; for i in 0..64 { if nodes[i]==unsafe { nil } { nodes[i]=r; return } }; return none }
fn security_register(mut r resource.Resource) { security.register_block_device(resource.block_identity(mut r)) }
pub fn devtmpfs_remove_device(_ string, r &resource.Resource) bool { for i in 0..64 { if nodes[i]==r { nodes[i]=unsafe { nil }; mut actual:=unsafe { r }; resource.release_resource(mut actual); return true } }; return false }
pub fn free_after_grace(p voidptr) { memory.free(p) }
pub fn free_charged_after_grace(p voidptr, charge kbudget.Charge) { memory.free(p); kbudget.release(charge) }
pub fn release_resource_after_grace(r &resource.Resource) { mut actual:=unsafe { r }; resource.release_resource(mut actual) }
