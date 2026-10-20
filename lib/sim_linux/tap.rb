#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

module TEZC
module SimLinux
  

#####################################################################
# class to access a tap device
class Tap

IFF_NO_PI = 0x1000
IFF_TAP =   0x0002  
TUNSETIFF = 0x400454ca

#################################################
# create a new TAP
# @param name [String] the device name
# 
def initialize(name)
  
   # sizeof(ifreq) = 40
   # sizeof(ifreq.ifr_name) = 16
   # sizeof(ifreq.ifr_flags) = 2

   # generate the ioctl ifreq
   ifreq = [name, IFF_TAP | IFF_NO_PI, ''].pack("a16 S a22")

   # open the tun device file
   @fd = IO.sysopen('/dev/net/tun', 'r+')
   @io = IO.new(@fd, 'r+', internal_encoding: nil, autoclose: true)

   # get the named tap device
   @io.ioctl(TUNSETIFF, ifreq)

end # def initialize()
  

#################################################
# Provide access to the IO
# @return [IO]
attr_reader :io


#################################################
# Send a packet
# 
# @param pkt [String] the packet to send
# 
def send(pkt)
   @io.syswrite(pkt)  
end # def send()


#################################################
# Get a packet if one is available
# 
# @return [String,nil] the packet, if one is available
# 
def recv()
   return @io.read_nonblock(1600)
rescue IO::WaitReadable
   return nil
end # def recv()


end # class TEZC::SimLinux::Tap
   
end # module TEZC::SimLinux
end # module TEZC