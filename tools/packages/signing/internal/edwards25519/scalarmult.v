module edwards25519

// This table belongs to the scalar multiplication that requested it.
fn basepoint_table() []AffineLookupTable {
	mut table := []AffineLookupTable{len: 32}
	mut p := new_generator_point()
	for i := 0; i < 32; i++ {
		table[i].from_p3(p)
		for j := 0; j < 8; j++ {
			p.add(p, p)
		}
	}
	return table
}

// scalar_base_mult sets v = x * B, where B is the canonical generator, and
// returns v.
//
// The scalar multiplication is done in constant time.
pub fn (mut v Point) scalar_base_mult(mut x Scalar) Point {
	mut bpt_table := basepoint_table()
	defer { unsafe { bpt_table.free() } }

	// Write x = sum(x_i * 16^i) so  x*B = sum( B*x_i*16^i )
	// as described in the Ed25519 paper
	//
	// Group even and odd coefficients
	// x*B     = x_0*16^0*B + x_2*16^2*B + ... + x_62*16^62*B
	//         + x_1*16^1*B + x_3*16^3*B + ... + x_63*16^63*B
	// x*B     = x_0*16^0*B + x_2*16^2*B + ... + x_62*16^62*B
	//    + 16*( x_1*16^0*B + x_3*16^2*B + ... + x_63*16^62*B)
	//
	// We use a lookup table for each i to get x_i*16^(2*i)*B
	// and do four doublings to multiply by 16.
	digits := x.signed_radix16()
	defer { unsafe { digits.free() } }

	mut multiple := AffineCached{}
	mut tmp1 := ProjectiveP1{}
	mut tmp2 := ProjectiveP2{}

	// Accumulate the odd components first
	v.set(new_identity_point())
	for i := 1; i < 64; i += 2 {
		bpt_table[i / 2].select_into(mut multiple, digits[i])
		tmp1.add_affine(v, multiple)
		v.from_p1(tmp1)
	}

	// Multiply by 16
	tmp2.from_p3(v) // tmp2 =    v in P2 coords
	tmp1.double(tmp2) // tmp1 =  2*v in P1xP1 coords
	tmp2.from_p1(tmp1) // tmp2 =  2*v in P2 coords
	tmp1.double(tmp2) // tmp1 =  4*v in P1xP1 coords
	tmp2.from_p1(tmp1) // tmp2 =  4*v in P2 coords
	tmp1.double(tmp2) // tmp1 =  8*v in P1xP1 coords
	tmp2.from_p1(tmp1) // tmp2 =  8*v in P2 coords
	tmp1.double(tmp2) // tmp1 = 16*v in P1xP1 coords
	v.from_p1(tmp1) // now v = 16*(odd components)

	// Accumulate the even components
	for j := 0; j < 64; j += 2 {
		bpt_table[j / 2].select_into(mut multiple, digits[j])
		tmp1.add_affine(v, multiple)
		v.from_p1(tmp1)
	}

	return v
}

// scalar_mult sets v = x * q, and returns v.
//
// The scalar multiplication is done in constant time.
pub fn (mut v Point) scalar_mult(mut x Scalar, q Point) Point {
	check_initialized(q)

	mut table := &ProjLookupTable{}
	defer { unsafe { free(table) } }
	table.from_p3(q)

	// Write x = sum(x_i * 16^i)
	// so  x*Q = sum( Q*x_i*16^i )
	//         = Q*x_0 + 16*(Q*x_1 + 16*( ... + Q*x_63) ... )
	//           <------compute inside out---------
	//
	// We use the lookup table to get the x_i*Q values
	// and do four doublings to compute 16*Q
	digits := x.signed_radix16()
	defer { unsafe { digits.free() } }

	// Unwrap first loop iteration to save computing 16*identity
	mut multiple := ProjectiveCached{}
	mut tmp1 := ProjectiveP1{}
	mut tmp2 := ProjectiveP2{}
	table.select_into(mut multiple, digits[63])

	v.set(new_identity_point())
	tmp1.add(v, multiple) // tmp1 = x_63*Q in P1xP1 coords
	for i := 62; i >= 0; i-- {
		tmp2.from_p1(tmp1) // tmp2 =    (prev) in P2 coords
		tmp1.double(tmp2) // tmp1 =  2*(prev) in P1xP1 coords
		tmp2.from_p1(tmp1) // tmp2 =  2*(prev) in P2 coords
		tmp1.double(tmp2) // tmp1 =  4*(prev) in P1xP1 coords
		tmp2.from_p1(tmp1) // tmp2 =  4*(prev) in P2 coords
		tmp1.double(tmp2) // tmp1 =  8*(prev) in P1xP1 coords
		tmp2.from_p1(tmp1) // tmp2 =  8*(prev) in P2 coords
		tmp1.double(tmp2) // tmp1 = 16*(prev) in P1xP1 coords
		v.from_p1(tmp1) //    v = 16*(prev) in P3 coords
		table.select_into(mut multiple, digits[i])
		tmp1.add(v, multiple) // tmp1 = x_i*Q + 16*(prev) in P1xP1 coords
	}
	v.from_p1(tmp1)
	return v
}

fn basepoint_naf_table(mut table NafLookupTable8) {
	table.from_p3(new_generator_point())
}

// vartime_double_scalar_base_mult sets v = a * A + b * B, where B is the canonical
// generator, and returns v.
//
// Execution time depends on the inputs.
pub fn (mut v Point) vartime_double_scalar_base_mult(xa Scalar, aa Point, xb Scalar) Point {
	check_initialized(aa)

	// Similarly to the single variable-base approach, we compute
	// digits and use them with a lookup table.  However, because
	// we are allowed to do variable-time operations, we don't
	// need constant-time lookups or constant-time digit
	// computations.
	//
	// So we use a non-adjacent form of some width w instead of
	// radix 16.  This is like a binary representation (one digit
	// for each binary place) but we allow the digits to grow in
	// magnitude up to 2^{w-1} so that the nonzero digits are as
	// sparse as possible.  Intuitively, this "condenses" the
	// "mass" of the scalar onto sparse coefficients (meaning
	// fewer additions).

	mut bp_naftable := &NafLookupTable8{}
	defer { unsafe { free(bp_naftable) } }
	basepoint_naf_table(mut bp_naftable)
	mut atable := &NafLookupTable5{}
	defer { unsafe { free(atable) } }
	atable.from_p3(aa)
	// Because the basepoint is fixed, we can use a wider NAF
	// corresponding to a bigger table.
	mut a := new_scalar_owned()
	mut b := new_scalar_owned()
	defer { unsafe { free(a); free(b) } }
	a.set(xa)
	b.set(xb)
	anaf := a.non_adjacent_form(5)
	bnaf := b.non_adjacent_form(8)
	defer { unsafe { anaf.free(); bnaf.free() } }

	// Find the first nonzero coefficient.
	mut i := 255
	for j := i; j >= 0; j-- {
		if anaf[j] != 0 || bnaf[j] != 0 {
			break
		}
	}

	mut multa := ProjectiveCached{}
	mut multb := AffineCached{}
	mut tmp1 := ProjectiveP1{}
	mut tmp2 := ProjectiveP2{}
	tmp2.zero()

	// Move from high to low bits, doubling the accumulator
	// at each iteration and checking whether there is a nonzero
	// coefficient to look up a multiple of.
	for ; i >= 0; i-- {
		tmp1.double(tmp2)

		// Only update v if we have a nonzero coeff to add in.
		if anaf[i] > 0 {
			v.from_p1(tmp1)
			atable.select_into(mut multa, anaf[i])
			tmp1.add(v, multa)
		} else if anaf[i] < 0 {
			v.from_p1(tmp1)
			atable.select_into(mut multa, -anaf[i])
			tmp1.sub(v, multa)
		}

		if bnaf[i] > 0 {
			v.from_p1(tmp1)
			bp_naftable.select_into(mut multb, bnaf[i])
			tmp1.add_affine(v, multb)
		} else if bnaf[i] < 0 {
			v.from_p1(tmp1)
			bp_naftable.select_into(mut multb, -bnaf[i])
			tmp1.sub_affine(v, multb)
		}

		tmp2.from_p1(tmp1)
	}

	v.from_p2(tmp2)
	return v
}
