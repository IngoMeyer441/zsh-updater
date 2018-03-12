export UPDATER_ROOT_DIR="${0:h}"
fpath+="${UPDATER_ROOT_DIR}/completion"

function update () (
    function init_variables () {
        export UPDATER_SCRIPTS_DIR="${UPDATER_ROOT_DIR}/update_scripts"
        export UPDATER_UTILS_DIR="${UPDATER_ROOT_DIR}/utils"
        export UPDATE_ORDER_PATH="${UPDATER_SCRIPTS_DIR}/update_order"
        export UPDATE_EXTRA_DEFINITIONS="${UPDATER_SCRIPTS_DIR}/extra_definitions.zsh"
        [[ -f "${UPDATE_EXTRA_DEFINITIONS}" ]] || export UPDATE_EXTRA_DEFINITIONS=""
        if [[ "$(uname)" == "Darwin" ]]; then
            export PLATFORM_MACOS=1
            export PLATFORM_LINUX=0
        else
            export PLATFORM_MACOS=0
            export PLATFORM_LINUX=1
        fi
        if (( ${PLATFORM_LINUX} )); then
            export PLATFORM_LINUX_DISTRO="unknown"
            [[ -f "/etc/redhat-release" ]] && export PLATFORM_LINUX_DISTRO="centos"
            [[ -f "/etc/debian_version" ]] && export PLATFORM_LINUX_DISTRO="debian"
            case "${PLATFORM_LINUX_DISTRO}" in
                centos)
                    if which lsb_release >/dev/null 2>&1; then
                        export PLATFORM_LINUX_DISTRO_VERSION="$(lsb_release -r | awk '{ print $2 }')"
                        export PLATFORM_LINUX_DISTRO_MAJOR_VERSION="$(echo "${PLATFORM_LINUX_DISTRO_VERSION}" | awk -F'.' '{ print $1 }')"
                    else
                        export PLATFORM_LINUX_DISTRO_VERSION="$(sed 's/[^0-9.]*//g' /etc/redhat-release)"
                        if [[ "${PLATFORM_LINUX_DISTRO_VERSION}" > "7" ]]; then
                            export PLATFORM_LINUX_DISTRO_MAJOR_VERSION="7"
                        elif [[ "${PLATFORM_LINUX_DISTRO_VERSION}" > "6" ]]; then
                            export PLATFORM_LINUX_DISTRO_MAJOR_VERSION="6"
                        else
                            export PLATFORM_LINUX_DISTRO_MAJOR_VERSION="5"
                        fi
                    fi
                    ;;
                debian)
                    export PLATFORM_LINUX_DISTRO_CODENAME="$(lsb_release -c | awk '{ print $2 }')"
                    export PLATFORM_LINUX_DISTRO_BRANCH="$(lsb_release -r | awk '{ print $2 }')"
                    ;;
                *)
                    ;;
            esac
        fi

        source "${UPDATER_UTILS_DIR}/update_utils.zsh"
        [[ -n "${UPDATE_EXTRA_DEFINITIONS}" ]] && source "${UPDATE_EXTRA_DEFINITIONS}"
    }

    function update_updater_scripts () {
        if [[ "${UPDATER_SCRIPTS_REPO_URL}" == "" ]]; then
            echo "The variable UPDATER_SCRIPTS_REPO_URL is not set. Aborting"
            exit 101
        fi

        print_update "update scripts"
        if [[ "$(cd ${UPDATER_SCRIPTS_DIR} 2>/dev/null && git remote -v | awk '$1 == "origin" && $3 == "(fetch)" { print $2 }')" == "${UPDATER_SCRIPTS_REPO_URL}" ]]; then
            pushd "${UPDATER_SCRIPTS_DIR}" && \
            git fetch origin && \
            [[ "$(git rev-list --count master...origin/master)" -gt 0 ]] && \
            git reset --hard origin/master && \
            popd
        else
            rm -rf "${UPDATER_SCRIPTS_DIR}"
            git clone "${UPDATER_SCRIPTS_REPO_URL}" "${UPDATER_SCRIPTS_DIR}"
        fi
    }

    function read_update_order () {
        if [[ ! -f "${UPDATE_ORDER_PATH}" ]]; then
            echo "The file ${UPDATE_ORDER_PATH} does not exist. Aborting"
            exit 102
        fi
        UPDATE_ORDER=( "${(f)$(<${UPDATE_ORDER_PATH})}" )
    }

    function run_update_script () (
        UPDATE_SCRIPT_PATH="${UPDATER_SCRIPTS_DIR}/scripts/$1"

        source "${UPDATE_SCRIPT_PATH}"

        export UPDATE_TEMP="$(mktemp -d)"
        (
            update_description
            if ! is_function "update_condition" || update_condition; then
                print_update "${UPDATE_DESCRIPTION_OUTPUT}" "${UPDATE_CONDITION_OUTPUT}"
                cd "${UPDATE_TEMP}" && update_run
                RET="$?"
                [[ "${RET}" -ne 0 ]] && print_abort "${UPDATE_RUN_OUTPUT}"
                exit "${RET}"
            else
                print_skip "${UPDATE_DESCRIPTION_OUTPUT}" "${UPDATE_CONDITION_OUTPUT}"
                exit
            fi
        )
        RET="$?"
        rm -rf "${UPDATE_TEMP}"
        exit "${RET}"
    )

    init_variables
    update_updater_scripts
    if [[ "$1" == "all" ]]; then
        read_update_order
    else
        UPDATE_ORDER=()
        for ENTRY in "$@"; do
            UPDATE_ORDER+=( "${ENTRY}.zsh" )
        done
    fi
    for UPDATE_SCRIPT in "${UPDATE_ORDER[@]}"; do
        run_update_script "${UPDATE_SCRIPT}"
        RET="$?"
        rehash  # rebuild PATH cache
        [[ "${RET}" -ne 0 ]] && exit "${RET}"
    done
    print_summary
)

function update-all () {
    update all
}

# vim: ft=zsh:tw=120
