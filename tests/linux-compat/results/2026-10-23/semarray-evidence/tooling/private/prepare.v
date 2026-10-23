import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'
const base = '004aaa782d989515399ccdcd9e94b81094337dcb'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}

fn main() {
 fixture := root + '/tests/linux-compat/semarrayfixture/core.v'
 mut text := os.read_file(fixture)!
 for pair in [['fn basic(', 'fn start('], ['fn queued(', "@[export: 'main']"]] {
  start := text.index(pair[0]) or { panic('start') }
  end := text.index(pair[1]) or { panic('end') }
  mut part := text[start..end]
  for value in ['&buffer[1]', '&input[0]', '&values[0]', '&invalid[0]', '&u16(isize(memory) + page - 8)', '&u16(isize(memory) + page - 6)', 'edge[index] = wanted[index]', 'crossing[0] = 65535'] {
   part = part.replace('unsafe { ' + value + ' }', value)
  }
  text = text[..start] + part + text[end..]
 }
 os.write_file(fixture, text)!
 execute([os.getenv('V'), 'fmt', '-w', fixture])!
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
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: implement semaphore array control operations', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 mut build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace("const base = '955b4af34bd668722631cef7926be5a0a22cec1e'", "const base = '" + base + "'")
  .replace("const candidate_commit = '" + base + "'", "const candidate_commit = '" + commit + "'")
  .replace("const candidate = 'c9c74221120bc1dd4c8695eb59a4f151604a4449bef6439e796b89824ecdc186'", "const candidate = '" + pin + "'")
 build = build.replace('/semword-evidence/', '/sempid-evidence/')
 os.write_file(area + '/build-kernels.v', build)!
 os.write_file(area + '/native.v', os.read_file(area + '/native.v')!.replace('checks=261', 'checks=457'))!
 os.write_file(root + '/tests/linux-compat/semarray-reference.v', os.read_file(root + '/tests/linux-compat/sempid-reference.v')!
  .replace('sempid', 'semarray').replace('SEMPID', 'SEMARRAY').replace('checks=261', 'checks=457').replace('checks=260', 'checks=456'))!
 println('Isolated candidate ' + commit + ' source ' + pin)
}
