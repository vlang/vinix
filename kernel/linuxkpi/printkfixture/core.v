// SPDX-License-Identifier: GPL-2.0-only
// Independent native logging fixture; every callback borrow quiesces on detach.
@[translated]
module printkfixture

#include "linuxkpi_printk_fixture_v_contract.h"

struct C.completion {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.vkfp_const_record_p {}
struct C.vinix_linuxkpi_printk_record {
 sequence u64
 caller u64
 format_status u32
 length u16
 level u8
 flags u8
 text [1024]char
}
struct C.vinix_linuxkpi_printk_state {
 submitted u64
 retired u64
 dropped u64
 truncated u64
 format_errors u64
 queued u32
 in_flight bool
 worker_live bool
 paused bool
 key_ready bool
}
type Sink = fn (C.vkfp_const_record_p, voidptr)
type NativeThread = fn (voidptr) voidptr
fn C.vinix_linuxkpi_fixture_printk_sink(C.vkfp_const_record_p, voidptr)
fn C.vinix_linuxkpi_fixture_printk_produce(voidptr) voidptr
fn C.vinix_linuxkpi_fixture_printk_flusher(voidptr) voidptr
fn C.vinix_linuxkpi_fixture_nested_format(&char, ...) i32
fn C.vinix_linuxkpi_fixture_nested_emit(&char, ...) i32
fn C.vkr_format_entry(&char, usize, &char, voidptr, &u32) i32
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable_no_resched()
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_test_worker_oom(i32)
fn C.vinix_linuxkpi_test_alloc_oom(i32)
fn C.vinix_linuxkpi_test_printk_locks() i32
fn C._printk(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.scnprintf(&char, usize, &char, ...) i32
fn C.vinix_linuxkpi_printk_snapshot() u64
fn C.vinix_linuxkpi_printk_get_state(&C.vinix_linuxkpi_printk_state)
fn C.vinix_linuxkpi_printk_flush(u64, u32) i32
fn C.vinix_linuxkpi_printk_shutdown() i32
fn C.vinix_linuxkpi_printk_bootstrap() i32
fn C.vinix_linuxkpi_printk_test_fail_create(bool)
fn C.vinix_linuxkpi_printk_test_pause(bool, u32) i32
fn C.vinix_linuxkpi_printk_test_sink(Sink, voidptr) i32
fn C.pthread_create(voidptr, voidptr, NativeThread, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.completion_done(&C.completion) bool
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.add_taint(u32, i32)
fn C.test_taint(u32) bool
fn C.get_taint() usize
fn C.cond_resched() i32
fn C.kmalloc(usize, u32) voidptr
fn C.kfree(voidptr)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strcpy(&char, &char) &char
fn C.strcmp(&char, &char) i32
fn C.memchr_inv(voidptr, i32, usize) voidptr
fn C.ERR_PTR(isize) voidptr
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32
@[c_extern] __global (
 C.EIO i32
 C.EALREADY i32
 C.ENODEV i32
 C.ENOMEM i32
 C.EDEADLK i32
 C.EWOULDBLOCK i32
 C.EOPNOTSUPP i32
 C.ETIMEDOUT i32
 C.GFP_KERNEL u32
 C.LOCKDEP_STILL_OK i32
 C.VINIX_PRINTK_CONT u32
 C.VINIX_PRINTK_NEWLINE u32
 C.VINIX_PRINTK_TRUNCATED u32
 C.VINIX_FORMAT_TRUNCATED u32
 C.VINIX_FORMAT_INVALID u32
)

enum Phase { basic producers overflow snapshot }
struct Capture {
mut:
 records [16]C.vinix_linuxkpi_printk_record
 first_entered C.completion
 first_release C.completion
 late_entered C.completion
 late_release C.completion
 phase Phase
 last_sequence u64
 seen [4]u64
 count u32
 hold_first bool
 hold_late bool
 result i32
}
struct VaDescriptor { fmt &char va voidptr }
struct OwnedText {
mut:
 text [16]char
 bytes [3]u8
}
struct Producer {
mut:
 thread C.pthread_t
 entered C.completion
 go C.completion
 done C.completion
 index u32
 cpu u32
 cancel u32
 initialized bool
 started bool
 result i32
}
struct Flusher {
mut:
 thread C.pthread_t
 entered C.completion
 done C.completion
 snapshot u64
 result i32
}

// Preserve the original first-failed-condition diagnostics as well as checks.
fn expect(result &i32, condition bool, original_line i32) {
 unsafe { if !condition && *result == 0 { *result = -original_line } }
}
fn irqs_enabled() bool { return C.vinix_linuxkpi_irq_flags() & (usize(1) << 9) != 0 }

@[export: 'vinix_linuxkpi_printk_locked_probe']
pub fn locked_probe() i32 {
 unsafe {
  mut result := i32(0)
  pinned := C.vinix_linuxkpi_preempt_count()
  irqs := irqs_enabled()
  expect(&result, C._printk(c'\x01\x36native held-lock probe\n') == 22, 37)
  expect(&result, C.vinix_linuxkpi_preempt_count() == pinned && irqs_enabled() == irqs, 39)
  return result
 }
}

@[export: 'vinix_linuxkpi_printk_bootstrap_native_selftest']
pub fn bootstrap_test() i32 {
 unsafe {
  mut result := i32(0)
  mut state := C.vinix_linuxkpi_printk_state{}
  C.vinix_linuxkpi_printk_get_state(&state)
  if state.worker_live { return -C.EALREADY }
  expect(&result, C._printk(c'\x01\x36native logging preboot\n') == 22, 49)
  before := C.vinix_linuxkpi_printk_snapshot()
  expect(&result, C.vinix_linuxkpi_printk_flush(before, 0) == -C.ENODEV, 51)
  C.vinix_linuxkpi_printk_test_fail_create(true)
  mut error := C.vinix_linuxkpi_printk_bootstrap()
  C.vinix_linuxkpi_printk_test_fail_create(false)
  expect(&result, error == -C.ENOMEM, 55)
  C.vinix_linuxkpi_printk_get_state(&state)
  expect(&result, !state.worker_live && state.submitted == before, 57)
  if state.worker_live {
   C.BUG_ON(C.vinix_linuxkpi_printk_shutdown() != 0)
   return if result != 0 { result } else { -C.EIO }
  }
  for stage in 1 .. 5 {
   C.vinix_linuxkpi_test_worker_oom(i32(stage))
   error = C.vinix_linuxkpi_printk_bootstrap()
   C.vinix_linuxkpi_test_worker_oom(0)
   expect(&result, error == -C.ENOMEM, 66)
   C.vinix_linuxkpi_printk_get_state(&state)
   expect(&result, !state.worker_live && state.submitted == before, 68)
   if state.worker_live {
    C.BUG_ON(C.vinix_linuxkpi_printk_shutdown() != 0)
    return if result != 0 { result } else { -C.EIO }
   }
  }
  if result != 0 { return result }
  error = C.vinix_linuxkpi_printk_bootstrap()
  if error != 0 { return error }
  expect(&result, C.vinix_linuxkpi_printk_bootstrap() == 0, 77)
  expect(&result, C.vinix_linuxkpi_printk_flush(before, 2000) == 0, 78)
  C.vinix_linuxkpi_printk_get_state(&state)
  expect(&result, state.worker_live && state.retired == state.submitted && state.queued == 0 && !state.in_flight, 81)
  return result
 }
}

@[export: 'vinix_linuxkpi_fixture_nested_format_entry']
pub fn nested_format_entry(format &char, cursor voidptr) i32 {
 unsafe {
  mut result := i32(0)
  mut nested := VaDescriptor{fmt: format, va: cursor}
  mut text := [96]char{}
  expected := &char(c'[CRTC:7:eDP-1] mismatch in pipe mode=1920/ok\n')
  expect(&result, C.snprintf(&text[0], sizeof(text), c'[CRTC:%d:%s] mismatch in %s %pV\n', i32(7), c'eDP-1', c'pipe', &nested) == 45 && C.strcmp(&text[0], expected) == 0, 95)
  // The second parse uses the producer's cursor, proving nested va_copy.
  expect(&result, C.vkr_format_entry(&text[0], sizeof(text), format, cursor, nil) == 12 && C.strcmp(&text[0], c'mode=1920/ok') == 0, 98)
  return result
 }
}

fn formats() i32 {
 unsafe {
  mut result := C.vinix_linuxkpi_fixture_nested_format(c'mode=%u/%s', u32(1920), c'ok')
  mut text := [96]char{}
  mut physical := u64(0x1234)
  mut fourcc := u32(0x3231564e)
  mut bytes := [u8(0xc0), u8(0xff), u8(0xee)]!
  mut bitmap := usize(0xa28ac)
  expect(&result, C.snprintf(&text[0], sizeof(text), c'%pa', &physical) == 18 && C.strcmp(&text[0], c'0x0000000000001234') == 0, 112)
  expect(&result, C.snprintf(&text[0], sizeof(text), c'%p4cc', &fourcc) == 31 && C.strcmp(&text[0], c'NV12 little-endian (0x3231564e)') == 0, 114)
  expect(&result, C.snprintf(&text[0], sizeof(text), c'%3ph', &bytes[0]) == 8 && C.strcmp(&text[0], c'c0 ff ee') == 0, 116)
  expect(&result, C.snprintf(&text[0], sizeof(text), c'%20pbl', &bitmap) == 19 && C.strcmp(&text[0], c'2-3,5,7,11,13,17,19') == 0, 119)
  expect(&result, C.snprintf(&text[0], sizeof(text), c'%pe', C.ERR_PTR(isize(-1234))) == 5 && C.strcmp(&text[0], c'-1234') == 0, 121)
  C.memset(&text[0], i32(`x`), sizeof(text))
  expect(&result, C.snprintf(&text[0], 5, c'%s', c'abcdef') == 6 && C.strcmp(&text[0], c'abcd') == 0 && text[5] == char(`x`), 124)
  expect(&result, C.snprintf(&text[0], 0, c'%s', c'abcdef') == 6 && text[0] == char(`a`), 125)
  expect(&result, C.scnprintf(&text[0], 5, c'%s', c'abcdef') == 4 && C.strcmp(&text[0], c'abcd') == 0, 126)
  mut untouched := i32(37)
  invalid := &char(c'before%nnever')
  expect(&result, C.snprintf(&text[0], sizeof(text), invalid, &untouched) == 6 && C.strcmp(&text[0], c'before') == 0 && untouched == 37, 130)
  return result
 }
}

fn inspect(capture &Capture, record &C.vinix_linuxkpi_printk_record, result &i32, index u32) {
 unsafe {
  if index == 0 {
   expect(result, C.vinix_linuxkpi_printk_flush(record.sequence, 0) == -C.EDEADLK, 161)
   expect(result, C.vinix_linuxkpi_printk_test_pause(true, 0) == -C.EDEADLK, 162)
   expect(result, C.vinix_linuxkpi_printk_shutdown() == -C.EDEADLK, 163)
  }
  if capture.phase == .producers {
   id := u32(u8(record.text[10])) - u32(`0`)
   tens := u32(u8(record.text[18])) - u32(`0`)
   units := u32(u8(record.text[19])) - u32(`0`)
   round := tens * 10 + units
   expect(result, record.length == 46 && id < 4 && tens < 10 && units < 10 && round < 64 && record.level == 6 && record.flags == C.VINIX_PRINTK_NEWLINE && record.format_status == 0, 174)
   if id < 4 && round < 64 && tens < 10 && units < 10 {
    mut expected := [47]char{}
    C.memcpy(&expected[0], c'native id=0 round=00 str=stable bytes=c0 ff ee', sizeof(expected))
    expected[10] = char(u32(`0`) + id)
    expected[18] = char(u32(`0`) + round / 10)
    expected[19] = char(u32(`0`) + round % 10)
    expect(result, C.strcmp(&record.text[0], &expected[0]) == 0 && capture.seen[id] & (u64(1) << round) == 0, 182)
    capture.seen[id] |= u64(1) << round
   }
  } else if capture.phase == .overflow {
   if index == 0 { expect(result, C.strcmp(&record.text[0], c'held') == 0, 186) }
   else {
    mut expected := [12]char{}
    C.memcpy(&expected[0], c'overflow=00', sizeof(expected))
    value := index + 15
    expected[9] = char(u32(`0`) + value / 10)
    expected[10] = char(u32(`0`) + value % 10)
    expect(result, index <= 64 && C.strcmp(&record.text[0], &expected[0]) == 0, 192)
   }
  } else {
   expect(result, index < 16, 195)
   if index < 16 { capture.records[index] = *record }
  }
 }
}

@[export: 'vinix_linuxkpi_fixture_printk_sink']
pub fn sink(record_const C.vkfp_const_record_p, argument voidptr) {
 unsafe {
  mut capture := &Capture(argument)
  record := &C.vinix_linuxkpi_printk_record(record_const)
  mut result := capture.result
  index := capture.count
  expect(&result, C.vinix_linuxkpi_may_sleep() && irqs_enabled() && C.vinix_linuxkpi_preempt_count() == 0, 153)
  expect(&result, record.length < 1024 && record.text[record.length] == 0 && record.caller == 0 && record.sequence > capture.last_sequence, 156)
  capture.last_sequence = record.sequence
  if record.length < 1024 && record.text[record.length] == 0 { inspect(capture, record, &result, index) }
  capture.result = result
  if index == 0 && capture.hold_first {
   C.complete(&capture.first_entered)
   C.wait_for_completion(&capture.first_release)
  }
  if index == 1 && capture.hold_late {
   C.complete(&capture.late_entered)
   C.wait_for_completion(&capture.late_release)
  }
  capture.count = index + 1
 }
}

fn attach(capture &Capture, phase Phase) i32 {
 unsafe {
  if C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(), 2000) != 0 { return -C.EIO }
  if C.vinix_linuxkpi_printk_test_pause(true, 2000) != 0 { return -C.EIO }
  *capture = Capture{phase: phase}
  C.init_completion(&capture.first_entered)
  C.init_completion(&capture.first_release)
  C.init_completion(&capture.late_entered)
  C.init_completion(&capture.late_release)
  result := C.vinix_linuxkpi_printk_test_sink(C.vinix_linuxkpi_fixture_printk_sink, capture)
  if result != 0 { C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(false, 0) != 0) }
  return result
 }
}
fn detach(capture &Capture) i32 {
 unsafe {
  mut result := i32(0)
  C.complete_all(&capture.first_release)
  C.complete_all(&capture.late_release)
  C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(false, 0) != 0)
  expect(&result, C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(), 2000) == 0, 229)
  // Quiesce every callback before removing its borrowed stack argument.
  C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(true, 2000) != 0)
  C.BUG_ON(C.vinix_linuxkpi_printk_test_sink(Sink(nil), nil) != 0)
  C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(false, 0) != 0)
  return if result != 0 { result } else { capture.result }
 }
}

@[export: 'vinix_linuxkpi_fixture_nested_emit_entry']
pub fn nested_emit_entry(format &char, cursor voidptr) i32 {
 unsafe {
  mut nested := VaDescriptor{fmt: format, va: cursor}
  return C._printk(c'\x01\x34nested:%pV\n', &nested)
 }
}

fn basic_emit(result &i32) {
 unsafe {
  @[freed]
  owned := &OwnedText(C.kmalloc(sizeof(OwnedText), C.GFP_KERNEL))
  if owned == nil { *result = -C.ENOMEM; return }
  C.strcpy(&owned.text[0], c'short-lived')
  owned.bytes[0] = 0xc0
  owned.bytes[1] = 0xff
  owned.bytes[2] = 0xee
  expect(result, C._printk(c'\x01\x36owned=%s bytes=%3ph\n', &owned.text[0], &owned.bytes[0]) == 32, 260)
  C.memset(owned, i32(`X`), sizeof(OwnedText))
  C.kfree(owned)
  mut nested := [char(`s`), char(`t`), char(`a`), char(`b`), char(`l`), char(`e`), char(0)]!
  expect(result, C.vinix_linuxkpi_fixture_nested_emit(c'%s/%d', &nested[0], i32(-9)) == 16, 264)
  C.memset(&nested[0], i32(`x`), sizeof(nested))
  expect(result, C._printk(c'%s%sowned %d\n', c'\x01\x35', c'\x01\x63', i32(7)) == 7, 266)
  expect(result, C._printk(c'\x01\x63tail') == 4, 267)
  expect(result, C._printk(c'\x01\x36new\n') == 3, 268)
  expect(result, C.vinix_linuxkpi_test_printk_locks() == 0, 269)
  C.vinix_linuxkpi_test_alloc_oom(0)
  flags := C.vinix_linuxkpi_irq_save()
  C.vinix_linuxkpi_preempt_disable()
  C.vinix_linuxkpi_preempt_disable()
  // Escape the initial 'a' separately so C's hex escape cannot consume it.
  expect(result, C._printk(c'\x01\x34\x61tomic producer\n') == 15, 273)
  expect(result, !irqs_enabled() && C.vinix_linuxkpi_preempt_count() == 2, 274)
  expect(result, C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(), 0) == -C.EWOULDBLOCK, 275)
  C.vinix_linuxkpi_preempt_enable_no_resched()
  C.vinix_linuxkpi_preempt_enable_no_resched()
  C.vinix_linuxkpi_irq_restore(flags)
  probe := C.kmalloc(17, C.GFP_KERNEL)
  C.vinix_linuxkpi_test_alloc_oom(-1)
  expect(result, probe == nil, 280)
  C.kfree(probe)
  mut large := [1124]char{}
  C.memset(&large[0], i32(`a`), sizeof(large) - 1)
  large[1123] = 0
  expect(result, C._printk(c'%s', &large[0]) == 1023, 284)
  mut untouched := i32(37)
  invalid := &char(c'before%nnever')
  expect(result, C._printk(invalid, &untouched) == 6 && untouched == 37, 287)
 }
}
fn basic() i32 {
 unsafe {
  mut capture := Capture{}
  mut result := attach(&capture, .basic)
  if result != 0 { return result }
  mut before := C.vinix_linuxkpi_printk_state{}
  mut after := C.vinix_linuxkpi_printk_state{}
  C.vinix_linuxkpi_printk_get_state(&before)
  basic_emit(&result)
  cleanup := detach(&capture)
  if result == 0 { result = cleanup }
  if result != 0 { return result }
  C.vinix_linuxkpi_printk_get_state(&after)
  expect(&result, capture.count == 10 && irqs_enabled() && C.vinix_linuxkpi_preempt_count() == 0, 296)
  expect(&result, after.truncated == before.truncated + 1 && after.format_errors == before.format_errors + 1, 298)
  expect(&result, C.strcmp(&capture.records[0].text[0], c'owned=short-lived bytes=c0 ff ee') == 0, 299)
  expect(&result, C.strcmp(&capture.records[1].text[0], c'nested:stable/-9') == 0, 300)
  expect(&result, C.strcmp(&capture.records[2].text[0], c'owned 7') == 0 && capture.records[2].level == 5 && capture.records[2].flags == C.VINIX_PRINTK_CONT | C.VINIX_PRINTK_NEWLINE, 303)
  expect(&result, C.strcmp(&capture.records[3].text[0], c'tail') == 0 && capture.records[3].flags == C.VINIX_PRINTK_CONT && C.strcmp(&capture.records[4].text[0], c'new') == 0 && capture.records[4].flags == C.VINIX_PRINTK_NEWLINE, 307)
  expect(&result, C.strcmp(&capture.records[5].text[0], c'native held-lock probe') == 0 && C.strcmp(&capture.records[6].text[0], c'native held-lock probe') == 0 && C.strcmp(&capture.records[7].text[0], c'atomic producer') == 0, 310)
  expect(&result, capture.records[8].length == 1023 && capture.records[8].flags == C.VINIX_PRINTK_TRUNCATED && capture.records[8].format_status == C.VINIX_FORMAT_TRUNCATED && C.memchr_inv(&capture.records[8].text[0], i32(`a`), 1023) == nil, 314)
  expect(&result, C.strcmp(&capture.records[9].text[0], c'before') == 0 && capture.records[9].format_status == C.VINIX_FORMAT_INVALID, 316)
  return result
 }
}

@[export: 'vinix_linuxkpi_fixture_printk_produce']
pub fn produce(argument voidptr) voidptr {
 unsafe {
  mut test := &Producer(argument)
  mut result := C.vinix_linuxkpi_worker_bind(test.cpu)
  C.complete(&test.entered)
  C.wait_for_completion(&test.go)
  for round := u32(0); result == 0 && round < 64 && C.__atomic_load_n(&test.cancel, 2) == 0; round++ {
   mut borrowed := [char(`s`), char(`t`), char(`a`), char(`b`), char(`l`), char(`e`), char(0)]!
   mut bytes := [u8(0xc0), u8(0xff), u8(0xee)]!
   pins := if round & 2 != 0 { u32(2) } else { u32(0) }
   mut flags := usize(0)
   if round & 1 != 0 { flags = C.vinix_linuxkpi_irq_save() }
   for i := u32(0); i < pins; i++ { C.vinix_linuxkpi_preempt_disable() }
   expect(&result, C._printk(c'\x01\x36native id=%u round=%02u str=%s bytes=%3ph\n', test.index, round, &borrowed[0], &bytes[0]) == 46, 342)
   C.add_taint(test.index, C.LOCKDEP_STILL_OK)
   expect(&result, C.test_taint(test.index), 344)
   expect(&result, C.vinix_linuxkpi_preempt_count() == pins && irqs_enabled() == (round & 1 == 0), 346)
   C.memset(&borrowed[0], i32(`X`), sizeof(borrowed))
   C.memset(&bytes[0], 0, sizeof(bytes))
   for i := u32(0); i < pins; i++ { C.vinix_linuxkpi_preempt_enable_no_resched() }
   if round & 1 != 0 { C.vinix_linuxkpi_irq_restore(flags) }
   expect(&result, C.vinix_linuxkpi_may_sleep() && C.vinix_linuxkpi_cpu_id() == test.cpu, 350)
   if round % 8 == 7 {
    expect(&result, C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(), 2000) == 0, 354)
    C.cond_resched()
   }
  }
  test.result = result
  C.complete(&test.done)
  C.pthread_exit(nil)
  return nil
 }
}

fn producers_body(tests &Producer, result &i32) {
 unsafe {
  cpus := C.vinix_linuxkpi_percpu_count()
  if cpus == 0 || cpus > 64 { *result = -C.EOPNOTSUPP; return }
  taint_before := C.get_taint()
  for i := u32(0); i < 4; i++ {
   tests[i].index = i
   tests[i].cpu = i % cpus
   C.init_completion(&tests[i].entered)
   C.init_completion(&tests[i].go)
   C.init_completion(&tests[i].done)
   tests[i].initialized = true
   if C.pthread_create(&tests[i].thread, nil, C.vinix_linuxkpi_fixture_printk_produce, &tests[i]) != 0 { *result = -C.ENOMEM; return }
   tests[i].started = true
   if C.wait_for_completion_timeout(&tests[i].entered, 2000) == 0 { *result = -C.EIO; return }
  }
  C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(false, 0) != 0)
  for i := u32(0); i < 4; i++ { C.complete(&tests[i].go) }
  for i := u32(0); i < 4; i++ {
   if C.wait_for_completion_timeout(&tests[i].done, 2000) == 0 { *result = -C.EIO; return }
  }
  expect(result, C.get_taint() & (taint_before | usize(15)) == taint_before | usize(15), 390)
 }
}
fn producers() i32 {
 unsafe {
  mut capture := Capture{}
  mut result := attach(&capture, .producers)
  if result != 0 { return result }
  mut tests := [4]Producer{}
  mut before := C.vinix_linuxkpi_printk_state{}
  mut after := C.vinix_linuxkpi_printk_state{}
  C.vinix_linuxkpi_printk_get_state(&before)
  producers_body(&tests[0], &result)
  for i := u32(0); i < 4; i++ {
   C.__atomic_store_n(&tests[i].cancel, 1, 3)
   if tests[i].initialized { C.complete_all(&tests[i].go) }
  }
  for i := u32(0); i < 4; i++ {
   if !tests[i].started { continue }
   C.BUG_ON(C.pthread_join(tests[i].thread, nil) != 0)
   if result == 0 && tests[i].result != 0 { result = tests[i].result }
  }
  cleanup := detach(&capture)
  if result == 0 { result = cleanup }
  if result != 0 { return result }
  C.vinix_linuxkpi_printk_get_state(&after)
  expect(&result, capture.count == 256 && after.dropped == before.dropped && after.submitted == before.submitted + 256 && after.retired == after.submitted, 409)
  for i := u32(0); i < 4; i++ { expect(&result, capture.seen[i] == ~u64(0), 411) }
  return result
 }
}

fn overflow_body(capture &Capture, before &C.vinix_linuxkpi_printk_state, result &i32) {
 unsafe {
  expect(result, C._printk(c'held') == 4, 423)
  first := C.vinix_linuxkpi_printk_snapshot()
  C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(false, 0) != 0)
  if C.wait_for_completion_timeout(&capture.first_entered, 2000) == 0 { *result = -C.EIO; return }
  for i := u32(0); i < 80; i++ { expect(result, C._printk(c'overflow=%02u', i) == 11, 428) }
  last := C.vinix_linuxkpi_printk_snapshot()
  mut held := C.vinix_linuxkpi_printk_state{}
  C.vinix_linuxkpi_printk_get_state(&held)
  expect(result, held.queued == 64 && held.in_flight && held.retired == first - 1 && held.dropped == before.dropped + 16 && held.submitted == first + 80, 433)
  expect(result, C.vinix_linuxkpi_printk_flush(first + 10, 0) == -C.ETIMEDOUT, 434)
  C.complete(&capture.first_release)
  expect(result, C.vinix_linuxkpi_printk_flush(last, 2000) == 0, 436)
 }
}
fn overflow() i32 {
 unsafe {
  mut capture := Capture{}
  mut result := attach(&capture, .overflow)
  if result != 0 { return result }
  capture.hold_first = true
  mut before := C.vinix_linuxkpi_printk_state{}
  mut after := C.vinix_linuxkpi_printk_state{}
  C.vinix_linuxkpi_printk_get_state(&before)
  overflow_body(&capture, &before, &result)
  cleanup := detach(&capture)
  if result == 0 { result = cleanup }
  if result != 0 { return result }
  C.vinix_linuxkpi_printk_get_state(&after)
  expect(&result, capture.count == 65 && after.retired == after.submitted && after.queued == 0 && !after.in_flight && after.dropped == before.dropped + 16, 445)
  return result
 }
}

@[export: 'vinix_linuxkpi_fixture_printk_flusher']
pub fn flush_thread(argument voidptr) voidptr {
 unsafe {
  mut test := &Flusher(argument)
  C.complete(&test.entered)
  test.result = C.vinix_linuxkpi_printk_flush(test.snapshot, 2000)
  C.complete(&test.done)
  C.pthread_exit(nil)
  return nil
 }
}
fn snapshot_body(capture &Capture, flusher &Flusher, started &bool, result &i32) {
 unsafe {
  expect(result, C._printk(c'old') == 3, 474)
  flusher.snapshot = C.vinix_linuxkpi_printk_snapshot()
  C.BUG_ON(C.vinix_linuxkpi_printk_test_pause(false, 0) != 0)
  if C.wait_for_completion_timeout(&capture.first_entered, 2000) == 0 { *result = -C.EIO; return }
  if C.pthread_create(&flusher.thread, nil, C.vinix_linuxkpi_fixture_printk_flusher, flusher) != 0 { *result = -C.ENOMEM; return }
  *started = true
  if C.wait_for_completion_timeout(&flusher.entered, 2000) == 0 { *result = -C.EIO; return }
  expect(result, !C.completion_done(&flusher.done), 483)
  expect(result, C._printk(c'late') == 4, 484)
  C.complete(&capture.first_release)
  if C.wait_for_completion_timeout(&capture.late_entered, 2000) == 0 { *result = -C.EIO; return }
  expect(result, C.wait_for_completion_timeout(&flusher.done, 2000) != 0 && flusher.result == 0, 487)
  mut state := C.vinix_linuxkpi_printk_state{}
  C.vinix_linuxkpi_printk_get_state(&state)
  expect(result, state.in_flight && state.retired == flusher.snapshot && capture.count == 1, 490)
 }
}
fn snapshot() i32 {
 unsafe {
  mut capture := Capture{}
  mut result := attach(&capture, .snapshot)
  if result != 0 { return result }
  capture.hold_first = true
  capture.hold_late = true
  mut flusher := Flusher{}
  mut started := false
  C.init_completion(&flusher.entered)
  C.init_completion(&flusher.done)
  snapshot_body(&capture, &flusher, &started, &result)
  C.complete_all(&capture.first_release)
  C.complete_all(&capture.late_release)
  if started { C.BUG_ON(C.pthread_join(flusher.thread, nil) != 0) }
  cleanup := detach(&capture)
  if result == 0 { result = cleanup }
  if result != 0 { return result }
  expect(&result, capture.count == 2 && C.strcmp(&capture.records[0].text[0], c'old') == 0 && C.strcmp(&capture.records[1].text[0], c'late') == 0, 500)
  return result
 }
}

@[export: 'vinix_linuxkpi_printk_native_selftest']
pub fn selftest() i32 {
 mut result := formats()
 if result == 0 { result = basic() }
 if result == 0 { result = producers() }
 if result == 0 { result = overflow() }
 if result == 0 { result = snapshot() }
 if result != 0 { C.kprintf(c'linuxkpi: native logging self-test failed at condition %d\n', -result) }
 return result
}
