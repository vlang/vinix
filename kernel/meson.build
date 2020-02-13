project('kernel', 'c', license: 'GPL3')

v = find_program('v')
nasm = find_program('nasm')

nasm_gen = generator(nasm,
    output: '@BASENAME@.o',
    arguments: ['-f', 'elf64', '@INPUT@', '-o', '@OUTPUT@'])

k_cflags =  ['-g', '-O2', '-std=gnu99', '-masm=intel', '-ffreestanding', '-z', 'max-page-size=0x1000', 
    '-mno-red-zone', '-mno-mmx', '-mno-sse', '-mno-sse2', '-no-pie', '-fno-pic', '-mcmodel=kernel',
    '-fno-stack-protector', '-std=gnu99', '-I' + meson.source_root() + '/../vrt',
    '-I' + meson.source_root() + '/../3rdparty/acpica/include']

k_ldflags = ['-z', 'max-page-size=0x1000', '-no-pie', '-ffreestanding', '-nostdlib', '-lgcc', 
    '-T', meson.source_root() + '/arch/amd64/link.ld']

k_objs = []
k_mods = []

c_src = [
    '../vrt/vrt_impl.c',
    'vrt_main.c',
]

asm_src = [
    'arch/amd64/init.asm',
    'arch/amd64/interrupt.asm',
    'arch/amd64/io.asm',
    'arch/amd64/paging.asm'
]

v_modules = [
    ['acpi', ['acpi.v']],
    ['debug', ['debug.v']],
    ['io', ['io.v']],
    ['libtinyalloc', ['tiny_alloc.v']],
    ['sync', ['mutex.v']],
    ['sys', [
        'boot_x64.v', 'callbacks.v', 'cmdline.v', 'debug_x64.v', 'fbcon.v', 'framebuffer.v', 
        'kern_devices.v', 'kmain.v', 'multiboot2_x64.v', 'paging.v', 'panic.v',
        'uefi.v', 'util.v', 'version.v'
    ]],
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
        command: [v, '-verbose', '-freestanding', '--enable-globals', 
            '-vlib-path', meson.source_root() + '/../vrt/vlib', 
            '-vpath', meson.source_root(), 
            '-o', meson.current_build_dir() + '/@OUTPUT@', 
            'build', 'module', meson.source_root() + '/' + mod[0]],
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
