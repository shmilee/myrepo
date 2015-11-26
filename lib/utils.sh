## check REPO directories and files exist or not
# return 1, when any file or directory not exist
check_dir() { #{{{
    local dir re=0 lost=()
    for dir in $REPO_PATH/{os/{i686,x86_64},pool/{packages,sources},trash}; do
        [[ -d $dir ]] || lost+=($dir)
    done
    if [[ "${#lost[@]}" != "0" ]];then
        error "$(gettext "Lost Directory:\n%s")" "$(list 1 1 ${lost[@]})"
        re=1
    fi
    if [ ! -f $LOG ]; then
        error "$(gettext "Lost File: %s !")" $LOG
        re=1
    fi
    if [ ! -f $POOLDB ]; then
        error "$(gettext "Lost File: %s !")" $POOLDB
        re=1
    fi
    return $re
} #}}}

# if SIGN packages, check USER_ID for Gnupg
check_user_id() { #{{{
    if [ $SIGN != 1 ];then
        return 0
    fi
    if no_va USER_ID; then
        error "$(gettext "Lost '%s', edit configure file %s.")" "USER_ID" "$CONF_FILE"
        exit 1
    fi
    msg "$(gettext "Checking key signatures for '%s' ...")" "$USER_ID"
    if ! gpg --check-sigs $USER_ID >/dev/null; then
        exit 1
    fi
} #}}}

## get version or pkg name from file name, such as pkg-name-ver-rel{-arch.pkg,.src}.tar.gz
# usage  : get_namver [-v|-n] [FileName]
# return : ver-rel, pkg-name
get_namver() { #{{{
    local act=$1 file=$2
    local name ver rel

    if echo $file|grep src.tar 2>&1 >/dev/null;then
        file=${file%.src.tar*}
    elif echo $file|grep pkg.tar 2>&1 >/dev/null;then
        file=${file%-*}
    else
        msg "File $file should be src or pkg."
        return 1
    fi
    case $act in
        -n)
            file=${file%-*}; name=${file%-*}
            echo $name
            ;;
        -v)
            rel=${file##*-}; file=${file%-*}
            ver=${file##*-}
            echo $ver-$rel
            ;;
        *)
            msg "Unknown option of get_namver."
            ;;
    esac
} #}}}

## get the string of package files or source files in $2 named $3, -p need $4 optionally
#  usage  : get_files [-s|-p] [path/to/directory] [PkgName] [Version|ARCH]
#  return : -s) PkgName-1.0-1.src.tar.gz PkgName-2.0-2.src.tar.gz ...
#           -p) PkgName-1.0-3-x86_64.pkg.tar.xz PkgName-2.0-1-x86_64.pkg.tar.xz ...
get_files() { #{{{
    local _s files
    case $1 in
        -s)
            # find $2 -name $3*$4*src.tar.gz, here optional $4 should be version
            files=($(basename -a $(ls $2/$3*$4*src.tar* 2>/dev/null) 2>/dev/null))
            ;;
        -p)
            files=($(basename -a $(ls $2/$3*$4*pkg.tar* 2>/dev/null) 2>/dev/null|sed '/.*.sig$/d'))
            if [ "${#files[@]}" == "0" ];then
                files=($(basename -a $(ls $2/$3*pkg.tar* 2>/dev/null) 2>/dev/null|sed '/.*.sig$/d'))
            fi
            ;;
        *)
            msg "Unknown option of get_files."
            ;;
    esac
    for _s in ${files[@]}; do
        [[ "$(get_namver -n $_s)" == "$3" ]] && echo -n $_s" "
    done
} #}}}

## get newest version, $@ = list of files or versions
# usage  : get_newest [PkgName-1.0-1.src.tar.gz PkgName-2.0-2.src.tar.gz]...
#          get_newest [1.0-1 2.0-2]...
# return : PkgName-2.0-2.src.tar.gz or 2.0-2
get_newest() { #{{{
    if [[ ${#@} == 1 ]];then
        echo $1
    else
        # use sort -V
        echo $@ | sed 's/ /\n/g' | sort -rV | head -n1
    fi
} #}}}

## get the information of package named $2 from aur, write it in file $TEMP/list_info/$2
# usage  : get_aur_info [-e|-v|-p|-m] [foo]
# return : -e) exist or not in AUR
#          -v) get version(ver-rel) from the file
#          -p) get tarball download URL
#          -m) get maintainer
get_aur_info() { #{{{
    case $1 in
        -e)
            if [ -f $TEMP/list_info/$2 ];then
                if [ "$(cat $TEMP/list_info/$2 2>/dev/null)" == 0 ];then
                    return 1
                else
                    return 0
                fi
            else
                return 2
            fi
            ;;
        -v) awk 'NR==1 {print $1}' $TEMP/list_info/$2 2>/dev/null ;;
        -p) awk 'NR==2 {print $1}' $TEMP/list_info/$2 2>/dev/null ;;
        -m) awk 'NR==3 {print $1}' $TEMP/list_info/$2 2>/dev/null ;;
        *)
            msg "Unknown option of get_aur_info."
            return 1
            ;;
    esac
} #}}}

## get package information form repo db file
# usage  : get_repo_filename [ARCH] [PkgName]
# return : filename
# if PkgName not given, return all the filenames; if package not found in repo-db, return 0
get_repo_filename() { #{{{
    local name=$2
    local _arch=$1
    local db_path=$REPO_PATH/os/$_arch/$REPO_NAME.db.tar.gz
    local files tardir _p lp

    # pacman -b $REPO_PATH/os/$1/ -Si $name, $REPO_PATH/os/$1/sync/$REPO_NAME.db should exist

    if [ x"$name" != x ];then
        files=($(tar -tvf $db_path 2>/dev/null|grep ^d.*$name|awk 'sub(/\//,"",$6){print $6}'))
        for _p in ${files[@]}; do
            lp=${_p%-*} # e.g. adobe-air-2.1-1 adobe-air-sdk-2.6-4
            [[ "${lp%-*}" == "$name" ]] && tardir="$_p"
        done
        if [ x"$tardir" != x ];then
            tar zx -C $TEMP -f $db_path $tardir/desc 2>/dev/null
            awk 'NR==2 {print $1}' $TEMP/$tardir/desc
            rm -r $TEMP/$tardir
        else
            echo 0
        fi
    else
        # list all
        mkdir $TEMP/$_arch
        tar zx --wildcards -C $TEMP/$_arch -f $db_path */desc 2>/dev/null
        find $TEMP/$_arch -type f -exec awk 'NR==2 {print $1}' {} \;
        rm -r $TEMP/$_arch
    fi
} #}}}

## read the PKGBUILD in source file
# usage  : read_srcfile [-n|-a|-m] [path/to/srcfile | path/to/PKGBUILD]
# return : -n) get pkg names
#          -a) get arch
#          -m) get more information
read_srcfile() { #{{{
    mkdir $TEMP/pkgbuild
    if [[ $(basename $2) == PKGBUILD ]]; then
        local PKGBUILD_path=$2
    else
        local _name=$(get_namver -n $(basename $2))
        tar --force-local -zx -C $TEMP/pkgbuild -f $2 $_name/PKGBUILD 2>&1 >/dev/null
        local PKGBUILD_path=$TEMP/pkgbuild/$_name/PKGBUILD
    fi
    local num=$(grep -E '^install|^url|^license|^options|^arch' $PKGBUILD_path -n 2>/dev/null \
        | cut -d: -f1 | sort -n -r | head -n1)
    sed -n "1,${num}p" $PKGBUILD_path > $TEMP/pkgbuild/PKGBUILD_tmp
    source $TEMP/pkgbuild/PKGBUILD_tmp
    case $1 in
        -n)
            echo ${pkgname[@]}
            ;;
        -a)
            echo ${arch[@]}
            ;;
        -m)
            : # name or names? version? desc??? url??
            ;;
        *)
            msg "Unknown option of read_srcfile."
            return 1
            ;;
    esac
    unset pkgbase pkgname pkgver pkgrel pkgdesc arch url depends source license
    rm -r $TEMP/pkgbuild
} #}}}

## makepkg x86_64 i686, sourcefile
# usage  : dual_makepkg [tarball extract path]
dual_makepkg() { #{{{
    local name=$(basename $1)
    local arch=$(read_srcfile -a $1/PKGBUILD)
    if [ x"$arch" == xany ]; then
        arch=x86_64 # arch==any, build package in $x86_64_ROOT
    fi
    cd $1

    if ! makepkg --allsource; then
        BUILD_RESULT="No source file build!"
        return 1
    fi
    # arch==any, arch==i686 x86_64, arch==x86_64
    if inclusion x86_64 $arch; then
        if ! makechrootpkg -r $x86_64_ROOT; then
            BUILD_RESULT="No pkg build!"
            return 2
        fi
        BUILD_RESULT="x86_64 (or any) pkg build. "
    fi
    # build i686 package, when arch==i686, arch==i686 x86_64
    if inclusion i686 $arch; then
        if [ x"$i686_ROOT" == x ]; then
            BUILD_RESULT="i686 pkg failed. Lost 'i686_ROOT' directory."
            return 3
        fi
        msg "$(gettext "Chrooting into %s to Build i686 package.")" "$i686_ROOT"
        makechrootpkg -r $i686_ROOT
        if [[ $? != 0 ]];then
            msg "$(gettext "Build i686 package .. failed.")"
            BUILD_RESULT+="i686 pkg failed."
            return 3
        fi
        # merge src file
        local srcname=$(ls $name-*-*.src.tar*)
        mv $srcname x64-$srcname
        tar --force-local -tf x64-$srcname|sort >x86_64_src_tmp
        makechrootpkg -r $i686_ROOT -- --allsource
        tar --force-local -tf $srcname|sort >i686_src_tmp
        if ! diff i686_src_tmp x86_64_src_tmp 2>&1 >/dev/null;then
            msg "$(gettext "Merging two different source files ...")"
            tar --force-local -zxf x64-$srcname
            tar --force-local -zxf $srcname
            rm x64-$srcname $srcname
            tar --force-local -zcf $srcname $name/
            msg "$(gettext "Done.")"
        fi
        BUILD_RESULT+="i686 pkg build."
    fi
    return 0
} #}}}

# change version for git or svn ...
# usage  : version_changed [tarball extract path]
version_changed() { #{{{
    local name=$(basename $1)
    cd $1
    local oldVer=$(awk '/^pkgver=/,sub(/pkgver=/,"",$1){printf $1}' PKGBUILD |sed -e 's/"//g' -e "s/'//g")
    makepkg -o
    local newVer=$(awk '/^pkgver=/,sub(/pkgver=/,"",$1){printf $1}' PKGBUILD |sed -e 's/"//g' -e "s/'//g")
    if [ "$oldVer" != "$newVer" ];then
        echo $newVer > $name-newver #newVersion file
        return 0
    else
        return 1
    fi
} #}}}

## do this after changing files in $TEMP/pooldb
retar_pooldb() { #{{{
    mv $POOLDB $POOLDB.old
    cd $TEMP/pooldb
    if tar zcf $POOLDB * ;then
        cd $TEMP && rm -r $TEMP/pooldb
    else
        error "$(gettext "Renew pool database failed.")"
        cp $POOLDB.old $POOLDB
    fi
} #}}}

## get information from $POOLDB
# usage  : info_pool_db [-e PackageName|PackageName/version] [-n] [-v PackageName]
# return : -e) PackageName or PackageName/version exist(0) or not(1)
#          -n) list all names in pool, if null, return 2
#          -v) list all versions of PackageName, if not exist, return 3
info_pool_db() { #{{{
    case $1 in
        -e)
            if tar tf $POOLDB $2 2>/dev/null >/dev/null;then
                return 0
            else
                return 1
            fi
            ;;
        -n)
            local names=$(tar -tvf $POOLDB 2>/dev/null|grep ^d|awk 'sub(/\//,"",$6){print $6}')
            if [[ x"$names" == x ]];then
                return 2
            else
                echo $names
            fi
            ;;
        -v)
            local vers=$(basename -a $(tar --wildcards -tf $POOLDB $2/ 2>/dev/null|sed '/\/$/d') 2>/dev/null)
            if [[ x"$vers" == x ]];then
                return 3
            else
                echo $vers
            fi
            ;;
        *) msg "Unknown option of info_pool_db." ;;
    esac
} #}}}

## ln pkgs and signatures that should exist in $PKGS to repo, add(remove) pkgs to database
# usage  : ln_repo_db [-a|-r] [PkgFileName]
ln_repo_db() { #{{{
    local _a _pf=$2 oldp oldlns anti_O_V _repo_sign
    local name=$(get_namver -n $_pf)
    local _arch=${_pf##*-}; _arch=${_arch%.pkg.tar*}
    [[ "$_arch" == "any" ]] && _arch="i686 x86_64" # if arch='any', let's do it twice

    if [[ ! -f $PKGS/$_pf ]];then
        error "$(gettext "This should never happen to you !")"
        exit 1
    fi
    if [[ x"$O_V" == x ]];then
        anti_O_V="-q"
    fi
    if [[ "$SIGN" == "1" ]];then
        _repo_sign="-s -k $USER_ID"
    fi
    if [[ "$1" == "-a" ]];then
        for _a in $_arch; do
            dir=$REPO_PATH/os/$_a
            msg2 "$(gettext "Adding pkg %s to repo database (%s) ...")" "$_pf" "$_a"
            msg2 "$(gettext "Making links for %s ...")" "$_pf"
            # remove old links
            oldlns="$(get_files -p $dir $name)"
            if [[ x"$oldlns" != x ]];then
                msg2 "$(gettext "Remove old links first ...")"
                for oldp in $oldlns; do
                    rm ${O_V} $dir/$oldp
                    [ -L $dir/$oldp.sig ] && rm ${O_V} $dir/$oldp.sig
                done
            fi
            ln -s ${O_V} ../../pool/packages/$_pf $dir/$_pf
            [ -f $PKGS/$_pf.sig ] && ln -s ${O_V} ../../pool/packages/$_pf.sig $dir/$_pf.sig
            msg2 "$(gettext "Renew repo database (%s) ...")" "$_a"
            repo-add $anti_O_V $_repo_sign $dir/$REPO_NAME.db.tar.gz $dir/$_pf
            repo-add $anti_O_V $_repo_sign -f $dir/$REPO_NAME.files.tar.gz $dir/$_pf
            msg2 "$(gettext "(%s)Done.")" "$_a"
        done
    elif [[ "$1" == "-r" ]];then
        for _a in $_arch;do
            dir=$REPO_PATH/os/$_a
            msg2 "$(gettext "Removing pkg %s from repo database (%s) ...")" "$_pf" "$_a"
            msg2 "$(gettext "Remove links for %s ...")" "$_pf"
            [ -L $dir/$_pf ] && rm ${O_V} $dir/$_pf
            [ -L $dir/$_pf.sig ] && rm ${O_V} $dir/$_pf.sig
            msg2 "$(gettext "Renew repo database (%s) ...")" "$_a"
            repo-remove $anti_O_V $_repo_sign $dir/$REPO_NAME.db.tar.gz "$(get_namver -n $_pf)"
            repo-remove $anti_O_V $_repo_sign -f $dir/$REPO_NAME.files.tar.gz "$(get_namver -n $_pf)"
            msg2 "$(gettext "(%s)Done.")" "$_a"
        done
    else
        msg "Unknown option of ln_repo_db."
    fi
} #}}}

version() { #{{{
    # cat arrow|gzip|base64 
    printf -- "\n$(echo -e "H4sIABkXNFIAA1PQqtPjUtBSUFDXU4CB3Mqi1IJ8hTLVYrCMgkIMlFawhqpwzi+oLMpMzyhR0EjW\n\
    VACqs81JTbW1ta0BYm07mGorqGq4OfoKqCJ66kBKV50LADkEIH6FAAAA"|openssl base64 -d|gzip -d)\n\n" \
    "$MYVER" \
    "2013-2015 shmilee <shmilee.zju@gmail.com>"\
    "$(gettext 'This program may be freely redistributed under')" \
    "$(gettext 'the terms of the GNU General Public License.')"
} #}}}

usage() { #{{{
    printf "myrepo %s\n" "$MYVER"
    printf -- "$(gettext "Usage: %s [options]")\n" "$(basename $0)"
    echo
    printf -- "$(gettext "Options:")\n"
    printf -- "$(gettext "  -A, --add <p/srcfile>  add package into repo")\n"
    printf -- "$(gettext "  -C, --check            check repo, link, signature and so on")\n"
    printf -- "$(gettext "  -E, --editaur          edit 'list_AUR'")\n"
    printf -- "$(gettext "  -I, --info             view package information")\n"
    printf -- "$(gettext "  -R, --remove <pkg>     remove package from repo")\n"
    printf -- "$(gettext "  -S, --search <key>     search package in your repo")\n"
    printf -- "$(gettext "  -U, --update           update packages in 'list_AUR' from AUR")\n"
    printf -- "$(gettext "  -m, --multi            get AUR information with multi threads")\n"
    printf -- "$(gettext "  -v, --verbose          be verbose")\n"
    printf -- "$(gettext "  -V, --version          show version information and exit")\n"
    printf -- "$(gettext "  -h, --help             print this usage guide")\n"
    printf -- "$(gettext "  --init                 initialize repo")\n"
    printf -- "$(gettext "  --clean                clean up temporary files in %s")\n" "$TEMP"
    printf -- "$(gettext "  --ignore <packages>    ignore packages (Format: package1,package2,...)")\n"
    printf -- "$(gettext "  --only <packages>      only do with these packages (Format as --ignore)")\n"
    printf -- "$(gettext "  --git                  force update git svn packages with local srcfiles")\n"
    echo
    printf -- "$(gettext "Notes:")\n"
    printf -- "$(gettext "%s Here, 'package' refers to pkgs per architecture grouped by pkgbase.")\n" "1)"
    printf -- "$(gettext "%s With option -A, pkgs you have built must be in the same DIR with srcfile.")\n" "2)"
    printf -- "$(gettext "%s With option -R, package will be removed into %s.")\n" "3)" "$TRASH"
    printf -- "$(gettext "%s Option --ignore or --only, only work with option -C or -U to save your time.")\n" "4)"
    printf -- "$(gettext "%s Use option --git after -U is a good choice.")\n" "5)"
    echo
} #}}}
