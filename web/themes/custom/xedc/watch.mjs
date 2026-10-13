import { context } from 'esbuild';
import fg from 'fast-glob';
import dotenv from 'dotenv';
import bs from 'browser-sync';
import { watch as fsWatch, rmSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import {
  makeSassPlugin,
  stylelintPlugin,
  copyPlugin,
  bootstrapIconsPlugin,
  componentJsEntries,
} from './plugins.mjs';

dotenv.config({ path: '.env.local' });

const isDdev = process.env.IS_DDEV_PROJECT?.toLowerCase() === 'true';

/**
 * Resolve the URL Browsersync should proxy.
 *
 * The configured `DRUPAL_BASE_URL` (e.g. https://my-site.ddev.site) is what a
 * human types into the browser, but it is a poor proxy target on the host:
 *   - The `*.ddev.site` name commonly resolves to both 127.0.0.1 and ::1. On
 *     many setups IPv6 is attempted first and waits out a ~5s connect timeout
 *     before falling back to IPv4, so EVERY proxied request (the page plus each
 *     asset) pays that penalty. With dozens of assets the page never appears to
 *     finish loading.
 *   - DDEV serves it over HTTPS with a generic self-signed cert, and the
 *     gzipped HTML defeats Browsersync's snippet injection.
 *
 * DDEV publishes the web container directly on an IPv4 host port over plain
 * HTTP (e.g. http://127.0.0.1:32799). Proxying that instead is instant, needs
 * no cert, and lets Browsersync inject its live-reload snippet cleanly. The
 * host port is dynamic (it changes when DDEV restarts), so it is queried at
 * startup rather than hard-coded.
 *
 * Outside DDEV — or if the query fails (DDEV stopped, a different local stack
 * such as Lando, etc.) — fall back to DRUPAL_BASE_URL.
 *
 * @returns {string} The proxy target URL.
 */
function resolveProxyTarget() {
  // Inside the DDEV web container the site is reachable on localhost directly.
  if (isDdev) {
    return 'localhost';
  }

  try {
    const json = execSync('ddev describe -j', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const parsed = JSON.parse(json);
    // `ddev describe -j` may wrap the payload in a log envelope ({ raw: … })
    // or emit the describe object at the top level, depending on version.
    const describe = parsed.raw ?? parsed;
    const httpUrl = describe?.services?.web?.host_http_url;
    if (httpUrl) {
      console.log(`[browsersync] proxying DDEV host port: ${httpUrl}`);
      return httpUrl;
    }
  } catch {
    // ddev not installed/running, or not a ddev project — fall through.
  }

  return process.env.DRUPAL_BASE_URL;
}

const target = resolveProxyTarget();

const browserSync = bs.create();

browserSync.init({
  proxy: {
    target,
    // Drupal serves HTML with `Content-Encoding: gzip`. Browsersync's
    // snippet-injection middleware can't parse a compressed body, so it neither
    // injects its client snippet nor terminates the response cleanly — the page
    // renders but the browser's load event can stall. Stripping Accept-Encoding
    // forces the upstream to return uncompressed HTML that Browsersync can
    // rewrite and inject into.
    proxyReq: [
      (proxyReq) => {
        proxyReq.removeHeader('Accept-Encoding');
      },
    ],
    proxyRes: [
      (proxyRes) => {
        // Drupal sends a fixed Content-Length for the original body.
        // Browsersync rewrites the HTML to inject its client snippet, which
        // changes the length; leaving the stale Content-Length in place
        // truncates the page (and suppresses injection). Clear it so the
        // rewritten body streams chunked.
        proxyRes.headers['content-length'] = undefined;
      },
    ],
  },
  open: !isDdev,
  notify: false,
  files: [
    'components/**/*.css',
    'components/**/*.js',
    'components/**/*.twig',
    'templates/**/*.twig',
    'build/css/*.css',
    'build/js/*.js',
  ],
});

const reloadPlugin = {
  name: 'reload',
  setup(build) {
    build.onEnd((result) => {
      if (result.errors.length === 0) {
        browserSync.reload();
      }
    });
  }
};

// One esbuild context per component SCSS file, keyed by source path. esbuild
// only watches each entry's own dependency graph, so newly-added components are
// registered dynamically by the filesystem watcher below.
const scssContexts = new Map();

async function watchScss(file) {
  if (scssContexts.has(file)) {
    return;
  }
  const ctx = await context({
    entryPoints: [file],
    outfile: file.replace('.scss', '.css'),
    plugins: [makeSassPlugin(), reloadPlugin],
  });
  scssContexts.set(file, ctx);
  await ctx.watch();
}

async function unwatchScss(file) {
  const ctx = scssContexts.get(file);
  if (!ctx) {
    return;
  }
  await ctx.dispose();
  scssContexts.delete(file);
  // Remove the now-orphaned compiled output.
  for (const out of [file.replace('.scss', '.css'), file.replace('.scss', '.css.map')]) {
    rmSync(out, { force: true });
  }
}

// Component JS is bundled through a single context with an entryPoints map.
// entryPoints can't be mutated, so the context is rebuilt when the set of
// _*.js sources changes.
let jsContext = null;
// Sources covered by the last successful build. Tracked independently of the
// context lifecycle so a fast-path dispose on deletion doesn't lose the record
// needed to clean up orphaned output.
let jsBuiltSources = new Set();

async function disposeJsContext() {
  if (jsContext) {
    const ctx = jsContext;
    jsContext = null;
    await ctx.dispose();
  }
}

async function rebuildJsContext() {
  await disposeJsContext();
  const entries = componentJsEntries();
  const sources = new Set(Object.values(entries));
  // Remove compiled output for component JS sources that no longer exist.
  for (const source of jsBuiltSources) {
    if (!sources.has(source)) {
      const out = source.replace(/\/_([^/]+)\.js$/, '/$1.js');
      rmSync(out, { force: true });
      rmSync(`${out}.map`, { force: true });
    }
  }
  jsBuiltSources = sources;
  if (sources.size === 0) {
    return;
  }
  jsContext = await context({
    entryPoints: entries,
    outdir: '.',
    bundle: true,
    minify: false,
    sourcemap: true,
    external: ['/themes/*'],
    plugins: [reloadPlugin],
  });
  await jsContext.watch();
}

// Initial build: register every existing component SCSS and build component JS.
for (const file of fg.sync('components/**/*.scss')) {
  await watchScss(file);
}
await rebuildJsContext();

// Watch the global theme bundle, plus assets and icons.
const globalCtx = await context({
  entryPoints: {
    'css/main.style': 'src/scss/main.style.scss',
    'js/main.script': 'src/js/main.script.js',
  },
  bundle: true,
  sourcemap: true,
  minify: false,
  outdir: 'build',
  external: ['/themes/*'],
  plugins: [
    makeSassPlugin(),
    reloadPlugin,
    stylelintPlugin,
    copyPlugin(true),
    bootstrapIconsPlugin
  ]
})

await globalCtx.watch()

// Pick up components added or removed while watch is running. esbuild's own
// watcher only tracks known entries (so it handles edits to existing files),
// while this recursive fs watcher registers new component contexts and tears
// down removed ones.
const debounce = new Map();

function reconcileScss() {
  const current = new Set(fg.sync('components/**/*.scss'));
  for (const file of current) {
    if (!scssContexts.has(file)) {
      watchScss(file);
    }
  }
}

const isComponentJs = (p) => /(^|[/\\])_[^/\\]+\.js$/.test(p) && !p.includes('node_modules');

if (existsSync('components')) {
  fsWatch('components', { recursive: true }, (_event, filename) => {
    if (!filename) {
      return;
    }
    // fs.watch reports paths relative to the watched dir; key by the same
    // project-relative path the contexts use.
    const rel = `components/${filename.toString().split('\\').join('/')}`;

    // Removals are handled immediately (no debounce) so the context is disposed
    // before esbuild's watcher reports a transient resolve error for the gone
    // file.
    if (!existsSync(rel)) {
      if (scssContexts.has(rel)) {
        unwatchScss(rel);
        return;
      }
      if (jsBuiltSources.has(rel)) {
        // Tear down now; the debounced rebuild below re-creates it without the
        // removed entry and cleans up its output.
        disposeJsContext();
      }
    }

    if (!rel.endsWith('.scss') && !isComponentJs(rel)) {
      return;
    }

    // Debounce additions/edits: editors fire several events per save.
    clearTimeout(debounce.get(rel));
    debounce.set(rel, setTimeout(() => {
      debounce.delete(rel);
      if (rel.endsWith('.scss')) {
        reconcileScss();
      } else if (isComponentJs(rel)) {
        rebuildJsContext();
      }
    }, 100));
  });
}
