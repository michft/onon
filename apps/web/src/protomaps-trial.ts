import maplibregl, { type CameraOptions } from "maplibre-gl";
import type { StyleSpecification } from "@maplibre/maplibre-gl-style-spec";
import "maplibre-gl/dist/maplibre-gl.css";
import "./protomaps-trial.css";

const scenes: Record<string, CameraOptions> = {
  streets: { center: [151.2024, -33.8685], zoom: 17, bearing: 45 },
  harbour: { center: [151.210, -33.856], zoom: 14.5, bearing: 0 },
  park: { center: [151.216, -33.863], zoom: 16, bearing: 0 }
};
const status = document.querySelector<HTMLElement>("#status")!;

async function start() {
  const response = await fetch("/light.json");
  if (!response.ok) throw new Error(`Local style unavailable (${response.status})`);
  const style: StyleSpecification = await response.json();
  const map = new maplibregl.Map({
    container: "map", style, ...scenes.streets,
    maxBounds: [[151.15, -33.92], [151.25, -33.80]], minZoom: 12, maxZoom: 19
  });
  map.addControl(new maplibregl.NavigationControl(), "top-right");
  let failed = false;
  map.on("error", (event) => {
    failed = true;
    status.textContent = "Map asset failed to load. Check local servers.";
    console.error(event.error);
  });
  map.on("idle", () => {
    if (!failed) status.textContent = "Local tiles ready · surface roads + walking paths";
  });
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-scene]")) {
    button.addEventListener("click", () => {
      const scene = scenes[button.dataset.scene ?? ""];
      if (!scene) return;
      for (const candidate of document.querySelectorAll("[data-scene]")) {
        candidate.setAttribute("aria-pressed", String(candidate === button));
      }
      map.jumpTo(scene);
    });
  }
}
void start().catch((error: unknown) => {
  status.textContent = "Local map unavailable. Check local servers.";
  console.error(error);
});
