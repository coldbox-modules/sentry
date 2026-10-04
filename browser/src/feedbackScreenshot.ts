import {
  feedbackBlockedMediaSelector,
  feedbackSecretSelector,
  maskFeedbackText,
} from "./feedbackCapturePrivacy";
import { isPrivateFeedbackPage, approvedStylesheet, readableCapture } from "./feedbackPrivacy";

export interface FeedbackScreenshot {
  data: Uint8Array;
  previewUrl: string;
}

export function compiledScreenshotStyles(doc: Document): string[] {
  // Capture already-loaded app CSS. A renderer iframe can otherwise parse the
  // sanitized page before its external stylesheets finish loading.
  return Array.from(doc.styleSheets).flatMap((sheet) => {
    if (!sheet.href) {
      return [];
    }
    const url = new URL(sheet.href, doc.baseURI);
    if (
      url.origin !== new URL(doc.baseURI).origin ||
      !approvedStylesheet(url) ||
      url.search ||
      url.hash
    ) {
      return [];
    }
    try {
      return [Array.from(sheet.cssRules, (rule) => rule.cssText).join("\n")];
    } catch {
      return [];
    }
  });
}

export function sanitizeScreenshotDocument(
  doc: Document,
  privatePage: boolean,
) {
  doc
    .querySelectorAll(
      `script, iframe, canvas, video, audio, object, embed, ${feedbackSecretSelector}, ${feedbackBlockedMediaSelector}, [data-feedback-ui]`,
    )
    .forEach((element) => {
      (element as HTMLElement).style.visibility = "hidden";
    });
  if (privatePage) {
    doc.body.style.visibility = "hidden";
    return;
  }
  const secretElements = new Set(
    Array.from(doc.querySelectorAll(feedbackSecretSelector)).flatMap(
      (element) => [element, ...element.querySelectorAll("*")],
    ),
  );
  doc
    .querySelectorAll(feedbackBlockedMediaSelector)
    .forEach((element) => element.removeAttribute("src"));
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    walker.currentNode.textContent = maskFeedbackText(
      walker.currentNode.textContent ?? "",
      walker.currentNode.parentElement,
    );
  }
  doc.querySelectorAll<HTMLElement>("body, body *").forEach((element) => {
    const secret = !readableCapture() || secretElements.has(element);
    const input = element as HTMLInputElement;
    const value = input.value;
    const checked = input.checked;
    const selectedIndex = (element as HTMLSelectElement).selectedIndex;
    element.style.setProperty("background-image", "none", "important");
    for (const attribute of [...element.attributes]) {
      // Vue's empty scope markers contain no user data and keep scoped CSS
      // matching after the clone's private attributes have been removed.
      if (/^data-v-[0-9a-f]{8}$/.test(attribute.name) && !attribute.value) {
        continue;
      }
      if (
        /^(?:data-|href$|srcset$|action$|formaction$|value$)/i.test(
          attribute.name,
        )
      ) {
        element.removeAttribute(attribute.name);
      } else if (
        /^(?:title|alt|aria-label|aria-description|placeholder)$/.test(
          attribute.name,
        )
      ) {
        element.setAttribute(
          attribute.name,
          secret ? attribute.value.replace(/\S/g, "*") : attribute.value,
        );
      }
    }
    // html2canvas adopts source-window elements into its iframe. instanceof
    // against the clone window misses those controls; tag names cross realms.
    if (element.tagName === "INPUT" || element.tagName === "TEXTAREA") {
      (element as HTMLInputElement | HTMLTextAreaElement).value = secret
        ? ""
        : value;
    }
    if (element.tagName === "INPUT") {
      (element as HTMLInputElement).checked = secret ? false : checked;
    }
    if (element.tagName === "SELECT") {
      (element as HTMLSelectElement).selectedIndex = secret
        ? -1
        : selectedIndex;
    }
  });
  // Generated content can expose data attributes, names or initials.
  const style = doc.createElement("style");
  style.textContent =
    "*::before, *::after { content: none !important; background-image: none !important; }";
  doc.head.append(style);
}

export async function captureFeedbackScreenshot(): Promise<
  FeedbackScreenshot | undefined
> {
  // A blank private-page screenshot is not useful; retain the text-only report.
  if (isPrivateFeedbackPage(window.location)) {
    return undefined;
  }
  const { default: html2canvas } = await import("html2canvas-pro");
  const width = window.innerWidth;
  const height = window.innerHeight;
  const styles = compiledScreenshotStyles(document);
  const canvas = await html2canvas(document.body, {
    width,
    height,
    x: window.scrollX,
    y: window.scrollY,
    scale: Math.min(1, Math.sqrt(1_500_000 / (width * height))),
    backgroundColor: "#f4f8fb",
    logging: false,
    allowTaint: false,
    useCORS: false,
    imageTimeout: 3000,
    ignoreElements: (element) => element.hasAttribute("data-feedback-ui"),
    onclone: async (doc) => {
      for (const css of styles) {
        const style = doc.createElement("style");
        style.textContent = css;
        doc.head.append(style);
      }
      sanitizeScreenshotDocument(doc, false);
      // Force style resolution before waiting for the clone's font faces.
      doc.body.getBoundingClientRect();
      await doc.fonts?.ready;
    },
  });
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/png"),
  );
  if (!blob || blob.size > 2_000_000) {
    return undefined;
  }
  return {
    data: new Uint8Array(await blob.arrayBuffer()),
    previewUrl: URL.createObjectURL(blob),
  };
}
