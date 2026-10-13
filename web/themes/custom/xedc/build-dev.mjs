import { build } from 'esbuild';
import fg from 'fast-glob';
import {
  makeSassPlugin,
  stylelintPlugin,
  copyPlugin,
  bootstrapIconsPlugin,
  componentJsEntries,
} from './plugins.mjs';

// Per-component SCSS -> sibling .css (e.g. components/card/card.scss -> components/card/card.css).
const components = fg.sync('components/**/*.scss');

for (const file of components) {
  await build({
    entryPoints: [file],
    outfile: file.replace('.scss', '.css'),
    bundle: false,
    sourcemap: true,
    plugins: [makeSassPlugin()]
  })
}

// Per-component JS: _name.js -> sibling name.js (the file Drupal SDC auto-attaches).
const jsEntries = componentJsEntries();
if (Object.keys(jsEntries).length > 0) {
  await build({
    entryPoints: jsEntries,
    outdir: '.',
    bundle: true,
    minify: false,
    sourcemap: true,
    external: ['/themes/*'],
  })
}

// Global theme bundle: main stylesheet + main script, plus assets and icons.
await build({
  entryPoints: {
    'css/main.style': 'src/scss/main.style.scss',
    'js/main.script': 'src/js/main.script.js',
  },
  bundle: true,
  minify: false,
  sourcemap: true,
  outdir: 'build',
  external: ['/themes/*'],
  plugins: [
    makeSassPlugin(),
    stylelintPlugin,
    copyPlugin(),
    bootstrapIconsPlugin
  ]
})
