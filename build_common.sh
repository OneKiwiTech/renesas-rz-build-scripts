#!/bin/bash

#########################################################
# This file contains functions common to all the scripts
# Each script sour 'source' this file at the beginning.
#########################################################



# Toolchain Selection GUI
# Since each sub-script will want to ask the user what toolchain to use, we will keep a common interface in this file.
# $1 = env variable to save TOOLCHAIN_SETUP_NAME
# $2 = env variable to save TOOLCHAIN_SETUP

select_toolchain() {

  INDEX=0
  tc_array_text=()
  tc_array_setup=()
  menu_text=""

  # --------------------------------------------------
  # (none)
  tc_array_text+=("(none)")
  tc_array_setup+=("")
  INDEX=$((INDEX+1))

  # --------------------------------------------------
  # Poky (Yocto SDK) under /opt/poky
  if [ -e /opt/poky ] ; then
    array_poky=( $(find -L /opt/poky -mindepth 1 -maxdepth 1 -type d 2>/dev/null) )
  fi
  for tc_path in "${array_poky[@]}"; do
    if ls "$tc_path"/environment-setup-* >/dev/null 2>&1; then
      tc_version=$(basename "$tc_path")
      tc_array_text+=("Poky (Yocto SDK) ($tc_version)")
      tc_array_setup+=("source $tc_path/environment-setup-*")
      menu_text="$menu_text \"$INDEX Poky (Yocto SDK)\" \"$tc_path\""
      INDEX=$((INDEX+1))
    fi
  done

  # --------------------------------------------------
  # ARM bare-metal toolchains under /opt/arm
  if [ -e /opt/arm ] ; then
    array_arm=( $(find -L /opt/arm -mindepth 1 -maxdepth 1 -type d 2>/dev/null) )
  fi
  for tc_path in "${array_arm[@]}"; do
    if [ -x "$tc_path/bin/aarch64-none-elf-gcc" ]; then
      tc_version=$(basename "$tc_path" | sed "s/-x86.*//")
      tc_array_text+=("ARM Bare-metal ($tc_version)")
      tc_array_setup+=("PATH=$tc_path/bin:\$PATH ; export CROSS_COMPILE=aarch64-none-elf-")
      menu_text="$menu_text \"$INDEX ARM Bare-metal\" \"$tc_path\""
      INDEX=$((INDEX+1))
    fi
  done

  # --------------------------------------------------
  # Linaro Linux toolchains under /opt/linaro
  if [ -e /opt/linaro ] ; then
    array_linaro=( $(find -L /opt/linaro -mindepth 1 -maxdepth 1 -type d 2>/dev/null) )
  fi
  for tc_path in "${array_linaro[@]}"; do
    if [ -x "$tc_path/bin/aarch64-linux-gnu-gcc" ]; then
      tc_version=$(basename "$tc_path" | sed "s/-x86.*//")
      tc_array_text+=("Linaro Linux ($tc_version)")
      tc_array_setup+=("PATH=$tc_path/bin:\$PATH ; export CROSS_COMPILE=aarch64-linux-gnu-")
      menu_text="$menu_text \"$INDEX Linaro Linux\" \"$tc_path\""
      INDEX=$((INDEX+1))
    fi
  done

  # --------------------------------------------------
  # CURRENT DIRECTORY toolchains ($PWD)
  for tc_path in $(find -L "$PWD" -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do

    # Local Yocto SDK
    if ls "$tc_path"/environment-setup-* >/dev/null 2>&1; then
      tc_version=$(basename "$tc_path")
      tc_array_text+=("Local Poky SDK ($tc_version)")
      tc_array_setup+=("source $tc_path/environment-setup-*")
      menu_text="$menu_text \"$INDEX Local Poky SDK\" \"$tc_path\""
      INDEX=$((INDEX+1))
      continue
    fi

    # Local Linux toolchain
    if [ -x "$tc_path/bin/aarch64-linux-gnu-gcc" ]; then
      tc_version=$(basename "$tc_path")
      tc_array_text+=("Local Linux Toolchain ($tc_version)")
      tc_array_setup+=("PATH=$tc_path/bin:\$PATH ; export CROSS_COMPILE=aarch64-linux-gnu-")
      menu_text="$menu_text \"$INDEX Local Linux\" \"$tc_path\""
      INDEX=$((INDEX+1))
      continue
    fi

    # Local bare-metal toolchain
    if [ -x "$tc_path/bin/aarch64-none-elf-gcc" ]; then
      tc_version=$(basename "$tc_path")
      tc_array_text+=("Local ARM Bare-metal ($tc_version)")
      tc_array_setup+=("PATH=$tc_path/bin:\$PATH ; export CROSS_COMPILE=aarch64-none-elf-")
      menu_text="$menu_text \"$INDEX Local Bare-metal\" \"$tc_path\""
      INDEX=$((INDEX+1))
      continue
    fi
  done

  # --------------------------------------------------
  # Put (none) at the end of menu
  menu_text="$menu_text \"0 (none)\" \"No toolchain setup (advanced users)\""

  # --------------------------------------------------
  # Whiptail menu
  WT_CMD="whiptail --title \"Toolchain Selection\" \
    --menu \"Choose the toolchain you want to use.\n\
Detected under /opt/poky, /opt/arm, /opt/linaro and current directory.\n\" \
    0 0 0 $menu_text"

  eval "$WT_CMD 3>&1 1>&2 2>&3" > /tmp/wt_result.txt

  SELECT=$(awk '{print $1}' /tmp/wt_result.txt)

  x_TOOLCHAIN_SETUP_NAME="${tc_array_text[$SELECT]}"
  x_TOOLCHAIN_SETUP="${tc_array_setup[$SELECT]}"

  eval "export $1=\"$x_TOOLCHAIN_SETUP_NAME\""

  DO_SET="export $2=\"$x_TOOLCHAIN_SETUP\""
  DO_SET=$(echo "$DO_SET" | sed s/\$PATH/\\\\\$PATH/)
  eval "$DO_SET"
}



read_setting() {
  if [ -e "$SETTINGS_FILE" ] ; then
    source "$SETTINGS_FILE"
  else
    echo -e "\nERROR: Settings file ($SETTINGS_FILE) not found."
    exit
  fi

  # Convert OUT_DIR from relative path to full path
  if [ "${OUT_DIR:0:1}" != "/" ] ; then
    export OUT_DIR="$(pwd)/$OUT_DIR"
  fi

}

# $1 = env variable to save
# $2 = value
# Remember, we we share this file with other scripts, so we only want to change
# the lines used by this script
save_setting() {


  if [ ! -e $SETTINGS_FILE ] ; then
    touch $SETTINGS_FILE # create file if does not exit
  fi

  # Do not change the file if we did not make any changes
  grep -q "^$1=$2$" $SETTINGS_FILE
  if [ "$?" == "0" ] ; then
    return
  fi

  sed '/^'"$1"'=/d' -i $SETTINGS_FILE
  echo  "$1=$2" >> $SETTINGS_FILE

  # Delete empty or blank lines
  sed '/^$/d' -i $SETTINGS_FILE

  # Sort the file to keep the same order
  sort -o $SETTINGS_FILE $SETTINGS_FILE
}

# Check for required Host packages
# If a package is missing, then kill the script (exit)
check_packages() {

  MISSING_A_PACKAGE=0
  PACKAGE_LIST=(git make gcc g++ python3 bison flex)

  for i in ${PACKAGE_LIST[@]} ; do
    CHECK=$(which $i)
    if [ "$CHECK" == "" ] ; then
      echo "ERROR: Missing host package: $i"
      MISSING_A_PACKAGE=1
    fi
  done
  CHECK=$(dpkg -l 'libncurses5-dev' | grep '^ii')
  if [ "$CHECK" == "" ] ; then
    MISSING_A_PACKAGE=1
  fi

  # File /usr/include/openssl/sha.h is required to build Trusted Firmware-A
  CHECK=$(dpkg -l 'libssl-dev' | grep '^ii')
  if [ "$CHECK" == "" ] ; then
    MISSING_A_PACKAGE=1
  fi

  if [ "$MISSING_A_PACKAGE" != "0" ] ; then
    echo "ERROR: Missing mandatory host packages"
    echo "Please make sure the following packages are installed on your machine."
    echo "    ${PACKAGE_LIST[@]} libncurses5-dev libncursesw5-dev libssl-dev"
    echo ""
    echo "The following command line will ensure all packages are installed."
    echo ""
    echo "   sudo apt-get install ${PACKAGE_LIST[@]} libncurses5-dev libncursesw5-dev"
    echo ""
    exit 1
  fi
}
