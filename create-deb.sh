#!/bin/bash

DIRECTORY=$(pwd)
export DEBIAN_FRONTEND=noninteractive

LATESTCOMMIT=`cat $DIRECTORY/commit.txt`

function error() {
	echo -e "\e[91m$1\e[39m"
  rm -f $COMMITFILE
  rm -rf $DIRECTORY/box64
	exit 1
 	break
}

rm -rf $DIRECTORY/box64

cd $DIRECTORY

rm -rf box64

git clone https://github.com/ptitSeb/box64 || error "Failed to download box64 repo"
cd box64
commit="$(bash -c 'git rev-parse HEAD | cut -c 1-7')"
if [ "$commit" == "$LATESTCOMMIT" ]; then
  cd "$DIRECTORY"
  rm -rf "box64"
  echo "Box64 is already up to date. Exiting."
  touch exited_successfully.txt
  exit 0
fi
echo "Box64 is not the latest version, compiling now."
echo $commit > $DIRECTORY/commit.txt
echo "Wrote commit to commit.txt file for use during the next compilation."

targets=(ARM64)

for target in ${targets[@]}; do
  echo "Building $target"

  cd "$DIRECTORY/box64"
  sudo rm -rf build && mkdir build && cd build || error "Could not move to build directory"
  # allow installation even on x86_64 (needed for checkinstall)
  sed -i "s/NOT _x86 AND NOT _x86_64/true/g" ../CMakeLists.txt
  # warning, BOX64 cmakelists enables crypto with the ARM_DYNAREC options, it was purly by luck that no crypto opts were used which would be a problem since the Pi4 doesn't have them
  if [[ $target == "ANDROID" ]]; then
    cmake .. -DBAD_SIGNAL=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc-9 -DARM_DYNAREC=ON || error "Failed to run cmake."
  else
    cmake .. -D$target=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc-9 -DARM_DYNAREC=ON || error "Failed to run cmake."
  fi
  make -j8 || error "Failed to run make."

  function get-box64-version() {
    if [[ $1 == "ver" ]]; then
      export BOX64VER="$(cat ../src/box64version.h | sed -n -e 's/^.*BOX64_MAJOR //p')"."$(cat ../src/box64version.h | sed -n -e 's/^.*BOX64_MINOR //p')"."$(cat ../src/box64version.h | sed -n -e 's/^.*BOX64_REVISION //p')"
    elif [[ $1 == "commit" ]]; then
      export BOX64COMMIT="$commit"
    fi
  }

  get-box64-version ver || error "Failed to get box64 version!"
  get-box64-version commit || error "Failed to get box64 commit!"
  DEBVER="$(echo "$BOX64VER+$(date +"%F" | sed 's/-//g').$BOX64COMMIT")" || error "Failed to set debver variable."

  mkdir doc-pak || error "Failed to create doc-pak dir."
  cp ../README.md ./doc-pak || error "Failed to add readme to docs"
  cp ../docs/CHANGELOG.md ./doc-pak || error "Failed to add changelog to docs"
  cp ../docs/USAGE.md ./doc-pak || error "Failed to add USAGE to docs"
  cp ../LICENSE ./doc-pak || error "Failed to add license to docs"
  echo "Box64 lets you run x86_64 Linux programs (such as games) on non-x86_64 Linux systems, like ARM (host system needs to be 64bit little-endian)">description-pak || error "Failed to create description-pak."
  echo "#!/bin/bash
  echo 'Restarting systemd-binfmt...'
  systemctl restart systemd-binfmt || true" > postinstall-pak || error "Failed to create postinstall-pak!"

  conflict_list="qemu-user-static"
  for value in "${targets[@]}"; do
    [[ $value != $target ]] && conflict_list+=", box64-$(echo $value | tr '[:upper:]' '[:lower:]' | tr _ - | sed -r 's/ /, /g')"
  done
  
  if [[ $target == "ARM64" ]]; then
    sudo checkinstall -y -D --pkgversion="$DEBVER" --arch="arm64" --provides="box64" --conflicts="$conflict_list" --maintainer="Ryan Fortner <ryankfortner@gmail.com>" --pkglicense="MIT" --pkgsource="https://github.com/ptitSeb/box64" --pkggroup="utils" --pkgname="box64" --install="no" make install || error "Checkinstall failed to create a deb package."
    ls | grep box64
  else
    sudo checkinstall -y -D --pkgversion="$DEBVER" --arch="arm64" --provides="box64" --conflicts="$conflict_list" --maintainer="Ryan Fortner <ryankfortner@gmail.com>" --pkglicense="MIT" --pkgsource="https://github.com/ptitSeb/box64" --pkggroup="utils" --pkgname="box64-$target" --install="no" make install || error "Checkinstall failed to create a deb package."
  fi

  cd $DIRECTORY
  mkdir -p $DIRECTORY/debz
  mv box64/build/*.deb $DIRECTORY/debz || error "Failed to move deb to debian folder."

done
