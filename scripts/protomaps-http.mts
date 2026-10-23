import { createServer, request } from "node:http";
import { cpSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { isAbsolute, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { createContext, runInContext } from "node:vm";
import { surfaceMapStyle } from "../apps/web/src/protomaps-style.ts";

type StyleSpecification = Parameters<typeof surfaceMapStyle>[0];
const { validateStyleMin } = createRequire(new URL("../apps/web/package.json", import.meta.url))(
  "@maplibre/maplibre-gl-style-spec",
) as { validateStyleMin: (style: StyleSpecification) => { message: string }[] };
const repo = fileURLToPath(new URL("../", import.meta.url));
const bounds = [151.15, -33.92, 151.25, -33.80];
const attribution = '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a> | Protomaps';
const fonts = ["Noto Sans Regular", "Noto Sans Italic", "Noto Sans Medium"];
const ranges = ["0-255", "256-511", "768-1023", "1536-1791", "7680-7935", "8192-8447"];

function localIPv4(host: string) {
  const octets = host.split(".").map(Number);
  if (!/^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$/.test(host) || octets.some((n) => n > 255)) return false;
  const [a, b] = octets;
  return a === 127 || a === 10 || (a === 172 && b! >= 16 && b! <= 31) ||
    (a === 192 && b === 168) || (a === 169 && b === 254);
}

function absoluteDirectory(path: string, name: string) {
  if (!isAbsolute(path) || path === "/" || normalize(path) !== path || /[\x00-\x1f]/.test(path)) {
    throw new Error(`${name} must be an absolute non-root path without dot segments`);
  }
  return path;
}

function port(value: string, name: string) {
  if (!/^[1-9]\d{0,4}$/.test(value) || Number(value) > 65535) throw new Error(`Invalid ${name}`);
  return Number(value);
}

export function trialConfig(env: NodeJS.ProcessEnv = process.env) {
  const bind = env.ONON_PROTOMAPS_BIND_ADDRESS ?? "127.0.0.1";
  const host = env.ONON_PROTOMAPS_PUBLIC_HOST ?? "127.0.0.1";
  const loopback = (value: string) => value === "localhost" || value.startsWith("127.");
  const localName = /^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+local$/;
  if (!(host === "localhost" || localIPv4(host) || (host.length <= 253 && localName.test(host)))) {
    throw new Error("ONON_PROTOMAPS_PUBLIC_HOST must be a local IPv4 address, localhost or .local hostname (no scheme, port or path)");
  }
  if (!(localIPv4(bind) || bind === "0.0.0.0")) throw new Error("ONON_PROTOMAPS_BIND_ADDRESS must be a local IPv4 address or 0.0.0.0");
  if (loopback(bind) !== loopback(host) || (!loopback(bind) && (!env.ONON_PROTOMAPS_BIND_ADDRESS || !env.ONON_PROTOMAPS_PUBLIC_HOST))) {
    throw new Error("LAN serving requires explicit non-loopback ONON_PROTOMAPS_BIND_ADDRESS and ONON_PROTOMAPS_PUBLIC_HOST");
  }
  if (bind !== "0.0.0.0" && ((localIPv4(host) && host !== bind) || (host === "localhost" && bind !== "127.0.0.1"))) {
    throw new Error("Advertised IPv4 host must match the bind address (or bind 0.0.0.0)");
  }
  const webPort = port(env.ONON_PROTOMAPS_PORT ?? "8083", "ONON_PROTOMAPS_PORT");
  const tilePort = port(env.ONON_PROTOMAPS_TILE_PORT ?? "8082", "ONON_PROTOMAPS_TILE_PORT");
  if (webPort === tilePort) throw new Error("Web and private tile ports must differ");
  const dataRoot = absoluteDirectory(env.ONON_DATA_ROOT ?? resolve(repo, ".local/onon"), "ONON_DATA_ROOT");
  const trialDir = absoluteDirectory(env.ONON_PROTOMAPS_TRIAL_DIR ?? resolve(dataRoot, "protomaps-trial"), "ONON_PROTOMAPS_TRIAL_DIR");
  const siteDir = resolve(dataRoot, "protomaps-trial/site");
  if (trialDir === siteDir || trialDir.startsWith(`${siteDir}/`)) throw new Error("Trial cache must be outside the published site");
  return { bind, host, webPort, tilePort, trialDir, siteDir,
    origin: `http://${host}:${webPort}`, tileOrigin: `http://127.0.0.1:${tilePort}` };
}

/** Publish only the pinned runtime resources, never the cache/provenance/tool folders. */
export function prepareTrialSite(config: ReturnType<typeof trialConfig>) {
  const context = createContext({}) as ReturnType<typeof createContext> & {
    basemaps: {
      namedFlavor: (flavor: string) => unknown;
      layers: (source: string, flavor: unknown, options: { lang: string }) => StyleSpecification["layers"];
    };
  };
  runInContext(readFileSync(resolve(config.trialDir, "assets/vendor/basemaps.js"), "utf8"), context);
  mkdirSync(config.siteDir, { recursive: true });
  for (const flavor of ["light", "dark"]) {
    const style = surfaceMapStyle({
      version: 8, name: `Onon surface roads · Protomaps ${flavor}`,
      sources: { protomaps: { type: "vector", url: `${config.origin}/sydney.json`, attribution } },
      glyphs: `${config.origin}/fonts/{fontstack}/{range}.pbf`,
      sprite: `${config.origin}/sprites/v4/${flavor}`,
      layers: context.basemaps.layers("protomaps", context.basemaps.namedFlavor(flavor), { lang: "en" }),
    });
    style.name = `Onon surface roads · Protomaps ${flavor}`;
    const errors = validateStyleMin(style);
    if (errors.length) throw new Error(errors.map((error) => error.message).join("\n"));
    writeFileSync(resolve(config.siteDir, `${flavor}.json`), `${JSON.stringify(style, null, 2)}\n`);
    for (const suffix of [".json", ".png", "@2x.json", "@2x.png"]) {
      const path = `sprites/v4/${flavor}${suffix}`;
      mkdirSync(resolve(config.siteDir, "sprites/v4"), { recursive: true });
      cpSync(resolve(config.trialDir, "assets", path), resolve(config.siteDir, path));
    }
  }
  for (const font of fonts) {
    mkdirSync(resolve(config.siteDir, "fonts", font), { recursive: true });
    for (const range of ranges) {
      const path = `fonts/${font}/${range}.pbf`;
      cpSync(resolve(config.trialDir, "assets", path), resolve(config.siteDir, path));
    }
  }
  cpSync(resolve(config.trialDir, "assets/vendor/basemaps-LICENSE.md"), resolve(config.siteDir, "basemaps-LICENSE.md"));
}

/** One origin for native HTTP downloaders and the browser. PMTiles stays private. */
export function trialServer(config: ReturnType<typeof trialConfig>) {
  const site = realpathSync(config.siteDir);
  return createServer(async (req, res) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Cache-Control", "no-cache");
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.writeHead(405, { Allow: "GET, HEAD" }).end();
      return;
    }
    // Inspect the raw path: URL normalization must not turn traversal into an allowed route.
    const raw = (req.url ?? "").split("?")[0]!;
    let path: string;
    try { path = decodeURIComponent(raw); } catch { res.writeHead(400).end(); return; }
    if (!path.startsWith("/") || /[%\\\0]/.test(path) || /%2f|%5c/i.test(raw) || path.split("/").some((part) => part === "." || part === "..")) {
      res.writeHead(400).end();
      return;
    }
    if (path === "/sydney.json") {
      const body = JSON.stringify({ tilejson: "3.0.0", name: "Retained Sydney Protomaps trial", scheme: "xyz",
        tiles: [`${config.origin}/sydney/{z}/{x}/{y}.mvt`], bounds, minzoom: 0, maxzoom: 15, attribution });
      res.writeHead(200, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) });
      res.end(req.method === "HEAD" ? undefined : body);
      return;
    }
    const tile = /^\/sydney\/(0|[1-9]\d?)\/(0|[1-9]\d*)\/(0|[1-9]\d*)\.mvt$/.exec(path);
    if (tile) {
      const [z, x, y] = tile.slice(1).map(Number) as [number, number, number];
      if (z > 15 || x >= 2 ** z || y >= 2 ** z) { res.writeHead(404).end(); return; }
      const upstream = request(`${config.tileOrigin}${path}`, { method: req.method, headers: { "Accept-Encoding": "gzip" } }, (source) => {
        if (source.statusCode !== 200 && source.statusCode !== 204 && source.statusCode !== 404) {
          source.resume(); res.writeHead(502).end(); return;
        }
        res.statusCode = source.statusCode;
        res.setHeader("Content-Type", "application/vnd.mapbox-vector-tile");
        for (const header of ["content-encoding", "content-length"] as const) {
          const value = source.headers[header];
          if (value !== undefined) res.setHeader(header, value);
        }
        source.on("error", () => res.destroy());
        source.pipe(res);
      });
      upstream.setTimeout(15_000, () => upstream.destroy(new Error("Tile upstream timeout")));
      upstream.on("error", () => { if (!res.headersSent) res.writeHead(502).end(); else res.destroy(); });
      res.on("close", () => upstream.destroy());
      upstream.end();
      return;
    }
    const file = path === "/" ? "/protomaps.html" : path;
    const allowed = /^\/(protomaps\.html|light\.json|dark\.json|basemaps-LICENSE\.md)$/.test(file) ||
      /^\/assets\/[\w-]+\.(js|css)$/.test(file) ||
      /^\/sprites\/v4\/(light|dark)(@2x)?\.(json|png)$/.test(file) ||
      fonts.some((font) => ranges.some((range) => file === `/fonts/${font}/${range}.pbf`));
    if (!allowed) { res.writeHead(404).end(); return; }
    try {
      const target = realpathSync(resolve(site, `.${file}`));
      if (!target.startsWith(`${site}${sep}`) || !statSync(target).isFile()) { res.writeHead(404).end(); return; }
      const body = readFileSync(target);
      const type = file.endsWith(".html") ? "text/html; charset=utf-8" : file.endsWith(".js") ? "text/javascript" :
        file.endsWith(".css") ? "text/css" : file.endsWith(".json") ? "application/json" :
          file.endsWith(".png") ? "image/png" : file.endsWith(".md") ? "text/plain" : "application/x-protobuf";
      res.writeHead(200, { "Content-Type": type, "Content-Length": body.length });
      res.end(req.method === "HEAD" ? undefined : body);
    } catch { res.writeHead(404).end(); }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const config = trialConfig();
  if (process.argv[2] === "--check-config") console.log(config.origin);
  else if (process.argv[2] === "--prepare") prepareTrialSite(config);
  else if (process.argv.length === 2) {
    const server = trialServer(config);
    server.on("error", (error) => { console.error(error.message); process.exitCode = 1; });
    server.listen(config.webPort, config.bind, () => console.log(`Open ${config.origin}/protomaps.html (HTTP tiles/styles; trusted LAN only)`));
    for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => server.close());
  } else throw new Error("Usage: node scripts/protomaps-http.mts [--check-config|--prepare]");
}
