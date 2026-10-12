module cpu

import rawtscspy

pub fn rdtsc() u64 { return rawtscspy.read() }
