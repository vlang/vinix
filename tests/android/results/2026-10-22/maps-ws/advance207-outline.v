import os
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'fixture-render207-fixed5.json',os.read_file(b+'fixture-render207-fixed4.json')!.replace('fixture-render207-fixed4','fixture-render207-fixed5'))!
 os.write_file(b+'run-render207-fixed5.v',os.read_file(b+'run-render207-fixed4.v')!.replace("'fixed4'","'fixed5'"))!
}
