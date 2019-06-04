export BOLD_LIGHT_RED='\033[91;1m'
export BOLD_LIGHT_GREEN='\033[92;1m'
export BOLD_LIGHT_YELLOW='\033[93;1m'
export BOLD_LIGHT_BLUE='\033[94;1m'
export BOLD_LIGHT_MAGENTA='\033[95;1m'
export BOLD_LIGHT_CYAN='\033[96;1m'
export NC='\033[0m'

export PRINTED_MESSAGES_LOG_FILE="$(mktemp)"


function add_entry_to_printed_messages () {
    printf -- "%s\n%s\n%s\n" "$1" "$2" "$3" >> "${PRINTED_MESSAGES_LOG_FILE}"
}

function print_summary () {
    local i
    PRINTED_MESSAGES=( "${(@f)$(<${PRINTED_MESSAGES_LOG_FILE})}" )
    if [[ "${#PRINTED_MESSAGES}" -gt 0 ]]; then
        printf -- "[${BOLD_LIGHT_BLUE}SUMMARY${NC}] "
        printf -- '=%.0s' {1..70}
        printf -- "\n"
        for (( i = 1; i <= ${#PRINTED_MESSAGES}; i += 3 )); do
            eval "print_${PRINTED_MESSAGES[${i}]}" \"${PRINTED_MESSAGES[$(( i + 1 ))]}\" \"${PRINTED_MESSAGES[$(( i + 2 ))]}\" \"false\"
        done
    fi
    rm -f "${PRINTED_MESSAGES_LOG_FILE}"
}

function print_update () {
    printf -- "[${BOLD_LIGHT_GREEN}UPDATE${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
    case "$3" in
        no|false|0)
            return 0
            ;;
    esac
    add_entry_to_printed_messages "update" "$1" "$2"
}

function print_skip () {
    printf -- "[${BOLD_LIGHT_YELLOW}SKIP${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
    case "$3" in
        no|false|0)
            return 0
            ;;
    esac
    add_entry_to_printed_messages "skip" "$1" "$2"
}

function print_abort () {
    printf -- "[${BOLD_LIGHT_RED}ABORT${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
    case "$3" in
        no|false|0)
            return 0
            ;;
    esac
    add_entry_to_printed_messages "abort" "$1" "$2"
}

function print_subtarget () {
    printf -- "[${BOLD_LIGHT_MAGENTA}SUBTARGET${NC}] ${BOLD_LIGHT_CYAN}%s... %s${NC}\n" "$1" "$2"
    case "$3" in
        no|false|0)
            return 0
            ;;
    esac
    add_entry_to_printed_messages "subtarget" "$1" "$2"
}

function is_function () {
    declare -f "$1" >/dev/null
}

function last_git_tag () {
    "${UPDATER_UTILS_DIR}/update_utils.py" --last-git-tag "$(IFS=, ; echo "$*")"
}

function last_git_tags () {
    "${UPDATER_UTILS_DIR}/update_utils.py" --multi-version --last-git-tag "$(IFS=, ; echo "$*")"
}

function last_website_version () {
    "${UPDATER_UTILS_DIR}/update_utils.py" --last-website-version "$(IFS=, ; echo "$*")"
}

function last_website_versions () {
    "${UPDATER_UTILS_DIR}/update_utils.py" --multi-version --last-website-version "$(IFS=, ; echo "$*")"
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
