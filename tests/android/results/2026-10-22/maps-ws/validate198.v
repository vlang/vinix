import os
import compress.gzip
fn main() {
 base:='build/android-maps/'
 before:=gzip.decompress(os.read_bytes(base+'fixture-lifecycle198-baseline/lifecycle-fixture/serial.log.gz')!)!.bytestr()
 after:=gzip.decompress(os.read_bytes(base+'fixture-lifecycle198-fixed/lifecycle-fixture/serial.log.gz')!)!.bytestr()
 assert before.contains('java.lang.AssertionError:')
 assert !before.contains('LIFECYCLE-CALLBACKS-PASS')
 assert after.contains('LIFECYCLE-CALLBACKS-PASS all-21-phases application-activity-order reverse-teardown snapshot-remove-add defaults restart recreation main-thread pre-application-order post-resume-order')
 assert !after.contains('java.lang.AssertionError')
 assert !after.contains('APK-SUITE-EXIT id=')
 println('LIFECYCLE198-REGRESSION-PASS: same signed APK fails old ordering; final framework/native pass 21 phases, application forward/activity reverse ordering, snapshot mutations, default methods, restart, recreation, main thread and post-resume timing')
}
