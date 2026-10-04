import { configureCapturePolicy } from "../src/feedbackPrivacy";
configureCapturePolicy({ readable: true, stylesheet: url => url.pathname.startsWith("/includes/build/") });
// @vitest-environment jsdom
import { afterEach, expect, it, vi } from "vitest";
import { init, getClient } from "@sentry/browser";
import { feedbackAvailable, sendFeedback } from "../src/feedback";
type Envelope = Parameters<
  NonNullable<ReturnType<typeof getClient>>["sendEnvelope"]
>[0];

afterEach(async () => {
  vi.useRealTimers();
  await getClient()?.close(100);
});

function transport(statusCode: number) {
  const envelopes: Envelope[] = [];
  init({
    dsn: "https://public@example.com/1",
    defaultIntegrations: false,
    transport: () => ({
      send: async (envelope) => {
        envelopes.push(envelope);
        return { statusCode };
      },
      flush: async () => true,
    }),
  });
  return envelopes;
}

it("uses the real SDK to send a feedback event with a PNG attachment", async () => {
  const envelopes = transport(200);
  expect(feedbackAvailable()).toBe(true);
  await sendFeedback({
    message: "  The save button did not respond  ",
    pageUrl: "https://example.com/productions/1",
    component: "Productions/Show",
    screenshot: { data: new Uint8Array([1, 2, 3]), previewUrl: "blob:preview" },
  });
  const items = envelopes[0][1];
  expect(items[0][0].type).toBe("feedback");
  expect(items[0][1]).toMatchObject({
    contexts: {
      feedback: {
        message: "The save button did not respond",
        url: "https://example.com/productions/1",
        source: "api",
      },
    },
    tags: { page_component: "Productions/Show" },
  });
  expect(items[1][0]).toMatchObject({
    type: "attachment",
    filename: "feedback-screenshot.png",
    content_type: "image/png",
  });
  expect(items[1][1]).toEqual(new Uint8Array([1, 2, 3]));
});

it("rejects provider rejection instead of reporting queue-drained success", async () => {
  transport(429);
  await expect(
    sendFeedback({
      message: "Save failed",
      pageUrl: "https://example.com/",
      component: "Main/Index",
    }),
  ).rejects.toThrow("not accepted");
});

it("rejects a timed-out submission even when the transport queue is stalled", async () => {
  vi.useFakeTimers();
  init({
    dsn: "https://public@example.com/1",
    defaultIntegrations: false,
    transport: () => ({
      send: () => new Promise(() => {}),
      flush: async () => true,
    }),
  });
  const report = expect(
    sendFeedback({
      message: "Save failed",
      pageUrl: "https://example.com/",
      component: "Main/Index",
    }),
  ).rejects.toThrow("timed out");
  await vi.advanceTimersByTimeAsync(15_000);
  await report;
});

it("rejects blank feedback before creating an envelope", async () => {
  const envelopes = transport(200);
  await expect(
    sendFeedback({
      message: "  ",
      pageUrl: "https://example.com/",
      component: "Main/Index",
    }),
  ).rejects.toThrow();
  expect(envelopes).toHaveLength(0);
});
