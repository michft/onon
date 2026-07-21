import { describe, expect, it } from "vitest";
import { applyTrailEdit } from "../src/domain/trail-edits.js";

describe("applyTrailEdit", () => {
  const indexes = [0, 1, 2, 3, 4, 5];

  it("trims a start without renumbering source samples", () => {
    expect(applyTrailEdit([indexes], { type: "trim_start", throughIndex: 1 })).toEqual([[2, 3, 4, 5]]);
  });

  it("removes one bounded section", () => {
    expect(applyTrailEdit([indexes], { type: "remove_range", fromIndex: 2, toIndex: 3 })).toEqual([[0, 1], [4, 5]]);
  });

  it("preserves an existing gap during later edits", () => {
    expect(applyTrailEdit([[0, 1, 2], [5, 6, 7]], { type: "trim_start", throughIndex: 0 })).toEqual([[1, 2], [5, 6, 7]]);
  });

  it("refuses edits which erase the trail", () => {
    expect(() => applyTrailEdit([indexes], { type: "trim_end", fromIndex: 1 })).toThrow("at least two");
  });
});
