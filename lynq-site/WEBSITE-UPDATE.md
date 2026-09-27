# Lynq website update — 2026-09-26

## Delivered locally

- Responsive home dashboard with cream/forest-green editorial styling, keyboard-accessible shortcuts, dark mode, task/event agenda, and visible update status.
- Typed dashboard data service: independent Supabase reads run concurrently, select only needed fields, and retain existing authentication and database policies.
- Removed fabricated fallback statistics and the full membership-list download previously used to infer ExCo counts. The replacement card accurately shows the signed-in user's open tasks.
- Refresh on tab visibility, browser focus, reconnection, and every 60 seconds while visible. Requests do not overlap and are aborted on unmount or after 15 seconds. This is polling, not instantaneous realtime synchronization.
- Lazy-loaded scanner, certificate, and existing Mentron dashboard routes. No Mentron functionality, backend, or Cloudflare storage changed.
- Navigation labels for assistive technology and stable layout during viewport resizing.

## Verification

- TypeScript and production build pass.
- Main JavaScript output reduced from 1,856.20 kB to 1,312.70 kB (about 29%); a large-bundle warning remains.
- Browser fixture checks pass at 1440px, 390px and 320px, including horizontal overflow, partial failure feedback, and retry recovery. Desktop/mobile/dark screenshots are under output/playwright (ignored).
- Supabase read-only checks confirm the referenced tables and columns exist. Real-account authorization and multi-device behavior have not been end-to-end tested.
- Reproducible browser fixture: scripts/check-dashboard.cjs, run using playwright-cli against the local Vite server. It intercepts network requests in an isolated browser; it never adds a production authentication bypass.

## Release notes

No production deployment, database mutation, record deletion, or identity migration performed. Existing Flutter registration changes were preserved. Website deployment is required to publish this work; native app behavior is unchanged.

Dependency installation reported 10 existing vulnerabilities (six high, three moderate, one low). They remain unresolved; do not describe this release as fully security-hardened. Real sign-in, authorization, and registration approval require separate testing before production rollout.

Supabase query reference: https://supabase.com/docs/reference/javascript/select
