// Exercise each actual maintained greeting body with independent output goldens.
module fixture
#include <stdio.h>
#include <unistd.h>
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
 greet_world()
 greet_arm()
 greet_x86()
 C.puts(c'USERLAND DEMO V PASS')
 // PID 1 remains alive instead of returning through libc's normal exit flush.
 C.fflush(unsafe { nil })
 $if hello_host ? {
  return 0
 } $else {
  for { C.pause() }
  return 0
 }
}
