#!/bin/bash

source /etc/myrepo.conf

_URL=https://aur.archlinux.org/rpc.php?type=info
_pkg=$1
_file_p=$TEMP/list_info/$_pkg

echo "Receiving information from AUR ..."
if curl -LfGs --data-urlencode arg="$_pkg" $_URL >${_file_p}.tmp; then
    if grep resultcount\"\:0 2>&1 >/dev/null ${_file_p}.tmp;then
        echo "0" > ${_file_p}
    else
        echo "1) about Version ..."; sleep 0.5s
        sed 's/.*Version\":\"//;s/\",\"CategoryID.*//' ${_file_p}.tmp >${_file_p}
        echo "2) about tarball URL path ..."; sleep 0.5s; echo >>${_file_p}
        sed 's/^.*URLPath\":\"//;s/\"\}\}//;s/\\//g' ${_file_p}.tmp >>${_file_p}
        echo "3) about Maintainer ..."; sleep 0.5s; echo >>${_file_p}
        sed 's/.*Maintainer\":\"//;s/\",\"ID.*//' ${_file_p}.tmp >>${_file_p}
    fi
fi
