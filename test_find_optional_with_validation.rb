require 'minitest/autorun'
require_relative 'find_optional_with_validation'

class TestFindOptionalWithValidation < Minitest::Test
  def setup
    @finder = OptionalWithValidationFinder.new
  end

  def test_finds_optional_belongs_to_with_presence_validation
    model_code = <<~RUBY
      class Post < ApplicationRecord
        belongs_to :user, optional: true
        belongs_to :category, optional: true
        belongs_to :author
        
        validates :user, presence: true
        validates :title, presence: true
      end
    RUBY
    
    result = @finder.analyze_model_code('Post', model_code)
    
    assert_equal 1, result.size
    assert_equal 'Post', result[0][:model]
    assert_equal 'user', result[0][:association]
  end

  def test_ignores_optional_false_belongs_to
    model_code = <<~RUBY
      class Comment < ApplicationRecord
        belongs_to :post, optional: false
        validates :post, presence: true
      end
    RUBY
    
    result = @finder.analyze_model_code('Comment', model_code)
    
    assert_empty result
  end

  def test_ignores_optional_belongs_to_without_validation
    model_code = <<~RUBY
      class Tag < ApplicationRecord
        belongs_to :post, optional: true
      end
    RUBY
    
    result = @finder.analyze_model_code('Tag', model_code)
    
    assert_empty result
  end

  def test_handles_symbol_and_string_syntax
    model_code = <<~RUBY
      class Article < ApplicationRecord
        belongs_to :author, optional: true
        belongs_to "editor", optional: true
        
        validates :author, presence: true
        validates "editor", presence: true
      end
    RUBY
    
    result = @finder.analyze_model_code('Article', model_code)
    
    assert_equal 2, result.size
    associations = result.map { |r| r[:association] }.sort
    assert_equal ['author', 'editor'], associations
  end

  def test_handles_multiline_belongs_to
    model_code = <<~RUBY
      class Review < ApplicationRecord
        belongs_to :user,
                   optional: true,
                   class_name: 'Customer'
        
        validates :user, presence: true
      end
    RUBY
    
    result = @finder.analyze_model_code('Review', model_code)
    
    assert_equal 1, result.size
    assert_equal 'user', result[0][:association]
  end

  def test_handles_nested_hashes_in_validates
    model_code = <<~RUBY
      class Product < ApplicationRecord
        belongs_to :vendor, optional: true
        
        validates :vendor, presence: { message: "must be present" }
      end
    RUBY
    
    result = @finder.analyze_model_code('Product', model_code)
    
    assert_equal 1, result.size
    assert_equal 'vendor', result[0][:association]
  end

  def test_validates_presence_of_syntax
    model_code = <<~RUBY
      class Book < ApplicationRecord
        belongs_to :author, optional: true
        validates_presence_of :author
      end
    RUBY
    
    result = @finder.analyze_model_code('Book', model_code)
    
    assert_equal 1, result.size
    assert_equal 'author', result[0][:association]
  end

  def test_validates_presence_of_with_multiple_fields
    model_code = <<~RUBY
      class Invoice < ApplicationRecord
        belongs_to :customer, optional: true
        belongs_to :vendor, optional: true
        
        validates_presence_of :customer, :vendor, :amount
      end
    RUBY
    
    result = @finder.analyze_model_code('Invoice', model_code)
    
    assert_equal 2, result.size
    associations = result.map { |r| r[:association] }.sort
    assert_equal ['customer', 'vendor'], associations
  end

  def test_directory_scanning
    # Create temporary test directory structure
    require 'tmpdir'
    require 'fileutils'
    
    Dir.mktmpdir do |tmpdir|
      models_dir = File.join(tmpdir, 'app', 'models')
      FileUtils.mkdir_p(models_dir)
      
      # Create test model files
      File.write(File.join(models_dir, 'user.rb'), <<~RUBY)
        class User < ApplicationRecord
          has_many :posts
        end
      RUBY
      
      File.write(File.join(models_dir, 'post.rb'), <<~RUBY)
        class Post < ApplicationRecord
          belongs_to :user, optional: true
          validates :user, presence: true
        end
      RUBY
      
      File.write(File.join(models_dir, 'comment.rb'), <<~RUBY)
        class Comment < ApplicationRecord
          belongs_to :post
          belongs_to :author, optional: true
        end
      RUBY
      
      results = @finder.scan_directory(models_dir)
      
      assert_equal 1, results.size
      assert_equal 'Post', results[0][:model]
      assert_equal 'user', results[0][:association]
      assert_match(/post\.rb$/, results[0][:file])
    end
  end
end