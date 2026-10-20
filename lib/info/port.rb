#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'
require_relative 'records'
require_relative 'messages'

module TEZC
module Info

##########################################################################
# Monitor the status of a port
#
class Port < Mod

#################################################
# New port monitor
# 
# @param nis (see Mod#initialize)
# @param port [Integer] the port number
# 
def initialize(nis, port)
   
   # save
   super(nis)
   @port = port

   # flow of messages
   @fc_current = 1
   @fc_processed = 0
   @fc_shared = 0
   @fc_acked = 0
   @fc_prior_tx = false
   @fc_tx_reqd = false
   @fc_rx_reqd = false
   @fc_tx_time = 0
   @fc_rx_time = 0

   # our side state
   @s_min_dist = 0

   # neighbor raw
   @n_id = nil
   @n_port = nil
   @n_cycle = nil
   @n_addr = Array.new(nis.max_levels)
   @n_node = Array.new(nis.max_levels)

   # link state
   @physical = false
   @cycle = 1

   # link values
   @ls_vals = {
      dist: 0,
      routerB: nil,
      portB: nil,
      nodeA: nil,
      nodeB: nil,
      speed: 0,
      addrA: [0],
      addrB: [0],
   }
   @ls_sent = {}
   @ls_curr = {
      up: false,
      sender: false,
      id: nil,
      serial: 1,
   }
   @ls_prev = @ls_curr.dup

   # our id and serial number
   @ls_id = Records.id_link(@nis.id, port)
   @ls_serial = 0
   @ls_refresh = false

   # create a timer
   @timer = Service::Timer.new()
   @timer.module = self

   # register for triggers
   [  :msg_phy,
      :msg_port,
      :self_address,
      :self_node,
      :db_area,
      :db_link_update,
   ].each{|trig| @nis.trigger_register(trig, 0, self) }


   # expire after not hearing from other side in 7s
   @cfg_expire = 7000

   # retry sending if we do not get a response in 0.5s
   @cfg_retry_active = 500

   # retry keepalive if we do not get a response in 4s
   @cfg_retry_keepalive = 4000

   # keepalive every 3s
   @cfg_keepalive = 3000

end # def initialize()


#################################################
# Set the minimum distance for the port
# 
# @param dist [Integer] the new minimum distance
#
def set_dist(dist)

   # no change
   return if( @s_min_dist == dist )
      
   # log
   log(:verbose, "Port %d dist %d" % 
            [@port, dist] )
   
   # change what we advertize
   @s_min_dist = dist
   @fc_current = @fc_current + 1

   # if this changes the active link
   if( @link && @link_dist < dist )
      link_changed()
   end

   # update the timer
   timer_update()

end # def set_dist()


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   case trig
     
   # physical layer notifies us of a state change
   when :msg_phy
      # not for us
      return if( data.port != @port )

      # log
      log(:verbose, "Port %d phy is %s" %
            [@port, data.link ? "UP" : "DOWN" ] )

      # has not changed
      return if( data.link == @physical )
      
      # save current state
      @physical = data.link
      @cycle = @cycle + 1
      @ls_vals[:speed] = data.speed
      if( !@physical )
         @ls_curr[:up] = false
      end

      # reset the flow control
      @fc_processed = 0
      @fc_shared = 0
      @fc_acked = 0
      @fc_prior_tx = false
      @fc_tx_reqd = false
      @fc_rx_reqd = false
      @fc_tx_time = 0
      @fc_rx_time = 0

   when :msg_port
      # not for us
      return if( data.port != @port )
      msg = data

      # log
      log(:debug, "Port %d RX %s pt %d req %s cng %d ack %s ngh %s pt %s reason %s" %
         [  @port, msg.s_router, msg.s_port,
            msg.required ? 'Y' : 'N',
            msg.s_change,
            msg.n_change ? msg.n_change.to_s : "-",
            msg.n_router ? msg.n_router : "---",
            msg.n_port ? msg.n_port.to_s : "-",
            msg.reason])        

      # drop messages from ports that are now down
      return if( !@physical )

      # flow control
      @fc_prior_tx = false
      @fc_rx_time = @nis.now
      @fc_rx_reqd = msg.required
      @fc_acked = msg.n_change
      @fc_processed = msg.s_change

      # link is up if they know we are their neighbor
      # but only on the same up/down cycle
      @ls_curr[:up] = (
         msg.n_router == @nis.id &&
         msg.n_port == @port &&
         msg.n_cycle == @cycle )

      # distance is the max of the mins
      @ls_vals[:dist] = [@s_min_dist, msg.s_min_dist].max

      # save message values
      @n_id = msg.s_router
      @n_port = msg.s_port
      @n_cycle = msg.s_cycle
      @n_addr = msg.s_addr.first(@nis.max_levels)
      @n_node = msg.s_node.first(@nis.max_levels)
      
   # our address/node changes
   when :self_address, :self_node

      # bump our change number
      @fc_current = @fc_current + 1

   # the area changes
   when :db_area
      # refresh on partition changes
      if(   @ls_curr[:up] &&
            level == @ls_vals[:dist] + 1 &&
            data[:partition] != data[:prev][:partition] )
         @ls_refresh = true
      end

   # we get a link description
   when :db_link_update

      # only care if we are routerB
      return if( data.routerB != @nis.id || data.portB != @port )
        
      # if we are up, keep this as the previous value
      if( @ls_curr[:up] )
         @ls_curr[:id] = data.id
         @ls_curr[:serial] = data.serial
      
      # if we are down, immediately delete it
      else
         @nis.db.remove(data.id, data.serial+1)
      end

      # this does not change either link or timer
      return

   else
      raise 'Unknown trigger received'

   end

   # update the link and timer
   link_update()
   timer_update()

end # def trigger()


#################################################
# (see Mod#timer)
def timer()

   # construct the message
   msg = Messages::Port.new
   msg.port = @port

   msg.s_router = @nis.id
   msg.s_port = @port
   msg.s_cycle = @cycle
   msg.n_router = @n_id
   msg.n_port = @n_port
   msg.n_cycle = @n_cycle

   msg.s_change = @fc_current
   msg.n_change = @fc_processed
   msg.required = (@fc_current != @fc_acked)

   msg.s_min_dist = @s_min_dist
   msg.s_addr = @nis.address.addr.dup
   msg.s_node = @nis.address.node.dup

   msg.reason = @reason

   # flow control
   @fc_prior_tx = true
   @fc_shared = @fc_current
   @fc_tx_time = @nis.now
   @fc_tx_reqd = msg.required

   # send it
   log(:debug, "Port %d TX %s pt %s req %s cng %d ack %s self %s reason %s" %
      [  @port,
         msg.n_router ? msg.n_router : "---",
         msg.n_port ? msg.n_port.to_s : "-",
         msg.required ? 'Y' : 'N',
         msg.s_change, 
         msg.n_change ? msg.n_change.to_s : "-",
         msg.s_router,
         msg.reason
      ])
   @nis.extif.send_message(msg)
   @nis.activity(:send_msg_port, 1)

   # update the timer
   timer_update()

end # def timer()


###########################################################
###########################################################
private


#################################################
# Update the link
def link_update()
  
   # update values
   dist = @ls_vals[:dist]
   @ls_vals[:routerB] = @n_id
   @ls_vals[:portB] = @n_port
   @ls_vals[:nodeB] = @n_node[dist]
   @ls_vals[:addrB] = @n_addr.first(dist+1)
   @ls_vals[:nodeA] = @nis.address.node[dist]
   @ls_vals[:addrA] = @nis.address.addr.first(dist+1)

   if( @ls_curr[:up] )
      @ls_curr[:sender] = (@nis.id > @n_id)
   end

   # log up/down
   if( @ls_curr[:up] != @ls_prev[:up] )
      log(:verbose, "Port %d link is %s" %
            [@port, @ls_curr[:up] ? "UP" : "DOWN" ] )
   end
   
   # remove old neighbor relationship
   if(   @ls_prev[:up] && (
         !@ls_curr[:up] ||
         (@ls_sent[:routerB] && @ls_vals[:routerB] != @ls_sent[:routerB]) ||
         (@ls_sent[:dist] && @ls_vals[:dist] != @ls_sent[:dist]) ))
      @nis.db.neighbor(@ls_vals[:routerB], @port, false, 0)
   end

   # add new neighbor relationship
   if(   @ls_curr[:up] && (
         !@ls_prev[:up] ||
         (@ls_sent[:routerB] && @ls_vals[:routerB] != @ls_sent[:routerB]) ||
         (@ls_sent[:dist] && @ls_vals[:dist] != @ls_sent[:dist]) ))
      @nis.db.neighbor(@ls_vals[:routerB], @port, true, @ls_vals[:dist])
   end

   # remove old link
   if(   @ls_prev[:up] && @ls_curr[:id] && (
         !@ls_curr[:up] ||
         @ls_curr[:sender] != @ls_prev[:sender] ))
      @nis.db.remove(@ls_curr[:id], @ls_curr[:serial]+1)
   end

   # we do the send when:
   do_send = (
      # 1) we are up
      @ls_curr[:up] &&
      # 2) we are the sender
      @ls_curr[:sender] && 
      # 3) nodes are complete
      @ls_vals[:nodeA] && @ls_vals[:nodeB] && (
      # 4) at least one of the following applies:
         # a) it is a critical change
            !@ls_prev[:up] ||
            @ls_refresh ||
            @ls_vals[:dist] != @ls_sent[:dist] ||
            @ls_vals[:routerB] != @ls_sent[:routerB] ||
            @ls_vals[:portB] != @ls_sent[:portB] ||

         # b) nodes have changed
         (  @ls_vals[:nodeA] != @ls_sent[:nodeA] ||
            @ls_vals[:nodeB] != @ls_sent[:nodeB]
         ) ||
                
         # c) addresses are complete and there is any change
         (  !@ls_vals[:addrA].any?(0) &&
            !@ls_vals[:addrB].any?(0) &&
            @ls_vals != @ls_sent
         )
      )
   )
   
   # we update the serial when something changed or the link went up again
   do_serial = ( @ls_vals != @ls_sent || @ls_curr[:up] != @ls_prev[:up] )
            
   # update the previous state
   @ls_prev = @ls_curr.dup
   return if( !do_send )
   @ls_sent = @ls_vals.dup
   @ls_refresh = false
     
   # send
   @ls_serial = @ls_serial + 2 if( do_serial )
   @ls_curr[:id] = @ls_id
   @ls_curr[:serial] = @ls_serial
   link_send()

end # def link_update()


#################################################
# Send the link record
def link_send()

   lr = Records::Link.new

   lr.id = @ls_id
   lr.serial = @ls_serial
   lr.level = @ls_vals[:dist] + 1

   lr.routerA = @nis.id
   lr.portA = @port
   lr.nodeA = @ls_vals[:nodeA]
   lr.addrA = @ls_vals[:addrA]

   lr.routerB = @ls_vals[:routerB]
   lr.portB = @ls_vals[:portB]
   lr.nodeB = @ls_vals[:nodeB]
   lr.addrB = @ls_vals[:addrB]

   lr.speed = @ls_vals[:speed]

   # add to database with current partition
   @nis.db.update(lr, :partition)

end # def link_send()


#################################################
# Update the timer
def timer_update()

   exp = msg_when()

   if( exp == 0 )
      @nis.timer_del(@timer)
   else
      @timer.expires = exp
      @nis.timer_set(@timer)
   end  

end # def timer_update()

 
#################################################
# Determines when the next message is due
#
# @return [Integer] when the next nessage is due, 0 if never
#s
def msg_when()

   # we never need to send if there is no physical link
   return 0 if( !@physical )

   # we have expired
   if( @link && @nis.now >= @fc_rx_time + @cfg_expire )
      log(:info, "Port %d EXPIRED last %d" % 
            [@port, @fc_rx_time])
      link_down()

      @reason = :expired
      return @nis.now - 1
   end

   # Retry during active exchange of data in two situations:
   # 1) We required a response, and our last action was TX.
   #    This is the normal situation.
   # 2) We required a response, our last action was RX, but
   #    it passed our TX in transit, and we have a lower
   #    router ID.
   #    When both routers send at the same time, their
   #    messages pass in transit and we pause response from
   #    one of the routers to allow the back-and-forth
   #    exchange of messages to resume.
   if( @fc_tx_reqd && ( @fc_prior_tx ||
         ( @fc_shared != @fc_acked && @n_id && @nis.id < @n_id )
      ))
      @reason = :retry_active
      return @fc_tx_time + @cfg_retry_active
   end

   # Retry during keepalive:
   # We did not require a response, our last action was TX,
   # and there is no new data.
   if( !@fc_tx_reqd && @fc_prior_tx && @fc_current == @fc_acked )
      @reason = :retry_keepalive
      return @fc_tx_time + @cfg_retry_keepalive
   end

   # Wait to send keepalive:
   # We last received, they did not require a response, and there
   # is no new data
   if( !@fc_rx_reqd && !@fc_prior_tx && @fc_current == @fc_acked )
      @reason = :keepalive
      return @fc_rx_time + @cfg_keepalive
   end

   # Reasons, mostly for debugging
   if( !@fc_prior_tx && @fc_rx_reqd )
      @reason = :ack
   elsif( @fc_current != @fc_acked )
      @reason = :change
   else
      raise "No good reason for port to send"
   end
   return @nis.now - 1
     
end # def msg_when()

  
end # class TEZC::Info::Port
  
end # module TEZC::Info
end # module TEZC