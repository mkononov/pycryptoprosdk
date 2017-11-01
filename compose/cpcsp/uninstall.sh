#!/bin/sh

check_if_debian_system() {
    if [ -f /etc/debian_version ] ||
        grep Ubuntu /etc/lsb-release > /dev/null 2>&1
    then
        is_debian_system=1
    else
        is_debian_system=0
    fi
}

set_del_command_and_package_lists() {
    if [ "${is_debian_system}" -eq 1 ] ; then
        pkglist="$(dpkg -l | grep -e rtSupCP -e cprocsp | awk '{print $2}')"
        del_command="dpkg -P"
    else
        pkglist="$(rpm -qa | grep -e rtSupCP -e cprocsp)"
        del_command="rpm -e --allmatches"
    fi
    rdr_package="$(echo "${pkglist}" | grep lsb-cprocsp-rdr | grep -v -e accord -e sobol)"
    base_package="$(echo "${pkglist}" | grep base | grep -v ssl)"
    compat_package="$(echo "${pkglist}" | grep compat)"
    csp_packages="$(
        echo "${pkglist}" \
            | grep -vx -e "${rdr_package}" -e "${base_package}" -e "${compat_package}" \
            | tr '\n' ' '
    )"
}

check_fail() {
    echo "Error: failed to uninstall CSP packages" >&2
    exit "$1"
}

main() {
    check_if_debian_system
    set_del_command_and_package_lists
    if [ -n "${csp_packages}" ] ; then
        # shellcheck disable=SC2086
        ${del_command} ${csp_packages} || check_fail "$?"
    fi
    if [ -n "${rdr_package}" ] ; then
        # shellcheck disable=SC2086
        ${del_command} ${rdr_package} || check_fail "$?"
    fi
    if [ -n "${base_package}" ] ; then
        # shellcheck disable=SC2086
        ${del_command} ${base_package} || check_fail "$?"
    fi
    if [ -n "${compat_package}" ] ; then
        # shellcheck disable=SC2086
        ${del_command} ${compat_package} || check_fail "$?"
    fi
}

main "$@"
