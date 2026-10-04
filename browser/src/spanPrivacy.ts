import type { BrowserClient, SpanJSON } from '@sentry/browser';
export function stablePageName(name: string) { return name.split(/[?#]/)[0].replace(/\/(?:login|password|tokens?|invites?|kiosk|reset)(?:\/[^\s]*)?/gi, '/[private-page]').replace(/\/[A-Za-z0-9_-]{24,}(?=\/|$)/g, '/:id').replace(/\b[0-9a-f]{8}-[0-9a-f-]{27,}\b/gi, ':id').replace(/\/\d+(?=\/|$)/g, '/:id').slice(0, 256); }
const configured = new WeakSet<BrowserClient>();
const technicalAttributes = /^(?:http\.request\.method|http\.response\.status_code|server\.address|sentry\.(?:origin|source|sample_rate)|type|op)$/;
function origin(value: string) { try { return new URL(value).origin; } catch { return '[resource]'; } }
export function sanitizeSpan(span: SpanJSON): SpanJSON {
  if (span.op?.startsWith('ui.')) span.description = 'interaction';
  else if (span.description) {
    if (['pageload', 'navigation'].includes(span.op ?? '')) span.description = stablePageName(span.description);
    else if (/https?:\/\//i.test(span.description)) span.description = span.description.replace(/https?:\/\/\S+/gi, origin);
    else if (!['pageload', 'navigation'].includes(span.op ?? '')) span.description = span.op ?? 'operation';
    span.description = span.description.split(/[?#]/)[0].replace(/\b[^\s/]+@[^\s/]+\b/g, '[private]').slice(0, 256);
  }
  const data: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(span.data ?? {})) {
    if (!technicalAttributes.test(key) || !['string', 'number', 'boolean'].includes(typeof value)) continue;
    if (typeof value === 'string') {
      if (key === 'server.address') data[key] = /^[a-z0-9.:-]+$/i.test(value) ? value : '[destination]';
      else if (/^[a-z0-9_. /:-]{1,128}$/i.test(value)) data[key] = value;
    } else data[key] = value as number | boolean;
  }
  span.data = data;
  return span;
}
export function installSpanPrivacy(client: BrowserClient) {
  if (configured.has(client)) return;
  configured.add(client);
  const options = client.getOptions();
  const previous = options.beforeSendSpan;
  options.beforeSendSpan = span => sanitizeSpan(previous ? previous(span) : span);
}
