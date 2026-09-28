module keyboard

const max_keycode = 57

// Keys the drivers treat on their own, as Linux keycodes (which PS/2 set 1
// scancodes match for these).
pub const key_space = u8(57)
pub const key_102nd = u8(86)

// iso_key is what the ISO key between left Shift and Z types. The US layout
// has no character for it, so it types the § and ± Apple's US layout prints
// there: that names the key uniquely, and the desktop's keyboard layouts put
// their own characters (< > | for most of Europe) on it.
pub fn iso_key(shift bool) &char {
	return if shift { c'\xc2\xb1' } else { c'\xc2\xa7' }
}

const convtab_nomod = [
	`\0`,
	`\e`,
	`1`,
	`2`,
	`3`,
	`4`,
	`5`,
	`6`,
	`7`,
	`8`,
	`9`,
	`0`,
	`-`,
	`=`,
	`\b`,
	`\t`,
	`q`,
	`w`,
	`e`,
	`r`,
	`t`,
	`y`,
	`u`,
	`i`,
	`o`,
	`p`,
	`[`,
	`]`,
	`\n`,
	`\0`,
	`a`,
	`s`,
	`d`,
	`f`,
	`g`,
	`h`,
	`j`,
	`k`,
	`l`,
	`;`,
	`'`,
	`\``,
	`\0`,
	`\\`,
	`z`,
	`x`,
	`c`,
	`v`,
	`b`,
	`n`,
	`m`,
	`,`,
	`.`,
	`/`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

const convtab_shift = [
	`\0`,
	`\e`,
	`!`,
	`@`,
	`#`,
	`$`,
	`%`,
	`^`,
	`&`,
	`*`,
	`(`,
	`)`,
	`_`,
	`+`,
	`\b`,
	`\t`,
	`Q`,
	`W`,
	`E`,
	`R`,
	`T`,
	`Y`,
	`U`,
	`I`,
	`O`,
	`P`,
	`{`,
	`}`,
	`\n`,
	`\0`,
	`A`,
	`S`,
	`D`,
	`F`,
	`G`,
	`H`,
	`J`,
	`K`,
	`L`,
	`:`,
	`"`,
	`~`,
	`\0`,
	`|`,
	`Z`,
	`X`,
	`C`,
	`V`,
	`B`,
	`N`,
	`M`,
	`<`,
	`>`,
	`?`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

const convtab_capslock = [
	`\0`,
	`\e`,
	`1`,
	`2`,
	`3`,
	`4`,
	`5`,
	`6`,
	`7`,
	`8`,
	`9`,
	`0`,
	`-`,
	`=`,
	`\b`,
	`\t`,
	`Q`,
	`W`,
	`E`,
	`R`,
	`T`,
	`Y`,
	`U`,
	`I`,
	`O`,
	`P`,
	`[`,
	`]`,
	`\n`,
	`\0`,
	`A`,
	`S`,
	`D`,
	`F`,
	`G`,
	`H`,
	`J`,
	`K`,
	`L`,
	`;`,
	`'`,
	`\``,
	`\0`,
	`\\`,
	`Z`,
	`X`,
	`C`,
	`V`,
	`B`,
	`N`,
	`M`,
	`,`,
	`.`,
	`/`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

const convtab_shift_capslock = [
	`\0`,
	`\e`,
	`!`,
	`@`,
	`#`,
	`$`,
	`%`,
	`^`,
	`&`,
	`*`,
	`(`,
	`)`,
	`_`,
	`+`,
	`\b`,
	`\t`,
	`q`,
	`w`,
	`e`,
	`r`,
	`t`,
	`y`,
	`u`,
	`i`,
	`o`,
	`p`,
	`{`,
	`}`,
	`\n`,
	`\0`,
	`a`,
	`s`,
	`d`,
	`f`,
	`g`,
	`h`,
	`j`,
	`k`,
	`l`,
	`:`,
	`"`,
	`~`,
	`\0`,
	`|`,
	`z`,
	`x`,
	`c`,
	`v`,
	`b`,
	`n`,
	`m`,
	`<`,
	`>`,
	`?`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

pub fn translate(code u8, shift bool, capslock bool, ctrl bool) u8 {
	if code > max_keycode {
		return 0
	}
	idx := int(code)
	mut c := u8(0)
	if !capslock && !shift {
		c = convtab_nomod[idx]
	} else if !capslock && shift {
		c = convtab_shift[idx]
	} else if capslock && !shift {
		c = convtab_capslock[idx]
	} else {
		c = convtab_shift_capslock[idx]
	}
	if c == 0 {
		return 0
	}
	if ctrl {
		mut upper := c
		if upper >= u8(`a`) && upper <= u8(`z`) {
			upper = upper - 32
		}
		if upper >= 0x40 && upper <= 0x5f {
			c = upper - 0x40
		}
	}
	return c
}
