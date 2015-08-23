#!/bin/bash
xgettext --no-location -d temp ../bin/myrepo.sh ../lib/*
msgmerge zh_CN.po temp.po -o new-zh_CN.po
rm temp.po
