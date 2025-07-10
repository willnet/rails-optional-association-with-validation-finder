require 'minitest/autorun'
require_relative 'replace_optional_with_required'

class TestReplaceOptionalWithRequired < Minitest::Test
  def setup
    @replacer = OptionalToRequiredReplacer.new
  end

  def test_basic_replacement
    input = <<~RUBY
      class Post < ApplicationRecord
        belongs_to :user, optional: true
        belongs_to :category, optional: true
        
        validates :user, presence: true
        validates :title, presence: true
      end
    RUBY
    
    expected = <<~RUBY
      class Post < ApplicationRecord
        belongs_to :user, required: true
        belongs_to :category, optional: true
        
        validates :title, presence: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_multiline_belongs_to_replacement
    input = <<~RUBY
      class Review < ApplicationRecord
        belongs_to :user,
                   optional: true,
                   class_name: 'Customer'
        
        validates :user, presence: true
      end
    RUBY
    
    expected = <<~RUBY
      class Review < ApplicationRecord
        belongs_to :user,
                   required: true,
                   class_name: 'Customer'
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_string_syntax_replacement
    input = <<~RUBY
      class Article < ApplicationRecord
        belongs_to "author", optional: true
        
        validates "author", presence: true
      end
    RUBY
    
    expected = <<~RUBY
      class Article < ApplicationRecord
        belongs_to "author", required: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_preserves_other_validations
    input = <<~RUBY
      class Product < ApplicationRecord
        belongs_to :vendor, optional: true
        
        validates :vendor, presence: true, uniqueness: true
        validates :name, presence: true
      end
    RUBY
    
    expected = <<~RUBY
      class Product < ApplicationRecord
        belongs_to :vendor, required: true
        
        validates :vendor, uniqueness: true
        validates :name, presence: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_handles_presence_with_hash
    input = <<~RUBY
      class Order < ApplicationRecord
        belongs_to :customer, optional: true
        
        validates :customer, presence: { message: "must be present" }
      end
    RUBY
    
    expected = <<~RUBY
      class Order < ApplicationRecord
        belongs_to :customer, required: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_leaves_non_optional_belongs_to_unchanged
    input = <<~RUBY
      class Comment < ApplicationRecord
        belongs_to :post, optional: false
        validates :post, presence: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal input.strip, result.strip
  end

  def test_leaves_optional_without_validation_unchanged
    input = <<~RUBY
      class Tag < ApplicationRecord
        belongs_to :post, optional: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal input.strip, result.strip
  end

  def test_multiple_associations_and_validations
    input = <<~RUBY
      class Item < ApplicationRecord
        belongs_to :user, optional: true
        belongs_to :category, optional: true
        belongs_to :store
        
        validates :user, presence: true
        validates :category, presence: true, inclusion: { in: %w[food clothes] }
        validates :name, presence: true
      end
    RUBY
    
    expected = <<~RUBY
      class Item < ApplicationRecord
        belongs_to :user, required: true
        belongs_to :category, required: true
        belongs_to :store
        
        validates :category, inclusion: { in: %w[food clothes] }
        validates :name, presence: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_validates_presence_of_replacement
    input = <<~RUBY
      class Book < ApplicationRecord
        belongs_to :author, optional: true
        validates_presence_of :author
      end
    RUBY
    
    expected = <<~RUBY
      class Book < ApplicationRecord
        belongs_to :author, required: true
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_validates_presence_of_with_multiple_fields
    input = <<~RUBY
      class Invoice < ApplicationRecord
        belongs_to :customer, optional: true
        belongs_to :vendor, optional: true
        
        validates_presence_of :customer, :vendor, :amount
      end
    RUBY
    
    expected = <<~RUBY
      class Invoice < ApplicationRecord
        belongs_to :customer, required: true
        belongs_to :vendor, required: true
        
        validates_presence_of :amount
      end
    RUBY
    
    result = @replacer.replace_in_code(input)
    assert_equal expected.strip, result.strip
  end

  def test_file_processing
    require 'tmpdir'
    require 'fileutils'
    
    Dir.mktmpdir do |tmpdir|
      input_file = File.join(tmpdir, 'post.rb')
      
      File.write(input_file, <<~RUBY)
        class Post < ApplicationRecord
          belongs_to :user, optional: true
          validates :user, presence: true
        end
      RUBY
      
      @replacer.replace_in_file(input_file)
      
      result = File.read(input_file)
      expected = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user, required: true
        end
      RUBY
      
      assert_equal expected.strip, result.strip
    end
  end

  def test_dry_run_mode
    require 'tmpdir'
    require 'fileutils'
    
    Dir.mktmpdir do |tmpdir|
      input_file = File.join(tmpdir, 'post.rb')
      original_content = <<~RUBY
        class Post < ApplicationRecord
          belongs_to :user, optional: true
          validates :user, presence: true
        end
      RUBY
      
      File.write(input_file, original_content)
      
      # Capture output
      output = capture_io do
        @replacer.replace_in_file(input_file, dry_run: true)
      end
      
      # File should not be changed
      assert_equal original_content, File.read(input_file)
      
      # Output should show the diff
      assert_match(/Would replace in/, output[0])
      assert_match(/belongs_to :user, required: true/, output[0])
    end
  end

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    [$stdout.string]
  ensure
    $stdout = old_stdout
  end
end