# Auto::L18n

Automatically find and replace hardcoded text in Rails ERB view files with I18n translation calls. Auto::L18n scans your HTML/ERB files, detects hardcoded strings, and can automatically replace them with proper I18n `t()` calls while generating the corresponding locale YAML files.

## Features

- 🔍 **Smart Detection** - Finds hardcoded text in ERB code, HTML content, attributes, and optionally JavaScript
- 🔄 **Automatic Replacement** - Replaces hardcoded strings with I18n translation calls
- 📝 **Locale File Generation** - Automatically creates/updates YAML locale files
- 🎯 **Intelligent Filtering** - Skips existing I18n calls, comments, and code-like patterns
- 🔧 **Highly Configurable** - Control what gets extracted and how
- 💻 **CLI & Programmatic API** - Use from command line or Ruby code
- 🧪 **Dry Run Mode** - Preview changes before applying them
- 💾 **Automatic Backups** - Creates backup files before modifying originals

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'auto-l18n'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install auto-l18n
```

## Quick Start

### Find hardcoded text in a file:

```ruby
require 'auto/l18n'

texts = Auto::L18n.find_text("app/views/posts/show.html.erb")
texts.each { |t| puts "- #{t}" }
```

### Replace hardcoded text with I18n calls:

```ruby
# Preview changes (dry run)
result = Auto::L18n.auto_internationalize(
  "app/views/posts/show.html.erb",
  # namespace: "views.posts.show", # Optional – will be derived from the file path if omitted
  dry_run: true
)

puts "Would replace #{result[:total_replaced]} strings"

# Apply changes
result = Auto::L18n.auto_internationalize(
  "app/views/posts/show.html.erb"
)
```

### Command Line:

```bash
# Find hardcoded text
ruby exe/auto-l18n app/views/posts/show.html.erb

# Replace with I18n calls (dry run)
# Note: If --namespace is omitted, it will be derived from the file path (e.g., app/views/admin/users/show.html.erb -> views.admin.users.show)
ruby exe/auto-l18n app/views/posts/show.html.erb \
  --replace --dry-run

# Actually apply changes
ruby exe/auto-l18n app/views/posts/show.html.erb \
  --replace
```

## Example Transformation

**Before:**
```erb
<h1>Welcome to our blog</h1>
<p>Please <%= "sign in" %> to continue.</p>
<button title="Click here">Submit</button>
```

**After:**
```erb
<h1><%= t('views.posts.welcome_to_our_blog') %></h1>
<p>Please <%= t('views.posts.sign_in') %> to continue.</p>
<button title="<%= t('views.posts.click_here') %>">Submit</button>
```

**Generated locale file (config/locales/en.yml):**
```yaml
en:
  views:
    posts:
      welcome_to_our_blog: "Welcome to our blog"
      sign_in: "sign in"
      click_here: "Click here"
```

## Documentation

- **[Quick Start Guide](QUICKSTART.md)** - Get up and running quickly
- **[API Documentation](API.md)** - Complete API reference and examples
- **[Demo Script](demo.rb)** - Run `ruby demo.rb` to see it in action

## Main Methods

### `Auto::L18n.find_text(path, options = {})`

Find all hardcoded text in a file.

```ruby
# Simple usage
texts = Auto::L18n.find_text("app/views/posts/show.html.erb")

# With structured output (includes metadata)
findings = Auto::L18n.find_text("app/views/posts/show.html.erb", structured: true)
findings.each do |f|
  puts "#{f.text} (#{f.type}) at line #{f.line}"
end

# With options
texts = Auto::L18n.find_text("app/views/posts/show.html.erb",
  min_length: 3,
  scan_js: true,
  ignore_patterns: ['\d+', 'http']
)
```

### `Auto::L18n.exchange_text_for_l18n_placeholder(path, options = {})`

Replace hardcoded text in a single file with I18n calls.

```ruby
result = Auto::L18n.exchange_text_for_l18n_placeholder(
  "app/views/posts/show.html.erb",
  namespace: "views.posts.show",
  locale_path: "config/locales/en.yml",
  dry_run: true  # Preview first!
)
```

### `Auto::L18n.auto_internationalize(path, options = {})`

Main method that handles the complete workflow (find + replace).

```ruby
# Single file
result = Auto::L18n.auto_internationalize(
  "app/views/posts/show.html.erb",
  namespace: "views.posts.show"
)

# Entire directory
result = Auto::L18n.auto_internationalize(
  "app/views",
  recursive: true,
  namespace: "views",
  dry_run: true
)
```

## CLI Options

```bash
ruby exe/auto-l18n [options] [file]

Options:
  -d, --directory=DIR      Search files in DIR
  -r, --recursive          Search recursively
  --ext=EXTS              File extensions (default: .html.erb)
  --replace               Replace hardcoded text with I18n calls
  --locale-path=PATH      Locale file path (default: config/locales/en.yml)
  --namespace=NS          Translation key namespace (e.g., views.posts). If omitted, it is derived from the file path (folder hierarchy).
  --dry-run               Preview changes without modifying files
  --no-backup             Don't create backup files
  -h, --help              Show help
```

## What Gets Extracted

✅ ERB string literals: `<%= "text" %>`  
✅ HTML text nodes: `<p>text</p>`  
✅ HTML attributes: `alt`, `title`, `placeholder`, `aria-label`, etc.  
✅ JavaScript strings (optional): `"text"`, `'text'`, `` `text` ``  
✅ Data attribute JSON values  

## What Gets Skipped

❌ Existing I18n calls: `t('key')`, `I18n.t('key')`  
❌ Comments: `<!-- -->`, `<%# %>`  
❌ Short strings (< 2 chars by default)  
❌ Pure punctuation/symbols  
❌ File paths and code syntax  
❌ Custom patterns via `ignore_patterns`  

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `namespace` | Prefix for translation keys | nil |
| `locale_path` | Path to locale YAML file | `"config/locales/en.yml"` |
| `locale` | Locale code | `"en"` |
| `dry_run` | Preview without modifying | `false` |
| `backup` | Create .backup files | `true` |
| `min_length` | Minimum string length | `2` |
| `ignore_patterns` | Regex patterns to exclude | `[]` |
| `extra_attrs` | Additional HTML attributes | `[]` |
| `scan_erb_code` | Extract from ERB blocks | `true` |
| `scan_js` | Extract from JavaScript | `false` |
| `recursive` | Process subdirectories | `false` |
| `file_pattern` | File pattern for directories | `"*.html.erb"` |

## Usage

After installing the gem, you can use either the Ruby API or the CLI.

- Ruby API: see the Quick Start examples above or `QUICKSTART.md`.
- CLI: run `auto-l18n --help` for options, for example:

```bash
# Find hardcoded text in a file
auto-l18n app/views/posts/show.html.erb

# Replace with I18n calls (dry run)
auto-l18n app/views/posts/show.html.erb \
  --replace --namespace views.posts.show --dry-run

# Apply changes
auto-l18n app/views/posts/show.html.erb \
  --replace --namespace views.posts.show
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NicolasReiner/auto-l18n. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/NicolasReiner/auto-l18n/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Auto::L18n project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/NicolasReiner/auto-l18n/blob/master/CODE_OF_CONDUCT.md).
