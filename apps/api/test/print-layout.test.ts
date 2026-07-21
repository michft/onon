import { describe, expect, it } from "vitest";
import { calculatePrintLayout } from "../src/domain/print-layout.js";

describe("calculatePrintLayout", () => {
  it("uses exact A4 portrait dimensions and scale", () => {
    const layout = calculatePrintLayout({ latitude: -33.8688, longitude: 151.2093 }, 10_000, "portrait");
    expect(layout.pageWidthMm).toBe(210);
    expect(layout.pageHeightMm).toBe(297);
    expect(layout.groundWidthM).toBe(1_860);
    expect(layout.groundHeightM).toBe(2_550);
  });

  it("rotates the A4 page in landscape", () => {
    const layout = calculatePrintLayout({ latitude: -33.8688, longitude: 151.2093 }, 25_000, "landscape");
    expect(layout.pageWidthMm).toBe(297);
    expect(layout.pageHeightMm).toBe(210);
    expect(layout.groundWidthM).toBeGreaterThan(layout.groundHeightM);
  });
});
