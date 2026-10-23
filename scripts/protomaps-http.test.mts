import assert from "node:assert/strict";
import { test } from "node:test";
import { createServer, request, type Server } from "node:http";
import { once } from "node:events";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { createRequire } from "node:module";
import { gzipSync } from "node:zlib";
import { prepareTrialSite, trialConfig, trialServer } from "./protomaps-http.mts";
import type { surfaceMapStyle } from "../apps/web/src/protomaps-style.ts";
type StyleSpecification = Parameters<typeof surfaceMapStyle>[0];

const { featureFilter, validateStyleMin } = createRequire(new URL("../apps/web/package.json", import.meta.url))(
  "@maplibre/maplibre-gl-style-spec",
) as {
  featureFilter: (filter: unknown) => { filter: (globals: { zoom: number }, feature: { type: string; properties: Record<string, unknown> }) => boolean };
  validateStyleMin: (style: StyleSpecification) => { message: string }[];
};

const lan = { ONON_PROTOMAPS_BIND_ADDRESS: "0.0.0.0", ONON_PROTOMAPS_PUBLIC_HOST: "192.168.1.20" };

test("loopback default and explicit LAN config produce one absolute advertised origin", () => {
  assert.equal(trialConfig({}).origin, "http://127.0.0.1:8083");
  assert.equal(trialConfig({}).bind, "127.0.0.1");
  for (const host of ["192.168.1.20", "mac.local", "mac.studio.local", "10.1.2.3", "172.16.0.1"]) {
    const config = trialConfig({ ...lan, ONON_PROTOMAPS_PUBLIC_HOST: host, ONON_PROTOMAPS_PORT: "9083" });
    assert.equal(config.origin, `http://${host}:9083`);
    assert.equal(config.tileOrigin, "http://127.0.0.1:8082");
  }
});

test("reject unsafe hosts, partial LAN opt-in, malformed ports and unsafe paths before startup", () => {
  for (const host of ["", "http://mac.local", "mac.local:80", "mac.local/path", "mac.local?x", "mac.local#x", "x@mac.local", "mac.local\n", "0.0.0.0", "8.8.8.8", "192.168.1.999", "192.168.01.2", "[::]", "evil.com", "-x.local"]) {
    assert.throws(() => trialConfig({ ...lan, ONON_PROTOMAPS_PUBLIC_HOST: host }), /PUBLIC_HOST/);
  }
  for (const env of [
    { ONON_PROTOMAPS_BIND_ADDRESS: "0.0.0.0" }, { ONON_PROTOMAPS_PUBLIC_HOST: "mac.local" },
    { ...lan, ONON_PROTOMAPS_BIND_ADDRESS: "192.168.1.21" },
    { ...lan, ONON_PROTOMAPS_BIND_ADDRESS: "evil.local" },
    { ONON_PROTOMAPS_PUBLIC_HOST: "127.0.0.2" },
    { ONON_PROTOMAPS_PUBLIC_HOST: "localhost", ONON_PROTOMAPS_BIND_ADDRESS: "127.0.0.2" },
    { ONON_PROTOMAPS_PORT: "0" }, { ONON_PROTOMAPS_PORT: "65536" }, { ONON_PROTOMAPS_PORT: "80/x" },
    { ONON_PROTOMAPS_TILE_PORT: "8083" },
    { ONON_DATA_ROOT: "/" }, { ONON_DATA_ROOT: "relative" }, { ONON_DATA_ROOT: "/tmp/../private" }, { ONON_DATA_ROOT: "/tmp/with\nnewline" },
    { ONON_PROTOMAPS_TRIAL_DIR: "relative" },
    { ONON_DATA_ROOT: "/tmp/onon", ONON_PROTOMAPS_TRIAL_DIR: "/tmp/onon/protomaps-trial/site" },
  ]) assert.throws(() => trialConfig(env));
});

test("reject output aliases into retained cache, filesystem root or unrelated data and preserve files", () => {
  const directory = mkdtempSync(resolve(tmpdir(), "onon-protomaps-alias-"));
  try {
    const cache = resolve(directory, "cache");
    mkdirSync(resolve(cache, "assets"), { recursive: true });
    writeFileSync(resolve(cache, "sydney.pmtiles"), "retained archive");
    writeFileSync(resolve(cache, "assets/keep"), "retained asset");
    const unrelated = resolve(directory, "unrelated");
    mkdirSync(unrelated);
    writeFileSync(resolve(unrelated, "keep"), "other user data");
    for (const [index, target] of [cache, resolve(cache, "assets"), "/", unrelated].entries()) {
      const output = resolve(directory, `output-${index}`);
      mkdirSync(resolve(output, "protomaps-trial"), { recursive: true });
      symlinkSync(target, resolve(output, "protomaps-trial/site"));
      assert.throws(() => trialConfig({ ONON_DATA_ROOT: output, ONON_PROTOMAPS_TRIAL_DIR: cache }), /retained|cache|output/i);
    }
    const alias = resolve(directory, "alias");
    symlinkSync(directory, alias);
    assert.throws(() => trialConfig({ ONON_DATA_ROOT: resolve(alias, "output-0"), ONON_PROTOMAPS_TRIAL_DIR: cache }), /retained|cache|output/i);
    assert.equal(readFileSync(resolve(cache, "sydney.pmtiles"), "utf8"), "retained archive");
    assert.equal(readFileSync(resolve(cache, "assets/keep"), "utf8"), "retained asset");
    assert.equal(readFileSync(resolve(unrelated, "keep"), "utf8"), "other user data");
    assert.equal(trialConfig({ ONON_DATA_ROOT: resolve(directory, "safe"), ONON_PROTOMAPS_TRIAL_DIR: cache }).trialDir, cache);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

function fixture() {
  const directory = mkdtempSync(resolve(tmpdir(), "onon-protomaps-http-"));
  try {
    const config = trialConfig({ ...lan, ONON_DATA_ROOT: directory });
    const assets = resolve(config.trialDir, "assets");
    mkdirSync(resolve(assets, "vendor"), { recursive: true });
    if (process.env.ONON_PROTOMAPS_TEST_CACHE) {
      // Copy retained assets into the private fixture. Never prepare into the retained cache.
      for (const path of ["vendor/basemaps.js", "vendor/basemaps-LICENSE.md", "fonts", "sprites"]) {
        cpSync(resolve(process.env.ONON_PROTOMAPS_TEST_CACHE, "assets", path), resolve(assets, path), { recursive: true });
      }
    } else {
      writeFileSync(resolve(assets, "vendor/basemaps.js"), `var basemaps = {
        namedFlavor: function (flavor) { return flavor; },
        layers: function (source, flavor) { return [
          {id: 'background', type: 'background', paint: {'background-color': flavor === 'dark' ? '#222' : '#fff'}},
          {id: 'roads', type: 'line', source: source, 'source-layer': 'roads', filter: ['in', 'kind', 'minor_road', 'major_road', 'highway']},
          {id: 'labels', type: 'symbol', source: source, 'source-layer': 'roads'}
        ]; }
      };`);
      writeFileSync(resolve(assets, "vendor/basemaps-LICENSE.md"), "fixture license");
      for (const font of ["Noto Sans Regular", "Noto Sans Italic", "Noto Sans Medium"]) {
        mkdirSync(resolve(assets, "fonts", font), { recursive: true });
        for (const range of ["0-255", "256-511", "768-1023", "1536-1791", "7680-7935", "8192-8447"]) {
          writeFileSync(resolve(assets, "fonts", font, `${range}.pbf`), `glyph fixture ${font} ${range}`);
        }
      }
      mkdirSync(resolve(assets, "sprites/v4"), { recursive: true });
      for (const flavor of ["light", "dark"]) for (const suffix of [".json", ".png", "@2x.json", "@2x.png"]) {
        writeFileSync(resolve(assets, `sprites/v4/${flavor}${suffix}`), suffix.endsWith("json") ? "{}" : "sprite fixture");
      }
    }
    return { directory, config };
  } catch (error) {
    rmSync(directory, { recursive: true, force: true });
    throw error;
  }
}

function visible(layer: StyleSpecification["layers"][number], properties: Record<string, unknown>) {
  assert.ok("filter" in layer);
  return featureFilter(layer.filter).filter({ zoom: 17 }, { type: "LineString", properties });
}

test("published light/dark JSON already contains surface filters and shared HTTP resources", () => {
  const { directory, config } = fixture();
  try {
    for (const origin of ["http://127.0.0.1:8083", config.origin]) {
      prepareTrialSite({ ...config, origin });
      for (const flavor of ["light", "dark"]) {
        const style = JSON.parse(readFileSync(resolve(config.siteDir, `${flavor}.json`), "utf8")) as StyleSpecification;
        assert.deepEqual(validateStyleMin(style), []);
        assert.equal(style.sources.protomaps?.type, "vector");
        assert.equal(style.sources.protomaps && "url" in style.sources.protomaps && style.sources.protomaps.url, `${origin}/sydney.json`);
        assert.equal(style.glyphs, `${origin}/fonts/{fontstack}/{range}.pbf`);
        assert.equal(style.sprite, `${origin}/sprites/v4/${flavor}`);
        assert.ok(style.name?.includes(flavor));
        const roads = style.layers.filter((layer) => "source-layer" in layer && layer["source-layer"] === "roads" && layer.id !== "walking-paths");
        assert.ok(roads.some((layer) => layer.type === "symbol"));
        for (const layer of roads) {
          for (const properties of [{ kind: "rail" }, { kind: "ferry" }, { kind: "path", kind_detail: "cycleway" }, { kind: "highway", is_tunnel: true }]) {
            assert.equal(visible(layer, properties), false, `${flavor}/${layer.id} excludes ${JSON.stringify(properties)}`);
          }
        }
        for (const properties of [
          { kind: "minor_road", kind_detail: "residential" },
          { kind: "highway", is_bridge: true, oneway: 1 },
          { kind: "highway", is_bridge: true, oneway: -1 },
        ]) {
          assert.ok(roads.some((layer) => layer.type === "line" && visible(layer, properties)), "Surface carriageways remain visible");
          assert.ok(roads.some((layer) => layer.type === "symbol" && visible(layer, properties)), "Surface road labels remain visible");
        }
        const paths = style.layers.filter((layer) => layer.id === "walking-paths");
        assert.equal(paths.length, 1);
        assert.equal(visible(paths[0]!, { kind: "path", kind_detail: "footway" }), true);
        assert.equal(visible(paths[0]!, { kind: "path", kind_detail: "footway", is_tunnel: true }), false);
        assert.equal(visible(paths[0]!, { kind: "path", kind_detail: "cycleway" }), false);
      }
    }
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

async function listen(server: Server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  return `http://127.0.0.1:${address.port}`;
}

function get(origin: string, path: string, method = "GET") {
  return new Promise<{ status: number; headers: import("node:http").IncomingHttpHeaders; body: Buffer }>((resolve, reject) => {
    const req = request(origin, { path, method }, (res) => {
      const chunks: Buffer[] = [];
      res.on("data", (chunk: Buffer) => chunks.push(chunk));
      res.on("error", reject);
      res.on("end", () => resolve({ status: res.statusCode!, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.on("error", reject);
    req.end();
  });
}

async function close(server: Server) {
  await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}

test("loopback HTTP TileJSON uses only the loopback origin, missing cached resources fail locally", async () => {
  const { directory, config } = fixture();
  const loopback = trialConfig({ ONON_DATA_ROOT: directory });
  let server: Server | undefined;
  try {
    prepareTrialSite(loopback);
    server = trialServer(loopback);
    const origin = await listen(server);
    const json = await get(origin, "/sydney.json");
    assert.deepEqual(JSON.parse(json.body.toString()).tiles, ["http://127.0.0.1:8083/sydney/{z}/{x}/{y}.mvt"]);
    rmSync(resolve(config.trialDir, "assets/fonts/Noto Sans Regular/0-255.pbf"));
    assert.throws(() => prepareTrialSite(loopback), /ENOENT/);
  } finally {
    if (server?.listening) await close(server);
    rmSync(directory, { recursive: true, force: true });
  }
});

test("HTTP route isolation, absolute TileJSON, published resources, raw compressed tiles and upstream failures", async () => {
  const { directory, config } = fixture();
  const seen: string[] = [];
  const tileBytes = gzipSync("vector tile fixture");
  let upstreamStatus = 200;
  const upstream = createServer((req, res) => {
    seen.push(`${req.method} ${req.url}`);
    res.writeHead(upstreamStatus, { "Content-Type": "application/vnd.mapbox-vector-tile", "Content-Encoding": "gzip", "Content-Length": tileBytes.length,
      Location: "http://external.invalid/private", "Set-Cookie": "private=secret" });
    res.end(req.method === "HEAD" ? undefined : tileBytes);
  });
  let server: Server | undefined;
  try {
    prepareTrialSite(config);
    writeFileSync(resolve(config.siteDir, "protomaps.html"), "published viewer");
    mkdirSync(resolve(config.siteDir, "assets"));
    writeFileSync(resolve(config.siteDir, "assets/protomaps-test.js"), "published bundle");
    writeFileSync(resolve(directory, "private.env"), "secret fixture");
    symlinkSync(resolve(directory, "private.env"), resolve(config.siteDir, "assets/leak.js"));
    const tileOrigin = await listen(upstream);
    server = trialServer({ ...config, tileOrigin });
    const origin = await listen(server);
    const json = await get(origin, "/sydney.json");
    assert.equal(json.status, 200);
    assert.deepEqual(JSON.parse(json.body.toString()), { tilejson: "3.0.0", name: "Retained Sydney Protomaps trial", scheme: "xyz",
      tiles: [`${config.origin}/sydney/{z}/{x}/{y}.mvt`], bounds: [151.15, -33.92, 151.25, -33.8], minzoom: 0, maxzoom: 15,
      attribution: '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a> | Protomaps' });
    const resources = ["/", "/protomaps.html", "/assets/protomaps-test.js", "/light.json", "/dark.json", "/basemaps-LICENSE.md"];
    for (const flavor of ["light", "dark"]) for (const suffix of [".json", ".png", "@2x.json", "@2x.png"]) {
      resources.push(`/sprites/v4/${flavor}${suffix}`);
    }
    for (const font of ["Noto Sans Regular", "Noto Sans Italic", "Noto Sans Medium"]) {
      for (const range of ["0-255", "256-511", "768-1023", "1536-1791", "7680-7935", "8192-8447"]) {
        resources.push(`/fonts/${encodeURIComponent(font)}/${range}.pbf`);
      }
    }
    for (const path of resources) {
      assert.equal((await get(origin, path)).status, 200, path);
      const head = await get(origin, path, "HEAD");
      assert.equal(head.status, 200, `HEAD ${path}`);
      assert.equal(head.body.length, 0);
    }
    for (const path of resources.filter((path) => path.startsWith("/fonts/") || path.startsWith("/sprites/"))) {
      const resource = await get(origin, path);
      assert.deepEqual(resource.body, readFileSync(resolve(config.trialDir, "assets", `.${decodeURIComponent(path)}`)));
    }
    const blocked = ["/sydney.pmtiles", "/other.json", "/other/0/0/0.mvt", "/sydney/16/0/0.mvt", "/sydney/0/1/0.mvt", "/sydney/0/0/1.mvt",
      "/sydney/-1/0/0.mvt", "/sydney/00/0/0.mvt", "/sydney/0/0/0.mvt/extra", "/tools/pmtiles", "/provenance/extract-metadata.json", "/assets/vendor/basemaps.js",
      "/assets/leak.js", "/api/v1/maps/manifest", "/.env", "/src/protomaps-trial.ts", "/@fs/private.env", "/fonts/", "/site/../private.env",
      "/%2e%2e/private.env", "/fonts%2fNoto%20Sans%20Regular/0-255.pbf", "/%252e%252e/private.env", "/%", "//private.env", "http://other/0/0/0.mvt"];
    for (const path of blocked) assert.ok([400, 404].includes((await get(origin, path)).status), path);
    assert.equal((await get(origin, "/sydney/0/0/0.mvt", "POST")).status, 405);
    assert.equal(seen.length, 0, "Rejected routes never reach upstream");
    const tile = await get(origin, "/sydney/0/0/0.mvt?untrusted=ignored");
    assert.equal(tile.status, 200);
    assert.deepEqual(tile.body, tileBytes);
    assert.equal(tile.headers["content-encoding"], "gzip");
    assert.equal(tile.headers.location, undefined);
    assert.equal(tile.headers["set-cookie"], undefined);
    assert.equal((await get(origin, "/sydney/0/0/0.mvt", "HEAD")).body.length, 0);
    assert.deepEqual(seen, ["GET /sydney/0/0/0.mvt", "HEAD /sydney/0/0/0.mvt"]);
    for (const status of [204, 404, 302, 500]) {
      upstreamStatus = status;
      assert.equal((await get(origin, "/sydney/0/0/0.mvt")).status, status === 302 || status === 500 ? 502 : status);
    }
    await close(upstream);
    assert.equal((await get(origin, "/sydney/0/0/0.mvt")).status, 502);
  } finally {
    if (server) await close(server);
    if (upstream.listening) await close(upstream);
    rmSync(directory, { recursive: true, force: true });
  }
});
