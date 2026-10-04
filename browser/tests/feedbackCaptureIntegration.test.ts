import { configureCapturePolicy } from "../src/feedbackPrivacy";
configureCapturePolicy({ readable: true, stylesheet: url => url.pathname.startsWith("/includes/build/") });
// @vitest-environment jsdom
import { afterEach, expect, it, vi } from "vitest";
import { getClient, init, type Envelope } from "@sentry/browser";
import { inflateSync, gunzipSync } from "node:zlib";
import {
  initializeFeedbackReplay,
  resumeFeedbackReplay,
  freezeFeedbackReplay,
  setFeedbackReplayEnabled,
} from "../src/feedbackReplay";

vi.mock("@inertiajs/vue3", () => ({ router: { on: vi.fn() } }));
afterEach(async () => {
  setFeedbackReplayEnabled(false);
  await getClient()?.close();
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

it("records readable evaluations and input changes with the real SDK, excluding credential and payment fields", async () => {
  history.replaceState({}, "", "/productions/123");
  // Run the SDK's browser/Electron-renderer path inside jsdom's Node host.
  vi.stubGlobal(
    "process",
    new Proxy(process, {
      get: (target, key) =>
        key === "type" ? "renderer" : Reflect.get(target, key),
    }),
  );
  const envelopes: Envelope[] = [];
  init({
    dsn: "https://public@example.test/1",
    defaultIntegrations: false,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    transport: () => ({
      send: async (envelope) => {
        envelopes.push(envelope);
        return { statusCode: 200 };
      },
      flush: async () => true,
    }),
  });
  document.body.innerHTML = `<main><h1>Jane Smith</h1><p>Excellent audition</p><textarea name="evaluation">Strong performance</textarea><input name="email" value="jane@example.test"><input name="password" type="text" value="SECRET_PASSWORD"><input autocomplete="one-time-code" value="SECRET_CODE"><input name="card_number" value="SECRET_CARD"><input type="hidden" value="SECRET_CSRF"><div data-feedback-secret>SECRET_CONTAINER</div></main>`;
  initializeFeedbackReplay();
  await resumeFeedbackReplay();
  const evaluation = document.querySelector("textarea")!;
  evaluation.value = "Improved diction";
  evaluation.dispatchEvent(new Event("input", { bubbles: true }));
  const password = document.querySelector<HTMLInputElement>(
    'input[name="password"]',
  )!;
  password.value = "SECRET_CHANGED";
  password.dispatchEvent(new Event("input", { bubbles: true }));
  const inserted = document.createElement("input");
  inserted.name = "api_key";
  inserted.value = "SECRET_INSERTED";
  document.body.append(inserted);
  inserted.dispatchEvent(new Event("input", { bubbles: true }));
  await new Promise((resolve) => setTimeout(resolve, 100));
  expect(await freezeFeedbackReplay()).toBeTruthy();
  const recordings = envelopes
    .flatMap(([, items]) =>
      items
        .filter(([header]) => header.type === "replay_recording")
        .map(([, payload]) => {
          if (!(payload instanceof Uint8Array)) {
            return String(payload);
          }
          let bytes = payload;
          if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
            bytes = gunzipSync(bytes);
          } else if (bytes[0] === 0x78) {
            bytes = inflateSync(bytes);
          }
          return new TextDecoder().decode(bytes);
        }),
    )
    .join("\n");
  expect(recordings).toContain("Jane Smith");
  expect(recordings).toContain("Strong performance");
  expect(recordings).toContain("Improved diction");
  expect(recordings).toContain("jane@example.test");
  expect(recordings).not.toContain("SECRET_");
}, 10_000);
