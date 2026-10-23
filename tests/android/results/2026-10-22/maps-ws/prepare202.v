import os
fn main(){
 b:='build/android-maps/'
 for phase in ['baseline','fixed']{os.write_file(b+'fixture-order202-'+phase+'.json',os.read_file(b+'fixture-order201-'+phase+'.json')!.replace('order201','order202'))!}
 os.write_file(b+'run-order202.v',os.read_file(b+'run-order201.v')!.replace('fixture-order201','fixture-order202'))!
}
