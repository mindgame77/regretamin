# What is in this folder and where it came from

The firm share card (the picture a messenger shows for a shared `/vc/<slug>/` link) is drawn on the server.
These files are copies of open-source work, kept here because the site has no install step.

| File | What | From | Licence |
|---|---|---|---|
| `lib.mjs` | Turns a layout into an SVG, then into a PNG. One bundled file. | satori 0.15.2, @resvg/resvg-wasm 2.4.0, yoga-wasm-web 0.3.3 (and their small dependencies) | MPL-2.0 (satori, resvg), MIT (yoga-wasm-web) |
| `yoga.wasm` | Layout engine | yoga-wasm-web 0.3.3 | MIT |
| `resvg.wasm` | SVG to PNG | @resvg/resvg-wasm 2.4.0 | MPL-2.0 |
| `signal-icons.mjs` | The seven signal emoji as 64px pictures | Noto Emoji by Google, via emoji-datasource-google 16.0.0 | Apache-2.0 |
| `../../assets/fonts/*.ttf` | Geist and Geist Mono | geist 1.9.2 (Vercel) | SIL Open Font Licence 1.1 |

Source code for the MPL-2.0 parts: https://github.com/vercel/satori and https://github.com/yisibl/resvg-js.

To rebuild `lib.mjs`: `npm i satori@0.15.2 @resvg/resvg-wasm@2.4.0 yoga-wasm-web@0.3.3 esbuild`, an entry file that re-exports
`satori` and `init` from `satori/wasm`, the default export of `yoga-wasm-web`, and `Resvg` and `initWasm` from `@resvg/resvg-wasm`,
then `esbuild entry.mjs --bundle --format=esm --platform=neutral --main-fields=module,main --conditions=import,worker,browser --minify`.
