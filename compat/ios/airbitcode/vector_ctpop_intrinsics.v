// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn ctpop_intrinsic_vector(source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
 return integer_intrinsic_vector(.ctpop, source, bits, count)
}
