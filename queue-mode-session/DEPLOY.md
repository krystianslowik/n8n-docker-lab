# Hosting the lesson page

The page is static: HTML, CSS, JS, one JSON file of recorded evidence and one image.
Nothing in this repo deploys it for you.

## Build

From `queue-mode-session/`:

```bash
./tools/rehearse.sh      # only if the lab changed; refreshes the recorded evidence (~10 min, wipes lab data)
./tools/build-site.sh    # writes site-dist/
```

`build-site.sh` fails if the recorded evidence is missing or if the page references a
file that isn't in the build. Check the result locally before uploading:

```bash
cd site-dist && python3 -m http.server 8765
```

Open <http://localhost:8765> and click through every lesson.

## Upload

Upload the contents of `site-dist/` so that `index.html` sits at the site root. Any
static host works. With Cloudflare Pages, the first deploy creates the project:

```bash
npx wrangler pages deploy site-dist --project-name <project-name> --branch main
```

To limit it to colleagues, put the `*.pages.dev` hostname behind Cloudflare Access
before you share the link. `site-dist/_headers` sets security and caching headers on
hosts that read it (Cloudflare Pages, Netlify); other hosts ignore it.

## After uploading

- Open the hosted URL in a private window. The hero image should load, every lesson
  should render, Recorded blocks should show a capture date, the incident 3 numbers
  table should be filled in, and Notebook, Download should produce a `.md` file.
- The quickstart clones `github.com/krystianslowik/n8n-docker-lab` and changes into
  `queue-mode-session`, which only works once this directory is pushed there.
- The hosted live panel contacts `http://localhost:5691` only after a participant opens
  it. Some browsers allow that, some ask, and Safari usually refuses. The page points
  people to their lab's own copy, which always works.

## Updating

Re-run `./tools/build-site.sh` and upload `site-dist/` again. Participants' notes are
stored in their browsers under the page's origin, so moving the page to another domain
gives everyone an empty notebook. Keep the URL stable once you've shared it.
