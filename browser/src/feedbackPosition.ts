export type FeedbackCorner =
  "topLeft" | "topRight" | "bottomLeft" | "bottomRight";
export type Point = { x: number; y: number };
export type Bounds = {
  left: number;
  top: number;
  right: number;
  bottom: number;
};
export const positionKey = "sentry.feedback.corner";
export function readCorner(): FeedbackCorner {
  try {
    const saved = localStorage.getItem(positionKey);
    if (
      ["topLeft", "topRight", "bottomLeft", "bottomRight"].includes(saved ?? "")
    ) {
      return saved as FeedbackCorner;
    }
  } catch {}
  return "bottomRight";
}
export function saveCorner(corner: FeedbackCorner) {
  try {
    localStorage.setItem(positionKey, corner);
  } catch {}
}
export function cornerPoint(corner: FeedbackCorner, bounds: Bounds): Point {
  return {
    x: corner.endsWith("Left") ? bounds.left : bounds.right,
    y: corner.startsWith("top") ? bounds.top : bounds.bottom,
  };
}
export function nearestCorner(point: Point, bounds: Bounds): FeedbackCorner {
  return ((point.y < (bounds.top + bounds.bottom) / 2 ? "top" : "bottom") +
    (point.x < (bounds.left + bounds.right) / 2
      ? "Left"
      : "Right")) as FeedbackCorner;
}
export function keyCorner(
  corner: FeedbackCorner,
  key: string,
): FeedbackCorner | undefined {
  if (key === "ArrowLeft") {
    return corner.startsWith("top") ? "topLeft" : "bottomLeft";
  }
  if (key === "ArrowRight") {
    return corner.startsWith("top") ? "topRight" : "bottomRight";
  }
  if (key === "ArrowUp") {
    return corner.endsWith("Left") ? "topLeft" : "topRight";
  }
  if (key === "ArrowDown") {
    return corner.endsWith("Left") ? "bottomLeft" : "bottomRight";
  }
}
export function constrain(point: Point, bounds: Bounds): Point {
  return {
    x: Math.max(bounds.left, Math.min(bounds.right, point.x)),
    y: Math.max(bounds.top, Math.min(bounds.bottom, point.y)),
  };
}
