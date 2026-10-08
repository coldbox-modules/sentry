import type { BrowserClient } from '@sentry/browser';
const configured = new WeakSet<BrowserClient>();
export function installClientPrivacy(client: BrowserClient) {
  if (configured.has(client)) return;
  configured.add(client);
  client.addEventProcessor((event, hint) => {
    if (event.type === 'feedback' || event.type === 'replay_event') {
      delete event.user; delete event.request; delete event.breadcrumbs; delete event.extra; delete event.transaction;
      if (event.type === 'replay_event') Object.assign(event, { urls: [] });
      const replayId = hint.data?.feedbackReplayId;
      if (event.type === 'feedback' && typeof replayId === 'string' && /^[a-f0-9]{32}$/i.test(replayId) && event.contexts?.feedback) event.contexts.feedback.replay_id = replayId;
    }
    return event;
  });
}
