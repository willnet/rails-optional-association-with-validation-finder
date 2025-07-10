# Rails Optional Association with Validation Finder

A script to detect Rails models where `belongs_to` associations have `optional: true` but also have `validates` with `presence: true`.

## Background

In Rails, you might encounter code like this:

```ruby
class Post < ApplicationRecord
  belongs_to :user, optional: true
  validates :user, presence: true
end
```

In such cases, using `belongs_to :user, required: true` would make `validates :user, presence: true` redundant. This script helps find such refactoring opportunities.

## Setup

```bash
bundle install
```

## Usage

### Basic Usage

By default, it searches the `app/models` directory:

```bash
ruby find_optional_with_validation.rb
```

### Search Specific Directory

```bash
ruby find_optional_with_validation.rb -d path/to/your/models
```

### Help

```bash
ruby find_optional_with_validation.rb --help
```

## Example Output

```
Found 2 match(es):

Model: Post
Association: user
File: app/models/post.rb
--------------------------------------------------
Model: Article
Association: author
File: app/models/article.rb
--------------------------------------------------
```

## Automatic Replacement Script

A script is also provided to automatically fix detected issues.

### Usage

#### Process Single File

```bash
ruby replace_optional_with_required.rb -f app/models/post.rb
```

#### Process Entire Directory

```bash
ruby replace_optional_with_required.rb -d app/models
```

#### Dry Run (Preview Changes)

Preview what changes would be made without actually modifying files:

```bash
ruby replace_optional_with_required.rb -d app/models --dry-run
```

### Transformation Example

Before:
```ruby
class Post < ApplicationRecord
  belongs_to :user, optional: true
  validates :user, presence: true
end
```

After:
```ruby
class Post < ApplicationRecord
  belongs_to :user, required: true
end
```

### Important Notes

- Always backup your files or commit to version control before running automatic replacements
- Use the `--dry-run` option to preview changes before applying them
- If `validates` contains validations other than `presence: true`, only `presence: true` will be removed while other validations are preserved

## Testing

To run tests:

```bash
# Test the detection script
bundle exec ruby test_find_optional_with_validation.rb

# Test the replacement script
bundle exec ruby test_replace_optional_with_required.rb
```

## Detection Patterns

This script detects the following patterns:

1. Both symbol and string syntax
   ```ruby
   belongs_to :user, optional: true
   belongs_to "user", optional: true
   ```

2. Multi-line definitions
   ```ruby
   belongs_to :user,
              optional: true,
              class_name: 'Customer'
   ```

3. Hash-style validations
   ```ruby
   validates :user, presence: { message: "must be present" }
   ```

4. `validates_presence_of` syntax
   ```ruby
   validates_presence_of :user
   validates_presence_of :user, :email, :name
   ```