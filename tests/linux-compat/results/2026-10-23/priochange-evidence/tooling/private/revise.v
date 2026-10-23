import crypto.sha256
import json2
import os
const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const root = '/Users/alex/code/vinix'
fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}
fn main() {
 for suffix in ['arm', 'x86'] { assert os.read_file(area + '/states/kernel-first-' + suffix + '-record.status')!.trim_space() == '1' }
 os.cp_all(area + '/source', area + '/first-source', true)!
 for name in ['source.diff', 'prepared-source-inputs.json', 'build-kernels.v'] { os.cp(area + '/' + name, area + '/first-' + name)! }
 old := json2.decode[map[string]json2.Any](os.read_file(area + '/prepared-source-inputs.json')!)!
 names := ['kernel/proc/nice.v', 'kernel/syscall/table/linux_common.v']
 mut pins := map[string]string{}
 for name in names {
  os.cp(root + '/' + name, area + '/source/' + name)!
  os.cp(root + '/' + name, area + '/kernel-arm/' + name)!
  pins[name] = sha256.sum(os.read_bytes(root + '/' + name)!).hex()
 }
 execute(['/usr/bin/git', '-C', area + '/kernel-arm', 'diff', '--check'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-arm', 'add', '--', names[0], names[1]])!
 execute(['/usr/bin/git', '-C', area + '/kernel-arm', 'commit', '--amend', '--no-edit', '--quiet', '--', names[0], names[1]])!
 commit := execute(['/usr/bin/git', '-C', area + '/kernel-arm', 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 diff := execute(['/usr/bin/git', '-C', area + '/kernel-arm', 'diff', old['base']!.str(), 'HEAD', '--', names[0], names[1]])!
 os.write_file(area + '/source.diff', diff + '\n')!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': old['base']!, 'commit': json2.Any(commit), 'sources': json2.decode[json2.Any](json2.encode(pins))!}, prettify: true) + '\n')!
 old_pins := old['sources']!.as_map()
 build := os.read_file(area + '/first-build-kernels.v')!.replace(old['commit']!.str(), commit).replace(old_pins[names[0]]!.str(), pins[names[0]])
 os.write_file(area + '/build-kernels.v', build)!
 println('Revised isolated setter candidate: ' + commit)
}
