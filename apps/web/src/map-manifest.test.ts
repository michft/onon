import { describe, expect, it } from "vitest";
import { useBrowserHostname } from "./map-manifest";
import type { MapManifest } from "./types";

const manifest: MapManifest = {
  version: "sydney-test",
  bounds: [151, -34.04, 151.33, -33.7],
  overviewMaxZoom: 11,
  detailMaxZoom: 14,
  styles: {
    screen: "http://onon-host.local:8080/styles/screen/style.json",
    blueLightPrint: "http://onon-host.local:8080/styles/blue-light-print/style.json",
    greyscalePrint: "http://onon-host.local:8080/styles/greyscale-print/style.json"
  }
};

describe("browser map manifest", () => {
  it("uses the hostname that opened the web workspace while preserving the tile port", () => {
    const result = useBrowserHostname(manifest, "127.0.0.1");

    expect(result.styles.screen).toBe("http://127.0.0.1:8080/styles/screen/style.json");
    expect(result.styles.blueLightPrint).toBe("http://127.0.0.1:8080/styles/blue-light-print/style.json");
    expect(result.styles.greyscalePrint).toBe("http://127.0.0.1:8080/styles/greyscale-print/style.json");
  });
});
