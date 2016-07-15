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

MYVER=0.9
CONF_FILE=/etc/myrepo.conf
LIBPATH=/usr/lib/myrepo

##
# BEGIN MAIN
##

if source $CONF_FILE; then
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
else
    printf "$(gettext "Lost File: %s !")" $CONF_FILE
    exit 1
fi

for file in $LIBPATH/{base.sh,utils.sh,cmds.sh}; do
    if [ -f $file ]; then
        source $file
    else
        printf "$(gettext "Lost File: %s !")" $file
        exit 1
    fi
done

for var in AURURL REPO_PATH REPO_NAME TEMP USE_COLOR SIGN; do
    if no_value $var; then
        error "$(gettext "Lost '%s', edit configure file %s.")" "$var" "$CONF_FILE"
        exit  1
    fi
done

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
        if no_value x86_64_ROOT || [ ! -d "$x86_64_ROOT" ]; then
            error "$(gettext "Lost '%s', edit configure file %s.")" "x86_64_ROOT" "$CONF_FILE"
            exit 1
        fi
        if no_value i686_ROOT || [ ! -d "$i686_ROOT" ]; then
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
