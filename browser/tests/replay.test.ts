// @vitest-environment jsdom
import { beforeEach, expect, it, vi } from "vitest";

const mock = vi.hoisted(() => ({
  before: undefined as (() => void) | undefined,
  navigate: undefined as (() => void) | undefined,
  replay: {
    startBuffering: vi.fn(),
    stop: vi.fn().mockResolvedValue(undefined),
    flush: vi.fn().mockResolvedValue(undefined),
    getReplayId: vi.fn().mockReturnValue("replay-id"),
  },
}));
vi.mock("@sentry/browser", () => ({
  getClient: () => ({}),
  addIntegration: vi.fn(),
  replayIntegration: () => mock.replay,
}));
vi.mock("@inertiajs/vue3", () => ({
  router: {
    on: (event: "before" | "navigate", callback: () => void) => {
      mock[event] = callback;
    },
  },
}));

beforeEach(async () => {
  vi.resetModules();
  vi.clearAllMocks();
  mock.replay.flush.mockResolvedValue(undefined);
  mock.replay.getReplayId.mockReturnValue("replay-id");
  const { configureCapturePolicy } = await import("../src/feedbackPrivacy"); configureCapturePolicy({ protectedPage: location => /invite/.test(location.pathname) });
  history.replaceState({}, "", "/productions/1");
});

it("starts a manual buffer and discards it before private navigation", async () => {
  const replay = await import("../src/feedbackReplay");
  replay.initializeFeedbackReplay();
  await replay.resumeFeedbackReplay();
  expect(mock.replay.startBuffering).toHaveBeenCalled();
  replay.stopFeedbackReplay();
  expect(mock.replay.stop).toHaveBeenCalledWith({ flush: false });
  history.replaceState({}, "", "/invites/PRIVATE");
  mock.replay.startBuffering.mockClear();
  await replay.resumeFeedbackReplay();
  expect(mock.replay.startBuffering).not.toHaveBeenCalled();
});

it("does not flush a disabled integration into continuous session recording", async () => {
  const replay = await import("../src/feedbackReplay");
  replay.initializeFeedbackReplay();
  mock.replay.getReplayId.mockReturnValue(undefined as unknown as string);
  expect(await replay.freezeFeedbackReplay()).toBeUndefined();
  expect(mock.replay.flush).not.toHaveBeenCalled();
});

it("freezes the pre-click buffer without continuing recording", async () => {
  const replay = await import("../src/feedbackReplay");
  replay.initializeFeedbackReplay();
  expect(await replay.freezeFeedbackReplay()).toBe("replay-id");
  expect(mock.replay.flush).toHaveBeenCalledWith({ continueRecording: false });
  expect(mock.replay.stop).toHaveBeenCalledWith({ flush: false });
});

it("waits for an in-flight flush before starting a replacement buffer", async () => {
  let finish!: () => void;
  mock.replay.flush.mockReturnValueOnce(
    new Promise<void>((resolve) => {
      finish = resolve;
    }),
  );
  const replay = await import("../src/feedbackReplay");
  replay.initializeFeedbackReplay();
  await replay.resumeFeedbackReplay();
  const frozen = replay.freezeFeedbackReplay();
  mock.replay.startBuffering.mockClear();
  replay.restartFeedbackReplay();
  await Promise.resolve();
  expect(mock.replay.startBuffering).not.toHaveBeenCalled();
  finish();
  await frozen;
  await replay.resumeFeedbackReplay();
  expect(mock.replay.startBuffering).toHaveBeenCalled();
});

it("discards recordings on feature revocation and will not restart or flush them", async () => {
  const replay = await import("../src/feedbackReplay");
  replay.setFeedbackReplayEnabled(true);
  await replay.resumeFeedbackReplay();
  mock.replay.startBuffering.mockClear();
  replay.setFeedbackReplayEnabled(false);
  expect(mock.replay.stop).toHaveBeenCalledWith({ flush: false });
  void replay.resumeFeedbackReplay();
  replay.restartFeedbackReplay();
  await replay.resumeFeedbackReplay();
  expect(mock.replay.startBuffering).not.toHaveBeenCalled();
  expect(await replay.freezeFeedbackReplay()).toBeUndefined();
  expect(mock.replay.flush).not.toHaveBeenCalled();
});
