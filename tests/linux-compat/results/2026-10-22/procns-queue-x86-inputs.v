import os

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

fn digest(path string) !string {
 mut file := os.open(path)!
 defer { file.close() }
 mut context := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(&context) == 1
 mut buffer := []u8{len: 1024 * 1024}
 mut size := u64(0)
 for {
  n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  size += u64(n)
  assert C.CC_SHA256_Update(&context, buffer.data, u32(n)) == 1
 }
 assert size == os.file_size(path)
 mut sum := [32]u8{}
 assert C.CC_SHA256_Final(&sum[0], &context) == 1
 return sum[..].hex()
}

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 root := '/Users/alex/code/vinix'
 assert os.args.len == 2 && os.args[1] in ['pin', 'verify']
 mut paths := os.walk_ext(area + '/qf-x86-tools', '')
 paths << os.walk_ext(area + '/qf-x86-launch', '')
 paths << os.walk_ext(area + '/qf-x86-curl', '')
 paths << [area + '/qf-x86-curl-setup.v', area + '/qf-x86-preserve-initial.v']
 for name in ['qf-x86-tools-wrapper.v', 'qf-x86-prepare.v', 'qf-x86-iso.v', 'qf-x86-run', 'qf-x86-audit.v', 'qf-x86-audit', 'qf-x86-inputs.v', 'qf-x86-producer.v', 'qf-x86-producer', 'qf-x86-audit-tail.v', 'qf-x86-prepare-audit.v', 'qf-x86-finish.v', 'qf-x86-finish'] { paths << area + '/' + name }
 paths << [area + '/queue-fix/x86-prod/kernel/bin/vinix', root + '/build-amd64-desktop/initramfs-desktop.tar', root + '/logs/desktop-ram-fix/vinix-desktop-amd64', root + '/logs/desktop-ram-fix/source.tar', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', os.executable()]
 for name in ['commit.txt', 'inputs-x86-prod.sha256', 'build-x86-prod.log', 'build-x86-prod.log.status', 'generated-review-x86-prod.log', 'generated-review-x86-prod.status', 'x86-prod/blob.c'] { paths << area + '/queue-fix/' + name }
 qemu := '/opt/homebrew/bin/qemu-system-x86_64'
 assert os.getenv('VINIX_QEMU_X86_64') == '' && os.getenv('VINIX_OVMF_CODE') == '', 'unexpected firmware/emulator override'
 paths << [qemu, '/opt/homebrew/share/qemu/edk2-x86_64-code.fd', '/opt/homebrew/bin/xorriso', '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs', area + '/launch-root/build-amd64-iso/limine/limine-uefi-cd.bin', area + '/launch-root/build-amd64-iso/limine/BOOTX64.EFI']
 paths.sort()
 mut pins := []string{}
 for path in paths { assert os.is_file(path), 'required frozen input missing: ' + path; pins << digest(path)! + '  ' + path }
 content := pins.join('\n') + '\n'
 manifest := area + '/qf-x86-inputs.sha256'
 if os.args[1] == 'pin' { assert !os.exists(manifest); os.write_file(manifest, content)! } else { assert os.read_file(manifest)! == content, 'x86 Q frozen inputs changed' }
 println('x86 Q input ' + os.args[1] + ': PASS ' + pins.len.str() + ' files')
}
