#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
############################################################
# update centmin mod 130.00beta01 & newer's optional
# geoip2 lite nginx module's database for geoip2 city
############################################################
# Maxmind GeoLite2 database API Key
# https://community.centminmod.com/posts/80656/
# You can override this API key with your own Maxmind
# account API key by setting MM_LICENSE_KEY variable 
# in persistent config file /etc/centminmod/custom_config.inc
MM_LICENSE_KEY='k0sP8JPgZm6i0sOF'
LOCALCENTMINMOD_MIRROR='https://centminmod.com'
############################################################
if [ -f /etc/centminmod/custom_config.inc ]; then
  . /etc/centminmod/custom_config.inc
fi
############################################################
if [ ! -f /etc/centminmod/custom_config.inc ]; then
  CHECK_CMM_MM_LICENSE_KEY=''
else
  CHECK_CMM_MM_LICENSE_KEY=$(awk -F '=' '/MM_LICENSE_KEY/ {print $2}' /etc/centminmod/custom_config.inc | sed -e 's| ||g' | sed -e 's|"||g' -e "s|'||g")
fi
if [[ "$MM_LICENSE_KEY" ]]; then
  echo
  maxmind_city_url="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=$MM_LICENSE_KEY&suffix=tar.gz"
  maxmind_country_url="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=$MM_LICENSE_KEY&suffix=tar.gz"
  maxmind_asn_url="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key=$MM_LICENSE_KEY&suffix=tar.gz"
else
  echo
  maxmind_city_url='${LOCALCENTMINMOD_MIRROR}/centminmodparts/geoip2-lite/GeoLite2-City.tar.gz'
  maxmind_country_url='${LOCALCENTMINMOD_MIRROR}/centminmodparts/geoip2-lite/GeoLite2-Country.tar.gz'
  maxmind_asn_url='${LOCALCENTMINMOD_MIRROR}/centminmodparts/geoip2-lite/GeoLite2-ASN.tar.gz'
fi

geoiptwo_updater() {
  mkdir -p /usr/share/GeoIP
  pushd /usr/share/GeoIP
  echo "------------------------------------------------------"
  echo "GeoLite2 City database download ..."
  echo "------------------------------------------------------"
  echo
  GEOIPTWOCITYDATA_CURLCHECK=$(curl -${ipv_forceopt}Is --connect-timeout 30 --max-time 30 "$maxmind_city_url" | grep 'HTTP\/' | grep '200' >/dev/null 2>&1; echo $?)  
  # only overwrite existing downloaded file if the download url is working
  # if download doesn't work, do not overwrite existing downloaded file
  if [[ "$GEOIPTWOCITYDATA_CURLCHECK" = '0' ]]; then
    if [ -f /usr/share/GeoIP/GeoLite2-City.mmdb ] ; then
      ls -lah /usr/share/GeoIP/GeoLite2-City.mmdb
    fi
    wget -4 "$maxmind_city_url" -O /usr/share/GeoIP/GeoLite2-City.tar.gz
  fi
  tar xzf /usr/share/GeoIP/GeoLite2-City.tar.gz -C /usr/share/GeoIP
  cp -a GeoLite2-City_*/GeoLite2-City.mmdb /usr/share/GeoIP/GeoLite2-City.mmdb
  rm -rf GeoLite2-City_*

  echo "------------------------------------------------------"
  echo "GeoLite2 Country database download ..."
  echo "------------------------------------------------------"
  GEOIPTWOCOUNTRYDATA_CURLCHECK=$(curl -${ipv_forceopt}Is --connect-timeout 30 --max-time 30 "$maxmind_country_url" | grep 'HTTP\/' | grep '200' >/dev/null 2>&1; echo $?)
  # only overwrite existing downloaded file if the download url is working
  # if download doesn't work, do not overwrite existing downloaded file
  if [[ "$GEOIPTWOCOUNTRYDATA_CURLCHECK" = '0' ]]; then
    if [ -f /usr/share/GeoIP/GeoLite2-Country.mmdb ]; then
      ls -lah /usr/share/GeoIP/GeoLite2-Country.mmdb
    fi
    wget -4 "$maxmind_country_url" -O /usr/share/GeoIP/GeoLite2-Country.tar.gz
  fi
  tar xzf /usr/share/GeoIP/GeoLite2-Country.tar.gz -C /usr/share/GeoIP
  cp -a GeoLite2-Country_*/GeoLite2-Country.mmdb /usr/share/GeoIP/GeoLite2-Country.mmdb
  rm -rf GeoLite2-Country_*

  echo "------------------------------------------------------"
  echo "GeoLite2 ASN database download ..."
  echo "------------------------------------------------------"
  GEOIPTWOASNDATA_CURLCHECK=$(curl -${ipv_forceopt}Is --connect-timeout 30 --max-time 30 "$maxmind_asn_url" | grep 'HTTP\/' | grep '200' >/dev/null 2>&1; echo $?)
  # only overwrite existing downloaded file if the download url is working
  # if download doesn't work, do not overwrite existing downloaded file
  if [[ "$GEOIPTWOASNDATA_CURLCHECK" = '0' ]]; then
    wget -4 "$maxmind_asn_url" -O /usr/share/GeoIP/GeoLite2-ASN.tar.gz
  fi
  tar xzf /usr/share/GeoIP/GeoLite2-ASN.tar.gz -C /usr/share/GeoIP
  cp -a GeoLite2-ASN_*/GeoLite2-ASN.mmdb /usr/share/GeoIP/GeoLite2-ASN.mmdb
  rm -rf GeoLite2-ASN_*

  # restart services
  if [[ "$(service nginx status >/dev/null 2>&1; echo $?)" -eq '0' ]]; then
    service nginx restart >/dev/null 2>&1
  fi
  if [[ "$(service php-fpm status >/dev/null 2>&1; echo $?)" -eq '0' ]]; then
    service php-fpm restart >/dev/null 2>&1
  fi

  echo "------------------------------------------------------"
  echo "Check GeoIP2 Lite Databases"
  echo "------------------------------------------------------"
  ls -lah /usr/share/GeoIP/GeoLite2-City.mmdb /usr/share/GeoIP/GeoLite2-Country.mmdb /usr/share/GeoIP/GeoLite2-ASN.mmdb
  echo
  echo "/usr/local/nginx-dep/bin/mmdblookup --file /usr/share/GeoIP/GeoLite2-Country.mmdb --ip 8.8.8.8 country names en"
  /usr/local/nginx-dep/bin/mmdblookup --file /usr/share/GeoIP/GeoLite2-Country.mmdb --ip 8.8.8.8 country names en
  echo
  echo "/usr/local/nginx-dep/bin/mmdblookup --file /usr/share/GeoIP/GeoLite2-ASN.mmdb --ip 8.8.8.8 autonomous_system_number"
  /usr/local/nginx-dep/bin/mmdblookup --file /usr/share/GeoIP/GeoLite2-ASN.mmdb --ip 8.8.8.8 autonomous_system_number
  echo
  echo "/usr/local/nginx-dep/bin/mmdblookup --file /usr/share/GeoIP/GeoLite2-ASN.mmdb --ip 8.8.8.8 autonomous_system_organization"
  /usr/local/nginx-dep/bin/mmdblookup --file /usr/share/GeoIP/GeoLite2-ASN.mmdb --ip 8.8.8.8 autonomous_system_organization
  echo
  popd
}

geoiptwo_updater
exit 0