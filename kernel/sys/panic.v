module sys

pub fn panic(reason string) {
	//printk('*** PANIC ***')
	printk('')
	printk('')
	printk('')
	printk('A problem has been detected and vOS has been shut down to prevent damage to your computer.')
	printk('')
	printk('If this is the first time you\'ve seen this Stop error screen,')
	printk('restart your computer. If this screen appears again, follow')
	printk('these steps:')
	printk('')
	printk('Check to make sure any new hardware or software is properly installed.')
	printk('If this is a new installation, ask your hardware or software manufacturer')
	printk('for any vOS updates you might need.')
	printk('')
	printk('If problems continue, disable or remove any newly installed hardware')
	printk('or software. Disable BIOS memory options such as caching or shadowing.')
	printk('If you need to use Safe Mode to remove or disable components, restart')
	printk('your computer, press F8 to select Advanced Startup Options, and then')
	printk('select Safe Mode.')
	printk('')
	printk('Technical Information:')
	printk('')
	printk('*** STOP: 0x00000000 (0x00000001, 0x00000001, 0x00000000, 0x00000000)')
	printk(reason)
	
	// todo cpu state / backtrace?

	// todo halt
	for {

	}
}