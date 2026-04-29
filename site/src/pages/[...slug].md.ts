/**
 * Raw markdown endpoint — serves the source MDX/MD body for any doc page.
 *
 * URL pattern: /fsuite/<slug>.md  (mirrors Anthropic/Mintlify's /<page>.md convention)
 *
 * Used by:
 *   - "View as Markdown" → opens this URL in a new tab
 *   - "Copy as Markdown" → fetches this URL and copies the body
 *   - "Open in Claude/ChatGPT" → references this URL in the prefilled prompt
 *
 * Astro 5 endpoint contract: getStaticPaths() enumerates all docs entries,
 * GET() returns the raw body with frontmatter stripped (or kept — we keep
 * it because it's useful for LLM context).
 */
import type { APIRoute } from 'astro';
import { getCollection, type CollectionEntry } from 'astro:content';

export async function getStaticPaths() {
  const docs = await getCollection('docs');
  return docs.map((entry: CollectionEntry<'docs'>) => ({
    params: { slug: entry.id.replace(/\.(md|mdx)$/i, '') },
    props: { entry },
  }));
}

export const GET: APIRoute = async ({ props }) => {
  const entry = props.entry as CollectionEntry<'docs'>;

  // Reconstruct a markdown source: YAML frontmatter (title + description) + body.
  // We don't expose the full original frontmatter (could leak template-only fields);
  // we only re-emit the human-meaningful fields so an LLM gets clean context.
  const fm: Record<string, string | undefined> = {
    title: entry.data.title,
    description: entry.data.description,
  };
  const yaml = Object.entries(fm)
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${k}: ${JSON.stringify(v)}`)
    .join('\n');

  const header = yaml ? `---\n${yaml}\n---\n\n` : '';
  const body = entry.body ?? '';

  return new Response(header + body, {
    status: 200,
    headers: {
      'Content-Type': 'text/markdown; charset=utf-8',
      'Content-Disposition': 'inline',
      'Cache-Control': 'public, max-age=300',
    },
  });
};
