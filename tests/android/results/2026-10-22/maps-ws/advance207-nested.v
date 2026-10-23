import os
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'fixture-render207-baseline3.json',os.read_file(b+'fixture-render207-baseline2.json')!.replace('fixture-render207-baseline2','fixture-render207-baseline3').replace('render207-final-apk','render207-final2-apk'))!
 os.write_file(b+'fixture-render207-fixed6.json',os.read_file(b+'fixture-render207-fixed5.json')!.replace('fixture-render207-fixed5','fixture-render207-fixed6').replace('render207-final-apk','render207-final2-apk'))!
 os.write_file(b+'run-render207-final2.v',os.read_file(b+'run-render207-final.v')!.replace("'baseline2'","'baseline3'").replace("'fixed3'","'fixed6'"))!
}
