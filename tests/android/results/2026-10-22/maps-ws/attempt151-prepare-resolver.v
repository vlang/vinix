import os
import json2

fn main() {
    source := os.read_file('build/android-maps/prepare150.v')!
    os.write_file('build/android-maps/prepare151-build.v', source.replace('resolve150','resolve151').replace('resolver-trace150.v','resolver-trace151.v').replace('fields150','fields151').replace('attempt150','attempt151'))!
    trace := os.read_file('build/android-maps/resolver-trace150.v')!
    marker := '        saved_errno := *C.__errno_location()'
    // Diagnostic only: preserve the real resolver's complete results, with
    // IPv4 entries before IPv6 entries. No lookup or response is fabricated.
    reorder := '        if status == 0 && result != nil {
            mut v4 := &C.addrinfo(nil)
            mut v4_tail := &C.addrinfo(nil)
            mut other := &C.addrinfo(nil)
            mut other_tail := &C.addrinfo(nil)
            mut item := *result
            for item != nil {
                next := item.ai_next
                item.ai_next = nil
                if item.ai_family == 2 {
                    if v4 == nil { v4 = item } else { v4_tail.ai_next = item }
                    v4_tail = item
                } else {
                    if other == nil { other = item } else { other_tail.ai_next = item }
                    other_tail = item
                }
                item = next
            }
            if v4 != nil { v4_tail.ai_next = other; *result = v4 }
            else { *result = other }
        }
'
    os.write_file('build/android-maps/resolver-trace151.v',trace.replace(marker,reorder+marker))!
    r := os.exec(['/Users/alex/code/v/v','-nocache','-cc','cc','run','build/android-maps/prepare151-build.v'])
    assert r.exit_code == 0,r.output
    // The launcher binary is byte-identical; the source is retained per run.
    mut cfg := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/attempt151.json')!)!
    cfg['output'] = 'build/android-maps/attempt151'
    os.write_file('build/android-maps/attempt151.json',json2.encode(cfg,prettify:true))!
}
