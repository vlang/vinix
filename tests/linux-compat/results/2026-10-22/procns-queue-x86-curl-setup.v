import os
import json2

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

fn digest(path string) !string {
 mut f := os.open(path)!
 defer { f.close() }
 mut c := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(&c) == 1
 mut b := []u8{len: 1024 * 1024}
 for {
  n := f.read(mut b) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  assert C.CC_SHA256_Update(&c, b.data, u32(n)) == 1
 }
 mut s := [32]u8{}
 assert C.CC_SHA256_Final(&s[0], &c) == 1
 return s[..].hex()
}

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 source := '/Users/alex/code/vinix/build/str-x86-20261022-2/packages-https-runtime/rootfs'
 frozen := area + '/qf-x86-curl'
 assert !os.exists(frozen)
 names := ['lib/ld-musl-x86_64.so.1', 'lib/libc.musl-x86_64.so.1', 'usr/bin/curl',
  'usr/lib/libbrotlicommon.so.1', 'usr/lib/libbrotlidec.so.1', 'usr/lib/libcares.so.2',
  'usr/lib/libcrypto.so.3', 'usr/lib/libcurl.so.4', 'usr/lib/libidn2.so.0',
  'usr/lib/libnghttp2.so.14', 'usr/lib/libpsl.so.5', 'usr/lib/libssl.so.3',
  'usr/lib/libunistring.so.5', 'usr/lib/libz.so.1', 'usr/lib/libzstd.so.1']
 mut pins := []string{}
 mut records := []map[string]string{}
 for name in names {
  original, target := source + '/' + name, frozen + '/rootfs/' + name
  assert os.is_file(original)
  hash := digest(original)!
  os.mkdir_all(os.dir(target))!
  os.cp(original, target)!
  assert digest(target)! == hash
  os.chmod(target, if name == 'usr/bin/curl' || name.starts_with('lib/') { 0o755 } else { 0o644 })!
  pins << hash + '  ' + name
  records << {'source': original, 'frozen': target, 'sha256': hash}
 }
 os.write_file(frozen + '/inputs.sha256', pins.join('\n') + '\n')!
 os.write_file(frozen + '/provenance.json', json2.encode(records, prettify: true) + '\n')!
 os.write_file(frozen + '/notes.txt', 'Genuine cached x86-64 musl curl and complete cached HTTPS fixture shared-library/interpreter closure. This private overlay fills the absent curl binary in the original desktop archive. Original 36x200 ops and four300-run churn programs remain unchanged; final Q2 kernel remains unchanged. No program substitution. Initial missing-curl failure remains separate.\n')!
 println('PASS: frozen genuine cached x86 curl and 14 runtime/interpreter files with exact source/destination SHA256 pins.')
}
