#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/_common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
for command in curl node tar unzip shasum; do require_command "$command"; done
[[ "$(uname -s)/$(uname -m)" = Darwin/arm64 ]] || die "trial downloader requires Apple Silicon macOS"
data_root="${ONON_DATA_ROOT:-$REPO_ROOT/.local/onon}"
[[ "$data_root" = /* && "$data_root" != / ]] || die "ONON_DATA_ROOT must be an absolute non-root path"
trial_dir="$data_root/protomaps-trial"
assets="$trial_dir/assets"
mkdir -p "$trial_dir/tools" "$trial_dir/provenance" "$assets/vendor"
valid() { [[ -f "$1" ]] && [[ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$2" ]]; }
download() {
  local target="$1" checksum="$2" url="$3"
  if valid "$target" "$checksum"; then return; fi
  mkdir -p "$(dirname "$target")"
  log "downloading $(basename "$target")"
  curl --fail --location --retry 3 --output "$target.part" "$url"
  valid "$target.part" "$checksum" || die "checksum mismatch: $target.part"
  mv "$target.part" "$target"
}
tool="$trial_dir/tools/pmtiles"
tool_hash=9037562a73ae619c67976d50a892566caf72c0323b55e1c3e10598897f35313a
if ! valid "$tool" "$tool_hash"; then
  download "$trial_dir/tools/go-pmtiles.zip" 40528f7f616fcbf91207cd48c8fc023d213f6d86c0cbf1f748732803d1880f3d \
    https://github.com/protomaps/go-pmtiles/releases/download/v1.31.2/go-pmtiles-1.31.2_Darwin_arm64.zip
  unzip -p "$trial_dir/tools/go-pmtiles.zip" pmtiles > "$tool.part"
  valid "$tool.part" "$tool_hash" || die "PMTiles executable checksum mismatch"
  mv "$tool.part" "$tool"
fi
chmod +x "$tool"
bundle="$assets/vendor/basemaps.js"
bundle_hash=551864f01da1bfe3005e99987197f22f56d0c35f9a10fa1727a889e2434af16d
if ! valid "$bundle" "$bundle_hash"; then
  package="$trial_dir/provenance/basemaps-5.7.2.tgz"
  download "$package" 2d5d41b29cdd2364f7092ad439bd9d170b4f38cbec8858cefbe84d0f98125ce6 \
    https://registry.npmjs.org/@protomaps/basemaps/-/basemaps-5.7.2.tgz
  tar -xOf "$package" package/dist/basemaps.js > "$bundle.part"
  valid "$bundle.part" "$bundle_hash" || die "style library checksum mismatch"
  mv "$bundle.part" "$bundle"
fi
download "$assets/vendor/basemaps-LICENSE.md" 74f975cfedd168098c43b5cfd6e587e40604684c4ffcec3e90d24b3b09c061b0 \
  https://raw.githubusercontent.com/protomaps/basemaps/3ea8293a28131c3dc63f1bb20827bdb8a76df06f/LICENSE.md
asset_source=https://raw.githubusercontent.com/protomaps/basemaps-assets/028c18f713baecad011301ff7a69acc39bcc2ae7
while read -r checksum path; do
  download "$assets/$path" "$checksum" "$asset_source/${path// /%20}"
done <<'ASSETS'
62c6d49b15fa836eb6aa45e259c7ca6762f44b011b09e47776efbe4a6db1b397 fonts/Noto Sans Regular/0-255.pbf
8ea977a587352fe31b4159ffdbc9a40be79056f2472017c742ea1e4a931864b9 fonts/Noto Sans Regular/8192-8447.pbf
2eca7561f9f566bcacfda5dd04fb5880baec1328ec0f5484678289a13994de8a fonts/Noto Sans Regular/256-511.pbf
b9100ec886dff647198802c41d1ca6df9e6f82325179d8d71e3d377b5fe8682e fonts/Noto Sans Regular/7680-7935.pbf
f46850e6574d817d58d96b91196739c77c1b570a7b4f992ff1380d2b4d5d631f fonts/Noto Sans Regular/1536-1791.pbf
537ccbee79180f4f8b3f6d2bdd27df979260ce1a0358c40d7aa7db505d9b03aa fonts/Noto Sans Regular/768-1023.pbf
43edfca91c285ba1226f09d5e74d68e1473a088c517f02a5212ff6ccb10037dc fonts/Noto Sans Italic/0-255.pbf
5dc4e6680116fef01be024e272859d130262613c7e634409a590e5d50ad124ae fonts/Noto Sans Italic/8192-8447.pbf
a6f9f6574c86a4a28aba630ca1017857ceadd2370ed32a1293c35f819ab9bd60 fonts/Noto Sans Italic/256-511.pbf
781d61c4e6c2634d704579906c71b064c4b62d7da7f06141a2babc0870c05ebb fonts/Noto Sans Italic/7680-7935.pbf
130f950ea1de60403501b681f786514f3a57a06b2304dd77400634a8ddfd8a83 fonts/Noto Sans Italic/1536-1791.pbf
52bfd64775b91f7847da983b7bbc277135e006423cec22a44499e03e182e614e fonts/Noto Sans Italic/768-1023.pbf
ba2f0118dd024e3041b158e5f9eb49bc0a658019f53f458e9f5c0b8efcd79b91 fonts/Noto Sans Medium/0-255.pbf
cc38e4956207f0edba1aaf749b61e8f6f1678ef1ad443d32ee285b21d0eb67aa fonts/Noto Sans Medium/8192-8447.pbf
d5e801a1a5b1d409d3298c3a1e1ca76328e2314a751078833a618620e8e66e4d fonts/Noto Sans Medium/256-511.pbf
21c35a285f8abc65e05bd55e80f8782d10a179831a83b31d983aa00a783a258b fonts/Noto Sans Medium/7680-7935.pbf
e998806d6e6b4c03950564e64be0d91c0cfc576c886d698953a42d33f2ccc099 fonts/Noto Sans Medium/1536-1791.pbf
4b92939b4d3779b2d0b6be5b69c105e8c88352c047170e474011e82511ac03e9 fonts/Noto Sans Medium/768-1023.pbf
bfac76cf7ed5c2aa2992695904056a1c6b07785b7fd20e6c640cb44fd6244a2e sprites/v4/light.json
b6a34640917bdc57d0bd080836db33376371a3312ebe7b849045268015de3481 sprites/v4/light.png
1fb5b123fbe35d2e1f6ac171513ce01df89e671273a417ee89c44886a4c132f0 sprites/v4/light@2x.json
23f6e9df27c2e9a14385763980a24e3608966bfc8192a106058bc2ca959ab563 sprites/v4/light@2x.png
bfac76cf7ed5c2aa2992695904056a1c6b07785b7fd20e6c640cb44fd6244a2e sprites/v4/dark.json
8920f68e8f9f7a4188da43e62a81bbc426532579fff7b5f27aad09e130f4246e sprites/v4/dark.png
1fb5b123fbe35d2e1f6ac171513ce01df89e671273a417ee89c44886a4c132f0 sprites/v4/dark@2x.json
6e01b4e366d304f27bbd55390511a3d4e39aa1d03eb3e82f873f7ea32e74cbe4 sprites/v4/dark@2x.png
ASSETS
archive="$trial_dir/sydney.pmtiles"
archive_hash=4035d24abf7aa0fcf2edc0a299d46a7fa17caf5dd099d2b5c585199a12509060
if ! valid "$archive" "$archive_hash"; then
  log "extracting pinned Sydney region (about 8.7 MB); dated upstream builds have limited retention"
  "$tool" extract https://build.protomaps.com/20261009.pmtiles "$archive.part" \
    --bbox=151.15,-33.92,151.25,-33.80 --minzoom=0 --maxzoom=15
  valid "$archive.part" "$archive_hash" || die "Sydney archive checksum mismatch"
  mv "$archive.part" "$archive"
fi
"$tool" verify "$archive"
"$tool" show "$archive" --header-json > "$trial_dir/provenance/extract-header.json"
"$tool" show "$archive" --metadata > "$trial_dir/provenance/extract-metadata.json"
node - "$assets" <<'JS'
const fs = require('node:fs');
const vm = require('node:vm');
const assets = process.argv[2];
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(`${assets}/vendor/basemaps.js`, 'utf8'), context);
const style = {
  version: 8, name: 'Protomaps Light',
  sources: {protomaps: {type: 'vector', url: 'http://127.0.0.1:8082/sydney.json',
    attribution: '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap</a> | Protomaps'}},
  glyphs: '/fonts/{fontstack}/{range}.pbf', sprite: '/sprites/v4/light',
  layers: context.basemaps.layers('protomaps', context.basemaps.namedFlavor('light'), {lang: 'en'}),
};
fs.writeFileSync(`${assets}/light.json.part`, `${JSON.stringify(style, null, 2)}\n`);
fs.renameSync(`${assets}/light.json.part`, `${assets}/light.json`);
JS
log "local Protomaps trial ready: $trial_dir (cached reruns require no Internet)"
