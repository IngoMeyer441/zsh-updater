export BOLD_LIGHT_RED='\033[91;1m'
export BOLD_LIGHT_GREEN='\033[92;1m'
export BOLD_LIGHT_YELLOW='\033[93;1m'
export BOLD_LIGHT_BLUE='\033[94;1m'
export BOLD_LIGHT_MAGENTA='\033[95;1m'
export BOLD_LIGHT_CYAN='\033[96;1m'
export NC='\033[0m'


function print_update () {
    printf -- "[${BOLD_LIGHT_GREEN}UPDATE${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
}

function print_skip () {
    printf -- "[${BOLD_LIGHT_YELLOW}SKIP${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
}

function print_abort () {
    printf -- "[${BOLD_LIGHT_RED}ABORT${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
}

function print_subtarget () {
    printf -- "[${BOLD_LIGHT_MAGENTA}SUBTARGET${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
}

function is_function () {
    declare -f "$1" >/dev/null
}

function last_git_tag () {
    "${UPDATER_UTILS_DIR}/update_utils.py" --last-git-tag "$(IFS=, ; echo "$*")"
}

function last_website_version () {
    "${UPDATER_UTILS_DIR}/update_utils.py" --last-website-version "$(IFS=, ; echo "$*")"
}

function create_version_script () {
    local SCRIPT_PATH="$1"
    local LATEST_VERSION="$2"

    cat <<-EOF > "${SCRIPT_PATH}"
		#!/bin/bash
		print_version () {
		    local VERSION="${LATEST_VERSION}"
		    echo "\${VERSION}"
		}
		print_version
	EOF
    [[ "$?" -eq 0 ]] || return 1
    chmod +x "${SCRIPT_PATH}"
}

# vim: ft=zsh:tw=120
