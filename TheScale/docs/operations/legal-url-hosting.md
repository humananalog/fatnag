# Host Privacy Policy + Terms (required for App Store Connect)

In-app copies always ship (Settings → Privacy & Legal). **App Store Connect still requires a live public Privacy Policy URL.** Do not invent temporary live URLs in code.

## Target URLs (already wired in the app)

| Document | Constant | Expected public URL |
|----------|----------|---------------------|
| Privacy Policy | `ScaleLegal.privacyPolicyURL` | `https://humananalog.github.io/the-scale/privacy` |
| Terms of Use | `ScaleLegal.termsOfUseURL` | `https://humananalog.github.io/the-scale/terms` |

Settings shows **Privacy Policy (web)** and **Terms of Use (web)** links that open these URLs. Until hosting is live, reviewers still have full in-app documents.

## Exact hosting steps (GitHub Pages)

1. Create (or open) the public repo `humananalog/the-scale` (or any public Pages site you prefer — then update the two URLs in `ScaleLegal.swift` and rebuild).
2. Enable **GitHub Pages** → Deploy from branch `main` / folder `/docs` (or `/` with a `docs` site).
3. Copy the HTML stubs from this repo:
   - `docs/legal-site/privacy/index.html`
   - `docs/legal-site/terms/index.html`
4. Paste the **current** bodies from:
   - `ScaleLegal.privacyPolicyBody`
   - `ScaleLegal.termsOfUseBody`
   into those pages (stubs already include placeholders and a note to sync from the app). Prefer keeping the Markdown mirrors at `docs/privacy-policy.md` and `docs/terms-of-use.md` in sync when legal text changes.
5. Commit + push. Wait for Pages deploy.
6. Verify in a private browser:
   - https://humananalog.github.io/the-scale/privacy
   - https://humananalog.github.io/the-scale/terms
7. App Store Connect → App Information → **Privacy Policy URL** = the privacy URL above.
8. Optional: Terms of Use URL field (if shown for subscriptions) = the terms URL.

## If you cannot use GitHub Pages

Host the same two HTML files on any HTTPS site you control (Cloudflare Pages, Vercel, company site). Then change `ScaleLegal.privacyPolicyURL` and `ScaleLegal.termsOfUseURL` to those URLs, bump the app version, and re-archive.

## Contact that must work

`privacy@humananalog.ai` is referenced in-app for GDPR/CCPA requests. Ensure the mailbox exists before submit.

## Related

- `docs/operations/legal-gdpr-us.md`
- `docs/operations/app-store-metadata.md`
- `ScaleLegal.swift`
