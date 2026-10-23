import os
import crypto.sha256

fn main() {
 b := 'build/android-maps/'
 out := b + 'framework243-popup-menus'
 assert !os.exists(out)
 assert sha256.sum(os.read_bytes(b + 'framework242-canvas-save/api-impl.jar')!).hex() == '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74'
 os.mkdir_all(out + '/sources/androidtools')!
 for path in os.walk_ext(b + 'framework242-canvas-save/sources/androidtools', '.v') {
  os.cp(path, out + '/sources/androidtools/' + os.base(path))!
 }
 for file in ['framework_classes.v', 'framework_popup_menus.v'] {
  os.cp('tests/native-android-tools/androidtools/' + file, out + '/sources/androidtools/' + file)!
 }
 for name in ['build-framework242-canvas-save', 'snapshot-framework242'] {
  new := name.replace('242-canvas-save', '243-popup-menus').replace('242', '243')
  os.write_file(b + new + '.v', os.read_file(b + name + '.v')!.replace('242-canvas-save', '243-popup-menus').replace('242', '243').replace('FRAMEWORK243-INSETS', 'FRAMEWORK243-POPUP-MENUS'))!
 }
 println('FRAMEWORK243 frozen242 plus PopupMenu WS implementation')
}
