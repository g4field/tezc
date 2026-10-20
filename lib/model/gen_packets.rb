#
# Copyright 2025 by Graham A. Field
# All Rights Reserved
#

require_relative 'buffer'

module TEZC
module Model

##########################################################################
# Packet generator
#
class GenPackets < Item

###########################################################
# Frequency of info reports
REPORT_FREQ = 10

###########################################################
# New packet generator
#
# @param sim (see Item#sim_register)
# @param name (see Item#sim_register)
#
def initialize(sim, name)

   @trace = false

   # register ourself
   sim_register(sim, nil, name)

   # the interface
   @iface = Interface.new(self, "if")
   @iface.router = self

   # running
   @wait_finish = Model::NEVER
   @report_finish = Model::NEVER
   @self_halt = Model::NEVER

   # stats
   @cnt_rxp = 0
   @cnt_txp = 0
   
end # def initialize()


###########################################################
# Packets received
# @return [Integer]
attr_reader :cnt_rxp


###########################################################
# Packets sent
# @return [Integer]
attr_reader :cnt_txp


###########################################################
# (see Interface#plugin)
def plugin(link)
   @iface.plugin(link)
end # def plugin()


###########################################################
# (see Interface#unplug)
def unplug()
   @iface.unplug()
end # def unplug()


###########################################################
# Send trace packets
# (
def trace(pps, bpp, dst, cnt=0)
   normal(pps, bpp, dst, cnt)
   @trace = true
end # trace()


###########################################################
# Run normal
#
# @param pps [Integer] Packets per second
# @param bpp [Integer] Bytes per packet
# @param dst [Array] Destination
# @param cnt [Integer] Count of seconds to run, 0 = forever
#
def normal(pps, bpp, dst, cnt=0)

   sim_log(:info, "run: dst %s pps %d bpp %d cnt %d" % 
         [dst.inspect, pps, bpp, cnt])

   # save the params
   @pps = pps
   @bpp = bpp
   @dst = dst

   # self halt
   if( cnt != 0 )
      @self_halt = @sim.time + cnt * @sim.resolution
   else
      @self_halt = Model::NEVER
   end

   # wake up the simulation with an immediate packet to send
   @wait_finish = @sim.time
   sim_wake()

   # by default we don't trace
   @trace = false

end # def normal()


###########################################################
# Halt
def halt
   sim_log(:info, "halt")
   @wait_finish = Model::NEVER
end # def halt


###########################################################
# (see Item#sim_run)
def sim_run(st)

   # read all received packets
   while( pkt = @iface.router_read() )
      @cnt_rxp = @cnt_rxp + 1
      sim_pkt(:debug, pkt, "RX packet")
      lev = pkt.trace ? :trace : :debug
      if( @report_finish == Model::NEVER )
         @report_finish = st + REPORT_FREQ*@sim.resolution
      end
   end

   # halt if time runs out
   if( st >= @self_halt )
      sim_log(:info, "self halt")
      @wait_finish = Model::NEVER
      @self_halt = Model::NEVER
   end

   # send a packet if it is time
   if( st >= @wait_finish )

      # send a packet
      pkt = Packet.new(:genpacket)
      pkt.content_set(nil, @bpp)
      pkt.trace = @trace
      pkt.client(@dst)
      sim_pkt(:debug, pkt, "TX packet")
      @iface.router_write(pkt)
      @cnt_txp = @cnt_txp + 1

      # wait time
      @wait_finish = st + @sim.resolution / @pps
      if( @report_finish == Model::NEVER )
         @report_finish = st + REPORT_FREQ*@sim.resolution
      end
   end

   # make a report if it is time
   if( st >= @report_finish )
      sim_log(:info, "Tx: %d Rx: %d" % [cnt_txp, cnt_rxp])
      @report_finish = Model::NEVER
   end

   return [@wait_finish, @report_finish].min

end # def sim_run()


end # class TEZC::Model::GenPackets

end # module TEZC::Model
end # module TEZC

