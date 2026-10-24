import os
fn main() {
 assert os.args.len == 2
 area := os.dir(@FILE)
 tag := os.args[1]
 assert tag.bytes().all(it.is_alnum() || it == `-`)
 for name in ['priozombiefixture','priozombiereferenceinit','serialcore'] {
  path := area + '/frozen-' + tag + '/' + name
  assert !os.exists(path)
  os.mkdir_all(path)!
  os.cp(if name == 'serialcore' {area + '/frozen-first/serialcore/core.v'} else {'/Users/alex/code/vinix/tests/linux-compat/' + name + '/core.v'},path + '/core.v')!
 }
}
