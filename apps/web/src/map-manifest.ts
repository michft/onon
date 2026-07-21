import type { MapManifest } from "./types";

export function useBrowserHostname(manifest: MapManifest, hostname: string): MapManifest {
  return {
    ...manifest,
    styles: {
      screen: withHostname(manifest.styles.screen, hostname),
      blueLightPrint: withHostname(manifest.styles.blueLightPrint, hostname),
      greyscalePrint: withHostname(manifest.styles.greyscalePrint, hostname)
    }
  };
}

function withHostname(value: string, hostname: string): string {
  const url = new URL(value);
  url.hostname = hostname;
  return url.toString();
}
