import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 header := '/Users/alex/.cache/vinix-linux-compat/execfd-20261015/sdk/include'
 wrapper := os.read_file(area + '/arm-cc.v')!
 os.write_file(area + '/arm-cc-third.v', wrapper.replace("mut args := ['--gcc-install-dir='", "mut args := ['-idirafter', '${header}', '--gcc-install-dir='"))!
 controller := os.read_file(area + '/maintained-second.v')!
 os.write_file(area + '/maintained-third.v', controller.replace("'/states/maintained-second-' + suffix", "'/states/m3' + suffix")
 .replace("area + '/arm-cc'", "area + '/arm-cc-third'")
 .replace("area + '/arm-cc.v'", "area + '/arm-cc-third.v'")
 .replace("    envhelper.configure()", "    for directory in ['linux', 'asm', 'asm-generic'] {\n        for path in os.walk_ext('${header}/' + directory, '') { if os.is_file(path) { inputs[path] = digest(path) } }\n    }\n    envhelper.configure()"))!
}
