#!/bin/bash

# based on run_tdnn_6h.sh

#%WER 9.6 | 1831 21395 | 91.6 5.8 2.6 1.2 9.6 44.2 | exp/chain/blstm_6h_sp/decode_eval2000_sw1_fsh_fg/score_10_1.0/eval2000_hires.ctm.swbd.filt.sys
#%WER 14.5 | 4459 42989 | 87.4 8.9 3.7 1.9 14.5 50.5 | exp/chain/blstm_6h_sp/decode_eval2000_sw1_fsh_fg/score_9_0.0/eval2000_hires.ctm.filt.sys
#%WER 19.3 | 2628 21594 | 83.3 11.8 4.9 2.5 19.3 54.8 | exp/chain/blstm_6h_sp/decode_eval2000_sw1_fsh_fg/score_9_0.0/eval2000_hires.ctm.callhm.filt.sys
#%WER 13.32 [ 6554 / 49204, 830 ins, 1696 del, 4028 sub ] exp/chain/blstm_6h_sp/decode_train_dev_sw1_fsh_fg/wer_10_0.0

set -e

# configs for 'chain'
stage=12
train_stage=-10
get_egs_stage=-10
<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
=======
mic=ihm
use_ihm_ali=false
exp_name=blstm
affix=
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
speed_perturb=true
dir=exp/chain/blstm_6h  # Note: _sp will get added to this if $speed_perturb == true.
decode_iter=
decode_dir_affix=

# training options
leftmost_questions_truncate=-1
chunk_width=150
chunk_left_context=40
chunk_right_context=40
xent_regularize=0.025

label_delay=0
# decode options
extra_left_context=
extra_right_context=
frames_per_chunk=

remove_egs=false
common_egs_dir=
max_wer=
min_seg_len=

affix=
# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# The iVector-extraction and feature-dumping parts are the same as the standard
# nnet3 setup, and you can skip them by setting "--stage 8" if you have already
# run those things.

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
suffix=
if [ "$speed_perturb" == "true" ]; then
  suffix=_sp
fi

dir=$dir${affix:+_$affix}
if [ $label_delay -gt 0 ]; then dir=${dir}_ld$label_delay; fi
dir=${dir}$suffix
train_set=train_nodup$suffix
ali_dir=exp/tri4_ali_nodup$suffix
treedir=exp/chain/tri5_2y_tree$suffix
lang=data/lang_chain_2y

=======

# if we are using the speed-perturbed data we need to generate
# alignments for it.
local/nnet3/run_ivector_common.sh --stage $stage \
                                  --mic $mic \
                                  --use-ihm-ali $use_ihm_ali \
                                  --use-sat-alignments true || exit 1;

gmm=tri4a
if [ $use_ihm_ali == "true" ]; then
  gmm_dir=exp/ihm/$gmm
  mic=${mic}_cleanali
  ali_dir=${gmm_dir}_${mic}_train_parallel_sp_ali
  lat_dir=${gmm_dir}_${mic}_train_parallel_sp_lats
else
  gmm_dir=exp/$mic/$gmm
  ali_dir=${gmm_dir}_${mic}_train_sp_ali
  lat_dir=${gmm_dir}_${mic}_train_sp_lats
fi




dir=exp/$mic/chain/${exp_name}${affix:+_$affix} # Note: _sp will get added to this if $speed_perturb == true.
dir=${dir}_sp


treedir=exp/$mic/chain/tri5_2y_tree_sp
lang=data/$mic/lang_chain_2y
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh

# if we are using the speed-perturbed data we need to generate
# alignments for it.
local/nnet3/run_ivector_common.sh --stage $stage \
  --speed-perturb $speed_perturb \
  --generate-alignments $speed_perturb || exit 1;

train_set=train_sp
latgen_train_set=train_sp
if [ $use_ihm_ali == "true" ]; then
  latgen_train_set=train_parallel_sp
fi

if [ ! -z $min_seg_len ]; then
  # combining the segments in training data to have a minimum length
  if [ $stage -le 10 ]; then
    steps/cleanup/combine_short_segments.sh $min_seg_len data/$mic/${train_set}_hires data/$mic/${train_set}_min${min_seg_len}_hires
    #extract ivectors for the new data
    steps/online/nnet2/copy_data_dir.sh --utts-per-spk-max 2 \
      data/$mic/${train_set}_min${min_seg_len}_hires data/$mic/${train_set}_min${min_seg_len}_hires_max2
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 30 \
      data/$mic/${train_set}_min${min_seg_len}_hires_max2 \
      exp/$mic/nnet3/extractor \
      exp/$mic/nnet3/ivectors_${train_set}_min${min_seg_len}_hires || exit 1;
   # combine the non-hires features for alignments/lattices
   steps/cleanup/combine_short_segments.sh $min_seg_len data/$mic/${latgen_train_set} data/$mic/${latgen_train_set}_min${min_seg_len}
    exit 1;
  fi
  train_set=${train_set}_min${min_seg_len}
  latgen_train_set=${latgen_train_set}_min${min_seg_len}

  if [ $stage -le 11 ]; then
    # realigning data as the segments would have changed
    steps/align_fmllr.sh --nj 100 --cmd "$train_cmd" data/$mic/$latgen_train_set data/lang $gmm_dir ${ali_dir}_min${min_seg_len} || exit 1;
  fi
  ali_dir=${ali_dir}_min${min_seg_len}
  lat_dir=${lat_dir}_min${min_seg_len}
fi

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
if [ $stage -le 9 ]; then
  # Get the alignments as lattices (gives the CTC training more freedom).
=======
if [ $stage -le 12 ]; then
  # Get the alignments as lattices (gives the chain training more freedom).
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
  # use the same num-jobs as the alignments
  nj=$(cat exp/tri4_ali_nodup$suffix/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh --nj $nj --cmd "$train_cmd" data/$train_set \
    data/lang exp/tri4 exp/tri4_lats_nodup$suffix
  rm exp/tri4_lats_nodup$suffix/fsts.*.gz # save space
fi


<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
if [ $stage -le 10 ]; then
=======
if [ $stage -le 13 ]; then
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r data/lang $lang
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this
  # topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
if [ $stage -le 11 ]; then
=======
if [ $stage -le 14 ]; then
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --leftmost-questions-truncate $leftmost_questions_truncate \
      --cmd "$train_cmd" 9000 data/$train_set $lang $ali_dir $treedir
fi

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
if [ $stage -le 12 ]; then
  echo "$0: creating neural net configs";

  steps/nnet3/lstm/make_configs.py  \
    --feat-dir data/${train_set}_hires \
    --ivector-dir exp/nnet3/ivectors_${train_set} \
=======
mkdir -p $dir
train_data_dir=data/$mic/${train_set}_hires
if [ ! -z $max_wer ]; then
  if [ $stage -le 15 ]; then
    steps/cleanup/find_bad_utts.sh --cmd "$decode_cmd" --nj 100 data/$mic/${train_set} data/lang $ali_dir ${gmm_dir}_bad_utts
    python local/sort_bad_utts.py --bad-utt-info-file ${gmm_dir}_bad_utts/all_info.sorted.txt --max-wer $max_wer --output-file $dir/wer_sorted_utts_${max_wer}wer
    utils/copy_data_dir.sh data/$mic/${train_set}_hires data/$mic/${train_set}_${max_wer}wer_hires
    utils/filter_scp.pl $dir/wer_sorted_utts_${max_wer}wer data/sdm1/${train_set}_hires/feats.scp  > data/$mic/${train_set}_${max_wer}wer_hires/feats.scp
    utils/fix_data_dir.sh data/$mic/${train_set}_${max_wer}wer_hires
  fi
  train_data_dir=data/$mic/${train_set}_${max_wer}wer_hires
fi

if [ $stage -le 16 ]; then
  echo "$0: creating neural net configs";

  steps/nnet3/lstm/make_configs.py  \
    --feat-dir $train_data_dir \
    --ivector-dir exp/$mic/nnet3/ivectors_${train_set}_hires \
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
    --tree-dir $treedir \
    --splice-indexes="-2,-1,0,1,2 0 0" \
    --lstm-delay=" [-3,3] [-3,3] [-3,3] " \
    --xent-regularize $xent_regularize \
    --include-log-softmax false \
    --num-lstm-layers 3 \
    --cell-dim 1024 \
    --hidden-dim 1024 \
    --recurrent-projection-dim 256 \
    --non-recurrent-projection-dim 256 \
    --label-delay $label_delay \
    --self-repair-scale 0.00001 \
   $dir/configs || exit 1;

fi

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
if [ $stage -le 13 ]; then
=======
if [ $stage -le 17 ]; then
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{5,6,7,8}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5c/$dir/egs/storage $dir/egs/storage
  fi

 touch $dir/egs/.nodelete # keep egs around when that run dies.

 steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd" \
    --feat.online-ivector-dir exp/nnet3/ivectors_${train_set} \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --chain.left-deriv-truncate 0 \
    --trainer.num-chunk-per-minibatch 64 \
    --trainer.frames-per-iter 1200000 \
    --trainer.max-param-change 2.0 \
    --trainer.num-epochs 5 \
    --trainer.optimization.shrink-value 0.99 \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 16 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.optimization.momentum 0.0 \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0" \
    --egs.chunk-width $chunk_width \
    --egs.chunk-left-context $chunk_left_context \
    --egs.chunk-right-context $chunk_right_context \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
    --feat-dir data/${train_set}_hires \
=======
    --feat-dir $train_data_dir \
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
    --tree-dir $treedir \
    --lat-dir exp/tri4_lats_nodup$suffix \
    --dir $dir  || exit 1;
fi

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
if [ $stage -le 14 ]; then
=======
if [ $stage -le 18 ]; then
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_sw1_tg $dir $dir/graph_sw1_tg
fi

<<<<<<< HEAD:egs/swbd/s5c/local/chain/run_blstm_6h.sh
decode_suff=sw1_tg
graph_dir=$dir/graph_sw1_tg
if [ $stage -le 15 ]; then
=======
if [ $stage -le 19 ]; then
>>>>>>> Added TDNN and BLSTM chain recipes. Added plotting tools for generating:egs/ami/s5/local/chain/run_blstm_6h.sh
  [ -z $extra_left_context ] && extra_left_context=$chunk_left_context;
  [ -z $extra_right_context ] && extra_right_context=$chunk_right_context;
  [ -z $frames_per_chunk ] && frames_per_chunk=$chunk_width;
  iter_opts=
  if [ ! -z $decode_iter ]; then
    iter_opts=" --iter $decode_iter "
  fi
  for decode_set in dev eval; do
      (
      steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
          --nj $num_jobs --cmd "$decode_cmd" $iter_opts \
          --extra-left-context $extra_left_context  \
          --extra-right-context $extra_right_context  \
          --frames-per-chunk "$frames_per_chunk" \
          --online-ivector-dir exp/nnet3/ivectors_${decode_set} \
         $graph_dir data/${decode_set}_hires $dir/decode_${decode_set}${decode_dir_affix:+_$decode_dir_affix}_${decode_suff} || exit 1;
      if $has_fisher; then
          steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
            data/lang_sw1_{tg,fsh_fg} data/${decode_set}_hires \
            $dir/decode_${decode_set}${decode_dir_affix:+_$decode_dir_affix}_sw1_{tg,fsh_fg} || exit 1;
      fi
      ) &
  done
fi
wait;
exit 0;
