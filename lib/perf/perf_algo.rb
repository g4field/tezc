#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'perf'
require_relative '../algo/avoid_cong'

module TEZC
module Perf


##########################################################################
# Measure the routing performance
#
class AlgoTest

#################################################
# number of routers per base area
ROUTER_BASE = 12

# ports per router
PORT_ROUTER = 16

# customers per router
CUST_ROUTER = 2

# internal links per routers
INTERN_ROUTER = 11

# external links per router
EXTERN_ROUTER = 3

# links in the base area
LINKS_ROUTER = [ 1, 2, 3, 4, 5, 6 ]

#################################################
# new network and demand pattern
# 
# @param num_nodes [Integer] number of nodes
# @param spd [Integer] speed of the links
# @param png [Random] the random number generator
# 
def initialize(num_nodes, spd, png)
  
   # save the random number generator
   @png = png
   @spd = spd

   # create the nodes
   # base areas with a regular mesh of links
   nodes = []
   num_nodes.times do |nix|
     
      # name of this node
      name = nix.to_s
     
      # routers
      routers = Array.new(ROUTER_BASE) do |rix|
         Perf::Router.new("%s router %d" % [name, rix],
               0, PORT_ROUTER)
      end
      tors = Array.new(ROUTER_BASE * CUST_ROUTER) do |tix|
         Perf::Router.new("%s router %d" % [name, tix+ROUTER_BASE],
               1, 1)
      end
      routers.concat(tors)

      # aggregate them into an area
      nd = Perf::Area.new(routers)
      nodes[nix] = nd

      # pair the ports
      ROUTER_BASE.times do |rix|

         # links between MR
         LINKS_ROUTER.each_index do |ix|
            offs = LINKS_ROUTER[ix]

            # skip if alreaydy linked by previous
            next if( 2*offs == ROUTER_BASE && rix*2 >= ROUTER_BASE )

            # ports
            pixY = ix*2
            pixZ = ( 2*offs == ROUTER_BASE ) ? pixY : (pixY+1)

            # link
            ptY = routers[rix].ports[pixY]
            ptZ = routers[(rix+offs)%ROUTER_BASE].ports[pixZ]
            Perf::Pairable.pair_items(ptY, ptZ)
         end

         # links to ToRs
         CUST_ROUTER.times do |cix|
            ptY = routers[rix].ports[PORT_ROUTER-1-cix]
            ptZ = routers[ROUTER_BASE+(CUST_ROUTER*rix)+cix].ports[0]
            Perf::Pairable.pair_items(ptY, ptZ)
         end
      end
      
      # create nodes from port pairs
      nd.link_pairs(spd)

   end

   # aggregate the nodes into an area
   @area = Perf::Area.new(nodes)

   # sanity check
   @area.nodes.each do |nd|
      raise "wtf" if( nd.ports.size != EXTERN_ROUTER*ROUTER_BASE )
   end

end # def initialize()


#################################################
# make demands
# 
# @param num_conc [Integer] number of demands concentrated
# @param num_local [Integer] number of demands local
# @param num_rand [Integer] number of demands random
# 
def demands(num_conc, num_local, num_rand)

   #####################
   # save what we should have
   @tot_demands = @area.nodes.size * ROUTER_BASE * CUST_ROUTER * 16
   @tot_request = @tot_demands * @spd/16
  
   # sanity check
   if( num_conc + num_local + num_rand != 16 )
      raise "wtf"
   end 

   # pair the nodes for concentrated traffic
   @area.nodes.each{|nd| nd.pair_slots = 2 }
   Perf::Pairable.pair_one_set(@area.nodes, @area.nodes.size, @png)

   # allocate customer slots
   customers = []
   @area.nodes.each{|nd| customers.concat(nd.customers) }
   customers.each{|cs| cs.pair_slots = 16 }

   # pair the customers for local traffic
   if( num_local > 0 )
      @area.nodes.each do |nd|
         Perf::Pairable.pair_one_set(nd.customers,
               num_local*CUST_ROUTER*ROUTER_BASE/2, @png)
      end
   end

   tot_slots = customers.map{|it| it.pair_slots}.sum

   # pair the customers for concentrated traffic
   if( num_conc > 0 )
      pair_done = []
      @area.nodes.each do |nd|
      
         # mark as done
         pair_done.push( nd )

         # make pairs
         nd.pairs.each do |ndp|
            next if( pair_done.include?( ndp ) )
            Perf::Pairable.pair_two_sets(
                  nd.customers, ndp.customers,
                  num_conc*CUST_ROUTER*ROUTER_BASE/2, @png)
         end
      end
   end

   tot_slots = customers.map{|it| it.pair_slots}.sum
   
   # pair the customers randomly
   if( num_rand > 0 )
      Perf::Pairable.pair_one_set(
            customers,
            @area.nodes.size*num_rand*CUST_ROUTER*ROUTER_BASE/2, @png)
   end

   tot_slots = customers.map{|it| it.pair_slots}.sum

   # sanity check
   if( tot_slots != 0 )
      raise "wtf"
   end

   # make demands from the pairs
   @area.demand_pairs(@spd/16)

   # calculate the fat tree demand info
   cnt_m = 0
   cnt_e = 0
   cnt_o = 0
  
   # each customer pairing list
   customers.each do |cst_a|
      # each pair
      cst_a.pairs.each do |cst_b|

         # offsets
         off_a =  (cst_a.addr[1]-1)*CUST_ROUTER*ROUTER_BASE +
                  (cst_a.addr[0]-1)*CUST_ROUTER +
                  cst_a.ix
         off_b =  (cst_b.addr[1]-1)*CUST_ROUTER*ROUTER_BASE +
                  (cst_b.addr[0]-1)*CUST_ROUTER +
                  cst_b.ix

         # same MR
         if( off_a / 16 == off_b / 16 )
            cnt_m = cnt_m + 1

         # same edge
         elsif( off_a / 64 == off_b / 64 )
            cnt_e = cnt_e + 1

         # other
         else
            cnt_o = cnt_o + 1
         end
      end
   end
   
   # the totals
   @ft_demands = {
      mr: cnt_m,
      edge: cnt_m,
      other: cnt_o,
   }
   
end # def demands()
  

#################################################
# Create area links
# 
# @param adapt [Integer] number of links per node pair
def links(num_pair)
  
   # sanity check
   raise "wtf" if( num_pair > 12 )
  
   # calculations
   num_mesh = EXTERN_ROUTER*ROUTER_BASE - num_pair*2
    
   # remove any existing links
   @area.links.clear
   @area.nodes.each do |nd|
     
      # clean up ports
      nd.ports.each do |pt|
         pt.link = nil
         pt.pairs.clear
         pt.pair_slots = 1
      end

      # random order on the ports
      nd.ports.shuffle!(random: @png)
   end

   # create the mesh
   ports = @area.nodes.map{|nd| nd.ports }
   Perf::Pairable.pair_mesh(ports, num_mesh, @png)

   # sanity check
   ports.each do |pta|
      slots = pta.map{|pt| pt.pair_slots}.sum 
      raise "wtf" if( slots != num_pair*2 )
   end
  
   # pair the ports for concentrated traffic
   if( num_pair != 0 )
      pair_done = []
      @area.nodes.each do |nd|
      
         # mark as done
         pair_done.push( nd )

         # make pairs
         nd.pairs.each do |ndp|
            next if( pair_done.include?( ndp ) )
            Perf::Pairable.pair_two_sets(nd.ports, ndp.ports, num_pair, @png)
         end
      end
   end

   # sanity check
   @area.nodes.each do |nd|
      nd.ports.each do |pt|
         raise "wtf" if( pt.pair_slots != 0 ) 
      end
   end

   # create links
   @area.link_pairs(@spd)
  
end # def links()
  

#################################################
# generate stats
def stats(algo)
  
   # clear old derivative demands
   @area.nodes.each do |nd|
      nd.demands.delete_if{|dem| dem[:pri] == 7 }
   end

   # route the area
   @area.route(algo)

   # go thru the node demands and see how much they carry
   dems_all = {}
   @area.nodes.each do |nd|
      nd.demands.each do |dem|
         if( dems_all.key?( dem[:id] ) )
            dems_all[dem[:id]] = {
               fill: [dems_all[dem[:id]][:fill], dem[:fill]].min,
               hops: dems_all[dem[:id]][:hops] + dem[:hops],
            }
         else
            dems_all[dem[:id]] = {
               fill: dem[:fill],
               hops: dem[:hops],
            }
         end
      end
   end

   # add in the hops from the level 2 network
   @area.demands.each do |dem|
      if( dems_all.key?( dem[:id] ) )
         dems_all[dem[:id]][:hops] = dems_all[dem[:id]][:hops] + dem[:hops]
      else
         raise "wtf"
      end
   end

   rt_request = 0
   @area.demands.each do |dem|
      rt_request = rt_request + dem[:spd] if( dem[:pri] != 7 )
   end
   @area.nodes.each do |nd|
      nd.demands.each do |dem|
         rt_request = rt_request + dem[:spd] if( dem[:pri] != 7 )
      end
   end

   rt_demands = dems_all.size
   rt_filled = dems_all.values.map{|inf| inf[:fill]}.sum
   rt_hops = dems_all.values.map{|inf| inf[:hops]}.sum.to_f / rt_demands
   rt_frac = rt_filled.to_f / rt_request

   # sanity check
   if( rt_demands != @tot_demands || rt_request != @tot_request )
      raise "oops"
   end

   # hops in a fat-tree
   ft_hops = (
         2*@ft_demands[:mr] +
         4*@ft_demands[:edge] +
         9.875*@ft_demands[:other]) / rt_demands

   # return the stats
   return {
      nodes: @area.nodes.size,
      num_demands: rt_demands,
      tot_request:  rt_request,
      tot_filled: rt_filled,
      tot_hops: rt_hops,
      ft_hops: ft_hops
   }

end # def stats()

end # class TEZC::Perf::AlgoTest

end # module TEZC::Perf
end # module TEZC
  

file_algo = File.open(ARGV[0], 'w')
file_dat = File.open(ARGV[1], 'w')
algo = TEZC::Algorithm::AvoidCong.new(file_algo)
png = Random.new
spd = 40000000

# connections for concentrated traffic
# 16 total splits per ToR
# c splits to paired nodes
# 2 paired nodes per node
# c * ROUTER_BASE * CUST_ROUTER / (2 * 16) to each paired node
# 
# Run:
# Number of nodes: 3 to ?
# Traffic patterns (conc, local, rand):
#   Even: 0, 0, 16
#   Conc: 16, 0, 0
#   Vary: c, 0, 16-c for c between 0 and 16
# 
# Connections, mesh or adapted
# 
if( ARGV[2] == '-' )
   vary_conc = true
   num_nodes = ARGV[3].to_i
else
   num_conc = ARGV[2].to_i
   num_rand = 16 - num_conc
end


# print info
file_dat.puts "random seed: %d" % png.seed

# print the header
file_dat.puts "nodes\tconc\tfill\thops\tfilla\thopsa\thopsf"


# generate stats
def gen_stats(num_nodes, num_conc, num_rand, spd, algo, png, file_dat)
 
   adapt = (
      (num_conc *
      TEZC::Perf::AlgoTest::ROUTER_BASE *
      TEZC::Perf::AlgoTest::CUST_ROUTER
      ).to_f / 32).ceil


   file_dat.flush
  
   av_fill = 0.0
   av_hops = 0.0
   av_filla = 0.0
   av_hopsa = 0.0
   av_ft = 0.0

   # average 5 runs
   5.times do

      # construct the network with demands
      net = TEZC::Perf::AlgoTest.new(num_nodes, spd, png)
      net.demands(num_conc, 0, num_rand)

      # mesh links
      puts( "mesh %d" % num_nodes )
      net.links(0)
      stats = net.stats(algo)

      av_ft = av_ft + stats[:ft_hops]
      av_fill = av_fill + stats[:tot_filled].to_f / stats[:tot_request]
      av_hops = av_hops + stats[:tot_hops]

      # adapted links
      if( adapt != 0 )
         puts( "adapt %d" % [num_nodes] )
         net.links(adapt)
         statsa = net.stats(algo)

         av_filla = av_filla + statsa[:tot_filled].to_f / statsa[:tot_request]
         av_hopsa = av_hopsa + statsa[:tot_hops]
      end
   end

   # take the averages
   av_fill = av_fill / 5
   av_hops = av_hops / 5
   av_filla = av_filla / 5
   av_hopsa = av_hopsa / 5
   av_ft = av_ft / 5

   # print the line
   file_dat.puts "%d\t%d\t%0.4f\t%0.4f\t%0.4f\t%0.4f\t%0.4f" % [
      num_nodes, num_conc,
      av_fill, av_hops,
      av_filla, av_hopsa,
      av_ft
   ]
end # def gen_stats()


# vary conc
if( vary_conc )

   (0..16).each do |num_conc|
      num_rand = 16 - num_conc
      gen_stats(num_nodes, num_conc, num_rand, spd, algo, png, file_dat)
   end
  
# vary nodes
else

   # number of nodes
   (3..24).each do |num_nodes|
      gen_stats(num_nodes, num_conc, num_rand, spd, algo, png, file_dat)
   end

end
