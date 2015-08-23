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
    local pkg_names=($(read_srcfile -n $1))
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
        $LIBPATH/multi-dl.py -c "$LIBPATH/dl_aur_info.sh -m %u" -u ${names[@]} -s -e -t $i
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
                $LIBPATH/dl_aur_info.sh -s $name
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
            if [[ ${loc_ver%-*} == ${aur_ver%-*} ]];then
                [ -f $SRCS/$name-${loc_ver}.src.tar.gz ] && \
                    tar --force-local -zxf $SRCS/$name-${loc_ver}.src.tar.gz $O_V -C $TEMP 
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
                error "$(gettext "Tarball of %s is broken.")" "$name:$aur_ver"
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
