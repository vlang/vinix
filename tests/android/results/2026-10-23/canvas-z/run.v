import os

fn main() {
 assert os.args.len == 2 && os.args[1] in ['baseline', 'fixed']
 variant := os.args[1]
 config := 'build/android-maps/canvas227/' + variant + '.json'
 r := os.exec(['build/android-maps/suite159', config])
 os.write_file('build/android-maps/canvas227/' + variant + '-harness.log', r.output)!
 print(r.output)
 exit(r.exit_code)
}
