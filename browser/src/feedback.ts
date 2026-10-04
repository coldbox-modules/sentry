import { installClientPrivacy } from './clientPrivacy';
import { captureFeedback, getClient } from "@sentry/browser";
import type { FeedbackScreenshot } from "./feedbackScreenshot";

export function feedbackAvailable(): boolean {
  return Boolean(getClient());
}

export async function sendFeedback(input: {
  message: string;
  pageUrl: string;
  component: string;
  replayId?: string;
  screenshot?: FeedbackScreenshot;
}): Promise<void> {
  const client = getClient();
  if (!client || !input.message.trim()) {
    throw new Error("Feedback is unavailable");
  }
  if (typeof client.addEventProcessor === "function") installClientPrivacy(client);
  // flush() only confirms that the queue drained. Listen for the actual provider
  // response so blocked, rate-limited or rejected reports never show success.
  await new Promise<void>((resolve, reject) => {
    let eventId: string | undefined;
    const cleanup = client.on("afterSendEvent", (event, response) => {
      if (event.event_id !== eventId) {
        return;
      }
      clearTimeout(timeout);
      cleanup();
      if (
        response?.statusCode &&
        response.statusCode >= 200 &&
        response.statusCode < 300
      ) {
        resolve();
      } else {
        reject(new Error("Feedback was not accepted"));
      }
    });
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("Feedback timed out"));
    }, 15_000);
    try {
      eventId = captureFeedback(
        {
          message: input.message.trim(),
          url: input.pageUrl,
          source: "api",
          tags: { page_component: input.component },
        },
        {
          includeReplay: false,
          data: { feedbackReplayId: input.replayId },
          attachments: input.screenshot
            ? [
                {
                  filename: "feedback-screenshot.png",
                  contentType: "image/png",
                  data: input.screenshot.data,
                },
              ]
            : [],
        },
      );
    } catch (error) {
      clearTimeout(timeout);
      cleanup();
      reject(error);
    }
  });
}
