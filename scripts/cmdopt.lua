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

local cmd = {} -- exported table

-- GENERIC ADD FUNCTIONS

local function add_void(cmd_opt_parser, description, long, short)
  cmd_opt_parser:add_option{
    description = assert(description),
    index_name = assert(long),
    long = long,
    short = short,
    argument = "no",
  }
end

local function add_num(cmd_opt_parser, description, long, short, default,
                       always, action)
  cmd_opt_parser:add_option{
    description = assert(description),
    index_name = assert(long),
    long = long,
    short = short,
    argument = "yes",
    filter = tonumber,
    default_value = default,
    mode = ((default or always) and "always") or nil,
    action = action,
  }
end

local function add_str(cmd_opt_parser, description, long, short, default,
                       always, action)
  cmd_opt_parser:add_option{
    description = assert(description),
    index_name = assert(long),
    long = long,
    short = short,
    argument = "yes",
    default_value = default,
    mode = ((default or always) and "always") or nil,
    action = action,
  }
end

function add_defopt(opt)
  assert(opt, "Needs a cmdOpt object")
  opt:add_option{
    description = "Default options table",
    index_name = "defopt",
    short = "f",
    argument = "yes",
    filter = function(v)
      return assert(util.deserialize(v), "Impossible to open defopt table")
    end
  }
end

-------------- EXPORTED FUNCTIONS ----------------

function cmd.new(arg, description)
  local opt = cmdOpt{
    program_name = arg[0]:basename(),
    argument_description = "",
    main_description = description,
  }
  add_defopt(opt)
  return opt
end

function cmd.add_help(opt)
  assert(opt, "Needs a cmdOpt object")
  opt:add_option{
    description = "Shows this help message",
    short = "h",
    long = "help",
    argument = "no",
    action = function (argument)
      print(opt:generate_help())
      os.exit(1)
    end
  }
end

function cmd.add_dataset(opt)
  assert(opt, "Needs a cmdOpt object")
  add_str(opt, "Training list", "train", nil, nil, true)
  add_str(opt, "Validation list", "val", nil, nil, true)
  add_str(opt, "Test list", "test", nil, nil, true)
  add_num(opt, "Gaussian noise variance", "var", nil, 0.01, true)
  add_void(opt, "Multi label classifier", "multi", "m")
  add_num(opt, "Shuffle seed", "sseed", nil, 1234, true)
  add_num(opt, "Perturbation seed", "pseed", nil, 5678, true)
  add_num(opt, "Context size", "context", "c", 0, true)
end

function cmd.add_bootstrap(opt)
  assert(opt, "Needs a cmdOpt object")
  add_str(opt, "Bunch size", "bsize", nil, 512, true)
  add_str(opt, "Model", "model", "m", nil, true)
  add_str(opt, "Data list", "list", "l", nil, true)
  add_str(opt, "Output info list", "info", "i", nil, true)
  add_num(opt, "Context size", "context", "c", 0, true)
  add_num(opt, "Sampling frequency", "hz", "s", 44100, true)
  add_num(opt, "Window size in ms", "wsize", nil, 23.2, true)
  add_num(opt, "Window advance in ms", "wadvance", nil, 11.6, true)
end

function cmd.add_mlp(opt, MAX_LAYERS)
  assert(opt, "Needs a cmdOpt object")
  add_str(opt, "Activation function", "actf", "a", "tanh", true,
          function(value)
            assert(ann.components.actf[value], "Incorrect actf name")
  end)
  for i=1,MAX_LAYERS do
    add_num(opt, "Hidden layer size", "h%d"%{i}, nil, 0, true)
  end
  add_num(opt, "Dropout probability", "dropout", nil, 0.0, true)
  add_num(opt, "Dropout mask", "dropout_mask", nil, 0.0, true)
  add_num(opt, "Dropout seed", "dseed", nil, 7654, true)
end

function cmd.add_trainer(opt)
  assert(opt)
  add_num(opt, "Bunch size", "bsize", "b", 32, true)
  add_num(opt, "Min epochs", "min", nil, 200, true)
  add_num(opt, "Max epochs", "max", nil, 4000, true)
end

function cmd.add_optimizer(opt)
  assert(opt)
  local global_hyps    = {}
  local layerwise_hyps = {}
  add_str(opt, "Optimizer algorithm", "optimizer", "o", "sgd",
          function(value)
            assert(ann.optimizer[value], "Incorrect optimizer name")
  end)
  add_str(opt, "Add global hyper-parameter option => option:value", "hyp",
          nil, nil, false,
          function(value)
            local k,v = value:match("([^:]+):([^:]+)")
            assert(k and v, "Incorrect hyper-parameter option")
            local v = assert(tonumber(v),
                             "Incorrect layerwise hyper-parameter option")
            global_hyps[k] = v
  end)
  add_str(opt, "Add layerwise hyper-parameter option => layer:option:value", "lhyp",
          nil, nil, false,
          function(value)
            local l,k,v = value:match("([^:]+):([^:]+):([^:]+)")
            assert(l and k and v, "Incorrect layerwise hyper-parameter option")
            local v = assert(tonumber(v),
                             "Incorrect layerwise hyper-parameter option")
            layerwise_hyps[l] = { k, v }
  end)
  return global_hyps, layerwise_hyps
end

function cmd.add_save(opt)
  add_str(opt, "Destination model filename", "dest", "d")
end

function cmd.parse(opt, arg)
  return opt:parse_args(arg, "defopt")
end

return cmd
