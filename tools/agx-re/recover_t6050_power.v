import os
import recoverycli

fn main() {
	recoverycli.run('recover_t6050_power', os.args[1..])
}
