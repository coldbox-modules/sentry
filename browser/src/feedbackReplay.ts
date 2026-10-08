import { addIntegration, getClient, replayIntegration } from '@sentry/browser';
import { feedbackSecretSelector, feedbackBlockedMediaSelector, feedbackReplayMaskedAttributes, maskFeedbackReplayText, maskReplayAttributesInTree, observeReplayAttributePrivacy } from './feedbackCapturePrivacy';
import { canRecordFeedbackPage, readableCapture } from './feedbackPrivacy';
let replay: ReturnType<typeof replayIntegration> | undefined;
let suspended = false, enabled = false, revision = 0;
let stopping = Promise.resolve();
let freezing: Promise<string | undefined> | undefined;
export function stopFeedbackReplay() {
  revision++;
  const previous = stopping;
  const stopped = replay?.stop({ flush: false }).catch(() => {}) ?? Promise.resolve();
  stopping = Promise.all([previous, stopped]).then(() => {});
}
export async function resumeFeedbackReplay() {
  const expected = revision;
  await stopping; await Promise.resolve();
  if (expected === revision && enabled && !suspended && canRecordFeedbackPage(window.location)) {
    maskReplayAttributesInTree(document.documentElement); replay?.startBuffering();
  }
}
export function initializeFeedbackReplay() {
  enabled = true;
  if (replay || !getClient()) return;
  observeReplayAttributePrivacy();
  replay = replayIntegration({ stickySession: false, minReplayDuration: 0,
    maskAllText: !readableCapture(), maskAllInputs: !readableCapture(), blockAllMedia: !readableCapture(),
    mask: [feedbackSecretSelector], maskFn: maskFeedbackReplayText, maskAttributes: feedbackReplayMaskedAttributes,
    block: ['script', 'iframe', 'canvas', 'video, audio, object, embed', feedbackSecretSelector, feedbackBlockedMediaSelector, '[style*="url("]', '[data-feedback-ui]'],
    networkCaptureBodies: false, networkDetailAllowUrls: [], beforeAddRecordingEvent: () => null });
  addIntegration(replay);
  window.addEventListener('popstate', stopFeedbackReplay, { capture: true });
  window.addEventListener('hashchange', () => { stopFeedbackReplay(); void resumeFeedbackReplay(); });
  void resumeFeedbackReplay();
}
export function freezeFeedbackReplay(): Promise<string | undefined> {
  if (freezing) return freezing;
  suspended = true;
  const active = replay; const id = active?.getReplayId(); const expected = revision;
  if (!enabled || !active || !id || !canRecordFeedbackPage(window.location)) return Promise.resolve(undefined);
  const frozen = (async () => { try { await active.flush({ continueRecording: false }); return expected === revision && enabled ? id : undefined; } catch { return undefined; } finally { await active.stop({ flush: false }); } })();
  freezing = frozen;
  stopping = frozen.then(() => {});
  void frozen.finally(() => { if (freezing === frozen) freezing = undefined; });
  return frozen;
}
export function restartFeedbackReplay() { suspended = false; stopFeedbackReplay(); void resumeFeedbackReplay(); }
export function setFeedbackReplayEnabled(value: boolean) { enabled = value; if (value) { suspended = false; if (replay) void resumeFeedbackReplay(); else initializeFeedbackReplay(); } else { suspended = true; stopFeedbackReplay(); } }
