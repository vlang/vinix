import os
import compress.gzip
fn main(){
 p:=os.args[1]
 bytes:=os.read_bytes(p)!
 s:=if p.ends_with('.gz'){gzip.decompress(bytes)!.bytestr()}else{bytes.bytestr()}
 lines:=s.split_into_lines()
 mut stubs:=map[string]int{}
 mut latest:=0
 for i,line in lines{
  if line.contains('STUB:'){stubs[line.all_after('STUB:')]++}
  if line.contains('ANDROID-WS-THREAD') && line.contains('main'){latest=i}
  if line.contains('WS-TRACE211') {println(lines[i..int_min(i+4,lines.len)].join('\n'))}
  if line.contains('ANDROID-WS-FAIL') || line.contains('APK-SUITE-EXIT') || line.contains('Exception:') || line.contains('Error:') {println(line)}
 }
 println('STUBS ${stubs}')
 println('LAST MAIN STACK '+lines[latest..int_min(latest+50,lines.len)].join('\n'))
}
