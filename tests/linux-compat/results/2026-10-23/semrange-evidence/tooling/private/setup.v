import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'
const base = 'f7db726bb'

fn execute(args []string) !string {
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if code != 0 { return error(output) }; return output.trim_space()
}

fn main() {
 os.mkdir_all(area + '/states')!
 os.mkdir_all(area + '/tmp')!
 os.mkdir_all(area + '/tooling')!
 execute([os.getenv('V'), 'fmt', '-w', root + '/tests/linux-compat/semrangefixture/core.v'])!
 os.mkdir_all(root + '/tests/linux-compat/semrangereferenceinit')!
 os.write_file(root + '/tests/linux-compat/semrangereferenceinit/core.v', os.read_file(root + '/tests/linux-compat/semarrayreferenceinit/core.v')!.replace('semarray', 'semrange').replace('SEMARRAY', 'SEMRANGE'))!
 os.write_file(root + '/tests/linux-compat/semrange-reference.v', os.read_file(root + '/tests/linux-compat/semarray-reference.v')!.replace('semarray', 'semrange').replace('SEMARRAY', 'SEMRANGE').replace('checks=457', 'checks=4200').replace('checks=456', 'checks=4199'))!
 for name in ['compile.v', 'native.v'] {
  os.write_file(area + '/' + name, os.read_file(old + '/' + name)!.replace(old, area).replace('semarray', 'semrange').replace('SEMARRAY', 'SEMRANGE').replace('checks=457', 'checks=4200'))!
 }
 os.cp(old + '/linux-v6.12-sem.c', area + '/linux-v6.12-sem.c')!
 full_base := execute(['/usr/bin/git', '-C', root, 'rev-parse', base])!
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
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: validate SETVAL range before semaphore lookup', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': full_base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace("const base = '004aaa782d989515399ccdcd9e94b81094337dcb'", "const base = '" + full_base + "'")
  .replace("const candidate_commit = '25a48efae23ed887ecd45559d7ec8b929e224809'", "const candidate_commit = '" + commit + "'")
  .replace("const candidate = '22b78bee6e8bbab1e3a84f45ab74574f81c6e5779b223ae6b02c4d3aebcd562c'", "const candidate = '" + pin + "'")
  .replace('/sempid-evidence/', '/semarray-evidence/')
 os.write_file(area + '/build-kernels.v', build)!
 // Reclaim only this earlier qualification's hash-verified omitted boot media.
 object := json2.decode[map[string]json2.Any](os.read_file(root + '/tests/linux-compat/results/2026-10-23/semarray-evidence/manifest.json')!)!
 pins := json2.decode[map[string]string](json2.encode(object['omitted'] or { panic('Missing omitted pins') }))!
 mut removed := map[string]string{}
 mut bytes := u64(0)
 for path, expected in pins {
  if !(path.starts_with(old + '/states/') || path.starts_with('/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/sa1-')) { continue }
  if !(path.ends_with('.iso') || path.ends_with('/initramfs.tar') || path.ends_with('/initramfs.cpio') || path.ends_with('.fd')) { continue }
  if !os.is_file(path) { continue }
  assert sha256.sum(os.read_bytes(path)!).hex() == expected
  bytes += os.file_size(path)
  os.rm(path)!
  removed[path] = expected
 }
 os.write_file(area + '/removed-prior-media-pins.json', json2.encode(removed, prettify: true) + '\n')!
 println('Reclaimed verified omitted media bytes=' + bytes.str())
 println('Isolated candidate ' + commit + ' source ' + pin)
}
