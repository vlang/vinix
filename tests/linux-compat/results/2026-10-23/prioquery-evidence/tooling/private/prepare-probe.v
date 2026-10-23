import os

const area = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'
const root = '/Users/alex/code/vinix'

fn main() {
 os.mkdir_all(area + '/states')!
 os.mkdir_all(area + '/prioqueryreferenceinit')!
 os.write_file(area + '/prioqueryreferenceinit/core.v', os.read_file(root + '/tests/linux-compat/semmetareferenceinit/core.v')!.replace('semmeta', 'prioquery').replace('SEMMETA', 'PRIOQUERY'))!
 os.write_file(area + '/reference.v', os.read_file(root + '/tests/linux-compat/semmeta-reference.v')!.replace('semmeta', 'prioquery').replace('SEMMETA', 'PRIOQUERY').replace('28713', '6199').replace('Semaphore', 'Priority query'))!
 os.write_file(area + '/native.v', os.read_file(old + '/native.v')!.replace('SEMMETA', 'PRIOQUERY').replace('28713', '6199').replace('semaphore ABI', 'priority query ABI'))!
 os.write_file(area + '/compile.v', os.read_file(old + '/compile.v')!.replace(old, area).replace('semmeta', 'prioquery').replace('semaphore', 'priority query')
  .replace("os.cp('/Users/alex/code/vinix/tests/linux-compat/prioqueryfixture/' + name, fixture + '/' + name)!", "os.cp(area + '/fixture/' + name, fixture + '/' + name)!"))!
 println('Prepared private priority query controllers')
}
