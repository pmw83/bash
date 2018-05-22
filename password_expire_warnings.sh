#!/bin/bash

HOST=$(hostname)
DOMAIN='somedomain.com'
WARNING_BUFFER=7 #days
CURRENT_DATE=$(date +%Y-%m-%d)
TMPFILE='/tmp/pass_warning'

touch ${TMPFILE}

for user in `ls /home | grep -vE 'lost\+found|some_excluded_user'`
do
  expire_date=$(chage -l ${user} | grep "Password expires" | awk '{print $4 " " $5 " " $6}')

  expires_in=$(echo $"(( $(date --date="${expire_date}" +%s) - $(date --date="${CURRENT_DATE}" +%s) ))/(60*60*24)"|bc)

  if [ $expires_in -le $WARNING_BUFFER ]; then
    if [ $expires_in -lt 0 ]; then
      echo "WARNING : Your password on ${HOST} is expired." > ${TMPFILE}
      echo "You will need to SSH to ${HOST} to change it." >> ${TMPFILE}
      echo "If you're running Windows, you can use the Putty utility to do so." >> ${TMPFILE}
      echo "You will be prompted just after authenticating with your current password to change it." >> ${TMPFILE}
    else
      if [ $expires_in == 0 ]; then
        echo "WARNING : Your password on ${HOST} will expire at midnight." > ${TMPFILE}
      else
        echo "WARNING : Your password on ${HOST} will expire in ${expires_in} day(s)." > ${TMPFILE}
      fi
      echo "You will need to SSH to ${HOST} to change it." >> ${TMPFILE}
      echo "If you're running Windows, you can use the Putty utility to do so." >> ${TMPFILE}
      echo "Once logged in, you can use the passwd command to change it." >> ${TMPFILE}
    fi

    mailx -s "Password expiration warning from ${HOST}" ${user}@${DOMAIN} < ${TMPFILE}
  fi
done

rm -f ${TMPFILE}

