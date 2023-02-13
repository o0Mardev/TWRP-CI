MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp"
MANIFEST_BRANCH="twrp-12.1"
DEVICE_TREE_URL="https://github.com/HemanthJabalpuri/twrp_motorola_hawao"
DEVICE_TREE_BRANCH="test-12.1"
DEVICE_PATH="device/motorola/hawao"
COMMON_TREE_URL="https://github.com/HemanthJabalpuri/twrp_motorola_sm6225-common"
COMMON_PATH="device/motorola/sm6225-common"
BUILD_TARGET="boot"
TW_DEVICE_VERSION="2"

DEVICE_NAME="$(echo $DEVICE_PATH | cut -d "/" -f 3)"
case $MANIFEST_BRANCH in
  twrp-1*) buildtree="twrp";;
  *) buildtree="omni";;
esac
MAKEFILE_NAME="${buildtree}_$DEVICE_NAME"

##
abort() { echo "$1"; exit 1; }
WORK_PATH="$HOME/work" # Full (absolute) path.
[ -e $WORK_PATH ] || mkdir $WORK_PATH
cd $WORK_PATH
##

sync() {
  # Install repo
  mkdir ~/bin
  curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
  chmod a+x ~/bin/repo
  sudo ln -sf ~/bin/repo /usr/bin/repo
  sudo ln -sf ~/bin/repo /usr/local/bin/repo

  # Initialize repo
  repo init --depth=1 $MANIFEST_URL -b $MANIFEST_BRANCH

  # Repo Sync
  repo sync -j$(nproc --all) --force-sync

  # Cherry-pick gerrit patches
  # if [ "$TWRP_BRANCH" = "twrp-12.1" ]; then
  #	  if [[ "$TWRP_MANIFEST" == *"faoliveira78"* ]]; then
  #	    git -C bootable/recovery fetch https://gerrit.twrp.me/android_bootable_recovery refs/changes/06/6106/1 && git -C bootable/recovery cherry-pick FETCH_HEAD
  #	  else
  #	    source build/envsetup.sh
  #	    repopick 5917 6106 6120
  #   fi
  # fi

  # Use our custom bootable recovery
  #rm -rf bootable/recovery
  #git clone --depth=1 https://github.com/HemanthJabalpuri/android_bootable_recovery -b test-12.1 bootable/recovery

  # Clone device tree
  git clone $DEVICE_TREE_URL -b $DEVICE_TREE_BRANCH $DEVICE_PATH || abort "ERROR: Failed to Clone the Device Tree!"

  # Clone common tree
  if [ -n "$COMMON_TREE_URL" ] && [ -n "$COMMON_PATH" ]; then
    git clone $COMMON_TREE_URL -b $DEVICE_TREE_BRANCH $COMMON_PATH || abort "ERROR: Failed to Clone the Common Tree!"
  fi
}

syncDevDeps() {
  # Sync Device Dependencies
  depsf=$DEVICE_PATH/${buildtree}.dependencies
  if [ -f $depsf ]; then
    curl -sL https://raw.githubusercontent.com/CaptainThrowback/Action-Recovery-Builder/main/scripts/convert.sh > ~/convert.sh
    bash ~/convert.sh $depsf
    repo sync -j$(nproc --all)
  else
    echo " Skipping, since $depsf not found"
  fi
}

build() {
  export USE_CCACHE=1
  export CCACHE_SIZE="50G"
  export CCACHE_DIR="$HOME/work/.ccache"
  ccache -M ${CCACHE_SIZE}

  # Building recovery
  source build/envsetup.sh
  export ALLOW_MISSING_DEPENDENCIES=true
  lunch twrp_${DEVICE_NAME}-eng || abort "ERROR: Failed to lunch the target!"
  export TW_DEVICE_VERSION
  mka -j$(nproc --all) ${BUILD_TARGET}image || abort "ERROR: Failed to Build TWRP!"
}

upload() {
  # Get Version info stored in variables.h
  TW_MAIN_VERSION=$(cat bootable/recovery/variables.h | grep "define TW_MAIN_VERSION_STR" | cut -d \" -f2)
  OUTFILE=TWRP-${TW_MAIN_VERSION}-${TW_DEVICE_VERSION}-${DEVICE_NAME}-$(date "+%Y%m%d%I%M").zip

  # Change to the Output Directory
  cd out/target/product/$DEVICE_NAME
  mv ${BUILD_TARGET}.img ${OUTFILE%.zip}.img
  zip -r9 $OUTFILE ${OUTFILE%.zip}.img

  uploadfile() {
    # Upload to WeTransfer
    # NOTE: the current Docker Image, "registry.gitlab.com/sushrut1101/docker:latest", includes the 'transfer' binary by Default
    transfer wet $1 > link.txt || abort "ERROR: Failed to Upload $1!"

    # Mirror to oshi.at
    TIMEOUT=20160
    curl -T $1 https://oshi.at/$1/${TIMEOUT} > mirror.txt || echo "WARNING: Failed to Mirror the Build!"

    # Show the Download Link
    DL_LINK=$(cat link.txt | grep Download | cut -d " " -f 3)
    MIRROR_LINK=$(cat mirror.txt | grep Download | cut -d " "  -f 1)
    echo "==$1=="
    echo "Download Link: ${DL_LINK}" || echo "ERROR: Failed to Upload the Build!"
    echo "Mirror: ${MIRROR_LINK}" || echo "WARNING: Failed to Mirror the Build!"
    echo "=============================================="
    echo " "
  }

  if [ $BUILD_TARGET = "boot" ]; then
    git clone --depth=1 https://github.com/HemanthJabalpuri/twrp_abtemplate
    cd twrp_abtemplate
    cp ../${OUTFILE%.zip}.img .
    zip -r9 $OUTFILE *
  fi
  uploadfile $OUTFILE
}

case "$1" in
  "sync") sync;;
  "syncDevDeps") syncDevDeps;;
  "build") build;;
  "upload") upload;;
esac
