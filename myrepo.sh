#!/bin/bash
##  AUTHOR : shmilee
##  EMAIL  : <echo c2htaWxlZS56anVAZ21haWwuY29tCg==|base64 -d>
##  DATE   : 2013-03-06
##  TARGET : Add, remove, check and update packages(from AUR) for my personal repo.
##  DETAIL : Here, 'package' refers to pkgs per architecture grouped by pkgbase.
##                           package.i686   => pkg1.i686   pkg2.i686   ...
##           one PKGBUILD => package.x86_64 => pkg1.x86_64 pkg2.x86_64 ...  name-ver-rel-arch.pkg .tar.xz
##                           package.any    => pkg1.any    pkg2.any    ...
##  arch=('any')
##  depends=('grep' 'pacman' 'devtools')

## gettext initialization
export TEXTDOMAIN='myrepo'
export TEXTDOMAINDIR='/usr/share/locale'

MYVER=0.8
CONF_FILE=/etc/myrepo.conf
LIBPATH=/usr/lib/myrepo
AURURL="https://aur.archlinux.org"
INFOURL="$AURURL/rpc.php?type=info"

msg() { #{{{
    local mesg=$1; shift
    printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

msg2() {
    local mesg=$1; shift
    printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

warning() {
    local mesg=$1; shift
    printf "${YELLOW}==> $(gettext "WARNING:")${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

error() {
    local mesg=$1; shift
    printf "${RED}==> $(gettext "ERROR:")${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

logging() {
    case $1 in
        -a) mesg="A-D-D-" ;;
        -u) mesg="UPDATE" ;;
        -r) mesg="REMOVE" ;;
        *)  msg "Unknown option of logging." ;;
    esac
    shift
    echo -e "[$(date +%F" "%H:%M)] ${mesg} $@" >>$LOG
}

## list "${@:3}", $1 beginning number, $2 the number of items in a row
# usage  : list  9 3 a b c d r f g
# return : 09) a;	10) b;	11) c;	
#          12) d;	13) r;	14) f;	
#          15) g;
list() {
    local n=($(seq -w $1 $((${#@}+$1-3)))) i=0 _f
    for _f in ${@:3}; do
        (($i%$2==0)) && echo -e -n "\t" # indent
        echo -e -n "${n[$i]}) $_f;\t"
        (( $i%$2 == $(($2-1)) )) && echo # \n
        ((i++))
    done
    (($i%$2==0)) ||echo # aliquant \n
} #}}}

## check REPO directories and files exist or not
# return 1, when any file or directory not exist
check_dir() { #{{{
    local dir re=0 lost=() lost_file=()
    for dir in $REPO_PATH/{os/{i686,x86_64},pool/{packages,sources},trash}; do
        [[ -d $dir ]] || lost+=($dir)
    done
    if [[ "${#lost[@]}" != "0" ]];then
        error "$(gettext "Nonexistent Directory:\n%s")" "$(list 1 1 ${lost[@]})"
        re=1
    fi
    [[ -f $LOG ]] || lost_file+=($LOG)
    [[ -f $POOLDB ]] || lost_file+=($POOLDB)
    if [[ "${#lost_file[@]}" != "0" ]];then
        error "$(gettext "Nonexistent File:\n%s")" "$(list 1 1 ${lost_file[@]})"
        re=1
    fi
    return $re
} #}}}

## initialize REPO directories and files
init_repo() { #{{{
    local YESRM=no
    if [[ x"$REPO_NAME" == x ]];then
        error "$(gettext "A name for the repository is needed.")"
        exit 1
    fi
    if [[ -d $REPO_PATH ]];then
        warning "$(gettext "Directory %s has been existent, remove it?")" "$REPO_PATH"
        warning "$(gettext "Think twice before you remove all files in %s !")" "$REPO_PATH"
        read -p "==> $(gettext "Press 'yes' to continue, any other to skip: ")" YESRM
        [[ "$YESRM" == "yes" ]] && rm -rv $REPO_PATH/* || exit 2
    fi
    msg "$(gettext "Initializing repository %s in %s ...")" "$REPO_NAME"  "$REPO_PATH"
    msg "$(gettext "%s Creating directories:\n%s")" "1)" "$(list 1 1 os/{i686,x86_64} pool/{packages,sources} trash)"
    if ! mkdir -p $O_V $REPO_PATH/{os/{i686,x86_64},pool/{packages,sources},trash};then
        error "$(gettext "Failed to create directories.")"
        exit 3
    fi
    msg "$(gettext "%s Creating files:\n%s")" "2)" "$(list 1 1 $REPO_NAME.log pool/pool.db.tar.gz)"
    echo "[$(date +%F" "%H:%M)] initialize $REPO_NAME" > $REPO_PATH/$REPO_NAME.log
    > $REPO_PATH/pool/list_AUR && cd $REPO_PATH/pool && (tar zcf $POOLDB list_AUR; rm list_AUR)
    if [[ "$?" != "0" ]];then
        error "$(gettext "Failed to create %s !")" "$POOLDB"
        exit 4
    fi
    msg "$(gettext "Finish initializing repository %s.")" "$REPO_NAME"
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
}

## $1 included in "$2 $3 ..." or not
# usage  : inclusion [$1] [$2 $3]...
# return : 0,included; 1,not included
inclusion() {
    local s
    for s in ${@:2}; do
        if [[ $s == $1 ]];then
            return 0
        fi
    done
    return 1
} #}}}

## get the information of package named $2 from aur, write it in file $TEMP/list_info/$2
# usage  : get_aur_info [-l|-e|-v|-p|-m] [foo]
# return : -l) write information to the file
#          -e) exist or not in AUR
#          -v) get version(ver-rel) from the file
#          -p) get tarball download URL
#          -m) get maintainer
get_aur_info() { #{{{
    case $1 in
        -l)
            local aur_pkg_info=$(curl -LfGs --data-urlencode arg="$2" "$INFOURL")
            if [[ x"$aur_pkg_info" == x ]];then
                error "$(gettext "Check you network, please.")"
                return 1
            elif echo $aur_pkg_info|grep resultcount\"\:0 2>&1 >/dev/null;then
                echo "0" >$TEMP/list_info/$2
            else
                echo $aur_pkg_info|sed 's/.*Version\":\"//;s/\",\"CategoryID.*//' >$TEMP/list_info/$2
                echo $aur_pkg_info|sed 's/^.*URLPath\":\"//;s/\"\}\}//;s/\\//g' >>$TEMP/list_info/$2
                echo $aur_pkg_info|sed 's/.*Maintainer\":\"//;s/\",\"ID.*//' >>$TEMP/list_info/$2
            fi
            ;;
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
# usage  : read_srcfile [-n|-a] [path/to/srcfile] [package-name]
# return : -n) get pkg names
#          -a) get more information
read_srcfile() { #{{{
    mkdir $TEMP/pkgbuild
    tar --force-local -zx -C $TEMP/pkgbuild -f $2 $3/PKGBUILD 2>&1 >/dev/null
    case $1 in
        -n)
            if grep ^pkgbase $TEMP/pkgbuild/$3/PKGBUILD 2>&1 >/dev/null;then # more than one pkg
                local num=$(grep ^license $TEMP/pkgbuild/$3/PKGBUILD -n -m1|cut -d: -f1)
                sed -n "1,${num}p" $TEMP/pkgbuild/$3/PKGBUILD > $TEMP/pkgbuild/$3/PKGBUILD_n
                source $TEMP/pkgbuild/$3/PKGBUILD_n
                echo ${pkgname[@]}
                unset pkgbase pkgname pkgver
            else # only one pkg
                echo $3
            fi
            ;;
        -a)
            : # name or names? version? desc??? url??
            ;;
        *)
            msg "Unknown option of read_srcfile."
            return 1
            ;;
    esac
    rm -r $TEMP/pkgbuild
} #}}}

## makepkg x86_64 i686, sourcefile
# usage  : dual_makepkg [tarball extract path]
dual_makepkg() { #{{{
    local name=$(basename $1)
    cd $1

    if ! makepkg --allsource; then
        BUILD_RESULT="No source file build!"
        return 1
    fi
    if ! makechrootpkg -r $x86_64_ROOT; then
        BUILD_RESULT="No pkg build!"
        return 2
    fi
    ls *any.pkg.tar* 2>/dev/null >/dev/null # arch=any?
    #build i686 package in x86_64, when arch != any
    if [ "$?" != 0 -a x"$i686_ROOT" != x -a "$(uname -m)" == "x86_64" ];then
        BUILD_RESULT="$(uname -m) pkg build, "
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
}

## ln pkgs and signatures that should exist in $PKGS to repo, add(remove) pkgs to database
# usage  : ln_repo_db [-a|-r] [PkgFileName]
ln_repo_db() {
    local _a _pf=$2 oldp oldlns anti_O_V
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
            repo-add $anti_O_V $dir/$REPO_NAME.db.tar.gz $dir/$_pf
            repo-add $anti_O_V -f $dir/$REPO_NAME.files.tar.gz $dir/$_pf
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
            repo-remove $anti_O_V $dir/$REPO_NAME.db.tar.gz "$(get_namver -n $_pf)"
            repo-remove $anti_O_V -f $dir/$REPO_NAME.files.tar.gz "$(get_namver -n $_pf)"
            msg2 "$(gettext "(%s)Done.")" "$_a"
        done
    else
        msg "Unknown option of ln_repo_db."
    fi
} #}}}

## add package to repo, $1 = source file
# usage  : add_package [path/to/source/file]
add_package() { #{{{
    [[ x"$1" == x ]] && return 1
    echo $1|grep src.tar 2>&1 >/dev/null
    if [ "$?" != "0" -o ! -f $1 ];then
        error "$(gettext "Cannot find source file: %s !")" "$1"
        return 2
    fi
    local _na _pf _arch _a dir pkg_files=()
    local srcpath=$(dirname $1) srcfile=$(basename $1)
    local name=$(get_namver -n $srcfile) version=$(get_namver -v $srcfile)
    # get pkg file names
    local pkg_names=($(read_srcfile -n $1 $name))
    for _na in ${pkg_names[@]}; do
        pkg_files+=($(get_files -p $srcpath $_na $version))
    done
    if [[ "${#pkg_files[@]}" == "0" ]];then
        error "$(gettext "Package %s has not been built, do it youself please.")" "$name"
        return 3
    fi
    # add to pool
    local _UPDATE=0 old_version TOREPO=0 # default do not add pkgs to os/{i686,x86_64}
    if [[ "$(get_newest $(info_pool_db -v $name) $version)" == "$version" ]];then
        TOREPO=1 # $version >= newest in pool
        if info_pool_db -e $name;then
            _UPDATE=1; old_version=$(get_newest $(info_pool_db -v $name))
            msg "$(gettext "Update package %s from %s to %s ...")" "$name" "$old_version" "$version"
        fi
    else
        warning "$(gettext "%s is not the latest version, and will add to %s only, without repo in %s.")"\
            "$name:$version" "$REPO_PATH/pool/" "$REPO_PATH/os/"
    fi
    if info_pool_db -e $name/$version;then
        warning "$(gettext "Package %s that exists in REPO %s will be overwrited!")" "$name:$version" "$REPO_NAME"
    fi

    if [[ "${#pkg_files[@]}" == "1" ]];then
        msg "$(gettext "Adding package %s with pkg %s to REPO: %s ...")" "$name:$version" "$pkg_files" "$REPO_NAME"
    else
        msg "$(gettext "Adding package %s to REPO: %s, with %s pkgs:\n%s")"\
            "$name:$version" "$REPO_NAME" "${#pkg_files[@]}" "$(list 1 1 ${pkg_files[@]})"
    fi
    # ADD_VERIFY
    if [ x$ADD_VERIFY == x0 ];then
        read -p "==> $(gettext "Press ENTER to continue, any other to skip: ")" SSTTOOPP
        [[ x"$SSTTOOPP" == x ]] || return 0
    fi
    msg2 "$(gettext "Copying source file %s ...")" "$srcfile"
    cp ${O_V} $srcpath/$srcfile $SRCS
    for _pf in ${pkg_files[@]}; do
        msg2 "$(gettext "Copying pkg file %s ...")" "$_pf"
        cp ${O_V} $srcpath/$_pf $PKGS
        if [[ "$SIGN" == "1" ]];then
            msg2 "$(gettext "Use USER-ID %s to sign pkg %s ...")" "$USER_ID" "$_pf"
            [ -f $PKGS/$_pf.sig ] && rm ${O_V} $PKGS/$_pf.sig
            gpg --detach-sign --use-agent -u $USER_ID $PKGS/$_pf
        fi
        if [[ "$TOREPO" == "1" ]];then
            ln_repo_db -a $_pf
        fi
    done
    msg "$(gettext "Renew pool database %s ...")" "$POOLDB"
    mkdir $TEMP/pooldb
    if tar zxf $POOLDB -C $TEMP/pooldb;then
        cd $TEMP/pooldb
        [[ -d $name ]] || mkdir $name
        echo ${pkg_files[@]}|sed 's/ /\n/g' > $name/$version
        retar_pooldb
    else
        error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
        return 4
    fi
    # add to log
    if [[ "$_UPDATE" == "1" ]];then
        logging -u "$name ($old_version=>$version)"
    elif [[ "$TOREPO" == "1" ]];then
        logging -a "$name ($version)"
    else
        logging -a "$name (old:$version)"
    fi
    msg "$(gettext "Finish adding package %s to REPO: %s.")" "$name:$version" "$REPO_NAME"
} #}}}

## remove package from REPO, $1 = package name
# usage  : remove_package [Package-Name]
# mv srcfile and pkgfiles into $TRASH/$PackageName-$version-$(date +%Y%m%d-%H%M%S)
remove_package() { #{{{
    local name=$1
    local versions rmones=() leftones=() select
    local i ver _pf newest trash_dir
    if info_pool_db -e $name;then
        versions=($(info_pool_db -v $name))
        newest=$(get_newest ${versions[@]})
        if ((${#versions[@]}>1));then
            msg "$(gettext "Find %s versions of package %s in %s:\n%s")"\
                "${#versions[@]}" "$name" "$REPO_NAME" "$(list 0 1 ${versions[@]})"
            read -p "==> $(gettext "Enter Numbers to remove (e.g. 0 3 5): ")" -a select
            if [[ x"$select" == x ]];then
                msg "$(gettext "No package removed!")"
                return 1
            fi
            for i in $(seq 0 $((${#versions[@]}-1))); do
                if inclusion $i ${select[@]};then
                    rmones+=(${versions[$i]})
                else
                    leftones+=(${versions[$i]})
                fi
            done
        else
            msg "$(gettext "Find one package %s in %s to remove.")" "$name:$versions" "$REPO_NAME"
            read -p "==> $(gettext "Press ENTER to continue, any other to skip: ")" SSTTOOPP
            if [[ x"$SSTTOOPP" != x ]];then
                msg "$(gettext "No package removed!")"
                return 1
            fi
            rmones=($versions); leftones=()
        fi
        # begin
        mkdir $TEMP/pooldb
        if ! tar zxf $POOLDB -C $TEMP/pooldb;then
            error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
            return 1
        fi
        # repo-db
        if [[ x"$leftones" == x ]];then
            msg "$(gettext "Removing package %s from repo-db of %s ...")" "$name" "$REPO_NAME"
            for _pf in $(cat $TEMP/pooldb/$name/$newest); do
                ln_repo_db -r $_pf
            done
        else
            if ! inclusion $newest ${leftones[@]};then
                msg "$(gettext "Downgrading package %s from %s to %s in repo-db of %s ...")"\
                    "$name" "$newest" "$(get_newest ${leftones[@]})" "$REPO_NAME"
                for _pf in $(cat $TEMP/pooldb/$name/$newest); do
                    ln_repo_db -r $_pf
                done
                for _pf in $(cat $TEMP/pooldb/$name/$(get_newest ${leftones[@]})); do
                    ln_repo_db -a $_pf
                done
            else
                : # newest is in leftones, nothing to do with repo-db
            fi
        fi
        # files in pool ==> $TRASH
        for ver in ${rmones[@]}; do
            msg "$(gettext "Removing package %s from pool ...")" "$name:$ver"
            trash_dir=$TRASH/$name-$ver-$(date +%Y%m%d-%H%M%S)
            mkdir $trash_dir
            msg2 "$(gettext "Removing source file %s ...")" "$name-$ver.src.tar.gz"
            mv ${O_V} $SRCS/$name-$ver.src.tar.gz $trash_dir/
            for _pf in $(cat $TEMP/pooldb/$name/$ver); do
                msg2 "$(gettext "Removing pkg file %s ...")" "$_pf"
                mv ${O_V} $PKGS/$_pf $trash_dir/
                if [[ -f $PKGS/$_pf.sig ]];then
                    msg2 "$(gettext "Removing pkg file signature %s ...")" "$_pf.sig"
                    mv ${O_V} $PKGS/$_pf.sig $trash_dir/
                fi
            done
            msg "$(gettext "Done.")"
        done
        # $POOLDB
        msg "$(gettext "Renew pool database %s ...")" "$POOLDB"
        if [[ x"$leftones" == x ]];then
            rm -r $TEMP/pooldb/$name
            sed -i "/^${name}$/d" $TEMP/pooldb/list_AUR # list_AUR
        else
            for ver in ${rmones[@]}; do
                rm $TEMP/pooldb/$name/$ver
            done
        fi
        retar_pooldb
        # add to log
        if [[ x"$leftones" == x ]];then
            logging -r "$name (all)"
            msg "$(gettext "Finish removing package %s from REPO: %s.")" "$name" "$REPO_NAME"
        else
            ver="${rmones[@]}"
            logging -r "$name ($ver)"
            msg "$(gettext "Finish removing package %s (versions %s) from REPO: %s.")" "$name" "$ver" "$REPO_NAME"
        fi
    else
        warning "$(gettext "Package %s do not exist in repo.")" "$name"
        return 1
    fi
} #}}}

## check repo, link, signature and so on
check_repo() { #{{{
    local name i ver vers newest sfile pfile sta _a arch gpg_check plost=() olost=()
    local names=($(info_pool_db -n))
    # about ONLY_PKGS
    if [ "${#ONLY_PKGS[@]}" != 0 ];then
        for name in ${names[@]}; do
            if ! inclusion $name ${ONLY_PKGS[@]};then # not in ONLY_PKGS
                IGNORE_PKGS+=($name)
            fi
        done
    fi
    mkdir $TEMP/{check,pooldb}
    if ! tar zxf $POOLDB -C $TEMP/pooldb;then
        error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
        return 1
    fi
    ls $SRCS > $TEMP/check/sourcefiles.list
    ls $PKGS > $TEMP/check/pkgfiles.list
    basename -a $(ls $REPO_PATH/os/i686/*pkg.tar* 2>/dev/null) 2>/dev/null > $TEMP/check/i686.pkglist
    basename -a $(ls $REPO_PATH/os/x86_64/*pkg.tar* 2>/dev/null) 2>/dev/null > $TEMP/check/x86_64.pkglist
    get_repo_filename i686 > $TEMP/check/i686.repodb
    get_repo_filename x86_64 > $TEMP/check/x86_64.repodb
    msg "$(gettext "Checking %s packages in REPO %s ...\n%s")" "${#names[@]}" "$REPO_NAME" "$(list 1 4 ${names[@]})"
    i=0
    for name in ${names[@]}; do
        ((i++))
        msg "$(gettext "(%s/%s) %s : Checking package ...")" "$i" "${#names[@]}" "$name"
        vers=($(info_pool_db -v $name))
        if inclusion $name ${IGNORE_PKGS[@]};then
            msg2 "$(gettext "Ignore.")"
            for sfile in $(get_files -s $SRCS $name); do
                sed -i "/^$sfile$/d" $TEMP/check/sourcefiles.list
            done
            for ver in ${vers[@]}; do
                for pfile in $(cat $TEMP/pooldb/$name/$ver); do
                    sed -i "/^$pfile$/d;/^$pfile.sig$/d" $TEMP/check/pkgfiles.list \
                        $TEMP/check/i686.pkglist $TEMP/check/x86_64.pkglist \
                        $TEMP/check/i686.repodb $TEMP/check/x86_64.repodb
                done
            done
        else
            # pool
            if [ ${#vers[@]} !=  "1" ];then
                sta="${RED}${#vers[@]}${ALL_OFF}${BOLD}"
            else
                sta="${GREEN}${#vers[@]}${ALL_OFF}${BOLD}"
            fi
            msg2 "$(gettext "%s versions(%s) in pool.")" "$sta" "${vers[*]}"
            for ver in ${vers[@]}; do
                sta=""
                if [[ ! -f $SRCS/$name-$ver.src.tar.gz ]];then
                    sta+="source_file_lost,_"
                else
                    sed -i "/$name-$ver.src.tar.gz/d" $TEMP/check/sourcefiles.list
                fi
                for pfile in $(cat $TEMP/pooldb/$name/$ver); do
                    if [[ ! -f $PKGS/$pfile ]];then
                        sta+="${pfile}_lost,_"
                    else
                        if ! gpg --verify $PKGS/$pfile.sig $PKGS/$pfile 2>/dev/null >/dev/null;then
                            sta+="${pfile}.sig_broken,_"
                        fi
                        sed -i "/^$pfile$/d;/^$pfile.sig$/d" $TEMP/check/pkgfiles.list
                    fi
                done
                if [[ x"$sta" != x ]];then
                    plost+=("$name:${ver}___${sta}_OVER.")
                fi
            done
            # os
            newest=$(get_newest ${vers[@]})
            msg2 "$(gettext "Latest version %s in os.")" "$newest"
            sta=""
            for pfile in $(cat $TEMP/pooldb/$name/$newest); do
                arch=${pfile##*-}; arch=${arch%.pkg.tar*}
                [[ "$arch" == "any" ]] && arch="i686 x86_64"
                for _a in $arch; do
                    gpg_check=0
                    if [[ ! -L $REPO_PATH/os/$_a/$pfile ]];then
                        sta+="$pfile(${_a})_link_lost,_"
                    elif [[ ! -f $REPO_PATH/os/$_a/$pfile ]];then
                        sta+="$pfile(${_a})_file_lost,_"
                    else
                        ((gpg_check++))
                    fi
                    if [[ ! -L $REPO_PATH/os/$_a/${pfile}.sig ]];then
                        sta+="${pfile}.sig(${_a})_link_lost,_"
                    elif [[ ! -f $REPO_PATH/os/$_a/${pfile}.sig ]];then
                        sta+="${pfile}.sig(${_a})_file_lost,_"
                    else
                        ((gpg_check++))
                    fi
                    if [[ $gpg_check == 2 ]];then
                        if ! gpg --verify $REPO_PATH/os/$_a/$pfile.sig $REPO_PATH/os/$_a/$pfile 2>/dev/null >/dev/null;then
                            sta+="$pfile(${_a})_verify_error,_"
                        fi
                    fi
                    sed -i "/^$pfile$/d;/^$pfile.sig$/d" $TEMP/check/$_a.pkglist
                    if grep ^$pfile$ $TEMP/check/$_a.repodb 2>&1 >/dev/null;then
                        sed -i "/$pfile/d" $TEMP/check/$_a.repodb
                    else
                        sta+="$pfile(${_a})_lost_in_repodb,_"
                    fi
                done
            done
            if [[ x"$sta" != x ]];then
                olost+=("$name:${newest}___${sta}_OVER.")
            fi
            # list_AUR
        fi
    done
    rm -r $TEMP/pooldb
    # report
    msg "$(gettext "Report:")"
    msg "$(gettext "%s In %s")" "1)" "$REPO_PATH/pool/"
    if [[ x"$plost" == x ]];then
        msg2 "$(gettext "All files are fine.")"
    else
        msg2 "$(gettext "Some packages are wrong:\n%s")" "$(list 1 1 ${plost[@]})"
    fi
    msg "$(gettext "%s In %s")" "2)" "$REPO_PATH/os/"
    if [[ x"$olost" == x ]];then
        msg2 "$(gettext "All files are fine.")"
    else
        msg2 "$(gettext "Some packages are wrong:\n%s")" "$(list 1 1 "${olost[@]}")"
    fi
    msg "$(gettext "%s Excess files:")" "3)"
    sta="$(basename -a $(ls -s $TEMP/check/*|awk '$1!=0{print $2}') 2>/dev/null)"
    if [[ x"$sta" != x ]];then
        for _a in $sta; do
            pfile="$(cat $TEMP/check/$_a)"
            case $_a in
                sourcefiles.list) msg2 "$(gettext "In %s:\n%s")" "$SRCS" "$(list 1 1 $pfile)" ;;
                pkgfiles.list) msg2 "$(gettext "In %s:\n%s")" "$PKGS" "$(list 1 1 $pfile)" ;;
                i686.pkglist) msg2 "$(gettext "In %s:\n%s")" "$REPO_PATH/os/i686" "$(list 1 1 $pfile)" ;;
                i686.repodb) msg2 "$(gettext "In %s:\n%s")" "$REPO_PATH/os/i686/$REPO_NAME.db(files).tar.gz" "$(list 1 1 $pfile)" ;;
                x86_64.pkglist) msg2 "$(gettext "In %s:\n%s")" "$REPO_PATH/os/x86_64" "$(list 1 1 $pfile)" ;;
                x86_64.repodb) msg2 "$(gettext "In %s:\n%s")" "$REPO_PATH/os/x86_64/$REPO_NAME.db(files).tar.gz" "$(list 1 1 $pfile)" ;;
                *) msg "wrong file." ;;
            esac
        done
    else
        msg2 "$(gettext "None.")"
    fi
    #msg "$(gettext "%s In %s")" "4)" "list_AUR"
} #}}}

## edit list_AUR
edit_aurlist() { #{{{
    local name names ins outs=() comm todo
    mkdir $TEMP/pooldb
    if ! tar zxf $POOLDB -C $TEMP/pooldb;then
        error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
        return 1
    fi
    names=($(info_pool_db -n))
    ins=($(cat $TEMP/pooldb/list_AUR))
    for name in ${names[@]}; do
        if ! inclusion $name ${ins[@]};then
            outs+=($name)
        fi
    done
    msg "$(gettext "%s packages in REPO: %s.")" "${#names[@]}" "$REPO_NAME"
    msg "$(gettext "%s packages in list_AUR:\n%s")" "${#ins[@]}" "$(list 1 3 ${ins[@]})"
    msg "$(gettext "%s packages not in list_AUR:\n%s")" "${#outs[@]}" "$(list 1 3 ${outs[@]})"
    DDOONNEE=0
    while true; do
        msg "$(gettext "Use 'add [names]' or 'del [names]' to add(delete) package to(from) list_AUR.")"
        msg "$(gettext "Use 'finish' to exit this loop.")"
        read -p "==> $(gettext "Enter you command: ")" -a comm
        todo=()
        for name in ${comm[@]:1}; do
            if inclusion $name ${names[@]};then
                todo+=($name)
            else
                msg2 "$(gettext "Ignore %s, because %s is not in %s.")" "$name" "$name" "$POOLDB"
            fi
        done
        if [ "${#todo[@]}" == 0 -a "${comm[0]}" == add -o "${#todo[@]}" == 0 -a "${comm[0]}" == del ];then
            msg2 "$(gettext "Nothing to do with list_AUR.")"
        else
            case ${comm[0]} in
                add)
                    msg2 "$(gettext "Adding %s to list_AUR ...")" "${todo[*]}"
                    ins=($(cat $TEMP/pooldb/list_AUR)) # add more than once
                    echo ${ins[@]} ${todo[@]} | sed 's/ /\n/g' |sort -u > $TEMP/pooldb/list_AUR
                    msg2 "$(gettext "Done.")"
                    ((DDOONNEE++))
                    ;;
                del)
                    msg2 "$(gettext "deleting %s from list_AUR ...")" "${todo[*]}"
                    for name in ${todo[@]}; do
                        sed -i "/^$name$/d" $TEMP/pooldb/list_AUR
                    done
                    msg2 "$(gettext "Done.")"
                    ((DDOONNEE++))
                    ;;
                finish) break ;;
                *) msg "$(gettext "Unknown command.")" ;;
            esac
        fi
    done
    if [[ "$DDOONNEE" == 0 ]];then
        msg "$(gettext "No change of list_AUR, no need to renew pool database %s ...")" "$POOLDB"
    else
        msg "$(gettext "Renew pool database %s ...")" "$POOLDB"
        retar_pooldb
        msg "$(gettext "Done.")"
    fi
} #}}}

## update packages in 'list_AUR' from AUR
update_aur() { #{{{
    local names name _up info loc_ver aur_ver tarballURL i
    local up_name=() suc_name=() fal_name=() los_name=()
    mkdir $TEMP/pooldb
    if ! tar zxf $POOLDB -C $TEMP/pooldb;then
        error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
        return 1
    fi
    names=($(cat $TEMP/pooldb/list_AUR))
    rm -r $TEMP/pooldb
    msg "$(gettext "There are %s packages in list_AUR:\n%s")" "${#names[@]}" "$(list 1 4 ${names[@]})"
    # about ONLY_PKGS
    if [ "${#ONLY_PKGS[@]}" != 0 ];then
        for name in ${names[@]}; do
            if ! inclusion $name ${ONLY_PKGS[@]};then
                IGNORE_PKGS+=($name)
            fi
        done
    fi
    # get information and todolist
    GET_NEW_INFO=0
    if [ -d $TEMP/list_info ];then
        [[ $(date +%Y%d%H) -le $(date +%Y%d%H -r $TEMP/list_info) ]] && GET_NEW_INFO=1
    else
        mkdir $TEMP/list_info
    fi
    # multi get AUR information
    if [ x$O_M == xY ];then
        GET_NEW_INFO=1
        if [[ ${#names[@]} -gt 20 ]];then
            i=20
        else
            i=${#names[@]}
        fi
        msg "$(gettext "We will begin to get information of these packages from AUR in 3 seconds.")"
        sleep 3s
        $LIBPATH/multi-dl.py -c "$LIBPATH/get_aur_info.sh %u" -u ${names[@]} -s -e -t $i
    fi
    i=0
    for name in ${names[@]}; do
        ((i++))
        if inclusion $name ${IGNORE_PKGS[@]};then # about IGNORE_PKGS
            msg "$(gettext "(%s/%s) %s : Ignore.")" "$i" "${#names[@]}" "$name"
        else
            if [ "$GET_NEW_INFO" == 1 -a -f $TEMP/list_info/$name ];then
                msg "$(gettext "(%s/%s) %s : Use just received information from AUR.")" "$i" "${#names[@]}" "$name"
            else
                # 1)no list_info dir, or the dir is old; 2) the dir is new, but no file for pkg '$name'; 3) multi get failed
                msg "$(gettext "(%s/%s) %s : Receiving information from AUR ...")" "$i" "${#names[@]}" "$name"
                get_aur_info -l $name
            fi
            get_aur_info -e $name; info=$?  ## 0:exist; 1: not exist; 2: net error
            if [ $info == 0 ];then
                loc_ver=$(get_newest $(info_pool_db -v $name))
                [ x$loc_ver == x ]&& loc_ver=0.0.0
                aur_ver=$(get_aur_info -v $name)
                [ x$aur_ver == x ]&& aur_ver=0.0.0
                if [ x$O_V != x ];then
                    msg2 "$(gettext "local newest : %s; aur version : %s")" "$loc_ver" "$aur_ver"
                fi
                if [ "$loc_ver" != "$aur_ver" -a "$(get_newest $loc_ver $aur_ver)" == "$aur_ver" ];then
                    up_name+=("${name}::$loc_ver==>$aur_ver")
                    msg2 "${GREEN}$(gettext "Need to update")"
                else
                    msg2 "$(gettext "No need to update")"
                fi
            elif [ $info == 1 ];then
                msg2 "${RED}$(gettext "NotFound")"
                los_name+=("$name")
            fi
        fi
    done
    if [ "${#up_name[@]}" == 0 ];then
        msg "$(gettext "Overview, no package need to update.")"
    else
        msg "$(gettext "Overview, %s packages need to update:\n%s")" "${#up_name[@]}" "$(list 1 1 ${up_name[@]})"
        read -p "==> $(gettext "Press ENTER to continue, any other to skip: ")" SSTTOOPP
        [[ x"$SSTTOOPP" != x ]] && exit 1
        # begin update
        i=0
        for _up in ${up_name[@]}; do
            name=${_up%::*} # _up, pkc::loc==>aur
            _up=${_up#*::} # _up, loc==>aur
            loc_ver=${_up%==*}
            aur_ver=$(get_aur_info -v $name)
            tarballURL=$AURURL$(get_aur_info -p $name)
            ((i++))
            msg "$(gettext "(%s/%s) Updating package %s(%s=>%s) from AUR")" "$i" "${#up_name[@]}" "$name" "$loc_ver" "$aur_ver"
            # pkgver-pkgrel, if pkgver is same, then no need to download sources again.
            if [ ${locVer%-*} == ${aurVer%-*} ];then
                [ -f $SRCS/$name-$locVer.src.tar.gz ] && \
                    tar --force-local -zxf $SRCS/$name-$locVer.src.tar.gz $O_V -C $TEMP 
            fi
            # get tarball and extract to $TEMP
            if curl -Lfs $tarballURL |tar xfz - -C $TEMP $O_V;then
                BUILD_RESULT=""
                version_changed $TEMP/$name
                dual_makepkg $TEMP/$name
                if [ "$?" != 0 ];then
                    error "$(gettext "Failed to run \`makepkg\`: %s")" "$BUILD_RESULT"
                    fal_name+=("$name")
                else
                    if [ -f $TEMP/$name/$name-newver ]; then
                        srcfile=$(get_newest $(get_files -s $TEMP/$name/ $name))
                        aur_ver=$(get_namver -v $srcfile)
                    fi
                    add_package $TEMP/$name/$name-$aur_ver.src.tar.gz
                    msg "$(gettext "Update package %s(%s=>%s) from AUR, done.")" "$name" "$loc_ver" "$aur_ver"
                    suc_name+=("$name")
                fi
            else
                error "$(gettext "Tarball of %s is broken.")" "$name:$aurVer"
                fal_name+=("$name")
            fi
        done
        msg "$(gettext "Report:")"
        msg2 "$(gettext "Finish updating %s packages.")" "${#up_name[@]}"
        msg2 "$(gettext "Success: %s\n%s")" "${#suc_name[@]}" "$(list 1 1 ${suc_name[@]})"
        msg2 "$(gettext "Fail: %s\n%s")" "${#fal_name[@]}" "$(list 1 1 ${fal_name[@]})"
    fi

    if [ "${#los_name[@]}" != 0 ];then
        msg "$(gettext "%s packages not found in AUR:\n%s")" "${#los_name[@]}" "$(list 1 1 ${los_name[@]})"
        msg "$(gettext "These packages may be moved into repo community, or your network cannot connect to AUR %s.")" "$AURURL"
    fi
} #}}}

## update git and svn packages
update_git() { #{{{
    local git_names=($(echo $(info_pool_db -n) | sed 's/ /\n/g' | grep -E '\-git$|\-svn$'))
    local name suc_name=() pas_name=() i srcfile old_pkgs ver nVer
    if [ "${#git_names[@]}" == 0 ];then
        msg "$(gettext "Overview, no git or svn package in repo: %s.")" "$REPO_NAME"
    else
        msg "$(gettext "Overview, %s git or svn packages need to update:\n%s")" "${#git_names[@]}" "$(list 1 1 ${git_names[@]})"
        i=0
        [[ -d $TEMP/git-svn ]] && rm -r $TEMP/git-svn
        mkdir $TEMP/git-svn
        for name in ${git_names[@]}; do
            ((i++))
            msg "$(gettext "(%s/%s) %s :")" "$i" "${#git_names[@]}" "$name"
            ver=""; srcfile=""
            read -p "==> $(gettext "Press ENTER to continue, any other to skip: ")" SSTTOOPP
            if [ x"$SSTTOOPP" != x ];then
                pas_name+=($name)
                continue
            fi
            ver=$(get_newest $(info_pool_db -v $name))
            srcfile=$(get_files -s $SRCS $name "$ver")
            if tar --force-local -zx ${O_V} -C $TEMP/git-svn -f $SRCS/$srcfile;then
                if version_changed $TEMP/git-svn/$name; then
                    # makepkg
                    BUILD_RESULT=""
                    dual_makepkg $TEMP/git-svn/$name/
                    if [ "$?" != 0 ];then
                        error "$(gettext "Failed to run \`makepkg\`: %s")" "$BUILD_RESULT"
                        pas_name+=($name)
                    else
                        # get new version pkg
                        cd $TEMP/git-svn/$name/
                        srcfile=$(get_newest $(get_files -s . $name))
                        nVer=$(get_namver -v $srcfile)
                        add_package $name-${nVer}.src.tar.gz
                        msg "$(gettext "Update package %s(%s=>%s) from AUR, done.")" "$name" "$ver" "$nVer"
                        suc_name+=("$name")
                    fi
                else
                    msg "$(gettext "No new version, PASS.")"
                    pas_name+=($name)
                fi
            else
                error "$(gettext "Ignore.")"
                pas_name+=($name)
            fi
        done
        msg "$(gettext "Report:")"
        msg2 "$(gettext "Finish updating %s packages.")" "${#git_names[@]}"
        msg2 "$(gettext "Success: %s\n%s")" "${#suc_name[@]}" "$(list 1 1 ${suc_name[@]})"
        msg2 "$(gettext "Pass: %s\n%s")" "${#pas_name[@]}" "$(list 1 1 ${pas_name[@]})"
    fi
} #}}}

## search package in repo, packages or pkgs. key = $1
search_repo() { #{{{
    local key=$1 name
    # first, search package names
    msg "$(gettext "In package names:")"
    echo $(info_pool_db -n) | sed 's/ /\n/g' | grep --color=auto $key
    msg "$(gettext "In pkg file names:")"
    mkdir $TEMP/pooldb
    if ! tar zxf $POOLDB -C $TEMP/pooldb;then
        error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
        return 1
    fi
    cd $TEMP/pooldb
    rm list_AUR
    grep -R --color=auto $key
    msg "$(gettext "Done.")"
} #}}}

## get the information of package named $1. name = $1
info_package() { #{{{
    local name=$1 versions ver src pkg pkgs i=0
    if info_pool_db -e $name;then
        versions=($(info_pool_db -v $name))
        mkdir $TEMP/pooldb
        if ! tar zxf $POOLDB -C $TEMP/pooldb;then
            error "$(gettext "%s may be broken, check it by youself!")" "$POOLDB"
            return 1
        fi
        msg "$(gettext "Find %s versions of package %s in %s:\n%s")"\
                "${#versions[@]}" "$name" "$REPO_NAME" "$(list 1 1 ${versions[@]})"
        for ver in ${versions[@]}; do
            ((i++)); unset src pkgs
            echo
            msg "$(gettext "(%s/%s) %s :")" "$i" "${#versions[@]}" "$name-$ver"
            src=$(get_files -s $SRCS $name $ver)
            msg2 "$(gettext "Source file : %s(%s, %s)")"\
                "$src" "$(ls -hl $SRCS/$src|awk '{print $5}')" "$(date +%F-%H:%M -r $SRCS/$src)"
            for pkg in $(cat $TEMP/pooldb/$name/$ver); do
                pkgs+=("$pkg,($(ls -hl $PKGS/$pkg|awk '{print $5}'),$(date +%F-%H:%M -r $PKGS/$pkg))")
            done
            msg2 "$(gettext "pkg files :\n%s")" "$(list 1 1 ${pkgs[@]})"
            if [ x$O_V == xxxxxxx ];then # not work now
                msg2 "$(gettext "More information :\n%s")" "$(read_srcfile -a $SRCS/$src $name)"
            fi

        done
    else
        msg "$(gettext "Package %s do not exist in repo.")" "$name"
    fi
} #}}}

version() { #{{{
    # cat arrow|gzip|base64 
    printf -- "\n$(echo -e "H4sIABkXNFIAA1PQqtPjUtBSUFDXU4CB3Mqi1IJ8hTLVYrCMgkIMlFawhqpwzi+oLMpMzyhR0EjW\n\
    VACqs81JTbW1ta0BYm07mGorqGq4OfoKqCJ66kBKV50LADkEIH6FAAAA"|openssl base64 -d|gzip -d)\n\n" \
    "$MYVER" \
    "2013 shmilee <shmilee.zju@gmail.com>"\
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

# check value of variable
# return : no value 0; else 1
no_va() { #{{{
    local var=$1
    eval local value=\$$var
    if [[ x"$value" == x ]]; then
        return 0
    else
        return 1
    fi
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

##
# BEGIN MAIN
##

if [ -f $CONF_FILE ]; then
    source $CONF_FILE
    for var in REPO_PATH REPO_NAME TEMP USE_COLOR SIGN; do
        if no_va $var; then
            error "$(gettext "Lost '%s', edit configure file %s.")" "$var" "$CONF_FILE"
            exit  1
        fi
    done
else
    error "$(gettext "Lost configure file %s !")" "$CONF_FILE"
    exit 1
fi

# using color
unset ALL_OFF BOLD BLUE GREEN RED YELLOW
if [[ $USE_COLOR = "y" ]]; then
    # prefer terminal safe colored and bold text when tput is supported
    if tput setaf 0 &>/dev/null; then
        ALL_OFF="$(tput sgr0)"
        BOLD="$(tput bold)"
        BLUE="${BOLD}$(tput setaf 4)"
        GREEN="${BOLD}$(tput setaf 2)"
        RED="${BOLD}$(tput setaf 1)"
        YELLOW="${BOLD}$(tput setaf 3)"
    else
        ALL_OFF="\e[1;0m"
        BOLD="\e[1;1m"
        BLUE="${BOLD}\e[1;34m"
        GREEN="${BOLD}\e[1;32m"
        RED="${BOLD}\e[1;31m"
        YELLOW="${BOLD}\e[1;33m"
    fi
fi
readonly ALL_OFF BOLD BLUE GREEN RED YELLOW

## REPO TREE
# $REPO_PATH
# ├── $REPO_NAME.log
# ├── os
# │   ├── i686
# │   └── x86_64
# ├── pool
# │   ├── packages
# │   ├── pool.db.tar.gz
# │   └── sources
# └── trash
SRCS=$REPO_PATH/pool/sources
PKGS=$REPO_PATH/pool/packages
POOLDB=$REPO_PATH/pool/pool.db.tar.gz
LOG=$REPO_PATH/$REPO_NAME.log
TRASH=$REPO_PATH/trash
#AURLIST=$REPO_PATH/pool/pool.db.tar.gz(list_AUR)

# Options
O_V="" #option for being verbose
O_M="N" # multi threads
OPT_SHORT="A:CEhI:mR:S:UVv"
OPT_LONG="add:,check,clean,editaur,git,help,info:,init,ignore:,multi,only:,remove:,search:,update,verbose,version"
if ! OPT_TEMP="$(getopt -q -o $OPT_SHORT -l $OPT_LONG -- "$@")";then
    usage;exit 1
fi
eval set -- "$OPT_TEMP"
unset OPT_SHORT OPT_LONG OPT_TEMP

OPER=''
IGNORE_PKGS=()
ONLY_PKGS=()
while true; do
    case $1 in
        -A|--add)     shift; SRC_PATH=$1; OPER+='A ' ;;
        -C|--check)   OPER+='C ' ;;
        -E|--editaur) OPER+='E ' ;;
        -I|--info)    shift; INFO_NAME=$1; OPER+='I ' ;;
        -R|--remove)  shift; PKG_NAME=$1; OPER+='R ' ;;
        -S|--search)  shift; SEARCH_KEY=$1; OPER+='S ' ;;
        -U|--update)  OPER+='U ' ;;
        -v|--verbose) O_V+="-v" ;;
        -m|--multi)   O_M="Y" ;;
        -V|--version) version; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        --init)       init_repo; exit 0 ;;
        --clean)      rm -I -rv $TEMP; exit 0 ;;
        --ignore)     shift; IGNORE_PKGS+=($(echo $1|sed 's/,/ /g')) ;;
        --only)       shift; ONLY_PKGS+=($(echo $1|sed 's/,/ /g'));;
        --git)        OPER+='G ';;
        --)           OPT_IND=0; shift; break ;;
        *)            usage; exit 1 ;;
    esac
    shift
done

# lock file
if [ -f $TEMP/myrepo.lock ];then
    error "$(gettext " A myrepo is running!")"
    msg "$(gettext "If you're sure a myrepo is not already running, you can remove %s.")" "$TEMP/myrepo.lock"
    exit 1
fi

# check repo directories
if ! check_dir;then
    msg "$(gettext "Some REPO directories or files do not exist. Use '--init' to initialize repo, or check them by youself!")"
    exit 2
fi

if [[ x"$OPER" == x ]];then
    echo
    msg "$(gettext "At least one operation of '%s', please.")" "-A -C -E -I -R -S -U --git, -h --clean or --init"
    echo; usage; exit 0
else
    # temp files
    if [[ -d $TEMP ]];then
        warning "$(gettext "All files in %s will be removed !")" $TEMP
        read -p "==> $(gettext "Press ENTER to continue, any other to skip: ")" SSTTOOPP
        [[ x"$SSTTOOPP" == x ]] && rm -r $TEMP
    fi
    if ! mkdir -p $TEMP;then
        error "$(gettext "Failed to create %s !")" "$TEMP"
        exit 4
    fi
    # create lock file
    echo $$ >$TEMP/myrepo.lock
    trap '{ rm $TEMP/myrepo.lock; } 2>/dev/null' EXIT
    # check_user_id with -A -C -U --git
    if echo $OPER|grep -E 'A|C|U|G' >/dev/null;then
        check_user_id
    fi
    # check chrootdir with -U --git
    if echo $OPER|grep -E 'U|G' >/dev/null;then
        if no_va x86_64_ROOT || [ ! -d "$x86_64_ROOT" ]; then
            error "$(gettext "Lost '%s', edit configure file %s.")" "x86_64_ROOT" "$CONF_FILE"
            exit 1
        fi
        if no_va i686_ROOT || [ ! -d "$i686_ROOT" ]; then
            warning "$(gettext "Lost '%s', edit configure file %s.")" "i686_ROOT" "$CONF_FILE"
        fi
    fi
    # operations, ADD_VERIFY=1, false
    for oper in $OPER; do
        case $oper in
            A) ADD_VERIFY=0; add_package $SRC_PATH ;;
            C) check_repo ;;
            E) edit_aurlist ;;
            G) ADD_VERIFY=0; update_git ;;
            I) info_package $INFO_NAME ;;
            R) remove_package $PKG_NAME ;;
            S) search_repo $SEARCH_KEY ;;
            U) ADD_VERIFY=1; update_aur ;;
            *) msg "Unknown option." ;;
        esac
    done
fi
exit 0
