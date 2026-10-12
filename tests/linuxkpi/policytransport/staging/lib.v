module lib
import policytransport
@[noreturn]
pub fn kpanic(_frame voidptr, message &char) { policytransport.fatal(message) }
