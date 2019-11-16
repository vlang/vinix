
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_entry)

PAGE_SIZE  = 0x1000;
KERNEL_VMA = 0xFFFFFFFF80000000;
UPPER_MEM  = 0x100000;

SECTIONS
{
  .multiboot :
  {
    *(.multiboot)
  }

  . = UPPER_MEM;

  .initl :
  {
    *(.initl)
  }

  .init_data :
  {
    *(.init_data)
  }
  
  _start = . + KERNEL_VMA;

  . += KERNEL_VMA;

  .text ALIGN(PAGE_SIZE) : AT(ADDR(.text) - KERNEL_VMA)
  {
    *(.inith)
    *(.text)
  }

  .data ALIGN(PAGE_SIZE) : AT(ADDR(.data) - KERNEL_VMA)
  {
    *(.data)
  }

  .rodata ALIGN(PAGE_SIZE) : AT(ADDR(.rodata) - KERNEL_VMA)
  {
    *(.rodata)
  }

  .bss ALIGN(PAGE_SIZE) : AT(ADDR(.bss) - KERNEL_VMA)
  {
    *(.bss)
  }

  _end = .;

  /DISCARD/ :
  {
    *(.comment)
  }
}