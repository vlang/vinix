import json2
import os
const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const old = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
fn main() {
 source := json2.decode[map[string]json2.Any](os.read_file(area + '/prepared-source-inputs.json')!)!
 pins := source['sources']!.as_map()
 mut build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
 build = build.replace('ad2c4322bc23e230f46b3631ffc873a03057c09b', source['base']!.str())
  .replace('4d5c21e0122b7eeee8e235f1154a9c701b5c7c9e', source['commit']!.str())
  .replace('067b32e970372e6e55950480081340fa9d0b2a2a7f25f28dd189401b1495f426', pins['kernel/proc/nice.v']!.str())
  .replace('kernel/proc/nice.v\\nkernel/syscall/table/linux_common.v', 'kernel/proc/nice.v\\nkernel/proc/proc.v\\nkernel/userland/exit.v')
  .replace("'kernel/proc/nice.v', 'kernel/syscall/table/linux_common.v'", "'kernel/proc/nice.v', 'kernel/proc/proc.v', 'kernel/userland/exit.v'")
  .replace("area + '/source/kernel/syscall/table/linux_common.v'", "area + '/source/kernel/proc/proc.v', area + '/source/kernel/userland/exit.v'")
  .replace('/2026-10-23/prioquery-evidence/', '/2026-10-23/priochange-evidence/')
 os.write_file(area + '/build-kernels.v', build)!
}
