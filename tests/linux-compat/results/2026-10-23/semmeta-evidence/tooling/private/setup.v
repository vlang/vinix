import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 full_base := execute(['/usr/bin/git', '-C', root, 'rev-parse', 'd2283faca'])!
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
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: implement native semaphore metadata controls', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': full_base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace("const base = 'e5b423347e1aad8ef122316bb85602aab2d52e50'", "const base = '" + full_base + "'")
  .replace("const candidate_commit = '99b997a347ea535c66128ba7858ccfeab1a32827'", "const candidate_commit = '" + commit + "'")
  .replace("const candidate = '939e171c1d8f83e065208d99d7e60b25db032cbdbf8851ee055de72e835d43b6'", "const candidate = '" + pin + "'")
  .replace('/semrange-evidence/', '/semperm-evidence/')
 os.write_file(area + '/build-kernels.v', build)!
 println('Isolated candidate ' + commit + ' source ' + pin)
}
