
/*
 Copyright 2026 by Graham A. Field
 All Rights Reserved
*/

#include <stdio.h>

#include <sys/ioctl.h>
#include <linux/if.h>
#include <linux/if_tun.h>

void main(void)
{
	struct ifreq req;
	
	printf("TUNSETIFF: %lx\n", TUNSETIFF);
	printf("IFF_NO_PI: %x\n", IFF_NO_PI);
	printf("IFF_TAP: %x\n", IFF_TAP);
	printf("sizeof ifreq: %ld\n", sizeof(req));
	printf("sizeof ifr_name: %ld\n", sizeof(req.ifr_name));
	printf("sizeof ifr_flags: %ld\n", sizeof(req.ifr_flags));
}
