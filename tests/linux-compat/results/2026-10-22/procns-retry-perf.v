import os
fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 source := os.read_file(area + '/desktop-retention.v')!
 assert source.count("'/perf-'") == 5
 updated := source.replace("'/perf-'", "'/perf-small-'").replace("'--rounds=1'", "'--initramfs=' + root + '/logs/m1-gpu-deploy-20261018/build-support/init-aarch64/initramfs-desktop.tar', '--rounds=1'")
 os.write_file(area + '/desktop-retention-small.v', updated)!
 os.write_file(area + '/frozen-perf/desktop-retention-small.v', updated)!
}
