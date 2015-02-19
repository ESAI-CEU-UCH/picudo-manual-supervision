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

if #arg < 3 or #arg > 4 then
  fprintf(io.stderr, "SYNTAX: april-ann %s INPUT_WAV_MAT INFOS OUTPUT_FB_MAT [FB_LEN=24]\n",
          arg[0])
  os.exit(1)
end
local wav_mats   = arg[1] -- input
local infos      = arg[2] -- infos list
local fb_mats    = arg[3] -- output
local FB_LEN     = tonumber(arg[4] or 24) -- number of filters in the filter bank
--
local HZ         = 44100
local WSIZE      = 23.2 -- mili seconds, approx 1024 samples
local WADVANCE   = 11.6 -- mili seconds, approx 512 samples
local LOWER_BAND = 1000 -- Hz
local UPPER_BAND = 8000 -- Hz
--
local function next_power_of_two(WSIZE)
  local p = 1
  while p < WSIZE do p=p*2 end
  return p
end
--
local WSIZE = next_power_of_two(math.round(WSIZE * HZ / 1000.0))
local WADVANCE = next_power_of_two(math.round(WADVANCE * HZ / 1000.0))
local FFT_SIZE = WSIZE/2.0

local function make_log_triangular_overlapped_filter(HZ, LOWER_BAND, UPPER_BAND,
                                                     FFT_SIZE, FB_LEN)
  local function freq2log(fHz) return math.log10( 1 + fHz ) end
  local function log2freq(fHz) return ( 10.0^( fHz ) - 1.0 ) end
  --
  local log_min = freq2log(LOWER_BAND)
  local log_max = freq2log(UPPER_BAND)
  local BIN_WIDTH = 0.5*HZ / FFT_SIZE
  local LOG_WIDTH = (log_max - log_min) / (FB_LEN + 1)
  -- create a bank filter matrix (sparse matrix)
  local filter = matrix(FFT_SIZE, FB_LEN):zeros()
  local centers = {}
  for i=1,FB_LEN+2 do centers[i] = log2freq(log_min + (i-1)*LOG_WIDTH) end
  for i=1,FB_LEN do
    local fb = filter:select(2,i)
    -- compute triangle
    local start  = math.min(math.round(centers[i] / BIN_WIDTH)+1, FFT_SIZE)
    local center = math.min(math.round(centers[i+1] / BIN_WIDTH)+1, FFT_SIZE)
    local stop   = math.min(math.round(centers[i+2] / BIN_WIDTH)+1, FFT_SIZE)
    -- compute bandwidth (number of indices per window)
    local inc = 1.0/(center - start)
    local dec = 1.0/(stop - center)
    -- compute triangle-shaped filter coefficients
    fb({start,center-1}):linear(0):scal(inc) -- left ramp
    fb({center,stop-1}):linear(0):scal(dec):complement() -- right ramp
    -- normalize the sum of coefficients:
    fb:scal(1/fb:sum())
    -- check for nan or inf
    assert(fb:isfinite(), "Fatal error on log filter bank")
  end
  filter:toTabFilename("filter.txt")
  local filter = matrix.sparse.csc(filter)
  return function(fft,...) return fft * filter,... end
end

local function build_class_matrix(info_filename, result)
  local N = result:dim(1)
  local class = matrix(N, 4):zeros()
  local wsize = WSIZE/HZ       -- in seconds
  local wadvance = WADVANCE/HZ -- in seconds
  local infos = matrix.fromTabFilename(info_filename)
  for _,row in matrix.ext.iterate(infos) do
    local start = math.round(row:get(1) / wadvance)
    local stop  = math.round(row:get(2) / wadvance)
    local diff  = stop - start + 1
    local c1    = math.round( start + diff * 1.0/3.0 )
    local c2    = math.round( start + diff * 2.0/3.0 )
    if diff <= 3 then
      fprintf(io.stderr,"WARNING!!! Underflow number of positive samples\n")
      stop, diff = start + 3, 4
    end
    class({start, stop}, 1):ones()
    class({start, c1-1}, 2):ones()
    class({c1,    c2-1}, 3):ones()
    class({c2,    stop}, 4):ones()
  end
  return class
end
-------------------------------------------------------------------------

local function tee(...) print("#", ...) return ... end

local function load_matrix(filename,...)
  local m = matrix.fromTabFilename(filename)
  return m:rewrap(m:size()),...
end

local function apply_fft(raw,...)
  return matrix.ext.real_fftwh(raw, WSIZE, WADVANCE),...
end

local apply_filter_bank = make_log_triangular_overlapped_filter(HZ,
                                                                LOWER_BAND,
                                                                UPPER_BAND,
                                                                FFT_SIZE,
                                                                FB_LEN)
local function apply_compress(fb,...)
  return fb:clone():clamp(1.0, math.huge):log(),...
end

local function write_data(result, info_filename, output_filename)
  collectgarbage("collect")
  local class = build_class_matrix(info_filename, result)
  local result = matrix.join(2, result, class)
  result:toFilename(output_filename)
end

------------------------------------------------------------------------------

iterator.zip(iterator(io.lines(wav_mats)),
             iterator(io.lines(infos)),
             iterator(io.lines(fb_mats))):
  map(tee):
  map(load_matrix):
  map(apply_fft):
  map(apply_filter_bank):
  map(apply_compress):
  apply(write_data)
