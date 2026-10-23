import os
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'build-framework208.v',os.read_file(b+'build-framework207.v')!.replace('207','208'))!
 for mode in ['baseline','fixed']{
  os.write_file(b+'fixture-layout208-'+mode+'.json',os.read_file(b+'fixture-render207-fixed6.json')!.replace('render207-final2-apk','layout208-apk').replace('fixture-render207-fixed6','fixture-layout208-'+mode))!
 }
 os.write_file(b+'run-layout208.v',os.read_file(b+'run-render207-final2.v')!.replace("{'206'} else {'207'}","{'207'} else {'208'}").replace("'fixture-render207-'+if baseline {'baseline3'} else {'fixed6'}","'fixture-layout208-'+if baseline {'baseline'} else {'fixed'}"))!
 os.write_file(b+'attempt208.json',os.read_file(b+'attempt207.json')!.replace('attempt207','attempt208'))!
 for helper in ['run','interact']{os.write_file(b+helper+'208.v',os.read_file(b+helper+'207.v')!.replace('207','208'))!}
 os.write_file(b+'stage-aux208.v',os.read_file(b+'stage-aux207.v')!.replace('attempt207','attempt208'))!
}
