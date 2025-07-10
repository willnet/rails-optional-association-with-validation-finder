#!/usr/bin/env ruby

require_relative 'find_optional_with_validation'

class OptionalToRequiredReplacer
  def initialize
    @finder = OptionalWithValidationFinder.new
  end

  def replace_in_code(code)
    lines = code.lines
    result_lines = lines.dup
    
    # Find all optional associations with presence validations
    matches = @finder.analyze_model_code('Model', code)
    
    # Track which lines to remove (for validates statements)
    lines_to_remove = []
    
    matches.each do |match|
      association_name = match[:association]
      
      # Replace optional: true with required: true in belongs_to
      result_lines = replace_optional_with_required(result_lines, association_name)
      
      # Remove or modify validates statements
      result_lines, removed = remove_or_modify_validates(result_lines, association_name)
      lines_to_remove.concat(removed)
    end
    
    # Clean up empty lines where validates were removed
    result_lines = cleanup_empty_lines(result_lines, lines_to_remove)
    
    result_lines.join
  end

  def replace_in_file(file_path, dry_run: false)
    original_content = File.read(file_path)
    new_content = replace_in_code(original_content)
    
    if original_content == new_content
      return false
    end
    
    if dry_run
      puts "Would replace in #{file_path}:"
      puts "=" * 50
      show_diff(original_content, new_content)
      puts "=" * 50
      puts
    else
      File.write(file_path, new_content)
      puts "Updated: #{file_path}"
    end
    
    true
  end

  def replace_in_directory(directory, dry_run: false)
    updated_files = 0
    
    Dir.glob(File.join(directory, '**', '*.rb')).each do |file|
      if replace_in_file(file, dry_run: dry_run)
        updated_files += 1
      end
    end
    
    puts "\n#{dry_run ? 'Would update' : 'Updated'} #{updated_files} file(s)"
  end

  private

  def replace_optional_with_required(lines, association_name)
    result = []
    belongs_to_indices = []
    
    # First, find all belongs_to declarations for this association
    lines.each_with_index do |line, index|
      if line =~ /belongs_to\s+:#{association_name}\b/ || line =~ /belongs_to\s+["']#{association_name}["']/
        belongs_to_indices << index
      end
    end
    
    # For each belongs_to, find its span and check if it has optional: true
    belongs_to_indices.each do |start_index|
      # Find the range of lines that belong to this belongs_to
      end_index = start_index
      paren_count = 0
      
      # Scan from start to find where belongs_to ends
      (start_index...lines.length).each do |i|
        line = lines[i]
        paren_count += line.count('(') - line.count(')')
        
        # Check if this line likely ends the belongs_to
        # It ends if we're back to paren_count 0 and line doesn't end with comma
        if i > start_index && paren_count <= 0 && !line.rstrip.end_with?(',')
          end_index = i
          break
        elsif i == start_index && !line.rstrip.end_with?(',') && paren_count <= 0
          # Single line belongs_to
          end_index = i
          break
        end
      end
      
      # Check if this belongs_to has optional: true
      belongs_to_text = lines[start_index..end_index].join
      if belongs_to_text =~ /optional:\s*true/
        # This belongs_to needs to be modified - continue processing
      end
    end
    
    # Process all lines
    belongs_to_ranges = []
    belongs_to_indices.each do |start_index|
      # Find the range again
      end_index = start_index
      paren_count = 0
      
      (start_index...lines.length).each do |i|
        line = lines[i]
        paren_count += line.count('(') - line.count(')')
        
        if i > start_index && paren_count <= 0 && !line.rstrip.end_with?(',')
          end_index = i
          break
        elsif i == start_index && !line.rstrip.end_with?(',') && paren_count <= 0
          end_index = i
          break
        end
      end
      
      belongs_to_text = lines[start_index..end_index].join
      if belongs_to_text =~ /optional:\s*true/
        belongs_to_ranges << [start_index, end_index]
      end
    end
    
    # Replace optional with required in the appropriate ranges
    lines.each_with_index do |line, index|
      in_range = belongs_to_ranges.any? { |start, end_idx| index >= start && index <= end_idx }
      
      if in_range
        modified_line = line.gsub(/optional:\s*true/, 'required: true')
        result << modified_line
      else
        result << line
      end
    end
    
    result
  end

  def remove_or_modify_validates(lines, association_name)
    result = []
    lines_removed = []
    
    lines.each_with_index do |line, index|
      # Match validates for this association
      if line =~ /validates\s+:#{association_name}\b/ || line =~ /validates\s+["']#{association_name}["']/
        # Check if this validates only has presence validation
        if line =~ /validates\s+[:"]#{association_name}["']?\s*,\s*presence:\s*(?:true|\{[^}]*\})\s*$/
          # Remove entire line
          lines_removed << index
          next
        elsif line =~ /validates\s+[:"]#{association_name}["']?\s*,\s*(.*)presence:\s*(?:true|\{[^}]*\})\s*,?\s*(.*)$/
          # Remove just the presence part
          before = $1
          after = $2
          
          # Reconstruct the line without presence validation
          new_validations = []
          
          # Parse other validations (simplified approach)
          all_validations = (before + after).strip
          if all_validations.length > 0
            # Clean up extra commas
            all_validations = all_validations.gsub(/,\s*,/, ',').gsub(/,\s*$/, '').gsub(/^\s*,/, '')
            if all_validations.length > 0
              result << "  validates :#{association_name}, #{all_validations}\n"
              next
            end
          end
          
          # If no other validations remain, remove the line
          lines_removed << index
          next
        end
      # Match validates_presence_of for this association
      elsif line =~ /validates_presence_of\s+/
        # Check if this line contains our association
        if line =~ /validates_presence_of\s+(.*)/
          fields_part = $1
          
          # Parse all fields in validates_presence_of
          fields = []
          fields_part.scan(/:(\w+)/) { |match| fields << match[0] }
          fields_part.scan(/["'](\w+)["']/) { |match| fields << match[0] }
          
          if fields.include?(association_name)
            # Remove this association from the list
            remaining_fields = fields - [association_name]
            
            if remaining_fields.empty?
              # Remove entire line if no fields remain
              lines_removed << index
              next
            else
              # Reconstruct validates_presence_of with remaining fields
              new_line = "  validates_presence_of "
              new_line += remaining_fields.map { |f| ":#{f}" }.join(", ")
              new_line += "\n"
              result << new_line
              next
            end
          end
        end
      end
      
      result << line
    end
    
    [result, lines_removed]
  end

  def cleanup_empty_lines(lines, removed_indices)
    # If we removed validates lines, we might have extra blank lines
    result = []
    prev_blank = false
    
    lines.each_with_index do |line, index|
      is_blank = line.strip.empty?
      
      # Don't add multiple consecutive blank lines
      if is_blank && prev_blank
        next
      end
      
      result << line
      prev_blank = is_blank
    end
    
    # Remove trailing blank lines from classes
    cleaned = []
    
    result.each_with_index do |line, index|
      # Check if next line is 'end'
      next_line = result[index + 1]
      
      # Skip blank lines that come right before 'end'
      if line.strip.empty? && next_line && next_line =~ /^\s*end\s*$/
        next
      end
      
      cleaned << line
    end
    
    cleaned
  end

  def show_diff(original, modified)
    original_lines = original.lines
    modified_lines = modified.lines
    
    max_lines = [original_lines.length, modified_lines.length].max
    
    max_lines.times do |i|
      orig_line = original_lines[i]
      mod_line = modified_lines[i]
      
      if orig_line != mod_line
        if orig_line && !mod_line
          puts "- #{orig_line.chomp}"
        elsif !orig_line && mod_line
          puts "+ #{mod_line.chomp}"
        else
          puts "- #{orig_line.chomp}" if orig_line
          puts "+ #{mod_line.chomp}" if mod_line
        end
      end
    end
  end
end

# Main script execution
if __FILE__ == $0
  require 'optparse'
  
  options = { dry_run: false }
  OptionParser.new do |opts|
    opts.banner = "Usage: replace_optional_with_required.rb [options]"
    
    opts.on("-d", "--directory DIR", "Directory to process (default: app/models)") do |dir|
      options[:directory] = dir
    end
    
    opts.on("-f", "--file FILE", "Single file to process") do |file|
      options[:file] = file
    end
    
    opts.on("--dry-run", "Show what would be changed without modifying files") do
      options[:dry_run] = true
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  replacer = OptionalToRequiredReplacer.new
  
  if options[:file]
    unless File.exist?(options[:file])
      puts "Error: File '#{options[:file]}' does not exist"
      exit 1
    end
    
    replacer.replace_in_file(options[:file], dry_run: options[:dry_run])
  else
    directory = options[:directory] || 'app/models'
    
    unless File.directory?(directory)
      puts "Error: Directory '#{directory}' does not exist"
      exit 1
    end
    
    replacer.replace_in_directory(directory, dry_run: options[:dry_run])
  end
end