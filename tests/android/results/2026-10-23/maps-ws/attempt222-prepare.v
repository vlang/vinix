import os

fn main() {
 b := 'build/android-maps/'
 os.write_file(b+'attempt222.json',os.read_file(b+'attempt221.json')!
  .replace('attempt221','attempt222').replace('"startup_seconds": 150','"startup_seconds": 180'))!
 mut interaction := os.read_file(b+'interact221.v')!.replace('attempt221','attempt222')
 interaction = interaction.replace("input(path,['click','556','134'],'10')", "input(path,['click','556','134'],'0.15')\n time.sleep(10*time.second)")
 os.write_file(b+'interact222.v',interaction)!
 os.write_file(b+'run222.v',os.read_file(b+'run221.v')!
  .replace('framework221-content-capture','framework222-autofill')
  .replace("assert sha256.sum(jar).hex() == 'b68a2228bf00dd24fd01a7da0bc9a66f2026564df4a3f515e15b22cd2b91c75f'", "println('FRAMEWORK222 '+sha256.sum(jar).hex())")
  .replace('attempt221','attempt222').replace('interact221','interact222')
  .replace('assert runner.code == 0','println(\'INTERACTION-EXIT \'+input.code.str())\n assert runner.code == 0'))!
}
