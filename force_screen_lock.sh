#!/bin/bash

if [ $1 ]; then
  username=$1
  lock_command="/usr/bin/xdg-screensaver lock"
  screensaver_running=0
  screensaver_pid=$(ps -ef | grep -vE 'grep|xscreensaver-demo|gnome-screensaver-preferences' | grep -m1 -E 'gnome-screensaver|xscreensaver|kscreenlock' | awk '{print $2}')

  if [ $screensaver_pid ]; then
    ls -la "/proc/${screensaver_pid}/exe" | grep /usr/ > /dev/null 2>&1

    if [ $? -eq 0 ]; then
      screensaver_running=1
    fi
  fi

  export DISPLAY=:0.0
  #export DBUS_SESSION_BUS_ADDRESS=$(grep -zi DBUS /proc/$(pgrep fluxbox)/environ | sed -r -e 's/^DBUS_SESSION_BUS_ADDRESS=//')
  export XAUTHORITY=$(ls -d /var/run/gdm3/auth-for-${username}*)/database
  #export RUNNING_UNDER_GDM=false

  #env >> /home/test/force_screen_lock.log 

  if [ -e "/home/${username}/.xscreensaver" ]; then
    sed -i 's/\(lock:\t\t\).*/\1True/' "/home/${username}/.xscreensaver" > /dev/null 2>&1
  else
    echo "lock:           True" > "/home/${username}/.xscreensaver" 
    chown "${username}:users" "/home/${username}/.xscreensaver"
  fi

  if [ $screensaver_running -eq 0 ]; then
    su "${username}" -c "/usr/bin/xscreensaver -nosplash &"
  fi

  su "${username}" -c "${lock_command}"
else
  echo "A username's screen to lock is required as an argument"
fi

