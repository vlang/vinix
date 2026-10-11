module main
import errno
struct Stat {
 size i64
}
interface Resource {
 stat Stat
mut:
 write(handle voidptr, buf voidptr, location u64, count u64) ?i64
}
struct Backing {
 stat Stat
}
fn (mut backing Backing) write(_handle voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
 return i64(count)
}
fn (mut backing Backing) append_data(_handle voidptr, _buf voidptr, count u64, _limit u64, end &u64) ?i64 {
 unsafe { *end = count }
 return i64(count)
}
fn main() {
 mut backing := Backing{}
 mut res := Resource(backing)
 result := append_write(mut res, unsafe { nil }, unsafe { nil }, 5, 100) or { panic('failed') }
 assert result.written == 5 && result.end == 5
}
