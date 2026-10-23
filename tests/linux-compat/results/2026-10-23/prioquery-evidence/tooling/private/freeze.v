import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 assert os.args.len == 2
 tag := os.args[1]
 target := area + '/frozen-' + tag
 assert !os.exists(target)
 for pair in [['fixture', 'prioqueryfixture'], ['prioqueryreferenceinit', 'prioqueryreferenceinit']] {
  os.mkdir_all(target + '/' + pair[1])!
  os.cp(area + '/' + pair[0] + '/core.v', target + '/' + pair[1] + '/core.v')!
 }
 os.mkdir_all(target + '/serialcore')!
 os.cp('/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/frozen/serialcore/core.v', target + '/serialcore/core.v')!
 os.mkdir_all(area + '/tmp')!
}
