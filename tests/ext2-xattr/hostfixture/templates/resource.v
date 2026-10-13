module resource
import errno
pub const attributes_kept = u32(0)
pub const acl_clear_setgid = 4
pub struct PermissionMetadata { pub: mode u32 uid u32 gid u32 }
pub struct Resource { pub mut:
 names []u8
 value []u8
 missing string
 list_error int
 get_error int
 set_error int
 copied_names []string
 copied_values [][]u8
}
pub fn xattr_names(mut res Resource, mut names []u8) ? {
 if res.list_error != 0 { errno.set(res.list_error); return none }
 for c in res.names { names << c }
}
pub fn get_xattr(mut res Resource, name string, mut value []u8) ? {
 if name == res.missing { errno.set(errno.enodata); return none }
 if res.get_error != 0 { errno.set(res.get_error); return none }
 for c in res.value { value << c }
}
pub fn set_xattr(mut res Resource, name string, value []u8, _ int) ? {
 if res.set_error != 0 { errno.set(res.set_error); return none }
 res.copied_names << name.clone()
 res.copied_values << value.clone()
}
