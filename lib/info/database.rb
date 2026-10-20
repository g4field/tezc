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
# the database
#
class Database < Mod

#################################################
# New database
#
# @param nis [Service] the network information service
#
def initialize(nis)
   super(nis)

   @req_offset = @nis.id[0,4].to_i(16)
   
   # change state
   @change = 0
   @time_change = @nis.now
   
   # the records we have and want
   @record = {}
   @content = {}
   @wanted = {}

   # the neighbors
   @neighbor = {}

   # the areas
   @area = []
   @nis.max_levels.times do |ix|
      @area[ix] = {
         leader: nil,
         election: 1,
         partition: 1,
      }
   end

   # when we clean
   @clean_neighbor = nil
   @clean_record = nil
   
   # create a timer
   @timer = Service::Timer.new
   @timer.module = self
     
   # register to get triggers
   [  :msg_database
   ].each{|trig| @nis.trigger_register(trig, 0, self) }

   @cfg_max_state = 5               # send max of 5 states per message
   @cfg_retry = 500                 # resend DB messages after 0.5s
   @cfg_exp_dropped = 5000          # clean dropped items after 5s
   @cfg_exp_stale = 2*60*1000      # clean egress/demand info after 10min
   @cfg_exp_disconnect = 30000      # clean disconnected neighbors after 30s

end # def initialize() 


#################################################
# The area information
# @return [Array(Hash)]
attr_reader :area


#################################################
# when the database changed
# @return [Integer]
attr_reader :time_change


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   case trig

   # process a database message
   when :msg_database
      msg_receive(data)

   else
      raise "Unknown trigger received"
   end

   timer_update()
end


#################################################
# (see Mod#timer)
def timer()

   now = @nis.now
   
   # clean up stuff
   neighbor_clean() if( @clean_neighbor && now >= @clean_neighbor )
   record_clean()

   # list of neighbors we need to send to now
   nlist = @neighbor.values.select do |nd|
      ( nd[:needed] && now >= nd[:needed] )
   end

   # send the the one we sent to longest ago
   if( !nlist.empty? )
      nd = nlist.sort{|aa,bb| aa[:tx_time] <=> bb[:tx_time] }.first
      msg = msg_send(nd)
      @nis.extif.send_message(msg)
      @nis.activity(:send_msg_db, 1)
   end
   
   timer_update()
end # def timer()


#################################################
# Add/Update a record
#
def update(rec, ref)
  
   # log
   log(:verbose, "DB %d local update %s ser %d typ %s" %
      [rec.level, rec.id, rec.serial, rec.type] )

   # current :election or :partion
   if( ref == :election )
      ref = @area[rec.level-1][:election]
   elsif( ref == :partition )
      ref = @area[rec.level-1][:partition]
   end
   
   # save it
   record_content(rec, ref)   
   
   timer_update()
end # def update()


#################################################
# Remove a record
#
# @param rid [String] the record ID
# @param ser [Integer] the serial
# 
def remove(rid, ser)

   # get the level
   pr = @record[rid]
   lev = (pr) ? pr[:level] : 0

   # log
   log(:verbose, "DB %d local remove %s ser %d" %
      [lev, rid, ser] )

   record_delete(rid, ser)   
   timer_update()
end # def remove()


#################################################
# Iterate over records
# 
# @param lev [Integer, nil] the level
# @param typ [Symbol, nil] the type
# 
def each(lev, typ)

   @record.each_pair do |rid, info|
      if(   info[:refresh] == 0 || info[:dropped] ||
            ( lev && info[:level] != lev ) ||
            ( typ && info[:type] != typ ) )
         next
      end

      rec = @content[rid]
      yield(rec)
   end

end # def each()


#################################################
# Update a neighbor port state
# 
# @param nis [String] the neighbor ID
# @param port [Integer] the port
# @param link [true, false] if we have a link
# @param dist [Integer] the hierarchical distance
# 
def neighbor(nis, port, link, dist)
   if( link )
      neighbor_up(nis, port, dist)
   else
      neighbor_down(nis, port)
   end

   timer_update()
end # def neighbor()


#################################################
# Make ourself the leader
# 
# @param lev [Integer] the level
# @param elec [Integer] how much to increase the election
# @param part [true,false] if we have an area partition
# 
def leader(lev, elec, part)

   # new info
   ci = @area[lev-1] 
   ni = {
      leader: @nis.id,
      election: ci[:election] + elec,
      partition: part ? (ci[:partition] + 1) : ci[:partition],
   }

   # apply the change
   elect_change(lev, ni)

   timer_update()
end # def leader()


################################################################
################################################################
private


###########################################################
###########################################################
# Timer

#################################################
# Update the timer
# 
def timer_update()

   # recalculate when neighbors need to send
   @neighbor.each_value{|nd| neighbor_needed(nd) }
  
   # find what neighbors have pending work
   pend = @neighbor.values.map{|nd| nd[:needed] }.compact.min

   # schedule timer for earliest time needed
   time_any = [
         pend,
         @clean_neighbor,
         @clean_record,
      ].compact.min
   if( time_any )
      @timer.expires = time_any
      @nis.timer_set(@timer)
   else
      @nis.timer_del(@timer)
   end
   
end # def timer_update()
  


###########################################################
###########################################################
# Neighbors

#################################################
# Clean old neighbors
# 
# We keep disconnected neighbor info around for a bit
# in case they reconnect quickly.
# Eventually they expire and need to be removed.
# 
def neighbor_clean()

   now = @nis.now
   exp_next = nil

   # make the list
   del_list = []
   @neighbor.each_pair do |nid, info|
      if( info[:disconnect] )
         expires = info[:disconnect] + @cfg_exp_disconnect

         if( now >= expires )
            del_list.append(info)
         elsif( !exp_next || exp_next < expires )
            exp_next = expires
         end
      end
   end

   # clean
   del_list.each do |info|

      # remove all the needed records this neighbor had
      info[:has_wanted].each do |rid|
         wi = @wanted[rid]
         wi[:avail_from].delete(info[:id])
         
         # remove if this was the last neighbor that had the record
         if( wi[:avail_from].empty? )
            record_unwanted(wi)
         end
      end
      
   end

   # save the next expiration
   @clean_neighbor = exp_next  
end # def neighbor_clean()


#################################################
# Add a neighbor on a port
# 
# @param nid [String] neighbor ID
# @param pn [Integer] the port number
# @param dist [Integer] the distance
# 
def neighbor_up(nid, pn, dist)

   # already known
   nd = @neighbor[nid]
   if( nd )

      # save the port and distance
      if( !nd[:ports].key?(pn) )
         nd[:ports][pn] = dist
      end

      # check the distance
      if( nd[:distance] != dist )
         log(:error, "DB neighbor %s mixed distances pts %s" %
            [nid, nd[:ports].inspect])
         nd[:distance] = nd[:ports].values.min
      end

      # reconnect if disconnected
      if( nd[:disconnect] )
         log(:verbose, "DB neighbor reconnect %s %d" % [nid, dist+1])
         nd[:disconnect] = false
         nd[:started] = false
      else
         return
      end
     
   # new neighbor
   else
      nd = {
         id: nid,                # the neighbor ID
         distance: dist,         # the hierarchical distance
         port: pn,               # the port we are using
         ports: { pn => dist },  # ports on which we are adjacent
         disconnect: false,      # when we disconnected
         started: false,         # have we started the back and forth
         has_wanted: {},         # list of wanted items they have

         request: nil,           # content we are asking for
         n_request: nil,         # content they asked for

         shared: 0,              # what we have shared
         acked: 0,               # what they have acked
         processed: 0,           # changes we have received and processed

         prior_tx: false,        # if the prior action was to send
         tx_reqd: false,         # if our TX required an ACK
         rx_reqd: false,         # if their RX required an ACK
         tx_time: 0,             # when we last sent
         rx_time: 0,             # when we last received
         needed: nil,            # when we need to send
      }
      @neighbor[nid] = nd

      # log
      log(:verbose, "DB neighbor add %s %d" % [nid, dist+1])

   end

end # def neighbor_up()


#################################################
# Remove a neighbor
# 
# @param nid [String] neighbor ID
# @param pn [Integer] the port number
# 
def neighbor_down(nid, pn)
  
   nd = @neighbor[nid]
   return if( !nd || !nd[:ports].key?(pn) )

   # remove port from the list
   nd[:ports].delete(pn)

   # no ports left
   if( nd[:ports].empty? )
     
      # mark as disconnected
      nd[:disconnect] = @nis.now

      # adjust the cleaning timer
      @clean_neighbor = [
            @clean_neighbor,
            @nis.now + @cfg_exp_disconnect
         ].compact.min

      # if we were asking them for an item, stop
      if( nd[:request] )
         wi = @wanted[nd[:request]]
         if( wi[:req_from] == nid )
            wi[:req_from] = nil
         end
      end

      # log
      log(:verbose, "DB neighbor remove %s" % nid)
     
   else

      # adjust port if needed
      if( !nd[:ports].key?(nd[:port]) )
         nd[:port] = nd[:ports].keys.first
      end
   
      # adjust distance if needed
      dist = nd[:ports].values.min
      if( dist != nd[:distance] )
         log(:error, "DB neighbor %s mixed distances pts %s" %
                  [nid, nd[:ports].inspect])
         nd[:distance] = dist
      end
   end
   
end # def neighbor_down()
  

#################################################
# Calculate when we need to send to a neighbor
# 
# @param nd [Hash] the neighbor info
# 
def neighbor_needed(nd)
  
   # disconnected never needs to send
   if( nd[:disconnect] )
      nd[:needed] = nil
      nd[:reason] = :disconnect
      return
   end

   # if we need to pick content to request
   if( !nd[:request] )
   
      # what can we ask for?
      req_list = nd[:has_wanted].keys.select do |xid|
         !@wanted[xid][:req_from]
      end

      # pick something to ask for
      # we want different neighbors to ask for different items
      # to take advantage of the mesh effect
      if( !req_list.empty? )
         xid = req_list[(@change + @req_offset) % req_list.size]
         nd[:request] = xid
         @wanted[xid][:req_from] = nd[:id]
      end
   end
   
   # Wait because there is nothing to do
   # no response needed to last action, and no new data
   if( ( (nd[:prior_tx] && !nd[:tx_reqd] ) ||
         ( !nd[:prior_tx] && !nd[:rx_reqd] ) ) &&
         @change == nd[:acked] && !nd[:n_request] && !nd[:request] )
      nd[:needed] = nil
      nd[:reason] = :none
      return
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
   #    But only if we have already started the exchange.
   if( nd[:tx_reqd] && ( nd[:prior_tx] ||
         ( nd[:started] && nd[:shared] != nd[:acked] && @nis.id < nd[:id] )
      ))
      nd[:needed] = nd[:tx_time] + @cfg_retry
      nd[:reason] = :retry
      return
   end

   # Reasons, mostly for debugging
   if( !nd[:prior_tx] && nd[:rx_reqd] )
      nd[:reason] = :ack
   elsif( @change != nd[:acked] )
      nd[:reason] = :change
   elsif( nd[:n_request] || nd[:request] )
      nd[:reason] = :request
   else
      raise "No good reason for database to send"
   end
   nd[:needed] = @nis.now - 1

end # def neighbor_needed()
  

###########################################################
###########################################################
# Messages

#################################################
# Generate a Database message to send
# 
# @param nd [Hash] the neighbor data
# @return [Messages::Database]
# 
def msg_send(nd)

   msg = Messages::Database.new

   #####################
   # areas
   msg.areas = @area.map{|ai| ai.dup }

   #####################
   # states
   
   # records that need to be sync'd to this neighbor
   list = @record.select do |rid, info|
      (  (info[:level] > nd[:distance]) &&
         !info[:dropped] &&
         (info[:change] > nd[:acked])
      )
   end
   list = list.values.sort{|aa, bb| aa[:change] <=> bb[:change] }
   all_states = ( list.size <= @cfg_max_state )
   list = list.first(@cfg_max_state)
   
   # create the states
   msg.states = list.map do |info|
      {  item:    info[:item],
         serial:  info[:serial],
         refresh: info[:refresh],
      }
   end

   # set the numbers
   if( msg.states.empty? )
      msg.change = @change
   else
      msg.change = list.last[:change]
   end
   msg.ack = nd[:processed]

   #####################
   # request

   # make a request
   if( nd[:request] )
      msg.request = nd[:request]
   end

   #####################
   # content
   
   # we have a request and we have the content
   if( nd[:n_request] )
      ct = @content[nd[:n_request]]
      msg.content = ct.dup if(ct)
      nd[:n_request] = nil
   end

   #####################
   # misc
   
   msg.port = nd[:port]
   msg.sender = @nis.id
   msg.adjacent = nd[:id]
   if( msg.change != nd[:acked] || msg.request )
      msg.required = true
   else
      msg.required = false
   end

   nd[:shared] = msg.change
   nd[:tx_reqd] = msg.required
   nd[:tx_time] = @nis.now
   nd[:prior_tx] = true

   # log
   log(:debug, "DB msg TX pt %d %s cng %d ack %d rqd %s sts %d req %s cnt %s %s %s %s" %
      [
         msg.port, msg.adjacent, msg.change, msg.ack,
         msg.required ? 'Y' : 'N',
         msg.states.size,
         (msg.request) ? msg.request : '---',
         (msg.content) ? msg.content.id : '---',
         (msg.content) ? msg.content.serial.to_s : '-',
         (msg.content) ? msg.content.type : '-',
         (msg.content) ? msg.content.level.to_s : '-',
      ])

   return msg

end # def msg_send()


#################################################
# Process a received Database message
# 
# @param msg [Messages::Database] the message
# 
def msg_receive(msg)

   # log
   log(:debug, "DB msg RX pt %d %s cng %d ack %d rqd %s sts %d req %s cnt %s %s %s %s" %
      [
         msg.port, msg.sender, msg.change, msg.ack,
         msg.required ? 'Y' : 'N',
         msg.states.size,
         (msg.request) ? msg.request : '---',
         (msg.content) ? msg.content.id : '---',
         (msg.content) ? msg.content.serial.to_s : '-',
         (msg.content) ? msg.content.type : '-',
         (msg.content) ? msg.content.level.to_s : '-',
      ])
   
   # not sent to us
   if( msg.adjacent != @nis.id )
      log(:error, "DB msg RX for router %s on port %d" %
         [msg.adjacent, msg.port])
      return
   end

   # the neighbor
   nd = @neighbor[msg.sender]
   if( !nd )
      log(:error, "DB msg RX from non-neighbor %s on port %d" %
         [msg.sender, msg.port] )
      return
   end
   if( nd[:disconnect] )
      log(:error, "DB msg RX from disconnected %s on port %d" %
         [msg.sender, msg.port] )
      return
   end

   # the sync basics
   nd[:rx_time] = @nis.now
   nd[:rx_reqd] = msg.required
   nd[:prior_tx] = false
   nd[:acked] = msg.ack
   nd[:started] = true if( nd[:shared] == nd[:acked] )

   # process the area elections
   elect_sync(msg.areas, nd[:distance])   
  
   # process the states
   msg.states.each do |st|
      if( st[:refresh] == 0 )
         record_delete(st[:item], st[:serial])
      else
         record_sync(st, msg.sender)
      end
   end
   nd[:processed] = msg.change

   # record the request
   nd[:n_request] = msg.request

   # process the content, assuming we wanted it
   if( msg.content )
      nr = @wanted[msg.content.id]
      if( nr && nr[:serial] == msg.content.serial )
         record_content(msg.content, nr[:refresh])
      end
   end

   # if we asked for content and they have acked it, remove the request
   if( nd[:request] && nd[:acked] == nd[:shared] )
      wi = @wanted[nd[:request]]
      if( wi )
         if( wi[:req_from] && wi[:req_from] == msg.sender )
            wi.delete(:req_from)
         else
            log(:error, "DB wanted requests not consistent")
         end
      end
      nd[:request] = nil 
   end

rescue
   puts msg.inspect
   raise
end # def msg_receive()


###########################################################
###########################################################
# Elections

#################################################
# Area election sync
# 
# Compare the area info from a message and determine
# the correct area information.
# 
# @param msg_areas [Array(Hash)] the area info from the message
# @param dist [Integer] the distance to this neighbor
# 
def elect_sync(msg_areas, dist)

   # each level at/above our distance
   (dist .. @nis.max_levels-1).each do |ix|

      # exact match
      ci = @area[ix]
      mi = msg_areas[ix]
      next if( ci[:leader] == mi[:leader] &&
               ci[:election] == mi[:election] &&
               ci[:partition] == mi[:partition] )

      # election logic
      if( ci[:election] < mi[:election] )
         ni = mi.dup
      elsif( ci[:election] > mi[:election] )
         ni = ci.dup
      else
         ni = (ci[:leader] < mi[:leader]) ? ci.dup : mi.dup
         ni[:election] = ni[:election] + 1
         log(:verbose, "DB %d election tie bump %d" %
            [ix+1, ni[:election]] )
      end
      ni[:partition] = [ci[:partition], mi[:partition]].max

      # apply the change
      elect_change(ix+1, ni)
   
   end
end # def elect_sync()


#################################################
# Make changes to an election
# 
# @param lev [Integer] the level
# @param ni [Hash] the new area information
#
def elect_change(lev, ni)

   # current info
   ci = @area[lev-1]

   # election changes
   if( ci[:election] != ni[:election] )

      # drop links and addresses
      @record.each_pair do |rid, info|
        
         # not our level, deleted, or already dropped
         if(   info[:level] != lev ||
               info[:refresh] == 0 ||
               info[:dropped] )
            next
         end

         # drop links on partition, addresses on election
         if(   (info[:type] == :link && info[:refresh] < ni[:partition]) ||
               (info[:type] == :addr && info[:refresh] < ni[:election]) )
            @change = @change + 1
            info[:change] = @change
            info[:dropped] = @nis.now
         end
      end

      # unwant
      list = @wanted.select do |rid, info|
         (  info[:level] == lev && (
            (info[:type] == :link && info[:refresh] < ni[:partition]) ||
            (info[:type] == :addr && info[:refresh] < ni[:election]) )
         )
      end
      list.each do |rid, info|
         record_unwanted(info)
      end
      
   end 
   
   # update the area info
   @change = @change + 1
   @time_change = @nis.now
   ni[:prev] = ci
   ci.delete(:prev)
   @area[lev-1] = ni

   # send the trigger
   @nis.trigger(:db_area, lev, ni)
  
end # def elect_change()


###########################################################
###########################################################
# Records

#################################################
# Clean old records
def record_clean()

   now = @nis.now
   exp_next = nil

   # lowest neighbor sync
   acked = @neighbor.values.map{|nd| nd[:acked] }.min

   # making a list
   del_list = []
   exp_list = []
   @record.each_pair do |rid, info|

      # deleted
      if( info[:refresh] == 0 )

         # all neighbors have acked
         if( info[:change] <= acked )
            del_list.append(rid)
         end
         
      # dropped
      elsif( info[:dropped] )
        
         expires = info[:dropped] + @cfg_exp_dropped
      
         # clean expired and track next expiration
         if( now >= expires )
            del_list.append(rid)
         elsif( !exp_next || expires < exp_next )
            exp_next = expires
         end

      # egress and demand records, clean expired and track next exp
      elsif( info[:type] == :egress || info[:type] == :demand )

         expires = info[:refresh_time] + @cfg_exp_stale

         # expired now or this is earliest
         if( now >= expires )
            exp_list.append(rid)
         elsif( !exp_next || expires < exp_next )
            exp_next = expires
         end
      end
   end

   # clean dropped and deleted
   del_list.each do |rid|
      @record.delete(rid)
      @content.delete(rid)
   end

   # clean expired
   exp_list.each do |rid|
      rec = @content[rid]
      @record.delete(rid)
      @content.delete(rid)
      trigger_remove(rec, 0)
   end

   # save the next expiration
   @clean_record = exp_next
end # def record_clean()


#################################################
# Add/update a record state
# 
# Called when processing received states
# 
# @param st [Hash] the state
# @param nid [String] the neighbor ID
# 
def record_sync(st, nid)
  
   #####################
   # update the records and wanted

   # already have a record
   pr = @record[st[:item]]
   if( pr )

      # current version refresh
      if( pr[:serial] == st[:serial] && pr[:refresh] < st[:refresh] )
         @change = @change + 1
         @time_change = @nis.now
         pr[:change] = @change
         pr[:refresh] = st[:refresh]
         pr[:refresh_time] = @nis.now
         
         # restore a dropped item
         if( pr[:dropped] )
            pr[:dropped] = false
            trigger_update(@content[st[:item]])
         end
      end

      # have newer or same, nothing more to do
      return if( pr[:serial] >= st[:serial] )
   end

   # already want it
   nr = @wanted[st[:item]]
   if( nr )
      
      # same version
      if( nr[:serial] == st[:serial] )

         # record the neighbor has it
         nr[:avail_from][nid] = true
         @neighbor[nid][:has_wanted][st[:item]] = true
        
         # adjust the refresh if newer
         nr[:refresh] = [nr[:refresh], st[:refresh]].max
      end

      # already want newer or same, nothing more to do
      return if( nr[:serial] >= st[:serial] )
      
      # we do not want this version, do cleanup
      record_unwanted(nr)
   end
    
   #####################
   # want a new record

   # record we want it
   @wanted[st[:item]] = {
      level: st[:level],
      type: st[:type],
      item: st[:item],
      serial: st[:serial],
      refresh: st[:refresh],
      avail_from: { nid => true },
      req_from: nil,
   }

   # record the neighbor has it
   @neighbor[nid][:has_wanted][st[:item]] = true

end # def record_sync()


#################################################
# We no longer want a record
# 
# @param wi [Hash] the wanted record
# 
def record_unwanted(wi)

   # cancel the request
   if( wi[:req_from] )
      @neighbor[wi[:req_from]][:request] = nil
   end
  
   # clean all the neighbors that have a copy
   wi[:avail_from].each_key do |nid|
      @neighbor[nid][:has_wanted].delete(wi[:item])
   end

   # remove the we-want-it record
   @wanted.delete(wi[:item])
  
end # def record_unwanted()


#################################################
# Save content for a record
# 
# @param rec [Records::Base] the record
# @param ref [Integer] the refresh
# 
def record_content(rec, ref)

   # if we wanted this record, we have it now
   nr = @wanted[rec.id]
   if( nr && nr[:serial] <= rec.serial )
      record_unwanted(nr)
   end
  
   # we have the same or newer version
   pr = @record[rec.id]
   if( pr && pr[:serial] >= rec.serial )

      # a refresh
      if( pr[:serial] == rec.serial && pr[:refresh] < ref )
         @change = @change + 1
         @time_change = @nis.now
         pr[:refresh] = ref
         pr[:refresh_time] = @nis.now
         pr[:change] = @change

         # restore a dropped item
         if( pr[:dropped] )
            pr[:dropped] = false
            trigger_update(rec)
         end
      end
     
      return
   end

   # area state does not bar it
   area = @area[rec.level-1]
   if(   (rec.type == :link && area[:partition] > ref) ||
         (rec.type == :addr && area[:election] > ref) )
      return
   end

   # store the record
   @change = @change + 1
   @time_change = @nis.now
   info = {
      level: rec.level,
      type: rec.type,
      item: rec.id,
      serial: rec.serial,
      refresh: ref,
      refresh_time: @nis.now,
      change: @change,
      dropped: false,
   }
   @record[rec.id] = info
   @content[rec.id] = rec.dup

   # notify everyone of the update
   trigger_update(rec)

end # def record_content()
  

#################################################
# Delete a record
# 
# @param rid [String] the record ID
# @param ser [Integer] the serial
# 
def record_delete(rid, ser)
  
   # must have the record and have provided a higher serial
   pr = @record[rid]
   if( !pr || pr[:serial] >= ser )
      return
   end
          
   # store the record
   @change = @change + 1
   @time_change = @nis.now
   pr[:serial] = ser
   pr[:refresh] = 0
   pr[:refresh_time] = @nis.now
   pr[:change] = @change

   # if we removed something from the database
   rec = @content[rid]
   if( rec )
      @content.delete(rid)
      trigger_remove(rec, ser)
   end

   # we wanted something we just deleted
   nr = @wanted[rid]
   if( nr && nr[:serial] <= ser )
      record_unwanted(nr)
   end

end # def record_delete()
  

#################################################
# Add/update a record
#
# @param rec [Records::Base] the record being added or updated
#
def trigger_update(rec)

   # log
   log(:verbose, "DB %d update %s ser %d typ %s" %
      [rec.level, rec.id, rec.serial, rec.type] )

   # send trigger
   case rec.type
   when :link
      @nis.trigger(:db_link_update, rec.level, rec)
   when :addr
      @nis.trigger(:db_addr_update, rec.level, rec)
   when :fill
      @nis.trigger(:db_fill_update, rec.level, rec)
   when :path
      @nis.trigger(:db_path_update, rec.level, rec)
   when :egress
      @nis.trigger(:db_egress_update, rec.level, rec)
   when :demand
      @nis.trigger(:db_demand_update, rec.level, rec)
   end

end # def trigger_update()


#################################################
# Remove a record
#
# @param rec [Records::Base] the record being removed
# @param ser [Integer] the new serial
#
def trigger_remove(rec, ser)

   # log
   log(:verbose, "DB %d remove %s ser %d typ %s old %d" %
      [rec.level, rec.id, ser, rec.type, rec.serial] )

   # send trigger
   case rec.type
   when :link
      @nis.trigger(:db_link_remove, rec.level, rec)
   when :addr
      @nis.trigger(:db_addr_remove, rec.level, rec)
   when :fill
      @nis.trigger(:db_fill_remove, rec.level, rec)
   when :path
      @nis.trigger(:db_path_remove, rec.level, rec)
   when :egress
      @nis.trigger(:db_egress_remove, rec.level, rec)
   when :demand
      @nis.trigger(:db_demand_remove, rec.level, rec)
   end

end # def trigger_remove()


end # class TEZC::Info::Database

end # module Info
end # module TEZC 