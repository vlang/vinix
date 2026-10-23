import os
import crypto.sha256
import json2

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semword-20261023'
const base = '955b4af34bd668722631cef7926be5a0a22cec1e'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}

fn main() {
 os.mkdir_all(area + '/states')!
 os.mkdir_all(area + '/tooling')!
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
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: record semaphore operation PIDs per index', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 mut build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace("const base = '51451adf1564de86e531b1de5a70f558d9bdb9b3'", "const base = '" + base + "'")
  .replace("const candidate_commit = '" + base + "'", "const candidate_commit = '" + commit + "'")
  .replace("const candidate = '0e4a76e878aeb15a498e856dd8b8c7e32fa36fd35ff401a941f2152278270c9f'", "const candidate = '" + pin + "'")
 start := build.index('\tbaseline := ') or { panic('baseline missing') }
 end := start + (build[start..].index('\n') or { panic('end missing') })
 build = build[..start] + "\tbaseline := '" + root + "/tests/linux-compat/results/2026-10-23/semword-evidence/' + suffix + '/build'" + build[end..]
 os.write_file(area + '/build-kernels.v', build)!
 os.write_file(area + '/compile.v', os.read_file(old + '/compile.v')!.replace(old, area).replace('semword', 'sempid').replace('SEMWORD', 'SEMPID'))!
 os.write_file(area + '/native.v', os.read_file(old + '/native.v')!.replace('SEMWORD', 'SEMPID').replace('checks=276', 'checks=261'))!
 reference := os.read_file(root + '/tests/linux-compat/semword-reference.v')!.replace('semword', 'sempid').replace('SEMWORD', 'SEMPID').replace('checks=276', 'checks=261').replace('checks=275', 'checks=260')
 os.write_file(root + '/tests/linux-compat/sempid-reference.v', reference)!
 os.mkdir_all(root + '/tests/linux-compat/sempidreferenceinit')!
 os.write_file(root + '/tests/linux-compat/sempidreferenceinit/core.v', os.read_file(root + '/tests/linux-compat/semwordreferenceinit/core.v')!.replace('semword', 'sempid').replace('SEMWORD', 'SEMPID'))!
 println('Isolated candidate ' + commit + ' source ' + pin)
}
