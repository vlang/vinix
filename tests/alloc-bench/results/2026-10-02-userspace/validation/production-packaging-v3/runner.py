#!/usr/bin/env python3
"""Run actual production userland builders in private, cached v3 output roots."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, tarfile
ROOT = Path('/Users/alex/code/vinix')
WORK = ROOT/'third_party/useralloc-libc'
PRIOR = WORK/'build/useralloc-production'
STATE = WORK/'build/useralloc-production-v3'
CACHE = WORK/'build/musl'
PATCH_SHA = 'fe6f1a94a9f568823a72ba032ceaa4159adfd529988336dd9fcb5763a21d2578'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def setup(arch):
    target = STATE/arch
    if target.exists(): raise RuntimeError('Refusing to reuse a previous output root: '+str(target))
    target.mkdir(parents=True)
    downloads = PRIOR/arch/'downloads'
    assert (downloads/'main_APKINDEX').is_file() and (downloads/'community_APKINDEX').is_file()
    # These are our frozen earlier build inputs; every selected archive must exist.
    for packages in [['build-base', 'vim'], ['zsh', 'vim'] + (['libuuid'] if arch=='amd64' else [])]:
        argv = ['python3', str(ROOT/'build-support/alpine-resolve.py'),
                '--index', 'main', str(downloads/'main_APKINDEX'),
                '--index', 'community', str(downloads/'community_APKINDEX'), *packages]
        for line in subprocess.check_output(argv, text=True).splitlines():
            repository, name = line.split('\t')
            assert (downloads/name).is_file(), 'Missing cached package: '+name
    assert any(downloads.glob('oh-my-zsh-*.tar.gz'))
    (target/'downloads').symlink_to(downloads, target_is_directory=True)
    if arch=='amd64':
        archive = PRIOR/arch/'alpine-minirootfs-3.21.7-x86_64.tar.gz'
        assert archive.is_file()
        (target/archive.name).symlink_to(archive)
    else:
        assert (downloads/'alpine-minirootfs-3.21.7-aarch64.tar.gz').is_file()
    return target

def run(arch):
    assert sha(ROOT/'build-support/musl/malloc-retain.patch') == PATCH_SHA
    target = setup(arch)
    prefix = 'VINIX_AMD64' if arch=='amd64' else 'VINIX_AARCH64'
    script = ROOT/('build-userland-'+arch+'.sh')
    settings = {prefix+'_USERLAND_BUILD_DIR': str(target),
                prefix+'_INITRAMFS': str(target/'initramfs.tar'),
                'VINIX_MUSL_BUILD_DIR': str(CACHE), 'VINIX_MUSL_RETAIN':'1',
                'VINIX_OPTIMIZED_MUSL':'1', 'VINIX_ALPINE_DEVTOOLS':'1',
                'VINIX_ALPINE_BASE_ONLY':'1', 'NPROC':'2',
                'ALPINE_VERSION':'3.21.7', 'ALPINE_BRANCH':'v3.21'}
    inputs = {'builder':str(script), 'builder_sha256':sha(script),
              'stage_helper_sha256':sha(ROOT/'build-support/musl/stage.py'),
              'settings':settings}
    (target/'inputs.json').write_text(json.dumps(inputs, indent=2)+'\n')
    with (target/'builder.log').open('wb') as out:
        subprocess.run([str(script)], env=dict(os.environ, **settings),
                       cwd=ROOT, check=True, stdout=out, stderr=out)
    stage = target/'staging'
    machine = 'x86_64' if arch=='amd64' else 'aarch64'
    manifest = json.loads((stage/'usr/share/vinix/musl-build.json').read_text())
    assert manifest['arch']==machine and manifest['retention']==1
    assert manifest['optimize']=='internal,malloc,malloc/mallocng/*.c,string'
    assert next(x['sha256'] for x in manifest['patches'] if x['name']=='malloc-retain.patch')==PATCH_SHA
    assert '(GCC) 14.2.0' in manifest['compiler_version']
    expected = [('lib/ld-musl-'+machine+'.so.1','libc_so_sha256'),
                ('usr/lib/libc.a','libc_a_sha256')]
    for name, field in expected: assert sha(stage/name)==manifest[field]
    assert (stage/'usr/include/malloc.h').is_file()
    assert 'int malloc_trim(size_t);' in (stage/'usr/include/malloc.h').read_text()
    assert os.readlink(stage/'usr/lib/libc.so')=='../../lib/ld-musl-'+machine+'.so.1'
    archive = target/'initramfs.tar'
    with tarfile.open(archive) as tar:
        for name, field in expected:
            assert hashlib.sha256(tar.extractfile('./'+name).read()).hexdigest()==manifest[field]
        assert json.load(tar.extractfile('./usr/share/vinix/musl-build.json'))==manifest
    assert sha(script)==inputs['builder_sha256']
    result = {'status':'PASS', 'arch':arch, 'inputs':inputs,
              'libc_build':manifest, 'initramfs_sha256':sha(archive),
              'builder_log_sha256':sha(target/'builder.log')}
    (target/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Production v3 packaging PASS',arch,target/'results.json',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch',choices=['amd64','aarch64','both'],default='both')
    args=parser.parse_args()
    for arch in (['amd64','aarch64'] if args.arch=='both' else [args.arch]): run(arch)
