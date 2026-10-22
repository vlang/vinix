import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn digest(path string) !string {
 mut f := os.open(path)!
 defer { f.close() }
 mut d := sha256.new()
 mut b := []u8{len: 1024 * 1024}
 mut total := i64(0)
 for {
  n := f.read(mut b) or { break }
  if n == 0 { break }
  total += n
  d.write(b[..n])!
 }
 if total != os.file_size(path) { return error('Incomplete hash read: ' + path) }
 return d.sum([]u8{}).hex()
}

fn main() {
 if os.args.len > 1 && os.args[1] == 'pin' {
  mut pins := []string{}
  for path in os.walk_ext(area + '/frozen-perf-compat', '.v') {
   pins << digest(path)! + '  ' + path
  }
  for path in [area + '/frozen-perf-compat/perf-init.sh', area + '/frozen-perf-compat/measure.c', area + '/desktop-retention-compat'] {
   pins << digest(path)! + '  ' + path
  }
  pins.sort()
  os.write_file(area + '/perf-compat-inputs.sha256', pins.join('\n') + '\n')!
  return
 }
 source := area + '/frozen-perf'
 target := area + '/frozen-perf-compat'
 assert !os.exists(target)
 os.cp_all(source, target, false)!
 mut driver := os.read_file(target + '/desktop-retention-small.v')!
 driver = driver.replace('/frozen-perf', '/frozen-perf-compat')
 driver = driver.replace('/perf-small-', '/perf-compat-')
 os.write_file(target + '/desktop-retention-compat.v', driver)!
 mut init := os.read_file(target + '/perf-init.sh')!
 old_name := "name_hex=$(printf 'Perf User' | od -An -tx1 | tr -d ' \\n')"
 assert init.count(old_name) == 1
 init = init.replace(old_name, 'name_hex=506572662055736572')
 old_install := 'install -m755 "$perf/vinix-desktop-$variant" /usr/bin/vinix-desktop'
 assert init.count(old_install) == 1
 init = init.replace(old_install, 'cp "$perf/vinix-desktop-$variant" /usr/bin/vinix-desktop\n\tchmod 755 /usr/bin/vinix-desktop')
 os.write_file(target + '/perf-init.sh', init)!
 os.chmod(target + '/perf-init.sh', 0o755)!
 println('Private cached-image compatibility fixture prepared: fixed literal user-name hex and cp/chmod desktop install')
}
