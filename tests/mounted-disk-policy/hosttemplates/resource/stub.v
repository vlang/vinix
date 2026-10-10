module resource
import stat
fn C.vinix_stack_alloc(usize) voidptr
pub interface Resource {
mut:
 stat stat.Stat
}
