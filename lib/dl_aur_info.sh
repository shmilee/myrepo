#!/bin/bash

## gettext initialization
export TEXTDOMAIN='myrepo'
export TEXTDOMAINDIR='/usr/share/locale'

source /etc/myrepo.conf
INFOURL="$AURURL/rpc/?v=5\&type=info"
if [ x$1 = 'x-s' ]; then
    source $(dirname $0)/base.sh
    msg2() {
        :
    }
elif [ x$1 = 'x-m' ]; then
    # used by multi-dl.py
    msg2() {
        echo $@
        sleep 0.3s
    }
    error() {
        echo $@
    }
else
    echo "!!! usage: $0 [-s|-m] [pkgname]"
    exit 1
fi
pkg=$2
file_p=$TEMP/list_info/$pkg

msg2 "$(gettext "Receiving information from AUR ...")"
if curl -LfGs --data-urlencode arg="$pkg" $INFOURL >${file_p}.tmp; then
    if [ ! -s ${file_p}.tmp ]; then
        error "$(gettext "Check you network, please.")"
        exit 1
    fi
    if grep resultcount\"\:0 2>&1 >/dev/null ${file_p}.tmp;then
        echo "0" > ${file_p}
    else
        msg2 "$(gettext "1. about Version ...")"
        sed 's/.*Version\":\"//;s/\",\".*//' ${file_p}.tmp >${file_p}
        msg2 "$(gettext "2. about tarball URL path ...")"
        echo >>${file_p}
        sed 's/^.*URLPath\":\"//;s/\",\".*//;s/\\//g' ${file_p}.tmp >>${file_p}
        msg2 "$(gettext "3. about Maintainer ...")"
        echo >>${file_p}
        sed 's/.*Maintainer\":\"//;s/\",\".*//' ${file_p}.tmp >>${file_p}
    fi
    exit 0
else
    exit 1
fi
