project('vos', 'c', license: 'GPL3')

v = find_program('v')
nasm = find_program('nasm')

nasm_gen = generator(nasm,
    output: '@BASENAME@.o',
    arguments: ['-g', '-F', 'dwarf', '-f', 'elf64', '@INPUT@', '-o', '@OUTPUT@'])

k_cflags =  ['-g', '-O2', '-std=gnu99', '-masm=intel', '-ffreestanding', '-z', 'max-page-size=0x1000', 
    '-mno-red-zone', '-mno-mmx', '-mno-sse', '-mno-sse2', '-no-pie', '-fno-pic', '-mcmodel=kernel',
    '-fno-stack-protector', '-std=gnu99', '-I' + meson.source_root() + '/../vore']

k_ldflags = ['-z', 'max-page-size=0x1000', '-no-pie', '-ffreestanding', '-nostdlib', '-lgcc', 
    '-T', meson.source_root() + '/arch/amd64/link.ld']

k_objs = []
k_mods = []

c_src = [
    '../vore/vrt_impl.c',
    'vrt_main.c',
]

asm_src = [
    'arch/amd64/init.asm',
    'arch/amd64/io.asm'
]

v_modules = [
    ['io', ['io.v']],
    ['sys', ['debug.v', 'kmain.v']],
    ['mm', ['paging.v']],
]

foreach mod : v_modules
    name = 'v_' + mod[0].underscorify()
    input = []
    foreach file : mod[1]
        input += mod[0] + '/' + file
    endforeach
    output = name + '.gen.c'
    #k_deps += name
    k_objs += custom_target(name,
        command: [v, '-verbose', '-freestanding', '-vlib-path', meson.source_root() + '/../vore/vlib', '-vpath', meson.source_root(), '-o', meson.current_build_dir() + '/@OUTPUT@', 'build', 'module', meson.source_root() + '/' + mod[0]],
        input: files(input),
        output: output
    )
endforeach

k_objs += c_src
k_objs += nasm_gen.process(asm_src)

shared_library('kernel',
    k_objs,
    c_args: k_cflags,
    link_args: k_ldflags,
    name_prefix: '',
    name_suffix: 'elf')