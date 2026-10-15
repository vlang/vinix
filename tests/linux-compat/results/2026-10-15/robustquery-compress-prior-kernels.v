import json2
import os
#include <CommonCrypto/CommonDigest.h>
fn C.CC_SHA256(voidptr,u32,&u8) &u8
const area = '/Users/alex/.cache/vinix-linux-compat/robustquery-20261015/'
fn digest(path string) string {
 data := os.read_bytes(path) or {panic(err)}; assert u64(data.len) < u64(0x100000000)
 mut result := [32]u8{}; unsafe {C.CC_SHA256(data.data,u32(data.len),&result[0]); data.free()}; return result[..].hex()
}
fn command(program string,args []string) string {
 mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); status := p.code; p.close(); assert status == 0,output; return output
}
fn main() {
 assert !os.exists(area+'prior-kernel-compression.json'); mut pins := map[string]string{}
 for name in ['waitabi','waitempty','waituid','waitevent','waitusage','waitconsume','waitstatus'] {
  prior := '/Users/alex/.cache/vinix-linux-compat/'+name+'-20261015/'
  mut paths := []string{}
  for folder in ['baseline-arm','baseline-x86','kernel-arm','kernel-x86'] {paths << prior+folder+'/kernel/bin/vinix'}
  for entry in os.ls(prior+'states')! {path := prior+'states/'+entry+'/kernel/bin/vinix'; if os.is_file(path) {paths << path}}
  for target in paths {
   assert os.inode(target).typ == .regular; expected := digest(target)
   temporary := area+'compressed-kernel.tmp'; assert !os.exists(temporary)
   command('/usr/bin/ditto',['--hfsCompression','--noclone',target,temporary])
   assert command('/usr/bin/stat',['-f','%Sf',temporary]).contains('compressed')
   assert digest(temporary) == expected && digest(target) == expected
   os.rename(temporary,target)!; assert digest(target) == expected
   pins[target] = expected; os.write_file(area+'prior-kernel-compression.json',json2.encode(pins,prettify:true)+'\n')!
  }
 }
 println('Preserved '+pins.len.str()+' retained kernel images with transparent compression; paths and SHA-256 unchanged')
}
