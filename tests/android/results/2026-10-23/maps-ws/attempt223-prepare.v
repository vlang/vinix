import os

fn main() {
 b := 'build/android-maps/'
 os.write_file(b+'attempt223.json', os.read_file(b+'attempt222.json')!.replace('attempt222', 'attempt223'))!
 os.write_file(b+'interact223.v', os.read_file(b+'interact222.v')!.replace('attempt222', 'attempt223'))!
 os.write_file(b+'run223.v', os.read_file(b+'run222.v')!
  .replace('framework222-autofill', 'framework223-autofill')
  .replace("println('FRAMEWORK222", "assert sha256.sum(jar).hex() == 'ab40d4f8a284c5db5dc819dfa439890ba3805b18a08adbc7c2ed6ccbbc8046a6'\n println('FRAMEWORK222")
  .replace('FRAMEWORK222', 'FRAMEWORK223')
  .replace('attempt222', 'attempt223').replace('interact222', 'interact223'))!
}
