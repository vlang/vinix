// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

#include <unistd.h>
fn C.truncate(&char, i64) int

struct MountReceipt {
 architecture string
 context string = 'native Vinix QEMU guest; private ext2 volume'
 inputs map[string]string
 exit_code int
}

fn digest(path string) !string {
 bytes := os.read_bytes(path)!
 return sha256.sum(bytes).hex()
}

fn main() {
 options := guesthost.parse(os.args[1..], [
  hosttest.Option{name: '--arch', value: true, choices: ['aarch64', 'x86_64']},
  hosttest.Option{name: '--kernel-dir', value: true},
  hosttest.Option{name: '--state-dir', value: true},
  hosttest.Option{name: '--timeout', value: true},
 ], [], 'Usage: run-mount.v --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR [--timeout SECONDS]')!
 for key in ['--arch', '--kernel-dir', '--state-dir'] {
  if !options.has(key) { eprintln('missing ' + key); exit(2) }
 }
 arch := options.value('--arch', '')
 state := os.abs_path(options.value('--state-dir', ''))
 timeout := options.integer('--timeout', 180)!
 if os.exists(state) || timeout <= 0 { eprintln('state must be fresh and timeout positive'); exit(2) }
 kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
 expected := if arch == 'aarch64' { 183 } else { 62 }
 if kernel.len < 20 || kernel[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || int(kernel[18]) + (int(kernel[19]) << 8) != expected {
  eprintln('kernel must be matching little-endian ELF64'); exit(2)
 }
 os.mkdir_all(state + '/kernel/bin')!
 os.mkdir_all(state + '/sources/mountfixture')!
 os.write_file_array(state + '/kernel/bin/vinix', kernel)!
 source := os.read_file(os.real_path(os.dir(@FILE) + '/mountfixture/core.v'))!
 os.write_file(state + '/sources/mountfixture/core.v', source)!
 disk := state + '/store.ext2'
 os.write_file(disk, '')!
 if unsafe { C.truncate(disk.str, 128 * 1024 * 1024) } != 0 { eprintln('cannot size private volume'); exit(1) }
 mut formatter := os.getenv('VINIX_MKE2FS')
 if formatter == '' {
  for candidate in ['mke2fs', 'mkfs.ext2', '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs'] {
   formatter = os.find_abs_path_of_executable(candidate) or { continue }
   break
  }
 }
 if formatter == '' { eprintln('mke2fs is required'); exit(2) }
 mut child := os.new_process(formatter)
 child.set_args(['-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
  'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', disk])
 child.run()
 child.wait()
 if child.code != 0 { eprintln('formatting private volume failed'); exit(1) }
 child.close()
 mut inputs := {'kernel': sha256.sum(kernel).hex(), 'fixture_source': sha256.sum(source.bytes()).hex(), 'disk_before': digest(disk)!}
 code := run_guest(state, arch, disk, timeout) or { eprintln(err.msg()); 1 }
 for name, path in {'init': state + '/init', 'iso': state + '/test.iso', 'disk_after': disk} {
  inputs[name] = digest(path) or { '' }
 }
 os.write_file(state + '/receipt.json', json2.encode(MountReceipt{arch, 'native Vinix QEMU guest; private ext2 volume', inputs, code}, prettify: true) + '\n')!
 exit(code)
}

fn run_guest(state string, arch string, disk string, timeout int) !int {
 init := guesthost.compile_init(state + '/sources/mountfixture/core.v', state, arch, false)!
 archive := guesthost.image(init, state)!
 if arch == 'x86_64' { os.setenv('VINIX_CMDLINE', os.getenv('VINIX_CMDLINE') + ' vinix.disk=auto', true) }
 configured := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
 mut command := configured.command.clone()
 if arch == 'aarch64' {
  command << ['-drive', 'if=none,format=raw,file=' + disk + ',id=compat-data', '-device', 'virtio-blk-device,drive=compat-data']
 } else { command << ['-drive', 'if=ide,format=raw,file=' + disk] }
 positive, negative := guesthost.verdict_policy(['LINUX MOUNT: PASS'], ['LINUX MOUNT FAIL'], false)
 return guesthost.boot(command, configured.env, state, positive, negative, timeout, true)!
}
