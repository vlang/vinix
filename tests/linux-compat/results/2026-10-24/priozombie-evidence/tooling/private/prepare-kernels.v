import os
const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const old = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
fn main() {
 mut setup := os.read_file(old + '/setup-kernels.v')!.replace(old, area).replace('ad2c4322b', '941c2ac85')
 setup = setup.replace("names := ['kernel/proc/nice.v', 'kernel/syscall/table/linux_common.v']", "names := ['kernel/proc/nice.v', 'kernel/proc/proc.v', 'kernel/userland/exit.v']")
 setup = setup.replace('names[0], names[1]', 'names[0], names[1], names[2]').replace('group and user priority setters', 'retain zombie priority').replace('priority setter candidate', 'zombie priority candidate')
 os.write_file(area + '/setup-kernels.v', setup)!
}
