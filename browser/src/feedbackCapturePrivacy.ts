import { readableCapture } from "./feedbackPrivacy";
// Credential fields stay excluded even when a password is toggled to text.
const secretFieldNames = [
  "password",
  "passcode",
  "verificationCode",
  "loginCode",
  "token",
  "secret",
  "apiKey",
  "cardNumber",
  "creditCard",
  "cvv",
  "cvc",
  "securityCode",
  "bankAccount",
  "accountNumber",
  "routingNumber",
  "iban",
];
export const feedbackSecretSelector = [
  "[data-feedback-secret]",
  "[data-feedback-ui]",
  "[data-token]",
  '[name="otp" i]',
  '[name="pin" i]',
  '[id="otp" i]',
  '[id="pin" i]',
  ".sentry-mask",
  "[data-sentry-mask]",
  ".sentry-block",
  "[data-sentry-block]",
  'input[type="password"]',
  'input[type="hidden"]',
  '[autocomplete~="current-password"]',
  '[autocomplete~="new-password"]',
  '[autocomplete~="one-time-code"]',
  '[autocomplete*="cc-" i]',
  ...secretFieldNames.flatMap((name) => {
    const words = name
      .match(/[A-Z]?[a-z]+/g)!
      .map((word) => word.toLowerCase());
    return ["name", "id"].map((attribute) =>
      words.map((word) => "[" + attribute + "*=" + word + " i]").join(""),
    );
  }),
  'a[href*="token=" i]',
  'a[href*="/invites/"]',
  'a[href*="/secure-links/"]',
  'a[href*="/login-links/"]',
  'a[href*="/document-deliveries/"]',
].join(",");

export function maskFeedbackText(
  text: string,
  element?: Element | null,
): string {
  return !readableCapture() || element?.closest(feedbackSecretSelector)
    ? text.replace(/\S/g, "*")
    : text;
}
export const maskFeedbackReplayText = maskFeedbackText;

// Authenticated or signed media URLs must not become replay metadata.
export const feedbackBlockedMediaSelector = [
  'img[src*="?"]',
  'img[src*="#"]',
  'img[src^="data:"]',
  'img[src*="/document-deliveries/"]',
  'img[src*="/secure-links/"]',
].join(",");

export const feedbackReplayMaskedAttributes = [
  "href",
  "srcset",
  "action",
  "formaction",
  "data-page",
  "data-token",
  "data-reference",
  "title",
  "aria-label",
  "aria-description",
  "alt",
  "placeholder",
  "content",
  "style",
  "data-position-name",
  "data-staff-member",
  "data-label-code",
  "data-edit-role",
  "data-edit-position",
];

const safeReplayAttributes = new Set([
  "class",
  "role",
  "type",
  "width",
  "height",
  "colspan",
  "rowspan",
  "rows",
  "cols",
  "dir",
  "lang",
  "aria-hidden",
  "src",
  "value",
  "d",
  "viewBox",
  "fill",
  "stroke",
  "stroke-width",
  "stroke-linecap",
  "stroke-linejoin",
  "x",
  "y",
  "x1",
  "y1",
  "x2",
  "y2",
  "cx",
  "cy",
  "r",
  "rx",
  "ry",
  "points",
]);

export function maskReplayAttributesInTree(root: Element) {
  for (const element of [root, ...root.querySelectorAll("*")]) {
    for (const { name } of element.attributes) {
      if (
        !safeReplayAttributes.has(name) &&
        !feedbackReplayMaskedAttributes.includes(name)
      ) {
        feedbackReplayMaskedAttributes.push(name);
      }
    }
  }
}

export function observeReplayAttributePrivacy() {
  maskReplayAttributesInTree(document.documentElement);
  // Register before rrweb's observer. Its serializers consult this same array,
  // so newly introduced attributes are masked before mutation snapshots run.
  const observer = new MutationObserver((changes) => {
    for (const change of changes) {
      if (
        change.type === "attributes" &&
        change.attributeName &&
        !safeReplayAttributes.has(change.attributeName) &&
        !feedbackReplayMaskedAttributes.includes(change.attributeName)
      ) {
        feedbackReplayMaskedAttributes.push(change.attributeName);
      }
      for (const node of change.addedNodes) {
        if (node instanceof Element) {
          maskReplayAttributesInTree(node);
        }
      }
    }
  });
  observer.observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
  });
  return observer;
}
