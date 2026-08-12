# OpenBubble — Minimalist UI Clone

A static, two-page clone of a terminal-native AI coding agent landing page,
rebranded as **OpenBubble**. Built with a strict minimalist aesthetic — no
frameworks, no build step — just HTML, CSS, and a small JS file.

## Pages

- **`index.html`** — Home. Hero, install command (curl/npm/bun/brew/paru tabs with copy), feature list, privacy, FAQ, and a Discord community CTA.
- **`pages/docs.html`** — Documentation with a sticky table of contents, scrollspy, code blocks, and keybinding chips.

## Design system

- Monospace everywhere (`Berkeley Mono` → `JetBrains Mono` → `Fira Code` → system mono).
- Strict palette: warm off-white `#fdfcfc`, near-black `#201d1d`, warm gray `#9a9595`, soft `#f8f7f7`.
- Two logo files (`logo-light.svg` and `logo-dark.svg`) auto-switched via `<picture>` + `prefers-color-scheme`.
- Flat surfaces, 1px borders at `rgba(15,0,0,0.12)`, 4–6px corner radius.
- Single-column layout, max content width ~880px.

## Features

- **Auto light/dark theme** — follows the user's OS color scheme, no toggle button needed.
- **Two logo files** for light/dark that switch automatically.
- Tabbed install command with one-click copy.
- Copy buttons on code snippets.
- Scrollspy table of contents on the docs page.
- Discord link in the nav (icon) and a community CTA on the home page.
- Fully responsive (collapses to single column under 720px).

## Run it

Just open `index.html` in a browser — no server required. For a slightly nicer
experience, serve the folder:

```bash
cd openbubble-clone
python3 -m http.server 8080
# then visit http://localhost:8080
```

## Structure

```
openbubble-clone/
├── index.html
├── README.md
├── assets/
│   ├── favicon.svg
│   ├── icon-discord.svg
│   ├── logo-light.svg
│   └── logo-dark.svg
├── css/
│   └── style.css
├── js/
│   └── app.js
└── pages/
    └── docs.html
```
# openbubble.github.io
