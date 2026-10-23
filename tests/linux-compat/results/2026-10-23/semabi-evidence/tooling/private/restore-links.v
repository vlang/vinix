import os

fn main() {
    for suffix in ['arm', 'x86'] {
        target := '/Users/alex/.cache/vinix-linux-compat/semabi-20261023/kernel-' + suffix + '/kernel/'
        for name in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi', 'c/nanoprintf.h'] {
            if !os.exists(target + name) { os.symlink('/Users/alex/code/vinix/kernel/' + name, target + name)! }
        }
        os.rmdir('/Users/alex/.cache/vinix-linux-compat/semabi-20261023/kernel-' + suffix + '.build-lock')!
    }
}
