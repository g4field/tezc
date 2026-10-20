#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'sim_linux_gen'


desc_l1 = {

   # 4 routers
   routers: 4,
   hosts: 2,

   # full mesh links
   links: [
      ['r0', 'r1', 100000],
      ['r2', 'r3', 100000],
      ['r0', 'r2', 100000],
      ['r1', 'r3', 100000],
      ['r0', 'r3', 100000],
      ['r1', 'r2', 100000],
   ]
}

topo_spec =  {

   areas: [
      { count: 3, spec: desc_l1 },
   ],

   links: [
      ['a0r2', 'a1r1', 100000],
      ['a0r3', 'a2r0', 100000],
      ['a1r3', 'a2r2', 100000],
   ]
}

# name of this topology
dir = 'demo'

# generate it
gen = TEZC::Test::SimLinuxGen.new
gen.gen_specified('', topo_spec)

# hosts[xa][xh] = xr
hosts = [ [0, 1], [0, 2], [1, 3] ]

hp = Array.new(3){ Array.new(2) }
3.times do |xa|
   2.times do |xh|
     
      xr = hosts[xa][xh]

      # add hosts
      hp[xa][xh] = gen.host_add(
         'a%dh%d' % [xa, xh],
         'a%dr%d' % [xa, xr],
         '10.%d.%d.2' % [xa, xh],
         '10.%d.%d.1' % [xa, xh],
         24, 100000)

      # add demands
      3.times do |ya|
         2.times do |yh|
            next if( ya == xa && yh == xh )
            gen.demand_add(
               'a%dr%d' % [xa, xr],
               hp[xa][xh],
               '10.%d.%d.2/32' % [ya, yh],
               5, 15000
            )
         end
      end
   end
end

gen.build(dir)
