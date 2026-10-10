@[has_globals]
module security
__global ( current_level int )
pub fn securelevel() int { return current_level }
pub fn set_level(value int) { current_level = value }
