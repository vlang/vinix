@[has_globals]
module main

import guesthost
import json2
import os
import perfconsole
import perfrunner

#include <unistd.h>
fn C.truncate(&char, i64) int

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

fn digest(path string) !string {
 mut input := os.open(path)!
 defer { input.close() }
 mut context := C.CC_SHA256_CTX{}
 if C.CC_SHA256_Init(&context) != 1 { return error('digest initialization failed') }
 mut buffer := []u8{len: 1024 * 1024}
 mut total := u64(0)
 for {
  n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  total += u64(n)
  if C.CC_SHA256_Update(&context, buffer.data, u32(n)) != 1 { return error('digest update failed') }
 }
 if total != os.file_size(path) { return error('digest input size changed') }
 mut sum := [32]u8{}
 if C.CC_SHA256_Final(&sum[0], &context) != 1 { return error('digest finalization failed') }
 return sum[..].hex()
}

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 root := '/Users/alex/code/vinix'
 if os.args.len != 2 || os.args[1] !in ['ops', 'drag'] { panic('usage: ops|drag') }
 label := os.args[1]
 scenarios := if label == 'ops' { 'ops,churn,cache,idle,apps' } else { 'drag' }
 work := area + if label == 'ops' { '/qxo' } else { '/qxd' }
 if os.exists(work) { panic('fresh state required') }
 os.mkdir_all(work + '/kernel/bin')!
 kernel := area + '/queue-fix/x86-prod/kernel/bin/vinix'
 os.cp(kernel, work + '/kernel/bin/vinix')!
 if digest(work + '/kernel/bin/vinix')! != '27295b43e131ef9f2df0fc55f07ab5cc9ea2b3c4ff6a10227f97fb44170d337d' { panic('kernel pin mismatch') }
 os.mkdir_all(work + '/overlay/opt/vinix-perf')!
 os.mkdir_all(work + '/overlay/sbin')!
 base := root + '/build-amd64-desktop/initramfs-desktop.tar'
 desktop := root + '/logs/desktop-ram-fix/vinix-desktop-amd64'
 os.cp(desktop, work + '/overlay/opt/vinix-perf/vinix-desktop-new')!
 original := os.read_file(area + '/qf-x86-tools/perf-init.sh')!
 mount_setup := '#!/bin/sh\nexec >/dev/com1 2>&1\nmkdir -p /root\nroot_ok=0\nfor dev in /dev/sd0 /dev/sd1 /dev/ata0 /dev/ata1; do\n if mount -t ext2 "$dev" /root; then root_ok=1; echo "PERF-ROOT device=$dev target=/root type=ext2"; break; fi\ndone\nif [ "$root_ok" != 1 ]; then echo "PERF-ERROR ext2 root mount failed"; poweroff -f; exit 1; fi\ncat /proc/mounts\n'
 os.write_file(work + '/overlay/sbin/init', original.replace('#!/bin/sh\n', mount_setup))!
 os.chmod(work + '/overlay/sbin/init', 0o755)!
 os.mkdir_all(work + '/overlay/usr/bin')!
 for line in os.read_lines(area + '/qf-x86-curl/inputs.sha256')! {
  parts := line.split('  ')
  if parts.len != 2 { panic('invalid curl input pin') }
  source := area + '/qf-x86-curl/rootfs/' + parts[1]
  target := work + '/overlay/' + parts[1]
  if digest(source)! != parts[0] { panic('curl source pin changed') }
  os.mkdir_all(os.dir(target))!
  os.cp(source, target)!
  if digest(target)! != parts[0] { panic('curl overlay pin changed') }
 }
 os.symlink('vinix-desktop', work + '/overlay/usr/bin/vinix-activity-monitor')!
 os.cp(area + '/ds/overlay/opt/vinix-perf/measure', work + '/overlay/opt/vinix-perf/measure')!
 os.write_file(work + '/overlay/opt/vinix-perf/config', "VARIANTS='new'\nSCENARIOS='${scenarios.replace(',', ' ')}'\nROUNDS=1\nSETTLE=3\nMEASURE=5\nDESKTOP_ARGS='--stats'\n")!
 guard := perfconsole.own_commands()
 defer { guard.close() }
 archive := work + '/initramfs.tar'
 perfrunner.command(['cp', '-c', base, archive])!
 os.setenv('COPYFILE_DISABLE', '1', true)
 perfrunner.command(['tar', '--format=ustar', '-rf', archive, '-C', work + '/overlay', '.'])!
 disk := work + '/root.ext2'
 os.write_file(disk, '')!
 if unsafe { C.truncate(disk.str, i64(128 * 1024 * 1024)) } != 0 { panic('disk sizing failed') }
 perfrunner.command(['/opt/homebrew/opt/e2fsprogs/sbin/mke2fs', '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O', 'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', disk])!
 disk_hash := digest(disk)!
 os.mkdir_all(work + '/vm')!
 launch := guesthost.launch_from(work + '/overlay/sbin/init', archive, work + '/vm', work + '/kernel', 'x86_64', true, area + '/qf-x86-launch')!
 mut command := launch.command.clone()
 command[command.index('-m') + 1] = '4096'
 command[command.index('-smp') + 1] = '4'
 command << ['-vga', 'std', '-device', 'qemu-xhci,id=xhci', '-device', 'usb-tablet,bus=xhci.0', '-drive', 'if=none,format=raw,file=' + disk + ',id=perf-root', '-device', 'ide-hd,drive=perf-root,bus=ide.0']
 os.write_file(work + '/receipt.json', json2.encode({
  'revision': 'bd9aa1bc1d04eac1ce31e02ce8914969294566ff'
  'architecture': 'x86_64'
  'kernel_sha256': digest(work + '/kernel/bin/vinix')!
  'kernel_build_inputs_sha256': digest(area + '/queue-fix/inputs-x86-prod.sha256')!
  'kernel_build_log_sha256': digest(area + '/queue-fix/build-x86-prod.log')!
  'kernel_revision_sha256': digest(area + '/queue-fix/commit.txt')!
  'base_sha256': digest(base)!
  'desktop_sha256': digest(work + '/overlay/opt/vinix-perf/vinix-desktop-new')!
  'desktop_source_sha256': digest(root + '/logs/desktop-ram-fix/source.tar')!
  'init_source_sha256': digest(area + '/qf-x86-tools/perf-init.sh')!
  'init_sha256': digest(work + '/overlay/sbin/init')!
  'measure_source_sha256': digest(area + '/qf-x86-tools/measure.c')!
  'measure_sha256': digest(work + '/overlay/opt/vinix-perf/measure')!
  'curl_inputs_sha256': digest(area + '/qf-x86-curl/inputs.sha256')!
  'curl_provenance_sha256': digest(area + '/qf-x86-curl/provenance.json')!
  'curl_sha256': digest(work + '/overlay/usr/bin/curl')!
  'archive_sha256': digest(archive)!
  'iso_sha256': digest(work + '/vm/test.iso')!
  'initial_ext2_sha256': disk_hash
  'command': command.join(' ')
 }, prettify: true) + '\n')!
 plan := perfrunner.parse(['new=' + desktop, '--scenarios=' + scenarios, '--rounds=1', '--settle=3', '--seconds=5', '--mem=4096', '--timeout=3600', '--desktop-args=--stats', '--json=' + work + '/results.json', '--shots=' + work + '/shots'], root, area + '/qf-x86-tools', '')!
 status := perfrunner.drive(plan, perfrunner.Launch{command, launch.env, work + '/vm/qmp.sock'}, work, 10, true) or { eprintln(err); 1 }
 os.write_file(work + '/status', '${status}\n')!
 exit(status)
}
