import { feedbackAvailable, sendFeedback } from './feedback';
import { feedbackPageUrl, isPrivateFeedbackPage } from './feedbackPrivacy';
import type { FeedbackScreenshot } from './feedbackScreenshot';
export type CaptureState = 'pending' | 'ready' | 'removed' | 'unavailable' | 'private';
export interface FeedbackState { message: string; busy: boolean; capturing: boolean; screenshot?: FeedbackScreenshot; captureState: CaptureState; error: '' | 'messageRequired' | 'unavailable' | 'sendFailed'; success: boolean; }
export function captureWithDeadline<T>(pending: Promise<T | undefined>, discard?: (value: T) => void): Promise<T | undefined> {
  return new Promise(resolve => { let expired = false; const timer = setTimeout(() => { expired = true; resolve(undefined); }, 8000);
    pending.then(value => { clearTimeout(timer); if (expired) { if (value) discard?.(value); } else resolve(value); }).catch(() => { clearTimeout(timer); resolve(undefined); }); });
}
export function createFeedbackController(options: { component?: () => string; changed?: (state: FeedbackState) => void; eligible?: () => boolean } = {}) {
  const state: FeedbackState = { message: '', busy: false, capturing: false, captureState: 'pending', error: '', success: false };
  let generation = 0, opened = false;
  let context: { pageUrl: string; component: string; replayId?: string } = { pageUrl: '', component: '' };
  const notify = () => options.changed?.({ ...state });
  function removeScreenshot() { if (state.screenshot) { URL.revokeObjectURL(state.screenshot.previewUrl); state.captureState = 'removed'; } state.screenshot = undefined; notify(); }
  async function open() {
    if (opened || options.eligible?.() === false) return;
    opened = true; const current = ++generation; state.error = ''; state.success = false; state.capturing = true;
    state.captureState = isPrivateFeedbackPage(window.location) ? 'private' : 'pending';
    context = { pageUrl: feedbackPageUrl(window.location), component: options.component?.() ?? 'document' }; notify();
    const capture = captureWithDeadline(import('./feedbackScreenshot').then(m => m.captureFeedbackScreenshot()), image => URL.revokeObjectURL(image.previewUrl));
    const replay = captureWithDeadline(import('./feedbackReplay').then(m => m.freezeFeedbackReplay()));
    const [image, replayId] = await Promise.all([capture, replay]);
    if (current !== generation) { if (image) URL.revokeObjectURL(image.previewUrl); return; }
    state.screenshot = image; context.replayId = replayId; state.capturing = false;
    if (state.captureState !== 'private') state.captureState = image ? 'ready' : 'unavailable'; notify();
  }
  function close() { if (state.busy) return; cancel(); void import('./feedbackReplay').then(m => m.restartFeedbackReplay()); }
  function cancel() { generation++; opened = false; removeScreenshot(); state.message = ''; state.capturing = false; notify(); }
  async function submit() {
    if (state.busy || state.capturing || options.eligible?.() === false) return;
    state.error = ''; if (!state.message.trim()) { state.error = 'messageRequired'; notify(); return; }
    if (!feedbackAvailable()) { state.error = 'unavailable'; notify(); return; }
    const current = generation; state.busy = true; notify();
    try { await sendFeedback({ ...context, message: state.message, screenshot: state.screenshot }); if (current === generation) { state.success = true; state.message = ''; removeScreenshot(); } }
    catch { if (current === generation) state.error = 'sendFailed'; }
    finally { state.busy = false; notify(); }
  }
  return { state, open, close, cancel, submit, removeScreenshot, setMessage(message: string) { state.message = message; notify(); } };
}
