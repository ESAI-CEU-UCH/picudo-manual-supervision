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

local DESCRIPTION = "Bootstrap by using previously trained model and a basic HMM viterbi algorithm"

local common = require "scripts.common"
local cmd    = require "scripts.cmdopt"
local round  = math.round
--
local opt = cmd.new(arg, DESCRIPTION)
cmd.add_help(opt)
cmd.add_bootstrap(opt)
--
local params  = cmd.parse(opt, arg)
--
local POSITIVE_PRIOR = 0.1
local POSITIVE_LOOP  = 0.1
local NEGATIVE_PRIOR = 1 - POSITIVE_PRIOR
local NEGATIVE_LOOP  = 0.9
--
local bsize       = params.bsize
local HZ          = params.hz
local wsize       = params.wsize/1000.0
local wadvance    = params.wadvance/1000.0
local saved_data  = util.deserialize(params.model)
local model       = assert(saved_data.model)
local net         = model:get_component()
local mean_dev    = assert(saved_data.mean_dev)

-- HMM for sequence merging, it allow to classify every segment of data as
-- positive or negative
local hmm = HMMTrainer.trainer()
hmm.trainer:set_a_priori_emissions({ POSITIVE_PRIOR, NEGATIVE_PRIOR })
local hmm_sequence = hmm:model{
  name = "hmm_sequence",
  transitions = {
    { from="ini", to="pos1", prob=0.5, emission=1 },
    { from="ini", to="neg1", prob=0.5, emission=2 },
    { from="fin",  to="ini", prob=1, emission=0 },
    --
    { from="pos1", to="pos1", prob=POSITIVE_LOOP, emission=1 },
    { from="pos1", to="fin", prob=1-POSITIVE_LOOP, emission=0, output="T" },
    --
    { from="neg1", to="neg1", prob=NEGATIVE_LOOP, emission=2 },
    { from="neg1", to="fin", prob=1-NEGATIVE_LOOP, emission=0, output="F" },
  },
  initial = "ini",
  final = "fin",
}
local hmm_sequence = hmm_sequence:generate_C_model()

------------------------------------------------------------------------------
------------------------------ FUNCTIONS BEGIN -------------------------------
------------------------------------------------------------------------------

local function window2time(v)
  -- v starts at 1 in Lua, so we substract one to start at 0
  return (v-1)*wadvance + (wsize/2.0)
end

local function build_hmm_emiss_from_ann_output(file_pos_frames)
  local hmm_emiss = matrix(file_pos_frames:dim(1), 2)
  hmm_emiss[{':',1}] = matrix.op.exp(file_pos_frames) -- 1 = positive class
  hmm_emiss[{':',2}] = (1.0 - hmm_emiss(':',1))       -- 2 = negative class
  return hmm_emiss
end

local function viterbi(hmm_emiss)
  local seq = matrix(hmm_emiss:dim(1))
  local lprob,str = hmm_sequence:viterbi{
    input_emission      = hmm_emiss,
    do_expectation      = false,
    -- output_emission     = m,
    output_emission_seq = seq,
  }
  seq:scalar_add(-1):complement()
  return seq
end

local function info_matrix_from_prob_sequence(seq, TH)
  local info = {}
  local first_true_pos = -math.huge
  for j=1,seq:dim(1) do
    local v = seq:get(j)
    if v < TH and first_true_pos > 0 then
      local start = window2time(first_true_pos)
      local stop  = window2time(j-1)
      table.insert(info, start)
      table.insert(info, stop)
      first_true_pos = -math.huge
    elseif v >= TH and first_true_pos < 0 then
      first_true_pos = j
    end
  end
  return matrix(#info/2, 2, info)
end

local function generate_info_from_outputs(outputs, sizes)
  assert(outputs:dim(3) == 1, "Not implemented for multi-label task")
  local N        = outputs:dim(1) -- number of files
  local infos    = {}
  for i,file_pos_frames in matrix.ext.iterate(outputs) do
    local file_pos_frames = file_pos_frames({ 1, sizes[i] }, ':')
    local hmm_emiss = build_hmm_emiss_from_ann_output(file_pos_frames)
    local seq       = viterbi(hmm_emiss)
    infos[i] = info_matrix_from_prob_sequence(seq, 0.5)
  end
  return infos
end

local lines_it = function(filename) return iterator(io.lines(filename)) end

local function sequence_bunch_iterator(bsize, it)
  local finished = false
  return function()
    if finished then return end
    local bunch = {}
    while #bunch < bsize do
      local c = table.pack(it())
      if not c[1] then break end
      table.insert(bunch, c)
    end
    finished = (#bunch < bsize) or (#bunch == 0)
    if #bunch > 0 then return bunch end
  end
end

local function bypass1(func)
  return function(one, ...)
    return func(one), ...
  end
end

local numP = dataset.."numPatterns"
local getP = dataset.."getPattern"

local function not_finished_datasets(ds, pos) return pos <= numP(ds) end

------------------------------------------------------------------------------
------------------------------ FUNCTIONS END ---------------------------------
------------------------------------------------------------------------------

local isize = model:get_input_size()
local osize = model:get_output_size()

print("# Model input size= ", isize)
print("# Num classes=      ", osize)

-- traverse the files list taking 'bsize' files at a time
for bunch in sequence_bunch_iterator(bsize,
                                     iterator.zip(lines_it(params.list),
                                                  lines_it(params.info))) do
  collectgarbage("collect")
  print("# Loading:")
  print(iterator.zip(iterator.duplicate("#\t"),
                     iterator(bunch):map(table.unpack)):concat(" ", "\n"))
  -- transform the bunch of files into a bunch of datasets plus info filenames
  local bunch = iterator(bunch):
    map(table.unpack):
    map(bypass1(matrix.fromFilename)):
    map(bypass1(common.extract_datasets_from_matrix)):
    map(table.pack):
    table()
  -- sort the files by its length, in decreasing order
  table.sort(bunch, function(a,b) return numP(a[1]) > numP(b[1]) end)
  --
  local data = iterator(bunch):field(1):table()
  local info_bunch = iterator(bunch):field(2):table()
  common.normalize_mean_dev(data, mean_dev)
  common.contextualize(params, { input_ds=data })
  print("# Num patterns=     ", iterator(data):map(numP):sum())
  print("# Current bunch=    ", #data)
  assert(#data == #info_bunch)
  local psize = data[1]:patternSize()
  april_assert(psize == isize,
               "Incorrect dataset pattern size, found %d, expected %d",
               psize, model:get_input_size())
  -- take the longer num patterns value in datasets list
  local longer = iterator(data):map(numP):reduce(math.max,0)
  -- the output would be stored at 'result' matrix
  local result = matrix(#data, longer, osize):fill(-math.huge)
  net:reset()
  -- process every frame
  for pos=1,longer do
    -- build an input with only whose datasets with greater or equal 'pos'
    -- patterns
    local input = matrix.join(1,
                              iterator(data):
                                filter(bind(not_finished_datasets, nil, pos)):
                                map(bind(getP, nil, pos)):
                                map(bind(matrix, 1, psize)):
                                table())
    -- forward step
    local output = assert( net:forward(input) )
    assert( #output:dim() == 2 )
    -- copy the output to the result matrix
    result[{ {1, input:dim(1)}, pos, ':' }] = output:rewrap(output:dim(1), 1,
                                                            output:dim(2))
  end
  -- table with size of every dataset in the list
  local sizes = iterator(data):map(numP):table()
  local info_result = generate_info_from_outputs(result, sizes)
  -- write the result to disk
  for i,info_filename in ipairs(info_bunch) do
    print("# Writting bootstrap ", i, " info to ", info_filename)
    info_result[i]:toTabFilename(info_filename)
  end
end
