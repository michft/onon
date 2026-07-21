import { useEffect, useRef } from "react";
import maplibregl, { type GeoJSONSource, type MapMouseEvent } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { DISPLAY_PROFILES } from "./profiles";
import { printBounds } from "./print-layout";
import type { EditMode, MapManifest, Orientation, PrintScale, ProfileName, TrailOverlay } from "./types";

interface MapCanvasProps {
  manifest: MapManifest;
  profile: ProfileName;
  trail: TrailOverlay | null;
  mode: EditMode;
  print: { scale: PrintScale; orientation: Orientation; center: [number, number] } | null;
  onMapClick: (longitude: number, latitude: number) => void;
  onCenterChange: (center: [number, number]) => void;
}

const emptyLines: GeoJSON.Feature<GeoJSON.MultiLineString> = {
  type: "Feature", properties: {}, geometry: { type: "MultiLineString", coordinates: [] }
};

export function MapCanvas(props: MapCanvasProps): React.JSX.Element {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const propsRef = useRef(props);
  propsRef.current = props;

  useEffect(() => {
    if (!containerRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: props.manifest.styles[props.profile],
      center: [151.12, -33.87],
      zoom: 10.5,
      maxBounds: [[props.manifest.bounds[0], props.manifest.bounds[1]], [props.manifest.bounds[2], props.manifest.bounds[3]]],
      attributionControl: false
    });
    map.addControl(new maplibregl.NavigationControl(), "top-right");
    map.addControl(new maplibregl.AttributionControl({
      compact: true,
      customAttribution: "© OpenMapTiles © OpenStreetMap contributors"
    }));
    const install = (): void => {
      installOverlayLayers(map, propsRef.current.profile);
      updateOverlayData(map, propsRef.current.trail, propsRef.current.print);
    };
    map.on("style.load", install);
    map.on("click", (event: MapMouseEvent) => propsRef.current.onMapClick(event.lngLat.lng, event.lngLat.lat));
    map.on("moveend", () => {
      const center = map.getCenter();
      propsRef.current.onCenterChange([center.lng, center.lat]);
    });
    mapRef.current = map;
    return () => { mapRef.current = null; map.remove(); };
  }, [props.manifest]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.getCanvas().style.cursor = props.mode === "inspect" ? "grab" : "crosshair";
  }, [props.mode]);

  const previousProfile = useRef(props.profile);
  useEffect(() => {
    const map = mapRef.current;
    if (!map || previousProfile.current === props.profile) return;
    previousProfile.current = props.profile;
    map.setStyle(props.manifest.styles[props.profile]);
  }, [props.manifest.styles, props.profile]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map?.isStyleLoaded()) return;
    updateOverlayData(map, props.trail, props.print);
  }, [props.trail, props.print]);

  const previousTrailId = useRef<string | null>(null);
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !props.trail || previousTrailId.current === props.trail.id) return;
    previousTrailId.current = props.trail.id;
    const coordinates = props.trail.geometry.coordinates.flat();
    if (coordinates.length === 0) return;
    const bounds = coordinates.reduce(
      (value, coordinate) => value.extend(coordinate as [number, number]),
      new maplibregl.LngLatBounds(coordinates[0] as [number, number], coordinates[0] as [number, number])
    );
    map.fitBounds(bounds, { padding: 60, maxZoom: 15 });
  }, [props.trail]);

  return <div ref={containerRef} className="map" aria-label="Editable trail map" />;
}

function installOverlayLayers(map: maplibregl.Map, profileName: ProfileName): void {
  if (map.getSource("trail")) return;
  const profile = DISPLAY_PROFILES[profileName];
  map.addSource("trail", { type: "geojson", data: emptyLines });
  map.addSource("waypoints", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
  map.addSource("arrows", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
  map.addSource("print-crop", { type: "geojson", data: emptyLines });
  map.addLayer({
    id: "trail-outline", type: "line", source: "trail",
    paint: { "line-color": profile.trailOutline, "line-width": 8, "line-opacity": 0.95 },
    layout: { "line-cap": "round", "line-join": "round" }
  });
  map.addLayer({
    id: "trail-line", type: "line", source: "trail",
    paint: { "line-color": profile.trailColour, "line-width": 4, "line-dasharray": profile.trailDash },
    layout: { "line-cap": "round", "line-join": "round" }
  });
  map.addLayer({ id: "waypoint-outer", type: "circle", source: "waypoints", paint: {
    "circle-radius": 8, "circle-color": "#ffffff", "circle-stroke-color": profile.trailColour, "circle-stroke-width": 2.5
  } });
  map.addLayer({ id: "waypoint-dot", type: "circle", source: "waypoints", paint: {
    "circle-radius": 2.5, "circle-color": profile.trailColour
  } });
  map.addLayer({
    id: "direction-arrows", type: "symbol", source: "arrows",
    layout: {
      "text-field": "➤", "text-font": ["Open Sans Regular"], "text-size": 22, "text-rotate": ["get", "mapRotation"],
      "text-rotation-alignment": "map", "text-allow-overlap": true
    },
    paint: { "text-color": profile.trailColour, "text-halo-color": "#ffffff", "text-halo-width": 1.5 }
  });
  map.addLayer({
    id: "print-crop-line", type: "line", source: "print-crop",
    paint: { "line-color": "#111111", "line-width": 2, "line-dasharray": [4, 2] }
  });
}

function updateOverlayData(
  map: maplibregl.Map,
  trail: TrailOverlay | null,
  print: MapCanvasProps["print"]
): void {
  const trailData: GeoJSON.Feature<GeoJSON.MultiLineString> = trail
    ? { type: "Feature", properties: {}, geometry: trail.geometry }
    : emptyLines;
  setData(map, "trail", trailData);
  setData(map, "waypoints", {
    type: "FeatureCollection",
    features: trail?.waypoints.map((waypoint) => ({
      type: "Feature" as const, properties: { id: waypoint.id, label: waypoint.label },
      geometry: { type: "Point" as const, coordinates: [waypoint.longitude, waypoint.latitude] }
    })) ?? []
  });
  setData(map, "arrows", {
    type: "FeatureCollection",
    features: trail?.directionArrows.map((arrow) => ({
      type: "Feature" as const, properties: { id: arrow.id, mapRotation: arrow.bearing - 90 },
      geometry: { type: "Point" as const, coordinates: [arrow.longitude, arrow.latitude] }
    })) ?? []
  });
  const cropCoordinates = print ? cropLine(printBounds(print.center, print.scale, print.orientation)) : [];
  setData(map, "print-crop", {
    type: "Feature", properties: {}, geometry: { type: "MultiLineString", coordinates: cropCoordinates.length ? [cropCoordinates] : [] }
  });
}

function setData(map: maplibregl.Map, id: string, data: GeoJSON.GeoJSON): void {
  (map.getSource(id) as GeoJSONSource | undefined)?.setData(data);
}

function cropLine(bounds: [number, number, number, number]): number[][] {
  const [west, south, east, north] = bounds;
  return [[west, south], [east, south], [east, north], [west, north], [west, south]];
}
