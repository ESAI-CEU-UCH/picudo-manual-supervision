-- Copyright (c) 2015 Francisco Zamora-Martinez (francisco.zamora@uch.ceu.es)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.

local gp = require "april_tools.gnuplot"()
local f  = matrix.fromTabFilename(arg[1])

local function next_power_of_two(WSIZE)
  local p = 1
  while p < WSIZE do p=p*2 end
  return p
end

local HZ        = 44100
local WSIZE     = 23.2 -- mili seconds, approx 1024 samples
local WSIZE     = next_power_of_two(math.round(WSIZE * HZ / 1000.0))
local FFT_SIZE  = WSIZE/2.0
local BIN_WIDTH = 0.5*HZ / FFT_SIZE

local str = { "plot '#1' u ($0*%f):1 w l notitle lc 0" % { BIN_WIDTH } }
for i=2,f:dim(2) do str[#str+1] = ", '' u ($0*%f):%d w l notitle lc 0" % { BIN_WIDTH, i } end
local str = table.concat(str)
  
gp:rawplot(f, str)
io.read("*l")
