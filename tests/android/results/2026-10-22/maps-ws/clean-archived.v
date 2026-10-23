import os
fn main() {
 base:='build/android-maps/'
 mut total:=0
 for name in os.ls(base)! {
  if !name.starts_with('attempt') || !os.is_dir(base+name) || !os.is_file(base+name+'/runtime-sha256.json') { continue }
  path:=base+name+'/companion-native'
  if os.is_dir(path) { os.rmdir_all(path)!; total++ }
 }
 println('Removed reproducible companion-library extraction caches from '+total.str()+' archived runs; signed source APKs and retained evidence remain available')
}
