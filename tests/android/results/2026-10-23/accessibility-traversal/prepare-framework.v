import os
fn main() {
 b := 'build/android-maps/'
 for name in ['prepare-framework234.v', 'prepare234.v'] {
  source := os.read_file(b + name)!
  target := name.replace('234', '235')
  if name == 'prepare234.v' { continue }
  converted := source.replace('framework234-interpolators', 'framework235-accessibility').replace('build-framework234-interpolators', 'build-framework235-accessibility').replace('snapshot-framework234', 'snapshot-framework235').replace('FRAMEWORK234', 'FRAMEWORK235')
  os.write_file(b + target + '.generated', converted)!
 }
}
