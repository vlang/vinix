import os
import crypto.sha256
#include <spawn.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>

@[typedef]
struct C.posix_spawn_file_actions_t {}

fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.WTERMSIG(i32) i32
fn C.kill(i32, i32) i32

struct StreamStatuses {
 producer int
 consumer int
}

fn stream_spawn(arguments []string, read_fd int, write_fd int, pipe_fds []int) !i32 {
 if arguments.len == 0 || arguments.any(it.contains('\x00')) { return error('invalid stream command') }
 mut actions := C.posix_spawn_file_actions_t{}
 initialized := C.posix_spawn_file_actions_init(&actions)
 if initialized != 0 { return error('stream spawn actions: ' + os.get_error_msg(initialized)) }
 defer { C.posix_spawn_file_actions_destroy(&actions) }
 for pair in [[read_fd, 0], [write_fd, 1]] {
  if pair[0] < 0 { continue }
  status := C.posix_spawn_file_actions_adddup2(&actions, i32(pair[0]), i32(pair[1]))
  if status != 0 { return error('stream redirect: ' + os.get_error_msg(status)) }
 }
 for descriptor in pipe_fds {
  status := C.posix_spawn_file_actions_addclose(&actions, i32(descriptor))
  if status != 0 { return error('stream close action: ' + os.get_error_msg(status)) }
 }
 mut argv := []&char{cap: arguments.len + 1}
 for argument in arguments { argv << &char(argument.str) }
 argv << &char(unsafe { nil })
 mut environment := []string{}
 for key, value in os.environ() { environment << key + '=' + value }
 mut envp := []&char{cap: environment.len + 1}
 for item in environment { envp << &char(item.str) }
 envp << &char(unsafe { nil })
 mut pid := i32(0)
 status := C.posix_spawnp(&pid, &char(arguments[0].str), &actions, unsafe { nil }, argv.data, envp.data)
 if status != 0 { return error('stream spawn ' + arguments[0] + ': ' + os.get_error_msg(status)) }
 return pid
}

fn stream_wait(pid i32) !int {
 mut status := i32(0)
 for C.waitpid(pid, &status, 0) < 0 {
  if C.errno != C.EINTR { return error('stream wait: ' + os.get_error_msg(C.errno)) }
 }
 return if C.WIFEXITED(status) != 0 { int(C.WEXITSTATUS(status)) } else { 128 + int(C.WTERMSIG(status)) }
}

// Connect the two programs directly. Both statuses are checked: an archive
// producer failure must not be hidden by mcopy successfully copying a prefix.
fn stream_commands(producer []string, consumer []string) !StreamStatuses {
 mut pipe := os.pipe()!
 defer { pipe.close() }
 if pipe.read_fd < 3 || pipe.write_fd < 3 { return error('stream requires open standard descriptors') }
 descriptors := [pipe.read_fd, pipe.write_fd]
 producer_pid := stream_spawn(producer, -1, pipe.write_fd, descriptors)!
 mut producer_reaped := false
 defer {
  if !producer_reaped {
   C.kill(producer_pid, C.SIGKILL)
   stream_wait(producer_pid) or {}
  }
 }
 consumer_pid := stream_spawn(consumer, pipe.read_fd, -1, descriptors)!
 mut consumer_reaped := false
 defer {
  if !consumer_reaped {
   C.kill(consumer_pid, C.SIGKILL)
   stream_wait(consumer_pid) or {}
  }
 }
 pipe.close()
 producer_status := stream_wait(producer_pid)!
 producer_reaped = true
 consumer_status := stream_wait(consumer_pid)!
 consumer_reaped = true
 return StreamStatuses{producer: producer_status, consumer: consumer_status}
}

fn stream_module(module_root string, boot_image string) ! {
 result := stream_commands(['tar', '--format=ustar', '-b', '1', '-cf', '-', '-C', module_root, '.'],
  ['mcopy', '-o', '-i', boot_image, '-', '::/boot/qemu-runtime.tar'])!
 println('MODULE-STREAM producer=' + result.producer.str() + ' consumer=' + result.consumer.str())
 if result.producer != 0 || result.consumer != 0 {
  return error('module stream failed: tar=' + result.producer.str() + ' mcopy=' + result.consumer.str())
 }
}

fn checked(arguments []string) ! {
 result := os.exec(arguments)
 if result.exit_code != 0 { return error(result.output) }
}

fn main() {
 task := 'build/android-maps/stream238/'
 root := task + 'private module with spaces'
 os.mkdir_all(root + '/nested')!
 os.write_file(root + '/marker', 'stream exact byte test\n')!
 mut data := []u8{len: 262277}
 for i in 0 .. data.len { data[i] = u8((i * 137 + i / 251) % 256) }
 os.write_file_array(root + '/nested/payload.bin', data)!
 image := task + 'private-fat.img'
 os.write_file(image, '')!
 os.truncate(image, 16 * 1024 * 1024)!
 defer { os.rm(image) or {} }
 checked(['mformat', '-i', image, '-F', '::'])!
 checked(['mmd', '-i', image, '::/boot'])!
 golden := task + 'expected.tar'
 checked(['tar', '--format=ustar', '-cf', golden, '-C', root, '.'])!
 stream_module(root, image)!
 actual := task + 'actual.tar'
 checked(['mcopy', '-o', '-i', image, '::/boot/qemu-runtime.tar', actual])!
 assert os.read_bytes(golden)! == os.read_bytes(actual)!
 println('STREAM238 exact-byte PASS sha256=' + sha256.sum(os.read_bytes(actual)!).hex())
 // Overwrite a larger archive with a smaller one; mcopy must update size too.
 os.rm(root + '/nested/payload.bin')!
 checked(['tar', '--format=ustar', '-cf', golden, '-C', root, '.'])!
 stream_module(root, image)!
 checked(['mcopy', '-o', '-i', image, '::/boot/qemu-runtime.tar', actual])!
 assert os.read_bytes(golden)! == os.read_bytes(actual)!
 println('STREAM238 smaller-overwrite PASS')
 producer_failure := stream_commands(['tar', '--format=ustar', '-cf', '-', '-C', root + '/missing', '.'], ['mcopy', '-o', '-i', image, '-', '::/boot/qemu-runtime.tar'])!
 assert producer_failure.producer != 0
 println('STREAM238 producer-failure PASS tar=${producer_failure.producer} mcopy=${producer_failure.consumer}')
 os.write_file_array(root + '/nested/payload.bin', data)!
 consumer_failure := stream_commands(['tar', '--format=ustar', '-cf', '-', '-C', root, '.'], ['mcopy', '-o', '-i', task + 'missing-fat.img', '-', '::/boot/qemu-runtime.tar'])!
 assert consumer_failure.consumer != 0
 println('STREAM238 consumer-failure PASS tar=${consumer_failure.producer} mcopy=${consumer_failure.consumer}')
 mut spawn_failed := false
 stream_commands(['tar', '--format=ustar', '-cf', '-', '-C', root, '.'], [task + 'missing-executable']) or { spawn_failed = true }
 assert spawn_failed
 println('STREAM238 consumer-spawn-failure PASS')
 for path in [golden, actual] { os.rm(path)! }
 os.rmdir_all(root)!
 println('STREAM238 ALL PASS')
}
