#!/usr/bin/env python

# we're using python 3.x style print but want it to work in python 2.x,
from __future__ import print_function
import os
import argparse
import shlex
import sys
import warnings
import copy
import imp
import ast

nodes = imp.load_source('', 'steps/nnet3/components.py')
nnet3_train_lib = imp.load_source('ntl', 'steps/nnet3/nnet3_train_lib.py')
chain_lib = imp.load_source('ncl', 'steps/nnet3/chain/nnet3_chain_lib.py')

def GetArgs():
    # we add compulsary arguments as named arguments for readability
    parser = argparse.ArgumentParser(description="Writes config files and variables "
                                                 "for TDNNs creation and training",
                                     epilog="See steps/nnet3/tdnn/train.sh for example.")

    # Only one of these arguments can be specified, and one of them has to
    # be compulsarily specified
    feat_group = parser.add_mutually_exclusive_group(required = True)
    feat_group.add_argument("--feat-dim", type=int,
                            help="Raw feature dimension, e.g. 13")
    feat_group.add_argument("--feat-dir", type=str,
                            help="Feature directory, from which we derive the feat-dim")

    # only one of these arguments can be specified
    ivector_group = parser.add_mutually_exclusive_group(required = False)
    ivector_group.add_argument("--ivector-dim", type=int,
                                help="iVector dimension, e.g. 100", default=0)
    ivector_group.add_argument("--ivector-dir", type=str,
                                help="iVector dir, which will be used to derive the ivector-dim  ", default=None)

    num_target_group = parser.add_mutually_exclusive_group(required = True)
    num_target_group.add_argument("--num-targets", type=int,
                                  help="number of network targets (e.g. num-pdf-ids/num-leaves)")
    num_target_group.add_argument("--ali-dir", type=str,
                                  help="alignment directory, from which we derive the num-targets")
    num_target_group.add_argument("--tree-dir", type=str,
                                  help="directory with final.mdl, from which we derive the num-targets")


    # MRTDNN options
    parser.add_argument("--ratewise-params", type=str, default=None,
                        help="the parameters for CWRNN units operating at different rates of operation in each clockwork-RNN")
    parser.add_argument("--operating-time-period", type=int,
                        help="The distance between time steps used at CWRNN input", default=1)
    parser.add_argument("--slow-rate-optional", type=str, action=nnet3_train_lib.StrToBoolAction,
                        help="if true, then the slower rate outputs are added only when available",
                        default=False, choices = ["false", "true"])


    # General neural network options
    parser.add_argument("--splice-indexes", type=str, required = True,
                        help="Splice indexes at each layer, e.g. '-3,-2,-1,0,1,2,3' "
                        "If CNN layers are used the first set of splice indexes will be used as input "
                        "to the first CNN layer and later splice indexes will be interpreted as indexes "
                        "for the TDNNs.")

    parser.add_argument("--include-log-softmax", type=str, action=nnet3_train_lib.StrToBoolAction,
                        help="add the final softmax layer ", default=True, choices = ["false", "true"])
    parser.add_argument("--add-final-sigmoid", type=str, action=nnet3_train_lib.StrToBoolAction,
                        help="add a final sigmoid layer as alternate to log-softmax-layer. "
                        "Can only be used if include-log-softmax is false. "
                        "This is useful in cases where you want the output to be "
                        "like probabilities between 0 and 1. Typically the nnet "
                        "is trained with an objective such as quadratic",
                        default=False, choices = ["false", "true"])

    parser.add_argument("--objective-type", type=str,
                        help = "the type of objective; i.e. quadratic or linear",
                        default="linear", choices = ["linear", "quadratic"])
    parser.add_argument("--xent-regularize", type=float,
                        help="For chain models, if nonzero, add a separate output for cross-entropy "
                        "regularization (with learning-rate-factor equal to the inverse of this)",
                        default=0.0)
    parser.add_argument("--xent-separate-forward-affine", type=str, action=nnet3_train_lib.StrToBoolAction,
                        help="if using --xent-regularize, gives it separate last-but-one weight matrix",
                        default=False, choices = ["false", "true"])
    parser.add_argument("--final-layer-normalize-target", type=float,
                        help="RMS target for final layer (set to <1 if final layer learns too fast",
                        default=1.0)
    parser.add_argument("--pnorm-input-dim", type=int,
                        help="input dimension to p-norm nonlinearities")
    parser.add_argument("--pnorm-output-dim", type=int,
                        help="output dimension of p-norm nonlinearities")
    parser.add_argument("--relu-dim", type=int,
                        help="dimension of ReLU nonlinearities")

    parser.add_argument("--self-repair-scale-nonlinearity", type=float,
                        help="A non-zero value activates the self-repair mechanism in the sigmoid and tanh non-linearities of the LSTM", default=None)

    parser.add_argument("--use-presoftmax-prior-scale", type=str, action=nnet3_train_lib.StrToBoolAction,
                        help="if true, a presoftmax-prior-scale is added",
                        choices=['true', 'false'], default = True)
    parser.add_argument("config_dir",
                        help="Directory to write config files and variables")

    # tuning params : should be deleted later
    parser.add_argument("--add-pda-type", type=int, default = 1)

    print(' '.join(sys.argv))

    args = parser.parse_args()
    args = CheckArgs(args)

    return args

def CheckArgs(args):
    if not os.path.exists(args.config_dir):
        os.makedirs(args.config_dir)

    ## Check arguments.
    if args.feat_dir is not None:
        args.feat_dim = nnet3_train_lib.GetFeatDim(args.feat_dir)

    if args.ali_dir is not None:
        args.num_targets = nnet3_train_lib.GetNumberOfLeaves(args.ali_dir)
    elif args.tree_dir is not None:
        args.num_targets = chain_lib.GetNumberOfLeaves(args.tree_dir)

    if args.ivector_dir is not None:
        args.ivector_dim = nnet3_train_lib.GetIvectorDim(args.ivector_dir)

    if not args.feat_dim > 0:
        raise Exception("feat-dim has to be postive")

    if not args.num_targets > 0:
        print(args.num_targets)
        raise Exception("num_targets has to be positive")

    if not args.ivector_dim >= 0:
        raise Exception("ivector-dim has to be non-negative")

    if not args.relu_dim is None:
        if not args.pnorm_input_dim is None or not args.pnorm_output_dim is None:
            raise Exception("--relu-dim argument not compatible with "
                            "--pnorm-input-dim or --pnorm-output-dim options");
        args.nonlin_input_dim = args.relu_dim
        args.nonlin_output_dim = args.relu_dim
        args.nonlin_type = 'relu'
    else:
        if not args.pnorm_input_dim > 0 or not args.pnorm_output_dim > 0:
            raise Exception("--relu-dim not set, so expected --pnorm-input-dim and "
                            "--pnorm-output-dim to be provided.");
        args.nonlin_input_dim = args.pnorm_input_dim
        args.nonlin_output_dim = args.pnorm_output_dim
        if (args.nonlin_input_dim < args.nonlin_output_dim) or (args.nonlin_input_dim % args.nonlin_output_dim != 0):
            raise Exception("Invalid --pnorm-input-dim {0} and --pnorm-output-dim {1}".format(args.nonlin_input_dim, args.nonlin_output_dim))
        args.nonlin_type = 'pnorm'

    if args.add_final_sigmoid and args.include_log_softmax:
        raise Exception("--include-log-softmax and --add-final-sigmoid cannot both be true.")

    if args.xent_separate_forward_affine and args.add_final_sigmoid:
        raise Exception("It does not make sense to have --add-final-sigmoid=true when xent-separate-forward-affine is true")

    if args.ratewise_params is None:
        args.ratewise_params = {'T1': {'rate':1},
                                'T2': {'rate':1.0/2},
                                'T3': {'rate':1.0/4},
                                'T4': {'rate':1.0/8}}
    else:
        args.ratewise_params = eval(args.ratewise_params)
        assert(CheckRatewiseParams(args.ratewise_params))
    if (args.operating_time_period <= 0):
        raise Exception("--operating-time-period should be greater than 0")

    for key in args.ratewise_params.keys():
        if args.ratewise_params[key]['rate'] > 1 :
            raise Exception("Rates cannot be greater than 1")

    return args

def CheckRatewiseParams(ratewise_params):
    #TODO : write this
    return True

def PrintConfig(file_name, config_lines):
    f = open(file_name, 'w')
    f.write("\n".join(config_lines['components'])+"\n")
    f.write("\n#Component nodes\n")
    f.write("\n".join(config_lines['component-nodes']))
    f.close()

def ParseSpliceString(splice_indexes):
    splice_array = []
    left_context = 0
    right_context = 0
    split1 = splice_indexes.split();  # we already checked the string is nonempty.
    if len(split1) < 1:
        raise Exception("invalid splice-indexes argument, too short: "
                 + splice_indexes)
    try:
        for string in split1:
            split2 = string.split(",")
            if len(split2) < 1:
                raise Exception("invalid splice-indexes argument, too-short element: "
                         + splice_indexes)
            int_list = []
            for int_str in split2:
                int_list.append(int(int_str))
            if not int_list == sorted(int_list):
                raise Exception("elements of splice-indexes must be sorted: "
                         + splice_indexes)
            left_context += -int_list[0]
            right_context += int_list[-1]
            splice_array.append(int_list)
    except ValueError as e:
        raise Exception("invalid splice-indexes argument " + splice_indexes + str(e))
    left_context = max(0, left_context)
    right_context = max(0, right_context)

    return {'left_context':left_context,
            'right_context':right_context,
            'splice_indexes':splice_array,
            'num_hidden_layers':len(splice_array)
            }

# The function signature of MakeConfigs is changed frequently as it is intended for local use in this script.
def MakeConfigs(config_dir, splice_indexes_string,
                feat_dim, ivector_dim, num_targets,
                rate_params, operating_time_period, slow_rate_optional,
                nonlin_type, nonlin_input_dim, nonlin_output_dim,
                use_presoftmax_prior_scale,
                final_layer_normalize_target,
                include_log_softmax,
                add_final_sigmoid,
                xent_regularize,
                xent_separate_forward_affine,
                self_repair_scale,
                objective_type,
                add_pda_type):

    parsed_splice_output = ParseSpliceString(splice_indexes_string.strip())
    left_context = parsed_splice_output['left_context']
    right_context = parsed_splice_output['right_context']
    num_hidden_layers = parsed_splice_output['num_hidden_layers']
    splice_indexes = parsed_splice_output['splice_indexes']
    input_dim = len(parsed_splice_output['splice_indexes'][0]) + feat_dim + ivector_dim

    num_learnable_params = 0
    num_learnable_params_xent = 0

    if xent_separate_forward_affine:
        if splice_indexes[-1] != [0]:
            raise Exception("--xent-separate-forward-affine option is supported"
                            " only if the last-hidden layer has no splicing before it."
                            " Please use a splice-indexes with just 0 as the final splicing config.")

    prior_scale_file = '{0}/presoftmax_prior_scale.vec'.format(config_dir)

    config_lines = {'components':[], 'component-nodes':[]}

    config_files={}
    prev_layer = nodes.AddInputLayer(config_lines, feat_dim, splice_indexes[0], ivector_dim)
    prev_layer_output = prev_layer['output']
    num_learnable_params += prev_layer['num_learnable_params']

    # Add the init config lines for estimating the preconditioning matrices
    init_config_lines = copy.deepcopy(config_lines)
    init_config_lines['components'].insert(0, '# Config file for initializing neural network prior to')
    init_config_lines['components'].insert(0, '# preconditioning matrix computation')
    nodes.AddOutputLayer(init_config_lines, prev_layer_output)
    config_files[config_dir + '/init.config'] = init_config_lines

    prev_layer = nodes.AddLdaLayer(config_lines, "L0", prev_layer_output, config_dir + '/lda.mat')
    prev_layer_output = prev_layer['output']

    # we moved the first splice layer to before the LDA..
    # so the input to the first affine layer is going to [0] index
    splice_indexes[0] = [0]

    for i in range(0, num_hidden_layers):
        if xent_separate_forward_affine and i == num_hidden_layers - 1:
            # xent_separate_forward_affine is only honored only when adding the final hidden layer
            # this is the final layer so assert that splice index is [0]
            assert(len(splice_indexes[i]) == 1 and splice_indexes[i][0] == 0)
            if xent_regularize == 0.0:
                raise Exception("xent-separate-forward-affine=True is valid only if xent-regularize is non-zero")

            # we use named arguments as we do not want argument offset errors
            num_learnable_params_final, num_learnable_params_final_xent = nodes.AddFinalLayersWithXentSeperateForwardAffineRegularizer(config_lines,
                                                                                                                     input = prev_layer_output,
                                                                                                                     num_targets = num_targets,
                                                                                                                     nonlin_type = nonlin_type,
                                                                                                                     nonlin_input_dim = nonlin_input_dim,
                                                                                                                     nonlin_output_dim = nonlin_output_dim,
                                                                                                                     use_presoftmax_prior_scale = use_presoftmax_prior_scale,
                                                                                                                     prior_scale_file = prior_scale_file,
                                                                                                                     include_log_softmax = include_log_softmax,
                                                                                                                     self_repair_scale = self_repair_scale,
                                                                                                                     xent_regularize = xent_regularize,
                                                                                                                     final_layer_normalize_target = final_layer_normalize_target)

        else:
            # make the intermediate config file for layerwise discriminative training
            if (len(splice_indexes[i]) == 1) and (splice_indexes[i][0] == 0):
                # add a normal affine layer
                prev_layer = nodes.AddAffineNonlinLayer(config_lines, 'Affine_{0}'.format(i),
                                                  prev_layer_output,
                                                  nonlin_type, nonlin_input_dim, nonlin_output_dim,
                                                  self_repair_scale = self_repair_scale,
                                                  norm_target_rms = 1.0 if i < num_hidden_layers -1 else final_layer_normalize_target)
            else :
                # penultimate layer can't be mrtdnn
                # this is not necessarily a major constraint
                assert(i < num_hidden_layers - 1)
                # add a mrtdnn layer
                if add_pda_type == 1:
                    prev_layer = nodes.AddMultiRateTdnnLayer(config_lines, 'Mrtdnn_{0}'.format(i),
                                                        prev_layer_output,
                                                        rate_params = rate_params,
                                                        splice_indexes = splice_indexes[i],
                                                        nonlin_type = nonlin_type,
                                                        nonlin_input_dim = nonlin_input_dim,
                                                        nonlin_output_dim = nonlin_output_dim,
                                                        operating_time_period = operating_time_period,
                                                        slow_rate_optional = slow_rate_optional,
                                                        self_repair_scale = self_repair_scale,
                                                        norm_target_rms = 1.0)
                elif add_pda_type == 2:
                    prev_layer = nodes.AddMultiRateTdnnLayer2(config_lines, 'Mrtdnn_{0}'.format(i),
                                                        prev_layer_output,
                                                        rate_params = rate_params,
                                                        splice_indexes = splice_indexes[i],
                                                        nonlin_type = nonlin_type,
                                                        nonlin_input_dim = nonlin_input_dim,
                                                        nonlin_output_dim = nonlin_output_dim,
                                                        operating_time_period = operating_time_period,
                                                        slow_rate_optional = slow_rate_optional,
                                                        self_repair_scale = self_repair_scale,
                                                        norm_target_rms = 1.0)

                left_context += prev_layer['left_context']
                right_context += prev_layer['right_context']

            prev_layer_output = prev_layer['output']
            num_learnable_params += prev_layer['num_learnable_params']




            # a final layer is added after each new layer as we are generating
            # configs for layer-wise discriminative training
            num_learnable_params_final, num_learnable_params_final_xent = nodes.AddFinalLayerWithXentRegularizer(config_lines,
                                                                                                         input = prev_layer_output,
                                                                                                         num_targets = num_targets,
                                                                                                         nonlin_type = nonlin_type,
                                                                                                         nonlin_input_dim = nonlin_input_dim,
                                                                                                         nonlin_output_dim = nonlin_output_dim,
                                                                                                         use_presoftmax_prior_scale = use_presoftmax_prior_scale,
                                                                                                         prior_scale_file = prior_scale_file,
                                                                                                         include_log_softmax = include_log_softmax,
                                                                                                         self_repair_scale = self_repair_scale,
                                                                                                         xent_regularize = xent_regularize,
                                                                                                         add_final_sigmoid = add_final_sigmoid,
                                                                                                         objective_type = objective_type)


        config_files['{0}/layer{1}.config'.format(config_dir, i+1)] = config_lines
        config_lines = {'components':[], 'component-nodes':[]}


    # now add the parameters from the final layer
    num_learnable_params += num_learnable_params_final
    num_learnable_params_xent += num_learnable_params_final_xent

    # write the files used by other scripts like steps/nnet3/get_egs.sh
    f = open(config_dir + "/vars", "w")
    print('model_left_context=' + str(int(left_context)), file=f)
    print('model_right_context=' + str(int(right_context)), file=f)
    print('num_hidden_layers=' + str(num_hidden_layers), file=f)
    print('num_targets=' + str(num_targets), file=f)
    print('add_lda=true', file=f)
    print('include_log_softmax=' + ('true' if include_log_softmax else 'false'), file=f)
    print('objective_type=' + objective_type, file=f)
    print('num_learable_params=' + str(num_learnable_params), file=f)
    print('num_learable_params_xent=' + str(num_learnable_params_xent), file=f)

    f.close()

    print('This model has num_learnable_params={0:,} and num_learnable_params_xent={1:,}'.format(num_learnable_params, num_learnable_params_xent))

    # printing out the configs
    # init.config used to train lda-mllt train
    for key in config_files.keys():
        PrintConfig(key, config_files[key])

def Main():
    args = GetArgs()

    MakeConfigs(config_dir = args.config_dir,
                splice_indexes_string = args.splice_indexes,
                feat_dim = args.feat_dim, ivector_dim = args.ivector_dim,
                num_targets = args.num_targets,
                rate_params = args.ratewise_params,
                slow_rate_optional = args.slow_rate_optional,
                operating_time_period = args.operating_time_period,
                nonlin_type = args.nonlin_type,
                nonlin_input_dim = args.nonlin_input_dim,
                nonlin_output_dim = args.nonlin_output_dim,
                use_presoftmax_prior_scale = args.use_presoftmax_prior_scale,
                final_layer_normalize_target = args.final_layer_normalize_target,
                include_log_softmax = args.include_log_softmax,
                add_final_sigmoid = args.add_final_sigmoid,
                xent_regularize = args.xent_regularize,
                xent_separate_forward_affine = args.xent_separate_forward_affine,
                self_repair_scale = args.self_repair_scale_nonlinearity,
                objective_type = args.objective_type,
                add_pda_type = args.add_pda_type)

if __name__ == "__main__":
    Main()

