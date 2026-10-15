import json2
import os
#include <CommonCrypto/CommonDigest.h>
fn C.CC_SHA256(voidptr,u32,&u8) &u8
const area = '/Users/alex/.cache/vinix-linux-compat/waitstatus-20261015/'
fn digest(path string) string {
 data := os.read_bytes(path) or {panic(err)}; assert u64(data.len) < u64(0x100000000)
 mut result := [32]u8{}; unsafe {C.CC_SHA256(data.data,u32(data.len),&result[0]); data.free()}; return result[..].hex()
}
fn command(program string,args []string) string {
 mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); status := p.code; p.close(); assert status == if args == ['--help'] {1} else {0},output; return output
}
fn main() {
 assert !os.exists(area+'transparent-compression.json')
 os.write_file(area+'ditto-help.txt',command('/usr/bin/ditto',['--help']))!
 mut compressed := map[string]string{}
 for name in ['waitabi','waitempty','waituid','waitevent','waitusage','waitconsume'] {
  prior := '/Users/alex/.cache/vinix-linux-compat/'+name+'-20261015/states/'
  for entry in os.ls(prior)! {
   state := prior+entry; if !os.is_dir(state) || !os.is_file(state+'/receipt.json') {continue}
   receipt := json2.decode[json2.Any](os.read_file(state+'/receipt.json')!)!.as_map()
   results := receipt['results'] or {continue}
   for row in results.as_array() {
    result := row.as_map(); expected := result['iso_sha256']!.str(); if expected.len != 64 || result['detail']!.str() != '' {continue}
    fixture := result['name']!.str(); assert fixture != '' && fixture.bytes().all(it >= `a` && it <= `z`)
    target := state+'/'+fixture+'/test.iso'; assert os.inode(target).typ == .regular && digest(target) == expected
    temporary := area+'compressed.tmp'; assert !os.exists(temporary)
    command('/usr/bin/ditto',['--hfsCompression','--noclone',target,temporary])
    assert command('/usr/bin/stat',['-f','%Sf',temporary]).contains('compressed')
    assert digest(temporary) == expected && digest(target) == expected
    os.rename(temporary,target)!; assert digest(target) == expected
    compressed[target] = expected
    os.write_file(area+'transparent-compression.json',json2.encode(compressed,prettify:true)+'\n')!
   }
  }
 }
 println('Verified transparent compression of '+compressed.len.str()+' completed ISO images; paths and SHA-256 unchanged')
}
