import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const root = '/Users/alex/code/vinix'
const destination = root + '/tests/linux-compat/results/2026-10-23/semabi-evidence'

struct Manifest {
mut:
    files map[string]string
    origins map[string]string
    omitted map[string]string
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn copy_file(source string, relative string, mut manifest Manifest) ! {
    target := destination + '/' + relative
    os.mkdir_all(os.dir(target))!
    os.cp(source, target)!
    pin := digest(source)!
    if digest(target)! != pin { return error('Copy changed: ' + source) }
    manifest.files[relative] = pin
    manifest.origins[source] = relative
}

fn directory(source string, relative string, mut manifest Manifest) ! {
    for path in os.walk_ext(source, '') {
        if !os.is_file(path) { continue }
        name := path[source.len + 1..]
        if name.ends_with('.iso') || name.ends_with('initramfs.tar') || name.ends_with('initramfs.cpio')
            || name == 'linux' || name.ends_with('.qcow2') || name.contains('/limine/') { continue }
        copy_file(path, relative + '/' + name, mut manifest)!
    }
}

fn pins(path string, mut manifest Manifest) ! {
    values := json2.decode[map[string]string](os.read_file(path)!)!
    for origin, pin in values {
        if origin !in manifest.origins {
            if previous := manifest.omitted[origin] { if previous != pin { return error('Conflicting external pin: ' + origin) } }
            manifest.omitted[origin] = pin
        }
    }
}

fn main() {
    assert !os.exists(destination), 'Fresh destination required'
    mut manifest := Manifest{}
    for suffix in ['arm', 'x86'] {
        for pair in [['compile-final1-', 'compile'], ['baseline-final1-', 'baseline'],
            ['reference-maintained1-', 'reference'], ['candidate-integration1-', 'native'],
            ['wait-integration1-', 'wait']] {
            state := area + '/states/' + pair[0] + suffix
            directory(state, suffix + '/' + pair[1], mut manifest)!
        }
        maintained := if suffix == 'arm' {
            '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/sa3'
        } else { area + '/states/maintained-integration2-x86' }
        directory(maintained, suffix + '/maintained', mut manifest)!
        if suffix == 'arm' {
            directory(area + '/states/maintained-integration1-arm', 'attempts/maintained-path-arm', mut manifest)!
            directory('/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/semabi-maintained-integration2-arm', 'attempts/maintained-socket-arm', mut manifest)!
        }
        if suffix == 'x86' {
            directory(area + '/states/maintained-integration1-x86', 'attempts/maintained-first-x86', mut manifest)!
        }
        build := area + '/states/kernel-integration4-' + suffix + '-prod'
        directory(build, suffix + '/build', mut manifest)!
    }
    directory(area + '/frozen-final1', 'source/fixture', mut manifest)!
    directory(area + '/draft-width', 'attempts/draft-width/source', mut manifest)!
    for suffix in ['arm', 'x86'] {
        directory(area + '/states/kernel-integration3-' + suffix + '-prod',
            'attempts/draft-width/' + suffix, mut manifest)!
    }
    copy_file(area + '/sysvsem-candidate.v', 'source/sysvsem.v', mut manifest)!
    copy_file(area + '/integration-source.diff', 'source/change.diff', mut manifest)!
    copy_file(area + '/prepared-source-inputs.json', 'source/identity.json', mut manifest)!
    for name in ['generated-review.json', 'generated-review-arm.c.txt', 'generated-review-x86.c.txt'] {
        copy_file(area + '/' + name, 'review/' + name, mut manifest)!
    }
    for name in ['semabi-reference.v', 'semabi-evidence.v', 'run.v'] {
        copy_file(root + '/tests/linux-compat/' + name, 'tooling/' + name, mut manifest)!
    }
    for name in ['semwait-evidence.v'] {
        copy_file(root + '/tests/linux-compat/' + name, 'tooling/' + name, mut manifest)!
    }
    copy_file(area + '/storage-check',
        'tooling/semwait-evidence', mut manifest)!
    copy_file(area + '/report.md', 'README.md', mut manifest)!
    for name in ['compile.v', 'native.v', 'native-wait.v', 'reference.v', 'build-kernels.v',
        'prepare-integration.v', 'correct-width.v', 'restore-links.v', 'freeze.v', 'review-generated.v',
        'maintained-native.v', 'maintained-arm3.v', 'publish.v'] {
        copy_file(area + '/' + name, 'tooling/private/' + name, mut manifest)!
    }
    // Every retained input/output receipt is either resolvable inside this
    // bundle or explicitly listed as an external content pin.
    for suffix in ['arm', 'x86'] {
        path := destination + '/' + suffix
        for name in ['inputs_before', 'inputs_after', 'outputs'] {
            object := json2.decode[map[string]json2.Any](os.read_file(path + '/build/receipt.json')!)!
            temporary := area + '/publish-' + suffix + '-' + name + '.json'
            os.write_file(temporary, json2.encode(object[name]))!
            pins(temporary, mut manifest)!
        }
        for kind in ['baseline', 'native', 'wait'] {
            object := json2.decode[map[string]json2.Any](os.read_file(path + '/' + kind + '/receipt.json')!)!
            temporary := area + '/publish-' + suffix + '-' + kind + '.json'
            os.write_file(temporary, json2.encode(object['inputs']))!
            pins(temporary, mut manifest)!
        }
        pins(path + '/reference/inputs.json', mut manifest)!
        pins(path + '/maintained/controller-inputs.json', mut manifest)!
        compile := json2.decode[map[string]json2.Any](os.read_file(path + '/compile/receipt.json')!)!
        for name in ['inputs', 'outputs'] {
            temporary := area + '/publish-' + suffix + '-compile-' + name + '.json'
            os.write_file(temporary, json2.encode(compile[name]))!
            pins(temporary, mut manifest)!
        }
    }
    for path in os.walk_ext(area, '') {
        if os.dir(path) == area && (path.ends_with('.log') || path.ends_with('.status') || path.ends_with('.command.json')) {
            copy_file(path, 'attempts/' + os.file_name(path), mut manifest)!
        }
    }
    os.write_file(destination + '/manifest.json', json2.encode(manifest, prettify: true) + '\n')!
    println('Published ' + manifest.files.len.str() + ' artifacts; ' + manifest.omitted.len.str() + ' external pins')
}
