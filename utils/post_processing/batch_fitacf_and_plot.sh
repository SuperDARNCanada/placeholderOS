#!/bin/bash

# Copyright 2019 SuperDARN Canada, University of Saskatchewan
# Author: Marci Detwiller

RAWACF_DIR="/borealis_site_data/sas_rawacf_dmap/"
FITACF_DIR="/borealis_site_data/sas_fitacf/"
SUMMARY_PLOT_DIR="/borealis_site_data/sas_summary_plot/"

source /home/dataman/pydarn-summary-env/bin/activate
# get the rtp plotting pydarn

LOG_DIR="/home/dataman/borealis/utils/post_processing/logs/"

dates=(
20190401
20190402
20190403
20190404
20190405
20190406
20190407
20190408
20190409
20190410
20190411
20190412
20190413
20190414
20190415
20190416
20190417
20190418
20190419
20190420
20190421
20190422
20190423
20190424
20190425
20190426
20190427
20190428
20190429
20190430
20190501
20190502
20190503
20190504
20190505
20190506
20190507
20190508
20190509
20190511
20190512
20190513
20190514
20190515
20190516
20190517
20190518
20190519
20190520
20190521
20190522
20190523
20190524
20190529
20190530
20190531
20190601
20190602
20190603
20190604
20190605
20190606
20190607
20190608
20190609
20190610
20190611
20190612
20190613
20190614
20190615
20190616
20190617
20190618
20190619
20190625
20190626
20190627
20190628
20190629
20190630
20190701
20190702
20190705
20190706
20190707
20190708
20190709
20190710
20190711
20190712
20190713
20190714
20190715
20190716
20190717
20190718
20190719
20190720
20190721
20190722
20190723
20190724
20190725
20190726
20190727
20190728
20190729
20190730
20190731
20190801
20190802
20190803
20190804
20190805
20190806
)

for date in "${dates[@]}"; do
	mkdir "$FITACF_DIR$date"
	cd "$RAWACF_DIR$date/"
	pwd
	bunzip2 -kv *.rawacf.dmap.bz2
	echo "/home/dataman/borealis/utils/post_processing/generate_fitacfs.sh $RAWACF_DIR $FITACF_DIR $date"
	/home/dataman/borealis/utils/post_processing/generate_fitacfs.sh $RAWACF_DIR $FITACF_DIR $date
	rm *rawacf.dmap # cleanup leaving only the bzipped

	cd /home/dataman/borealis/utils/post_processing/
	# bzip2 $($RAWACF_DIR$date/*.rawacf.dmap)
	mkdir "$SUMMARY_PLOT_DIR$date"
	echo "python3 /home/dataman/borealis/utils/post_processing/batch_summary_plots.py "$SUMMARY_PLOT_DIR$date/" $FITACF_DIR$date/*.fitacf.dmap"
	python3 /home/dataman/borealis/utils/post_processing/batch_summary_plots.py "$SUMMARY_PLOT_DIR$date/" "$FITACF_DIR$date"/*.fitacf.dmap
done
