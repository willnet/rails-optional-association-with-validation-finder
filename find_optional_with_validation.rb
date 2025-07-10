#!/usr/bin/env ruby

class OptionalWithValidationFinder
  def analyze_model_code(model_name, code)
    results = []
    
    # Find all belongs_to associations with optional: true
    optional_associations = find_optional_belongs_to(code)
    
    # Find all presence validations
    presence_validations = find_presence_validations(code)
    
    # Find matches
    optional_associations.each do |association|
      # Check both association name and foreign key name
      foreign_key = generate_foreign_key_name(association, code)
      
      if presence_validations.include?(association) || presence_validations.include?(foreign_key)
        results << {
          model: model_name,
          association: association
        }
      end
    end
    
    results
  end
  
  def scan_directory(directory)
    results = []
    
    Dir.glob(File.join(directory, '**', '*.rb')).each do |file|
      content = File.read(file)
      
      # Extract model name from class definition
      if content =~ /class\s+(\w+)\s*<\s*(?:ApplicationRecord|ActiveRecord::Base)/
        model_name = $1
        file_results = analyze_model_code(model_name, content)
        
        file_results.each do |result|
          results << result.merge(file: file)
        end
      end
    end
    
    results
  end
  
  private
  
  def generate_foreign_key_name(association, code)
    # Default foreign key is association_name + "_id"
    default_foreign_key = "#{association}_id"
    
    # TODO: In the future, we could parse custom foreign_key options
    # For now, we'll just use the default naming convention
    default_foreign_key
  end
  
  def find_optional_belongs_to(code)
    associations = []
    
    # Match single-line belongs_to with optional: true
    # Handles both symbol and string association names
    code.scan(/belongs_to\s+:(\w+)(?:\s*,.*?)?\s*,\s*optional:\s*true/) do |match|
      associations << match[0]
    end
    
    code.scan(/belongs_to\s+["'](\w+)["'](?:\s*,.*?)?\s*,\s*optional:\s*true/) do |match|
      associations << match[0]
    end
    
    # Match multi-line belongs_to with optional: true
    # This regex handles cases where belongs_to spans multiple lines
    code.scan(/belongs_to\s+:(\w+)\s*,[\s\S]*?optional:\s*true(?:\s*,|\s*$|\s*\))/) do |match|
      associations << match[0] unless associations.include?(match[0])
    end
    
    code.scan(/belongs_to\s+["'](\w+)["']\s*,[\s\S]*?optional:\s*true(?:\s*,|\s*$|\s*\))/) do |match|
      associations << match[0] unless associations.include?(match[0])
    end
    
    associations.uniq
  end
  
  def find_presence_validations(code)
    validations = []
    
    # Match validates with presence: true
    # Handles both symbol and string field names
    code.scan(/validates\s+:(\w+)(?:\s*,.*?)?\s*,\s*presence:\s*(?:true|{)/) do |match|
      validations << match[0]
    end
    
    code.scan(/validates\s+["'](\w+)["'](?:\s*,.*?)?\s*,\s*presence:\s*(?:true|{)/) do |match|
      validations << match[0]
    end
    
    # Match multi-line validates with presence: true or presence: { ... }
    code.scan(/validates\s+:(\w+)\s*,[\s\S]*?presence:\s*(?:true|{[^}]*})/) do |match|
      validations << match[0] unless validations.include?(match[0])
    end
    
    code.scan(/validates\s+["'](\w+)["']\s*,[\s\S]*?presence:\s*(?:true|{[^}]*})/) do |match|
      validations << match[0] unless validations.include?(match[0])
    end
    
    # Match validates_presence_of with single or multiple fields
    # validates_presence_of :user
    # validates_presence_of :user, :email, :name
    code.scan(/validates_presence_of\s+((?::\w+(?:\s*,\s*)?)+)/) do |match|
      # Extract all field names from the match
      match[0].scan(/:(\w+)/) do |field|
        validations << field[0]
      end
    end
    
    # Also handle string syntax for validates_presence_of
    code.scan(/validates_presence_of\s+((?:["']\w+["'](?:\s*,\s*)?)+)/) do |match|
      match[0].scan(/["'](\w+)["']/) do |field|
        validations << field[0]
      end
    end
    
    validations.uniq
  end
end

# Main script execution
if __FILE__ == $0
  require 'optparse'
  
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: find_optional_with_validation.rb [options]"
    
    opts.on("-d", "--directory DIR", "Directory to scan (default: app/models)") do |dir|
      options[:directory] = dir
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  directory = options[:directory] || 'app/models'
  
  unless File.directory?(directory)
    puts "Error: Directory '#{directory}' does not exist"
    exit 1
  end
  
  finder = OptionalWithValidationFinder.new
  results = finder.scan_directory(directory)
  
  if results.empty?
    puts "No matches found: No belongs_to with optional: true that also has validates presence: true"
  else
    puts "Found #{results.size} match(es):"
    puts
    
    results.each do |result|
      puts "Model: #{result[:model]}"
      puts "Association: #{result[:association]}"
      puts "File: #{result[:file]}"
      puts "-" * 50
    end
  end
end