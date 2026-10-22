// SPDX-License-Identifier: GPL-2.0-or-later
// MS-FSCC 2.5.1 FILE_FS_ATTRIBUTE_INFORMATION.
module smb2

pub fn (mut c Client) volume_readonly() ?bool {
	id := c.create('', 0x80, 1, true)?
	defer { c.close(id) or {} }
	c.header(16, 40)
	put16(c.tx, 64, 41)
	unsafe {
		c.tx[66] = 2
		c.tx[67] = 5
	}
	put32(c.tx, 68, 512)
	fid_put(c.tx, 88, id)
	c.success(16, 104, 72, 9)?
	offset := int(get16(c.rx, 66))
	length := get32(c.rx, 68)
	if length < 12 || length > 512 || offset < 72 || !span(c.response_len, offset, int(length)) {
		c.broken()
		return none
	}
	name_length := get32(c.rx, offset + 8)
	if name_length % 2 != 0 || name_length > length - 12 {
		c.broken()
		return none
	}
	return get32(c.rx, offset) & 0x00080000 != 0
}
