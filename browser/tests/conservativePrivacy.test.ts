import { expect, it } from 'vitest';
import { configureCapturePolicy } from '../src/feedbackPrivacy';
import { maskFeedbackText } from '../src/feedbackCapturePrivacy';
import { sanitizeScreenshotDocument } from '../src/feedbackScreenshot';
it('defaults to masking ordinary text and form values', () => { configureCapturePolicy({}); document.body.innerHTML = '<p>Personal name</p><input value="personal value">'; expect(maskFeedbackText('Personal name', document.querySelector('p'))).toBe('******** ****'); sanitizeScreenshotDocument(document, false); expect(document.body.textContent).not.toContain('Personal'); expect(document.querySelector('input')!.value).toBe(''); });
