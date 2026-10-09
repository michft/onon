import { cpSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { createContext, runInContext } from "node:vm";
import { surfaceMapStyle } from "../apps/web/src/protomaps-style.ts";
type StyleSpecification = Parameters<typeof surfaceMapStyle>[0];
const { validateStyleMin } = createRequire(new URL("../apps/web/package.json", import.meta.url))(
  "@maplibre/maplibre-gl-style-spec",
) as { validateStyleMin: (style: StyleSpecification) => { message: string }[] };

const trial = process.argv[2];
if (!trial) throw new Error("Pass the downloaded Protomaps trial directory");
const output = fileURLToPath(new URL("../.local/onon/ios-map/Protomaps", import.meta.url));
const staging = `${output}.part`;
rmSync(staging, { recursive: true, force: true });
mkdirSync(staging, { recursive: true });

const context = createContext({}) as ReturnType<typeof createContext> & {
  basemaps: {
    namedFlavor: (flavor: string) => unknown;
    layers: (source: string, flavor: unknown, options: { lang: string }) => StyleSpecification["layers"];
  };
};
runInContext(readFileSync(resolve(trial, "assets/vendor/basemaps.js"), "utf8"), context);
cpSync(resolve(trial, "sydney.pmtiles"), `${staging}/sydney.pmtiles`);
for (const font of ["Noto Sans Regular", "Noto Sans Italic", "Noto Sans Medium"]) {
  cpSync(resolve(trial, "assets/fonts", font), `${staging}/fonts/${font}`, { recursive: true });
}
mkdirSync(`${staging}/sprites/v4`, { recursive: true });
cpSync(resolve(trial, "assets/vendor/basemaps-LICENSE.md"), `${staging}/basemaps-LICENSE.md`);

for (const flavor of ["light", "dark"] as const) {
  const style = surfaceMapStyle({
    version: 8,
    name: `Onon surface roads · Protomaps ${flavor}`,
    sources: {
      protomaps: {
        type: "vector",
        url: "pmtiles://__MAP_ROOT__/sydney.pmtiles",
        attribution: '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a> | Protomaps',
      },
    },
    glyphs: "__MAP_ROOT__/fonts/{fontstack}/{range}.pbf",
    sprite: `__MAP_ROOT__/sprites/v4/${flavor}`,
    layers: context.basemaps.layers("protomaps", context.basemaps.namedFlavor(flavor), { lang: "en" }),
  });
  style.name = `Onon surface roads · Protomaps ${flavor}`;
  for (const layer of style.layers) {
    if ((layer.id === "roads_labels_minor" || layer.id === "roads_labels_major") && layer.type === "symbol") {
      layer.layout = { ...layer.layout, "text-size": ["interpolate", ["linear"], ["zoom"], 12, 13, 17, 17, 19, 20] };
      if (flavor === "dark") layer.paint = {
        ...layer.paint, "text-color": "#ece9f2", "text-halo-color": "#15151b", "text-halo-width": 1.5,
      };
    }
  }
  const errors = validateStyleMin(style);
  if (errors.length) throw new Error(errors.map((error) => error.message).join("\n"));
  writeFileSync(`${staging}/${flavor}.json`, `${JSON.stringify(style, null, 2)}\n`);
  for (const suffix of [".json", ".png", "@2x.json", "@2x.png"]) {
    cpSync(resolve(trial, `assets/sprites/v4/${flavor}${suffix}`), `${staging}/sprites/v4/${flavor}${suffix}`);
  }
}
writeFileSync(`${staging}/provenance.json`, readFileSync(resolve(trial, "provenance/extract-metadata.json")));
rmSync(output, { recursive: true, force: true });
renameSync(staging, output);
console.log(`Bundled offline Sydney map prepared: ${output}`);
