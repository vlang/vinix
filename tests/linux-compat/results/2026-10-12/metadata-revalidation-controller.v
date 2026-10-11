import crypto.sha256
import json2
import os

fn run(argv []string) ! {
 mut child := os.new_process(argv[0])
 child.set_args(argv[1..])
 child.set_redirect_stdio()
 child.run()
 output := child.stdout_slurp() + child.stderr_slurp()
 child.wait()
 code := child.code
 child.close()
 println(output)
 if code != 0 { return error('audit failed: ' + argv.str()) }
}

fn main() {
 root := '/Users/alex/code/vinix'
 work := '/Volumes/VinixLinuxCompatNext1011/tmp/metadata-checked-audit'
 os.mkdir_all(work)!
 inventory := json2.decode[json2.Any](os.read_file(root + '/docs/linux-syscall-coverage.json')!)!.as_map()
 for path, hash in inventory['inputs']!.as_map() {
  if sha256.sum(os.read_bytes(root + '/' + path)!).hex() != hash.str() { panic('inventory changed: ' + path) }
  if path.starts_with('kernel/') {
   for arch in ['arm', 'x86'] {
    if sha256.sum(os.read_bytes('/Volumes/VinixLinuxCompatContinue1011/' + arch + '/' + path)!).hex() != hash.str() { panic('build tree differs: ' + arch + '/' + path) }
   }
  }
 }
 sources := ['/tmp/vinix-linux-posix-export-abi.v',
  '/tmp/vinix-linux-posix-export-metadata-runtimes.v',
  '/tmp/vinix-linux-posix-export-metadata-firefox.v',
  '/tmp/vinix-metadata-export-native.v', '/tmp/vinix-metadata-export-memlock.v']
 for index, original in sources {
  out := work + '/' + index.str() + '/'
  os.mkdir_all(out)!
  mut source := os.read_file(original)!
  old_out := if index == 0 { "out := root + 'tests/linux-compat/results/' + date + '/'" }
   else if index in [1, 2] { "out := root + '/tests/linux-compat/results/2026-10-12/'" }
   else { "out := root + 'tests/linux-compat/results/2026-10-12/'" }
  if source.count(old_out) != 1 { panic('unexpected audit source') }
  source = source.replace(old_out, "out := '" + out + "'")
  source = source.replace('@FILE', "'" + original + "'")
  file := work + '/audit-' + index.str() + '.v'
  executable := work + '/audit-' + index.str()
  os.write_file(file, source)!
  // C optimization preserves V assertions; -prod erases them in V3.
  run(['v', '-nocache', '-cflags', '-O2', '-o', executable, file])!
  args := if index == 0 { ['mapstorage', 'metadata-storage', 'metadata-before3-', 'metadata-after2-', '18', 'LINUX MAPSTORAGE FAIL: fixed metadata overreservation', 'LINUX MAPSTORAGE: PASS'] }
   else if index == 3 { ['paging'] } else { []string{} }
  run([executable, ...args])!
  for name in os.ls(out)! {
   a := sha256.sum(os.read_bytes(out + name)!)
   b := sha256.sum(os.read_bytes(root + '/tests/linux-compat/results/2026-10-12/' + name)!)
   if a != b { panic('published receipt differs: ' + name) }
  }
  println('Audit ' + index.str() + ': assertions enabled; published output byte-identical')
 }
 println('All mapping metadata receipts and kernel source fingerprints revalidated')
}
