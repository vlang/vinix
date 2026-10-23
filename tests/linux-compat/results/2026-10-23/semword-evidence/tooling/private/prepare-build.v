import crypto.sha256
import json2
import os
const area = '/Users/alex/.cache/vinix-linux-compat/semword-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const root = '/Users/alex/code/vinix'
const base = '51451adf1564de86e531b1de5a70f558d9bdb9b3'
fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 source := os.read_bytes(root + '/kernel/sysvsem/sysvsem.v')!
 pin := sha256.sum(source).hex()
 os.write_file_array(area + '/sysvsem-candidate.v', source)!
 for suffix in ['arm', 'x86'] {
  tree := area + '/kernel-' + suffix
  execute(['/usr/bin/git', '-C', root, 'worktree', 'add', '--no-checkout', '--detach', tree, base])!
  execute(['/usr/bin/git', '-C', tree, 'sparse-checkout', 'init', '--cone'])!
  execute(['/usr/bin/git', '-C', tree, 'sparse-checkout', 'set', 'kernel', 'build-support', 'tests/native-generators', 'tests/linuxkpi', 'tests/scheduler-qos', 'tools'])!
  execute(['/usr/bin/git', '-C', tree, 'checkout', '--detach', base])!
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
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: import signed native semaphore integers before lookup', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 controller := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace("const base = '033b04639076b7e8982504322c64443f167afd20'", "const base = '" + base + "'")
  .replace("const candidate_commit = '51451adf1564de86e531b1de5a70f558d9bdb9b3'", "const candidate_commit = '" + commit + "'")
  .replace("const candidate = 'a2236eea20c6a0bf53aee5dc41db4f06d03b582459c3eaf892d0bd937f32c9da'", "const candidate = '" + pin + "'")
 start := controller.index("\tbaseline := ") or { panic('baseline missing') }
 end := start + (controller[start..].index('\n') or { panic('end missing') })
 fixed := controller[..start] + "\tbaseline := '" + old + "/states/kernel-integration4-' + suffix + '-prod'" + controller[end..]
 os.write_file(area + '/build-kernels.v', fixed)!
 println('Isolated candidate ' + commit + ' source ' + pin)
}
