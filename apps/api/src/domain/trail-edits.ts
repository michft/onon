export type TrailSegments = number[][];

export type TrailEdit =
  | { type: "trim_start"; throughIndex: number }
  | { type: "trim_end"; fromIndex: number }
  | { type: "remove_range"; fromIndex: number; toIndex: number };

export function applyTrailEdit(segments: TrailSegments, edit: TrailEdit): TrailSegments {
  const flattened = segments.flat();
  if (flattened.length < 2) throw new Error("Trail must contain at least two points");
  let removeFrom: number;
  let removeThrough: number;
  switch (edit.type) {
    case "trim_start":
      requirePosition(edit.throughIndex, flattened.length);
      removeFrom = 0;
      removeThrough = edit.throughIndex;
      break;
    case "trim_end":
      requirePosition(edit.fromIndex, flattened.length);
      removeFrom = edit.fromIndex;
      removeThrough = flattened.length - 1;
      break;
    case "remove_range":
      requirePosition(edit.fromIndex, flattened.length);
      requirePosition(edit.toIndex, flattened.length);
      if (edit.fromIndex > edit.toIndex) throw new Error("Section start must precede section end");
      removeFrom = edit.fromIndex;
      removeThrough = edit.toIndex;
      break;
  }
  const result: TrailSegments = [];
  let globalIndex = 0;
  for (const segment of segments) {
    let retained: number[] = [];
    for (const sourceIndex of segment) {
      const removed = globalIndex >= removeFrom && globalIndex <= removeThrough;
      if (removed) {
        if (retained.length >= 2) result.push(retained);
        retained = [];
      } else {
        retained.push(sourceIndex);
      }
      globalIndex += 1;
    }
    if (retained.length >= 2) result.push(retained);
  }
  if (result.flat().length < 2) throw new Error("Edit must leave at least two trail points");
  return result;
}

function requirePosition(position: number, count: number): void {
  if (!Number.isInteger(position) || position < 0 || position >= count) {
    throw new Error(`Index ${position} is outside trail with ${count} points`);
  }
}
