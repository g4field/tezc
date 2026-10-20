#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'sim_linux_gen'

#################################################
# Create a pod
def pod_create()

   # 12 routers
   links = []
   desc = {
      routers: 12,
      links: links
   }

   # full mesh of links
   12.times do |rix|
      (11-rix).times do |oix|
         lk = [
            'r%d' % rix,
            'r%d' % [rix + oix + 1],
            100000
         ]
         links.push(lk)
      end
   end
  
   return desc
end # def pod_create()


#################################################
# Create a network
def net_create(podcnt)

   # create the pod description
   pod_spec = pod_create()

   # create the network
   links = []
   spec = {
      areas: [
         { count: podcnt+1, spec: pod_spec },
      ],

      links: links
   }
 
   # create intra-area links for the main network
   port_b = 0
   pix_b = 0
   (podcnt-1).times do |pix_a|

      # if we were going to do this pod next
      # else we already did it.
      if( pix_b == pix_a )
         port_a = port_b
         pix_b = pix_a+1
      else
         port_a = port_b+1
      end

      # assign each external link
      while( port_a < 36 )
         lk = [
            'a%dr%d' % [pix_a, port_a/3],
            'a%dr%d' % [pix_b, port_b/3],
            100000
         ]
         links.push(lk)

         # next neighbor/port 
         pix_b = pix_b + 1
         if( pix_b >= podcnt )
            pix_b = pix_a + 1
            port_b = port_b + 1
         end
         port_a = port_a + 1
      end

   end

   # tack on the extra pod with a single link
   lk = [
         'a%dr0' % [podcnt-1, 14],
         'a%dr0' % [podcnt, 11],
         100000
      ]
   links.push(lk)

   return spec

end # def net_create()



podcnt = ARGV[0].to_i

# name of this topology
dir = 'pods_%d' % podcnt

# build a topo
topo_spec = net_create(podcnt)

# generate it
gen = TEZC::Test::SimLinuxGen.new
gen.gen_specified('', topo_spec)

# make a single host for each pod
hp = Array.new(podcnt+1)
hp.each_index do |pix|
   hp[pix] = gen.host_add(
         'a%dh0' % [pix],
         'a%dr0' % [pix],
         '10.0.%d.2' % [pix],
         '10.0.%d.1' % [pix],
         24, 100000)

end

# add demands from each host to each other host
hp.each_index do |pix_a|
   hp.each_index do |pix_b|
      next if( pix_a == pix_b )
      gen.demand_add(
            'a%dr0' % [pix_a],
            hp[pix_a],
            '10.0.%d.2/32' % [pix_b],
            4, 15000)
   end
end

gen.build(dir)