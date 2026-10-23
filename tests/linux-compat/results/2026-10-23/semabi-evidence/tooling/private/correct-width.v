import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const root = '/Users/alex/code/vinix'
const base = '033b04639076b7e8982504322c64443f167afd20'

fn execute(args []string) !string {
 mut p := os.new_process(args[0])
 p.set_args(args[1..])
 p.set_redirect_stdio_merged()
 p.run()
 text := p.stdout_slurp()
 p.wait()
 code := p.code
 p.close()
 if code != 0 { return error(text) }
 return text.trim_space()
}

fn main() {
 for suffix in ['arm', 'x86'] {
  state := area + '/states/kernel-integration3-' + suffix + '-prod'
  assert os.exists(state + '/status'), 'Wait for the stopped controller to finish'
  os.write_file(state + '/cancel-reason.txt', 'Compilation stopped after generated-C review found SETVAL cast to kernel V int (64 bits); final source uses explicit i32. Not a qualified build.\n')!
 }
 archive := area + '/draft-width'
 assert !os.exists(archive)
 os.mkdir_all(archive)!
 old := json2.decode[map[string]string](os.read_file(area + '/prepared-source-inputs.json')!)!
 for name in ['sysvsem-candidate.v', 'prepared-source-inputs.json', 'integration-source.diff', 'build-kernels.v', 'prepare-integration.v'] {
  os.cp(area + '/' + name, archive + '/' + name)!
 }
 source := os.read_file(root + '/kernel/sysvsem/sysvsem.v')!
 assert source.contains('value := i32(argument)')
 pin := sha256.sum(source.bytes()).hex()
 os.write_file(area + '/sysvsem-candidate.v', source)!
 for suffix in ['arm', 'x86'] {
  tree := area + '/kernel-' + suffix
  execute(['/usr/bin/git', '-C', tree, 'checkout', '--detach', base])!
 }
 tree := area + '/kernel-arm'
 os.cp(area + '/sysvsem-candidate.v', tree + '/kernel/sysvsem/sysvsem.v')!
 os.write_file(area + '/integration-source.diff', execute(['/usr/bin/git', '-C', tree, 'diff', '--', 'kernel/sysvsem/sysvsem.v'])! + '\n')!
 execute(['/usr/bin/git', '-C', tree, 'diff', '--check'])!
 execute(['/usr/bin/git', '-C', tree, 'add', '--', 'kernel/sysvsem/sysvsem.v'])!
 execute(['/usr/bin/git', '-C', tree, 'commit', '-m', 'Kernel: match native semaphore argument widths and errors', '--', 'kernel/sysvsem/sysvsem.v'])!
 commit := execute(['/usr/bin/git', '-C', tree, 'rev-parse', 'HEAD'])!
 execute(['/usr/bin/git', '-C', area + '/kernel-x86', 'checkout', '--detach', commit])!
 os.write_file(area + '/prepared-source-inputs.json', json2.encode({'base': base, 'commit': commit, 'source_sha256': pin}, prettify: true) + '\n')!
 for path in [area + '/build-kernels.v', root + '/tests/linux-compat/semabi-evidence.v'] {
  text := os.read_file(path)!.replace(old['commit'], commit).replace(old['source_sha256'], pin)
  os.write_file(path, text)!
 }
 publisher := os.read_file(area + '/publish.v')!.replace('kernel-integration3-', 'kernel-integration4-')
 os.write_file(area + '/publish.v', publisher)!
 println('Corrected candidate ' + commit + ' source ' + pin)
}
