import os

fn main() {
 b := 'build/android-maps/'
 output := b + 'framework238-insets'
 assert !os.exists(output), 'Frozen framework sources already exist'
 os.mkdir_all(output + '/sources/androidtools')!
 for path in os.walk_ext(b + 'framework236-texture/sources/androidtools', '.v') {
  os.cp(path, output + '/sources/androidtools/' + os.base(path))!
 }
 startup := os.read_file(output + '/sources/androidtools/framework_startup.v')!
 assert !startup.contains('framework_window_insets(smali)!')
 os.write_file(output + '/sources/androidtools/framework_startup.v', startup.replace(' framework_texture_transforms(smali)!', ' framework_texture_transforms(smali)!\n framework_window_insets(smali)!'))!
 os.cp('tests/native-android-tools/androidtools/framework_insets.v', output + '/sources/androidtools/framework_insets.v')!
 for kind in ['build-framework236-texture', 'snapshot-framework236'] {
  converted := os.read_file(b + kind + '.v')!
   .replace('framework236-texture', 'framework238-insets')
   .replace('FRAMEWORK236-TEXTURE', 'FRAMEWORK238-INSETS')
   .replace('FRAMEWORK236', 'FRAMEWORK238')
  name := if kind.starts_with('build-') { 'build-framework238-insets' } else { 'snapshot-framework238' }
  os.write_file(b + name + '.v', converted)!
 }
 println('FRAMEWORK238 PREPARED immutable236 base plus WindowInsets values and Builder')
}
