if #arg ~= 2 then
  fprintf(io.stderr, "SYNTAX: april-ann %s INPUT_WAV_MAT OUTPUT_FB_MAT\n",
          arg[0])
  os.exit(1)
end
local wav_mats = arg[1] -- input
local fb_mats  = arg[2] -- output
--
local HZ       = 44100
local WSIZE    = 23.2 -- mili seconds, approx 1024 samples
local WADVANCE = 11.6 -- mili seconds, approx 512 samples
local LOWER_BAND = 1000 -- Hz
local UPPER_BAND = 8000 -- Hz
local NUM_FB     = 24
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
                                                     FFT_SIZE, NUM_FB)
  local function freq2log(fHz) return math.log10( 1 + fHz ) end
  local function log2freq(fHz) return ( 10.0^( fHz ) - 1.0 ) end
  --
  local log_min = freq2log(LOWER_BAND)
  local log_max = freq2log(UPPER_BAND)
  local BIN_WIDTH = 0.5*HZ / FFT_SIZE
  local LOG_WIDTH = (log_max - log_min) / (NUM_FB + 1)
  -- create a bank filter matrix (sparse matrix)
  local filter = matrix(FFT_SIZE, NUM_FB):zeros()
  local centers = {}
  for i=1,NUM_FB+2 do centers[i] = log2freq(log_min + (i-1)*LOG_WIDTH) end
  for i=1,NUM_FB do
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

-------------------------------------------------------------------------

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
                                                                NUM_FB)
local function apply_compress(fb,...)
  return fb:clone():clamp(1.0, math.huge):log(),...
end

------------------------------------------------------------------------------

iterator.zip(iterator(io.lines(wav_mats)), iterator(io.lines(fb_mats))):
  map(function(...)
      print("#", ...)
      return ...
  end):
  map(load_matrix):
  map(apply_fft):
  map(apply_filter_bank):
  map(apply_compress):
  apply(function(result, output_filename)
      result:toFilename(output_filename)
  end)
