import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const root = '/Users/alex/code/vinix'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 for name in ['build-kernels.v', 'build-kernels', 'prepared-source-inputs.json', 'source.diff'] {
  os.cp(area + '/' + name, area + '/first-' + name)!
 }
 mut pins := map[string]string{}
 names := ['kernel/proc/nice.v', 'kernel/syscall/table/linux_common.v']
 tree := area + '/kernel-arm'
 for name in names {
  old := area + '/first-source/' + name
  os.mkdir_all(os.dir(old))!
  os.cp(area + '/source/' + name, old)!
  bytes := os.read_bytes(root + '/' + name)!
  os.write_file_array(area + '/source/' + name, bytes)!
  os.write_file_array(tree + '/' + name, bytes)!
  pins[name] = sha256.sum(bytes).hex()
 }
 execute(['/usr/bin/git', '-C', tree, 'diff', '--check'])!
 execute(['/usr/bin/git', '-C', tree, 'add', '--', names[0], names[1]])!
 execute(['/usr/bin/git', '-C', tree, 'commit', '--amend', '--no-edit', '--quiet', '--', names[0], names[1]])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 base := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD^'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/source.diff', execute(['/usr/bin/git', '-C', tree, 'diff', base, 'HEAD', '--', names[0], names[1]])! + '\n')!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({
  'base': json2.Any(base), 'commit': commit, 'sources': json2.decode[json2.Any](json2.encode(pins))!
 }, prettify: true) + '\n')!
 old := os.read_file(area + '/first-build-kernels.v')!
 build := old.replace('04a92081d7fc1039aac3168a5863c43161b9d339', commit)
  .replace('0192778a4697539dcd2e7083e93e59c1f5f6ea2f4540c1151011a151cdb17073', pins[names[0]])
 os.write_file(area + '/build-kernels.v', build)!
 println('Revised isolated candidate: ' + commit + ' ' + json2.encode(pins))
}
