import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const previous = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 base := execute(['/usr/bin/git', '-C', root, 'rev-parse', '941c2ac85'])!
 names := ['kernel/proc/nice.v', 'kernel/proc/proc.v', 'kernel/userland/exit.v']
 mut pins := map[string]string{}
 for name in names {
  bytes := os.read_bytes(root + '/' + name)!
  target := area + '/source/' + name
  os.mkdir_all(os.dir(target))!
  os.write_file_array(target, bytes)!
  pins[name] = sha256.sum(bytes).hex()
 }
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
 for name in names { os.cp(area + '/source/' + name, tree + '/' + name)! }
 os.write_file(area + '/source.diff', execute(['/usr/bin/git', '-C', tree, 'diff', '--', names[0], names[1], names[2]])! + '\n')!
 execute(['/usr/bin/git', '-C', tree, 'diff', '--check'])!
 execute(['/usr/bin/git', '-C', tree, 'add', '--', names[0], names[1], names[2]])!
 execute(['/usr/bin/git', '-C', tree, 'commit', '--quiet', '-m', 'Kernel: implement retain zombie priority', '--', names[0], names[1], names[2]])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({
  'base': json2.Any(base), 'commit': commit, 'sources': json2.decode[json2.Any](json2.encode(pins))!
 }, prettify: true) + '\n')!
 println('Isolated zombie priority candidate: ' + commit)
}
