export UPDATER_ROOT_DIR="${0:h}"

function update-all () (
    function init_variables () {
        export UPDATER_SCRIPTS_DIR="${UPDATER_ROOT_DIR}/update_scripts"
        export UPDATE_ORDER_PATH="${UPDATER_SCRIPTS_DIR}/update_order"
        if [[ "$(uname)" == "Darwin" ]]; then
            export PLATFORM_MACOS=1
            export PLATFORM_LINUX=0
        else
            export PLATFORM_MACOS=0
            export PLATFORM_LINUX=1
        fi
        if (( ${PLATFORM_LINUX} )); then
            export PLATFORM_LINUX_DISTRO="unknown"
            [[ -f "/etc/debian_version" ]] && export PLATFORM_LINUX_DISTRO="debian"
            [[ -f "/etc/redhat-release" ]] && export PLATFORM_LINUX_DISTRO="centos"
        fi

        source "${UPDATER_ROOT_DIR}/utils/utils.zsh"
    }

    function update_updater_scripts () {
        if [[ "${UPDATER_SCRIPTS_REPO_URL}" == "" ]]; then
            echo "The variable UPDATER_SCRIPTS_REPO_URL is not set. Aborting"
            exit 101
        fi

        if [[ "$(cd ${UPDATER_SCRIPTS_DIR} 2>/dev/null && git remote get-url origin)" == "${UPDATER_SCRIPTS_REPO_URL}" ]]; then
            pushd "${UPDATER_SCRIPTS_DIR}" && \
            git fetch origin && \
            [[ "$(git rev-list --count master...origin/master)" -gt 0 ]] && \
            git reset --hard origin/master && \
            popd
        else
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
    read_update_order
    for UPDATE_SCRIPT in "${UPDATE_ORDER[@]}"; do
        run_update_script "${UPDATE_SCRIPT}"
        RET="$?"
        [[ "${RET}" -ne 0 ]] && exit "${RET}"
    done
)

# vim: ft=zsh:tw=120
