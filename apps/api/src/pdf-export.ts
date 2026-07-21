import PDFDocument from "pdfkit";
import { config } from "./config.js";
import { calculatePrintLayout, type Orientation, type PrintScale } from "./domain/print-layout.js";
import { loadTrail, type TrailDocument } from "./trails.js";

type ProfileName = "screen" | "blueLightPrint" | "greyscalePrint";

interface PdfExportRequest {
  trailOverlayId: string;
  profile: ProfileName;
  orientation: Orientation;
  scale: PrintScale;
  center: [longitude: number, latitude: number];
}

const PT_PER_MM = 72 / 25.4;
const profileStyle: Record<ProfileName, { trail: string; waypoint: string; text: string; styleId: string; dash: [number, number] | null }> = {
  screen: { trail: "#d64000", waypoint: "#161616", text: "#161616", styleId: "screen", dash: null },
  blueLightPrint: { trail: "#8c2500", waypoint: "#111111", text: "#111111", styleId: "blue-light-print", dash: [8, 3] },
  greyscalePrint: { trail: "#111111", waypoint: "#000000", text: "#000000", styleId: "greyscale-print", dash: [10, 4] }
};

export async function renderPdf(input: PdfExportRequest): Promise<Buffer> {
  const trail = await loadTrail(input.trailOverlayId);
  const layout = calculatePrintLayout(
    { longitude: input.center[0], latitude: input.center[1] },
    input.scale,
    input.orientation
  );
  const style = profileStyle[input.profile];
  const rasterUrl = new URL(
    `/styles/${style.styleId}/static/${layout.bounds.join(",")}/${layout.rasterWidthPx}x${layout.rasterHeightPx}.png`,
    config.TILESERVER_URL
  );
  const rasterResponse = await fetch(rasterUrl);
  if (!rasterResponse.ok) throw new PdfExportError(502, `tile_renderer_${rasterResponse.status}`);
  const raster = Buffer.from(await rasterResponse.arrayBuffer());
  return composePdf(trail, input, layout, raster, style);
}

function composePdf(
  trail: TrailDocument,
  input: PdfExportRequest,
  layout: ReturnType<typeof calculatePrintLayout>,
  raster: Buffer,
  style: { trail: string; waypoint: string; text: string; dash: [number, number] | null }
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const document = new PDFDocument({
      autoFirstPage: false,
      compress: true,
      info: { Title: trail.name, Author: "Onon" }
    });
    const chunks: Buffer[] = [];
    document.on("data", (chunk: Buffer) => chunks.push(chunk));
    document.on("error", reject);
    document.on("end", () => resolve(Buffer.concat(chunks)));
    document.addPage({ size: "A4", layout: input.orientation, margin: 0 });

    const margin = 12 * PT_PER_MM;
    const header = 18 * PT_PER_MM;
    const mapX = margin;
    const mapY = margin + header;
    const mapWidth = layout.mapWidthMm * PT_PER_MM;
    const mapHeight = layout.mapHeightMm * PT_PER_MM;
    document.image(raster, mapX, mapY, { width: mapWidth, height: mapHeight });
    document.save().rect(mapX, mapY, mapWidth, mapHeight).clip();

    const project = ([longitude, latitude]: number[]): [number, number] => {
      if (longitude === undefined || latitude === undefined) throw new Error("Invalid map coordinate");
      const [west, south, east, north] = layout.bounds;
      const northY = mercatorY(north);
      const southY = mercatorY(south);
      return [
        mapX + (longitude - west) / (east - west) * mapWidth,
        mapY + (northY - mercatorY(latitude)) / (northY - southY) * mapHeight
      ];
    };
    document.lineCap("round").lineJoin("round").strokeColor("#ffffff").lineWidth(3.8);
    strokeTrail(document, trail, project);
    document.strokeColor(style.trail).lineWidth(2.2);
    if (style.dash) document.dash(style.dash[0], { space: style.dash[1] });
    else document.undash();
    strokeTrail(document, trail, project);
    document.undash();
    for (const waypoint of trail.waypoints) {
      const [x, y] = project([waypoint.longitude, waypoint.latitude]);
      document.circle(x, y, 5).fillAndStroke("#ffffff", style.waypoint);
      document.circle(x, y, 1.5).fill(style.waypoint);
    }
    for (const arrow of trail.directionArrows) {
      const [x, y] = project([arrow.longitude, arrow.latitude]);
      drawArrow(document, x, y, arrow.bearing, style.trail);
    }
    document.restore();

    document.fillColor(style.text).fontSize(14).text(trail.name, margin, margin, { lineBreak: false });
    document.fontSize(8).text(`A4 ${input.orientation} · 1:${input.scale.toLocaleString("en-AU")}`, margin, margin + 18, { lineBreak: false });
    drawLegend(document, mapX + mapWidth - 190, margin + 13, style);
    drawNorthArrow(document, mapX + mapWidth - 20, mapY + 28, style.text);
    drawScaleBar(document, mapX + 12, mapY + mapHeight - 18, layout.groundWidthM, mapWidth, style.text);
    document.fontSize(6).fillColor(style.text).text(
      "© OpenMapTiles © OpenStreetMap contributors",
      mapX + 4,
      mapY + mapHeight - 8,
      { width: mapWidth - 8, align: "right", lineBreak: false }
    );
    document.end();
  });
}

function drawLegend(
  document: PDFKit.PDFDocument,
  x: number,
  y: number,
  style: { trail: string; waypoint: string; text: string; dash: [number, number] | null }
): void {
  document.save().fontSize(6.5).fillColor(style.text);
  document.strokeColor(style.trail).lineWidth(2);
  if (style.dash) document.dash(style.dash[0], { space: style.dash[1] });
  document.moveTo(x, y).lineTo(x + 18, y).stroke().undash();
  document.text("Trail", x + 22, y - 4, { lineBreak: false });

  const waypointX = x + 65;
  document.circle(waypointX, y, 4).fillAndStroke("#ffffff", style.waypoint);
  document.circle(waypointX, y, 1.2).fill(style.waypoint);
  document.fillColor(style.text).text("Waypoint", waypointX + 8, y - 4, { lineBreak: false });

  const arrowX = x + 130;
  drawArrow(document, arrowX, y, 90, style.trail);
  document.fillColor(style.text).text("Direction", arrowX + 9, y - 4, { lineBreak: false });
  document.restore();
}

function mercatorY(latitude: number): number {
  const clamped = Math.max(-85.05112878, Math.min(85.05112878, latitude));
  const radians = clamped * Math.PI / 180;
  return Math.log(Math.tan(Math.PI / 4 + radians / 2));
}

function strokeTrail(
  document: PDFKit.PDFDocument,
  trail: TrailDocument,
  project: (coordinate: number[]) => [number, number]
): void {
  for (const line of trail.geometry.coordinates) {
    const first = line[0];
    if (!first) continue;
    document.moveTo(...project(first));
    for (const coordinate of line.slice(1)) document.lineTo(...project(coordinate));
  }
  document.stroke();
}

function drawArrow(document: PDFKit.PDFDocument, x: number, y: number, bearing: number, colour: string): void {
  document.save().translate(x, y).rotate(bearing).fillColor(colour);
  document.moveTo(0, -7).lineTo(4.5, 4).lineTo(0, 2).lineTo(-4.5, 4).closePath().fill();
  document.restore();
}

function drawNorthArrow(document: PDFKit.PDFDocument, x: number, y: number, colour: string): void {
  document.save().fillColor(colour).fontSize(8).text("N", x - 3, y - 17, { lineBreak: false });
  document.moveTo(x, y - 7).lineTo(x + 5, y + 7).lineTo(x, y + 4).lineTo(x - 5, y + 7).closePath().fill();
  document.restore();
}

function drawScaleBar(
  document: PDFKit.PDFDocument,
  x: number,
  y: number,
  groundWidthM: number,
  mapWidth: number,
  colour: string
): void {
  const target = groundWidthM / 5;
  const magnitude = 10 ** Math.floor(Math.log10(target));
  const scaleM = [1, 2, 5].map((factor) => factor * magnitude).filter((value) => value <= target).at(-1) ?? magnitude;
  const width = scaleM / groundWidthM * mapWidth;
  document.strokeColor(colour).lineWidth(1.5).moveTo(x, y).lineTo(x + width, y).stroke();
  document.moveTo(x, y - 3).lineTo(x, y + 3).moveTo(x + width, y - 3).lineTo(x + width, y + 3).stroke();
  document.fillColor(colour).fontSize(6).text(scaleM >= 1_000 ? `${scaleM / 1_000} km` : `${scaleM} m`, x, y - 12, { lineBreak: false });
}

export class PdfExportError extends Error {
  constructor(public readonly statusCode: number, message: string) { super(message); }
}
