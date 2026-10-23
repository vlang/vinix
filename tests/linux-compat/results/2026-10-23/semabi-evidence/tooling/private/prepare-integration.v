import crypto.sha256
import json2
import os
const area = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const base = '033b04639076b7e8982504322c64443f167afd20'
fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 old := json2.decode[map[string]string](os.read_file(area + '/prepared-source-inputs.json')!)!
 os.cp(area + '/prepared-source-inputs.json', area + '/initial-private-source-inputs.json')!
 for suffix in ['arm', 'x86'] {
  tree := area + '/kernel-' + suffix
  execute(['/usr/bin/git', '-C', tree, 'sparse-checkout', 'init', '--cone'])!
  execute(['/usr/bin/git', '-C', tree, 'sparse-checkout', 'set', 'kernel', 'build-support', 'tests/native-generators', 'tests/linuxkpi', 'tests/scheduler-qos', 'tools'])!
  execute(['/usr/bin/git', '-C', tree, 'checkout', '--detach', base])!
 }
 tree := area + '/kernel-arm'
 os.cp(area + '/sysvsem-candidate.v', tree + '/kernel/sysvsem/sysvsem.v')!
 os.write_file(area + '/integration-source.diff', execute(['/usr/bin/git', '-C', tree, 'diff', '--', 'kernel/sysvsem/sysvsem.v'])! + '\n')!
 execute(['/usr/bin/git', '-C', tree, 'diff', '--check'])!
 execute(['/usr/bin/git', '-C', tree, 'add', '--', 'kernel/sysvsem/sysvsem.v'])!
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: match native semaphore argument ABI and errors', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': base, 'commit': commit, 'source_sha256': old['source_sha256']}, prettify: true) + '\n')!
 mut controller := os.read_file(area + '/build-kernels.v')!
 controller = controller.replace("const base = '" + old['base'] + "'", "const base = '" + base + "'").replace("const candidate_commit = '" + old['commit'] + "'", "const candidate_commit = '" + commit + "'")
 os.write_file(area + '/build-kernels.v', controller)!
 println('Isolated integration base ' + base + ' candidate ' + commit)
}
