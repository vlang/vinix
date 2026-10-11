module file
import resource
pub struct Handle { pub mut: resource &resource.Resource flags int }
pub fn (mut h Handle) mac_check(_ u64) ? {}
pub struct FD { pub mut: handle &Handle }
