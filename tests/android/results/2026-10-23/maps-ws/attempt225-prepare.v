import os

fn main() {
 b := 'build/android-maps/'
 os.write_file(b+'build-native225.v',os.read_file(b+'build-native224.v')!.replace('224','225').replace("'graphics.v','glutils.v'", "'graphics.v','glutils.v','ndk_surfaces.v'"))!
 os.write_file(b+'attempt225.json',os.read_file(b+'attempt223.json')!.replace('attempt223','attempt225'))!
 os.write_file(b+'interact225.v',os.read_file(b+'interact223.v')!.replace('attempt223','attempt225'))!
 os.write_file(b+'run225.v',os.read_file(b+'run223.v')!
  .replace('attempt223','attempt225').replace('interact223','interact225')
  .replace('libnative221.so','libnative225.so'))!
}
