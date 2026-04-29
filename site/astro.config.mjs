// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
  site: 'https://lliwcwill.github.io',
  base: '/fsuite',
  integrations: [
    starlight({
      title: 'fsuite',
      description: 'Filesystem reconnaissance drones for AI coding agents. Fourteen CLI tools that replace grep, find, cat, sed, and bash with something LLMs can actually use without blowing their context window.',
      logo: {
        src: './src/assets/fsuite-hero.jpeg',
        replacesTitle: false,
      },
      components: {
        // Override the page H1 so we can render the page-actions dropdown
        // (Copy / View / Open in LLM) inline with the title.
        PageTitle: './src/components/PageTitle.astro',
      },
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/lliWcWill/fsuite' },
      ],
      customCss: [
        './src/styles/custom.css',
      ],
      expressiveCode: {
        themes: ['monokai', 'github-light'],
        styleOverrides: {
          codeFontFamily: '"JetBrainsMono Nerd Font", "Fira Code", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
        },
      },
      sidebar: [
        {
          label: 'Story',
          items: [
            { label: 'The Lightbulb Moment', slug: 'story/lightbulb' },
            { label: 'Episode 0 — Origins', slug: 'story/episode-0' },
            { label: 'Episode 1', slug: 'story/episode-1' },
            { label: 'Episode 2', slug: 'story/episode-2' },
            { label: 'Episode 3', slug: 'story/episode-3' },
          ],
        },
        {
          label: 'Getting Started',
          items: [
            { label: 'Installation', slug: 'getting-started/installation' },
            { label: 'Mental Model', slug: 'getting-started/mental-model' },
            { label: 'First Contact', slug: 'getting-started/first-contact' },
          ],
        },
        {
          label: 'Commands',
          autogenerate: { directory: 'commands' },
        },
        {
          label: 'Architecture',
          items: [
            { label: 'MCP Adapter', slug: 'architecture/mcp' },
            { label: 'Hooks & Enforcement', slug: 'architecture/hooks' },
            { label: 'Telemetry', slug: 'architecture/telemetry' },
            { label: 'Chain Combinations', slug: 'architecture/chains' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Cheat Sheet', slug: 'reference/cheatsheet' },
            { label: 'Output Formats', slug: 'reference/output-formats' },
            { label: 'Changelog', slug: 'reference/changelog' },
          ],
        },
      ],
    }),
  ],
});
