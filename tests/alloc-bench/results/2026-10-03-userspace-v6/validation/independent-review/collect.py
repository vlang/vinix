#!/usr/bin/env python3
"""Read-only evidence collection for exact staged v6 allocator objects."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path('/Users/alex/code/vinix')
OUT = ROOT / 'build/useralloc-review-v6'
PATCH_SHA = hashlib.sha256((ROOT/'build-support/musl/malloc-retain.patch').read_bytes()).hexdigest()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def cmd(args):
    return subprocess.check_output([str(x) for x in args])

def function(asm, name):
    start = asm.index('<'+name+'>:')
    end = asm.find('\n\n', start)
    return asm[start:end if end >= 0 else len(asm)]

def archive_members(path):
    # libc.a contains repeated basenames (public wrappers and mallocng).
    # Parse every occurrence so evidence names the byte-identical member,
    # rather than relying on ar p's ambiguous first-name lookup.
    data = path.read_bytes()
    assert data.startswith(b'!<arch>\n')
    result = {}
    pos = 8
    while pos < len(data):
        header = data[pos:pos+60]
        assert header[58:60] == b'`\n'
        name = header[:16].decode().strip().rstrip('/')
        size = int(header[48:58].decode().strip())
        body = data[pos+60:pos+60+size]
        result.setdefault(name, []).append(body)
        pos += 60 + size + (size & 1)
    assert pos == len(data)
    return result

records = {}
for stage in ['optimized-v6-final', 'disabled-v6-final', 'optimized-arm126-v6-final', 'disabled-arm126-v6-final']:
    base = ROOT/'third_party/useralloc-libc/build/useralloc'/stage
    mp = base/'usr/share/vinix/musl-build.json'
    manifest = json.loads(mp.read_text())
    source = Path(manifest['configure_argv'][0]).parent
    cache = source.parent
    cached_manifest = json.loads((cache/'build.json').read_text())
    toolbase = Path(manifest['cc'][0]).parent
    prefix = manifest['compiler_target']+'-'
    objdump = toolbase/(prefix+'objdump')
    ar = toolbase/(prefix+'ar')
    readelf = toolbase/(prefix+'readelf')
    cached_lib = cache/'objects/lib'
    loader = base/('lib/ld-musl-'+manifest['arch']+'.so.1')
    archive = base/'usr/lib/libc.a'
    r = {
        'manifest': manifest,
        'manifest_sha256': sha(mp),
        'stage_manifest_matches_cache': manifest == cached_manifest,
        'patch_sha256_matches_candidate': manifest['patches'][-1]['sha256'] == PATCH_SHA,
        'cached_patch_sha256_matches_candidate': sha(cache/'patches/malloc-retain.patch') == PATCH_SHA,
        'loader_sha256': sha(loader),
        'archive_sha256': sha(archive),
        'loader_matches_manifest_and_cache': sha(loader) == manifest['libc_so_sha256'] == sha(cached_lib/'libc.so'),
        'archive_matches_manifest_and_cache': sha(archive) == manifest['libc_a_sha256'] == sha(cached_lib/'libc.a'),
        'source_sha256': {n: sha(source/'src/malloc/mallocng'/n) for n in ['malloc.c','meta.h','free.c','glue.h','realloc.c','aligned_alloc.c']},
        'objects': {},
    }
    members = archive_members(archive)
    for name in ['malloc','free','realloc']:
        for ext in ['o','lo']:
            obj = cache/'objects/obj/src/malloc/mallocng'/(name+'.'+ext)
            asm = cmd([objdump, '-dr', obj]).decode()
            ap = OUT/(stage+'-'+name+'-'+ext+'.asm')
            ap.write_text(asm)
            sym = {'malloc':'__libc_malloc_impl','free':'__libc_free','realloc':'__libc_realloc'}[name]
            body = function(asm,sym)
            z = {'object_sha256':sha(obj), 'object_path':str(obj.relative_to(ROOT)),
                 'assembly_sha256':sha(ap),'assembly_path':str(ap.relative_to(ROOT)),
                 'function_has_stack_canary_reference':'__stack_chk_fail' in body,
                 'object_has_stack_canary_reference':'__stack_chk_fail' in asm,
                 'trap_instruction_present': ('ud2' in asm if manifest['arch']=='x86_64' else 'brk' in asm),
                 'function_calls':[l.strip() for l in body.splitlines() if re.search(r'\b(call|bl)\s',l)]}
            if manifest['arch']=='x86_64':
                z['function_pushes'] = [l.strip() for l in body.splitlines() if re.search(r'\bpush\s',l)]
                z['function_stack_arithmetic'] = [l.strip() for l in body.splitlines() if re.search(r'\b(sub|add)\s.*%rsp',l)]
                if name=='malloc':
                    z['malloc_slow_tail_jump_relocations'] = [l.strip() for l in body.splitlines() if '.text.malloc_slow' in l]
            if ext=='o':
                member = name+'.o'
                data = members[member]
                z['archive_member_count'] = len(data)
                z['archive_member_sha256s'] = [hashlib.sha256(x).hexdigest() for x in data]
                z['archive_byte_identical_member_count'] = sum(x == obj.read_bytes() for x in data)
                z['archive_member_byte_identical'] = z['archive_byte_identical_member_count'] == 1
            r['objects'][name+'.'+ext] = z
    # Save linked symbol tables to tie allocator implementations and public wrappers to the loader.
    sp = OUT/(stage+'-symbols.txt')
    sp.write_bytes(cmd([readelf,'-Ws',loader]))
    r['loader_symbols_sha256'] = sha(sp)
    records[stage] = r

checks = []
for n,r in records.items():
    for key in ['stage_manifest_matches_cache','patch_sha256_matches_candidate','cached_patch_sha256_matches_candidate','loader_matches_manifest_and_cache','archive_matches_manifest_and_cache']:
        checks.append(r[key])
    for obj,z in r['objects'].items():
        if obj.endswith('.o'):
            checks.append(z['archive_member_byte_identical'])
        if obj.startswith('free.'):
            checks.append(not z['object_has_stack_canary_reference'])
        if r['manifest']['arch']=='x86_64' and obj.startswith('malloc.'):
            checks.append(len(z['function_pushes'])==2 and not z['function_stack_arithmetic'] and not z['function_calls'] and bool(z['malloc_slow_tail_jump_relocations']))
result = {'candidate_patch_sha256':PATCH_SHA,'all_machine_checks_pass':all(checks),'object_count':sum(len(r['objects']) for r in records.values()),'stages':records}
(OUT/'object-proof.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'all_machine_checks_pass':result['all_machine_checks_pass'],'object_count':result['object_count'], 'stages':{k:{'arch':v['manifest']['arch'],'retention':v['manifest']['retention'],'loader_sha256':v['loader_sha256'],'archive_sha256':v['archive_sha256']} for k,v in records.items()}},indent=2))
