import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 previous := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 wrapper := os.read_file(previous + '/arm-cc.v')!.replace("assert destination.starts_with(area + '/states/')", "assert destination.starts_with('" + area + "/states/')")
 os.write_file(area + '/arm-cc.v', wrapper)!
 mut controller := os.read_file(area + '/maintained-native.v')!.replace('maintained-first-', 'maintained-second-').replace('kernel-first-', 'kernel-second-')
 controller = controller.replace("kernel + '/bin/vinix', previous + '/generate-module'", "kernel + '/bin/vinix', previous + '/generate-module', area + '/arm-cc', area + '/arm-cc.v', os.find_abs_path_of_executable('clang')!")
 controller = controller.replace('envhelper.configure()', "envhelper.configure()\n    os.setenv('CC', area + '/arm-cc', true)")
 os.write_file(area + '/maintained-second.v', controller)!
}
