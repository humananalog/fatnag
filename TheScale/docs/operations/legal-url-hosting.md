# Host Privacy Policy + Terms (required for App Store Connect)

In-app copies always ship (Settings → Privacy & Legal). **App Store Connect still requires a live public Privacy Policy URL.** Do not invent temporary live URLs in code.

## Target URLs (already wired in the app)

| Document | Constant | Expected public URL |
|----------|----------|---------------------|
| Privacy Policy | `ScaleLegal.privacyPolicyURL` | `https://humananalog.github.io/fatnag/privacy` |
| Terms of Use | `ScaleLegal.termsOfUseURL` | `https://humananalog.github.io/fatnag/terms` |
| Support | `ScaleLegal.supportURL` | `https://humananalog.github.io/fatnag/support` |

**Live (Sep 2026):** public repo `humananalog/fatnag` on GitHub Pages (`main` / root). Clean public paths are `/privacy`, `/terms`, `/support` at the repo root (mirrored from `docs/legal-site/`). Settings web links and ASC fields should use these URLs. In-app documents remain the interactive copy.

## Exact hosting steps (GitHub Pages)

1. Open the public repo `humananalog/fatnag` (or any public Pages site you prefer; then update URLs in `ScaleLegal.swift` and rebuild).
2. GitHub Pages → Deploy from branch `main` / folder `/` (root).
3. Keep root Pages HTML in sync with the editable copies:
   - Source: `docs/legal-site/{privacy,terms,support}/index.html`
   - Published: `/{privacy,terms,support}/index.html` (repo root — required for `github.io/fatnag/{privacy,terms,support}`)
4. When legal text changes, regenerate pages from:
   - `ScaleLegal.privacyPolicyBody`
   - `ScaleLegal.termsOfUseBody`
   and keep Markdown mirrors at `docs/privacy-policy.md` / `docs/terms-of-use.md` in sync.
   Then copy the three HTML files from `docs/legal-site/` to the matching root folders.
5. Commit + push to `main`. Wait for Pages deploy.
6. Verify in a private browser (expect HTTP 200):
   - https://humananalog.github.io/fatnag/privacy
   - https://humananalog.github.io/fatnag/terms
   - https://humananalog.github.io/fatnag/support
7. App Store Connect → App Information → **Privacy Policy URL** = the privacy URL above.
8. App Store Connect → **Support URL** = the support URL above.
9. Optional: Terms of Use URL field (if shown for subscriptions) = the terms URL.

## If you cannot use GitHub Pages

Host the same HTML files (privacy, terms, support) on any HTTPS site you control (Cloudflare Pages, Vercel, company site). Then change `ScaleLegal.privacyPolicyURL`, `ScaleLegal.termsOfUseURL`, and `ScaleLegal.supportURL` to those URLs, bump the app version, and re-archive.

## Contact that must work

`privacy@humananalog.ai` is referenced in-app for GDPR/CCPA requests. Ensure the mailbox exists before submit.

## Related

- `docs/operations/legal-gdpr-us.md`
- `docs/operations/app-store-metadata.md`
- `ScaleLegal.swift`
