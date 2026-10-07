#!/bin/zsh
# Build FlyGift and a double-clickable macOS app bundle.
set -euo pipefail
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
cp assets/splat-realistic-v1.png "$CONTENTS/Resources/splat-realistic-v1.png"
cp assets/gift-box-cc0/GiftBox.obj "$CONTENTS/Resources/GiftBox.obj"
cp assets/gift-box-cc0/README.md "$CONTENTS/Resources/GIFT_BOX_LICENSE.md"
cp -R data "$CONTENTS/Resources/data"

# Sign only after every resource and Info.plist are in their final positions.
# The linker's executable-only signature does not seal an App bundle.
if [[ -n "${FLYGIFT_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$FLYGIFT_SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
    echo "Preview signing: bundle integrity is sealed; Apple notarization is not present."
fi
codesign --verify --deep --strict --verbose=2 "$APP"

# Production distributions require both Developer ID and a successful notary
# submission. Credentials stay in the user's Keychain, never in the repository.
if [[ -n "${FLYGIFT_NOTARY_PROFILE:-}" ]]; then
    [[ -n "${FLYGIFT_SIGNING_IDENTITY:-}" ]] || { echo "Notarization requires FLYGIFT_SIGNING_IDENTITY" >&2; exit 1; }
    ditto -c -k --sequesterRsrc --keepParent "$APP" build/FlyGift-notary.zip
    xcrun notarytool submit build/FlyGift-notary.zip --keychain-profile "$FLYGIFT_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

rm -f build/FlyGift-macOS-arm64.zip build/SHA256SUMS.txt
ditto -c -k --sequesterRsrc --keepParent "$APP" build/FlyGift-macOS-arm64.zip
(cd build && shasum -a 256 FlyGift-macOS-arm64.zip > SHA256SUMS.txt)

echo "Built ./FlyGift"
echo "Built ./build/FlyGift.app"
echo "Packaged ./build/FlyGift-macOS-arm64.zip"
