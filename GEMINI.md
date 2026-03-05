# Jekyll Blog Project Context

## Project Overview

This is a personal tech blog created by DL (Donglu), built using [Jekyll](https://jekyllrb.com/), a static site generator in Ruby. The blog uses the default `minima` theme and generates static pages from Markdown files located in the `_posts/` directory.

- **Primary Language:** Ruby, Markdown, HTML, YAML
- **Framework:** Jekyll ~> 4.4.1
- **Theme:** minima
- **Plugins:** jekyll-feed, nokogiri, mermaid_processor.rb (custom plugin)

## Building and Running

This project uses Bundler to manage Ruby gem dependencies.

- **Install Dependencies:**
  ```bash
  bundle install
  ```

- **Run Local Development Server:**
  ```bash
  bundle exec jekyll serve --livereload
  ```
  *Note: The local server will watch for changes and regenerate the site automatically, except for changes to `_config.yml` which require a server restart.*

- **Build Static Site:**
  ```bash
  bundle exec jekyll build
  ```
  *The generated static files will be placed in the `_site/` directory.*

## Project Structure

- `_config.yml`: Global configuration for the Jekyll site (title, url, theme, plugins).
- `Gemfile` / `Gemfile.lock`: Ruby dependencies managed by Bundler.
- `_posts/`: Contains all blog posts in Markdown format. Filenames must follow the `YYYY-MM-DD-title.md` format.
- `_layouts/`: Custom HTML layouts (e.g., `post.html`).
- `_includes/`: Reusable HTML snippets (e.g., `google-analytics.html`, `mermaid.html`).
- `_plugins/`: Custom Ruby plugins, such as `mermaid_processor.rb` to render mermaid diagrams.
- `_site/`: The generated static site (ignored by version control).
- `.github/workflows/jekyll.yml`: GitHub Actions workflow for automated building and deployment.

## Development Conventions

- **Creating a New Post:** Create a new Markdown file in the `_posts/` directory. The filename must follow the pattern `YYYY-MM-DD-title.md`. Use YAML front matter at the top of the file to specify layout, title, and other metadata.
- **Dependency Management:** Always use `bundle exec` before Jekyll commands to ensure the correct versions of gems are used. If adding new plugins or gems, add them to the `Gemfile` and run `bundle install`.
- **Mermaid Support:** The site includes custom support for rendering Mermaid diagrams via the `_plugins/mermaid_processor.rb` and `_includes/mermaid.html`.
