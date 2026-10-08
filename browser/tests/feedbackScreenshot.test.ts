import { configureCapturePolicy } from "../src/feedbackPrivacy";
configureCapturePolicy({ readable: true, stylesheet: url => url.pathname.startsWith("/includes/build/") });
// @vitest-environment jsdom
import { afterEach, expect, it } from "vitest";
import {
  compiledScreenshotStyles,
  sanitizeScreenshotDocument,
} from "../src/feedbackScreenshot";
afterEach(() => {
  document.body.innerHTML = "";
});
it("keeps evaluation text, ordinary values, selections, and safe images while removing secrets", () => {
  document.body.innerHTML = `<main><h1>Jane Smith</h1><p>Excellent audition</p><input name="email" value="jane@example.test"><textarea name="evaluation">Strong performance</textarea><select name="role"><option selected>Lead</option></select><input name="available" type="checkbox" checked><input name="password" type="text" value="SECRET_PASSWORD"><input autocomplete="one-time-code" value="SECRET_OTP"><input name="card_number" value="SECRET_CARD"><div data-feedback-secret><textarea>SECRET_NOTE</textarea></div><a href="/invites/SECRET_LINK">SECRET_LINK</a><div data-page="SECRET_PROPS">Roster</div><img src="/logo.png"><img src="/photo?token=SECRET_MEDIA"><div data-feedback-ui>SECRET_FEEDBACK</div></main>`;
  sanitizeScreenshotDocument(document, false);
  expect(document.querySelector("h1")?.textContent).toBe("Jane Smith");
  expect(document.querySelector('input[name="email"]')?.value).toBe(
    "jane@example.test",
  );
  expect(document.querySelector('textarea[name="evaluation"]')?.value).toBe(
    "Strong performance",
  );
  expect(document.querySelector("select")?.selectedIndex).toBe(0);
  expect(document.querySelector('input[type="checkbox"]')?.checked).toBe(true);
  expect(document.querySelector('input[name="password"]')?.value).toBe("");
  expect(
    document.querySelector('input[autocomplete="one-time-code"]')?.value,
  ).toBe("");
  expect(document.querySelector('input[name="card_number"]')?.value).toBe("");
  expect(document.querySelectorAll("textarea")[1]?.value).toBe("");
  expect(document.querySelector("a")?.hasAttribute("href")).toBe(false);
  expect(document.querySelector("img")?.getAttribute("src")).toBe("/logo.png");
  expect(document.querySelectorAll("img")[1]?.hasAttribute("src")).toBe(false);
  expect(document.body.innerHTML).not.toContain("SECRET");
});
it("hides the entire clone for private screens", () => {
  document.body.innerHTML = "<h1>Private invitation</h1>";
  sanitizeScreenshotDocument(document, true);
  expect(document.body.style.visibility).toBe("hidden");
  document.body.removeAttribute("style");
});

it("keeps empty compiled Vue style markers while removing private data attributes", () => {
  document.body.innerHTML =
    '<main data-v-1234abcd="" data-token="PRIVATE"><h1 data-v-1234abcd="">Send feedback</h1><p data-v-deadbeef="PRIVATE">Evaluation</p></main>';
  sanitizeScreenshotDocument(document, false);
  expect(document.querySelector("main")?.hasAttribute("data-v-1234abcd")).toBe(
    true,
  );
  expect(document.querySelector("h1")?.hasAttribute("data-v-1234abcd")).toBe(
    true,
  );
  expect(document.querySelector("p")?.hasAttribute("data-v-deadbeef")).toBe(
    false,
  );
  expect(document.body.innerHTML).not.toContain("PRIVATE");
});

it("copies loaded compiled CSS without depending on a second stylesheet fetch", () => {
  const doc = document.implementation.createHTMLDocument();
  const base = doc.createElement("base");
  base.href = "https://communiarts.com/";
  doc.head.append(base);
  const style = doc.createElement("style");
  style.textContent = "main[data-v-1234abcd] { display: grid; color: teal; }";
  document.head.append(style);
  const sheet = style.sheet!;
  Object.defineProperty(sheet, "href", {
    configurable: true,
    value: "https://communiarts.com/includes/build/assets/app.css",
  });
  Object.defineProperty(doc, "styleSheets", { value: [sheet] });
  expect(compiledScreenshotStyles(doc).join("\n")).toContain("display: grid");
  Object.defineProperty(sheet, "href", {
    configurable: true,
    value: "https://other.example/private.css",
  });
  expect(compiledScreenshotStyles(doc)).toEqual([]);
  Object.defineProperty(sheet, "href", {
    configurable: true,
    value: "https://communiarts.com/private.css?token=PRIVATE",
  });
  expect(compiledScreenshotStyles(doc)).toEqual([]);
  style.remove();
});

it("clears fields adopted from another window without changing the source field", () => {
  const iframe = document.createElement("iframe");
  document.body.append(iframe);
  const clone = iframe.contentDocument!;
  const input = document.createElement("input");
  input.name = "password";
  input.value = "PRIVATE_TYPED";
  const source = input.cloneNode(true) as HTMLInputElement;
  document.body.append(source);
  clone.body.append(clone.adoptNode(input));
  const OtherInput = (iframe.contentWindow as Window & typeof globalThis)
    .HTMLInputElement;
  expect(input instanceof OtherInput).toBe(false);
  sanitizeScreenshotDocument(clone, false);
  expect(input.value).toBe("");
  expect(source.value).toBe("PRIVATE_TYPED");
  iframe.remove();
});
