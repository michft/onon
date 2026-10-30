import maplibregl from "maplibre-gl";
import type { StyleSpecification } from "@maplibre/maplibre-gl-style-spec";
import "maplibre-gl/dist/maplibre-gl.css";
import "./protomaps-trial.css";
import { mapRegion } from "./protomaps-regions";

const status = document.querySelector<HTMLElement>("#status")!;

async function start() {
  const selectionResponse = await fetch("/region.json");
  if (!selectionResponse.ok) throw new Error(`Map region unavailable (${selectionResponse.status})`);
  const selection: unknown = await selectionResponse.json();
  if (!selection || typeof selection !== "object" || !("id" in selection) || typeof selection.id !== "string") {
    throw new Error("Invalid map region");
  }
  const region = mapRegion(selection.id);
  const scenes = region.scenes;
  document.querySelector("h1")!.textContent = `${region.name} run map`;
  document.title = `Onon · ${region.name} run map`;
  document.querySelector("#map")!.setAttribute("aria-label", `Interactive ${region.name} surface road map`);
  for (const button of document.querySelectorAll<HTMLButtonElement>("[data-scene]")) {
    const key = button.dataset.scene as keyof typeof scenes;
    if (scenes[key]) button.textContent = scenes[key].label;
  }
  const response = await fetch("/light.json");
  if (!response.ok) throw new Error(`Local style unavailable (${response.status})`);
  const style: StyleSpecification = await response.json();
  const map = new maplibregl.Map({
    container: "map", style, ...scenes.streets,
    maxBounds: [[region.bounds[0], region.bounds[1]], [region.bounds[2], region.bounds[3]]], minZoom: 12, maxZoom: 19
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
      const scene = scenes[button.dataset.scene as keyof typeof scenes];
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
