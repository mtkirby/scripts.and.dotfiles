#!/bin/bash
# 20261004 kirby

workdir="/var/named/chroot/var/named"
zonefile=$1
myserial=$(date +%y%m%d%H%M)
newzonefile="${zonefile}.$myserial"
filesdir="${workdir}/files"
zonetemplate="${zonefile}.template"
failsafe="${zonefile}.failsafe"

if ! cd $workdir
then
  echo "bad workdir $workdir"
  exit 1
fi
if [[ ! -f "$zonefile" ]]
then
  echo "suppy zonefile or bad zonefile $zonefile"
  exit 1
fi
if [[ ! -f "$zonetemplate" ]]
then
  echo "template file $zonetemplate does not exist"
  exit 1
fi
if [[ ! -f "$failsafe" ]]
then
  echo "failsafe file $failsafe does not exist"
  exit 1
fi


cat ${zonetemplate} |sed -e "s/MYSERIAL/$myserial/" > $newzonefile

for file in $('ls' ${filesdir}/)
do
    echo "$file IN TXT (\"\"" >> $newzonefile
    cat ${filesdir}/$file |gzip -9|base64 -w75 |sed -e 's/^/  "/' |sed -e 's/$/"/'  >> $newzonefile
    echo '  "")' >> $newzonefile
done


dnsfilelist=$(echo "$filesdir"/* |sed -e "s,$filesdir/,,g")
echo "list IN TXT (\"$dnsfilelist\"" >> $newzonefile
echo '  "")' >> $newzonefile

cat $newzonefile > $zonefile

if ! systemctl restart named-chroot
then
  echo "FAIL FAIL FAIL FAIL FAIL FAIL FAIL FAIL"
  cat $failsafe > $zonefile
  systemctl restart named-chroot
else
  ps -efwww|grep named|grep -v grep
fi
