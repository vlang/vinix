project('vos', 'c',
    license: 'GPL3')

v = find_program('v')
nasm = find_program('nasm')

v_gen = generator(v,
    output: '@BASENAME@.c',
    arguments: ['-bare', 'build', '@INPUT@', '-o', '@OUTPUT@'])

nasm_gen = generator(nasm,
    output: '@BASENAME@.o',
    arguments: ['-f', 'elf64', '@INPUT@', '-o', '@OUTPUT@'])

objs = []

asm_src = [
    'arch/amd64/init.asm'
]
v_modules = [
    'init'
]

objs += nasm_gen.process(asm_src)

foreach mod : v_modules
    output = meson.current_build_dir() + '/' + mod.underscorify() + '.c'
    objs += output
    run_command(
        v,
        '-bare',
        '-o',
        output,
        'build',
        'module',
        mod
    )
endforeach

shared_library('kernel',
    objs,
    name_prefix: '',
    name_suffix: 'elf')

