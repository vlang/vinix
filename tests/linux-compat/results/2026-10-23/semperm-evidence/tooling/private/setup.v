import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 os.mkdir_all(area + '/states')!
 os.mkdir_all(area + '/tmp')!
 execute([os.getenv('V'), 'fmt', '-w', root + '/tests/linux-compat/sempermfixture/core.v'])!
 os.mkdir_all(root + '/tests/linux-compat/sempermreferenceinit')!
 os.write_file(root + '/tests/linux-compat/sempermreferenceinit/core.v', os.read_file(root + '/tests/linux-compat/semrangereferenceinit/core.v')!.replace('semrange', 'semperm').replace('SEMRANGE', 'SEMPERM'))!
 os.write_file(root + '/tests/linux-compat/semperm-reference.v', os.read_file(root + '/tests/linux-compat/semrange-reference.v')!.replace('semrange', 'semperm').replace('SEMRANGE', 'SEMPERM').replace('checks=4200', 'checks=256552').replace('checks=4199', 'checks=256551'))!
 for name in ['compile.v', 'native.v'] {
  os.write_file(area + '/' + name, os.read_file(old + '/' + name)!.replace(old, area).replace('semrange', 'semperm').replace('SEMRANGE', 'SEMPERM').replace('checks=4200', 'checks=256552'))!
 }
 os.cp(old + '/linux-v6.12-sem.c', area + '/linux-v6.12-sem.c')!
 full_base := execute(['/usr/bin/git', '-C', root, 'rev-parse', 'e5b423347'])!
 source := os.read_bytes(root + '/kernel/sysvsem/sysvsem.v')!
 pin := sha256.sum(source).hex()
 os.write_file_array(area + '/sysvsem-candidate.v', source)!
 for suffix in ['arm', 'x86'] {
  tree := area + '/kernel-' + suffix
  execute(['/usr/bin/git', '-C', root, 'worktree', 'add', '--no-checkout', '--detach', tree, full_base])!
  execute(['/usr/bin/git', '-C', tree, 'sparse-checkout', 'init', '--cone'])!
  execute(['/usr/bin/git', '-C', tree, 'sparse-checkout', 'set', 'kernel', 'build-support', 'tests/native-generators', 'tests/linuxkpi', 'tests/scheduler-qos', 'tools'])!
  execute(['/usr/bin/git', '-C', tree, 'checkout', '--detach', full_base])!
  for name in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi', 'c/nanoprintf.h'] {
   assert !os.exists(tree + '/kernel/' + name)
   os.symlink(os.real_path(root + '/kernel/' + name), tree + '/kernel/' + name)!
  }
 }
 tree := area + '/kernel-arm'
 os.write_file_array(tree + '/kernel/sysvsem/sysvsem.v', source)!
 os.write_file(area + '/source.diff', execute(['/usr/bin/git', '-C', tree, 'diff', '--', 'kernel/sysvsem/sysvsem.v'])! + '\n')!
 execute(['/usr/bin/git', '-C', tree, 'diff', '--check'])!
 execute(['/usr/bin/git', '-C', tree, 'add', '--', 'kernel/sysvsem/sysvsem.v'])!
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: enforce semaphore permissions', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': full_base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace("const base = 'f7db726bbba470e3b4746a90197a8b3958b62a78'", "const base = '" + full_base + "'")
  .replace("const candidate_commit = '7eb399c6e8da852729a04fa52943a848eb1b6c92'", "const candidate_commit = '" + commit + "'")
  .replace("const candidate = '0ee9007d431ac0f225a59e391af2d379dcbb6380c6d6da813f0f2f1fa9adaab1'", "const candidate = '" + pin + "'")
  .replace('/semarray-evidence/', '/semrange-evidence/')
 os.write_file(area + '/build-kernels.v', build)!
 println('Isolated candidate ' + commit + ' source ' + pin)
}
