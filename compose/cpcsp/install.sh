#!/bin/sh

COMPAT_VERSION="1.0.0-1"
VERSION="4.0.*-5"

show_help() {
    echo "\
usage: ./install.sh [kc1|kc2] [package [...]]
  kc1: install kc1 packages (by default)
  kc2: install kc2 packages
  [package [...]]: list of additional packages"
}

parse_args() {
    enclosure="kc1"
    case "$1" in
        "kc1")
            shift
            ;;
        "kc2")
            enclosure="kc2"
            shift
            ;;
        "-help"|"--help")
            show_help
            exit 0
            ;;
    esac
    additional_packages="$*"
}

which_architecture() {
    machine_architecture="$(uname -m)"
    case "${machine_architecture}" in
        "x86_64"|"amd64"|"ppc64"|"ppc64le")
            bits_postfix="-64"
            ;;
        *)
            bits_postfix=""
            ;;
    esac
    case "${machine_architecture}" in
        "armv7l"|"armv7")
            is_arm=1
            ;;
        *)
            is_arm=0
            ;;
    esac
}

check_if_debian_system() {
    if [ -f /etc/debian_version ] ||
        grep Ubuntu /etc/lsb-release > /dev/null 2>&1
    then
        is_debian_system=1
    else
        is_debian_system=0
    fi
}

check_release_attributes() {
    if ls ./lsb-cprocsp-base*.deb > /dev/null 2>&1 ; then
        is_debian_release=1
    else
        is_debian_release=0
    fi
    if ls ./lsb-cprocsp-rdr-64* > /dev/null 2>&1 ; then
        is_64_release=1
    else
        is_64_release=0
    fi
}

# Use dpkg or alien on debian systems, otherwise use rpm.
set_inst_cmd() {
    if [ "${is_debian_system}" -eq 1 ] ; then
        if [ "${is_debian_release}" -eq 1 ] ; then
            inst_cmd="dpkg -i"
        else
            inst_cmd="alien -kci"
        fi
    else
        if [ "${is_debian_release}" -eq 1 ] ; then
            echo "Error: you are trying to install debian packages on not debian package system" >&2
            exit 1
        else
            inst_cmd="rpm -i"
        fi
    fi
}

# The release variables are used to construct full names of packages.
set_release_variables() {
    if [ "${is_debian_release}" -eq 1 ] ; then
        first_delimeter="_"
        noarch="all"
        second_delimeter="_"
        extension=".deb"
    else
        first_delimeter="-"
        noarch="noarch"
        second_delimeter="."
        extension=".rpm"
    fi
    case "${machine_architecture}" in
        # Enforce to install 64-bit packages on 64-bit system.
        "x86_64"|"amd64")
            if [ "${is_debian_release}" -eq 1 ] ; then
                arch="amd64"
            else
                arch="x86_64"
            fi
            ;;
        "ppc64"|"ppc64le")
            arch="${machine_architecture}"
            ;;
        "armv7l"|"armv7"|"mips")
            arch="${noarch}"
            ;;
        *)
            if [ "${is_debian_release}" -eq 1 ] ; then
                arch="i386"
            elif ls ./*.i686.rpm > /dev/null 2>&1 ; then
                arch="i686"
            else
                arch="i486"
            fi
            ;;
    esac
}

lsb_warning() {
    echo "Warning: lsb-core package not installed - installing cprocsp-compat-debian.
If you prefer to install system lsb-core package then
 * uninstall CryptoPro CSP
 * install lsb-core manually
 * install CryptoPro CSP again" >&2
}

construct_compat_package() {
    if [ -f /etc/cp-release ] ; then
        if grep Gaia /etc/cp-release > /dev/null 2>&1 ; then
            _distr="gaia"
        else
            _distr="splat"
        fi
    elif [ -f /etc/altlinux-release ] ; then
        _distr="altlinux${bits_postfix}"
    elif [ -f /etc/os-rt-release ] ; then
        _distr="osrt${bits_postfix}"
    elif [ "${is_arm}" -eq 1 ] ; then
        _distr="armhf"
    elif [ "${is_debian_system}" -eq 1 ] ; then
        if dpkg -s lsb-core > /dev/null 2>&1 ; then
            compat_package=""
            return
        else
            lsb_warning
            _distr="debian"
        fi
    else
        compat_package=""
        return
    fi

    compat_package="cprocsp-compat-\
${_distr}\
${first_delimeter}\
${COMPAT_VERSION}\
${second_delimeter}\
${noarch}\
${extension}"
}

construct_other_packages() {
    other_packages=""

    _names="lsb-cprocsp-base \
lsb-cprocsp-rdr lsb-cprocsp-${enclosure} lsb-cprocsp-capilite cprocsp-curl \
lsb-cprocsp-ca-certs \
${additional_packages}"

    for _name in ${_names} ; do
        _package="${_name}"

        if [ "${is_64_release}" -eq 1 ] ; then
            _package="${_package}${bits_postfix}"
        fi

        _package="${_package}\
${first_delimeter}\
${VERSION}\
${second_delimeter}\
${arch}\
${extension}"

        # There are several packages which are NOT architecture-specific,
        # e.g. lsb-cprocsp-base, lsb-cprocsp-ca-certs and devel-packages.
        # If the architecture-specific package is not found, try to install
        # the noarch package.
        # shellcheck disable=SC2086
        if ! [ -f ${_package} ] ; then
            _package="${_name}\
${first_delimeter}\
${VERSION}\
${second_delimeter}\
${noarch}\
${extension}"
        fi

        # Even the noarch package wasn't found.
        # shellcheck disable=SC2086
        if ! [ -f ${_package} ] ; then
            echo "Error: compatible package ${_name} doesn't exist or isn't unique" >&2
            exit 1
        fi

        other_packages="${other_packages} ${_package}"
    done
}

construct_list_of_packages() {
    packages=""

    construct_compat_package
    packages="${packages} ${compat_package}"

    # Other packages are the base packages and additional packages
    # specified by command-line arguments.
    construct_other_packages
    packages="${packages} ${other_packages}"
}

check_fail() {
    echo "Error: installation failed. LSB package may not be installed.
      Install LSB package and reinstall CryptoPro CSP. If it does not help, please 
      read installation documentation or contact the manufacturer: support@cryptopro.ru." >&2
    exit "$1"
}

install_packages() {
    for _package in ${packages} ; do
        echo "Installing ${_package}..."
        ${inst_cmd} "${_package}" || check_fail "$?"
    done
}

main() {
    cd "$(dirname "$0")" || exit "$?"
    parse_args "$@"

    which_architecture
    check_if_debian_system
    check_release_attributes
    set_inst_cmd
    set_release_variables
    construct_list_of_packages

    sh ./uninstall.sh || exit "$?"
    install_packages
}

main "$@"
