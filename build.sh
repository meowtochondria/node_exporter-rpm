#!/bin/bash

###########################################
# Some initializations.                   #
###########################################
project='prometheus'
product='node_exporter'
pkg_version='latest'
pkg_release='1'
isDebug=false
current_dir=$(dirname ${0})
build_root=$(realpath $current_dir/rpmbuild)
download_url_root="https://github.com/$project/$product/releases/download/"
release_link="https://api.github.com/repos/$project/$product/releases"
execute_features=()
declare -A available_versions

# Array containing mapping of dependency binaries to the packages that contain them.
# This is used in perform_safety_checks() to install missing packages.
# To add a dependency, just add to this mapping.
declare -A deps_bin_to_pkg
deps_bin_to_pkg=(
    ['wget']='wget'
    ['rpmbuild']='rpm-build'
    ['sha256sum']='coreutils'
    ['curl']='curl'
)
###########################################
# Functions                               #
###########################################
function print_debug_line()
{
    if [ "$isDebug" = true ]; then
        printf "DEBUG: $1\n"
    fi
}

function usage()
{
    echo "Script to setup RPM build environment and package $product.";
    echo "The script should _NOT_ be run as root. It will ask for";
    echo "password via sudo if something needs it.";
    echo "";
    echo "Usage: ${0} [-v version_to_build] [-r release_version]";
    echo -e "\n-v\tVersion of $product to build. This version should be";
    echo -e "  \tavailable upstream. Default: latest ($pkg_version)";
    echo -e "\n-r\tRPM release version. Use this field to specify if this is a"
    echo -e "  \tcustom version for your needs. For example, if you are"
    echo -e "  \tbuilding this package for your company, you can set this"
    echo -e "  \tto company name. Default: 1";
    echo -e "\n-b\tPath that will contain RPM build tree. Default is current dir.";
    echo -e "\n-l\tList available versions.";
    echo -e "\n-h\tShow this help message and exit.";
    echo -e "\n-d\tPrint debugging statements.";
    echo -e "\nExample: ${0} -v $pkg_version";
}

function parse_command()
{
    SHORT=v:r:b:lhd
    LONG=version:,release:,build_root:,list,help,debug
    PARSED=$(getopt --options $SHORT --longoptions $LONG --name "$0" -- "$@")
    if [[ $? -ne 0 ]]; then
        # e.g. $? == 1
        #  then getopt has complained about wrong arguments to stdout
        exit 1
    fi

    # use eval with "$PARSED" to properly handle the quoting
    eval set -- "$PARSED"

    # Parse options until we see --
    while true; do
        case "$1" in
            -d|--debug)
                isDebug=true;
                print_debug_line "ON";
                shift
                ;;
            -v|--version)
                pkg_version="$2"
                shift 2
                ;;
            -r|--release)
                pkg_release="$2"
                shift 2
                ;;
            -b|--build_root)
                build_root="$2"
                shift 2
                ;;
            -l|--list)
                execute_features+=('print_available_versions')
                shift
                ;;
            -h|--help)
                execute_features+=('usage')
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo -e "\nProgrammer has the dumbz."
                exit 2
                ;;
        esac
    done
}

function perform_safety_checks()
{
    # Ensure we are not running as root.
    if [ $EUID -eq 0 ]; then
        echo 'Please do not run this script as root.'
        echo 'See https://fedoraproject.org/wiki/How_to_create_an_RPM_package#Preparing_your_system for details.'
        exit 3
    fi

    # Ensure we are on Red Hat or its derivatives.
    if [ -f "/proc/version" ]; then
        proc_version=`cat /proc/version`
    else
        proc_version=`uname -a`
    fi

    print_debug_line "${FUNCNAME[0]} : proc version = $proc_version"

    if [[ $proc_version != *"Red Hat"* ]]; then
        echo "ERROR: Your OS is not supported by this script! :("
        echo "At the moment only Red Hat and its derivatives are supported."
        exit 4
    fi

    # Check if packages are installed
    unavailable_packages=''
    for dep in ${!deps_bin_to_pkg[@]}; do
        which $dep &>/dev/null
        if [ "$?" -gt 0 ]; then
            print_debug_line "${FUNCNAME[0]} : '$dep' from '${deps_bin_to_pkg[$dep]}' is not installed."
            unavailable_packages+="${deps_bin_to_pkg[$dep]} "
        fi
        print_debug_line "${FUNCNAME[0]} : $dep is available."
    done

    # Install missing packages. Exit if installation is unsuccessful.
    if [ -n "$unavailable_packages" ]; then
        echo -e "\nFollowing packages need to be installed:\n$unavailable_packages"
        echo    "Please enter the password for sudo (if prompted)"
        sudo yum install -y $unavailable_packages

        # Check if installation was successful.
        if [ "$?" -ne 0 ]; then
            echo -e "\nSome packages could not be installed successfully. Following command was run:"
            echo -e "sudo yum install -y $unavailable_packages"
            echo -e "\nPlease debug and rerun the script."
            exit 5
        fi
    fi
}

function validate_inputs()
{
    # Check if correct version has been supplied. Otherwise downloads will fail.
    [ ${#available_versions[@]} -eq 0 ] && get_available_versions

    is_version_valid='false'
    if [ "$pkg_version" == "latest" ]; then
        pkg_version=$(echo ${!available_versions[@]} | tr ' ' '\n' | sort --version-sort | tail -n 1)
        is_version_valid='true'
    else
        for available_version in ${!available_versions[@]}; do
            if [ "$available_version" == "$pkg_version" ]; then
                is_version_valid='true'
                break
            fi
        done
    fi

    if [ "$is_version_valid" == 'false' ]; then
        echo "'$pkg_version' of $product is not available upstream. Versions available for packaging:"
        print_available_versions
        exit 6
    fi

    print_debug_line "Using version: $pkg_version"
}

function get_available_versions()
{
    print_debug_line "Getting available versions from $release_link"
    links=$(curl --silent $release_link | grep -oP "https.+$product-\d+\.\d+\.\d+\.linux-amd64.tar.gz")
    if [ "$?" -ne 0 ]; then
        echo "Could not fetch releases from $release_link."
        echo "Please verify you are connected to the interwebz."
        echo "Exiting..."
        exit 7
    fi
    for link in $links; do
        ver=$(echo $link | cut -f 8 -d '/' | tr -d 'v')
        available_versions["$ver"]=$link
    done
}

function print_available_versions()
{
    echo "Released versions available upstream..."
    [ ${#available_versions[@]} -eq 0 ] && get_available_versions
    # Reference: http://www.tldp.org/LDP/abs/html/arrays.html
    echo ${!available_versions[@]} | tr -s ' ' '\n' | sort --version-sort --reverse
}

function setup_rpm_tree()
{
    # clean the working directories. Do not remove SOURCES dir if it is already there.
    print_debug_line "${FUNCNAME[0]} : Deleting and recreating RPM build tree folders."
    for dir in BUILD RPMS SRPMS BUILDROOT; do
        rm -rf $build_root/$dir || true
        mkdir -p $build_root/$dir
    done

    print_debug_line "${FUNCNAME[0]} : Copying SPECS and SOURCES to $build_root."
    # Copy spec dir to build dir
    cp -R $current_dir/SPECS $build_root/
    # Copy sources to the sources dir.
    cp -Rf $current_dir/SOURCES $build_root/
}

function download_packages()
{
    # prometheus is not publishing checksums for every release :/
    core_archive_name=$(basename ${available_versions[$pkg_version]})
    sources_dir="$build_root/SOURCES"
    failed_download='false'

    # Skip download if file already exists
    if [ -f "$sources_dir/$core_archive_name" ]; then
        print_debug_line "$sources_dir/$core_archive_name already exists. Not downloading again..."
        return
    fi

    print_debug_line "${FUNCNAME[0]} : Downloading ${available_versions[$pkg_version]} to $sources_dir/$core_archive_name"
    wget -O $sources_dir/$core_archive_name ${available_versions[$pkg_version]}

    # Print a message if download leads to file of size 0, or wget exits with
    # non-zero exit code
    if [ ! -s $sources_dir/$core_archive_name -o "$?" -ne 0 ]; then
        echo
        echo "Failed to download ${available_versions[$pkg_version]}."
        echo "Please verify if the link is accurate and network connectivity"
        echo "is available."
        failed_download='true'
    fi

    if [ "$failed_download" == 'true' ]; then
        echo -e "\nDownload(s) failed :(. Exiting.\n"
        exit 8
    fi

}

##################
# Pass all args of the script to the function.
parse_command "$@"
perform_safety_checks
validate_inputs
for func in ${execute_features[@]}; do
    ($func)
done
[ ${#execute_features[@]} -gt 0 ] && exit 0
setup_rpm_tree
download_packages
# Now that the sources are downloaded and verified we can actually make the RPM.
# _topdir and _tmppath are magic rpm variables that can be defined in ~/.rpmmacros
# For ease of reliable builds they are defined here on the command line.
print_debug_line "Starting rpmbuild."
rpmbuild -ba --define="_topdir $build_root" --define="buildroot $build_root/BUILDROOT" --define="pkg_version $pkg_version" --define="rpm_release $pkg_release" $build_root/SPECS/$product.spec
