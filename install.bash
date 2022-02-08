#!/usr/bin/env bash

BASEDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi
if [[ $1 == "sync" ]]; then
  if [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "alpine" ]]; then
    install -m 755 "$BASEDIR"/zsync.service /etc/periodic/daily/zsync
  else 
    install -m 644 "$BASEDIR"/zsync.timer /etc/systemd/system/
    install -m 644 "$BASEDIR"/zsync.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now zsync.timer
  fi
  echo "#####     zsync service is now installed     #####"
  exit 0
fi
if [[ "$(systemctl is-active zram-config.service 2> /dev/null)" == "active" ]] || [[ "$(rc-service syslog status 2> /dev/null | sed -ne 's/^ \* status: \(.*\)/\1/p')" == "started" ]]; then
  echo -e "ERROR: zram-config service is still running.\\nPlease run \"sudo ${BASEDIR}/update.bash\" to update zram-config instead."
  exit 1
fi
if [[ -f /usr/local/sbin/zram-config || -f /usr/sbin/zram-config ]]; then
  echo -e "ERROR: zram-config is already installed.\\nPlease run \"sudo ${BASEDIR}/update.bash\" to update zram-config instead."
  exit 1
fi

if ! dpkg -s 'gcc' 'make' 'libc6-dev' &> /dev/null && ! [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "alpine" ]]; then
  echo "Installing needed packages (gcc, make, libc6-dev)"
  apt-get install --yes gcc make libc6-dev || exit 1
fi
if ! [[ "$(apk info 2> /dev/null | grep -E '^(gcc|make|fts-dev)' | tr '\n' ' ')" == "gcc make fts-dev " ]]; then
  echo "Installing needed packages (gcc, make, fts-dev)"
  apk add gcc make fts-dev || exit 1
fi

if [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "ubuntu" ]] && [[ $(bc -l <<< "$(grep -o '^VERSION_ID=.*$' /etc/os-release | cut -d'=' -f2 | tr -d '"') >= 21.10") -eq 1 ]]; then
  echo "Install zram module package for Ubuntu (linux-modules-extra-raspi)"
  if ! dpkg -s 'linux-modules-extra-raspi' &> /dev/null; then
    apt-get install --yes linux-modules-extra-raspi || exit 1
  fi
fi

if [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "alpine" ]]; then
  make --always-make --directory="${BASEDIR}/overlayfs-tools" external
else 
  make --always-make --directory="${BASEDIR}/overlayfs-tools"
fi

echo "Installing zram-config files"
if [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "alpine" ]]; then
  install -m 755 "${BASEDIR}/zram-config" /usr/sbin/
  install -m 755 "${BASEDIR}/zram-config.openrc" /etc/init.d/zram-config
else 
  install -m 755 "${BASEDIR}/zram-config" /usr/local/sbin/
  install -m 644 "${BASEDIR}/zram-config.service" /etc/systemd/system/zram-config.service
  echo "ReadWritePaths=/usr/local/share/zram-config/log" >> /lib/systemd/system/logrotate.service
fi
install -m 644 "${BASEDIR}/ztab" /etc/ztab
mkdir -p /usr/local/share/zram-config/log
ln -s /usr/local/share/zram-config/log /var/log/zram-config
install -m 755 "${BASEDIR}/uninstall.bash" /usr/local/share/zram-config/uninstall.bash
install -m 644 "${BASEDIR}/zram-config.logrotate" /etc/logrotate.d/zram-config
mkdir -p /usr/local/lib/zram-config/
install -m 755 "${BASEDIR}/overlayfs-tools/overlay" /usr/local/lib/zram-config/overlay

if [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "alpine" ]]; then
  echo "Starting zram-config service..."
  rc-update add zram-config boot
  rc-service zram-config start
else 
  echo "Starting zram-config.service"
  systemctl daemon-reload
  systemctl enable --now zram-config.service
  until [[ $(systemctl show -p SubState --value zram-config) == "exited" ]]; do
    sleep 5
  done
fi

echo "#####     zram-config is now installed and running     #####"
echo "#####       edit /etc/ztab to configure options        #####"
