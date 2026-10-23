import os
import crypto.sha256
fn main() {
 b:='build/android-maps/'
 baseline:=os.read_file(b+'framework236-texture/smali/android/view/ViewGroup.smali')!
 mut fixed:=os.read_file(b+'framework237-lookup/smali/android/view/ViewGroup.smali')!
 for n in 0..2 {
  label:=':vinix_lookup_trace_skip_'+n.str()
  gate:='    sget-boolean v0, Landroid/atl/VinixViewLookupTrace;->enabled:Z\n    if-eqz v0, '+label+'\n'
  assert fixed.count(gate)==1
  assert fixed.count('    '+label+'\n\n')==1
  fixed=fixed.replace_once(gate,'').replace_once('    '+label+'\n\n','')
 }
 assert fixed==baseline, 'search or other ViewGroup bytes changed'
 println('LOOKUP237 INVARIANT PASS: stripping only two gates restores entire ViewGroup byte-for-byte '+sha256.sum(fixed.bytes()).hex())
}
