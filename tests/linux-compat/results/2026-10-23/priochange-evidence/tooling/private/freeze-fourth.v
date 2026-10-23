import os
fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
 for name in ['priochangefixture', 'serialcore', 'priochangereferenceinit'] {
  os.mkdir_all(area + '/frozen-fourth/' + name)!
  from := if name == 'priochangefixture' { '/Users/alex/code/vinix/tests/linux-compat/' + name } else { area + '/frozen-first/' + name }
  os.cp(from + '/core.v', area + '/frozen-fourth/' + name + '/core.v')!
 }
}
