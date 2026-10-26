// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only comparison of focused APK fixtures, including ZIP signing metadata.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

struct Entry {
 name string
 compression int
 crc u32
 compressed_size int
 size int
 payload_sha256 string
 dos_time int
 dos_date int
 extra_hex string
}

struct Zip {
 entries []Entry
 normalized_sha256 string
 signing_block_sha256 string
 signing_block_start int
 timestamp_offsets []int
}

fn digest(bytes []u8) string {
 mut context := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(unsafe { &context }) == 1
 assert C.CC_SHA256_Update(unsafe { &context }, bytes.data, u32(bytes.len)) == 1
 mut value := [32]u8{}
 assert C.CC_SHA256_Final(unsafe { &value[0] }, unsafe { &context }) == 1
 return value[..].hex()
}

fn hash(path string) !string { return digest(os.read_bytes(path)!) }
fn json_value[T](value T) json2.Any {
 return json2.decode[json2.Any](json2.encode(value)) or { panic(err) }
}
fn le16(bytes []u8, at int) int { return int(bytes[at]) | (int(bytes[at + 1]) << 8) }
fn le32(bytes []u8, at int) u32 {
 return u32(bytes[at]) | (u32(bytes[at + 1]) << 8) | (u32(bytes[at + 2]) << 16) | (u32(bytes[at + 3]) << 24)
}
fn le64(bytes []u8, at int) u64 { return u64(le32(bytes, at)) | (u64(le32(bytes, at + 4)) << 32) }

fn zero(mut bytes []u8, at int, count int, mut offsets []int) {
 assert at >= 0 && count >= 0 && at + count <= bytes.len
 for index in at .. at + count { bytes[index] = 0; offsets << index }
}

fn timestamps(mut bytes []u8, at int, count int, central bool, mut offsets []int) {
 mut cursor := at
 for cursor < at + count {
  assert cursor + 4 <= at + count
  kind := le16(bytes, cursor)
  size := le16(bytes, cursor + 2)
  assert cursor + 4 + size <= at + count
  if kind == 0x5455 {
   assert size >= 1 && size <= 13 && (size - 1) % 4 == 0
   flags := bytes[cursor + 4]
   assert flags & 0xf8 == 0, 'supported UT timestamp bits only'
   mut fields := if flags & 1 != 0 { 1 } else { 0 }
   if !central {
    if flags & 2 != 0 { fields++ }
    if flags & 4 != 0 { fields++ }
   }
   assert size == 1 + fields * 4, 'exact UT timestamp payload required'
   zero(mut bytes, cursor + 5, size - 1, mut offsets)
  }
  cursor += 4 + size
 }
 assert cursor == at + count
}

fn inspect(path string) !Zip {
 bytes := os.read_bytes(path)!
 assert bytes.len > 22 && bytes.len < 65536, 'focused non-ZIP64 APK required'
 end := bytes.len - 22
 assert le32(bytes, end) == 0x06054b50 && le16(bytes, end + 20) == 0
 assert le16(bytes, end + 4) == 0 && le16(bytes, end + 6) == 0
 count := le16(bytes, end + 10)
 assert count == le16(bytes, end + 8)
 central := int(le32(bytes, end + 16))
 assert central >= 24 && central + int(le32(bytes, end + 12)) == end
 assert bytes[central - 16 .. central].bytestr() == 'APK Sig Block 42'
 block_size := le64(bytes, central - 24)
 assert block_size <= u64(central - 8) && block_size > 24
 block_start := central - int(block_size) - 8
 assert le64(bytes, block_start) == block_size
 block_sha := digest(bytes[block_start .. central])
 mut normalized := bytes.clone()
 mut offsets := []int{}
 mut entries := []Entry{}
 mut cursor := central
 for _ in 0 .. count {
  assert le32(bytes, cursor) == 0x02014b50
  flags := le16(bytes, cursor + 8)
  assert flags & 9 == 0, 'unencrypted entries without descriptors required'
  name_len := le16(bytes, cursor + 28)
  extra_len := le16(bytes, cursor + 30)
  comment_len := le16(bytes, cursor + 32)
  name := bytes[cursor + 46 .. cursor + 46 + name_len].bytestr()
  local := int(le32(bytes, cursor + 42))
  assert local >= 0 && local + 30 <= block_start
  assert le32(bytes, local) == 0x04034b50
  assert le16(bytes, local + 6) == flags
  assert le16(bytes, local + 8) == le16(bytes, cursor + 10)
  assert le32(bytes, local + 14) == le32(bytes, cursor + 16)
  assert le32(bytes, local + 18) == le32(bytes, cursor + 20)
  assert le32(bytes, local + 22) == le32(bytes, cursor + 24)
  local_name := le16(bytes, local + 26)
  local_extra := le16(bytes, local + 28)
  assert local + 30 + local_name + local_extra <= block_start
  assert bytes[local + 30 .. local + 30 + local_name].bytestr() == name
  start := local + 30 + local_name + local_extra
  compressed := int(le32(bytes, cursor + 20))
  assert compressed >= 0 && start + compressed <= block_start
  entries << Entry{name: name, compression: le16(bytes, cursor + 10),
   crc: le32(bytes, cursor + 16), compressed_size: compressed,
   size: int(le32(bytes, cursor + 24)), payload_sha256: digest(bytes[start .. start + compressed]),
   dos_time: le16(bytes, cursor + 12), dos_date: le16(bytes, cursor + 14),
   extra_hex: bytes[cursor + 46 + name_len .. cursor + 46 + name_len + extra_len].hex()}
  zero(mut normalized, local + 10, 4, mut offsets)
  zero(mut normalized, cursor + 12, 4, mut offsets)
  timestamps(mut normalized, local + 30 + local_name, local_extra, false, mut offsets)
  timestamps(mut normalized, cursor + 46 + name_len, extra_len, true, mut offsets)
  cursor += 46 + name_len + extra_len + comment_len
 }
 assert cursor == end
 for index in block_start .. central { normalized[index] = 0 }
 return Zip{entries: entries, normalized_sha256: digest(normalized),
  signing_block_sha256: block_sha, signing_block_start: block_start, timestamp_offsets: offsets}
}

fn inventory(root string, prefix string, mut result map[string]string) ! {
 for name in os.ls(root + '/' + prefix)! {
  key := if prefix == '' { name } else { prefix + '/' + name }
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { inventory(root, key, mut result)! }
   .regular { result[key] = hash(root + '/' + key)! }
   else { return error('regular fixture inputs required: ' + key) }
  }
 }
}

fn main() {
 assert os.args.len == 4, 'usage: apk-content-compare OLD-FIXTURE NEW-FIXTURE FRESH-RECEIPT'
 old_root := os.real_path(os.args[1])
 new_root := os.real_path(os.args[2])
 receipt := os.args[3]
 assert !os.exists(receipt) && os.is_abs_path(receipt)
 assert !receipt.starts_with(old_root + '/') && !receipt.starts_with(new_root + '/')
 started := time.utc().str()
 mut compared := map[string]string{}
 for directory in ['apk/smali', 'apk/res', 'fixture-inputs'] {
  mut old := map[string]string{}
  mut new := map[string]string{}
  inventory(old_root + '/' + directory, '', mut old) or { panic(err) }
  inventory(new_root + '/' + directory, '', mut new) or { panic(err) }
  assert old == new, directory + ' differs'
  for name, pin in old { compared[directory + '/' + name] = pin }
 }
 for name in ['apk/classes.dex', 'apk/AndroidManifest.xml', 'apk/fixture.p12',
  'frozen/vroot/bundle-parcel-driver/main.v',
  'frozen/vroot/bundle-parcel-driver/startupfixture/bundle_parcel.v'] {
  pin := hash(old_root + '/' + name) or { panic(err) }
  assert hash(new_root + '/' + name) or { panic(err) } == pin, name + ' differs'
  compared[name] = pin
 }
 old := inspect(old_root + '/apk/probe.apk') or { panic(err) }
 new := inspect(new_root + '/apk/probe.apk') or { panic(err) }
 assert old.entries.len == new.entries.len
 for index, entry in old.entries {
  other := new.entries[index]
  assert entry.name == other.name && entry.compression == other.compression
  assert entry.crc == other.crc && entry.compressed_size == other.compressed_size
  assert entry.size == other.size && entry.payload_sha256 == other.payload_sha256
 }
 assert old.timestamp_offsets == new.timestamp_offsets
 assert old.normalized_sha256 == new.normalized_sha256,
  'APK bytes differ outside ZIP timestamps and signing block'
 mut before := map[string]string{}
 for name in ['apk/probe.apk', 'apk/unsigned.apk', 'apk/resources.zip', 'apk/classes.dex', 'build-pins.json'] {
  before['old/' + name] = hash(old_root + '/' + name) or { panic(err) }
  before['new/' + name] = hash(new_root + '/' + name) or { panic(err) }
 }
 os.write_file(receipt, json2.encode({'argv': json2.Any(os.args),
  'source_sha256': json2.Any(hash(@FILE) or { panic(err) }),
  'executable_sha256': json2.Any(hash(os.executable()) or { panic(err) }),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'old_root': json2.Any(old_root), 'new_root': json2.Any(new_root),
  'compared_inputs': json_value(compared), 'artifact_sha256': json_value(before),
  'old_zip': json_value(old), 'new_zip': json_value(new),
  'scope': json2.Any('Read-only focused fixture comparison. Exact equality of listed fixture source, APK resource/signing inputs, packaging tools and DEX; each compressed ZIP member payload identical. Full APK byte equality after masking only validated ZIP timestamp fields and a non-overlapping APK signing block. Compiler closure is outside this comparison.'),
  'passed': json2.Any(true)}, prettify: true) + '\n') or { panic(err) }
 println('APK-CONTENT-COMPARE-PASS inputs=' + compared.len.str() + ' members=' + old.entries.len.str())
}
