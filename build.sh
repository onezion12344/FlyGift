#!/bin/zsh
# Build FlyGift and a double-clickable macOS app bundle.
cd "$(dirname "$0")"
swiftc -O -swift-version 5 -o FlyGift main.swift FlyModel.swift Sim.swift MetalSim.swift GPUCheck.swift Diagnostics.swift \
    BrainView.swift Environment.swift FlyGift.swift \
    -framework Cocoa -framework SceneKit -framework Metal -framework AVFoundation || exit 1

ln -sf FlyGift SiliconFly

APP="build/FlyGift.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp FlyGift "$CONTENTS/MacOS/FlyGift"
cp app/Info.plist "$CONTENTS/Info.plist"
cp LIF.metal "$CONTENTS/Resources/LIF.metal"
cp LICENSE "$CONTENTS/Resources/LICENSE.txt"
cp assets/fly-realistic-v2.png "$CONTENTS/Resources/fly-realistic-v2.png"
cp assets/swatter-red-v3.png "$CONTENTS/Resources/swatter-red-v3.png"
cp -R data "$CONTENTS/Resources/data"

rm -f build/FlyGift-macOS-arm64.zip build/SHA256SUMS.txt
ditto -c -k --sequesterRsrc --keepParent "$APP" build/FlyGift-macOS-arm64.zip
(cd build && shasum -a 256 FlyGift-macOS-arm64.zip > SHA256SUMS.txt)

echo "Built ./FlyGift"
echo "Built ./build/FlyGift.app"
echo "Packaged ./build/FlyGift-macOS-arm64.zip"
