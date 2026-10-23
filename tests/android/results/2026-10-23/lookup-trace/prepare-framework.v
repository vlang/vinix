import os
fn main() {
 b := 'build/android-maps/'
 out := b+'framework237-lookup'
 assert !os.exists(out)
 os.mkdir_all(out+'/sources/androidtools')!
 for path in os.walk_ext(b+'framework236-texture/sources/androidtools','.v') {
  os.cp(path,out+'/sources/androidtools/'+os.base(path))!
 }
 startup := out+'/sources/androidtools/framework_startup.v'
 old := os.read_file(startup)!
 anchor := ' framework_texture_transforms(smali)!\n'
 assert old.count(anchor)==1
 os.write_file(startup,old.replace_once(anchor,anchor+' framework_lookup_trace(smali)!\n'))!
 os.cp('tests/native-android-tools/androidtools/framework_lookup_trace.v',out+'/sources/androidtools/framework_lookup_trace.v')!
 for pair in [['build-framework236-texture','build-framework237-lookup'],['snapshot-framework236','snapshot-framework237']] {
  source := os.read_file(b+pair[0]+'.v')!.replace('framework236-texture','framework237-lookup').replace('FRAMEWORK236-TEXTURE','FRAMEWORK237-LOOKUP').replace('FRAMEWORK236','FRAMEWORK237')
  os.write_file(b+pair[1]+'.v',source)!
 }
 println('FRAMEWORK237 immutable236 plus lookup gate only')
}
