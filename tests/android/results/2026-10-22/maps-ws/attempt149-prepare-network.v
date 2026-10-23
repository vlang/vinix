import os
import json2

fn main() {
    assert os.is_file('build/android-maps/attempt148/results.json')
    source := os.read_file('build/android-maps/suite-low-disk.v')!
    os.write_file('build/android-maps/suite-ipv4-149.v', source.replace("'user,id=net0'", "'user,id=net0,ipv6=off'"))!
    result := os.exec(['/Users/alex/code/v/v', '-nocache', '-cc', 'cc', '-path', '@vlib|build-support/android', '-o', 'build/android-maps/suite-ipv4-149', 'build/android-maps/suite-ipv4-149.v'])
    assert result.exit_code == 0, result.output
    os.cp('build/android-maps/fields148-launcher.v', 'build/android-maps/fields149-launcher.v')!
    mut config := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/attempt148.json')!)!
    config['output'] = 'build/android-maps/attempt149'
    os.write_file('build/android-maps/attempt149.json', json2.encode(config, prettify:true))!
}
