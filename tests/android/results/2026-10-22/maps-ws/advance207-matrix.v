import os
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'fixture-render207-fixed4.json',os.read_file(b+'fixture-render207-fixed3.json')!.replace('fixture-render207-fixed3','fixture-render207-fixed4'))!
 os.write_file(b+'run-render207-fixed4.v',os.read_file(b+'run-render207-final.v')!.replace("'fixed3'","'fixed4'"))!
}
