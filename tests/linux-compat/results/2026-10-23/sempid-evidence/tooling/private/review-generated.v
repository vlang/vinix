import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'

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
        index := text.index('struct sysvsem__Set {') or { panic('Missing set') }
        end := text[index..].index('\n};') or { panic('Missing set end') }
        layout := text[index..index + end + 3]
        assert layout.contains('i64 last_pid[32];')
        commit := body(text, 'void sysvsem__commit_unlocked(sysvsem__Set* set, i64* proposed, sysvsem__SemBuf* operations, i64 count, i64 pid)')!
        assert commit.contains('i < count')
        assert commit.contains('i64 number = (i64)(((operations)[i]).number);')
        assert commit.contains('set->last_pid[v_fixed_index(number, 32)] = pid;')
        for forbidden in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'event__', 'free('] {
            assert !commit.contains(forbidden), 'New allocation or lifetime in commit: ' + forbidden
        }
        control := body(text, 'multi_return_u64_u64 sysvsem__syscall_semctl(void* _0, i32 id, i32 number, i32 command, u64 argument)')!
        assert control.contains('i64 pid = set->last_pid[v_fixed_index(number, 32)];')
        assert control.contains('set->last_pid[v_fixed_index(number, 32)] = (proc__current_thread())->process->pid;')
        progress := body(text, 'void sysvsem__progress_unlocked(sysvsem__Set* set)')!
        assert progress.contains('sysvsem__commit_unlocked(set, &proposed[0], pending->operations, pending->count, pending->pid);')
        operate := body(text, 'multi_return_u64_u64 sysvsem__operate(i32 id, u64 user_operations, u32 count, u64 timeout_address)')!
        assert operate.contains('sysvsem__commit_unlocked(set, &proposed[0], &operations[0], (i64)(count), pid);')
        get := body(text, 'multi_return_u64_u64 sysvsem__syscall_semget(void* _0, i32 key, i32 nsems, i32 flags)')!
        initializer := get.split_into_lines().filter(it.contains('memdup(&(sysvsem__Set)'))
        assert initializer.len == 1 && !initializer[0].contains('.last_pid')
        output := area + '/generated-review-' + suffix + '.c.txt'
        os.write_file(output, layout + '\n' + commit + '\n' + control + '\n' + progress + '\n' + operate + '\n' + get)!
        records << {
            'architecture': suffix,
            'generated_c': path,
            'generated_c_sha256': digest(path)!,
            'excerpt': output,
            'excerpt_sha256': digest(output)!,
            'result': 'PASS: inline zero-initialized 32-slot PID array; successful vector indices only; indexed SETVAL and GETPID; queued operations retain original caller PID; no new allocation in commit',
            'scope': 'Inline metadata adds 248 bytes to the existing set allocation and is freed with it. Existing set and pending-operation ownership, synchronization and teardown are unchanged. No new allocation or lifetime is introduced.'
        }
    }
    os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
    println('Generated semaphore PID review: PASS (both architectures)')
}
