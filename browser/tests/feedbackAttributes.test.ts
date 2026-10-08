import { configureCapturePolicy } from "../src/feedbackPrivacy";
configureCapturePolicy({ readable: true, stylesheet: url => url.pathname.startsWith("/includes/build/") });
// @vitest-environment jsdom
import { expect, it } from "vitest";
import {
  feedbackReplayMaskedAttributes,
  observeReplayAttributePrivacy,
  maskFeedbackReplayText,
} from "../src/feedbackCapturePrivacy";

it("masks arbitrary inherited and dynamically added attributes before the recorder observer", async () => {
  document.body.innerHTML = '<main csrftoken="PRIVATE" class="safe"></main>';
  const privacy = observeReplayAttributePrivacy();
  expect(feedbackReplayMaskedAttributes).toContain("csrftoken");
  expect(feedbackReplayMaskedAttributes).not.toContain("class");
  let recorded = false;
  const recorder = new MutationObserver(() => {
    expect(feedbackReplayMaskedAttributes).toContain("new-private-value");
    expect(feedbackReplayMaskedAttributes).toContain("nested-private-value");
    recorded = true;
  });
  recorder.observe(document.body, {
    attributes: true,
    subtree: true,
    childList: true,
  });
  document.querySelector("main")!.setAttribute("new-private-value", "PRIVATE");
  const child = document.createElement("span");
  child.setAttribute("nested-private-value", "PRIVATE");
  document.body.append(child);
  await new Promise<void>((resolve) => queueMicrotask(resolve));
  expect(recorded).toBe(true);
  privacy.disconnect();
  recorder.disconnect();
  document.body.innerHTML = "";
});

it("retains ordinary input text and excludes credential fields", () => {
  const input = document.createElement("input");
  expect(maskFeedbackReplayText("Email", input)).toBe("Email");
  input.name = "password";
  input.type = "text";
  expect(maskFeedbackReplayText("secret", input)).toBe("******");
  expect(maskFeedbackReplayText("Email", document.createElement("label"))).toBe(
    "Email",
  );
});
