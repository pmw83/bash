#!/bin/bash
#set -x

PROGRAM=`basename $0 .sh`
WD=`dirname $0`
DATESTAMP=`date +%Y-%m-%d.%H:%M`
LOGFILE=/var/log/rsync_snapshots/${PROGRAM}-${DATESTAMP}.log
LOCKFILE=/tmp/rsync_snapshots.lock
MAIL_RCPT=phillip.wyman83@gmail.com
CFGDIR='/etc/rsync_snapshots'
BACKUPDEV='/dev/sda5'
BACKUPROOT='/backup'
BACKUPFS='ext4'
BACKUPFSARGS='-t ext4 -m 0'
MAXDU='90'
BACKUPHOSTS=${CFGDIR}/hosts
BACKUPUSER='root'
PID=$$
PPID=$PPID

backuptype_pref='incr'
backup_reset=0
crontab=${CFGDIR}/crontab_incr

echo " " > ${LOGFILE}

ps -ef | grep rsync | grep -vE "${PID}|${PPID}|grep" > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "Previous rsync processes found. Exiting." >> ${LOGFILE}
  #mailx -s "rsync snapshots : failure" ${MAIL_RCPT} < ${LOGFILE}
  exit 1
fi

grep -w "${BACKUPDEV}" /etc/mtab > /dev/null 2>&1

if [ $? -ne 0 ]; then
  mount -t ${BACKUPFS} ${BACKUPDEV} ${BACKUPROOT} >> ${LOGFILE} 2>&1
 
  if [ $? -ne 0 ]; then
    echo "Failed mounting ${BACKUPDEV} to ${BACKUPROOT}. Exiting." >> ${LOGFILE}
    mailx -s "rsync snapshots : failure" ${MAIL_RCPT} < ${LOGFILE}
    exit 1
  fi
fi

if [ $1 ]; then
  if [ $1 == 'incr' ] || [ $1 == 'full' ]; then
    backuptype_pref=$1
  fi
fi

if [ $2 ]; then
  if [ $2 == 'reset' ]; then
    backup_reset=1

    umount -f ${BACKUPROOT} >> ${LOGFILE} 2>&1

    if [ $? -ne 0 ]; then
      echo "Failed unmounting ${BACKUPROOT} for reset. Exiting." >> ${LOGFILE}
      mailx -s "rsync snapshots : failure" ${MAIL_RCPT} < ${LOGFILE}
      exit 1
    fi

    /sbin/mkfs ${BACKUPFSARGS} ${BACKUPDEV} >> ${LOGFILE} 2>&1

    if [ $? -ne 0 ]; then
      echo "Failed creating filesystem on ${BACKUPDEV} for reset. Exiting." >> ${LOGFILE}
      mailx -s "rsync snapshots : failure" ${MAIL_RCPT} < ${LOGFILE}
      exit 1
    fi   

    mount ${BACKUPROOT} >> ${LOGFILE} 2>&1

    if [ $? -ne 0 ]; then
      echo "Failed mounting ${BACKUPDEV} to ${BACKUPROOT} during reset attempt. Exiting." >> ${LOGFILE}
      mailx -s "rsync snapshots : failure" ${MAIL_RCPT} < ${LOGFILE}
      exit 1
    fi       
  fi
fi

if [ $backup_reset -eq 0 ]; then
  pctfull=$(df -k ${BACKUPROOT} | grep ${BACKUPROOT}| awk '{print $5}'| sed -e's/%//')

  if [ $pctfull -gt $MAXDU ]; then
    echo "re-scheduling rsync snapshots to do a one-time full reset" >> ${LOGFILE}
    crontab=${CFGDIR}/crontab_full
    cp -f ${crontab} /var/spool/cron/root >> ${LOGFILE} 2>&1
    /etc/init.d/crond restart >> ${LOGFILE} 2>&1
    mailx -s "rsync snapshots : reset scheduled" ${MAIL_RCPT} < ${LOGFILE}
    exit 0
  fi
fi

echo rsync snapshots begin at `date` >> ${LOGFILE}

for backuphost in `cat ${BACKUPHOSTS}`
do
  if [ ! -d $BACKUPROOT/$backuphost ]; then
    mkdir -p ${BACKUPROOT}/${backuphost} >> ${LOGFILE} 2>&1
  fi   

  for backupdir in `cat ${CFGDIR}/${backuphost}-dirlist`
  do
    if [ ! -d $BACKUPROOT/$backuphost$backupdir ]; then
      mkdir -p ${BACKUPROOT}/${backuphost}${backupdir} >> ${LOGFILE} 2>&1
    fi

    if [ ! -e "$BACKUPROOT/$backuphost$backupdir/current" ]; then
      backuptype='full'
    else
      backuptype=$backuptype_pref
    fi

    backupdate=`date +%Y-%m-%d.%H:%M`

    mkdir ${BACKUPROOT}/${backuphost}${backupdir}/${backuptype}-${backupdate} >> ${LOGFILE} 2>&1

    rsync_flags='-avz --sparse --del'

    # remove leading /, replace other /s with - in path
    backupdir_str=`echo ${backupdir}|sed -e's/\///;s/\//-/g'`

    if [ -e "$CFGDIR/$backuphost-$backupdir_str-excludes" ]; then
      echo "excluding files matching patterns from ${CFGDIR}/${backuphost}-${backupdir_str}-excludes" >> ${LOGFILE}
      rsync_flags="$rsync_flags --exclude-from=${CFGDIR}/${backuphost}-${backupdir_str}-excludes"
    elif [ -e "$CFGDIR/$backuphost-excludes" ]; then
      echo "excluding files matching patterns from ${CFGDIR}/${backuphost}-excludes" >> ${LOGFILE}
      rsync_flags="$rsync_flags --exclude-from=${CFGDIR}/${backuphost}-excludes"
    fi

    if [ $backuptype == 'incr' ]; then
      rsync_flags="$rsync_flags --link-dest=${BACKUPROOT}/${backuphost}${backupdir}/current"
    fi

   df=$(df ${BACKUPDEV} | tail -n 1 | awk '{print $5}')

   echo "disk usage for snapshots partition is currently : ${df}" >> ${LOGFILE}

   echo "rsync of ${backuphost}:${backupdir} (${backuptype}) begins at `date`" >> ${LOGFILE}

   /usr/bin/rsync ${rsync_flags} -e ssh ${BACKUPUSER}@${backuphost}:${backupdir}/ ${BACKUPROOT}/${backuphost}${backupdir}/${backuptype}-${backupdate}/ >> ${LOGFILE} 2>&1

   if [ $? != 0 ]; then
     echo "rsync of ${backuphost}:${backupdir} (${backuptype}) returned non-zero status on `date`, not updating current symlink." >> ${LOGFILE}
   else 
     echo "rsync of ${backuphost}:${backupdir} (${backuptype}) ends at `date`" >> ${LOGFILE}

     df=$(df ${BACKUPDEV} | tail -n 1 | awk '{print $5}')

     echo "disk usage for snapshots partition is now : ${df}" >> ${LOGFILE}

     rm ${BACKUPROOT}/${backuphost}${backupdir}/current >> ${LOGFILE} 2>&1
     ln -s ${BACKUPROOT}/${backuphost}${backupdir}/${backuptype}-${backupdate}  ${BACKUPROOT}/${backuphost}${backupdir}/current >> ${LOGFILE} 2>&1
   fi
  done
done

echo rsync snapshots end at `date` >> ${LOGFILE}

if [ $backup_reset -eq 1 ]; then
  echo "re-scheduling rsync snapshots back to incremental schedule" >> ${LOGFILE}
  cp -f ${crontab} /var/spool/cron/root >> ${LOGFILE} 2>&1
  /etc/init.d/crond restart >> ${LOGFILE} 2>&1
  echo "Logfile can be viewed here : ${LOGFILE}" > /tmp/output
  mailx -s "rsync snapshots : reset complete" ${MAIL_RCPT} < /tmp/output
  rm -f /tmp/output
fi

