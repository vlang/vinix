// SPDX-License-Identifier: GPL-2.0-or-later
module ioscontroller

import androidhost as ah

fn images(mut f Frame) !string {
	mut t := Temps{}
	defer { t.clear() or {} }
	// Original line 79: original = (fixtures / "calculator").read_bytes()
	e1 := t.hold(f.load('fixtures')!)
	e2 := t.hold(literal(ah.Value('calculator'))!)
	e3 := t.hold(operation('truediv', [e1, e2]) or {
		t.drop(e1)!
		t.drop(e2)!
		return err
	})
	t.drop(e1)!
	t.drop(e2)!
	e4 := t.hold(member(e3, 'read_bytes') or {
		t.drop(e3)!
		return err
	})
	t.drop(e3)!
	e5 := t.hold(invoke_owned(e4, [], {}, [])!)
	t.take(e4)
	f.named('original', t.take(e5))!
	t.clear()!
	// Original line 80: arm64e = bytearray(original)
	e6 := t.hold(global('bytearray')!)
	e7 := t.hold(f.load('original')!)
	e8 := t.hold(invoke_owned(e6, [o(e7)], {}, [e7])!)
	t.take(e6)
	t.take(e7)
	f.named('arm64e', t.take(e8))!
	t.clear()!
	// Original line 81: struct.pack_into("<I", arm64e, 8, 2)
	e9 := t.hold(global('struct')!)
	e10 := t.hold(member(e9, 'pack_into') or {
		t.drop(e9)!
		return err
	})
	t.drop(e9)!
	e11 := t.hold(literal(ah.Value('<I'))!)
	e12 := t.hold(f.load('arm64e')!)
	e13 := t.hold(literal(ah.Value(i64(8)))!)
	e14 := t.hold(literal(ah.Value(i64(2)))!)
	e15 := t.hold(invoke_owned(e10, [o(e11), o(e12), o(e13), o(e14)], {}, [e14, e13, e12, e11])!)
	t.take(e10)
	t.take(e11)
	t.take(e12)
	t.take(e13)
	t.take(e14)
	t.drop(e15)!
	t.clear()!
	// Original line 82: (destination / "calculator-arm64e").write_bytes(arm64e)
	e16 := t.hold(f.load('destination')!)
	e17 := t.hold(literal(ah.Value('calculator-arm64e'))!)
	e18 := t.hold(operation('truediv', [e16, e17]) or {
		t.drop(e16)!
		t.drop(e17)!
		return err
	})
	t.drop(e16)!
	t.drop(e17)!
	e19 := t.hold(member(e18, 'write_bytes') or {
		t.drop(e18)!
		return err
	})
	t.drop(e18)!
	e20 := t.hold(f.load('arm64e')!)
	e21 := t.hold(invoke_owned(e19, [o(e20)], {}, [e20])!)
	t.take(e19)
	t.take(e20)
	t.drop(e21)!
	t.clear()!
	// Original line 83: (destination / "truncated").write_bytes(original[:31])
	e22 := t.hold(f.load('destination')!)
	e23 := t.hold(literal(ah.Value('truncated'))!)
	e24 := t.hold(operation('truediv', [e22, e23]) or {
		t.drop(e22)!
		t.drop(e23)!
		return err
	})
	t.drop(e22)!
	t.drop(e23)!
	e25 := t.hold(member(e24, 'write_bytes') or {
		t.drop(e24)!
		return err
	})
	t.drop(e24)!
	e26 := t.hold(f.load('original')!)
	e27 := t.hold(literal(none_())!)
	e28 := t.hold(literal(ah.Value(i64(31)))!)
	e29 := t.hold(literal(none_())!)
	e30 := t.hold(resolve('_SLICE')!)
	e31 := t.hold(invoke_owned(e30, [o(e27), o(e28), o(e29)], {}, [e29, e28, e27])!)
	t.take(e30)
	t.take(e27)
	t.take(e28)
	t.take(e29)
	e32 := t.hold(operation('getitem', [e26, e31]) or {
		t.drop(e26)!
		t.drop(e31)!
		return err
	})
	t.drop(e26)!
	t.drop(e31)!
	e33 := t.hold(invoke_owned(e25, [o(e32)], {}, [e32])!)
	t.take(e25)
	t.take(e32)
	t.drop(e33)!
	t.clear()!
	// Original line 84: second = (4096 + len(original) + 4095) & ~4095
	e34 := t.hold(literal(ah.Value(i64(4096)))!)
	e35 := t.hold(global('len')!)
	e36 := t.hold(f.load('original')!)
	e37 := t.hold(invoke_owned(e35, [o(e36)], {}, [e36])!)
	t.take(e35)
	t.take(e36)
	e38 := t.hold(operation('add', [e34, e37]) or {
		t.drop(e34)!
		t.drop(e37)!
		return err
	})
	t.drop(e34)!
	t.drop(e37)!
	e39 := t.hold(literal(ah.Value(i64(4095)))!)
	e40 := t.hold(operation('add', [e38, e39]) or {
		t.drop(e38)!
		t.drop(e39)!
		return err
	})
	t.drop(e38)!
	t.drop(e39)!
	e41 := t.hold(literal(ah.Value(i64(4095)))!)
	e42 := t.hold(operation('invert', [e41]) or {
		t.drop(e41)!
		return err
	})
	t.drop(e41)!
	e43 := t.hold(operation('and_', [e40, e42]) or {
		t.drop(e40)!
		t.drop(e42)!
		return err
	})
	t.drop(e40)!
	t.drop(e42)!
	f.named('second', t.take(e43))!
	t.clear()!
	// Original line 85: fat = bytearray(second + len(original))
	e44 := t.hold(global('bytearray')!)
	e45 := t.hold(f.load('second')!)
	e46 := t.hold(global('len')!)
	e47 := t.hold(f.load('original')!)
	e48 := t.hold(invoke_owned(e46, [o(e47)], {}, [e47])!)
	t.take(e46)
	t.take(e47)
	e49 := t.hold(operation('add', [e45, e48]) or {
		t.drop(e45)!
		t.drop(e48)!
		return err
	})
	t.drop(e45)!
	t.drop(e48)!
	e50 := t.hold(invoke_owned(e44, [o(e49)], {}, [e49])!)
	t.take(e44)
	t.take(e49)
	f.named('fat', t.take(e50))!
	t.clear()!
	// Original line 86: struct.pack_into(">II", fat, 0, 0xCAFEBABE, 2)
	e51 := t.hold(global('struct')!)
	e52 := t.hold(member(e51, 'pack_into') or {
		t.drop(e51)!
		return err
	})
	t.drop(e51)!
	e53 := t.hold(literal(ah.Value('>II'))!)
	e54 := t.hold(f.load('fat')!)
	e55 := t.hold(literal(ah.Value(i64(0)))!)
	e56 := t.hold(literal(ah.Value(i64(3405691582)))!)
	e57 := t.hold(literal(ah.Value(i64(2)))!)
	e58 := t.hold(invoke_owned(e52, [o(e53), o(e54), o(e55), o(e56), o(e57)], {}, [
		e57,
		e56,
		e55,
		e54,
		e53,
	])!)
	t.take(e52)
	t.take(e53)
	t.take(e54)
	t.take(e55)
	t.take(e56)
	t.take(e57)
	t.drop(e58)!
	t.clear()!
	// Original line 87: struct.pack_into(">IIIII", fat, 8, 0x100000C, 2, 4096, len(arm64e), 12)
	e59 := t.hold(global('struct')!)
	e60 := t.hold(member(e59, 'pack_into') or {
		t.drop(e59)!
		return err
	})
	t.drop(e59)!
	e61 := t.hold(literal(ah.Value('>IIIII'))!)
	e62 := t.hold(f.load('fat')!)
	e63 := t.hold(literal(ah.Value(i64(8)))!)
	e64 := t.hold(literal(ah.Value(i64(16777228)))!)
	e65 := t.hold(literal(ah.Value(i64(2)))!)
	e66 := t.hold(literal(ah.Value(i64(4096)))!)
	e67 := t.hold(global('len')!)
	e68 := t.hold(f.load('arm64e')!)
	e69 := t.hold(invoke_owned(e67, [o(e68)], {}, [e68])!)
	t.take(e67)
	t.take(e68)
	e70 := t.hold(literal(ah.Value(i64(12)))!)
	e71 := t.hold(invoke_owned(e60, [o(e61), o(e62), o(e63), o(e64), o(e65), o(e66), o(e69), o(e70)], {}, [
		e70,
		e69,
		e66,
		e65,
		e64,
		e63,
		e62,
		e61,
	])!)
	t.take(e60)
	t.take(e61)
	t.take(e62)
	t.take(e63)
	t.take(e64)
	t.take(e65)
	t.take(e66)
	t.take(e69)
	t.take(e70)
	t.drop(e71)!
	t.clear()!
	// Original line 88: struct.pack_into(">IIIII", fat, 28, 0x100000C, 0, second, len(original), 12)
	e72 := t.hold(global('struct')!)
	e73 := t.hold(member(e72, 'pack_into') or {
		t.drop(e72)!
		return err
	})
	t.drop(e72)!
	e74 := t.hold(literal(ah.Value('>IIIII'))!)
	e75 := t.hold(f.load('fat')!)
	e76 := t.hold(literal(ah.Value(i64(28)))!)
	e77 := t.hold(literal(ah.Value(i64(16777228)))!)
	e78 := t.hold(literal(ah.Value(i64(0)))!)
	e79 := t.hold(f.load('second')!)
	e80 := t.hold(global('len')!)
	e81 := t.hold(f.load('original')!)
	e82 := t.hold(invoke_owned(e80, [o(e81)], {}, [e81])!)
	t.take(e80)
	t.take(e81)
	e83 := t.hold(literal(ah.Value(i64(12)))!)
	e84 := t.hold(invoke_owned(e73, [o(e74), o(e75), o(e76), o(e77), o(e78), o(e79), o(e82), o(e83)], {}, [
		e83,
		e82,
		e79,
		e78,
		e77,
		e76,
		e75,
		e74,
	])!)
	t.take(e73)
	t.take(e74)
	t.take(e75)
	t.take(e76)
	t.take(e77)
	t.take(e78)
	t.take(e79)
	t.take(e82)
	t.take(e83)
	t.drop(e84)!
	t.clear()!
	// Original line 89: fat[4096:4096 + len(arm64e)] = arm64e
	e85 := t.hold(f.load('arm64e')!)
	e86 := t.hold(f.load('fat')!)
	e87 := t.hold(literal(ah.Value(i64(4096)))!)
	e88 := t.hold(literal(ah.Value(i64(4096)))!)
	e89 := t.hold(global('len')!)
	e90 := t.hold(f.load('arm64e')!)
	e91 := t.hold(invoke_owned(e89, [o(e90)], {}, [e90])!)
	t.take(e89)
	t.take(e90)
	e92 := t.hold(operation('add', [e88, e91]) or {
		t.drop(e88)!
		t.drop(e91)!
		return err
	})
	t.drop(e88)!
	t.drop(e91)!
	e93 := t.hold(literal(none_())!)
	e94 := t.hold(resolve('_SLICE')!)
	e95 := t.hold(invoke_owned(e94, [o(e87), o(e92), o(e93)], {}, [e93, e92, e87])!)
	t.take(e94)
	t.take(e87)
	t.take(e92)
	t.take(e93)
	release([operation('setitem', [e86, e95, e85]) or {
		t.drop(e85)!
		t.drop(e86)!
		t.drop(e95)!
		return err
	}])!
	t.drop(e85)!
	t.drop(e86)!
	t.drop(e95)!
	t.clear()!
	// Original line 90: fat[second:] = original
	e96 := t.hold(f.load('original')!)
	e97 := t.hold(f.load('fat')!)
	e98 := t.hold(f.load('second')!)
	e99 := t.hold(literal(none_())!)
	e100 := t.hold(literal(none_())!)
	e101 := t.hold(resolve('_SLICE')!)
	e102 := t.hold(invoke_owned(e101, [o(e98), o(e99), o(e100)], {}, [e100, e99, e98])!)
	t.take(e101)
	t.take(e98)
	t.take(e99)
	t.take(e100)
	release([operation('setitem', [e97, e102, e96]) or {
		t.drop(e96)!
		t.drop(e97)!
		t.drop(e102)!
		return err
	}])!
	t.drop(e96)!
	t.drop(e97)!
	t.drop(e102)!
	t.clear()!
	// Original line 91: (destination / "calculator-fat").write_bytes(fat)
	e103 := t.hold(f.load('destination')!)
	e104 := t.hold(literal(ah.Value('calculator-fat'))!)
	e105 := t.hold(operation('truediv', [e103, e104]) or {
		t.drop(e103)!
		t.drop(e104)!
		return err
	})
	t.drop(e103)!
	t.drop(e104)!
	e106 := t.hold(member(e105, 'write_bytes') or {
		t.drop(e105)!
		return err
	})
	t.drop(e105)!
	e107 := t.hold(f.load('fat')!)
	e108 := t.hold(invoke_owned(e106, [o(e107)], {}, [e107])!)
	t.take(e106)
	t.take(e107)
	t.drop(e108)!
	t.clear()!
	return literal(none_())!
}

fn plan(mut f Frame) !string {
	mut t := Temps{}
	defer { t.clear() or {} }
	// Original line 116: if arguments.timeout <= 0:
	e1 := t.hold(f.load('arguments')!)
	e2 := t.hold(member(e1, 'timeout') or {
		t.drop(e1)!
		return err
	})
	t.drop(e1)!
	e3 := t.hold(literal(ah.Value(i64(0)))!)
	e4 := t.hold(operation('le', [e2, e3]) or {
		t.drop(e2)!
		t.drop(e3)!
		return err
	})
	t.drop(e2)!
	t.drop(e3)!
	b5 := truth(e4) or {
		t.drop(e4)!
		return err
	}
	t.drop(e4)!
	if b5 {
		// Original line 117: parser.error("timeout must be positive")
		e6 := t.hold(f.load('parser')!)
		e7 := t.hold(member(e6, 'error') or {
			t.drop(e6)!
			return err
		})
		t.drop(e6)!
		e8 := t.hold(literal(ah.Value('timeout must be positive'))!)
		e9 := t.hold(invoke_owned(e7, [o(e8)], {}, [e8])!)
		t.take(e7)
		t.take(e8)
		t.drop(e9)!
		t.clear()!
	}
	t.clear()!
	// Original line 118: if arguments.with_ppsspp and not arguments.with_cxx:
	e11 := t.hold(f.load('arguments')!)
	e12 := t.hold(member(e11, 'with_ppsspp') or {
		t.drop(e11)!
		return err
	})
	t.drop(e11)!
	b13 := truth(e12) or {
		t.drop(e12)!
		return err
	}
	t.drop(e12)!
	mut b10 := b13
	if b10 {
		e14 := t.hold(f.load('arguments')!)
		e15 := t.hold(member(e14, 'with_cxx') or {
			t.drop(e14)!
			return err
		})
		t.drop(e14)!
		b16 := truth(e15) or {
			t.drop(e15)!
			return err
		}
		t.drop(e15)!
		b10 = !b16
	}
	if b10 {
		// Original line 119: parser.error("--with-ppsspp requires --with-cxx for PPSSPP's native C++ runtime")
		e17 := t.hold(f.load('parser')!)
		e18 := t.hold(member(e17, 'error') or {
			t.drop(e17)!
			return err
		})
		t.drop(e17)!
		e19 := t.hold(literal(ah.Value("--with-ppsspp requires --with-cxx for PPSSPP's native C++ runtime"))!)
		e20 := t.hold(invoke_owned(e18, [o(e19)], {}, [e19])!)
		t.take(e18)
		t.take(e19)
		t.drop(e20)!
		t.clear()!
	}
	t.clear()!
	// Original line 120: if arguments.ppsspp_muted and not (arguments.with_ppsspp and arguments.with_gles):
	e22 := t.hold(f.load('arguments')!)
	e23 := t.hold(member(e22, 'ppsspp_muted') or {
		t.drop(e22)!
		return err
	})
	t.drop(e22)!
	b24 := truth(e23) or {
		t.drop(e23)!
		return err
	}
	t.drop(e23)!
	mut b21 := b24
	if b21 {
		e26 := t.hold(f.load('arguments')!)
		e27 := t.hold(member(e26, 'with_ppsspp') or {
			t.drop(e26)!
			return err
		})
		t.drop(e26)!
		b28 := truth(e27) or {
			t.drop(e27)!
			return err
		}
		t.drop(e27)!
		mut b25 := b28
		if b25 {
			e29 := t.hold(f.load('arguments')!)
			e30 := t.hold(member(e29, 'with_gles') or {
				t.drop(e29)!
				return err
			})
			t.drop(e29)!
			b31 := truth(e30) or {
				t.drop(e30)!
				return err
			}
			t.drop(e30)!
			b25 = b31
		}
		b21 = !b25
	}
	if b21 {
		// Original line 121: parser.error("--ppsspp-muted requires --with-ppsspp and --with-gles")
		e32 := t.hold(f.load('parser')!)
		e33 := t.hold(member(e32, 'error') or {
			t.drop(e32)!
			return err
		})
		t.drop(e32)!
		e34 := t.hold(literal(ah.Value('--ppsspp-muted requires --with-ppsspp and --with-gles'))!)
		e35 := t.hold(invoke_owned(e33, [o(e34)], {}, [e34])!)
		t.take(e33)
		t.take(e34)
		t.drop(e35)!
		t.clear()!
	}
	t.clear()!
	// Original line 122: if arguments.ppsspp_cube and not arguments.ppsspp_muted:
	e37 := t.hold(f.load('arguments')!)
	e38 := t.hold(member(e37, 'ppsspp_cube') or {
		t.drop(e37)!
		return err
	})
	t.drop(e37)!
	b39 := truth(e38) or {
		t.drop(e38)!
		return err
	}
	t.drop(e38)!
	mut b36 := b39
	if b36 {
		e40 := t.hold(f.load('arguments')!)
		e41 := t.hold(member(e40, 'ppsspp_muted') or {
			t.drop(e40)!
			return err
		})
		t.drop(e40)!
		b42 := truth(e41) or {
			t.drop(e41)!
			return err
		}
		t.drop(e41)!
		b36 = !b42
	}
	if b36 {
		// Original line 123: parser.error("--ppsspp-cube requires --ppsspp-muted")
		e43 := t.hold(f.load('parser')!)
		e44 := t.hold(member(e43, 'error') or {
			t.drop(e43)!
			return err
		})
		t.drop(e43)!
		e45 := t.hold(literal(ah.Value('--ppsspp-cube requires --ppsspp-muted'))!)
		e46 := t.hold(invoke_owned(e44, [o(e45)], {}, [e45])!)
		t.take(e44)
		t.take(e45)
		t.drop(e46)!
		t.clear()!
	}
	t.clear()!
	// Original line 124: if arguments.ppsspp_nzp and (not arguments.ppsspp_muted or arguments.ppsspp_cube):
	e48 := t.hold(f.load('arguments')!)
	e49 := t.hold(member(e48, 'ppsspp_nzp') or {
		t.drop(e48)!
		return err
	})
	t.drop(e48)!
	b50 := truth(e49) or {
		t.drop(e49)!
		return err
	}
	t.drop(e49)!
	mut b47 := b50
	if b47 {
		e52 := t.hold(f.load('arguments')!)
		e53 := t.hold(member(e52, 'ppsspp_muted') or {
			t.drop(e52)!
			return err
		})
		t.drop(e52)!
		b54 := truth(e53) or {
			t.drop(e53)!
			return err
		}
		t.drop(e53)!
		mut b51 := !b54
		if !b51 {
			e55 := t.hold(f.load('arguments')!)
			e56 := t.hold(member(e55, 'ppsspp_cube') or {
				t.drop(e55)!
				return err
			})
			t.drop(e55)!
			b57 := truth(e56) or {
				t.drop(e56)!
				return err
			}
			t.drop(e56)!
			b51 = b57
		}
		b47 = b51
	}
	if b47 {
		// Original line 125: parser.error("--ppsspp-nzp requires --ppsspp-muted and cannot be combined with --ppsspp-cube")
		e58 := t.hold(f.load('parser')!)
		e59 := t.hold(member(e58, 'error') or {
			t.drop(e58)!
			return err
		})
		t.drop(e58)!
		e60 := t.hold(literal(ah.Value('--ppsspp-nzp requires --ppsspp-muted and cannot be combined with --ppsspp-cube'))!)
		e61 := t.hold(invoke_owned(e59, [o(e60)], {}, [e60])!)
		t.take(e59)
		t.take(e60)
		t.drop(e61)!
		t.clear()!
	}
	t.clear()!
	// Original line 126: if arguments.ppsspp_gow and (not arguments.ppsspp_muted or arguments.ppsspp_cube or arguments.ppsspp_nzp):
	e63 := t.hold(f.load('arguments')!)
	e64 := t.hold(member(e63, 'ppsspp_gow') or {
		t.drop(e63)!
		return err
	})
	t.drop(e63)!
	b65 := truth(e64) or {
		t.drop(e64)!
		return err
	}
	t.drop(e64)!
	mut b62 := b65
	if b62 {
		e67 := t.hold(f.load('arguments')!)
		e68 := t.hold(member(e67, 'ppsspp_muted') or {
			t.drop(e67)!
			return err
		})
		t.drop(e67)!
		b69 := truth(e68) or {
			t.drop(e68)!
			return err
		}
		t.drop(e68)!
		mut b66 := !b69
		if !b66 {
			e70 := t.hold(f.load('arguments')!)
			e71 := t.hold(member(e70, 'ppsspp_cube') or {
				t.drop(e70)!
				return err
			})
			t.drop(e70)!
			b72 := truth(e71) or {
				t.drop(e71)!
				return err
			}
			t.drop(e71)!
			b66 = b72
		}
		if !b66 {
			e73 := t.hold(f.load('arguments')!)
			e74 := t.hold(member(e73, 'ppsspp_nzp') or {
				t.drop(e73)!
				return err
			})
			t.drop(e73)!
			b75 := truth(e74) or {
				t.drop(e74)!
				return err
			}
			t.drop(e74)!
			b66 = b75
		}
		b62 = b66
	}
	if b62 {
		// Original line 127: parser.error("--ppsspp-gow requires --ppsspp-muted and cannot be combined with another PSP game")
		e76 := t.hold(f.load('parser')!)
		e77 := t.hold(member(e76, 'error') or {
			t.drop(e76)!
			return err
		})
		t.drop(e76)!
		e78 := t.hold(literal(ah.Value('--ppsspp-gow requires --ppsspp-muted and cannot be combined with another PSP game'))!)
		e79 := t.hold(invoke_owned(e77, [o(e78)], {}, [e78])!)
		t.take(e77)
		t.take(e78)
		t.drop(e79)!
		t.clear()!
	}
	t.clear()!
	// Original line 128: build = Path(os.environ.get("VINIX_IOS_BUILD_DIR", ROOT / "build/ios"))
	e80 := t.hold(global('Path')!)
	e81 := t.hold(global('os')!)
	e82 := t.hold(member(e81, 'environ') or {
		t.drop(e81)!
		return err
	})
	t.drop(e81)!
	e83 := t.hold(member(e82, 'get') or {
		t.drop(e82)!
		return err
	})
	t.drop(e82)!
	e84 := t.hold(literal(ah.Value('VINIX_IOS_BUILD_DIR'))!)
	e85 := t.hold(global('ROOT')!)
	e86 := t.hold(literal(ah.Value('build/ios'))!)
	e87 := t.hold(operation('truediv', [e85, e86]) or {
		t.drop(e85)!
		t.drop(e86)!
		return err
	})
	t.drop(e85)!
	t.drop(e86)!
	e88 := t.hold(invoke_owned(e83, [o(e84), o(e87)], {}, [e87, e84])!)
	t.take(e83)
	t.take(e84)
	t.take(e87)
	e89 := t.hold(invoke_owned(e80, [o(e88)], {}, [e88])!)
	t.take(e80)
	t.take(e88)
	f.named('build', t.take(e89))!
	t.clear()!
	// Original line 129: if not arguments.no_build:
	e90 := t.hold(f.load('arguments')!)
	e91 := t.hold(member(e90, 'no_build') or {
		t.drop(e90)!
		return err
	})
	t.drop(e90)!
	b92 := truth(e91) or {
		t.drop(e91)!
		return err
	}
	t.drop(e91)!
	if !b92 {
		// Original line 130: subprocess.run(["bash", str(ROOT / "scripts/build-ios-aarch64.sh")]
		e93 := t.hold(global('subprocess')!)
		e94 := t.hold(member(e93, 'run') or {
			t.drop(e93)!
			return err
		})
		t.drop(e93)!
		e95 := t.hold(literal(ah.Value('bash'))!)
		e96 := t.hold(global('str')!)
		e97 := t.hold(global('ROOT')!)
		e98 := t.hold(literal(ah.Value('scripts/build-ios-aarch64.sh'))!)
		e99 := t.hold(operation('truediv', [e97, e98]) or {
			t.drop(e97)!
			t.drop(e98)!
			return err
		})
		t.drop(e97)!
		t.drop(e98)!
		e100 := t.hold(invoke_owned(e96, [o(e99)], {}, [e99])!)
		t.take(e96)
		t.take(e99)
		e101 := t.hold(resolve('_list')!)
		e102 := t.hold(invoke_owned(e101, [o(e95), o(e100)], {}, [e100, e95])!)
		t.take(e101)
		t.take(e95)
		t.take(e100)
		mut e103 := ''
		e104 := t.hold(f.load('arguments')!)
		e105 := t.hold(member(e104, 'with_cxx') or {
			t.drop(e104)!
			return err
		})
		t.drop(e104)!
		b106 := truth(e105) or {
			t.drop(e105)!
			return err
		}
		t.drop(e105)!
		if b106 {
			e107 := t.hold(literal(ah.Value('--with-cxx'))!)
			e108 := t.hold(resolve('_list')!)
			e109 := t.hold(invoke_owned(e108, [o(e107)], {}, [e107])!)
			t.take(e108)
			t.take(e107)
			e103 = e109
		} else {
			e110 := t.hold(resolve('_list')!)
			e111 := t.hold(invoke_owned(e110, [], {}, [])!)
			t.take(e110)
			e103 = e111
		}
		e112 := t.hold(operation('add', [e102, e103]) or {
			t.drop(e102)!
			t.drop(e103)!
			return err
		})
		t.drop(e102)!
		t.drop(e103)!
		mut e113 := ''
		e114 := t.hold(f.load('arguments')!)
		e115 := t.hold(member(e114, 'with_gles') or {
			t.drop(e114)!
			return err
		})
		t.drop(e114)!
		b116 := truth(e115) or {
			t.drop(e115)!
			return err
		}
		t.drop(e115)!
		if b116 {
			e117 := t.hold(literal(ah.Value('--with-gles'))!)
			e118 := t.hold(resolve('_list')!)
			e119 := t.hold(invoke_owned(e118, [o(e117)], {}, [e117])!)
			t.take(e118)
			t.take(e117)
			e113 = e119
		} else {
			e120 := t.hold(resolve('_list')!)
			e121 := t.hold(invoke_owned(e120, [], {}, [])!)
			t.take(e120)
			e113 = e121
		}
		e122 := t.hold(operation('add', [e112, e113]) or {
			t.drop(e112)!
			t.drop(e113)!
			return err
		})
		t.drop(e112)!
		t.drop(e113)!
		e123 := t.hold(literal(ah.Value(true))!)
		e124 := t.hold(invoke_owned(e94, [o(e122)], {
			'check': o(e123)
		}, [e123, e122])!)
		t.take(e94)
		t.take(e122)
		t.take(e123)
		t.drop(e124)!
		t.clear()!
	}
	t.clear()!
	// Original line 133: subprocess.run(["sh", str(ROOT / "tests/ios/build-fixture.sh"), str(build / "fixtures")], check=True)
	e125 := t.hold(global('subprocess')!)
	e126 := t.hold(member(e125, 'run') or {
		t.drop(e125)!
		return err
	})
	t.drop(e125)!
	e127 := t.hold(literal(ah.Value('sh'))!)
	e128 := t.hold(global('str')!)
	e129 := t.hold(global('ROOT')!)
	e130 := t.hold(literal(ah.Value('tests/ios/build-fixture.sh'))!)
	e131 := t.hold(operation('truediv', [e129, e130]) or {
		t.drop(e129)!
		t.drop(e130)!
		return err
	})
	t.drop(e129)!
	t.drop(e130)!
	e132 := t.hold(invoke_owned(e128, [o(e131)], {}, [e131])!)
	t.take(e128)
	t.take(e131)
	e133 := t.hold(global('str')!)
	e134 := t.hold(f.load('build')!)
	e135 := t.hold(literal(ah.Value('fixtures'))!)
	e136 := t.hold(operation('truediv', [e134, e135]) or {
		t.drop(e134)!
		t.drop(e135)!
		return err
	})
	t.drop(e134)!
	t.drop(e135)!
	e137 := t.hold(invoke_owned(e133, [o(e136)], {}, [e136])!)
	t.take(e133)
	t.take(e136)
	e138 := t.hold(resolve('_list')!)
	e139 := t.hold(invoke_owned(e138, [o(e127), o(e132), o(e137)], {}, [e137, e132, e127])!)
	t.take(e138)
	t.take(e127)
	t.take(e132)
	t.take(e137)
	e140 := t.hold(literal(ah.Value(true))!)
	e141 := t.hold(invoke_owned(e126, [o(e139)], {
		'check': o(e140)
	}, [e140, e139])!)
	t.take(e126)
	t.take(e139)
	t.take(e140)
	t.drop(e141)!
	t.clear()!
	// Original line 134: if arguments.with_cxx:
	e142 := t.hold(f.load('arguments')!)
	e143 := t.hold(member(e142, 'with_cxx') or {
		t.drop(e142)!
		return err
	})
	t.drop(e142)!
	b144 := truth(e143) or {
		t.drop(e143)!
		return err
	}
	t.drop(e143)!
	if b144 {
		// Original line 135: subprocess.run(["bash", str(ROOT / "tests/ios/build-cxx-fixture.sh"), str(build / "fixtures")], check=True)
		e145 := t.hold(global('subprocess')!)
		e146 := t.hold(member(e145, 'run') or {
			t.drop(e145)!
			return err
		})
		t.drop(e145)!
		e147 := t.hold(literal(ah.Value('bash'))!)
		e148 := t.hold(global('str')!)
		e149 := t.hold(global('ROOT')!)
		e150 := t.hold(literal(ah.Value('tests/ios/build-cxx-fixture.sh'))!)
		e151 := t.hold(operation('truediv', [e149, e150]) or {
			t.drop(e149)!
			t.drop(e150)!
			return err
		})
		t.drop(e149)!
		t.drop(e150)!
		e152 := t.hold(invoke_owned(e148, [o(e151)], {}, [e151])!)
		t.take(e148)
		t.take(e151)
		e153 := t.hold(global('str')!)
		e154 := t.hold(f.load('build')!)
		e155 := t.hold(literal(ah.Value('fixtures'))!)
		e156 := t.hold(operation('truediv', [e154, e155]) or {
			t.drop(e154)!
			t.drop(e155)!
			return err
		})
		t.drop(e154)!
		t.drop(e155)!
		e157 := t.hold(invoke_owned(e153, [o(e156)], {}, [e156])!)
		t.take(e153)
		t.take(e156)
		e158 := t.hold(resolve('_list')!)
		e159 := t.hold(invoke_owned(e158, [o(e147), o(e152), o(e157)], {}, [e157, e152, e147])!)
		t.take(e158)
		t.take(e147)
		t.take(e152)
		t.take(e157)
		e160 := t.hold(literal(ah.Value(true))!)
		e161 := t.hold(invoke_owned(e146, [o(e159)], {
			'check': o(e160)
		}, [e160, e159])!)
		t.take(e146)
		t.take(e159)
		t.take(e160)
		t.drop(e161)!
		t.clear()!
		// Original line 136: subprocess.run(["bash", str(ROOT / "tests/ios/build-cxx-native.sh"), str(build / "fixtures")], check=True)
		e162 := t.hold(global('subprocess')!)
		e163 := t.hold(member(e162, 'run') or {
			t.drop(e162)!
			return err
		})
		t.drop(e162)!
		e164 := t.hold(literal(ah.Value('bash'))!)
		e165 := t.hold(global('str')!)
		e166 := t.hold(global('ROOT')!)
		e167 := t.hold(literal(ah.Value('tests/ios/build-cxx-native.sh'))!)
		e168 := t.hold(operation('truediv', [e166, e167]) or {
			t.drop(e166)!
			t.drop(e167)!
			return err
		})
		t.drop(e166)!
		t.drop(e167)!
		e169 := t.hold(invoke_owned(e165, [o(e168)], {}, [e168])!)
		t.take(e165)
		t.take(e168)
		e170 := t.hold(global('str')!)
		e171 := t.hold(f.load('build')!)
		e172 := t.hold(literal(ah.Value('fixtures'))!)
		e173 := t.hold(operation('truediv', [e171, e172]) or {
			t.drop(e171)!
			t.drop(e172)!
			return err
		})
		t.drop(e171)!
		t.drop(e172)!
		e174 := t.hold(invoke_owned(e170, [o(e173)], {}, [e173])!)
		t.take(e170)
		t.take(e173)
		e175 := t.hold(resolve('_list')!)
		e176 := t.hold(invoke_owned(e175, [o(e164), o(e169), o(e174)], {}, [e174, e169, e164])!)
		t.take(e175)
		t.take(e164)
		t.take(e169)
		t.take(e174)
		e177 := t.hold(literal(ah.Value(true))!)
		e178 := t.hold(invoke_owned(e163, [o(e176)], {
			'check': o(e177)
		}, [e177, e176])!)
		t.take(e163)
		t.take(e176)
		t.take(e177)
		t.drop(e178)!
		t.clear()!
	}
	t.clear()!
	// Original line 137: if arguments.with_gles:
	e179 := t.hold(f.load('arguments')!)
	e180 := t.hold(member(e179, 'with_gles') or {
		t.drop(e179)!
		return err
	})
	t.drop(e179)!
	b181 := truth(e180) or {
		t.drop(e180)!
		return err
	}
	t.drop(e180)!
	if b181 {
		// Original line 138: subprocess.run(["bash", str(ROOT / "tests/ios/build-gles-fixture.sh"), str(build / "fixtures")], check=True)
		e182 := t.hold(global('subprocess')!)
		e183 := t.hold(member(e182, 'run') or {
			t.drop(e182)!
			return err
		})
		t.drop(e182)!
		e184 := t.hold(literal(ah.Value('bash'))!)
		e185 := t.hold(global('str')!)
		e186 := t.hold(global('ROOT')!)
		e187 := t.hold(literal(ah.Value('tests/ios/build-gles-fixture.sh'))!)
		e188 := t.hold(operation('truediv', [e186, e187]) or {
			t.drop(e186)!
			t.drop(e187)!
			return err
		})
		t.drop(e186)!
		t.drop(e187)!
		e189 := t.hold(invoke_owned(e185, [o(e188)], {}, [e188])!)
		t.take(e185)
		t.take(e188)
		e190 := t.hold(global('str')!)
		e191 := t.hold(f.load('build')!)
		e192 := t.hold(literal(ah.Value('fixtures'))!)
		e193 := t.hold(operation('truediv', [e191, e192]) or {
			t.drop(e191)!
			t.drop(e192)!
			return err
		})
		t.drop(e191)!
		t.drop(e192)!
		e194 := t.hold(invoke_owned(e190, [o(e193)], {}, [e193])!)
		t.take(e190)
		t.take(e193)
		e195 := t.hold(resolve('_list')!)
		e196 := t.hold(invoke_owned(e195, [o(e184), o(e189), o(e194)], {}, [e194, e189, e184])!)
		t.take(e195)
		t.take(e184)
		t.take(e189)
		t.take(e194)
		e197 := t.hold(literal(ah.Value(true))!)
		e198 := t.hold(invoke_owned(e183, [o(e196)], {
			'check': o(e197)
		}, [e197, e196])!)
		t.take(e183)
		t.take(e196)
		t.take(e197)
		t.drop(e198)!
		t.clear()!
	}
	t.clear()!
	// Original line 139: subprocess.run(["bash", str(ROOT / "examples/ios-calculator/build.sh")],
	e199 := t.hold(global('subprocess')!)
	e200 := t.hold(member(e199, 'run') or {
		t.drop(e199)!
		return err
	})
	t.drop(e199)!
	e201 := t.hold(literal(ah.Value('bash'))!)
	e202 := t.hold(global('str')!)
	e203 := t.hold(global('ROOT')!)
	e204 := t.hold(literal(ah.Value('examples/ios-calculator/build.sh'))!)
	e205 := t.hold(operation('truediv', [e203, e204]) or {
		t.drop(e203)!
		t.drop(e204)!
		return err
	})
	t.drop(e203)!
	t.drop(e204)!
	e206 := t.hold(invoke_owned(e202, [o(e205)], {}, [e205])!)
	t.take(e202)
	t.take(e205)
	e207 := t.hold(resolve('_list')!)
	e208 := t.hold(invoke_owned(e207, [o(e201), o(e206)], {}, [e206, e201])!)
	t.take(e207)
	t.take(e201)
	t.take(e206)
	e209 := t.hold(global('os')!)
	e210 := t.hold(member(e209, 'environ') or {
		t.drop(e209)!
		return err
	})
	t.drop(e209)!
	e211 := t.hold(resolve('_mapping')!)
	e212 := t.hold(invoke_owned(e211, [o(e210)], {}, [e210])!)
	t.take(e211)
	t.take(e210)
	e213 := t.hold(literal(ah.Value('VINIX_IOS_CALCULATOR_BUILD_DIR'))!)
	e214 := t.hold(global('str')!)
	e215 := t.hold(f.load('build')!)
	e216 := t.hold(literal(ah.Value('objc'))!)
	e217 := t.hold(operation('truediv', [e215, e216]) or {
		t.drop(e215)!
		t.drop(e216)!
		return err
	})
	t.drop(e215)!
	t.drop(e216)!
	e218 := t.hold(invoke_owned(e214, [o(e217)], {}, [e217])!)
	t.take(e214)
	t.take(e217)
	release([operation('setitem', [e212, e213, e218])!])!
	t.drop(e218)!
	t.drop(e213)!
	e219 := t.hold(literal(ah.Value(true))!)
	e220 := t.hold(invoke_owned(e200, [o(e208)], {
		'env':   o(e212)
		'check': o(e219)
	}, [e219, e212, e208])!)
	t.take(e200)
	t.take(e208)
	t.take(e212)
	t.take(e219)
	t.drop(e220)!
	t.clear()!
	// Original line 141: if arguments.with_2048:
	e221 := t.hold(f.load('arguments')!)
	e222 := t.hold(member(e221, 'with_2048') or {
		t.drop(e221)!
		return err
	})
	t.drop(e221)!
	b223 := truth(e222) or {
		t.drop(e222)!
		return err
	}
	t.drop(e222)!
	if b223 {
		// Original line 142: env = {**os.environ, "VINIX_IOS_2048_BUILD_DIR": str(build / "2048")}
		e224 := t.hold(global('os')!)
		e225 := t.hold(member(e224, 'environ') or {
			t.drop(e224)!
			return err
		})
		t.drop(e224)!
		e226 := t.hold(resolve('_mapping')!)
		e227 := t.hold(invoke_owned(e226, [o(e225)], {}, [e225])!)
		t.take(e226)
		t.take(e225)
		e228 := t.hold(literal(ah.Value('VINIX_IOS_2048_BUILD_DIR'))!)
		e229 := t.hold(global('str')!)
		e230 := t.hold(f.load('build')!)
		e231 := t.hold(literal(ah.Value('2048'))!)
		e232 := t.hold(operation('truediv', [e230, e231]) or {
			t.drop(e230)!
			t.drop(e231)!
			return err
		})
		t.drop(e230)!
		t.drop(e231)!
		e233 := t.hold(invoke_owned(e229, [o(e232)], {}, [e232])!)
		t.take(e229)
		t.take(e232)
		release([operation('setitem', [e227, e228, e233])!])!
		t.drop(e233)!
		t.drop(e228)!
		f.named('env', t.take(e227))!
		t.clear()!
		// Original line 143: subprocess.run(["bash", str(ROOT / "examples/ios-2048/build.sh")], env=env, check=True)
		e234 := t.hold(global('subprocess')!)
		e235 := t.hold(member(e234, 'run') or {
			t.drop(e234)!
			return err
		})
		t.drop(e234)!
		e236 := t.hold(literal(ah.Value('bash'))!)
		e237 := t.hold(global('str')!)
		e238 := t.hold(global('ROOT')!)
		e239 := t.hold(literal(ah.Value('examples/ios-2048/build.sh'))!)
		e240 := t.hold(operation('truediv', [e238, e239]) or {
			t.drop(e238)!
			t.drop(e239)!
			return err
		})
		t.drop(e238)!
		t.drop(e239)!
		e241 := t.hold(invoke_owned(e237, [o(e240)], {}, [e240])!)
		t.take(e237)
		t.take(e240)
		e242 := t.hold(resolve('_list')!)
		e243 := t.hold(invoke_owned(e242, [o(e236), o(e241)], {}, [e241, e236])!)
		t.take(e242)
		t.take(e236)
		t.take(e241)
		e244 := t.hold(f.load('env')!)
		e245 := t.hold(literal(ah.Value(true))!)
		e246 := t.hold(invoke_owned(e235, [o(e243)], {
			'env':   o(e244)
			'check': o(e245)
		}, [e245, e244, e243])!)
		t.take(e235)
		t.take(e243)
		t.take(e244)
		t.take(e245)
		t.drop(e246)!
		t.clear()!
		// Original line 144: subprocess.run(["bash", str(ROOT / "tests/ios/build-2048-model.sh")], env=env, check=True)
		e247 := t.hold(global('subprocess')!)
		e248 := t.hold(member(e247, 'run') or {
			t.drop(e247)!
			return err
		})
		t.drop(e247)!
		e249 := t.hold(literal(ah.Value('bash'))!)
		e250 := t.hold(global('str')!)
		e251 := t.hold(global('ROOT')!)
		e252 := t.hold(literal(ah.Value('tests/ios/build-2048-model.sh'))!)
		e253 := t.hold(operation('truediv', [e251, e252]) or {
			t.drop(e251)!
			t.drop(e252)!
			return err
		})
		t.drop(e251)!
		t.drop(e252)!
		e254 := t.hold(invoke_owned(e250, [o(e253)], {}, [e253])!)
		t.take(e250)
		t.take(e253)
		e255 := t.hold(resolve('_list')!)
		e256 := t.hold(invoke_owned(e255, [o(e249), o(e254)], {}, [e254, e249])!)
		t.take(e255)
		t.take(e249)
		t.take(e254)
		e257 := t.hold(f.load('env')!)
		e258 := t.hold(literal(ah.Value(true))!)
		e259 := t.hold(invoke_owned(e248, [o(e256)], {
			'env':   o(e257)
			'check': o(e258)
		}, [e258, e257, e256])!)
		t.take(e248)
		t.take(e256)
		t.take(e257)
		t.take(e258)
		t.drop(e259)!
		t.clear()!
	}
	t.clear()!
	// Original line 145: if arguments.with_ppsspp or arguments.with_gles:
	e261 := t.hold(f.load('arguments')!)
	e262 := t.hold(member(e261, 'with_ppsspp') or {
		t.drop(e261)!
		return err
	})
	t.drop(e261)!
	b263 := truth(e262) or {
		t.drop(e262)!
		return err
	}
	t.drop(e262)!
	mut b260 := b263
	if !b260 {
		e264 := t.hold(f.load('arguments')!)
		e265 := t.hold(member(e264, 'with_gles') or {
			t.drop(e264)!
			return err
		})
		t.drop(e264)!
		b266 := truth(e265) or {
			t.drop(e265)!
			return err
		}
		t.drop(e265)!
		b260 = b266
	}
	if b260 {
		// Original line 146: subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download.py"),
		e267 := t.hold(global('subprocess')!)
		e268 := t.hold(member(e267, 'run') or {
			t.drop(e267)!
			return err
		})
		t.drop(e267)!
		e269 := t.hold(literal(ah.Value('python3'))!)
		e270 := t.hold(global('str')!)
		e271 := t.hold(global('ROOT')!)
		e272 := t.hold(literal(ah.Value('examples/ios-ppsspp/download.py'))!)
		e273 := t.hold(operation('truediv', [e271, e272]) or {
			t.drop(e271)!
			t.drop(e272)!
			return err
		})
		t.drop(e271)!
		t.drop(e272)!
		e274 := t.hold(invoke_owned(e270, [o(e273)], {}, [e273])!)
		t.take(e270)
		t.take(e273)
		e275 := t.hold(literal(ah.Value('--output'))!)
		e276 := t.hold(global('str')!)
		e277 := t.hold(f.load('build')!)
		e278 := t.hold(literal(ah.Value('ppsspp'))!)
		e279 := t.hold(operation('truediv', [e277, e278]) or {
			t.drop(e277)!
			t.drop(e278)!
			return err
		})
		t.drop(e277)!
		t.drop(e278)!
		e280 := t.hold(invoke_owned(e276, [o(e279)], {}, [e279])!)
		t.take(e276)
		t.take(e279)
		e281 := t.hold(resolve('_list')!)
		e282 := t.hold(invoke_owned(e281, [o(e269), o(e274), o(e275), o(e280)], {}, [
			e280,
			e275,
			e274,
			e269,
		])!)
		t.take(e281)
		t.take(e269)
		t.take(e274)
		t.take(e275)
		t.take(e280)
		e283 := t.hold(literal(ah.Value(true))!)
		e284 := t.hold(invoke_owned(e268, [o(e282)], {
			'check': o(e283)
		}, [e283, e282])!)
		t.take(e268)
		t.take(e282)
		t.take(e283)
		t.drop(e284)!
		t.clear()!
	}
	t.clear()!
	// Original line 148: if arguments.ppsspp_cube:
	e285 := t.hold(f.load('arguments')!)
	e286 := t.hold(member(e285, 'ppsspp_cube') or {
		t.drop(e285)!
		return err
	})
	t.drop(e285)!
	b287 := truth(e286) or {
		t.drop(e286)!
		return err
	}
	t.drop(e286)!
	if b287 {
		// Original line 149: subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download-cube.py"),
		e288 := t.hold(global('subprocess')!)
		e289 := t.hold(member(e288, 'run') or {
			t.drop(e288)!
			return err
		})
		t.drop(e288)!
		e290 := t.hold(literal(ah.Value('python3'))!)
		e291 := t.hold(global('str')!)
		e292 := t.hold(global('ROOT')!)
		e293 := t.hold(literal(ah.Value('examples/ios-ppsspp/download-cube.py'))!)
		e294 := t.hold(operation('truediv', [e292, e293]) or {
			t.drop(e292)!
			t.drop(e293)!
			return err
		})
		t.drop(e292)!
		t.drop(e293)!
		e295 := t.hold(invoke_owned(e291, [o(e294)], {}, [e294])!)
		t.take(e291)
		t.take(e294)
		e296 := t.hold(literal(ah.Value('--output'))!)
		e297 := t.hold(global('str')!)
		e298 := t.hold(f.load('build')!)
		e299 := t.hold(literal(ah.Value('ppsspp/cube.pbp'))!)
		e300 := t.hold(operation('truediv', [e298, e299]) or {
			t.drop(e298)!
			t.drop(e299)!
			return err
		})
		t.drop(e298)!
		t.drop(e299)!
		e301 := t.hold(invoke_owned(e297, [o(e300)], {}, [e300])!)
		t.take(e297)
		t.take(e300)
		e302 := t.hold(resolve('_list')!)
		e303 := t.hold(invoke_owned(e302, [o(e290), o(e295), o(e296), o(e301)], {}, [
			e301,
			e296,
			e295,
			e290,
		])!)
		t.take(e302)
		t.take(e290)
		t.take(e295)
		t.take(e296)
		t.take(e301)
		e304 := t.hold(literal(ah.Value(true))!)
		e305 := t.hold(invoke_owned(e289, [o(e303)], {
			'check': o(e304)
		}, [e304, e303])!)
		t.take(e289)
		t.take(e303)
		t.take(e304)
		t.drop(e305)!
		t.clear()!
	}
	t.clear()!
	// Original line 151: if arguments.ppsspp_nzp:
	e306 := t.hold(f.load('arguments')!)
	e307 := t.hold(member(e306, 'ppsspp_nzp') or {
		t.drop(e306)!
		return err
	})
	t.drop(e306)!
	b308 := truth(e307) or {
		t.drop(e307)!
		return err
	}
	t.drop(e307)!
	if b308 {
		// Original line 152: subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download-nzp.py"),
		e309 := t.hold(global('subprocess')!)
		e310 := t.hold(member(e309, 'run') or {
			t.drop(e309)!
			return err
		})
		t.drop(e309)!
		e311 := t.hold(literal(ah.Value('python3'))!)
		e312 := t.hold(global('str')!)
		e313 := t.hold(global('ROOT')!)
		e314 := t.hold(literal(ah.Value('examples/ios-ppsspp/download-nzp.py'))!)
		e315 := t.hold(operation('truediv', [e313, e314]) or {
			t.drop(e313)!
			t.drop(e314)!
			return err
		})
		t.drop(e313)!
		t.drop(e314)!
		e316 := t.hold(invoke_owned(e312, [o(e315)], {}, [e315])!)
		t.take(e312)
		t.take(e315)
		e317 := t.hold(literal(ah.Value('--output'))!)
		e318 := t.hold(global('str')!)
		e319 := t.hold(f.load('build')!)
		e320 := t.hold(literal(ah.Value('nzportable'))!)
		e321 := t.hold(operation('truediv', [e319, e320]) or {
			t.drop(e319)!
			t.drop(e320)!
			return err
		})
		t.drop(e319)!
		t.drop(e320)!
		e322 := t.hold(invoke_owned(e318, [o(e321)], {}, [e321])!)
		t.take(e318)
		t.take(e321)
		e323 := t.hold(resolve('_list')!)
		e324 := t.hold(invoke_owned(e323, [o(e311), o(e316), o(e317), o(e322)], {}, [
			e322,
			e317,
			e316,
			e311,
		])!)
		t.take(e323)
		t.take(e311)
		t.take(e316)
		t.take(e317)
		t.take(e322)
		e325 := t.hold(literal(ah.Value(true))!)
		e326 := t.hold(invoke_owned(e310, [o(e324)], {
			'check': o(e325)
		}, [e325, e324])!)
		t.take(e310)
		t.take(e324)
		t.take(e325)
		t.drop(e326)!
		t.clear()!
	}
	t.clear()!
	// Original line 154: if arguments.ppsspp_gow:
	e327 := t.hold(f.load('arguments')!)
	e328 := t.hold(member(e327, 'ppsspp_gow') or {
		t.drop(e327)!
		return err
	})
	t.drop(e327)!
	b329 := truth(e328) or {
		t.drop(e328)!
		return err
	}
	t.drop(e328)!
	if b329 {
		// Original line 155: subprocess.run(["python3", str(ROOT / "examples/ios-ppsspp/download-gow.py"),
		e330 := t.hold(global('subprocess')!)
		e331 := t.hold(member(e330, 'run') or {
			t.drop(e330)!
			return err
		})
		t.drop(e330)!
		e332 := t.hold(literal(ah.Value('python3'))!)
		e333 := t.hold(global('str')!)
		e334 := t.hold(global('ROOT')!)
		e335 := t.hold(literal(ah.Value('examples/ios-ppsspp/download-gow.py'))!)
		e336 := t.hold(operation('truediv', [e334, e335]) or {
			t.drop(e334)!
			t.drop(e335)!
			return err
		})
		t.drop(e334)!
		t.drop(e335)!
		e337 := t.hold(invoke_owned(e333, [o(e336)], {}, [e336])!)
		t.take(e333)
		t.take(e336)
		e338 := t.hold(literal(ah.Value('--output'))!)
		e339 := t.hold(global('str')!)
		e340 := t.hold(f.load('build')!)
		e341 := t.hold(literal(ah.Value('god-of-war'))!)
		e342 := t.hold(operation('truediv', [e340, e341]) or {
			t.drop(e340)!
			t.drop(e341)!
			return err
		})
		t.drop(e340)!
		t.drop(e341)!
		e343 := t.hold(invoke_owned(e339, [o(e342)], {}, [e342])!)
		t.take(e339)
		t.take(e342)
		e344 := t.hold(resolve('_list')!)
		e345 := t.hold(invoke_owned(e344, [o(e332), o(e337), o(e338), o(e343)], {}, [
			e343,
			e338,
			e337,
			e332,
		])!)
		t.take(e344)
		t.take(e332)
		t.take(e337)
		t.take(e338)
		t.take(e343)
		e346 := t.hold(literal(ah.Value(true))!)
		e347 := t.hold(invoke_owned(e331, [o(e345)], {
			'check': o(e346)
		}, [e346, e345])!)
		t.take(e331)
		t.take(e345)
		t.take(e346)
		t.drop(e347)!
		t.clear()!
	}
	t.clear()!
	// Original line 157: runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
	e348 := t.hold(global('Path')!)
	e349 := t.hold(global('os')!)
	e350 := t.hold(member(e349, 'environ') or {
		t.drop(e349)!
		return err
	})
	t.drop(e349)!
	e351 := t.hold(member(e350, 'get') or {
		t.drop(e350)!
		return err
	})
	t.drop(e350)!
	e352 := t.hold(literal(ah.Value('VINIX_VM_RUNNER_ROOT'))!)
	e353 := t.hold(global('ROOT')!)
	e354 := t.hold(invoke_owned(e351, [o(e352), o(e353)], {}, [e353, e352])!)
	t.take(e351)
	t.take(e352)
	t.take(e353)
	e355 := t.hold(invoke_owned(e348, [o(e354)], {}, [e354])!)
	t.take(e348)
	t.take(e354)
	f.named('runner_root', t.take(e355))!
	t.clear()!
	// Original line 158: spec = importlib.util.spec_from_file_location("ios_vm", runner_root / "tests/realtime/run_vm.py")
	e356 := t.hold(global('importlib')!)
	e357 := t.hold(member(e356, 'util') or {
		t.drop(e356)!
		return err
	})
	t.drop(e356)!
	e358 := t.hold(member(e357, 'spec_from_file_location') or {
		t.drop(e357)!
		return err
	})
	t.drop(e357)!
	e359 := t.hold(literal(ah.Value('ios_vm'))!)
	e360 := t.hold(f.load('runner_root')!)
	e361 := t.hold(literal(ah.Value('tests/realtime/run_vm.py'))!)
	e362 := t.hold(operation('truediv', [e360, e361]) or {
		t.drop(e360)!
		t.drop(e361)!
		return err
	})
	t.drop(e360)!
	t.drop(e361)!
	e363 := t.hold(invoke_owned(e358, [o(e359), o(e362)], {}, [e362, e359])!)
	t.take(e358)
	t.take(e359)
	t.take(e362)
	f.named('spec', t.take(e363))!
	t.clear()!
	// Original line 159: runner = importlib.util.module_from_spec(spec)
	e364 := t.hold(global('importlib')!)
	e365 := t.hold(member(e364, 'util') or {
		t.drop(e364)!
		return err
	})
	t.drop(e364)!
	e366 := t.hold(member(e365, 'module_from_spec') or {
		t.drop(e365)!
		return err
	})
	t.drop(e365)!
	e367 := t.hold(f.load('spec')!)
	e368 := t.hold(invoke_owned(e366, [o(e367)], {}, [e367])!)
	t.take(e366)
	t.take(e367)
	f.named('runner', t.take(e368))!
	t.clear()!
	// Original line 160: spec.loader.exec_module(runner)
	e369 := t.hold(f.load('spec')!)
	e370 := t.hold(member(e369, 'loader') or {
		t.drop(e369)!
		return err
	})
	t.drop(e369)!
	e371 := t.hold(member(e370, 'exec_module') or {
		t.drop(e370)!
		return err
	})
	t.drop(e370)!
	e372 := t.hold(f.load('runner')!)
	e373 := t.hold(invoke_owned(e371, [o(e372)], {}, [e372])!)
	t.take(e371)
	t.take(e372)
	t.drop(e373)!
	t.clear()!
	// Original line 161: runner.PASS_MARKER = b"VINIX iOS GUEST: PASS"
	e374 := t.hold(bytes_('56494e495820694f532047554553543a2050415353')!)
	e375 := t.hold(f.load('runner')!)
	set_attribute(e375, 'PASS_MARKER', e374) or {
		t.drop(e375)!
		t.drop(e374)!
		return err
	}
	t.drop(e375)!
	t.drop(e374)!
	t.clear()!
	// Original line 162: runner.FAIL_MARKERS = (b"iOS FAIL:", b"FATAL EXCEPTION", b"KERNEL PANIC")
	e376 := t.hold(bytes_('694f53204641494c3a')!)
	e377 := t.hold(bytes_('464154414c20455843455054494f4e')!)
	e378 := t.hold(bytes_('4b45524e454c2050414e4943')!)
	e379 := t.hold(literal(ah.Value('tuple:36420'))!)
	e380 := t.hold(resolve('_tuple_literal')!)
	e381 := t.hold(invoke_owned(e380, [o(e379), o(e376), o(e377), o(e378)], {}, [e378, e377, e376,
		e379])!)
	t.take(e380)
	t.take(e379)
	t.take(e376)
	t.take(e377)
	t.take(e378)
	e382 := t.hold(f.load('runner')!)
	set_attribute(e382, 'FAIL_MARKERS', e381) or {
		t.drop(e382)!
		t.drop(e381)!
		return err
	}
	t.drop(e382)!
	t.drop(e381)!
	t.clear()!
	// Original line 163: runner.FEATURE_MARKERS = FEATURES + ((
	e383 := t.hold(global('FEATURES')!)
	mut e384 := ''
	e385 := t.hold(f.load('arguments')!)
	e386 := t.hold(member(e385, 'with_2048') or {
		t.drop(e385)!
		return err
	})
	t.drop(e385)!
	b387 := truth(e386) or {
		t.drop(e386)!
		return err
	}
	t.drop(e386)!
	if b387 {
		e388 := t.hold(bytes_('694f5320504153533a20757073747265616d2032303438206569676874206d6f64656c206d65726765207465737473')!)
		e389 := t.hold(bytes_('694f5320504153533a20757073747265616d2032303438206c61756e63682c207377697065732c206d65726765732c2074696d65727320616e64204152432074656172646f776e')!)
		e390 := t.hold(literal(ah.Value('tuple:37533'))!)
		e391 := t.hold(resolve('_tuple_literal')!)
		e392 := t.hold(invoke_owned(e391, [o(e390), o(e388), o(e389)], {}, [e389, e388, e390])!)
		t.take(e391)
		t.take(e390)
		t.take(e388)
		t.take(e389)
		e384 = e392
	} else {
		e393 := t.hold(literal(ah.Value('tuple:37954'))!)
		e394 := t.hold(resolve('_tuple_literal')!)
		e395 := t.hold(invoke_owned(e394, [o(e393)], {}, [e393])!)
		t.take(e394)
		t.take(e393)
		e384 = e395
	}
	e396 := t.hold(operation('add', [e383, e384]) or {
		t.drop(e383)!
		t.drop(e384)!
		return err
	})
	t.drop(e383)!
	t.drop(e384)!
	e397 := t.hold(f.load('runner')!)
	set_attribute(e397, 'FEATURE_MARKERS', e396) or {
		t.drop(e397)!
		t.drop(e396)!
		return err
	}
	t.drop(e397)!
	t.drop(e396)!
	t.clear()!
	// Original line 167: if arguments.with_ppsspp:
	e398 := t.hold(f.load('arguments')!)
	e399 := t.hold(member(e398, 'with_ppsspp') or {
		t.drop(e398)!
		return err
	})
	t.drop(e398)!
	b400 := truth(e399) or {
		t.drop(e399)!
		return err
	}
	t.drop(e399)!
	if b400 {
		// Original line 168: runner.FEATURE_MARKERS += (b"iOS PASS: upstream PPSSPP native framebuffer and process lifecycle (muted)",) if arguments.ppsspp_muted else
		e401 := t.hold(f.load('runner')!)
		e402 := t.hold(member(e401, 'FEATURE_MARKERS')!)
		mut e403 := ''
		e404 := t.hold(f.load('arguments')!)
		e405 := t.hold(member(e404, 'ppsspp_muted') or {
			t.drop(e404)!
			return err
		})
		t.drop(e404)!
		b406 := truth(e405) or {
			t.drop(e405)!
			return err
		}
		t.drop(e405)!
		if b406 {
			e407 := t.hold(bytes_('694f5320504153533a20757073747265616d20505053535050206e6174697665206672616d6562756666657220616e642070726f63657373206c6966656379636c6520286d7574656429')!)
			e408 := t.hold(literal(ah.Value('tuple:39358'))!)
			e409 := t.hold(resolve('_tuple_literal')!)
			e410 := t.hold(invoke_owned(e409, [o(e408), o(e407)], {}, [e407, e408])!)
			t.take(e409)
			t.take(e408)
			t.take(e407)
			e403 = e410
		} else {
			e411 := t.hold(bytes_('694f5320424c4f434b45443a20757073747265616d2050505353505020756e737570706f727465642041504920726561636865642061742072756e74696d65')!)
			e412 := t.hold(literal(ah.Value('tuple:39838'))!)
			e413 := t.hold(resolve('_tuple_literal')!)
			e414 := t.hold(invoke_owned(e413, [o(e412), o(e411)], {}, [e411, e412])!)
			t.take(e413)
			t.take(e412)
			t.take(e411)
			e403 = e414
		}
		e415 := t.hold(operation('iadd', [e402, e403]) or {
			t.drop(e402)!
			t.drop(e403)!
			return err
		})
		t.drop(e402)!
		t.drop(e403)!
		set_attribute(e401, 'FEATURE_MARKERS', e415)!
		t.drop(e401)!
		t.drop(e415)!
		t.clear()!
	}
	t.clear()!
	// Original line 169: if arguments.ppsspp_cube:
	e416 := t.hold(f.load('arguments')!)
	e417 := t.hold(member(e416, 'ppsspp_cube') or {
		t.drop(e416)!
		return err
	})
	t.drop(e416)!
	b418 := truth(e417) or {
		t.drop(e417)!
		return err
	}
	t.drop(e417)!
	if b418 {
		// Original line 170: runner.FEATURE_MARKERS += (b"iOS PASS: unchanged PPSSPP iOS binary executes PSP cube homebrew",)
		e419 := t.hold(f.load('runner')!)
		e420 := t.hold(member(e419, 'FEATURE_MARKERS')!)
		e421 := t.hold(bytes_('694f5320504153533a20756e6368616e6765642050505353505020694f532062696e61727920657865637574657320505350206375626520686f6d6562726577')!)
		e422 := t.hold(literal(ah.Value('tuple:40953'))!)
		e423 := t.hold(resolve('_tuple_literal')!)
		e424 := t.hold(invoke_owned(e423, [o(e422), o(e421)], {}, [e421, e422])!)
		t.take(e423)
		t.take(e422)
		t.take(e421)
		e425 := t.hold(operation('iadd', [e420, e424]) or {
			t.drop(e420)!
			t.drop(e424)!
			return err
		})
		t.drop(e420)!
		t.drop(e424)!
		set_attribute(e419, 'FEATURE_MARKERS', e425)!
		t.drop(e419)!
		t.drop(e425)!
		t.clear()!
	}
	t.clear()!
	// Original line 171: if arguments.ppsspp_nzp:
	e426 := t.hold(f.load('arguments')!)
	e427 := t.hold(member(e426, 'ppsspp_nzp') or {
		t.drop(e426)!
		return err
	})
	t.drop(e426)!
	b428 := truth(e427) or {
		t.drop(e427)!
		return err
	}
	t.drop(e427)!
	if b428 {
		// Original line 172: runner.FEATURE_MARKERS += (b"iOS PASS: unchanged PPSSPP iOS binary plays NZP PSP shooter",)
		e429 := t.hold(f.load('runner')!)
		e430 := t.hold(member(e429, 'FEATURE_MARKERS')!)
		e431 := t.hold(bytes_('694f5320504153533a20756e6368616e6765642050505353505020694f532062696e61727920706c617973204e5a50205053502073686f6f746572')!)
		e432 := t.hold(literal(ah.Value('tuple:42040'))!)
		e433 := t.hold(resolve('_tuple_literal')!)
		e434 := t.hold(invoke_owned(e433, [o(e432), o(e431)], {}, [e431, e432])!)
		t.take(e433)
		t.take(e432)
		t.take(e431)
		e435 := t.hold(operation('iadd', [e430, e434]) or {
			t.drop(e430)!
			t.drop(e434)!
			return err
		})
		t.drop(e430)!
		t.drop(e434)!
		set_attribute(e429, 'FEATURE_MARKERS', e435)!
		t.drop(e429)!
		t.drop(e435)!
		t.clear()!
	}
	t.clear()!
	// Original line 173: if arguments.ppsspp_gow:
	e436 := t.hold(f.load('arguments')!)
	e437 := t.hold(member(e436, 'ppsspp_gow') or {
		t.drop(e436)!
		return err
	})
	t.drop(e436)!
	b438 := truth(e437) or {
		t.drop(e437)!
		return err
	}
	t.drop(e437)!
	if b438 {
		// Original line 174: runner.FEATURE_MARKERS += (b"iOS PASS: unchanged PPSSPP iOS binary runs God of War PSP demo",)
		e439 := t.hold(f.load('runner')!)
		e440 := t.hold(member(e439, 'FEATURE_MARKERS')!)
		e441 := t.hold(bytes_('694f5320504153533a20756e6368616e6765642050505353505020694f532062696e6172792072756e7320476f64206f6620576172205053502064656d6f')!)
		e442 := t.hold(literal(ah.Value('tuple:43131'))!)
		e443 := t.hold(resolve('_tuple_literal')!)
		e444 := t.hold(invoke_owned(e443, [o(e442), o(e441)], {}, [e441, e442])!)
		t.take(e443)
		t.take(e442)
		t.take(e441)
		e445 := t.hold(operation('iadd', [e440, e444]) or {
			t.drop(e440)!
			t.drop(e444)!
			return err
		})
		t.drop(e440)!
		t.drop(e444)!
		set_attribute(e439, 'FEATURE_MARKERS', e445)!
		t.drop(e439)!
		t.drop(e445)!
		t.clear()!
	}
	t.clear()!
	// Original line 175: if arguments.with_cxx:
	e446 := t.hold(f.load('arguments')!)
	e447 := t.hold(member(e446, 'with_cxx') or {
		t.drop(e446)!
		return err
	})
	t.drop(e446)!
	b448 := truth(e447) or {
		t.drop(e447)!
		return err
	}
	t.drop(e447)!
	if b448 {
		// Original line 176: runner.FEATURE_MARKERS += (b"iOS PASS: native C++ strings, streams, regex and lifetime",)
		e449 := t.hold(f.load('runner')!)
		e450 := t.hold(member(e449, 'FEATURE_MARKERS')!)
		e451 := t.hold(bytes_('694f5320504153533a206e617469766520432b2b20737472696e67732c2073747265616d732c20726567657820616e64206c69666574696d65')!)
		e452 := t.hold(literal(ah.Value('tuple:44206'))!)
		e453 := t.hold(resolve('_tuple_literal')!)
		e454 := t.hold(invoke_owned(e453, [o(e452), o(e451)], {}, [e451, e452])!)
		t.take(e453)
		t.take(e452)
		t.take(e451)
		e455 := t.hold(operation('iadd', [e450, e454]) or {
			t.drop(e450)!
			t.drop(e454)!
			return err
		})
		t.drop(e450)!
		t.drop(e454)!
		set_attribute(e449, 'FEATURE_MARKERS', e455)!
		t.drop(e449)!
		t.drop(e455)!
		t.clear()!
		// Original line 177: runner.FEATURE_MARKERS += (b"iOS PASS: extended C++ ABI, Darwin entropy and variadic abort",)
		e456 := t.hold(f.load('runner')!)
		e457 := t.hold(member(e456, 'FEATURE_MARKERS')!)
		e458 := t.hold(bytes_('694f5320504153533a20657874656e64656420432b2b204142492c2044617277696e20656e74726f707920616e642076617269616469632061626f7274')!)
		e459 := t.hold(literal(ah.Value('tuple:45041'))!)
		e460 := t.hold(resolve('_tuple_literal')!)
		e461 := t.hold(invoke_owned(e460, [o(e459), o(e458)], {}, [e458, e459])!)
		t.take(e460)
		t.take(e459)
		t.take(e458)
		e462 := t.hold(operation('iadd', [e457, e461]) or {
			t.drop(e457)!
			t.drop(e461)!
			return err
		})
		t.drop(e457)!
		t.drop(e461)!
		set_attribute(e456, 'FEATURE_MARKERS', e462)!
		t.drop(e456)!
		t.drop(e462)!
		t.clear()!
		// Original line 178: runner.FEATURE_MARKERS += (b"iOS PASS: native ELF vector exception helpers",)
		e463 := t.hold(f.load('runner')!)
		e464 := t.hold(member(e463, 'FEATURE_MARKERS')!)
		e465 := t.hold(bytes_('694f5320504153533a206e617469766520454c4620766563746f7220657863657074696f6e2068656c70657273')!)
		e466 := t.hold(literal(ah.Value('tuple:45832'))!)
		e467 := t.hold(resolve('_tuple_literal')!)
		e468 := t.hold(invoke_owned(e467, [o(e466), o(e465)], {}, [e465, e466])!)
		t.take(e467)
		t.take(e466)
		t.take(e465)
		e469 := t.hold(operation('iadd', [e464, e468]) or {
			t.drop(e464)!
			t.drop(e468)!
			return err
		})
		t.drop(e464)!
		t.drop(e468)!
		set_attribute(e463, 'FEATURE_MARKERS', e469)!
		t.drop(e463)!
		t.drop(e469)!
		t.clear()!
		// Original line 179: runner.FEATURE_MARKERS += (b"iOS PASS: Objective-C image startup and C++ ivars",)
		e470 := t.hold(f.load('runner')!)
		e471 := t.hold(member(e470, 'FEATURE_MARKERS')!)
		e472 := t.hold(bytes_('694f5320504153533a204f626a6563746976652d4320696d616765207374617274757020616e6420432b2b206976617273')!)
		e473 := t.hold(literal(ah.Value('tuple:46619'))!)
		e474 := t.hold(resolve('_tuple_literal')!)
		e475 := t.hold(invoke_owned(e474, [o(e473), o(e472)], {}, [e472, e473])!)
		t.take(e474)
		t.take(e473)
		t.take(e472)
		e476 := t.hold(operation('iadd', [e471, e475]) or {
			t.drop(e471)!
			t.drop(e475)!
			return err
		})
		t.drop(e471)!
		t.drop(e475)!
		set_attribute(e470, 'FEATURE_MARKERS', e476)!
		t.drop(e470)!
		t.drop(e476)!
		t.clear()!
	}
	t.clear()!
	// Original line 180: if arguments.with_gles:
	e477 := t.hold(f.load('arguments')!)
	e478 := t.hold(member(e477, 'with_gles') or {
		t.drop(e477)!
		return err
	})
	t.drop(e477)!
	b479 := truth(e478) or {
		t.drop(e478)!
		return err
	}
	t.drop(e478)!
	if b479 {
		// Original line 181: runner.FEATURE_MARKERS += (b"iOS PASS: native OpenGL ES shader rendering and GLKView lifecycle",)
		e480 := t.hold(f.load('runner')!)
		e481 := t.hold(member(e480, 'FEATURE_MARKERS')!)
		e482 := t.hold(bytes_('694f5320504153533a206e6174697665204f70656e474c204553207368616465722072656e646572696e6720616e6420474c4b56696577206c6966656379636c65')!)
		e483 := t.hold(literal(ah.Value('tuple:47707'))!)
		e484 := t.hold(resolve('_tuple_literal')!)
		e485 := t.hold(invoke_owned(e484, [o(e483), o(e482)], {}, [e482, e483])!)
		t.take(e484)
		t.take(e483)
		t.take(e482)
		e486 := t.hold(operation('iadd', [e481, e485]) or {
			t.drop(e481)!
			t.drop(e485)!
			return err
		})
		t.drop(e481)!
		t.drop(e485)!
		set_attribute(e480, 'FEATURE_MARKERS', e486)!
		t.drop(e480)!
		t.drop(e486)!
		t.clear()!
		// Original line 182: runner.FEATURE_MARKERS += (b"iOS PASS: display links, main queue and desktop shared-surface presentation",)
		e487 := t.hold(f.load('runner')!)
		e488 := t.hold(member(e487, 'FEATURE_MARKERS')!)
		e489 := t.hold(bytes_('694f5320504153533a20646973706c6179206c696e6b732c206d61696e20717565756520616e64206465736b746f70207368617265642d737572666163652070726573656e746174696f6e')!)
		e490 := t.hold(literal(ah.Value('tuple:48592'))!)
		e491 := t.hold(resolve('_tuple_literal')!)
		e492 := t.hold(invoke_owned(e491, [o(e490), o(e489)], {}, [e489, e490])!)
		t.take(e491)
		t.take(e490)
		t.take(e489)
		e493 := t.hold(operation('iadd', [e488, e492]) or {
			t.drop(e488)!
			t.drop(e492)!
			return err
		})
		t.drop(e488)!
		t.drop(e492)!
		set_attribute(e487, 'FEATURE_MARKERS', e493)!
		t.drop(e487)!
		t.drop(e493)!
		t.clear()!
		// Original line 183: runner.FEATURE_MARKERS += (b"iOS PASS: native CoreText fonts and bitmap glyph rendering",)
		e494 := t.hold(f.load('runner')!)
		e495 := t.hold(member(e494, 'FEATURE_MARKERS')!)
		e496 := t.hold(bytes_('694f5320504153533a206e617469766520436f72655465787420666f6e747320616e64206269746d617020676c7970682072656e646572696e67')!)
		e497 := t.hold(literal(ah.Value('tuple:49436'))!)
		e498 := t.hold(resolve('_tuple_literal')!)
		e499 := t.hold(invoke_owned(e498, [o(e497), o(e496)], {}, [e496, e497])!)
		t.take(e498)
		t.take(e497)
		t.take(e496)
		e500 := t.hold(operation('iadd', [e495, e499]) or {
			t.drop(e495)!
			t.drop(e499)!
			return err
		})
		t.drop(e495)!
		t.drop(e499)!
		set_attribute(e494, 'FEATURE_MARKERS', e500)!
		t.drop(e494)!
		t.drop(e500)!
		t.clear()!
		// Original line 184: runner.FEATURE_MARKERS += (b"iOS PASS: native zlib and Mach-O callbacks",)
		e501 := t.hold(f.load('runner')!)
		e502 := t.hold(member(e501, 'FEATURE_MARKERS')!)
		e503 := t.hold(bytes_('694f5320504153533a206e6174697665207a6c696220616e64204d6163682d4f2063616c6c6261636b73')!)
		e504 := t.hold(literal(ah.Value('tuple:50215'))!)
		e505 := t.hold(resolve('_tuple_literal')!)
		e506 := t.hold(invoke_owned(e505, [o(e504), o(e503)], {}, [e503, e504])!)
		t.take(e505)
		t.take(e504)
		t.take(e503)
		e507 := t.hold(operation('iadd', [e502, e506]) or {
			t.drop(e502)!
			t.drop(e506)!
			return err
		})
		t.drop(e502)!
		t.drop(e506)!
		set_attribute(e501, 'FEATURE_MARKERS', e507)!
		t.drop(e501)!
		t.drop(e507)!
		t.clear()!
	}
	t.clear()!
	return literal(none_())!
}

fn stage(mut f Frame) !string {
	mut t := Temps{}
	defer { t.clear() or {} }
	// Original line 186: work = Path(directory)
	e1 := t.hold(global('Path')!)
	e2 := t.hold(f.load('directory')!)
	e3 := t.hold(invoke_owned(e1, [o(e2)], {}, [e2])!)
	t.take(e1)
	t.take(e2)
	f.named('work', t.take(e3))!
	t.clear()!
	// Original line 187: rootfs = work / "rootfs"
	e4 := t.hold(f.load('work')!)
	e5 := t.hold(literal(ah.Value('rootfs'))!)
	e6 := t.hold(operation('truediv', [e4, e5]) or {
		t.drop(e4)!
		t.drop(e5)!
		return err
	})
	t.drop(e4)!
	t.drop(e5)!
	f.named('rootfs', t.take(e6))!
	t.clear()!
	// Original line 188: for name in ("root", "sbin", "proc", "sys", "dev", "tmp", "etc", "opt/ios"):
	for name7 in ['root', 'sbin', 'proc', 'sys', 'dev', 'tmp', 'etc', 'opt/ios'] {
		f.named('name', literal(ah.Value(name7))!)!
		// Original line 189: (rootfs / name).mkdir(parents=True)
		e8 := t.hold(f.load('rootfs')!)
		e9 := t.hold(f.load('name')!)
		e10 := t.hold(operation('truediv', [e8, e9]) or {
			t.drop(e8)!
			t.drop(e9)!
			return err
		})
		t.drop(e8)!
		t.drop(e9)!
		e11 := t.hold(member(e10, 'mkdir') or {
			t.drop(e10)!
			return err
		})
		t.drop(e10)!
		e12 := t.hold(literal(ah.Value(true))!)
		e13 := t.hold(invoke_owned(e11, [], {
			'parents': o(e12)
		}, [e12])!)
		t.take(e11)
		t.take(e12)
		t.drop(e13)!
		t.clear()!
	}
	t.clear()!
	// Original line 190: (rootfs / "etc/hosts").write_text("127.0.0.1 localhost\n::1 localhost\n")
	e14 := t.hold(f.load('rootfs')!)
	e15 := t.hold(literal(ah.Value('etc/hosts'))!)
	e16 := t.hold(operation('truediv', [e14, e15]) or {
		t.drop(e14)!
		t.drop(e15)!
		return err
	})
	t.drop(e14)!
	t.drop(e15)!
	e17 := t.hold(member(e16, 'write_text') or {
		t.drop(e16)!
		return err
	})
	t.drop(e16)!
	e18 := t.hold(literal(ah.Value('127.0.0.1 localhost\n::1 localhost\n'))!)
	e19 := t.hold(invoke_owned(e17, [o(e18)], {}, [e18])!)
	t.take(e17)
	t.take(e18)
	t.drop(e19)!
	t.clear()!
	// Original line 191: (rootfs / "etc/services").write_text("domain 53/tcp\ndomain 53/udp\n")
	e20 := t.hold(f.load('rootfs')!)
	e21 := t.hold(literal(ah.Value('etc/services'))!)
	e22 := t.hold(operation('truediv', [e20, e21]) or {
		t.drop(e20)!
		t.drop(e21)!
		return err
	})
	t.drop(e20)!
	t.drop(e21)!
	e23 := t.hold(member(e22, 'write_text') or {
		t.drop(e22)!
		return err
	})
	t.drop(e22)!
	e24 := t.hold(literal(ah.Value('domain 53/tcp\ndomain 53/udp\n'))!)
	e25 := t.hold(invoke_owned(e23, [o(e24)], {}, [e24])!)
	t.take(e23)
	t.take(e24)
	t.drop(e25)!
	t.clear()!
	// Original line 192: (rootfs / "etc/protocols").write_text("icmp 1 ICMP\ntcp 6 TCP\nudp 17 UDP\n")
	e26 := t.hold(f.load('rootfs')!)
	e27 := t.hold(literal(ah.Value('etc/protocols'))!)
	e28 := t.hold(operation('truediv', [e26, e27]) or {
		t.drop(e26)!
		t.drop(e27)!
		return err
	})
	t.drop(e26)!
	t.drop(e27)!
	e29 := t.hold(member(e28, 'write_text') or {
		t.drop(e28)!
		return err
	})
	t.drop(e28)!
	e30 := t.hold(literal(ah.Value('icmp 1 ICMP\ntcp 6 TCP\nudp 17 UDP\n'))!)
	e31 := t.hold(invoke_owned(e29, [o(e30)], {}, [e30])!)
	t.take(e29)
	t.take(e30)
	t.drop(e31)!
	t.clear()!
	// Original line 193: (rootfs / "etc/passwd").write_text("root:*:0:0:Vinix iOS root:/root:/bin/sh\n"
	e32 := t.hold(f.load('rootfs')!)
	e33 := t.hold(literal(ah.Value('etc/passwd'))!)
	e34 := t.hold(operation('truediv', [e32, e33]) or {
		t.drop(e32)!
		t.drop(e33)!
		return err
	})
	t.drop(e32)!
	t.drop(e33)!
	e35 := t.hold(member(e34, 'write_text') or {
		t.drop(e34)!
		return err
	})
	t.drop(e34)!
	e36 := t.hold(literal(ah.Value('root:*:0:0:Vinix iOS root:/root:/bin/sh\n'))!)
	e37 := t.hold(literal(ah.Value('ios-fixture:*:1001:37:'))!)
	e38 := t.hold(operation('add', [e36, e37]) or {
		t.drop(e36)!
		t.drop(e37)!
		return err
	})
	t.drop(e36)!
	t.drop(e37)!
	e39 := t.hold(literal(ah.Value('G'))!)
	e40 := t.hold(literal(ah.Value(i64(8192)))!)
	e41 := t.hold(operation('mul', [e39, e40]) or {
		t.drop(e39)!
		t.drop(e40)!
		return err
	})
	t.drop(e39)!
	t.drop(e40)!
	e42 := t.hold(operation('add', [e38, e41]) or {
		t.drop(e38)!
		t.drop(e41)!
		return err
	})
	t.drop(e38)!
	t.drop(e41)!
	e43 := t.hold(literal(ah.Value(':/var/empty:/bin/false\n'))!)
	e44 := t.hold(operation('add', [e42, e43]) or {
		t.drop(e42)!
		t.drop(e43)!
		return err
	})
	t.drop(e42)!
	t.drop(e43)!
	e45 := t.hold(invoke_owned(e35, [o(e44)], {}, [e44])!)
	t.take(e35)
	t.take(e44)
	t.drop(e45)!
	t.clear()!
	// Original line 195: (rootfs / "etc/group").write_text("root:*:0:\nbase:*:37:\nfirst:*:8:ios-fixture\n"
	e46 := t.hold(f.load('rootfs')!)
	e47 := t.hold(literal(ah.Value('etc/group'))!)
	e48 := t.hold(operation('truediv', [e46, e47]) or {
		t.drop(e46)!
		t.drop(e47)!
		return err
	})
	t.drop(e46)!
	t.drop(e47)!
	e49 := t.hold(member(e48, 'write_text') or {
		t.drop(e48)!
		return err
	})
	t.drop(e48)!
	e50 := t.hold(literal(ah.Value('root:*:0:\nbase:*:37:\nfirst:*:8:ios-fixture\n'))!)
	e51 := t.hold(literal(ah.Value('unrelated:*:9:someone\nsecond:*:11:ios-fixture\n'))!)
	e52 := t.hold(operation('add', [e50, e51]) or {
		t.drop(e50)!
		t.drop(e51)!
		return err
	})
	t.drop(e50)!
	t.drop(e51)!
	e53 := t.hold(invoke_owned(e49, [o(e52)], {}, [e52])!)
	t.take(e49)
	t.take(e52)
	t.drop(e53)!
	t.clear()!
	// Original line 197: destination = rootfs / "opt/ios"
	e54 := t.hold(f.load('rootfs')!)
	e55 := t.hold(literal(ah.Value('opt/ios'))!)
	e56 := t.hold(operation('truediv', [e54, e55]) or {
		t.drop(e54)!
		t.drop(e55)!
		return err
	})
	t.drop(e54)!
	t.drop(e55)!
	f.named('destination', t.take(e56))!
	t.clear()!
	// Original line 198: (destination / "launch name#é%?.bin").write_bytes(b"native file launch fixture\n")
	e57 := t.hold(f.load('destination')!)
	e58 := t.hold(literal(ah.Value('launch name#é%?.bin'))!)
	e59 := t.hold(operation('truediv', [e57, e58]) or {
		t.drop(e57)!
		t.drop(e58)!
		return err
	})
	t.drop(e57)!
	t.drop(e58)!
	e60 := t.hold(member(e59, 'write_bytes') or {
		t.drop(e59)!
		return err
	})
	t.drop(e59)!
	e61 := t.hold(bytes_('6e61746976652066696c65206c61756e636820666978747572650a')!)
	e62 := t.hold(invoke_owned(e60, [o(e61)], {}, [e61])!)
	t.take(e60)
	t.take(e61)
	t.drop(e62)!
	t.clear()!
	// Original line 199: shutil.copy2(build / "staging/usr/bin" / ("run-ios-gles" if arguments.with_gles else "run-ios"), destination / "run-ios")
	e63 := t.hold(global('shutil')!)
	e64 := t.hold(member(e63, 'copy2') or {
		t.drop(e63)!
		return err
	})
	t.drop(e63)!
	e65 := t.hold(f.load('build')!)
	e66 := t.hold(literal(ah.Value('staging/usr/bin'))!)
	e67 := t.hold(operation('truediv', [e65, e66]) or {
		t.drop(e65)!
		t.drop(e66)!
		return err
	})
	t.drop(e65)!
	t.drop(e66)!
	mut e68 := ''
	e69 := t.hold(f.load('arguments')!)
	e70 := t.hold(member(e69, 'with_gles') or {
		t.drop(e69)!
		return err
	})
	t.drop(e69)!
	b71 := truth(e70) or {
		t.drop(e70)!
		return err
	}
	t.drop(e70)!
	if b71 {
		e72 := t.hold(literal(ah.Value('run-ios-gles'))!)
		e68 = e72
	} else {
		e73 := t.hold(literal(ah.Value('run-ios'))!)
		e68 = e73
	}
	e74 := t.hold(operation('truediv', [e67, e68]) or {
		t.drop(e67)!
		t.drop(e68)!
		return err
	})
	t.drop(e67)!
	t.drop(e68)!
	e75 := t.hold(f.load('destination')!)
	e76 := t.hold(literal(ah.Value('run-ios'))!)
	e77 := t.hold(operation('truediv', [e75, e76]) or {
		t.drop(e75)!
		t.drop(e76)!
		return err
	})
	t.drop(e75)!
	t.drop(e76)!
	e78 := t.hold(invoke_owned(e64, [o(e74), o(e77)], {}, [e77, e74])!)
	t.take(e64)
	t.take(e74)
	t.take(e77)
	t.drop(e78)!
	t.clear()!
	// Original line 200: if arguments.with_gles:
	e79 := t.hold(f.load('arguments')!)
	e80 := t.hold(member(e79, 'with_gles') or {
		t.drop(e79)!
		return err
	})
	t.drop(e79)!
	b81 := truth(e80) or {
		t.drop(e80)!
		return err
	}
	t.drop(e80)!
	if b81 {
		// Original line 201: shutil.copytree(build / "staging/usr/lib/vinix/ios-gles", rootfs / "usr/lib/vinix/ios-gles", symlinks=True)
		e82 := t.hold(global('shutil')!)
		e83 := t.hold(member(e82, 'copytree') or {
			t.drop(e82)!
			return err
		})
		t.drop(e82)!
		e84 := t.hold(f.load('build')!)
		e85 := t.hold(literal(ah.Value('staging/usr/lib/vinix/ios-gles'))!)
		e86 := t.hold(operation('truediv', [e84, e85]) or {
			t.drop(e84)!
			t.drop(e85)!
			return err
		})
		t.drop(e84)!
		t.drop(e85)!
		e87 := t.hold(f.load('rootfs')!)
		e88 := t.hold(literal(ah.Value('usr/lib/vinix/ios-gles'))!)
		e89 := t.hold(operation('truediv', [e87, e88]) or {
			t.drop(e87)!
			t.drop(e88)!
			return err
		})
		t.drop(e87)!
		t.drop(e88)!
		e90 := t.hold(literal(ah.Value(true))!)
		e91 := t.hold(invoke_owned(e83, [o(e86), o(e89)], {
			'symlinks': o(e90)
		}, [e90, e89, e86])!)
		t.take(e83)
		t.take(e86)
		t.take(e89)
		t.take(e90)
		t.drop(e91)!
		t.clear()!
		// Original line 202: shutil.copy2(build / "fixtures/gles", destination / "gles")
		e92 := t.hold(global('shutil')!)
		e93 := t.hold(member(e92, 'copy2') or {
			t.drop(e92)!
			return err
		})
		t.drop(e92)!
		e94 := t.hold(f.load('build')!)
		e95 := t.hold(literal(ah.Value('fixtures/gles'))!)
		e96 := t.hold(operation('truediv', [e94, e95]) or {
			t.drop(e94)!
			t.drop(e95)!
			return err
		})
		t.drop(e94)!
		t.drop(e95)!
		e97 := t.hold(f.load('destination')!)
		e98 := t.hold(literal(ah.Value('gles'))!)
		e99 := t.hold(operation('truediv', [e97, e98]) or {
			t.drop(e97)!
			t.drop(e98)!
			return err
		})
		t.drop(e97)!
		t.drop(e98)!
		e100 := t.hold(invoke_owned(e93, [o(e96), o(e99)], {}, [e99, e96])!)
		t.take(e93)
		t.take(e96)
		t.take(e99)
		t.drop(e100)!
		t.clear()!
		// Original line 203: shutil.copy2(build / "fixtures/gles-app", destination / "gles-app")
		e101 := t.hold(global('shutil')!)
		e102 := t.hold(member(e101, 'copy2') or {
			t.drop(e101)!
			return err
		})
		t.drop(e101)!
		e103 := t.hold(f.load('build')!)
		e104 := t.hold(literal(ah.Value('fixtures/gles-app'))!)
		e105 := t.hold(operation('truediv', [e103, e104]) or {
			t.drop(e103)!
			t.drop(e104)!
			return err
		})
		t.drop(e103)!
		t.drop(e104)!
		e106 := t.hold(f.load('destination')!)
		e107 := t.hold(literal(ah.Value('gles-app'))!)
		e108 := t.hold(operation('truediv', [e106, e107]) or {
			t.drop(e106)!
			t.drop(e107)!
			return err
		})
		t.drop(e106)!
		t.drop(e107)!
		e109 := t.hold(invoke_owned(e102, [o(e105), o(e108)], {}, [e108, e105])!)
		t.take(e102)
		t.take(e105)
		t.take(e108)
		t.drop(e109)!
		t.clear()!
		// Original line 204: shutil.copy2(build / "fixtures/compression", destination / "compression")
		e110 := t.hold(global('shutil')!)
		e111 := t.hold(member(e110, 'copy2') or {
			t.drop(e110)!
			return err
		})
		t.drop(e110)!
		e112 := t.hold(f.load('build')!)
		e113 := t.hold(literal(ah.Value('fixtures/compression'))!)
		e114 := t.hold(operation('truediv', [e112, e113]) or {
			t.drop(e112)!
			t.drop(e113)!
			return err
		})
		t.drop(e112)!
		t.drop(e113)!
		e115 := t.hold(f.load('destination')!)
		e116 := t.hold(literal(ah.Value('compression'))!)
		e117 := t.hold(operation('truediv', [e115, e116]) or {
			t.drop(e115)!
			t.drop(e116)!
			return err
		})
		t.drop(e115)!
		t.drop(e116)!
		e118 := t.hold(invoke_owned(e111, [o(e114), o(e117)], {}, [e117, e114])!)
		t.take(e111)
		t.take(e114)
		t.take(e117)
		t.drop(e118)!
		t.clear()!
		// Original line 205: shutil.copytree(build / "fixtures/TextFixture.app", destination / "TextFixture.app")
		e119 := t.hold(global('shutil')!)
		e120 := t.hold(member(e119, 'copytree') or {
			t.drop(e119)!
			return err
		})
		t.drop(e119)!
		e121 := t.hold(f.load('build')!)
		e122 := t.hold(literal(ah.Value('fixtures/TextFixture.app'))!)
		e123 := t.hold(operation('truediv', [e121, e122]) or {
			t.drop(e121)!
			t.drop(e122)!
			return err
		})
		t.drop(e121)!
		t.drop(e122)!
		e124 := t.hold(f.load('destination')!)
		e125 := t.hold(literal(ah.Value('TextFixture.app'))!)
		e126 := t.hold(operation('truediv', [e124, e125]) or {
			t.drop(e124)!
			t.drop(e125)!
			return err
		})
		t.drop(e124)!
		t.drop(e125)!
		e127 := t.hold(invoke_owned(e120, [o(e123), o(e126)], {}, [e126, e123])!)
		t.take(e120)
		t.take(e123)
		t.take(e126)
		t.drop(e127)!
		t.clear()!
		// Original line 206: shutil.copy2(build / "ppsspp/unpacked/Payload/PPSSPP.app/assets/Roboto_Condensed-Regular.ttf", destination / "TextFixture.app/font.ttf")
		e128 := t.hold(global('shutil')!)
		e129 := t.hold(member(e128, 'copy2') or {
			t.drop(e128)!
			return err
		})
		t.drop(e128)!
		e130 := t.hold(f.load('build')!)
		e131 := t.hold(literal(ah.Value('ppsspp/unpacked/Payload/PPSSPP.app/assets/Roboto_Condensed-Regular.ttf'))!)
		e132 := t.hold(operation('truediv', [e130, e131]) or {
			t.drop(e130)!
			t.drop(e131)!
			return err
		})
		t.drop(e130)!
		t.drop(e131)!
		e133 := t.hold(f.load('destination')!)
		e134 := t.hold(literal(ah.Value('TextFixture.app/font.ttf'))!)
		e135 := t.hold(operation('truediv', [e133, e134]) or {
			t.drop(e133)!
			t.drop(e134)!
			return err
		})
		t.drop(e133)!
		t.drop(e134)!
		e136 := t.hold(invoke_owned(e129, [o(e132), o(e135)], {}, [e135, e132])!)
		t.take(e129)
		t.take(e132)
		t.take(e135)
		t.drop(e136)!
		t.clear()!
	}
	t.clear()!
	// Original line 207: for name in ("calculator", "calculator-legacy", "unsupported", "lifecycle", "exit-handlers", "pointer-tags", "pointer-tags-legacy", "core-
	for name137 in ['calculator', 'calculator-legacy', 'unsupported', 'lifecycle', 'exit-handlers',
		'pointer-tags', 'pointer-tags-legacy', 'core-foundation', 'audio-converter', 'audio-graph',
		'colors', 'provider-images', 'geometry', 'game-constants', 'security', 'security-trust',
		'cfnetwork', 'keychain', 'common-crypto', 'atomic-queue', 'assertions', 'stack-probe',
		'libsystem-safety', 'runes', 'sockets', 'numeric', 'nan', 'poll', 'permissions', 'dispatch',
		'fcntl', 'netdb', 'interfaces', 'system-queries', 'process', 'proc-memory', 'atfork',
		'pthread-attr', 'pthread-condattr', 'pthread-identity', 'pthread-sched', 'pthread-mach',
		'ioctl', 'calendar', 'framework-constants', 'accessibility', 'objc-runtime', 'arc-registers',
		'graphics', 'lazy', 'stdio', 'arc-threads', 'mach-memory'] {
		f.named('name', literal(ah.Value(name137))!)!
		// Original line 208: shutil.copy2(build / "fixtures" / name, destination / name)
		e138 := t.hold(global('shutil')!)
		e139 := t.hold(member(e138, 'copy2') or {
			t.drop(e138)!
			return err
		})
		t.drop(e138)!
		e140 := t.hold(f.load('build')!)
		e141 := t.hold(literal(ah.Value('fixtures'))!)
		e142 := t.hold(operation('truediv', [e140, e141]) or {
			t.drop(e140)!
			t.drop(e141)!
			return err
		})
		t.drop(e140)!
		t.drop(e141)!
		e143 := t.hold(f.load('name')!)
		e144 := t.hold(operation('truediv', [e142, e143]) or {
			t.drop(e142)!
			t.drop(e143)!
			return err
		})
		t.drop(e142)!
		t.drop(e143)!
		e145 := t.hold(f.load('destination')!)
		e146 := t.hold(f.load('name')!)
		e147 := t.hold(operation('truediv', [e145, e146]) or {
			t.drop(e145)!
			t.drop(e146)!
			return err
		})
		t.drop(e145)!
		t.drop(e146)!
		e148 := t.hold(invoke_owned(e139, [o(e144), o(e147)], {}, [e147, e144])!)
		t.take(e139)
		t.take(e144)
		t.take(e147)
		t.drop(e148)!
		t.clear()!
	}
	t.clear()!
	// Original line 209: (destination / "permissions-loop").symlink_to("permissions-loop")
	e149 := t.hold(f.load('destination')!)
	e150 := t.hold(literal(ah.Value('permissions-loop'))!)
	e151 := t.hold(operation('truediv', [e149, e150]) or {
		t.drop(e149)!
		t.drop(e150)!
		return err
	})
	t.drop(e149)!
	t.drop(e150)!
	e152 := t.hold(member(e151, 'symlink_to') or {
		t.drop(e151)!
		return err
	})
	t.drop(e151)!
	e153 := t.hold(literal(ah.Value('permissions-loop'))!)
	e154 := t.hold(invoke_owned(e152, [o(e153)], {}, [e153])!)
	t.take(e152)
	t.take(e153)
	t.drop(e154)!
	t.clear()!
	// Original line 210: shutil.copytree(build / "fixtures/SceneFixture.app", destination / "SceneFixture.app")
	e155 := t.hold(global('shutil')!)
	e156 := t.hold(member(e155, 'copytree') or {
		t.drop(e155)!
		return err
	})
	t.drop(e155)!
	e157 := t.hold(f.load('build')!)
	e158 := t.hold(literal(ah.Value('fixtures/SceneFixture.app'))!)
	e159 := t.hold(operation('truediv', [e157, e158]) or {
		t.drop(e157)!
		t.drop(e158)!
		return err
	})
	t.drop(e157)!
	t.drop(e158)!
	e160 := t.hold(f.load('destination')!)
	e161 := t.hold(literal(ah.Value('SceneFixture.app'))!)
	e162 := t.hold(operation('truediv', [e160, e161]) or {
		t.drop(e160)!
		t.drop(e161)!
		return err
	})
	t.drop(e160)!
	t.drop(e161)!
	e163 := t.hold(invoke_owned(e156, [o(e159), o(e162)], {}, [e162, e159])!)
	t.take(e156)
	t.take(e159)
	t.take(e162)
	t.drop(e163)!
	t.clear()!
	// Original line 211: shutil.copytree(build / "fixtures/Modules.app", destination / "Modules.app")
	e164 := t.hold(global('shutil')!)
	e165 := t.hold(member(e164, 'copytree') or {
		t.drop(e164)!
		return err
	})
	t.drop(e164)!
	e166 := t.hold(f.load('build')!)
	e167 := t.hold(literal(ah.Value('fixtures/Modules.app'))!)
	e168 := t.hold(operation('truediv', [e166, e167]) or {
		t.drop(e166)!
		t.drop(e167)!
		return err
	})
	t.drop(e166)!
	t.drop(e167)!
	e169 := t.hold(f.load('destination')!)
	e170 := t.hold(literal(ah.Value('Modules.app'))!)
	e171 := t.hold(operation('truediv', [e169, e170]) or {
		t.drop(e169)!
		t.drop(e170)!
		return err
	})
	t.drop(e169)!
	t.drop(e170)!
	e172 := t.hold(invoke_owned(e165, [o(e168), o(e171)], {}, [e171, e168])!)
	t.take(e165)
	t.take(e168)
	t.take(e171)
	t.drop(e172)!
	t.clear()!
	// Original line 212: missing_bundle = destination / "ModulesMissing.app"
	e173 := t.hold(f.load('destination')!)
	e174 := t.hold(literal(ah.Value('ModulesMissing.app'))!)
	e175 := t.hold(operation('truediv', [e173, e174]) or {
		t.drop(e173)!
		t.drop(e174)!
		return err
	})
	t.drop(e173)!
	t.drop(e174)!
	f.named('missing_bundle', t.take(e175))!
	t.clear()!
	// Original line 213: shutil.copytree(destination / "Modules.app", missing_bundle)
	e176 := t.hold(global('shutil')!)
	e177 := t.hold(member(e176, 'copytree') or {
		t.drop(e176)!
		return err
	})
	t.drop(e176)!
	e178 := t.hold(f.load('destination')!)
	e179 := t.hold(literal(ah.Value('Modules.app'))!)
	e180 := t.hold(operation('truediv', [e178, e179]) or {
		t.drop(e178)!
		t.drop(e179)!
		return err
	})
	t.drop(e178)!
	t.drop(e179)!
	e181 := t.hold(f.load('missing_bundle')!)
	e182 := t.hold(invoke_owned(e177, [o(e180), o(e181)], {}, [e181, e180])!)
	t.take(e177)
	t.take(e180)
	t.take(e181)
	t.drop(e182)!
	t.clear()!
	// Original line 214: (missing_bundle / "Frameworks/Leaf.framework/Leaf").unlink()
	e183 := t.hold(f.load('missing_bundle')!)
	e184 := t.hold(literal(ah.Value('Frameworks/Leaf.framework/Leaf'))!)
	e185 := t.hold(operation('truediv', [e183, e184]) or {
		t.drop(e183)!
		t.drop(e184)!
		return err
	})
	t.drop(e183)!
	t.drop(e184)!
	e186 := t.hold(member(e185, 'unlink') or {
		t.drop(e185)!
		return err
	})
	t.drop(e185)!
	e187 := t.hold(invoke_owned(e186, [], {}, [])!)
	t.take(e186)
	t.drop(e187)!
	t.clear()!
	// Original line 215: arm64e_bundle = destination / "ModulesArm64e.app"
	e188 := t.hold(f.load('destination')!)
	e189 := t.hold(literal(ah.Value('ModulesArm64e.app'))!)
	e190 := t.hold(operation('truediv', [e188, e189]) or {
		t.drop(e188)!
		t.drop(e189)!
		return err
	})
	t.drop(e188)!
	t.drop(e189)!
	f.named('arm64e_bundle', t.take(e190))!
	t.clear()!
	// Original line 216: shutil.copytree(destination / "Modules.app", arm64e_bundle)
	e191 := t.hold(global('shutil')!)
	e192 := t.hold(member(e191, 'copytree') or {
		t.drop(e191)!
		return err
	})
	t.drop(e191)!
	e193 := t.hold(f.load('destination')!)
	e194 := t.hold(literal(ah.Value('Modules.app'))!)
	e195 := t.hold(operation('truediv', [e193, e194]) or {
		t.drop(e193)!
		t.drop(e194)!
		return err
	})
	t.drop(e193)!
	t.drop(e194)!
	e196 := t.hold(f.load('arm64e_bundle')!)
	e197 := t.hold(invoke_owned(e192, [o(e195), o(e196)], {}, [e196, e195])!)
	t.take(e192)
	t.take(e195)
	t.take(e196)
	t.drop(e197)!
	t.clear()!
	// Original line 217: leaf = arm64e_bundle / "Frameworks/Leaf.framework/Leaf"
	e198 := t.hold(f.load('arm64e_bundle')!)
	e199 := t.hold(literal(ah.Value('Frameworks/Leaf.framework/Leaf'))!)
	e200 := t.hold(operation('truediv', [e198, e199]) or {
		t.drop(e198)!
		t.drop(e199)!
		return err
	})
	t.drop(e198)!
	t.drop(e199)!
	f.named('leaf', t.take(e200))!
	t.clear()!
	// Original line 218: unsupported_library = bytearray(leaf.read_bytes())
	e201 := t.hold(global('bytearray')!)
	e202 := t.hold(f.load('leaf')!)
	e203 := t.hold(member(e202, 'read_bytes') or {
		t.drop(e202)!
		return err
	})
	t.drop(e202)!
	e204 := t.hold(invoke_owned(e203, [], {}, [])!)
	t.take(e203)
	e205 := t.hold(invoke_owned(e201, [o(e204)], {}, [e204])!)
	t.take(e201)
	t.take(e204)
	f.named('unsupported_library', t.take(e205))!
	t.clear()!
	// Original line 219: struct.pack_into("<I", unsupported_library, 8, 2)
	e206 := t.hold(global('struct')!)
	e207 := t.hold(member(e206, 'pack_into') or {
		t.drop(e206)!
		return err
	})
	t.drop(e206)!
	e208 := t.hold(literal(ah.Value('<I'))!)
	e209 := t.hold(f.load('unsupported_library')!)
	e210 := t.hold(literal(ah.Value(i64(8)))!)
	e211 := t.hold(literal(ah.Value(i64(2)))!)
	e212 := t.hold(invoke_owned(e207, [o(e208), o(e209), o(e210), o(e211)], {}, [e211, e210, e209,
		e208])!)
	t.take(e207)
	t.take(e208)
	t.take(e209)
	t.take(e210)
	t.take(e211)
	t.drop(e212)!
	t.clear()!
	// Original line 220: leaf.write_bytes(unsupported_library)
	e213 := t.hold(f.load('leaf')!)
	e214 := t.hold(member(e213, 'write_bytes') or {
		t.drop(e213)!
		return err
	})
	t.drop(e213)!
	e215 := t.hold(f.load('unsupported_library')!)
	e216 := t.hold(invoke_owned(e214, [o(e215)], {}, [e215])!)
	t.take(e214)
	t.take(e215)
	t.drop(e216)!
	t.clear()!
	// Original line 221: if arguments.with_cxx:
	e217 := t.hold(f.load('arguments')!)
	e218 := t.hold(member(e217, 'with_cxx') or {
		t.drop(e217)!
		return err
	})
	t.drop(e217)!
	b219 := truth(e218) or {
		t.drop(e218)!
		return err
	}
	t.drop(e218)!
	if b219 {
		// Original line 222: shutil.copy2(build / "fixtures/cxx", destination / "cxx")
		e220 := t.hold(global('shutil')!)
		e221 := t.hold(member(e220, 'copy2') or {
			t.drop(e220)!
			return err
		})
		t.drop(e220)!
		e222 := t.hold(f.load('build')!)
		e223 := t.hold(literal(ah.Value('fixtures/cxx'))!)
		e224 := t.hold(operation('truediv', [e222, e223]) or {
			t.drop(e222)!
			t.drop(e223)!
			return err
		})
		t.drop(e222)!
		t.drop(e223)!
		e225 := t.hold(f.load('destination')!)
		e226 := t.hold(literal(ah.Value('cxx'))!)
		e227 := t.hold(operation('truediv', [e225, e226]) or {
			t.drop(e225)!
			t.drop(e226)!
			return err
		})
		t.drop(e225)!
		t.drop(e226)!
		e228 := t.hold(invoke_owned(e221, [o(e224), o(e227)], {}, [e227, e224])!)
		t.take(e221)
		t.take(e224)
		t.take(e227)
		t.drop(e228)!
		t.clear()!
		// Original line 223: shutil.copy2(build / "fixtures/cxx-extended", destination / "cxx-extended")
		e229 := t.hold(global('shutil')!)
		e230 := t.hold(member(e229, 'copy2') or {
			t.drop(e229)!
			return err
		})
		t.drop(e229)!
		e231 := t.hold(f.load('build')!)
		e232 := t.hold(literal(ah.Value('fixtures/cxx-extended'))!)
		e233 := t.hold(operation('truediv', [e231, e232]) or {
			t.drop(e231)!
			t.drop(e232)!
			return err
		})
		t.drop(e231)!
		t.drop(e232)!
		e234 := t.hold(f.load('destination')!)
		e235 := t.hold(literal(ah.Value('cxx-extended'))!)
		e236 := t.hold(operation('truediv', [e234, e235]) or {
			t.drop(e234)!
			t.drop(e235)!
			return err
		})
		t.drop(e234)!
		t.drop(e235)!
		e237 := t.hold(invoke_owned(e230, [o(e233), o(e236)], {}, [e236, e233])!)
		t.take(e230)
		t.take(e233)
		t.take(e236)
		t.drop(e237)!
		t.clear()!
		// Original line 224: shutil.copy2(build / "fixtures/cxx-native", destination / "cxx-native")
		e238 := t.hold(global('shutil')!)
		e239 := t.hold(member(e238, 'copy2') or {
			t.drop(e238)!
			return err
		})
		t.drop(e238)!
		e240 := t.hold(f.load('build')!)
		e241 := t.hold(literal(ah.Value('fixtures/cxx-native'))!)
		e242 := t.hold(operation('truediv', [e240, e241]) or {
			t.drop(e240)!
			t.drop(e241)!
			return err
		})
		t.drop(e240)!
		t.drop(e241)!
		e243 := t.hold(f.load('destination')!)
		e244 := t.hold(literal(ah.Value('cxx-native'))!)
		e245 := t.hold(operation('truediv', [e243, e244]) or {
			t.drop(e243)!
			t.drop(e244)!
			return err
		})
		t.drop(e243)!
		t.drop(e244)!
		e246 := t.hold(invoke_owned(e239, [o(e242), o(e245)], {}, [e245, e242])!)
		t.take(e239)
		t.take(e242)
		t.take(e245)
		t.drop(e246)!
		t.clear()!
		// Original line 225: shutil.copy2(build / "fixtures/startup", destination / "startup")
		e247 := t.hold(global('shutil')!)
		e248 := t.hold(member(e247, 'copy2') or {
			t.drop(e247)!
			return err
		})
		t.drop(e247)!
		e249 := t.hold(f.load('build')!)
		e250 := t.hold(literal(ah.Value('fixtures/startup'))!)
		e251 := t.hold(operation('truediv', [e249, e250]) or {
			t.drop(e249)!
			t.drop(e250)!
			return err
		})
		t.drop(e249)!
		t.drop(e250)!
		e252 := t.hold(f.load('destination')!)
		e253 := t.hold(literal(ah.Value('startup'))!)
		e254 := t.hold(operation('truediv', [e252, e253]) or {
			t.drop(e252)!
			t.drop(e253)!
			return err
		})
		t.drop(e252)!
		t.drop(e253)!
		e255 := t.hold(invoke_owned(e248, [o(e251), o(e254)], {}, [e254, e251])!)
		t.take(e248)
		t.take(e251)
		t.take(e254)
		t.drop(e255)!
		t.clear()!
	}
	t.clear()!
	// Original line 226: shutil.copy2(build / "objc/Calculator.app/Calculator", destination / "UIKitCalculator")
	e256 := t.hold(global('shutil')!)
	e257 := t.hold(member(e256, 'copy2') or {
		t.drop(e256)!
		return err
	})
	t.drop(e256)!
	e258 := t.hold(f.load('build')!)
	e259 := t.hold(literal(ah.Value('objc/Calculator.app/Calculator'))!)
	e260 := t.hold(operation('truediv', [e258, e259]) or {
		t.drop(e258)!
		t.drop(e259)!
		return err
	})
	t.drop(e258)!
	t.drop(e259)!
	e261 := t.hold(f.load('destination')!)
	e262 := t.hold(literal(ah.Value('UIKitCalculator'))!)
	e263 := t.hold(operation('truediv', [e261, e262]) or {
		t.drop(e261)!
		t.drop(e262)!
		return err
	})
	t.drop(e261)!
	t.drop(e262)!
	e264 := t.hold(invoke_owned(e257, [o(e260), o(e263)], {}, [e263, e260])!)
	t.take(e257)
	t.take(e260)
	t.take(e263)
	t.drop(e264)!
	t.clear()!
	// Original line 227: if arguments.with_2048:
	e265 := t.hold(f.load('arguments')!)
	e266 := t.hold(member(e265, 'with_2048') or {
		t.drop(e265)!
		return err
	})
	t.drop(e265)!
	b267 := truth(e266) or {
		t.drop(e266)!
		return err
	}
	t.drop(e266)!
	if b267 {
		// Original line 228: shutil.copytree(build / "2048/NumberTileGame.app", destination / "NumberTileGame.app")
		e268 := t.hold(global('shutil')!)
		e269 := t.hold(member(e268, 'copytree') or {
			t.drop(e268)!
			return err
		})
		t.drop(e268)!
		e270 := t.hold(f.load('build')!)
		e271 := t.hold(literal(ah.Value('2048/NumberTileGame.app'))!)
		e272 := t.hold(operation('truediv', [e270, e271]) or {
			t.drop(e270)!
			t.drop(e271)!
			return err
		})
		t.drop(e270)!
		t.drop(e271)!
		e273 := t.hold(f.load('destination')!)
		e274 := t.hold(literal(ah.Value('NumberTileGame.app'))!)
		e275 := t.hold(operation('truediv', [e273, e274]) or {
			t.drop(e273)!
			t.drop(e274)!
			return err
		})
		t.drop(e273)!
		t.drop(e274)!
		e276 := t.hold(invoke_owned(e269, [o(e272), o(e275)], {}, [e275, e272])!)
		t.take(e269)
		t.take(e272)
		t.take(e275)
		t.drop(e276)!
		t.clear()!
		// Original line 229: shutil.copy2(build / "2048/model-tests", destination / "model-tests")
		e277 := t.hold(global('shutil')!)
		e278 := t.hold(member(e277, 'copy2') or {
			t.drop(e277)!
			return err
		})
		t.drop(e277)!
		e279 := t.hold(f.load('build')!)
		e280 := t.hold(literal(ah.Value('2048/model-tests'))!)
		e281 := t.hold(operation('truediv', [e279, e280]) or {
			t.drop(e279)!
			t.drop(e280)!
			return err
		})
		t.drop(e279)!
		t.drop(e280)!
		e282 := t.hold(f.load('destination')!)
		e283 := t.hold(literal(ah.Value('model-tests'))!)
		e284 := t.hold(operation('truediv', [e282, e283]) or {
			t.drop(e282)!
			t.drop(e283)!
			return err
		})
		t.drop(e282)!
		t.drop(e283)!
		e285 := t.hold(invoke_owned(e278, [o(e281), o(e284)], {}, [e284, e281])!)
		t.take(e278)
		t.take(e281)
		t.take(e284)
		t.drop(e285)!
		t.clear()!
	}
	t.clear()!
	// Original line 230: if arguments.with_ppsspp:
	e286 := t.hold(f.load('arguments')!)
	e287 := t.hold(member(e286, 'with_ppsspp') or {
		t.drop(e286)!
		return err
	})
	t.drop(e286)!
	b288 := truth(e287) or {
		t.drop(e287)!
		return err
	}
	t.drop(e287)!
	if b288 {
		// Original line 231: if arguments.ppsspp_muted:
		e289 := t.hold(f.load('arguments')!)
		e290 := t.hold(member(e289, 'ppsspp_muted') or {
			t.drop(e289)!
			return err
		})
		t.drop(e289)!
		b291 := truth(e290) or {
			t.drop(e290)!
			return err
		}
		t.drop(e290)!
		if b291 {
			// Original line 232: installed = rootfs / "usr/share/vinix/ios/PPSSPP.app"
			e292 := t.hold(f.load('rootfs')!)
			e293 := t.hold(literal(ah.Value('usr/share/vinix/ios/PPSSPP.app'))!)
			e294 := t.hold(operation('truediv', [e292, e293]) or {
				t.drop(e292)!
				t.drop(e293)!
				return err
			})
			t.drop(e292)!
			t.drop(e293)!
			f.named('installed', t.take(e294))!
			t.clear()!
			// Original line 233: shutil.copytree(build / "ppsspp/unpacked/Payload/PPSSPP.app", installed, copy_function=stage_game_asset)
			e295 := t.hold(global('shutil')!)
			e296 := t.hold(member(e295, 'copytree') or {
				t.drop(e295)!
				return err
			})
			t.drop(e295)!
			e297 := t.hold(f.load('build')!)
			e298 := t.hold(literal(ah.Value('ppsspp/unpacked/Payload/PPSSPP.app'))!)
			e299 := t.hold(operation('truediv', [e297, e298]) or {
				t.drop(e297)!
				t.drop(e298)!
				return err
			})
			t.drop(e297)!
			t.drop(e298)!
			e300 := t.hold(f.load('installed')!)
			e301 := t.hold(global('stage_game_asset')!)
			e302 := t.hold(invoke_owned(e296, [o(e299), o(e300)], {
				'copy_function': o(e301)
			}, [e301, e300, e299])!)
			t.take(e296)
			t.take(e299)
			t.take(e300)
			t.take(e301)
			t.drop(e302)!
			t.clear()!
			// Original line 234: (destination / "PPSSPP").symlink_to("/usr/share/vinix/ios/PPSSPP.app/PPSSPP")
			e303 := t.hold(f.load('destination')!)
			e304 := t.hold(literal(ah.Value('PPSSPP'))!)
			e305 := t.hold(operation('truediv', [e303, e304]) or {
				t.drop(e303)!
				t.drop(e304)!
				return err
			})
			t.drop(e303)!
			t.drop(e304)!
			e306 := t.hold(member(e305, 'symlink_to') or {
				t.drop(e305)!
				return err
			})
			t.drop(e305)!
			e307 := t.hold(literal(ah.Value('/usr/share/vinix/ios/PPSSPP.app/PPSSPP'))!)
			e308 := t.hold(invoke_owned(e306, [o(e307)], {}, [e307])!)
			t.take(e306)
			t.take(e307)
			t.drop(e308)!
			t.clear()!
			// Original line 235: binary = rootfs / "usr/bin"
			e309 := t.hold(f.load('rootfs')!)
			e310 := t.hold(literal(ah.Value('usr/bin'))!)
			e311 := t.hold(operation('truediv', [e309, e310]) or {
				t.drop(e309)!
				t.drop(e310)!
				return err
			})
			t.drop(e309)!
			t.drop(e310)!
			f.named('binary', t.take(e311))!
			t.clear()!
			// Original line 236: binary.mkdir(parents=True)
			e312 := t.hold(f.load('binary')!)
			e313 := t.hold(member(e312, 'mkdir') or {
				t.drop(e312)!
				return err
			})
			t.drop(e312)!
			e314 := t.hold(literal(ah.Value(true))!)
			e315 := t.hold(invoke_owned(e313, [], {
				'parents': o(e314)
			}, [e314])!)
			t.take(e313)
			t.take(e314)
			t.drop(e315)!
			t.clear()!
			// Original line 237: shutil.copy2(build / "staging/usr/bin/run-ios-gles", binary / "run-ios-gles")
			e316 := t.hold(global('shutil')!)
			e317 := t.hold(member(e316, 'copy2') or {
				t.drop(e316)!
				return err
			})
			t.drop(e316)!
			e318 := t.hold(f.load('build')!)
			e319 := t.hold(literal(ah.Value('staging/usr/bin/run-ios-gles'))!)
			e320 := t.hold(operation('truediv', [e318, e319]) or {
				t.drop(e318)!
				t.drop(e319)!
				return err
			})
			t.drop(e318)!
			t.drop(e319)!
			e321 := t.hold(f.load('binary')!)
			e322 := t.hold(literal(ah.Value('run-ios-gles'))!)
			e323 := t.hold(operation('truediv', [e321, e322]) or {
				t.drop(e321)!
				t.drop(e322)!
				return err
			})
			t.drop(e321)!
			t.drop(e322)!
			e324 := t.hold(invoke_owned(e317, [o(e320), o(e323)], {}, [e323, e320])!)
			t.take(e317)
			t.take(e320)
			t.take(e323)
			t.drop(e324)!
			t.clear()!
			// Original line 238: (binary / "vinix-ios-ppsspp").symlink_to("run-ios-gles")
			e325 := t.hold(f.load('binary')!)
			e326 := t.hold(literal(ah.Value('vinix-ios-ppsspp'))!)
			e327 := t.hold(operation('truediv', [e325, e326]) or {
				t.drop(e325)!
				t.drop(e326)!
				return err
			})
			t.drop(e325)!
			t.drop(e326)!
			e328 := t.hold(member(e327, 'symlink_to') or {
				t.drop(e327)!
				return err
			})
			t.drop(e327)!
			e329 := t.hold(literal(ah.Value('run-ios-gles'))!)
			e330 := t.hold(invoke_owned(e328, [o(e329)], {}, [e329])!)
			t.take(e328)
			t.take(e329)
			t.drop(e330)!
			t.clear()!
			// Original line 239: (destination / "ppsspp-muted").touch()
			e331 := t.hold(f.load('destination')!)
			e332 := t.hold(literal(ah.Value('ppsspp-muted'))!)
			e333 := t.hold(operation('truediv', [e331, e332]) or {
				t.drop(e331)!
				t.drop(e332)!
				return err
			})
			t.drop(e331)!
			t.drop(e332)!
			e334 := t.hold(member(e333, 'touch') or {
				t.drop(e333)!
				return err
			})
			t.drop(e333)!
			e335 := t.hold(invoke_owned(e334, [], {}, [])!)
			t.take(e334)
			t.drop(e335)!
			t.clear()!
			// Original line 240: if arguments.ppsspp_cube:
			e336 := t.hold(f.load('arguments')!)
			e337 := t.hold(member(e336, 'ppsspp_cube') or {
				t.drop(e336)!
				return err
			})
			t.drop(e336)!
			b338 := truth(e337) or {
				t.drop(e337)!
				return err
			}
			t.drop(e337)!
			if b338 {
				// Original line 241: shutil.copy2(build / "ppsspp/cube.pbp", destination / "cube.pbp")
				e339 := t.hold(global('shutil')!)
				e340 := t.hold(member(e339, 'copy2') or {
					t.drop(e339)!
					return err
				})
				t.drop(e339)!
				e341 := t.hold(f.load('build')!)
				e342 := t.hold(literal(ah.Value('ppsspp/cube.pbp'))!)
				e343 := t.hold(operation('truediv', [e341, e342]) or {
					t.drop(e341)!
					t.drop(e342)!
					return err
				})
				t.drop(e341)!
				t.drop(e342)!
				e344 := t.hold(f.load('destination')!)
				e345 := t.hold(literal(ah.Value('cube.pbp'))!)
				e346 := t.hold(operation('truediv', [e344, e345]) or {
					t.drop(e344)!
					t.drop(e345)!
					return err
				})
				t.drop(e344)!
				t.drop(e345)!
				e347 := t.hold(invoke_owned(e340, [o(e343), o(e346)], {}, [e346, e343])!)
				t.take(e340)
				t.take(e343)
				t.take(e346)
				t.drop(e347)!
				t.clear()!
				// Original line 242: (destination / "ppsspp-cube").touch()
				e348 := t.hold(f.load('destination')!)
				e349 := t.hold(literal(ah.Value('ppsspp-cube'))!)
				e350 := t.hold(operation('truediv', [e348, e349]) or {
					t.drop(e348)!
					t.drop(e349)!
					return err
				})
				t.drop(e348)!
				t.drop(e349)!
				e351 := t.hold(member(e350, 'touch') or {
					t.drop(e350)!
					return err
				})
				t.drop(e350)!
				e352 := t.hold(invoke_owned(e351, [], {}, [])!)
				t.take(e351)
				t.drop(e352)!
				t.clear()!
			}
			t.clear()!
			// Original line 243: if arguments.ppsspp_nzp:
			e353 := t.hold(f.load('arguments')!)
			e354 := t.hold(member(e353, 'ppsspp_nzp') or {
				t.drop(e353)!
				return err
			})
			t.drop(e353)!
			b355 := truth(e354) or {
				t.drop(e354)!
				return err
			}
			t.drop(e354)!
			if b355 {
				// Original line 244: game = destination / "ppsspp-documents/PSP/GAME/nzportable"
				e356 := t.hold(f.load('destination')!)
				e357 := t.hold(literal(ah.Value('ppsspp-documents/PSP/GAME/nzportable'))!)
				e358 := t.hold(operation('truediv', [e356, e357]) or {
					t.drop(e356)!
					t.drop(e357)!
					return err
				})
				t.drop(e356)!
				t.drop(e357)!
				f.named('game', t.take(e358))!
				t.clear()!
				// Original line 245: shutil.copytree(build / "nzportable/unpacked/nzportable", game, copy_function=stage_game_asset)
				e359 := t.hold(global('shutil')!)
				e360 := t.hold(member(e359, 'copytree') or {
					t.drop(e359)!
					return err
				})
				t.drop(e359)!
				e361 := t.hold(f.load('build')!)
				e362 := t.hold(literal(ah.Value('nzportable/unpacked/nzportable'))!)
				e363 := t.hold(operation('truediv', [e361, e362]) or {
					t.drop(e361)!
					t.drop(e362)!
					return err
				})
				t.drop(e361)!
				t.drop(e362)!
				e364 := t.hold(f.load('game')!)
				e365 := t.hold(global('stage_game_asset')!)
				e366 := t.hold(invoke_owned(e360, [o(e363), o(e364)], {
					'copy_function': o(e365)
				}, [e365, e364, e363])!)
				t.take(e360)
				t.take(e363)
				t.take(e364)
				t.take(e365)
				t.drop(e366)!
				t.clear()!
				// Original line 248: (game / "setup.ini").write_text("-condebug +developer 1 +exec vinix-input.cfg\n")
				e367 := t.hold(f.load('game')!)
				e368 := t.hold(literal(ah.Value('setup.ini'))!)
				e369 := t.hold(operation('truediv', [e367, e368]) or {
					t.drop(e367)!
					t.drop(e368)!
					return err
				})
				t.drop(e367)!
				t.drop(e368)!
				e370 := t.hold(member(e369, 'write_text') or {
					t.drop(e369)!
					return err
				})
				t.drop(e369)!
				e371 := t.hold(literal(ah.Value('-condebug +developer 1 +exec vinix-input.cfg\n'))!)
				e372 := t.hold(invoke_owned(e370, [o(e371)], {}, [e371])!)
				t.take(e370)
				t.take(e371)
				t.drop(e372)!
				t.clear()!
				// Original line 249: (game / "nzp/vinix-input.cfg").write_text('bind "SELECT" "edict 1; echo VINIX-NZP-STATE-DONE"\nbinddt "SELECT" ""\n')
				e373 := t.hold(f.load('game')!)
				e374 := t.hold(literal(ah.Value('nzp/vinix-input.cfg'))!)
				e375 := t.hold(operation('truediv', [e373, e374]) or {
					t.drop(e373)!
					t.drop(e374)!
					return err
				})
				t.drop(e373)!
				t.drop(e374)!
				e376 := t.hold(member(e375, 'write_text') or {
					t.drop(e375)!
					return err
				})
				t.drop(e375)!
				e377 := t.hold(literal(ah.Value('bind "SELECT" "edict 1; echo VINIX-NZP-STATE-DONE"\nbinddt "SELECT" ""\n'))!)
				e378 := t.hold(invoke_owned(e376, [o(e377)], {}, [e377])!)
				t.take(e376)
				t.take(e377)
				t.drop(e378)!
				t.clear()!
				// Original line 250: (destination / "ppsspp-nzp").touch()
				e379 := t.hold(f.load('destination')!)
				e380 := t.hold(literal(ah.Value('ppsspp-nzp'))!)
				e381 := t.hold(operation('truediv', [e379, e380]) or {
					t.drop(e379)!
					t.drop(e380)!
					return err
				})
				t.drop(e379)!
				t.drop(e380)!
				e382 := t.hold(member(e381, 'touch') or {
					t.drop(e381)!
					return err
				})
				t.drop(e381)!
				e383 := t.hold(invoke_owned(e382, [], {}, [])!)
				t.take(e382)
				t.drop(e383)!
				t.clear()!
			}
			t.clear()!
			// Original line 251: if arguments.ppsspp_gow:
			e384 := t.hold(f.load('arguments')!)
			e385 := t.hold(member(e384, 'ppsspp_gow') or {
				t.drop(e384)!
				return err
			})
			t.drop(e384)!
			b386 := truth(e385) or {
				t.drop(e385)!
				return err
			}
			t.drop(e385)!
			if b386 {
				// Original line 252: game = destination / "ppsspp-documents/PSP/GAME/UCUS98713"
				e387 := t.hold(f.load('destination')!)
				e388 := t.hold(literal(ah.Value('ppsspp-documents/PSP/GAME/UCUS98713'))!)
				e389 := t.hold(operation('truediv', [e387, e388]) or {
					t.drop(e387)!
					t.drop(e388)!
					return err
				})
				t.drop(e387)!
				t.drop(e388)!
				f.named('game', t.take(e389))!
				t.clear()!
				// Original line 253: shutil.copytree(build / "god-of-war/unpacked/PSP/GAME/UCUS98713", game, copy_function=stage_game_asset)
				e390 := t.hold(global('shutil')!)
				e391 := t.hold(member(e390, 'copytree') or {
					t.drop(e390)!
					return err
				})
				t.drop(e390)!
				e392 := t.hold(f.load('build')!)
				e393 := t.hold(literal(ah.Value('god-of-war/unpacked/PSP/GAME/UCUS98713'))!)
				e394 := t.hold(operation('truediv', [e392, e393]) or {
					t.drop(e392)!
					t.drop(e393)!
					return err
				})
				t.drop(e392)!
				t.drop(e393)!
				e395 := t.hold(f.load('game')!)
				e396 := t.hold(global('stage_game_asset')!)
				e397 := t.hold(invoke_owned(e391, [o(e394), o(e395)], {
					'copy_function': o(e396)
				}, [e396, e395, e394])!)
				t.take(e391)
				t.take(e394)
				t.take(e395)
				t.take(e396)
				t.drop(e397)!
				t.clear()!
				// Original line 254: system = destination / "ppsspp-documents/PSP/SYSTEM"
				e398 := t.hold(f.load('destination')!)
				e399 := t.hold(literal(ah.Value('ppsspp-documents/PSP/SYSTEM'))!)
				e400 := t.hold(operation('truediv', [e398, e399]) or {
					t.drop(e398)!
					t.drop(e399)!
					return err
				})
				t.drop(e398)!
				t.drop(e399)!
				f.named('system', t.take(e400))!
				t.clear()!
				// Original line 255: system.mkdir(parents=True)
				e401 := t.hold(f.load('system')!)
				e402 := t.hold(member(e401, 'mkdir') or {
					t.drop(e401)!
					return err
				})
				t.drop(e401)!
				e403 := t.hold(literal(ah.Value(true))!)
				e404 := t.hold(invoke_owned(e402, [], {
					'parents': o(e403)
				}, [e403])!)
				t.take(e402)
				t.take(e403)
				t.drop(e404)!
				t.clear()!
				// Original line 258: (system / "ppsspp.ini").write_text("[Sound]\nEnable=False\n[Graphics]\nInternalResolution=1\n")
				e405 := t.hold(f.load('system')!)
				e406 := t.hold(literal(ah.Value('ppsspp.ini'))!)
				e407 := t.hold(operation('truediv', [e405, e406]) or {
					t.drop(e405)!
					t.drop(e406)!
					return err
				})
				t.drop(e405)!
				t.drop(e406)!
				e408 := t.hold(member(e407, 'write_text') or {
					t.drop(e407)!
					return err
				})
				t.drop(e407)!
				e409 := t.hold(literal(ah.Value('[Sound]\nEnable=False\n[Graphics]\nInternalResolution=1\n'))!)
				e410 := t.hold(invoke_owned(e408, [o(e409)], {}, [e409])!)
				t.take(e408)
				t.take(e409)
				t.drop(e410)!
				t.clear()!
				// Original line 259: (destination / "ppsspp-gow").touch()
				e411 := t.hold(f.load('destination')!)
				e412 := t.hold(literal(ah.Value('ppsspp-gow'))!)
				e413 := t.hold(operation('truediv', [e411, e412]) or {
					t.drop(e411)!
					t.drop(e412)!
					return err
				})
				t.drop(e411)!
				t.drop(e412)!
				e414 := t.hold(member(e413, 'touch') or {
					t.drop(e413)!
					return err
				})
				t.drop(e413)!
				e415 := t.hold(invoke_owned(e414, [], {}, [])!)
				t.take(e414)
				t.drop(e415)!
				t.clear()!
			}
			t.clear()!
		} else {
			// Original line 261: shutil.copytree(build / "ppsspp/unpacked/Payload/PPSSPP.app", destination / "PPSSPP.app", copy_function=stage_game_asset)
			e416 := t.hold(global('shutil')!)
			e417 := t.hold(member(e416, 'copytree') or {
				t.drop(e416)!
				return err
			})
			t.drop(e416)!
			e418 := t.hold(f.load('build')!)
			e419 := t.hold(literal(ah.Value('ppsspp/unpacked/Payload/PPSSPP.app'))!)
			e420 := t.hold(operation('truediv', [e418, e419]) or {
				t.drop(e418)!
				t.drop(e419)!
				return err
			})
			t.drop(e418)!
			t.drop(e419)!
			e421 := t.hold(f.load('destination')!)
			e422 := t.hold(literal(ah.Value('PPSSPP.app'))!)
			e423 := t.hold(operation('truediv', [e421, e422]) or {
				t.drop(e421)!
				t.drop(e422)!
				return err
			})
			t.drop(e421)!
			t.drop(e422)!
			e424 := t.hold(global('stage_game_asset')!)
			e425 := t.hold(invoke_owned(e417, [o(e420), o(e423)], {
				'copy_function': o(e424)
			}, [e424, e423, e420])!)
			t.take(e417)
			t.take(e420)
			t.take(e423)
			t.take(e424)
			t.drop(e425)!
			t.clear()!
			// Original line 262: (destination / "PPSSPP").symlink_to("PPSSPP.app/PPSSPP")
			e426 := t.hold(f.load('destination')!)
			e427 := t.hold(literal(ah.Value('PPSSPP'))!)
			e428 := t.hold(operation('truediv', [e426, e427]) or {
				t.drop(e426)!
				t.drop(e427)!
				return err
			})
			t.drop(e426)!
			t.drop(e427)!
			e429 := t.hold(member(e428, 'symlink_to') or {
				t.drop(e428)!
				return err
			})
			t.drop(e428)!
			e430 := t.hold(literal(ah.Value('PPSSPP.app/PPSSPP'))!)
			e431 := t.hold(invoke_owned(e429, [o(e430)], {}, [e430])!)
			t.take(e429)
			t.take(e430)
			t.drop(e431)!
			t.clear()!
		}
		t.clear()!
	}
	t.clear()!
	// Original line 263: prepare_images(build / "fixtures", destination)
	e432 := t.hold(global('prepare_images')!)
	e433 := t.hold(f.load('build')!)
	e434 := t.hold(literal(ah.Value('fixtures'))!)
	e435 := t.hold(operation('truediv', [e433, e434]) or {
		t.drop(e433)!
		t.drop(e434)!
		return err
	})
	t.drop(e433)!
	t.drop(e434)!
	e436 := t.hold(f.load('destination')!)
	e437 := t.hold(invoke_owned(e432, [o(e435), o(e436)], {}, [e436, e435])!)
	t.take(e432)
	t.take(e435)
	t.take(e436)
	t.drop(e437)!
	t.clear()!
	// Original line 265: sysroot = Path(os.environ.get("VINIX_IOS_TEST_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
	e438 := t.hold(global('Path')!)
	e439 := t.hold(global('os')!)
	e440 := t.hold(member(e439, 'environ') or {
		t.drop(e439)!
		return err
	})
	t.drop(e439)!
	e441 := t.hold(member(e440, 'get') or {
		t.drop(e440)!
		return err
	})
	t.drop(e440)!
	e442 := t.hold(literal(ah.Value('VINIX_IOS_TEST_SYSROOT'))!)
	e443 := t.hold(global('ROOT')!)
	e444 := t.hold(literal(ah.Value('build-aarch64-userland/sysroot'))!)
	e445 := t.hold(operation('truediv', [e443, e444]) or {
		t.drop(e443)!
		t.drop(e444)!
		return err
	})
	t.drop(e443)!
	t.drop(e444)!
	e446 := t.hold(invoke_owned(e441, [o(e442), o(e445)], {}, [e445, e442])!)
	t.take(e441)
	t.take(e442)
	t.take(e445)
	e447 := t.hold(invoke_owned(e438, [o(e446)], {}, [e446])!)
	t.take(e438)
	t.take(e446)
	f.named('sysroot', t.take(e447))!
	t.clear()!
	// Original line 266: subprocess.run([
	e448 := t.hold(global('subprocess')!)
	e449 := t.hold(member(e448, 'run') or {
		t.drop(e448)!
		return err
	})
	t.drop(e448)!
	e450 := t.hold(global('os')!)
	e451 := t.hold(member(e450, 'environ') or {
		t.drop(e450)!
		return err
	})
	t.drop(e450)!
	e452 := t.hold(member(e451, 'get') or {
		t.drop(e451)!
		return err
	})
	t.drop(e451)!
	e453 := t.hold(literal(ah.Value('CC'))!)
	e454 := t.hold(literal(ah.Value('clang'))!)
	e455 := t.hold(invoke_owned(e452, [o(e453), o(e454)], {}, [e454, e453])!)
	t.take(e452)
	t.take(e453)
	t.take(e454)
	e456 := t.hold(literal(ah.Value('--target=aarch64-linux-musl'))!)
	e457 := t.hold(literal(ah.Value('--sysroot='))!)
	e458 := t.hold(f.load('sysroot')!)
	e459 := t.hold(formatted(e458, false) or {
		t.drop(e458)!
		return err
	})
	t.drop(e458)!
	e460 := t.hold(concatenate([e457, e459])!)
	t.take(e457)
	t.take(e459)
	e461 := t.hold(literal(ah.Value('-static'))!)
	e462 := t.hold(literal(ah.Value('-O2'))!)
	e463 := t.hold(literal(ah.Value('-fno-stack-protector'))!)
	e464 := t.hold(literal(ah.Value('-Wall'))!)
	e465 := t.hold(literal(ah.Value('-Wextra'))!)
	e466 := t.hold(literal(ah.Value('-Werror'))!)
	e467 := t.hold(global('str')!)
	e468 := t.hold(global('ROOT')!)
	e469 := t.hold(literal(ah.Value('tests/ios/guest.c'))!)
	e470 := t.hold(operation('truediv', [e468, e469]) or {
		t.drop(e468)!
		t.drop(e469)!
		return err
	})
	t.drop(e468)!
	t.drop(e469)!
	e471 := t.hold(invoke_owned(e467, [o(e470)], {}, [e470])!)
	t.take(e467)
	t.take(e470)
	e472 := t.hold(global('str')!)
	e473 := t.hold(global('ROOT')!)
	e474 := t.hold(literal(ah.Value('tests/ios/uikit-guest.c'))!)
	e475 := t.hold(operation('truediv', [e473, e474]) or {
		t.drop(e473)!
		t.drop(e474)!
		return err
	})
	t.drop(e473)!
	t.drop(e474)!
	e476 := t.hold(invoke_owned(e472, [o(e475)], {}, [e475])!)
	t.take(e472)
	t.take(e475)
	e477 := t.hold(global('str')!)
	e478 := t.hold(global('ROOT')!)
	e479 := t.hold(literal(ah.Value('tests/ios/gles-guest.c'))!)
	e480 := t.hold(operation('truediv', [e478, e479]) or {
		t.drop(e478)!
		t.drop(e479)!
		return err
	})
	t.drop(e478)!
	t.drop(e479)!
	e481 := t.hold(invoke_owned(e477, [o(e480)], {}, [e480])!)
	t.take(e477)
	t.take(e480)
	e482 := t.hold(literal(ah.Value('-L'))!)
	e483 := t.hold(f.load('sysroot')!)
	e484 := t.hold(literal(ah.Value('lib'))!)
	e485 := t.hold(operation('truediv', [e483, e484]) or {
		t.drop(e483)!
		t.drop(e484)!
		return err
	})
	t.drop(e483)!
	t.drop(e484)!
	e486 := t.hold(formatted(e485, false) or {
		t.drop(e485)!
		return err
	})
	t.drop(e485)!
	e487 := t.hold(concatenate([e482, e486])!)
	t.take(e482)
	t.take(e486)
	e488 := t.hold(literal(ah.Value('-fuse-ld=lld'))!)
	e489 := t.hold(literal(ah.Value('-o'))!)
	e490 := t.hold(global('str')!)
	e491 := t.hold(f.load('work')!)
	e492 := t.hold(literal(ah.Value('init'))!)
	e493 := t.hold(operation('truediv', [e491, e492]) or {
		t.drop(e491)!
		t.drop(e492)!
		return err
	})
	t.drop(e491)!
	t.drop(e492)!
	e494 := t.hold(invoke_owned(e490, [o(e493)], {}, [e493])!)
	t.take(e490)
	t.take(e493)
	e495 := t.hold(resolve('_list')!)
	e496 := t.hold(invoke_owned(e495, [o(e455), o(e456), o(e460), o(e461), o(e462), o(e463), o(e464),
		o(e465), o(e466), o(e471), o(e476), o(e481), o(e487), o(e488), o(e489), o(e494)], {}, [
		e494,
		e489,
		e488,
		e487,
		e481,
		e476,
		e471,
		e466,
		e465,
		e464,
		e463,
		e462,
		e461,
		e460,
		e456,
		e455,
	])!)
	t.take(e495)
	t.take(e455)
	t.take(e456)
	t.take(e460)
	t.take(e461)
	t.take(e462)
	t.take(e463)
	t.take(e464)
	t.take(e465)
	t.take(e466)
	t.take(e471)
	t.take(e476)
	t.take(e481)
	t.take(e487)
	t.take(e488)
	t.take(e489)
	t.take(e494)
	e497 := t.hold(literal(ah.Value(true))!)
	e498 := t.hold(invoke_owned(e449, [o(e496)], {
		'check': o(e497)
	}, [e497, e496])!)
	t.take(e449)
	t.take(e496)
	t.take(e497)
	t.drop(e498)!
	t.clear()!
	// Original line 273: archive = work / ("initramfs.tar.gz" if arguments.with_gles else "initramfs.tar")
	e499 := t.hold(f.load('work')!)
	mut e500 := ''
	e501 := t.hold(f.load('arguments')!)
	e502 := t.hold(member(e501, 'with_gles') or {
		t.drop(e501)!
		return err
	})
	t.drop(e501)!
	b503 := truth(e502) or {
		t.drop(e502)!
		return err
	}
	t.drop(e502)!
	if b503 {
		e504 := t.hold(literal(ah.Value('initramfs.tar.gz'))!)
		e500 = e504
	} else {
		e505 := t.hold(literal(ah.Value('initramfs.tar'))!)
		e500 = e505
	}
	e506 := t.hold(operation('truediv', [e499, e500]) or {
		t.drop(e499)!
		t.drop(e500)!
		return err
	})
	t.drop(e499)!
	t.drop(e500)!
	f.named('archive', t.take(e506))!
	t.clear()!
	return literal(none_())!
}

fn finish(mut f Frame) !string {
	mut t := Temps{}
	defer { t.clear() or {} }
	// Original line 288: os.environ["VINIX_QEMU_RT_NO_BUILD"] = "1"
	e1 := t.hold(literal(ah.Value('1'))!)
	e2 := t.hold(global('os')!)
	e3 := t.hold(member(e2, 'environ') or {
		t.drop(e2)!
		return err
	})
	t.drop(e2)!
	e4 := t.hold(literal(ah.Value('VINIX_QEMU_RT_NO_BUILD'))!)
	release([operation('setitem', [e3, e4, e1]) or {
		t.drop(e1)!
		t.drop(e3)!
		t.drop(e4)!
		return err
	}])!
	t.drop(e1)!
	t.drop(e3)!
	t.drop(e4)!
	t.clear()!
	// Original line 289: os.environ["VINIX_QEMU_HOST_SOURCE"] = "0"
	e5 := t.hold(literal(ah.Value('0'))!)
	e6 := t.hold(global('os')!)
	e7 := t.hold(member(e6, 'environ') or {
		t.drop(e6)!
		return err
	})
	t.drop(e6)!
	e8 := t.hold(literal(ah.Value('VINIX_QEMU_HOST_SOURCE'))!)
	release([operation('setitem', [e7, e8, e5]) or {
		t.drop(e5)!
		t.drop(e7)!
		t.drop(e8)!
		return err
	}])!
	t.drop(e5)!
	t.drop(e7)!
	t.drop(e8)!
	t.clear()!
	// Original line 290: os.environ["VINIX_QEMU_CLIPBOARD"] = "0"
	e9 := t.hold(literal(ah.Value('0'))!)
	e10 := t.hold(global('os')!)
	e11 := t.hold(member(e10, 'environ') or {
		t.drop(e10)!
		return err
	})
	t.drop(e10)!
	e12 := t.hold(literal(ah.Value('VINIX_QEMU_CLIPBOARD'))!)
	release([operation('setitem', [e11, e12, e9]) or {
		t.drop(e9)!
		t.drop(e11)!
		t.drop(e12)!
		return err
	}])!
	t.drop(e9)!
	t.drop(e11)!
	t.drop(e12)!
	t.clear()!
	// Original line 291: os.environ["VINIX_QEMU_AUDIO"] = "off"
	e13 := t.hold(literal(ah.Value('off'))!)
	e14 := t.hold(global('os')!)
	e15 := t.hold(member(e14, 'environ') or {
		t.drop(e14)!
		return err
	})
	t.drop(e14)!
	e16 := t.hold(literal(ah.Value('VINIX_QEMU_AUDIO'))!)
	release([operation('setitem', [e15, e16, e13]) or {
		t.drop(e13)!
		t.drop(e15)!
		t.drop(e16)!
		return err
	}])!
	t.drop(e13)!
	t.drop(e15)!
	t.drop(e16)!
	t.clear()!
	// Original line 292: os.environ["VINIX_QEMU_NETWORK"] = "0"
	e17 := t.hold(literal(ah.Value('0'))!)
	e18 := t.hold(global('os')!)
	e19 := t.hold(member(e18, 'environ') or {
		t.drop(e18)!
		return err
	})
	t.drop(e18)!
	e20 := t.hold(literal(ah.Value('VINIX_QEMU_NETWORK'))!)
	release([operation('setitem', [e19, e20, e17]) or {
		t.drop(e17)!
		t.drop(e19)!
		t.drop(e20)!
		return err
	}])!
	t.drop(e17)!
	t.drop(e19)!
	t.drop(e20)!
	t.clear()!
	// Original line 293: return runner.run_vm(runner_root, work / "init", archive, work / "vm", arguments.timeout)
	e21 := t.hold(f.load('runner')!)
	e22 := t.hold(member(e21, 'run_vm') or {
		t.drop(e21)!
		return err
	})
	t.drop(e21)!
	e23 := t.hold(f.load('runner_root')!)
	e24 := t.hold(f.load('work')!)
	e25 := t.hold(literal(ah.Value('init'))!)
	e26 := t.hold(operation('truediv', [e24, e25]) or {
		t.drop(e24)!
		t.drop(e25)!
		return err
	})
	t.drop(e24)!
	t.drop(e25)!
	e27 := t.hold(f.load('archive')!)
	e28 := t.hold(f.load('work')!)
	e29 := t.hold(literal(ah.Value('vm'))!)
	e30 := t.hold(operation('truediv', [e28, e29]) or {
		t.drop(e28)!
		t.drop(e29)!
		return err
	})
	t.drop(e28)!
	t.drop(e29)!
	e31 := t.hold(f.load('arguments')!)
	e32 := t.hold(member(e31, 'timeout') or {
		t.drop(e31)!
		return err
	})
	t.drop(e31)!
	e33 := t.hold(invoke_owned(e22, [o(e23), o(e26), o(e27), o(e30), o(e32)], {}, [
		e32,
		e30,
		e27,
		e26,
		e23,
	])!)
	t.take(e22)
	t.take(e23)
	t.take(e26)
	t.take(e27)
	t.take(e30)
	t.take(e32)
	return t.take(e33)
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	ids := ah.field(row, 'arguments').items().map(it.text())
	current_builtins = ids[1]
	mut f := Frame{ start: checkpoint()!, pins: ids[0], scope: ids[2] }
	result := match ah.field(row, 'operation').text() {
		'images' { images(mut f) or {
			f.failed()!
			return err
		} }
		'plan' { plan(mut f) or {
			f.failed()!
			return err
		} }
		'stage' { stage(mut f) or {
			f.failed()!
			return err
		} }
		'finish' { finish(mut f) or {
			f.failed()!
			return err
		} }
		else { return error('unknown IOS controller operation') }
	}
	clean_since(f.start, [result])!
	return ah.Value(result)
}
