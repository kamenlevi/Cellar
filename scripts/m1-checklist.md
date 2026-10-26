# M1 checklist: Steam that works

Kamen's hands-on checks, in the real Cellar folder (`~/Library/Application Support/Cellar`). Use the release build: `~/Cellar/.build/release/cellar` (build it with `swift build -c release` in `~/Cellar`).

**Before you start:** quit Steam for Mac (Steam ▸ Quit Steam). It holds ports Windows Steam wants. Cellar works without this but warns.

1. **Install and first start.** Run `cellar steam install`, then `cellar steam`. Steam updates itself first (about 400 MB, a few minutes), then shows its sign-in window. **Sign in yourself**, with your password and Steam Guard. Cellar never sees them.
2. **Health.** Run `cellar steam status`. Expect `Signed in: yes (since …)` and `Crash loop: no`.
3. **Downloading works.** In the Steam window, install ANIMAL WELL (about 200 MB). It reaches 100%.
4. **Sign-in survives a normal quit.** Quit from Steam's own menu (Steam ▸ Exit), then run `cellar steam` again. It comes back signed in without asking for your password.
5. **Recovers from a hard stop.** Run `cellar bottle kill Steam`, then `cellar steam`. It says `Cleared a stuck Steam session…` or `Starting Steam…`, and you're still signed in.
6. **Never two Steams.** Run `cellar steam` while Steam is open. It says `bringing its window forward`. There's one Steam window and at most two Dock icons, which is accepted (spec section 8).
7. **One week later (2026-10-24 or after).** Run `cellar steam`, then `cellar steam status`. You're still signed in, there's no crash loop, and `Last update check` falls within the week. That shows Steam updated itself without breaking.
8. **Your account id stays out of Cellar's log.** After step 1, run `grep -c '\[U:1:[0-9]' ~/Library/Logs/Cellar/Steam.log`. It prints `0`.

Write down what you saw in `docs/m1-signoff.md`. M1 is done when all eight pass.
