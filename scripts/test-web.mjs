import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const html = readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const css = readFileSync(new URL('../docs/styles.css', import.meta.url), 'utf8');
const js = readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const socialCard = readFileSync(new URL('../docs/social-card.png', import.meta.url));

function occurrences(source, pattern) {
  return [...source.matchAll(pattern)].length;
}

test('landing page has semantic document structure', () => {
  assert.match(html, /^<!doctype html>/i);
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<meta name="viewport"/);
  assert.equal(occurrences(html, /<h1\b/g), 1);
  for (const landmark of ['header', 'nav', 'main', 'footer']) {
    assert.match(html, new RegExp(`<${landmark}\\b`));
  }
  assert.match(html, /class="skip-link"/);
  assert.match(html, /aria-live="polite"/);
});

test('landing page exposes exactly the approved actions', () => {
  assert.match(html, /releases\/latest/);
  assert.equal(occurrences(html, /data-copy-prompt/g), 2);
  assert.match(html, /Tailscale Serve/);
  assert.match(html, /never Funnel/i);
});

test('social metadata uses an absolute PNG card', () => {
  assert.match(html, /property="og:url" content="https:\/\/kalebcole\.github\.io\/otp-grabber\/"/);
  assert.match(html, /property="og:image" content="https:\/\/kalebcole\.github\.io\/otp-grabber\/social-card\.png"/);
  assert.equal(socialCard.subarray(1, 4).toString(), 'PNG');
});

test('landing page has no inline or remote executable code', () => {
  assert.doesNotMatch(html, /<script(?![^>]+src=)/i);
  assert.doesNotMatch(html, /\son(?:click|load|error)=/i);
  assert.doesNotMatch(html, /https?:\/\/[^"']+\.(?:js|css)(?:[?"'])/i);
  assert.doesNotMatch(js, /\beval\s*\(|new Function\s*\(/);
});

test('responsive and reduced-motion rules are present', () => {
  assert.match(css, /@media \(max-width: 900px\)/);
  assert.match(css, /@media \(max-width: 640px\)/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(css, /:focus-visible/);
});

test('public files do not contain machine-specific values', () => {
  for (const source of [html, css, js]) {
    assert.doesNotMatch(source, /\/Users\//);
    assert.doesNotMatch(source, /\.ts\.net/);
    assert.doesNotMatch(source, /Bearer\s+[A-Za-z0-9._~-]{12,}/i);
  }
});
