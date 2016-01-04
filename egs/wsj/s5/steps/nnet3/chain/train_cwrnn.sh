#!/bin/bash


# Copyright 2012-2015  Johns Hopkins University (Author: Daniel Povey).
#           2013  Xiaohui Zhang
#           2013  Guoguo Chen
#           2014  Vimal Manohar
#           2014-2015  Vijayaditya Peddinti
# Apache 2.0.

# Terminology:
# sample - one input-output tuple, which is an input sequence and output sequence for RNN
# frame  - one output label and the input context used to compute it

# Begin configuration section.
cmd=run.pl
num_epochs=10      # Number of epochs of training;
                   # the number of iterations is worked out from this.
                   # Be careful with this: we actually go over the data
                   # num-epochs * frame-subsampling-factor times, due to
                   # using different data-shifts.
truncate_deriv_weights=0  # can be used to set to zero the weights of derivs from frames
                          # near the edges.  (counts subsampled frames).
apply_deriv_weights=true
initial_effective_lrate=0.0003
final_effective_lrate=0.00003
lm_opts=   # options to chain-est-phone-lm
frames_per_iter=800000  # each iteration of training, see this many [input]
                        # frames per job.  This option is passed to get_egs.sh.
                        # Aim for about a minute of training time
right_tolerance=10
denominator_scale=1.0 # relates to tombsone stuff.
num_jobs_initial=1 # Number of neural net jobs to run in parallel at the start of training
num_jobs_final=8   # Number of neural net jobs to run in parallel at the end of training
frame_subsampling_factor=3  # controls reduced frame-rate at the output.
get_egs_stage=0    # can be used for rerunning after partial
online_ivector_dir=
max_param_change=2.0
scale_max_param_change=false # if this option is used, scale it by num-jobs.
remove_egs=true  # set to false to disable removing egs after training is done.

max_models_combine=20 # The "max_models_combine" is the maximum number of models we give
  # to the final 'combine' stage, but these models will themselves be averages of
  # iteration-number ranges.
ngram_order=3

shuffle_buffer_size=5000 # This "buffer_size" variable controls randomization of the samples
                # on each iter.  You could set it to 0 or to a large value for complete
                # randomization, but this would both consume memory and cause spikes in
                # disk I/O.  Smaller is easier on disk and memory but less random.  It's
                # not a huge deal though, as samples are anyway randomized right at the start.
                # (the point of this is to get data in different minibatches on different iterations,
                # since in the preconditioning method, 2 samples in the same minibatch can
                # affect each others' gradients.
final_layer_normalize_target=1.0  # you can set this to less than one if you
                                  # think the final layer is learning too fast
                                  # compared with the other layers.
add_layers_period=2 # by default, add new layers every 2 iterations.
stage=-6
exit_stage=-100 # you can set this to terminate the training early.  Exits before running this stage

# count space-separated fields in splice_indexes to get num-hidden-layers.
splice_indexes="-2,-1,0,1,2 0 0"
ratewise_params=
# Format : layer<hidden_layer>/<frame_indices>....layer<hidden_layer>/<frame_indices> "
# note: hidden layers which are composed of one or more components,
# so hidden layer indexing is different from component count

# CWRNN parameters
input_type="smooth"
nonlinearity="SigmoidComponent"
diag_init_scaling_factor=0
num_cwrnn_layers=3
use_lstm=false
subsample=true
hidden_dim=1024  # the dimension of the fully connected hidden layer outputs
norm_based_clipping=true  # if true norm_based_clipping is used.
                          # In norm-based clipping the activation Jacobian matrix
                          # for the recurrent connections in the network is clipped
                          # to ensure that the individual row-norm (l2) does not increase
                          # beyond the clipping_threshold.
                          # If false, element-wise clipping is used.
clipping_threshold=30     # if norm_based_clipping is true this would be the maximum value of the row l2-norm,
                          # else this is the max-absolute value of each element in Jacobian.
chunk_left_context=40  # number of steps used in the estimation of LSTM state before prediction of the first label
label_delay=5  # the lstm output is used to predict the label with the specified delay
num_bptt_steps=    # this variable counts the number of time steps to back-propagate from the last label in the chunk
                   # it is usually same as chunk_width
projection_dim=0

# nnet3-train options
shrink=0.99  # this parameter would be used to scale the parameter matrices
shrink_threshold=0.15  # a value less than 0.25 that we compare the mean of
                       # 'deriv-avg' for sigmoid components with, and if it's
                       # less, we shrink.
epsilon=0.05    # regularization constant for perturbed training.
perturb_proportion=1.0 # proportion of examples on which we do perturbed training.
# for ReLU networks we use fix nnet in place of shrink
fix_nnet=false
min_average=0.05
max_average=0.95

max_param_change=1.0  # max param change per minibatch
num_chunk_per_minibatch=64  # number of sequences to be processed in parallel every mini-batch

momentum=0.5    # e.g. 0.5.  Note: we implemented it in such a way that
                # it doesn't increase the effective learning rate.
use_gpu=true    # if true, we run on GPU.
cleanup=true
egs_dir=
max_lda_jobs=20  # use no more than 20 jobs for the LDA accumulation.
lda_opts=
egs_opts=
transform_dir=     # If supplied, this dir used instead of alidir to find transforms.
cmvn_opts=  # will be passed to get_lda.sh and get_egs.sh, if supplied.
            # only relevant for "raw" features, not lda.
feat_type=raw  # or set to 'lda' to use LDA features.
chunk_width=25   # number of frames of output per chunk.  To be passed on to get_egs.sh.
left_deriv_truncate=   # number of time-steps to avoid using the deriv of, on the left.
right_deriv_truncate=  # number of time-steps to avoid using the deriv of, on the right.
rand_prune=4.0 # speeds up LDA.
ng_affine_options=
# End configuration section.

trap 'for pid in $(jobs -pr); do kill -KILL $pid; done' INT QUIT TERM

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 4 ]; then
  echo "Usage: $0 [opts] <data> <tree-dir> <phone-lattice-dir> <exp-dir>"
  echo " e.g.: $0 data/train exp/chain/tri3b_tree exp/tri3_latali exp/chain/tdnn_a"
  echo ""
  echo "Main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config file containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-epochs <#epochs|10>                        # Number of epochs of training"
  echo "  --initial-effective-lrate <lrate|0.0003>         # effective learning rate at start of training."
  echo "  --final-effective-lrate <lrate|0.00003>          # effective learning rate at end of training."
  echo "                                                   # data, 0.00025 for large data"
  echo "  --momentum <momentum|0.5>                        # Momentum constant: note, this is "
  echo "                                                   # implemented in such a way that it doesn't"
  echo "                                                   # increase the effective learning rate."
  echo "  --num-hidden-layers <#hidden-layers|2>           # Number of hidden layers, e.g. 2 for 3 hours of data, 4 for 100hrs"
  echo "  --num-jobs-initial <num-jobs|1>                  # Number of parallel jobs to use for neural net training, at the start."
  echo "  --num-jobs-final <num-jobs|8>                    # Number of parallel jobs to use for neural net training, at the end"
  echo "  --num-threads <num-threads|16>                   # Number of parallel threads per job, for CPU-based training (will affect"
  echo "                                                   # results as well as speed; may interact with batch size; if you increase"
  echo "                                                   # this, you may want to decrease the batch size."
  echo "  --parallel-opts <opts|\"-pe smp 16 -l ram_free=1G,mem_free=1G\">      # extra options to pass to e.g. queue.pl for processes that"
  echo "                                                   # use multiple threads... note, you might have to reduce mem_free,ram_free"
  echo "                                                   # versus your defaults, because it gets multiplied by the -pe smp argument."
  echo "  --num-chunks-per-minibatch <minibatch-size|100>  # Number of sequences to be processed in parallel in a minibatch"
  echo "  --samples-per-iter <#samples|20000>              # Number of egs in each archive of data.  This times --chunk-width is"
  echo "                                                   # the number of frames processed per iteration"
  echo "  --splice-indexes <string|\"-2,-1,0,1,2 0 0\"> "
  echo "                                                   # Frame indices used for each splice layer."
  echo "                                                   # Format : <frame_indices> .... <frame_indices> "
  echo "                                                   # (note: we splice processed, typically 40-dimensional frames"
  echo "  --lda-dim <dim|''>                               # Dimension to reduce spliced features to with LDA"

  echo " ################### LSTM options ###################### "
  echo "  --num-lstm-layers <int|3>                        # number of LSTM layers"
  echo "  --cell-dim   <int|1024>                          # dimension of the LSTM cell"
  echo "  --hidden-dim      <int|1024>                     # the dimension of the fully connected hidden layer outputs"
  echo "  --recurrent-projection-dim  <int|256>            # the output dimension of the recurrent-projection-matrix"
  echo "  --non-recurrent-projection-dim  <int|256>        # the output dimension of the non-recurrent-projection-matrix"
  echo "  --chunk-left-context <int|40>                    # number of time-steps used in the estimation of the first LSTM state"
  echo "  --chunk-width <int|20>                           # number of output labels in the sequence used to train an LSTM"
  echo "  --norm-based-clipping <bool|true>                # if true norm_based_clipping is used."
  echo "                                                   # In norm-based clipping the activation Jacobian matrix"
  echo "                                                   # for the recurrent connections in the network is clipped"
  echo "                                                   # to ensure that the individual row-norm (l2) does not increase"
  echo "                                                   # beyond the clipping_threshold."
  echo "                                                   # If false, element-wise clipping is used."
  echo "  --num-bptt-steps <int|20>                        # this variable counts the number of time steps to back-propagate from the last label in the chunk"
  echo "                                                   # it is usually same as chunk_width"
  echo "  --label-delay <int|5>                            # the lstm output is used to predict the label with the specified delay"
  echo "  --clipping-threshold <int|30>                    # if norm_based_clipping is true this would be the maximum value of the row l2-norm,"
  echo "                                                   # else this is the max-absolute value of each element in Jacobian."
  echo "  --stage <stage|-4>                               # Used to run a partially-completed training process from somewhere in"
  echo "                                                   # the middle."



  exit 1;
fi

data=$1
treedir=$2
latdir=$3
dir=$4


# Check some files.
for f in $data/feats.scp $treedir/ali.1.gz $treedir/final.mdl $treedir/tree \
    $latdir/lat.1.gz $latdir/final.mdl $latdir/num_jobs $latdir/splice_opts; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

# Set some variables.
nj=`cat $treedir/num_jobs` || exit 1;  # number of jobs in alignment dir...

sdata=$data/split$nj
utils/split_data.sh $data $nj

mkdir -p $dir/log
echo $nj > $dir/num_jobs
cp $treedir/tree $dir


# First work out the feature and iVector dimension, needed for tdnn config creation.
case $feat_type in
  raw) feat_dim=$(feat-to-dim --print-args=false scp:$data/feats.scp -) || \
      { echo "$0: Error getting feature dim"; exit 1; }
    ;;
  lda)  [ ! -f $alidir/final.mat ] && echo "$0: With --feat-type lda option, expect $alidir/final.mat to exist."
   # get num-rows in lda matrix, which is the lda feature dim.
   feat_dim=$(matrix-dim --print-args=false $alidir/final.mat | cut -f 1)
    ;;
  *)
   echo "$0: Bad --feat-type '$feat_type';"; exit 1;
esac
if [ -z "$online_ivector_dir" ]; then
  ivector_dim=0
else
  ivector_dim=$(feat-to-dim scp:$online_ivector_dir/ivector_online.scp -) || exit 1;
fi

if  [ $stage -le -7 ]; then
  echo "$0: creating phone language-model"

  $cmd $dir/log/make_phone_lm.log \
    chain-est-phone-lm $lm_opts \
     "ark:gunzip -c $treedir/ali.*.gz | ali-to-phones $treedir/final.mdl ark:- ark:- |" \
     $dir/phone_lm.fst || exit 1
fi

if [ $stage -le -6 ]; then
  echo "$0: creating denominator FST"
  copy-transition-model $treedir/final.mdl $dir/0.trans_mdl
  $cmd $dir/log/make_den_fst.log \
    chain-make-den-fst $dir/tree $dir/0.trans_mdl $dir/phone_lm.fst \
       $dir/den.fst $dir/normalization.fst || exit 1;
fi

# work out num-leaves
num_leaves=$(am-info $dir/0.trans_mdl | grep -w pdfs | awk '{print $NF}') || exit 1;
[ $num_leaves -gt 0 ] || exit 1;

if [ $stage -le -5 ]; then
  echo "$0: creating neural net configs";

  # create the config files for nnet initialization
  # note an additional space is added to splice_indexes to
  # avoid issues with the python ArgParser which can have
  # issues with negative arguments (due to minus sign)
  config_extra_opts=()
  [ ! -z "$ratewise_params" ] && config_extra_opts+=(--ratewise-params "$ratewise_params")
  [ ! -z "$ng_affine_opts" ] && config_extra_opts+=( "$ng_affine_opts" )

  steps/nnet3/cwrnn/make_configs.py  "${config_extra_opts[@]}" \
    --splice-indexes "$splice_indexes " \
    --num-cwrnn-layers $num_cwrnn_layers \
    --feat-dim $feat_dim \
    --ivector-dim $ivector_dim \
    --hidden-dim $hidden_dim \
    --nonlinearity $nonlinearity \
    --projection-dim $projection_dim \
    --subsample "$subsample" \
    --input-type "$input_type" \
    --diag-init-scaling-factor $diag_init_scaling_factor \
    --use-lstm "$use_lstm" \
    --norm-based-clipping $norm_based_clipping \
    --clipping-threshold $clipping_threshold \
    --num-targets $num_leaves \
    --label-delay $label_delay \
   $dir/configs || exit 1;
  # Initialize as "raw" nnet, prior to training the LDA-like preconditioning
  # matrix.  This first config just does any initial splicing that we do;
  # we do this as it's a convenient way to get the stats for the 'lda-like'
  # transform.
  $cmd $dir/log/nnet_init.log \
    nnet3-init --srand=-2 $dir/configs/init.config $dir/init.raw || exit 1;
fi
# sourcing the "vars" below sets
# model_left_context=(something)
# model_right_context=(something)
# num_hidden_layers=(something)
. $dir/configs/vars || exit 1;
left_context=$((chunk_left_context + model_left_context))
right_context=$model_right_context
context_opts="--left-context=$left_context --right-context=$right_context"

! [ "$num_hidden_layers" -gt 0 ] && echo \
 "$0: Expected num_hidden_layers to be defined" && exit 1;

[ -z "$transform_dir" ] && transform_dir=$latdir

if [ $stage -le -4 ] && [ -z "$egs_dir" ]; then
  extra_opts=()
  [ ! -z "$cmvn_opts" ] && extra_opts+=(--cmvn-opts "$cmvn_opts")
  [ ! -z "$feat_type" ] && extra_opts+=(--feat-type $feat_type)
  [ ! -z "$online_ivector_dir" ] && extra_opts+=(--online-ivector-dir $online_ivector_dir)
  extra_opts+=(--transform-dir $transform_dir)
  # we need a bit of extra left-context and right-context to allow for frame
  # shifts (we use shifted version of the data for more variety).
  extra_opts+=(--left-context $[$left_context+$frame_subsampling_factor/2])
  extra_opts+=(--right-context $[$right_context+$frame_subsampling_factor/2])
  extra_opts+=(--valid-left-context $(( chunk_width + left_context)))
  extra_opts+=(--valid-right-context $((chunk_width + right_context)))

  # Note: in RNNs we process sequences of labels rather than single label per sample
  echo "$0: calling get_egs.sh"
  steps/nnet3/chain/get_egs.sh $egs_opts "${extra_opts[@]}" \
      --frames-per-iter $frames_per_iter --stage $get_egs_stage \
      --cmd "$cmd" \
      --frames-per-eg $chunk_width \
      --frame-subsampling-factor $frame_subsampling_factor \
      $data $dir $latdir $dir/egs || exit 1;
fi

[ -z $egs_dir ] && egs_dir=$dir/egs

if [ "$feat_dim" != "$(cat $egs_dir/info/feat_dim)" ]; then
  echo "$0: feature dimension mismatch with egs in $egs_dir: $feat_dim vs $(cat $egs_dir/info/feat_dim)";
  exit 1;
fi
if [ "$ivector_dim" != "$(cat $egs_dir/info/ivector_dim)" ]; then
  echo "$0: ivector dimension mismatch with egs in $egs_dir: $ivector_dim vs $(cat $egs_dir/info/ivector_dim)";
  exit 1;
fi

# copy any of the following that exist, to $dir.
cp $egs_dir/{cmvn_opts,splice_opts,final.mat} $dir 2>/dev/null

# confirm that the egs_dir has the necessary context (especially important if
# the --egs-dir option was used on the command line).
egs_left_context=$(cat $egs_dir/info/left_context) || exit -1
egs_right_context=$(cat $egs_dir/info/right_context) || exit -1
 ( [ $egs_left_context -lt $left_context ] || \
   [ $egs_right_context -lt $right_context ] ) && \
   echo "$0: egs in $egs_dir have too little context" && exit -1;

chunk_width=$(cat $egs_dir/info/frames_per_eg) || { echo "error: no such file $egs_dir/info/frames_per_eg"; exit 1; }
num_archives=$(cat $egs_dir/info/num_archives) || { echo "error: no such file $egs_dir/info/frames_per_eg"; exit 1; }

num_archives_expanded=$[$num_archives*$frame_subsampling_factor]


[ $num_jobs_initial -gt $num_jobs_final ] && \
  echo "$0: --initial-num-jobs cannot exceed --final-num-jobs" && exit 1;

[ $num_jobs_final -gt $num_archives_expanded ] && \
  echo "$0: --final-num-jobs cannot exceed #archives $num_archives_expanded." && exit 1;

if [ $stage -le -3 ]; then
  echo "$0: getting preconditioning matrix for input features."
  num_lda_jobs=$num_archives
  [ $num_lda_jobs -gt $max_lda_jobs ] && num_lda_jobs=$max_lda_jobs

  # Write stats with the same format as stats for LDA.
  $cmd JOB=1:$num_lda_jobs $dir/log/get_lda_stats.JOB.log \
      nnet3-chain-acc-lda-stats --rand-prune=$rand_prune \
         $dir/init.raw "ark:$egs_dir/cegs.JOB.ark" $dir/JOB.lda_stats || exit 1;

  all_lda_accs=$(for n in $(seq $num_lda_jobs); do echo $dir/$n.lda_stats; done)
  $cmd $dir/log/sum_transform_stats.log \
    sum-lda-accs $dir/lda_stats $all_lda_accs || exit 1;

  rm $all_lda_accs || exit 1;

  # this computes a fixed affine transform computed in the way we described in
  # Appendix C.6 of http://arxiv.org/pdf/1410.7455v6.pdf; it's a scaled variant
  # of an LDA transform but without dimensionality reduction.
  $cmd $dir/log/get_transform.log \
     nnet-get-feature-transform $lda_opts $dir/lda.mat $dir/lda_stats || exit 1;

  ln -sf ../lda.mat $dir/configs/lda.mat
fi

if [ $stage -le -1 ]; then
  # Add the first layer; this will add in the lda.mat and
  # presoftmax_prior_scale.vec.

  echo "$0: creating initial raw model"
  $cmd $dir/log/add_first_layer.log \
       nnet3-init --srand=-1 $dir/init.raw $dir/configs/layer1.config $dir/0.raw || exit 1;

  # The model-format for a 'chain' acoustic model is just the transition
  # model and then the raw nnet, so we can use 'cat' to create this, as
  # long as they have the same mode (binary or not binary).
  # We ensure that they have the same mode (even if someone changed the
  # script to make one or both of them text mode) by copying them both
  # before concatenating them.

  echo "$0: creating initial model"
  $cmd $dir/log/init_model.log \
    nnet3-am-init $dir/0.trans_mdl $dir/0.raw $dir/0.mdl || exit 1;

fi

echo $frame_subsampling_factor >$dir/frame_subsampling_factor || exit 1;

# set num_iters so that as close as possible, we process the data $num_epochs
# times, i.e. $num_iters*$avg_num_jobs) == $num_epochs*$num_archives_expanded
# where avg_num_jobs=(num_jobs_initial+num_jobs_final)/2.

num_archives_to_process=$[$num_epochs*$num_archives_expanded]
num_archives_processed=0
num_iters=$[($num_archives_to_process*2)/($num_jobs_initial+$num_jobs_final)]

! [ $num_iters -gt $[$finish_add_layers_iter+2] ] \
  && echo "$0: Insufficient epochs" && exit 1

finish_add_layers_iter=$[$num_hidden_layers * $add_layers_period]

echo "$0: Will train for $num_epochs epochs = $num_iters iterations"

if $use_gpu; then
  parallel_suffix=""
  train_queue_opt="--gpu 1"
  combine_queue_opt="--gpu 1"
  prior_gpu_opt="--use-gpu=yes"
  prior_queue_opt="--gpu 1"
  parallel_train_opts=
  if ! cuda-compiled; then
    echo "$0: WARNING: you are running with one thread but you have not compiled"
    echo "   for CUDA.  You may be running a setup optimized for GPUs.  If you have"
    echo "   GPUs and have nvcc installed, go to src/ and do ./configure; make"
    exit 1
  fi
else
  echo "$0: without using a GPU this will be very slow.  nnet3 does not yet support multiple threads."
  parallel_train_opts="--use-gpu=no"
  train_queue_opt="--num-threads $num_threads"
  combine_queue_opt=""  # the combine stage will be quite slow if not using
                        # GPU, as we didn't enable that program to use
                        # multiple threads.
  prior_gpu_opt="--use-gpu=no"
  prior_queue_opt=""
fi


if [ "$nonlinearity" == "RectifiedLinearComponent" ] && [ $fix_nnet ]; then
  fix_nnet=true;
else
  fix_nnet=false;
fi

approx_iters_per_epoch_final=$[$num_archives_expanded/$num_jobs_final]
# First work out how many iterations we want to combine over in the final
# nnet3-combine-fast invocation.  (We may end up subsampling from these if the
# number exceeds max_model_combine).  The number we use is:
# min(max(max_models_combine, approx_iters_per_epoch_final),
#     1/2 * iters_after_last_layer_added)
num_iters_combine=$max_models_combine
if [ $num_iters_combine -lt $approx_iters_per_epoch_final ]; then
   num_iters_combine=$approx_iters_per_epoch_final
fi
half_iters_after_add_layers=$[($num_iters-$finish_add_layers_iter)/2]
if [ $num_iters_combine -gt $half_iters_after_add_layers ]; then
  num_iters_combine=$half_iters_after_add_layers
fi
first_model_combine=$[$num_iters-$num_iters_combine+1]

x=0

deriv_time_opts=
[ ! -z "$left_deriv_truncate" ] && deriv_time_opts="--optimization.min-deriv-time=$left_deriv_truncate"
[ ! -z "$right_deriv_truncate" ] && \
  deriv_time_opts="$deriv_time_opts --optimization.max-deriv-time=$((chunk_width - right_deriv_truncate))"


[ -z $num_bptt_steps ] && num_bptt_steps=$chunk_width;
min_deriv_time=$((chunk_width - num_bptt_steps))
while [ $x -lt $num_iters ]; do
  [ $x -eq $exit_stage ] && echo "$0: Exiting early due to --exit-stage $exit_stage" && exit 0;

  this_num_jobs=$(perl -e "print int(0.5+$num_jobs_initial+($num_jobs_final-$num_jobs_initial)*$x/$num_iters);")

  ilr=$initial_effective_lrate; flr=$final_effective_lrate; np=$num_archives_processed; nt=$num_archives_to_process;
  this_effective_learning_rate=$(perl -e "print ($x + 1 >= $num_iters ? $flr : $ilr*exp($np*log($flr/$ilr)/$nt));");
  this_learning_rate=$(perl -e "print ($this_effective_learning_rate*$this_num_jobs);");


  if [ $x -ge 0 ] && [ $stage -le $x ]; then
    if [ "$nonlinearity" == "RectifiedLinearComponent+NormalizeComponent" ]; then
      # we might want to do something like nnet-am-fix here.
      this_shrink=1.0
    else
      # Set this_shrink value.
      if [ $x -eq 0 ] || nnet3-am-info --print-args=false $dir/$x.mdl | \
        perl -e "while(<>){ if (m/type=$nonlinearity.+deriv-avg=.+mean=(\S+)/) { \$n++; \$tot+=\$1; } } exit(\$tot/\$n > $shrink_threshold);"; then
        this_shrink=$shrink; # e.g. avg-deriv of sigmoids was <= 0.125, so shrink.
      else
        this_shrink=1.0  # don't shrink: nonlinearities are not over-saturated.
      fi
    fi
    echo "On iteration $x, learning rate is $this_learning_rate and shrink value is $this_shrink."

    # Set off jobs doing some diagnostics, in the background.
    # Use the egs dir from the previous iteration for the diagnostics
    $cmd $dir/log/compute_prob_valid.$x.log \
      nnet3-chain-compute-prob  \
          "nnet3-am-copy --raw=true $dir/$x.mdl -|" $dir/den.fst \
          "ark:nnet3-chain-merge-egs ark:$egs_dir/valid_diagnostic.cegs ark:- |" &
    $cmd $dir/log/compute_prob_train.$x.log \
      nnet3-chain-compute-prob \
          "nnet3-am-copy --raw=true $dir/$x.mdl -|" $dir/den.fst \
          "ark:nnet3-chain-merge-egs ark:$egs_dir/train_diagnostic.cegs ark:- |" &

    if [ $x -gt 0 ]; then
      # This doesn't use the egs, it only shows the relative change in model parameters.
      $cmd $dir/log/progress.$x.log \
        nnet3-show-progress --use-gpu=no "nnet3-am-copy --raw=true $dir/$[$x-1].mdl - |" \
                  "nnet3-am-copy --raw=true $dir/$x.mdl - |" '&&' \
        nnet3-am-info $dir/$x.mdl &
    fi

    echo "Training neural net (pass $x) $num_chunk_per_minibatch"

    if [ $x -gt 0 ] && \
      [ $x -le $[($num_hidden_layers-1)*$add_layers_period] ] && \
      [ $[$x%$add_layers_period] -eq 0 ]; then
      do_average=false # if we've just mixed up, don't do averaging but take the
                       # best.
      cur_num_hidden_layers=$[1+$x/$add_layers_period]
      config=$dir/configs/layer$cur_num_hidden_layers.config
      mdl="nnet3-am-copy --raw=true --learning-rate=$this_learning_rate $dir/$x.mdl - | nnet3-init --srand=$x - $config - |"
    else
      do_average=true
      if [ $x -eq 0 ]; then do_average=false; fi # on iteration 0, pick the best, don't average.
      mdl="nnet3-am-copy --raw=true --learning-rate=$this_learning_rate $dir/$x.mdl -|"
    fi
    if $do_average; then
      this_num_chunk_per_minibatch=$num_chunk_per_minibatch
    else
      # on iteration zero or when we just added a layer, use a smaller minibatch
      # size (and we will later choose the output of just one of the jobs): the
      # model-averaging isn't always helpful when the model is changing too fast
      # (i.e. it can worsen the objective function), and the smaller minibatch
      # size will help to keep the update stable.
      this_num_chunk_per_minibatch=$[$num_chunk_per_minibatch/2];
    fi

    rm $dir/.error 2>/dev/null


    ( # this sub-shell is so that when we "wait" below,
      # we only wait for the training jobs that we just spawned,
      # not the diagnostic jobs that we spawned above.

      # We cannot easily use a single parallel SGE job to do the main training,
      # because the computation of which archive and which --frame option
      # to use for each job is a little complex, so we spawn each one separately.
      # this is no longer true for RNNs as we use do not use the --frame option
      # but we use the same script for consistency with FF-DNN code

      for n in $(seq $this_num_jobs); do
        k=$[$num_archives_processed + $n - 1]; # k is a zero-based index that we will derive
                                               # the other indexes from.
        archive=$[($k%$num_archives)+1]; # work out the 1-based archive index.
        frame_shift=$[($k/$num_archives)%$frame_subsampling_factor];

        if $scale_max_param_change; then
          this_max_param_change=$(perl -e "print ($max_param_change * $this_num_jobs);")
        else
          this_max_param_change=$max_param_change
        fi
        $cmd $train_queue_opt $dir/log/train.$x.$n.log \
          nnet3-chain-train --apply-deriv-weights=$apply_deriv_weights \
              $parallel_train_opts $deriv_time_opts \
             --max-param-change=$this_max_param_change \
             --optimization.min-deriv-time=$min_deriv_time \
             --print-interval=10 "$mdl" $dir/den.fst \
          "ark:nnet3-chain-copy-egs --truncate-deriv-weights=$truncate_deriv_weights --frame-shift=$frame_shift ark:$egs_dir/cegs.$archive.ark ark:- | nnet3-chain-shuffle-egs --buffer-size=$shuffle_buffer_size --srand=$x ark:- ark:-| nnet3-chain-merge-egs --minibatch-size=$this_num_chunk_per_minibatch ark:- ark:- |" \
          $dir/$[$x+1].$n.raw || touch $dir/.error &
      done
      wait
    )
    # the error message below is not that informative, but $cmd will
    # have printed a more specific one.
    [ -f $dir/.error ] && echo "$0: error on iteration $x of training" && exit 1;

    models_to_average=$(steps/nnet3/get_successful_models.py --difference-threshold 0.1 $this_num_jobs $dir/log/train.$x.%.log)
    nnets_list=
    for n in $models_to_average; do
      nnets_list="$nnets_list $dir/$[$x+1].$n.raw"
    done

    if $do_average; then
      # average the output of the different jobs.
      $cmd $dir/log/average.$x.log \
        nnet3-average $nnets_list - \| \
        nnet3-am-copy --scale=$this_shrink --set-raw-nnet=- $dir/$x.mdl $dir/$[$x+1].mdl || exit 1;
    else
      # choose the best from the different jobs.
      n=$(perl -e '($nj,$pat)=@ARGV; $best_n=1; $best_logprob=-1.0e+10; for ($n=1;$n<=$nj;$n++) {
          $fn = sprintf($pat,$n); open(F, "<$fn") || die "Error opening log file $fn";
          undef $logprob; while (<F>) { if (m/log-prob-per-frame=(\S+)/) { $logprob=$1; } }
          close(F); if (defined $logprob && $logprob > $best_logprob) { $best_logprob=$logprob;
          $best_n=$n; } } print "$best_n\n"; ' $this_num_jobs $dir/log/train.$x.%d.log) || exit 1;
      [ -z "$n" ] && echo "Error getting best model" && exit 1;
      $cmd $dir/log/select.$x.log \
        nnet3-am-copy --scale=$this_shrink --set-raw-nnet=$dir/$[$x+1].$n.raw  $dir/$x.mdl $dir/$[$x+1].mdl || exit 1;
    fi

    if $fix_nnet; then
      echo "not yet implemented : Fixing the network"
      # do nnet-am-fix to fix some pathology in the network
      #nnet-am-fix --max-average-deriv=$max_average --min-average-deriv=$min_average $dir/$[$x+1].mdl $dir/$[$x+1].mdl 2>$dir/log/fix.$x.log || exit;
    fi

    nnets_list=
    for n in `seq 1 $this_num_jobs`; do
      nnets_list="$nnets_list $dir/$[$x+1].$n.raw"
    done

    rm $nnets_list
    [ ! -f $dir/$[$x+1].mdl ] && exit 1;
    if [ -f $dir/$[$x-1].mdl ] && $cleanup && \
       [ $[($x-1)%100] -ne 0  ] && [ $[$x-1] -lt $first_model_combine ]; then
      rm $dir/$[$x-1].mdl
    fi
  fi
  x=$[$x+1]
  num_archives_processed=$[$num_archives_processed+$this_num_jobs]
done


if [ $stage -le $num_iters ]; then
  echo "Doing final combination to produce final.mdl"

  # Now do combination.  In the nnet3 setup, the logic
  # for doing averaging of subsets of the models in the case where
  # there are too many models to reliably esetimate interpolation
  # factors (max_models_combine) is moved into the nnet3-combine
  nnets_list=()
  for n in $(seq 0 $[num_iters_combine-1]); do
    iter=$[$first_model_combine+$n]
    mdl=$dir/$iter.mdl
    [ ! -f $mdl ] && echo "Expected $mdl to exist" && exit 1;
    nnets_list[$n]="nnet3-am-copy --raw=true $mdl -|";
  done

  # Below, we use --use-gpu=no to disable nnet3-combine-fast from using a GPU,
  # as if there are many models it can give out-of-memory error; and we set
  # num-threads to 8 to speed it up (this isn't ideal...)
  
  $cmd $combine_queue_opt $dir/log/combine.log \
    nnet3-chain-combine --num-iters=40 \
       --enforce-sum-to-one=true --enforce-positive-weights=true \
       --verbose=3 $dir/den.fst "${nnets_list[@]}" "ark:nnet3-chain-merge-egs --minibatch-size=$num_chunk_per_minibatch ark:$egs_dir/combine.cegs ark:-|" \
       "|nnet3-am-copy --set-raw-nnet=- $dir/$first_model_combine.mdl $dir/final.mdl" || exit 1;


  # Compute the probability of the final, combined model with
  # the same subset we used for the previous compute_probs, as the
  # different subsets will lead to different probs.
  $cmd $dir/log/compute_prob_valid.final.log \
    nnet3-chain-compute-prob \
           "nnet3-am-copy --raw=true $dir/final.mdl - |" $dir/den.fst \
    "ark:nnet3-chain-merge-egs ark:$egs_dir/valid_diagnostic.cegs ark:- |" &
  $cmd $dir/log/compute_prob_train.final.log \
    nnet3-chain-compute-prob \
      "nnet3-am-copy --raw=true $dir/final.mdl - |" $dir/den.fst \
    "ark:nnet3-chain-merge-egs ark:$egs_dir/train_diagnostic.cegs ark:- |" &
fi

if [ ! -f $dir/final.mdl ]; then
  echo "$0: $dir/final.mdl does not exist."
  # we don't want to clean up if the training didn't succeed.
  exit 1;
fi

sleep 2

echo Done

if $cleanup; then
  echo Cleaning up data
  if $remove_egs && [[ $cur_egs_dir =~ $dir/egs* ]]; then
    steps/nnet2/remove_egs.sh $cur_egs_dir
  fi

  echo Removing most of the models
  for x in `seq 0 $num_iters`; do
    if [ $[$x%100] -ne 0 ] && [ $x -ne $num_iters ] && [ -f $dir/$x.mdl ]; then
       # delete all but every 100th model; don't delete the ones which combine to form the final model.
       rm $dir/$x.mdl
    fi
  done
fi
