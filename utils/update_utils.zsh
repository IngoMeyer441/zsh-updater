export BOLD_LIGHT_RED='\033[91;1m'
export BOLD_LIGHT_GREEN='\033[92;1m'
export BOLD_LIGHT_YELLOW='\033[93;1m'
export BOLD_LIGHT_BLUE='\033[94;1m'
export BOLD_LIGHT_MAGENTA='\033[95;1m'
export BOLD_LIGHT_CYAN='\033[96;1m'
export NC='\033[0m'

export PRINTED_MESSAGES_LOG_FILE="${UPDATER_TMP_DIR}/log"


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
            eval "print_${PRINTED_MESSAGES[${i}]}" "\"\${PRINTED_MESSAGES[$(( i + 1 ))]}\"" "\"\${PRINTED_MESSAGES[$(( i + 2 ))]}\"" "\"false\""
        done
    fi
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

function is_in_array () {
    local elem array

    elem="$1"
    shift
    array=( "$@" )
    (( ${array[(I)${elem}]} ))
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

function query_installed_version () {
    local prefix version_query_command command_name

    prefix="$1"
    version_query_command="$2"
    command_name="${version_query_command%% *}"

    if command which "${command_name}" >/dev/null 2>&1; then
        eval "${prefix}_INSTALLED_VERSION=$(eval ${version_query_command})"
    else
        eval "${prefix}_INSTALLED_VERSION='(none)'"
    fi
}

function query_version_script () {
    local prefix command_name check_command_existence

    prefix="$1"
    command_name="$2"
    check_command_existence="$3"

    if [[ -z "${command_name}" ]]; then
        command_name="$(echo "${prefix}" | awk '{ print tolower($0) }')"
    fi
    if [[ -z "${check_command_existence}" ]] || is_in_array "${check_command_existence}" "ON" "on" "TRUE" "true"; then
        check_command_existence="1"
    else
        check_command_existence="0"
    fi

    if ! (( check_command_existence )) || command which "${command_name}" >/dev/null 2>&1; then
        if command which "${command_name}-version" >/dev/null 2>&1; then
            eval "${prefix}_INSTALLED_VERSION=$(${command_name}-version)"
            return
        fi
    fi
    eval "${prefix}_INSTALLED_VERSION='(none)'"
}

function find_installable_version () {
    local prefix url_template versions version url installed_version http_code

    prefix="$1"
    url_template="$2"
    shift; shift

    versions=( "$@" )

    for version in "${versions[@]}"; do
        eval "${prefix}_LATEST_VERSION=${version}"
        eval "${prefix}_URL=${url_template}"
        eval "url=\${${prefix}_URL}"
        eval installed_version="\${${prefix}_INSTALLED_VERSION}"
        http_code="$(curl -s -o /dev/null -I -w "%{http_code}" "${url}")"
        # Deal with web servers which do not support head requests...
        if [[ "${http_code}" -eq 403 ]]; then
            http_code="$(curl -s -o /dev/null -w "%{http_code}" "${url}")"
        fi
        # 226 and 350 are FTP status codes
        if ! is_in_array "${http_code}" 200 301 302 303 305 307 308 226 350; then
            continue
        fi
        if [[ ! "${version}" =~ ^[A-Fa-f0-9]+$ || ! "${version}" =~ ^${installed_version} ]] && \
           [[ "${version}" =~ ^[A-Fa-f0-9]+$ || "${version}" != "${installed_version}" ]]; then
            UPDATE_CONDITION_OUTPUT="v${installed_version} -> v${version}"
            return 0
        else
            if [[ "${version}" == "${versions[1]}" ]]; then
                UPDATE_CONDITION_OUTPUT="v${installed_version} is already the newest version"
            else
                UPDATE_CONDITION_OUTPUT="v${installed_version} is already the newest installable version"
            fi
            return 1
        fi
    done
    # No version was suitable -> abort
    UPDATE_CONDITION_OUTPUT="No installable version found!"
    return 2
}

function compare_installed_and_latest_version () {
    local prefix installed_version latest_version

    prefix="$1"
    eval installed_version="\${${prefix}_INSTALLED_VERSION}"
    eval latest_version="\${${prefix}_LATEST_VERSION}"
    if [[ ! "${latest_version}" =~ ^[A-Fa-f0-9]+$ || ! "${latest_version}" =~ ^${installed_version} ]] && \
       [[ "${latest_version}" =~ ^[A-Fa-f0-9]+$ || "${latest_version}" != "${installed_version}" ]]; then
        UPDATE_CONDITION_OUTPUT="v${installed_version} -> v${latest_version}"
        return 0
    else
        UPDATE_CONDITION_OUTPUT="v${installed_version} is already the newest version"
        return 1
    fi
}

function is_any_os () {
    local used_os_details os_entries os_name os_details os_detail os_matches

    used_os_details=("${(@s/;/)PLATFORM_DETAILS}")

    os_entries="$(IFS=','; echo "$*")"
    os_entries="${os_entries:l:gs/ /}"  # convert to lowercase and remove all spaces
    while [[ -n "${os_entries}" ]]; do
        if ! [[ "${os_entries}" =~ '^(([[:alnum:]]+)(\[([[:alnum:],]+)\])?)(,|$)' ]]; then
            >&2 echo "The argument \"${os_entries}\" has an invalid format."
            return 1
        fi
        os_entries="${os_entries:${#MATCH}}"
        os_name="${match[2]}"
        os_details="${match[4]}"
        if (( PLATFORM_MACOS )); then
            [[ "${os_name}" == "macos" ]] || continue
        elif (( PLATFORM_LINUX )); then
            [[ "${os_name}" == "linux" || "${os_name}" == "${PLATFORM_LINUX_DISTRO}" ]] || continue
        fi
        os_matches=1
        if [[ -n "${os_details}" ]]; then
            while IFS= read -r os_detail; do
                if ! (($used_os_details[(Ie)${os_detail}])); then
                    os_matches=0
                    break
                fi
            done < <(tr -s ',' '\n' <<< "${os_details}")
        fi
        if (( os_matches )); then
            return 0
        fi
    done

    return 1
}

function continue_if_any_os () {
    if ! is_any_os "$@"; then
        UPDATE_CONDITION_OUTPUT="Your OS is ${PLATFORM_DESCRIPTIVE_NAME}"
        return 1
    fi

    return 0
}

function skip_if_any_os () {
    if is_any_os "$@"; then
        UPDATE_CONDITION_OUTPUT="Your OS is ${PLATFORM_DESCRIPTIVE_NAME}"
        return 1
    fi

    return 0
}

# vim: ft=zsh:tw=120
