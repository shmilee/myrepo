#!/bin/bash
xgettext --no-location -d temp myrepo.sh
msgmerge po/zh_CN.po temp.po -o new-zh_CN.po
rm temp.po
