module acpi

[packed]
pub struct Fadt {
pub:
	header               SDT
	firmware_ctrl        u32
	dsdt                 u32

	// Field no longer in use, for compatibility only.
	reserved            u8
}