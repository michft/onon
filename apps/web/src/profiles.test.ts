import { describe, expect, it } from "vitest";
import { DISPLAY_PROFILES, minimumLuminanceSeparation } from "./profiles";

describe("recommended display profiles", () => {
  it.each(Object.values(DISPLAY_PROFILES))("keeps important classes separated in $label", (profile) => {
    expect(minimumLuminanceSeparation(profile.importantLuminances)).toBeGreaterThanOrEqual(0.2);
  });
});
