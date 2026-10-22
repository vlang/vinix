import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
 target := area + '/frozen-perf-drag'
 if os.args.len > 1 && os.args[1] == 'pin' {
  mut paths := os.walk_ext(target, '.v')
  paths << os.walk_ext(target, '.h')
  paths << target + '/perf-init.sh'
  paths << target + '/measure.c'
  paths << area + '/desktop-retention-drag'
  mut pins := []string{}
  for path in paths { pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path }
  pins.sort()
  os.write_file(area + '/perf-drag-inputs.sha256', pins.join('\n') + '\n')!
  return
 }
 assert !os.exists(target)
 os.cp_all(area + '/frozen-perf-compat', target, false)!
 mut driver := os.read_file(target + '/desktop-retention-compat.v')!
 driver = driver.replace('/frozen-perf-compat', '/frozen-perf-drag').replace('/perf-compat-', '/perf-drag-')
 driver = driver.replace("else {'idle,apps,drag'}", "else {'drag'}")
 driver = driver.replace("'--rounds=1'", "'--shots=' + area + '/perf-drag-shots', '--rounds=1'")
 os.write_file(target + '/desktop-retention-drag.v', driver)!
 mut drive := os.read_file(target + '/perfrunner/drive.v')!
 needle := "\tif drive.len == 2 {\n"
 assert drive.count(needle) == 1
 drive = drive.replace(needle, needle + "\t\tif directory := session.shots {\n\t\t\tos.mkdir_all(directory)!\n\t\t\tabsolute := hosttest.module_resolve(directory)!\n\t\t\tsession.pointer.command('screendump', { 'filename': json2.Any(absolute + '/before-drag.ppm') })!\n\t\t}\n")
 os.write_file(target + '/perfrunner/drive.v', drive)!
 println('Fresh drag-only frozen driver with before/after screenshots prepared')
}
