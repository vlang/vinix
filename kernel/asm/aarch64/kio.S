// Width-exact MMIO accessors.
//
// V's inline assembler renders an operand as `%[name]`, and on AArch64 a bare
// operand always prints as the 64-bit register: only `%w[name]` yields the
// 32-bit view, and V has no way to write that. So `ldr ret, [addr]` with a u32
// result assembled to `ldr xN, [xM]`: an 8-byte access. At a 4-byte-aligned
// device register that is a misaligned Device-memory access, which real
// hardware reports as an alignment fault (DFSC 0x21); QEMU forgave it. Even
// when aligned it touches the neighbouring register. These routines pin the
// access width by naming the register class explicitly.
//
// Barriers are the caller's business (kio.v adds dmb ish around each access).
.section .text

.globl vinix_mmio_read8
.type vinix_mmio_read8, %function
vinix_mmio_read8:
    ldrb w0, [x0]
    ret

.globl vinix_mmio_read16
.type vinix_mmio_read16, %function
vinix_mmio_read16:
    ldrh w0, [x0]
    ret

.globl vinix_mmio_read32
.type vinix_mmio_read32, %function
vinix_mmio_read32:
    ldr w0, [x0]
    ret

.globl vinix_mmio_read64
.type vinix_mmio_read64, %function
vinix_mmio_read64:
    ldr x0, [x0]
    ret

.globl vinix_mmio_write8
.type vinix_mmio_write8, %function
vinix_mmio_write8:
    strb w1, [x0]
    ret

.globl vinix_mmio_write16
.type vinix_mmio_write16, %function
vinix_mmio_write16:
    strh w1, [x0]
    ret

.globl vinix_mmio_write32
.type vinix_mmio_write32, %function
vinix_mmio_write32:
    str w1, [x0]
    ret

.globl vinix_mmio_write64
.type vinix_mmio_write64, %function
vinix_mmio_write64:
    str x1, [x0]
    ret

// Width-exact acquire/release atomics for the same reason: LDAR/STLR must be
// naturally aligned for their register width, so an x-register access to a
// 32-bit field is either a fault or an 8-byte clobber.
.globl vinix_ldar32
.type vinix_ldar32, %function
vinix_ldar32:
    ldar w0, [x0]
    ret

.globl vinix_ldar64
.type vinix_ldar64, %function
vinix_ldar64:
    ldar x0, [x0]
    ret

.globl vinix_stlr32
.type vinix_stlr32, %function
vinix_stlr32:
    stlr w1, [x0]
    ret

.globl vinix_stlr64
.type vinix_stlr64, %function
vinix_stlr64:
    stlr x1, [x0]
    ret

.globl vinix_ldar8
.type vinix_ldar8, %function
vinix_ldar8:
    ldarb w0, [x0]
    ret

.globl vinix_ldar16
.type vinix_ldar16, %function
vinix_ldar16:
    ldarh w0, [x0]
    ret

.globl vinix_stlr8
.type vinix_stlr8, %function
vinix_stlr8:
    stlrb w1, [x0]
    ret

.globl vinix_stlr16
.type vinix_stlr16, %function
vinix_stlr16:
    stlrh w1, [x0]
    ret

// Width-exact LSE read-modify-write atomics. Each returns the OLD value.
// x0 = address, x1/w1 = operand (and for CAS: x1/w1 = expected, x2/w2 = new).

.globl vinix_ldadd32
.type vinix_ldadd32, %function
vinix_ldadd32:
    ldaddal w1, w0, [x0]
    ret

.globl vinix_ldadd64
.type vinix_ldadd64, %function
vinix_ldadd64:
    ldaddal x1, x0, [x0]
    ret

.globl vinix_ldset32
.type vinix_ldset32, %function
vinix_ldset32:
    ldsetal w1, w0, [x0]
    ret

.globl vinix_ldset64
.type vinix_ldset64, %function
vinix_ldset64:
    ldsetal x1, x0, [x0]
    ret

.globl vinix_ldclr32
.type vinix_ldclr32, %function
vinix_ldclr32:
    ldclral w1, w0, [x0]
    ret

.globl vinix_ldclr64
.type vinix_ldclr64, %function
vinix_ldclr64:
    ldclral x1, x0, [x0]
    ret

// Compare-and-swap: returns the value observed (== expected on success).
.globl vinix_cas32
.type vinix_cas32, %function
vinix_cas32:
    cas w1, w2, [x0]
    mov w0, w1
    ret

.globl vinix_cas64
.type vinix_cas64, %function
vinix_cas64:
    cas x1, x2, [x0]
    mov x0, x1
    ret

.globl vinix_casa32
.type vinix_casa32, %function
vinix_casa32:
    casa w1, w2, [x0]
    mov w0, w1
    ret

.globl vinix_casa64
.type vinix_casa64, %function
vinix_casa64:
    casa x1, x2, [x0]
    mov x0, x1
    ret
