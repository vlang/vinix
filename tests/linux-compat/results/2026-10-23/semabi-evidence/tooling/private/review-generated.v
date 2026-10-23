import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn body(text string, signature string) !string {
    start := text.index(signature + ' {') or { return error('Missing function: ' + signature) }
    tail := text[start..]
    end := tail.index('\n}\n') or { return error('Missing function end') }
    return tail[..end + 3]
}

fn main() {
    mut records := []map[string]string{}
    for suffix in ['arm', 'x86'] {
        path := area + '/kernel-' + suffix + '/kernel/obj/blob.c'
        text := os.read_file(path)!
        operate := body(text, 'multi_return_u64_u64 sysvsem__operate(i64 id, u64 user_operations, u32 count, u64 timeout_address)')!
        control := body(text, 'multi_return_u64_u64 sysvsem__syscall_semctl(void* _0, i64 id, i64 number, i64 command, u64 argument)')!
        assert control.contains('i32 value = (i32)(argument);')
        assert operate.contains('time__TimeSpec duration = (time__TimeSpec){0};')
        assert !operate.contains('time__TimeSpec* duration')
        assert operate.contains('usercopy__copy_from_user((void*)(&duration), timeout_address, sizeof(time__TimeSpec))')
        timeout_copy := operate.index('(&duration)') or { panic('Missing timeout copy') }
        count_check := operate.index('if (count == 0)') or { panic('Missing count check') }
        vector_copy := operate.index('(&operations[0])') or { panic('Missing vector copy') }
        duration_check := operate.index('duration.tv_sec < 0') or { panic('Missing duration check') }
        id_lookup := operate.index('sysvsem__find_id_unlocked') or { panic('Missing ID lookup') }
        assert timeout_copy < count_check
        assert vector_copy < duration_check
        assert duration_check < id_lookup
        assert operate.contains('sysvsem__SemBuf operations[32];')
        output := area + '/generated-review-' + suffix + '.c.txt'
        os.write_file(output, control + '\n' + operate)!
        records << {
            'architecture': suffix,
            'generated_c': path,
            'generated_c_sha256': digest(path)!,
            'excerpt': output,
            'excerpt_sha256': digest(output)!,
            'result': 'PASS: signed i32 SETVAL, unsigned u32 count, stack timeout and operation vector, timeout import before count/vector and duration validation before ID lookup',
            'scope': 'Argument/import changes only. Queue ownership, completion, event detachment and set destruction are unchanged; the prior semaphore lifetime qualification is separate.'
        }
    }
    os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
    println('Generated semaphore ABI review: PASS (both architectures)')
}
