import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'

fn digest(path string) !string {
 mut f := os.open(path)!
 defer { f.close() }
 mut d := sha256.new()
 mut buffer := []u8{len: 1024 * 1024}
 for {
  n := f.read(mut buffer) or { break }
  if n == 0 { break }
  d.write(buffer[..n])!
 }
 return d.sum([]u8{}).hex()
}

fn main() {
 frozen := area + '/frozen-perf'
 assert !os.exists(frozen)
 os.mkdir_all(frozen)!
 mut pins := []string{}
 sources := {
  'hosttest': root + '/tests/linuxkpi/hosttest'
  'sourcecommand': root + '/tools/sourcecommand'
  'qmpclient': root + '/tools/qmpclient'
  'perfconsole': root + '/tests/desktop-perf/perfconsole'
  'perfrunner': root + '/tests/desktop-perf/perfrunner'
  'perfreport': root + '/tests/desktop-perf/perfreport'
 }
 for name, source in sources {
  target := frozen + '/' + name
  os.mkdir_all(target)!
  for filename in os.ls(source)! {
   if filename.ends_with('_test.v') || (!filename.ends_with('.v') && !filename.ends_with('.h')) { continue }
   os.cp(source + '/' + filename, target + '/' + filename)!
   pins << digest(target + '/' + filename)! + '  ' + target + '/' + filename
  }
 }
 for filename in ['measure.c', 'perf-init.sh'] {
  target := frozen + '/' + filename
  os.cp(root + '/tests/desktop-perf/' + filename, target)!
  pins << digest(target)! + '  ' + target
 }
 for path in [area + '/arm-track/kernel/bin/vinix', root + '/logs/desktop-ram-fix/vinix-desktop-arm64', root + '/build-support/init-aarch64/initramfs-desktop.tar', root + '/boot-image/edk2-aarch64-code-2048x1536.fd', root + '/scripts/run-aarch64.sh', root + '/build-support/qemu-storage.sh', root + '/tools/build-qemu-module-iso', root + '/tools/build-qemu-module-iso.v', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', area + '/desktop-retention.v'] {
  println('Pinning ' + path)
  pins << digest(path)! + '  ' + path
 }
 pins.sort()
 os.write_file(area + '/perf-inputs.sha256', pins.join('\n') + '\n')!
 println('Frozen modules and input manifest complete')
}
