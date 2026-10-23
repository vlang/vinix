import os

fn main() {
 b := 'build/android-maps/'
 os.write_file(b+'attempt221.json',os.read_file(b+'attempt220.json')!.replace('attempt220','attempt221'))!
 mut interaction := os.read_file(b+'interact220.v')!.replace('attempt220','attempt221')
 interaction = interaction.replace('import json2\nimport qmpclient\n','')
 start := interaction.index('fn doubletap(') or { panic('missing helper') }
 end := interaction.index('fn main()') or { panic('missing main') }
 interaction = interaction[..start]+interaction[end..]
 os.write_file(b+'interact221.v',interaction)!
 os.write_file(b+'run221.v',os.read_file(b+'run220.v')!
  .replace('framework217-observer2','framework221-content-capture')
  .replace('acd7c4ca1ab2447f528879b2ecc8533d38129627f50e867cc8a586b557978593','b68a2228bf00dd24fd01a7da0bc9a66f2026564df4a3f515e15b22cd2b91c75f')
  .replace('libnative220.so','libnative221.so')
  .replace('attempt220','attempt221').replace('interact220','interact221'))!
}
