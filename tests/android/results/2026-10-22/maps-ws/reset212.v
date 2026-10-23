import os
import json2
fn main() {
 base:='build/android-maps/'
 path:=base+'attempt212'
 os.cp(path+'/results.json',base+'attempt212-stage-failure.json')!
 note:={
  'scope':json2.Any('Host staging failures before QEMU boot; no application execution or functional result'),
  'initial':json2.Any('Host disk exhausted; harness could not write results.json'),
  'retry':json2.Any('Not a directory while reusing partially staged module; full failure record in attempt212-stage-failure.json'),
  'resolution':json2.Any('Reclaimed archived companion extraction caches and removed incomplete attempt212 staging before a fresh retry')
 }
 os.write_file(base+'attempt212-stage-failures.json',json2.encode(note,prettify:true)+'\n')!
 os.rmdir_all(path)!
}
