MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp"
MANIFEST_BRANCH="twrp-11"
DEVICE_TREE_URL="https://github.com/o0Mardev/android_device_oppo_OP4B9B.git"
DEVICE_TREE_BRANCH="test"
DEVICE_PATH="device/OPPO/OP4B9B"
BUILD_TARGET="recovery"
TW_DEVICE_VERSION="test"

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
  
  # Clone device tree
  git clone $DEVICE_TREE_URL -b $DEVICE_TREE_BRANCH $DEVICE_PATH || abort "ERROR: Failed to Clone the Device Tree!"
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
    curl --upload-file $1 https://free.keep.sh > link.txt || abort "ERROR: Failed to Upload $1!"

    # Mirror to oshi.at
    TIMEOUT=20160
    curl -T $1 https://oshi.at/$1/${TIMEOUT} > mirror.txt || echo "WARNING: Failed to Mirror the Build!"

    # Show the Download Link
    DL_LINK=$(cat link.txt)
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
  sync|syncDevDeps|build|upload) $1;;
esac
