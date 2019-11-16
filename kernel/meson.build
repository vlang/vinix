project('vos', 'c',
    license: 'GPL3')

v = find_program('v')
nasm = find_program('nasm')

nasm_gen = generator(nasm,
    output: '@BASENAME@.o',
    arguments: ['-g', '-F', 'dwarf', '-f', 'elf64', '@INPUT@', '-o', '@OUTPUT@'])

k_cflags =  ['-g', '-O2', '-std=gnu99', '-masm=intel', '-ffreestanding', '-mcmodel=large', '-z', 'max-page-size=0x1000', '-mno-red-zone', '-mno-mmx', '-mno-sse', '-mno-sse2', '-no-pie', '-fno-pic', '-mcmodel=kernel', '-fno-stack-protector']
k_ldflags = ['-z', 'max-page-size=0x1000', '-no-pie', '-ffreestanding', '-nostdlib', '-lgcc', '-T', meson.source_root() + '/arch/amd64/link.ld']

k_objs = []
k_mods = []

c_src = [
    'sys/v_runtime.c'
]

asm_src = [
    'arch/amd64/init.asm',
    'arch/amd64/io.asm'
]

v_modules = [
    'sys',
    'mm',
]

k_objs += c_src
k_objs += nasm_gen.process(asm_src)

foreach mod : v_modules
    k_mods += meson.source_root() + '/' + mod
endforeach

k_objs += custom_target('vkernel',
    command: [v, '-bare', '-o', meson.current_build_dir() + '/meson-out/vkernel.c', 'build', 'module'] + k_mods,
    output: 'vkernel.c'
)

shared_library('kernel',
    k_objs,
    c_args: k_cflags,
    link_args: k_ldflags,
    name_prefix: '',
    name_suffix: 'elf')