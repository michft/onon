import type { ProfileName } from "./types";

export interface DisplayProfile {
  id: ProfileName;
  label: string;
  trailColour: string;
  trailOutline: string;
  trailDash: number[];
  importantLuminances: number[];
}

export const DISPLAY_PROFILES: Record<ProfileName, DisplayProfile> = {
  screen: {
    id: "screen", label: "Screen colour", trailColour: "#d64000", trailOutline: "#fff7e8",
    trailDash: [1000, 0.01], importantLuminances: [0.08, 0.29, 0.56, 0.83]
  },
  blueLightPrint: {
    id: "blueLightPrint", label: "Blue-light paper", trailColour: "#8c2500", trailOutline: "#ffffff",
    trailDash: [4, 1.5], importantLuminances: [0.06, 0.27, 0.53, 0.82]
  },
  greyscalePrint: {
    id: "greyscalePrint", label: "Greyscale paper", trailColour: "#111111", trailOutline: "#ffffff",
    trailDash: [5, 2], importantLuminances: [0.04, 0.28, 0.55, 0.86]
  }
};

export function minimumLuminanceSeparation(values: readonly number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted.slice(1).reduce((minimum, value, index) => {
    const previous = sorted[index];
    return previous === undefined ? minimum : Math.min(minimum, value - previous);
  }, Number.POSITIVE_INFINITY);
}
