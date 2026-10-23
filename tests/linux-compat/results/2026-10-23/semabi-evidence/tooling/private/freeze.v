import os
fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
 tag := os.args[1]
 assert !os.exists(area + '/frozen-' + tag)
 for name in ['semabifixture', 'serialcore', 'semabireferenceinit'] {
  os.mkdir_all(area + '/frozen-' + tag + '/' + name)!
  os.cp(area + '/frozen-draft1/' + name + '/core.v', area + '/frozen-' + tag + '/' + name + '/core.v')!
 }
 os.cp('/Users/alex/code/vinix/tests/linux-compat/semabifixture/core.v', area + '/frozen-' + tag + '/semabifixture/core.v')!
}
