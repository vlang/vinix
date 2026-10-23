import os
import compress.gzip
fn main() {
 path:=os.args[1]
 data:=os.read_bytes(path)!
 log:=if path.ends_with('.gz'){gzip.decompress(data)!.bytestr()}else{data.bytestr()}
 mut selected:=false
 for raw in log.split_into_lines() {
  line:=raw.trim_space()
  if line.starts_with('ANDROID-WS-OBJECT index=') {
   selected=line.all_after('class=') in os.args[2..]
  }
  if selected && line.starts_with('ANDROID-WS-OBJECT') {println(line)}
 }
}
