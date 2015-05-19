#!/usr/bin/bash

##################################################
#
# This script is run via cron to check the FTP deposit directory for
# new records.
#
# You need one per supplier
#
#################################################

export INDIR=/path/to/ftp/elife/deposit
export BACKUPDIR=/path/to/backups/elife_processed

subdirs=`ls -F $INDIR | grep '/'`;
for d in $subdirs;
do
/path/to/eprints/scripts/broker_ftp_import --quiet --user elife archive Elife $INDIR/$d;
if [ $? == 0 ]; then
  mv $INDIR/$d $BACKUPDIR;
fi;
done
