import os
fn main(){
 b:='build/android-maps/'
 for phase in ['baseline','fixed']{os.write_file(b+'fixture-order203-'+phase+'.json',os.read_file(b+'fixture-order202-'+phase+'.json')!.replace('order202','order203'))!}
 os.write_file(b+'run-order203.v',os.read_file(b+'run-order202.v')!.replace('fixture-order202','fixture-order203'))!
}
