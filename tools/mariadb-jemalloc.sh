#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
######################################################
# switch from glibc system memory allocator to
# jemalloc malloc on CentOS 7 64bit systems only
#
# also apply numa intervleave cpu optimisations if 
# more than 1 cpu socket detected
#
# written by George Liu (centminmod.com)
######################################################
JEMALLOC='y'
NUMA='y'

######################################################
# Setup Colours
black='\E[30;40m'
red='\E[31;40m'
green='\E[32;40m'
yellow='\E[33;40m'
blue='\E[34;40m'
magenta='\E[35;40m'
cyan='\E[36;40m'
white='\E[37;40m'

boldblack='\E[1;30;40m'
boldred='\E[1;31;40m'
boldgreen='\E[1;32;40m'
boldyellow='\E[1;33;40m'
boldblue='\E[1;34;40m'
boldmagenta='\E[1;35;40m'
boldcyan='\E[1;36;40m'
boldwhite='\E[1;37;40m'

Reset="tput sgr0"      #  Reset text attributes to normal
                       #+ without clearing screen.

cecho ()                     # Coloured-echo.
                             # Argument $1 = message
                             # Argument $2 = color
{
message=$1
color=$2
echo -e "$color$message" ; $Reset
return
}
######################################################
# set locale temporarily to english
# due to some non-english locale issues
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
# disable systemd pager so it doesn't pipe systemctl output to less
export SYSTEMD_PAGER=''

shopt -s expand_aliases
for g in "" e f; do
    alias ${g}grep="LC_ALL=C ${g}grep"  # speed-up grep, egrep, fgrep
done

cmservice() {
  servicename=$1
  action=$2
  if [[ "$CENTOS_SIX" = '6' ]] && [[ "${servicename}" = 'haveged' || "${servicename}" = 'pure-ftpd' || "${servicename}" = 'mysql' || "${servicename}" = 'php-fpm' || "${servicename}" = 'nginx' || "${servicename}" = 'memcached' || "${servicename}" = 'nsd' || "${servicename}" = 'csf' || "${servicename}" = 'lfd' ]]; then
    echo "service ${servicename} $action"
    if [[ "$CMSDEBUG" = [nN] ]]; then
      service "${servicename}" "$action"
    fi
  else
    if [[ "${servicename}" = 'php-fpm' || "${servicename}" = 'nginx' ]]; then
      echo "service ${servicename} $action"
      if [[ "$CMSDEBUG" = [nN] ]]; then
        service "${servicename}" "$action"
      fi
    elif [[ "${servicename}" = 'mysql' || "${servicename}" = 'mysqld' ]]; then
      servicename='mariadb'
      echo "systemctl $action ${servicename}.service"
      if [[ "$CMSDEBUG" = [nN] ]]; then
        systemctl "$action" "${servicename}.service"
      fi
    fi
  fi
}

switch_malloc() {
  switchback=$1
  JEMALLOC_MARIADBVER=$(mysqladmin -V | awk '{print $5}' | sed -e 's|,||g' -e 's|-||g' -e 's|MariaDB||' | cut -d . -f1,2)
  if [[ "$JEMALLOC_MARIADBVER" = 10.[56] ]]; then
    jemalloc_mariadb_bin='mariadbd'
  elif [[ "$JEMALLOC_MARIADBVER" = 10.4 ]]; then
    jemalloc_mariadb_bin='mysqld'
  fi
  if [[ "$JEMALLOC_MARIADBVER" = 10.[456] ]]; then
    if [[ "$JEMALLOC" = [yY] && "$(mysqladmin ping -s >/dev/null 2>&1; echo $?)" -eq '0' && "$switchback" != 'back' ]]; then
      echo
      cecho "check existing $jemalloc_mariadb_bin memory usage" $boldyellow
      pidstat -rh -C $jemalloc_mariadb_bin | sed -e "s|$(hostname)|hostname|g"
  
      echo
      cecho "check listing at /etc/systemd/system/mariadb.service.d" $boldyellow
      ls -lah /etc/systemd/system/mariadb.service.d
  
      echo
      cecho "inspect MariaDB MySQL server version_malloc_library value before switch" $boldyellow
      mysqladmin var | grep 'version_malloc_library' | tr -s ' '
  
      if [[ ! "$(lsof -p $(pidof $jemalloc_mariadb_bin) | grep 'jemalloc')" && "$(mysqladmin var | grep 'version_malloc_library' | tr -s ' ' | grep -o 'jemalloc')" != 'jemalloc' && -f /usr/lib64/libjemalloc.so.1 && ! -f /etc/systemd/system/mariadb.service.d/jemalloc.conf ]]; then
        echo
        cecho "switch malloc from glibc system to jemalloc" $boldyellow
        echo -e "[Service]\nEnvironment=\"LD_PRELOAD=/usr/lib64/libjemalloc.so.1\"" > /etc/systemd/system/mariadb.service.d/jemalloc.conf
      else
        skip='y'
      fi
      if [[ "$skip" = [yY] ]]; then
        echo
        cecho "criteria for switching to jemalloc was not met" $boldyellow
        if [[ "$(lsof -p $(pidof $jemalloc_mariadb_bin) | grep 'jemalloc')" || "$(mysqladmin var | grep 'version_malloc_library' | tr -s ' ' | grep -o 'jemalloc')" = 'jemalloc' ]]; then
          if [ -f /etc/systemd/system/mariadb.service.d/jemalloc.conf ]; then
            echo
            echo "jemalloc malloc already in use by MariaDB MySQL"
            echo "via /etc/systemd/system/mariadb.service.d/jemalloc.conf"
          fi
        fi
        echo
        cecho "no changes were made" $boldyellow
        cecho "aborting run..." $boldyellow
        exit 1
      else
        echo
        cecho "contents of /etc/systemd/system/mariadb.service.d/jemalloc.conf" $boldyellow
        cat /etc/systemd/system/mariadb.service.d/jemalloc.conf
  
        echo
        cecho "restarting MariaDB MySQL server for changes" $boldyellow
        systemctl daemon-reload; systemctl restart mariadb; systemctl status mariadb --no-pager
  
        echo
        cecho "inspect MariaDB MySQL server version_malloc_library value after switch" $boldyellow
        mysqladmin var | grep 'version_malloc_library' | tr -s ' '
  
        echo
        cecho "check existing $jemalloc_mariadb_bin memory usage after switch" $boldyellow
        pidstat -rh -C $jemalloc_mariadb_bin | sed -e "s|$(hostname)|hostname|g"
      fi
    elif [[ "$(mysqladmin ping -s >/dev/null 2>&1; echo $?)" -ne '0' && "$switchback" != 'back' ]]; then
      echo
      cecho "MariaDB MySQL server is not running" $boldyellow
      cecho "aborting run..." $boldyellow
      exit 1
    fi
    if [[ "$switchback" = 'back' && -f /etc/systemd/system/mariadb.service.d/jemalloc.conf ]]; then
      echo "Switching MariaDB from jemalloc to system glibc malloc default method"
      rm -f /etc/systemd/system/mariadb.service.d/jemalloc.conf
      echo
      cecho "restarting MariaDB MySQL server for changes" $boldyellow
      systemctl daemon-reload; systemctl restart mariadb; systemctl status mariadb --no-pager
      echo
      cecho "inspect MariaDB MySQL server version_malloc_library value after switch" $boldyellow
      mysqladmin var | grep 'version_malloc_library' | tr -s ' '
      echo
      cecho "check existing $jemalloc_mariadb_bin memory usage after switch" $boldyellow
      pidstat -rh -C $jemalloc_mariadb_bin | sed -e "s|$(hostname)|hostname|g"
    fi
  fi
}

numa_opt() {
  if [[ "$NUMA" = [yY] && "$(mysqladmin ping -s >/dev/null 2>&1; echo $?)" -eq '0' ]]; then
    echo
    cecho "apply numa optimisation if required" $boldyellow
    if [[ -f /usr/bin/numactl && "$(numactl --hardware | awk '/available:/ {print $2}')" -gt '2' && ! -f /etc/systemd/system/mariadb.service.d/numa.conf ]]; then
      echo -e "[Service]\nExecStart=\nExecStart=/usr/bin/numactl --interleave=all /usr/sbin/${jemalloc_mariadb_bin} \$MYSQLD_OPTS \$_WSREP_NEW_CLUSTER \$_WSREP_START_POSITION\"" > /etc/systemd/system/mariadb.service.d/numa.conf
    else
      skip='y'
    fi
    if [[ "$skip" = [yY] ]]; then
      if [[ -f /usr/bin/numactl && "$(numactl --hardware | awk '/available:/ {print $2}')" -lt '2' ]]; then
        echo
        echo "numa optimisation not needed"
        echo "single cpu socket (node) system detected"
      fi
      if [ -f /etc/systemd/system/mariadb.service.d/numa.conf ]; then
        echo
        echo "numa optimisation already in use by MariaDB MySQL"
        echo "via /etc/systemd/system/mariadb.service.d/numa.conf"
      fi
      echo
      cecho "no numa changes were made" $boldyellow
      cecho "aborting run..." $boldyellow
      exit 1
    else
      echo
      cecho "contents of /etc/systemd/system/mariadb.service.d/numa.conf" $boldyellow
      cat /etc/systemd/system/mariadb.service.d/numa.conf

      echo
      cecho "restarting MariaDB MySQL server for changes" $boldyellow
      systemctl daemon-reload; systemctl restart mariadb; systemctl status mariadb --no-pager
    fi
  else
    echo
    cecho "MariaDB MySQL server is not running" $boldyellow
    cecho "aborting run..." $boldyellow
    exit 1
  fi
}

case "$1" in
  switch )
    switch_malloc
    ;;
  switch-back )
    switch_malloc back
    ;;
  numa )
    numa_opt
    ;;
  * )
    echo
    echo "Usage:"
    echo
    echo "$0 {switch|switch-back|numa}"
    echo
    ;;
esac

exit