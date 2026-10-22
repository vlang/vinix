import crypto.sha256
import json2
import os

fn clone(source string, output string) ! {
 os.mkdir(output)!
 for name in os.ls(source)! {
  from := source+'/'+name
  to := output+'/'+name
  if os.is_link(from) { os.symlink(os.readlink(from)!,to)! }
  else if os.is_dir(from) { clone(from,to)! }
  else { os.cp(from,to)! }
 }
}
fn main() {
 if os.args.len != 4 { panic('SOURCE LOADER OUTPUT') }
 clone(os.args[1],os.args[3])!
 os.mkdir_all(os.args[3]+'/lib')!
 os.cp(os.args[2],os.args[3]+'/lib/ld-musl-x86_64.so.1')!
 os.symlink('ld-musl-x86_64.so.1',os.args[3]+'/lib/libc.musl-x86_64.so.1')!
 os.write_file(os.args[3]+'/.normal-init-input.json',json2.encode({
  'source-rootfs':os.args[1], 'musl-loader':os.args[2],
  'musl-loader-sha256':sha256.hexhash(os.read_file(os.args[2])!),
  'preparation-source-sha256':sha256.hexhash(os.read_file(@FILE)!)
 }))!
}
