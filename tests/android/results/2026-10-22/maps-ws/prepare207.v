import os
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'build-framework207.v',os.read_file(b+'build-framework206.v')!.replace('206','207'))!
 for mode in ['baseline','fixed']{
  os.write_file(b+'fixture-render207-'+mode+'.json',os.read_file(b+'fixture-drawing206-'+mode+'.json')!.replace('drawing206','render207'))!
 }
 os.write_file(b+'run-render207.v',os.read_file(b+'run-drawing206.v')!.replace("{'205'} else {'206'}","{'206'} else {'207'}").replace('fixture-drawing206-','fixture-render207-'))!
 os.write_file(b+'attempt207.json',os.read_file(b+'attempt206.json')!.replace('attempt206','attempt207'))!
 for helper in ['run','interact']{os.write_file(b+helper+'207.v',os.read_file(b+helper+'206.v')!.replace('206','207'))!}
 os.write_file(b+'stage-aux207.v',os.read_file(b+'stage-aux206.v')!.replace('attempt206','attempt207'))!
}
