import os
fn main() {
 path := '/Users/alex/code/vinix/tests/linux-compat/sempermfixture/core.v'
 mut source := os.read_file(path)!
 source = source.replace('*C.__errno_location() = 0', 'clear_errno()')
 source = source.replace('fn ctl(', 'fn clear_errno() {\n unsafe {\n  location := C.__errno_location()\n  *location = 0\n }\n}\n\nfn ctl(')
 os.write_file(path, source)!
}
