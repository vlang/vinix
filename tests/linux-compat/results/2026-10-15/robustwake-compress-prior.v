import json2
import os
#include <CommonCrypto/CommonDigest.h>
fn C.CC_SHA256(voidptr,u32,&u8) &u8
const area = '/Users/alex/.cache/vinix-linux-compat/robustwake-20261015/'
const prior = '/Users/alex/.cache/vinix-linux-compat/robustquery-20261015/'
fn digest(path string) string {
 data := os.read_bytes(path) or {panic(err)}; assert u64(data.len) < u64(0x100000000)
 mut result := [32]u8{}; unsafe {C.CC_SHA256(data.data,u32(data.len),&result[0]); data.free()}; return result[..].hex()
}
fn command(program string,args []string) string {
 mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); status := p.code; p.close(); assert status == 0,output; return output
}
fn main() {
 assert os.is_file(area+'base.txt') && !os.exists(area+'prior-transparent-compression.json')
 mut paths := map[string]string{}
 for name in ['before-arm.c','before-x86.c','after-arm.c','after-x86.c','output-only-arm.c','output-only-x86.c','output-only-arm.elf','output-only-x86.elf'] {paths[prior+name] = digest(prior+name)}
 for name in ['baseline-arm','baseline-x86','kernel-arm','kernel-x86'] {path := prior+name+'/kernel/bin/vinix'; paths[path] = digest(path)}
 for name in os.ls(prior+'states')! {
  state := prior+'states/'+name; if !os.is_file(state+'/receipt.json') {continue}
  receipt := json2.decode[json2.Any](os.read_file(state+'/receipt.json')!)!.as_map()
  kernel := state+'/kernel/bin/vinix'; if os.is_file(kernel) {paths[kernel] = receipt['kernel_sha256']!.str()}
  rows := receipt['results'] or {continue}
  for entry in rows.as_array() {
   row := entry.as_map(); if row['detail']!.str() != '' {continue}
   iso := state+'/'+row['name']!.str()+'/test.iso'; expected := row['iso_sha256']!.str(); assert expected.len == 64; paths[iso] = expected
  }
 }
 mut pins := map[string]string{}
 for target,expected in paths {
  assert os.inode(target).typ == .regular && digest(target) == expected
  temporary := area+'compressed-prior.tmp'; assert !os.exists(temporary)
  command('/usr/bin/ditto',['--hfsCompression','--noclone',target,temporary])
  assert command('/usr/bin/stat',['-f','%Sf',temporary]).contains('compressed')
  assert digest(temporary) == expected && digest(target) == expected
  os.rename(temporary,target)!; assert digest(target) == expected
  pins[target] = expected; os.write_file(area+'prior-transparent-compression.json',json2.encode(pins,prettify:true)+'\n')!
 }
 println('Preserved '+pins.len.str()+' prior robustquery artifacts with transparent compression; paths and SHA-256 unchanged')
}
