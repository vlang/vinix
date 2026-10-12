// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

import androidrun
import androidhost as ah
import cachecli
import os
import sourcecommand
import strconv
import time

pub struct GameState {
pub mut:
 transcript string
 menu u64
 started u64
 world u64
 loading bool
 passed bool
 fps []f64
}

pub fn guest_environment(options Options, archive string, socket string) map[string]string {
 mut environment := os.environ()
 for key, value in {
  'VINIX_KERNEL_DIR':options.kernel
  'VINIX_INITRAMFS':archive
  'VINIX_INITRAMFS_COMPRESSED':'0'
  'VINIX_QEMU_ROOT_DISK':'0'
  'VINIX_VENUS_STAGING':options.venus_runtime
  'VINIX_BOOT_DISK':path(options.work,'boot.img')
  'VINIX_EFIVARS':path(options.work,'efivars.fd')
  'VINIX_BOOT_DISK_SIZE_MB':'2048'
  'VINIX_QEMU_PACKAGE_STORE':path(options.work,'packages.tar')
  'VINIX_QEMU_PACKAGE_PERSIST':'0'
  'VINIX_QEMU_HOST_SOURCE':'0'
  'VINIX_QEMU_AUDIO':'off'
  'VINIX_QEMU_SMP':options.cpus.str()
  'VINIX_KEEP_TEMP_BOOT_DISK':'1'
  'VINIX_QEMU_EXTRA':'-qmp unix:${socket},server=on,wait=off -d guest_errors -D ${options.work}/qemu-errors.log'
 } { environment[key] = value }
 firmware := path(options.repo,'boot-image/edk2-aarch64-code-2048x1536.fd')
 if os.exists(firmware) { environment['VINIX_QEMU_RESOLUTION'] = '2048x1536x32'; environment['VINIX_OVMF_CODE'] = firmware }
 return environment
}

pub fn guest_command(options Options) []string {
 return [path(options.repo,'scripts/run-aarch64.sh'),'--no-build','--no-persist',if options.venus { '--mem=12288' } else { '--mem=8192' },if options.venus { '--venus' } else { '--serial' }]
}

// Match complete original overlay rows only. Include the old last 100 bytes so
// a split line is observed once; skip rows whose newline was already consumed.
pub fn fps_samples(previous string, chunk string) ![]f64 {
 tail := if previous.len > 100 { previous[previous.len - 100..] } else { previous }
 combined := tail + chunk
 mut result := []f64{}; mut position := 0
 for line in combined.split('\n') {
  end := position + line.len + 1
  if end <= combined.len && end > tail.len && line.starts_with('0, 0, ') {
   fields := line[6..].trim_right('\r').split(', ')
   if fields.len == 2 && fields[0].len > 0 && fields[0].bytes().all(it.is_digit() || it == `.`) && fields[1].len > 0 && fields[1].bytes().all(it.is_digit()) {
    result << strconv.atof64(fields[0])!
   }
  }
  position = end
 }
 return result
}

pub fn (mut state GameState) ingest(chunk string, now u64, options Options) ! {
 if options.venus && state.world != 0 && now - state.world >= u64(options.warmup) * time.second { state.fps << fps_samples(state.transcript,chunk)! }
 state.transcript += chunk
}

pub fn (state &GameState) failed() bool {
 for marker in ['---crashlog(','KERNEL PANIC','OPENGOTHIC-GONE','VENUS-ABI-FAIL','VENUS-SMOKE-FAIL'] { if state.transcript.contains(marker) { return true } }
 return false
}

pub fn (mut state GameState) advance(now u64, options Options) string {
 if state.failed() { return 'failure' }
 if state.menu == 0 {
  if state.transcript.contains('Shader compilation took') { state.menu = now; println('The engine reached its menu') }
 } else if state.started == 0 {
  if now - state.menu > 10 * time.second { return 'start' }
 } else if state.world == 0 {
  if !state.loading && state.transcript.contains('Parsing object [MeshAndBsp') { state.loading = true; println('New game: loading the world') }
  if state.transcript.contains('unable to locate video file') { state.world = now; println('The world is running') }
 } else if now - state.world > u64(options.warmup + options.seconds) * time.second { return 'capture' }
 return ''
}

pub fn (state &GameState) reached() string {
 return if state.world != 0 { 'the world' } else if state.loading { 'the loading screen' } else if state.menu != 0 { 'the menu' } else { 'nothing' }
}

pub fn performance(options Options, root string, kernel_hash string, screenshot string, state GameState) ! {
 for marker in ['VINIX_VENUS_FENCE_FD_PASS','VINIX_VENUS_GPU_FILL_PASS','VENUS GPU: Virtio-GPU Venus'] { if !state.transcript.contains(marker) { return error('Native Venus GPU smoke failed') } }
 if state.fps.len < options.seconds / 2 { return error('Too few gameplay FPS samples') }
 if state.fps.len == 0 { return error('no median for empty FPS samples') }
 mut sorted := state.fps.clone(); sorted.sort()
 middle := sorted.len / 2
 median := if sorted.len % 2 == 0 { (sorted[middle - 1] + sorted[middle]) / 2 } else { sorted[middle] }
 record := ah.Value({
  'samples':ah.Value(sorted.len)
  'median_fps':ah.Value(ah.Number{median.str()})
  'min_fps':ah.Value(ah.Number{sorted[0].str()})
  'max_fps':ah.Value(ah.Number{sorted.last().str()})
  'seconds':ah.Value(options.seconds)
  'warmup_seconds':ah.Value(options.warmup)
  'cpus':ah.Value(options.cpus)
  'kernel_sha256':ah.Value(kernel_hash)
  'engine_sha256':ah.Value(digest(path(root,'opt/opengothic/Gothic2Notr'))!)
  'venus_sha256':ah.Value(digest(path(root,'opt/venus/lib/libvulkan_virtio.so'))!)
  'screenshot':ah.Value(screenshot)
 })
 os.write_file(path(options.work,'performance.json'),androidrun.dump_json(record,2) + '\n')!
 println('Native Venus gameplay: median ${median:.2f} FPS (${sorted.len} samples)')
 if median < options.min_fps { return error('Gameplay median below required ${options.min_fps} FPS; inspect ${options.work}/performance.json') }
}

pub fn stop(mut child sourcecommand.PtyChild) ! {
 child.poll() or { return }
 child.write([u8(1),`x`]) or {}
 // Shutdown proceeds even after interruption. The leader remains reserved.
 time.sleep(time.second)
 child.signal(C.SIGTERM) or {}
 child.settle(5) or {}
 child.close()!
}

pub fn run_guest(options Options, root string) !string {
 kernel := digest(path(options.kernel,'bin/vinix'))!
 archive_path := path(options.work,'initramfs.tar'); archive(root,archive_path)!
 socket := path(options.work,'qmp.sock'); remove(socket)!
 println('Booting Vinix with Gothic II open'); flush_stdout()
 mut child := sourcecommand.spawn_pty(guest_command(options),guest_environment(options,archive_path,socket),options.repo)!
 defer { stop(mut child) or {} }
 mut log := os.create(path(options.work,'vinix.log'))!; defer { log.close() }
 screenshot := path(options.work,'gothic.png')
 mut state := GameState{}; mut buffer := []u8{len:65536}
 deadline := time.sys_mono_now() + u64(options.timeout) * time.second
 for time.sys_mono_now() < deadline {
  cachecli.checkpoint()!
  count := child.read(mut buffer,100)!
  if count == 0 { break }
  if count > 0 { unsafe { log.write_full_buffer(buffer.data,usize(count))! }; log.flush(); state.ingest(buffer[..count].bytestr(),time.sys_mono_now(),options)! }
  now := time.sys_mono_now()
  action := state.advance(now,options)
  if action == 'failure' { break }
  if action == 'start' { press(socket,'ret',0.12)!; state.started = now }
  if action == 'capture' { press(socket,'up',1)!; androidrun.screenshot(socket,screenshot)!; state.passed = true; break }
 }
 stop(mut child)!
 if !state.passed { return error('OpenGothic failed after reaching ${state.reached()}; inspect ${options.work}/vinix.log') }
 if options.venus { performance(options,root,kernel,screenshot,state)! }
 return screenshot
}
