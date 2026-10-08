export interface CapturePolicy {
  readable?: boolean;
  protectedPage?: (location: Pick<Location, 'pathname' | 'search'>) => boolean;
  stylesheet?: (url: URL) => boolean;
}
let policy: CapturePolicy = {};
export function configureCapturePolicy(value: CapturePolicy) { policy = { ...value }; }
export function readableCapture() { return policy.readable === true; }
export function approvedStylesheet(url: URL) { return !url.search && !url.hash && (policy.stylesheet?.(url) ?? false); }
export function isPrivateFeedbackPage(location: Pick<Location, 'pathname' | 'search'>) { return policy.protectedPage?.(location) ?? /(?:login|password|token|payment|checkout|bank)/i.test(location.pathname + location.search); }
export function canRecordFeedbackPage(location: Pick<Location, 'pathname' | 'search' | 'hash'>) { return !isPrivateFeedbackPage(location) && !location.search && !location.hash; }
export function feedbackPageUrl(location: Pick<Location, 'origin' | 'pathname' | 'search'>) { return `${location.origin}${isPrivateFeedbackPage(location) ? '/[private-page]' : location.pathname}`; }
