import os
fn main(){
 b:='build/android-maps/'
 os.write_file(b+'build-framework206.v',os.read_file(b+'build-framework205.v')!.replace('205','206'))!
 for mode in ['baseline','fixed']{
  os.write_file(b+'fixture-drawing206-'+mode+'.json',os.read_file(b+'fixture-locales205-'+mode+'.json')!.replace('locales205','drawing206'))!
 }
 os.write_file(b+'run-drawing206.v',os.read_file(b+'run-locales205.v')!.replace("{'204'} else {'205'}","{'205'} else {'206'}").replace('fixture-locales205-','fixture-drawing206-'))!
 os.write_file(b+'attempt206.json',os.read_file(b+'attempt205.json')!.replace('attempt205','attempt206'))!
 os.write_file(b+'run206.v',os.read_file(b+'run205.v')!.replace('205','206'))!
 os.write_file(b+'interact206.v',os.read_file(b+'interact205.v')!.replace('205','206'))!
 os.write_file(b+'stage-aux206.v',os.read_file(b+'stage-aux205.v')!.replace('attempt205','attempt206'))!
}
