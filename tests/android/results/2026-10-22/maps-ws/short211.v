import os
fn main(){
 p:='build/android-maps/interact211.v'
 s:=os.read_file(p)!
 at:=s.index(" input(path,['drag'") or {panic('end')}
 os.write_file(p,s[..at]+" time.sleep(20*time.second)\n capture(path,'skip-later')\n}\n")!
}
