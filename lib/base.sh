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

msg() {
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
        -a) mesg="A" ;;
        -u) mesg="U" ;;
        -r) mesg="R" ;;
        *)  msg "Unknown option of logging." ;;
    esac
    shift
    echo -e "[$(date +%y%m%d%H%M)] ${mesg} $@" >>$LOG
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
}

# check value of variable
# return : no value 0; else 1
no_value() {
    local var=$1
    eval local value=\$$var
    if [[ x"$value" == x ]]; then
        return 0
    else
        return 1
    fi
}
