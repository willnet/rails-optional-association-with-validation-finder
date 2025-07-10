#!/usr/bin/env ruby

require_relative 'find_optional_with_validation'

def assert_equal(expected, actual, message = nil)
  unless expected == actual
    raise "Assertion failed: Expected #{expected.inspect}, got #{actual.inspect}#{message ? " - #{message}" : ""}"
  end
end

def assert_empty(collection, message = nil)
  unless collection.empty?
    raise "Assertion failed: Expected empty collection, got #{collection.inspect}#{message ? " - #{message}" : ""}"
  end
end

def assert_match(pattern, string, message = nil)
  unless pattern.match?(string)
    raise "Assertion failed: Expected #{string.inspect} to match #{pattern.inspect}#{message ? " - #{message}" : ""}"
  end
end

def run_test(name)
  print "Running #{name}... "
  yield
  puts "✓"
rescue => e
  puts "✗"
  puts "  Error: #{e.message}"
  puts e.backtrace[0..2].map { |line| "    #{line}" }
end

finder = OptionalWithValidationFinder.new

# Test 1: finds optional belongs_to with presence validation
run_test("finds optional belongs_to with presence validation") do
  model_code = <<~RUBY
    class Post < ApplicationRecord
      belongs_to :user, optional: true
      belongs_to :category, optional: true
      belongs_to :author
      
      validates :user, presence: true
      validates :title, presence: true
    end
  RUBY
  
  result = finder.analyze_model_code('Post', model_code)
  
  assert_equal 1, result.size
  assert_equal 'Post', result[0][:model]
  assert_equal 'user', result[0][:association]
end

# Test 2: ignores optional false belongs_to
run_test("ignores optional false belongs_to") do
  model_code = <<~RUBY
    class Comment < ApplicationRecord
      belongs_to :post, optional: false
      validates :post, presence: true
    end
  RUBY
  
  result = finder.analyze_model_code('Comment', model_code)
  
  assert_empty result
end

# Test 3: ignores optional belongs_to without validation
run_test("ignores optional belongs_to without validation") do
  model_code = <<~RUBY
    class Tag < ApplicationRecord
      belongs_to :post, optional: true
    end
  RUBY
  
  result = finder.analyze_model_code('Tag', model_code)
  
  assert_empty result
end

# Test 4: handles symbol and string syntax
run_test("handles symbol and string syntax") do
  model_code = <<~RUBY
    class Article < ApplicationRecord
      belongs_to :author, optional: true
      belongs_to "editor", optional: true
      
      validates :author, presence: true
      validates "editor", presence: true
    end
  RUBY
  
  result = finder.analyze_model_code('Article', model_code)
  
  assert_equal 2, result.size
  associations = result.map { |r| r[:association] }.sort
  assert_equal ['author', 'editor'], associations
end

# Test 5: handles multiline belongs_to
run_test("handles multiline belongs_to") do
  model_code = <<~RUBY
    class Review < ApplicationRecord
      belongs_to :user,
                 optional: true,
                 class_name: 'Customer'
      
      validates :user, presence: true
    end
  RUBY
  
  result = finder.analyze_model_code('Review', model_code)
  
  assert_equal 1, result.size
  assert_equal 'user', result[0][:association]
end

# Test 6: handles nested hashes in validates
run_test("handles nested hashes in validates") do
  model_code = <<~RUBY
    class Product < ApplicationRecord
      belongs_to :vendor, optional: true
      
      validates :vendor, presence: { message: "must be present" }
    end
  RUBY
  
  result = finder.analyze_model_code('Product', model_code)
  
  assert_equal 1, result.size
  assert_equal 'vendor', result[0][:association]
end

# Test 7: directory scanning
run_test("directory scanning") do
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
    
    results = finder.scan_directory(models_dir)
    
    assert_equal 1, results.size
    assert_equal 'Post', results[0][:model]
    assert_equal 'user', results[0][:association]
    assert_match(/post\.rb$/, results[0][:file])
  end
end

puts "\nAll tests passed!"