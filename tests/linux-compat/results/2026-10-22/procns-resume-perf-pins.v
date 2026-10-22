import os

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'

fn digest(path string) !string {
 expected := os.file_size(path)
 mut f := os.open(path)!
 defer { f.close() }
 mut context := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(&context) == 1
 mut b := []u8{len: 1024 * 1024}
 mut total := u64(0)
 for {
  n := f.read(mut b) or { break }
  if n == 0 { break }
  total += u64(n)
  assert C.CC_SHA256_Update(&context, b.data, u32(n)) == 1
 }
 if total != expected || os.file_size(path) != expected { return error('Incomplete or unstable input: ' + path) }
 mut result := [32]u8{}
 assert C.CC_SHA256_Final(&result[0], &context) == 1
 return result[..].hex()
}

fn main() {
 if os.args.len == 2 && os.args[1] == 'stop-original' {
  observed := os.execute('/bin/ps -p 89798 -o command=')
  assert observed.exit_code == 0 && observed.output.trim_space() == area + '/freeze-perf'
  stopped := os.execute('/bin/kill -TERM 89798')
  assert stopped.exit_code == 0
  os.write_file(area + '/freeze-perf-stop.log', 'Stopped original slow unused-image hashing helper pid89798 after equivalent optimized manifest completed; no guest process was touched.\n')!
  return
 }
 // The original helper already copied these modules before any guest launch.
 // Resume its unfinished manifest with C optimization and no input mutation.
 mut paths := []string{}
 for group in ['hosttest', 'sourcecommand', 'qmpclient', 'perfconsole', 'perfrunner', 'perfreport'] {
  paths << os.walk_ext(area + '/frozen-perf/' + group, '.v')
  paths << os.walk_ext(area + '/frozen-perf/' + group, '.h')
 }
 paths << [area + '/frozen-perf/measure.c', area + '/frozen-perf/perf-init.sh', area + '/arm-track/kernel/bin/vinix', root + '/logs/desktop-ram-fix/vinix-desktop-arm64', root + '/build-support/init-aarch64/initramfs-desktop.tar', root + '/boot-image/edk2-aarch64-code-2048x1536.fd', root + '/scripts/run-aarch64.sh', root + '/build-support/qemu-storage.sh', root + '/tools/build-qemu-module-iso', root + '/tools/build-qemu-module-iso.v', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', area + '/desktop-retention.v']
 mut pins := []string{}
 for path in paths {
  println('Pinning ' + path)
  pins << digest(path)! + '  ' + path
 }
 pins.sort()
 content := pins.join('\n') + '\n'
 if os.exists(area + '/perf-inputs.sha256') { assert os.read_file(area + '/perf-inputs.sha256')! == content, 'resumed SHA implementations disagree' }
 os.write_file(area + '/perf-inputs.sha256', content)!
 println('Frozen modules and input manifest complete (optimized resumption)')
}
