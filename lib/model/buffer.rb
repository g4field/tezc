#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'item'

module TEZC
module Model


##########################################################################
# A packet queue
# 
# Packets are written to the queue, dropped if there is not enough space,
# and then read from it.
# 
class Queue < Item


#################################################
# new queue
# 
# @param parent (see Item#sim_register)
# @param name (see Item#sim_register)
# 
def initialize(parent, name)

   # register with the simulation
   sim_register(parent.sim, parent, name)

   # where we hold the packets
   @packets = []
   @available = 4096

   # defaults
   @cfg_buffer = 4096         # how big a buffer in bytes
   @cfg_overhead = 8          # how much overheade in bytes

end # def initialize()


#################################################
# Storage overhead per packet in bytes
# 
# Default is 8
# 
# @return [Integer]
attr_accessor :cfg_overhead


#################################################
# Buffer size in bytes
# 
# Default is 4096.
# If nil, there are no limits to the buffer.
# 
# @return [Integer,nil]
attr_reader :cfg_buffer


#################################################
# Set the buffer size
# 
# This should only be called while the queue is empty
# 
# @param buf [Integer] the buffer size in bytes
def cfg_buffer=(buf)
   @packets = []
   @available = buf
   @cfg_buffer = buf
end # def cfg_buffer()


#################################################
# The item which reads
# 
# If set, this will be woken when a write happens.
# 
# @return [Item]
attr_accessor :reader


#################################################
# The item which writes
# 
# If set, this will be woken when a read happens.
# 
# @return [Item]
attr_accessor :writer


#################################################
# Write a packet
# 
# @param pkt [Packet] the packet to write
# @return [true,false] if the packet was written
# 
def write(pkt)

   # byte limited queue
   if( @cfg_buffer )
     if( (pkt.size + @cfg_overhead) >= @available )
       sim_drop(pkt, :queue)
       return false
     end
     @available = @available - pkt.size - @cfg_overhead
   end

   # record queue time
   pkt.meta_queue = @sim.time

   # store it
   sim_pkt(:debug, pkt, "write to queue")
   @packets.push(pkt)

   # wake the reader
   @reader.sim_wake() if (@reader)

   return true
end # def write()


#################################################
# Write metadata
# 
# Used by Link to pass up/down info
# 
# @param dta [Object] a non-packet to pass thru
# 
def write_meta(dta)

   # store it
   sim_debug("write metadata to queue")
   @packets.push(dta)
   
   # wake the reader
   @reader.sim_wake() if (@reader)
end # def write_meta()


#################################################
# Read a packet
# 
# @return [Packet,Object,nil] the next packet or metadata, if any
# 
def read()

   # get packet
   pkt = @packets.shift
   return nil if( !pkt )

   # metadata
   if( !pkt.is_a?(Packet) )
      sim_debug("read metadata from queue")
      return pkt
   end

   # log packet
   sim_pkt(:debug, pkt, "read from queue")

   # byte limited buffer
   if( @cfg_buffer )
     @available = @available + pkt.size + @cfg_overhead
   end

   # wake the writer
   @writer.sim_wake() if(writer)

   return pkt  
end # def read()


#################################################
# Lookahead to next packet
# 
# @return [Packet,nil] the next packet, if any
# 
def next()
   return (@packets.empty?) ? nil : @packets[0]
end # def next()


#################################################
# Is the queue empty?
# 
# @return [true,false] if the queue is empty or not
# 
def empty?
   return @packets.empty?
end # def empty?


end # class TEZC::Model::Queue


##########################################################################
#  A bi-directional buffer from a router to a link
#  
class Interface < Item

#################################################
# New Interface
# 
# @param parent (see Item#sim_register)
# @param name (see Item#sim_register)
#
def initialize(parent, name)

   # register with the runtime
   sim_register(parent.sim, parent, name)

   # create the queues
   @qA = Queue.new(self, 'qA')
   @qB = Queue.new(self, 'qB')

   # start down
   @active = false

   # defaults
   @cfg_max_speed = 100000

end # def initialize()


#################################################
# If the interface is up or down
# 
# Will be set by the {Link}
# 
# @return [true,false]
attr_accessor :active


#################################################
# Number
# 
# If set, this will be recorded on packets as meta_iface
# @return [Integer]
attr_accessor :number


#################################################
# The maximum speed in kbits per second
# 
# Defaults to 100 mbps.
#
# @return [Integer] 
attr_accessor :cfg_max_speed


#################################################
# The current speed of the connected link
# 
# Valid only if active.
# Units are bits per second.
# 
# @return [Integer]
attr_accessor :speed


#################################################
# The latency of the link
# 
# Valid only if active.
# Units are seconds.
# 
# @return [Float]
attr_accessor :latency


#################################################
# The router
# @return [Router]
attr_accessor :router


#################################################
# the link
# @return [Link]
attr_accessor :link


#################################################
# The port monitor
# 
# Woken on link status changes
# 
# @return [Item]
attr_accessor :monitor


#################################################
# router writes to the interface
# 
# @param pkt [Packet] the packet to write
# 
def router_write(pkt)
   if( @active )
     @qA.write(pkt)
   else
      sim_drop(pkt, :iface)
   end

   @link.sim_wake() if( @link )
end # def router_write()


#################################################
# Router reads from the interface
def router_read()
   pkt = @qB.read()

   pkt.meta_iface = @number if( pkt && @number )
   
   return pkt
end # def router_read()


#################################################
# Lookahead to the next packet
def router_next()
   @qB.next()
end # def router_next()


#################################################
# Write by the Link
def link_write(pkt)
   if( @active )
      @qB.write(pkt)
   else
      sim_drop(pkt, :iface)
      sim_error("Down link writing to an Interface")
   end

   @router.sim_wake() if( @router )
end # def link_write()


#################################################
# Read by the Link
def link_read()
   @qA.read()
end # def link_read()


#################################################
# Plug in a LinkHalf
def plugin(lh)

   # plug in and register as the reader
   @link = lh
   @qA.reader = lh

   # let the link half know
   lh.iface = self
   lh.sim_wake()

end # def plugin()


#################################################
# Unplug the LinkHalf
def unplug()

   if( !@link )
      sim_error("unplug with no link plugged in")
      return
   end

   # let the link know we are not plugged in
   @link.iface = nil
   @link.sim_wake()

   # turn off and disconnect
   @active = false
   @link = nil
   @qA.reader = nil

   # wake the router if it exists
   @router.sim_wake() if( @router )
   @monitor.sim_wake() if( @monitor )
  
end # def unplug()


#################################################
# Make this a socket connected to some user Item
def socket(it)

   # turn off numbering
   @number = nil

   # set active
   @active = true

   # connect the user item to the queue
   @link = it
  
end # def socket()

  
end # class TEZC::Model::Interface



##########################################################################
# A Link
class Link < Item


#################################################
# A new Link
def initialize(sim, name)

   # register
   sim_register(sim, nil, name)

   # create two halves connected
   @a = LinkHalf.new(self, "A")
   @b = LinkHalf.new(self, "B")
   @a.pair = @b
   @b.pair = @a
   @a.queue.reader = @b
   @b.queue.reader = @a

   # save the raw latency
   @latency_raw = latency

   # get latency in st
   @latency = 5e-6 # FIXME

   # defaults
   @cfg_ipg = 12
   @cfg_latency = sim_sec(0, @latency)       # end-to-end latency

end # def initialize()

#################################################
# The interpacket gap in bytes
# 
# Defaults to 12
# @return [Integer]
attr_accessor :cfg_ipg


#################################################
# The latency in seconds
# 
# Default is 5 us
# @return [Float]
attr_reader :latency


#################################################
# The latency in sim time
# 
attr_reader :cfg_latency


#################################################
# Side A
# @return [LinkHalf]
attr_reader :a


#################################################
# Side B
# @return [LinkHalf]
attr_reader :b


#################################################
# Set the latency
# 
# @param lt [Float] the latency in seconds
# 
def latency=(lt)
   @latency = lt
   @cfg_latency = sim_sec(0, lt)  
end # def latency=()

end # class TEZC::Model::Link


##########################################################################
# A Link Half
class LinkHalf < Item


#################################################
# new link half
def initialize(parent, name)

   sim_register(parent.sim, parent, name)
  
   # create the queue, unlimited buffer
   @queue = Queue.new(self, 'q')
   @queue.cfg_buffer = nil

   # state
   @iface = nil
   @iface_prev = nil

   # waits
   @send_finish = Model::NEVER
   @recv_finish = Model::NEVER

   # farside
   @farside = { iface: nil }
   
end # def initialize()


#################################################
# The other half of the link pair
# @return [LinkHalf]
attr_accessor :pair


#################################################
# The interface we are plugged into
# @return [Interface]
attr_accessor :iface


#################################################
# The queue
# 
# Should only by used by the other half of the link pair
# @return [Queue]
attr_accessor :queue


#################################################
# Run our half of the link
def sim_run(st)

   # sending packet complete
   if( st > @send_finish )
      @send_finish = Model::NEVER
   end

   # start to send a packet
   if( @send_finish == Model::NEVER )

      # a plug/unplug event
      if( @iface != @iface_prev )
         @iface_prev = @iface
        
         # send our state
         meta = {
            iface: @iface,
            time: st
         }
         meta[:max_speed] = @iface.cfg_max_speed if( @iface )

         # log it
         sim_debug("sending link %s" % (meta[:iface] ? 'UP' : 'DOWN' ) )

         # put it in the queue
         @queue.write_meta(meta)

         # adjust our link
         set_state()

      # up and sending
      elsif( @iface && @active )
         pkt = @iface.link_read()

         # send it down the wire
         if( pkt )
            # log it
            sim_pkt(:debug, pkt, "transmit")

            # put it in the queue
            @queue.write(pkt)

            # note when we are done sending
            @send_finish = st + wire_time(pkt)
         end
      end

   end

   # receive packet complete
   if( st >= @recv_finish )
      @recv_finish = Model::NEVER

      # get it from the pair queue
      pkt = @pair.queue.read()
      if( pkt )

         # if we have a packet
         if( pkt.is_a?(Packet) )

            # log it
            sim_pkt(:debug, pkt, "receive")

            # write packet to the interface
            if( @iface )
               @iface.link_write(pkt)
            else
               sim_drop(pkt, :link)
            end

         # other side has been plugged in/out
         else
            # log it
            sim_debug("receive link %s" % (pkt[:iface] ? 'UP' : 'DOWN' ) )

            # save it
            @farside = pkt

            # adjust our state
            set_state()
         end
      end
   end

   # start to receive a packet from our pair
   if( @recv_finish == Model::NEVER )

      pkt = @pair.queue.next()
      if( pkt )
         if( pkt.is_a?(Packet) )
            @recv_finish = pkt.meta_queue + wire_time(pkt) + @sim_parent.cfg_latency
         else
            @recv_finish = pkt[:time] + @sim_parent.cfg_latency
         end
      end

   end

   return [@recv_finish, @send_finish].min  

end # def sim_run()


################################################################
private


#################################################
# Adjust our state
def set_state()

   # up
   if( @farside[:iface] && @iface )

      @active = true
      @iface.active = true

      # set speed
      @speed = [@farside[:max_speed], @iface.cfg_max_speed].min
      @stpb = @sim.resolution.to_f / (@speed*1000) / 8.0
      @iface.speed = @speed

      # set latency
      @iface.latency = @sim_parent.latency

      # wake the router/monitor, if any
      @iface.router.sim_wake() if( @iface.router )
      @iface.monitor.sim_wake() if( @iface.monitor )

   # down
   else

      @active = false

      if( @iface )
         @iface.active = false
         @iface.sim_wake()

         # wake the router/monitor, if any
         @iface.router.sim_wake() if( @iface.router )
         @iface.monitor.sim_wake() if( @iface.monitor )
      end
   end 

end # def set_state()


#################################################
# time on the wire
def wire_time(pkt)
   return(@stpb * (@sim_parent.cfg_ipg + pkt.size)).ceil
end # def wire_time()

  
end # class TEZC::Model::LinkHalf


end # module TEZC::Model
end # module TEZC
