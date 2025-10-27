# frozen_string_literal: true

require_relative "l18n/version"
require "fileutils"
begin
  require "nokogiri"
rescue LoadError
  # We'll raise a clear error when trying to use HTML parsing if Nokogiri isn't available.
end

module Auto
  module L18n
    class Error < StandardError; end
    
    # Represents a hardcoded text finding with metadata
    Finding = Struct.new(:text, :type, :source, :line, :context, keyword_init: true)
    
    # Extract visible hardcoded text from an HTML/ERB file.
    # This focuses on view files (e.g. .html.erb). It will:
    #  - Extract hardcoded strings from ERB Ruby code
    #  - Strip ERB tags with placeholders to preserve structure
    #  - Skip I18n translation calls
    #  - Remove HTML comments
    #  - Parse the remaining HTML and collect visible text nodes and attribute values
    #  - Optionally scan JavaScript for hardcoded strings
    #  - Return structured findings with location metadata
    #
    # @param path [String] Path to the file to analyze
    # @param options [Hash] Configuration options
    # @option options [Boolean] :structured (false) Return Finding objects instead of strings
    # @option options [Integer] :min_length (2) Minimum string length to consider
    # @option options [Array<String>] :ignore_patterns ([]) Regex patterns to exclude
    # @option options [Array<String>] :extra_attrs ([]) Additional HTML attributes to extract
    # @option options [Boolean] :scan_erb_code (true) Extract strings from ERB Ruby code blocks
    # @option options [Boolean] :scan_js (false) Extract strings from JavaScript blocks
    #
    # @return [Array<String>, Array<Finding>] Unique hardcoded strings or Finding objects
    def self.find_text(path, options = {})
      raise ArgumentError, "path must be a String" unless path.is_a?(String)
      return [] unless File.file?(path)

      unless defined?(Nokogiri)
        raise Error, "Nokogiri is required for HTML parsing. Add `nokogiri` to your Gemfile or gemspec."
      end

      # Default options
      opts = {
        structured: false,
        min_length: 2,
        ignore_patterns: [],
        extra_attrs: [],
        scan_erb_code: true,
        scan_js: false
      }.merge(options)

      raw = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
      
      # Track line numbers for better reporting
      line_map = build_line_map(raw)
      
      results = []

      # Helper to validate and record candidate text
      record = lambda do |str, type:, source:, original_position: nil|
        return if str.nil?
        
        # Normalize whitespace
        s = str.gsub(/\s+/, " ").strip
        return if s.empty?
        return if s.length < opts[:min_length]
        
        # Skip our own placeholders
        return if s.include?('⟦ERB') || s.include?('⟦I18N⟧')
        
        # Skip if matches ignore patterns
        opts[:ignore_patterns].each do |pattern|
          return if s =~ /#{pattern}/
        end
        
        # Skip pure punctuation or symbols
        return if s =~ /\A[\W_]*\z/
        
        # Skip placeholder patterns (be more specific to avoid false positives)
        return if s.include?('#{') || s.include?('%{')
        # Only skip if multiple curly braces (likely interpolation)
        return if s.scan(/\{/).size > 1 && s.scan(/\}/).size > 1
        
        # Skip file paths
        return if s =~ %r{\A\.?/?[\w\-]+(/[\w\-\.]+)+\z}
        
        # Skip code-like syntax
        return if s =~ /[;=>]{2,}/ || s =~ /function\s*\(/ || s =~ /\b(?:var|const|let)\s+\w+/
        
        # Normalize quotes for comparison
        normalized = s.tr('""''', %q{"''"})
        
        # Try to estimate line number
        line = estimate_line(original_position, line_map) if original_position
        
        if opts[:structured]
          results << Finding.new(
            text: normalized,
            type: type,
            source: source,
            line: line,
            context: s # keep original for display
          )
        else
          results << normalized
        end
      end

      # PHASE 1: Extract hardcoded strings from ERB Ruby code blocks
      if opts[:scan_erb_code]
        raw.scan(/<%=?\s*(.*?)%>/m).each do |match|
          code = match[0]
          position = raw.index("<%") # Approximate position
          
          # Skip if it's an I18n call
          next if code =~ /\b(?:I18n\.)?(?:t|translate)\s*\(/
          
          # Extract double-quoted strings
          code.scan(/"((?:[^"\\]|\\.)*)"/m).each do |string_match|
            unescaped = string_match[0].gsub(/\\(.)/, '\1')
            record.call(
              unescaped,
              type: :erb_string,
              source: "ERB block",
              original_position: position
            )
          end
          
          # Extract single-quoted strings
          code.scan(/'((?:[^'\\]|\\.)*)'/).each do |string_match|
            unescaped = string_match[0].gsub(/\\(.)/, '\1')
            record.call(
              unescaped,
              type: :erb_string,
              source: "ERB block",
              original_position: position
            )
          end
        end
      end

      # PHASE 2: Prepare HTML for Nokogiri parsing
      # 1) Remove ERB comments
      cleaned_erb = raw.gsub(/<%#.*?%>/m, " ⟦ERB_COMMENT⟧ ")
      
      # 2) Skip I18n translation calls - replace with placeholder
      # Matches: t("key"), t('key'), I18n.t("key"), translate("key"), etc.
      cleaned_erb = cleaned_erb.gsub(/<%=?\s*(?:I18n\.)?(?:t|translate)\s*\([^)]+\)\s*%>/m, " ⟦I18N⟧ ")
      
      # 3) Remove remaining ERB tags with unique placeholder to preserve spacing
      cleaned_erb = cleaned_erb.gsub(/<%=?\s*.*?%>/m, " ⟦ERB⟧ ")

      # 4) Remove HTML comments
      cleaned_erb = cleaned_erb.gsub(/<!--.*?-->/m, " ")

      # 5) Parse with Nokogiri
      fragment = Nokogiri::HTML::DocumentFragment.parse(cleaned_erb)

      # Standard attributes to extract
      standard_attrs = %w[alt title placeholder aria-label aria-placeholder aria-description label]
      # Additional attributes for form inputs and buttons
      value_attrs = %w[value]
      all_attrs = (standard_attrs + value_attrs + opts[:extra_attrs]).uniq

      # PHASE 3: Extract from JavaScript blocks (optional)
      if opts[:scan_js]
        fragment.css('script').each do |script_node|
          js_content = script_node.content
          
          # Extract double-quoted strings
          js_content.scan(/"((?:[^"\\]|\\.)*)"/m).each do |string_match|
            unescaped = string_match[0].gsub(/\\(.)/, '\1')
            record.call(
              unescaped,
              type: :js_string,
              source: "JavaScript block",
              original_position: nil
            )
          end
          
          # Extract single-quoted strings
          js_content.scan(/'((?:[^'\\]|\\.)*)'/).each do |string_match|
            unescaped = string_match[0].gsub(/\\(.)/, '\1')
            record.call(
              unescaped,
              type: :js_string,
              source: "JavaScript block",
              original_position: nil
            )
          end
          
          # Extract template literals (backticks) - basic support
          js_content.scan(/`([^`]*)`/).each do |string_match|
            record.call(
              string_match[0],
              type: :js_template,
              source: "JavaScript template literal",
              original_position: nil
            )
          end
        end
      end

      # PHASE 4: Collect text nodes (visible text)
      fragment.traverse do |node|
        # Skip script, style, and template tags
        next if node.ancestors.any? { |a| %w[script style template].include?(a.name) }
        
        if node.text? && !node.content.strip.empty?
          # Skip if parent has hidden attribute
          next if node.parent&.[]("hidden")
          
          position = find_position_in_original(node.content, raw)
          record.call(
            node.content,
            type: :text_node,
            source: "text content",
            original_position: position
          )
        end
      end

      # PHASE 5: Collect attributes
      selector = all_attrs.map { |attr| "*[#{attr}]" }.join(', ')
      fragment.css(selector).each do |el|
        all_attrs.each do |attr|
          next unless el[attr]
          
          # Skip empty values or single characters for 'value' attribute
          next if attr == 'value' && el[attr].length < 2
          
          position = find_position_in_original(el[attr], raw)
          record.call(
            el[attr],
            type: :attribute,
            source: "#{el.name}[#{attr}]",
            original_position: position
          )
        end
      end

      # PHASE 6: Extract from data-* JSON attributes
      fragment.css('[data-config], [data-text], [data-message], [data-label]').each do |el|
        el.attributes.each do |name, attr|
          next unless name.start_with?('data-')
          value = attr.value
          
          # Try to parse as JSON
          begin
            require 'json'
            parsed = JSON.parse(value)
            extract_strings_from_json(parsed).each do |str|
              record.call(
                str,
                type: :data_attribute,
                source: "#{el.name}[#{name}]",
                original_position: nil
              )
            end
          rescue JSON::ParserError, LoadError
            # Not JSON or JSON not available, skip
          end
        end
      end

      # Return unique results
      if opts[:structured]
        results.uniq { |f| [f.text, f.type] }
      else
        results.uniq
      end
    end

    private

    # Build a map of character positions to line numbers
    def self.build_line_map(content)
      lines = content.lines
      map = []
      pos = 0
      lines.each_with_index do |line, idx|
        map << [pos, idx + 1]
        pos += line.length
      end
      map
    end

    # Estimate line number from character position
    def self.estimate_line(position, line_map)
      return nil unless position && line_map
      line_map.reverse.each do |start_pos, line_num|
        return line_num if position >= start_pos
      end
      1
    end

    # Find approximate position of a string in the original content
    def self.find_position_in_original(str, content)
      # Simple indexOf approach - may not be perfect for duplicates
      content.index(str)
    end

    # Recursively extract string values from JSON structures
    def self.extract_strings_from_json(obj, results = [])
      case obj
      when String
        results << obj unless obj.empty?
      when Array
        obj.each { |item| extract_strings_from_json(item, results) }
      when Hash
        obj.each_value { |value| extract_strings_from_json(value, results) }
      end
      results
    end

      # Exchange hardcoded text for I18n placeholders
    # 
    # This method replaces hardcoded strings in a file with I18n translation calls
    # and adds the translations to a locale file (default: en.yml).
    #
    # @param path [String] Path to the file to process
    # @param options [Hash] Configuration options
    # @option options [String] :locale_path Path to locale file (default: config/locales/en.yml)
    # @option options [String] :locale (en) Locale code
    # @option options [String] :namespace Namespace prefix for translation keys (e.g., 'views.posts')
    # @option options [Boolean] :dry_run (false) Preview changes without modifying files
    # @option options [Integer] :min_length (2) Minimum string length to consider
    # @option options [Array<String>] :ignore_patterns ([]) Regex patterns to exclude
    # @option options [Boolean] :backup (true) Create backup files before modifying
    #
    # @return [Hash] Summary of changes made
    def self.exchange_text_for_l18n_placeholder(path, options = {})
      raise ArgumentError, "path must be a String" unless path.is_a?(String)
      raise ArgumentError, "File not found: #{path}" unless File.file?(path)

      # Default options
      opts = {
        locale_path: "config/locales/en.yml",
        locale: "en",
        namespace: nil,
        dry_run: false,
        min_length: 2,
        ignore_patterns: [],
        backup: true
      }.merge(options)

      # Find all hardcoded text with structured data
      findings = find_text(path, opts.merge(structured: true))

      return { replaced: 0, added_keys: 0, message: "No hardcoded text found" } if findings.empty?

      # Load or create locale file
      locale_data = load_locale_file(opts[:locale_path], opts[:locale])
      
      # Track changes
      replacements = []
      new_keys = []
      
      # Read original file content
      content = File.read(path, encoding: "UTF-8")
      modified_content = content.dup
      
      # Process findings in reverse order by position to maintain string positions
      sorted_findings = findings.sort_by { |f| -(f.line || 0) }
      
      sorted_findings.each_with_index do |finding, idx|
        # Generate translation key
        key = generate_translation_key(finding.text, finding.type, opts[:namespace], idx)
        
        # Add to locale file
        set_nested_key(locale_data, key, finding.text, opts[:locale])
        new_keys << key
        
        # Replace in content based on type
        replacement = case finding.type
        when :erb_string
          # Replace strings in ERB blocks
          replace_erb_string(modified_content, finding.text, key)
        when :text_node
          # Replace HTML text nodes
          replace_text_node(modified_content, finding.context, key)
        when :attribute
          # Replace attribute values
          replace_attribute(modified_content, finding.context, key)
        when :js_string, :js_template
          # Replace JavaScript strings
          replace_js_string(modified_content, finding.text, key)
        when :data_attribute
          # Data attributes are complex, skip for now
          nil
        end
        
        replacements << { text: finding.text, key: key, type: finding.type } if replacement
      end

      unless opts[:dry_run]
        # Create backup
        if opts[:backup]
          backup_path = "#{path}.backup"
          File.write(backup_path, content)
        end
        
        # Write modified file
        File.write(path, modified_content)
        
        # Write locale file
        write_locale_file(opts[:locale_path], locale_data)
      end

      {
        replaced: replacements.size,
        added_keys: new_keys.size,
        keys: new_keys,
        replacements: replacements,
        dry_run: opts[:dry_run]
      }
    end

    # Automatically internationalize a file or directory
    #
    # This is the main entry point that combines finding and replacing hardcoded text.
    # It will:
    # 1. Find all hardcoded text in the file(s)
    # 2. Replace them with I18n translation calls
    # 3. Add translations to locale file
    #
    # @param path [String] Path to file or directory to process
    # @param options [Hash] Configuration options (see exchange_text_for_l18n_placeholder)
    # @option options [Boolean] :recursive (false) Process directories recursively
    # @option options [String] :file_pattern (*.html.erb) File pattern to match in directories
    #
    # @return [Hash] Summary of all changes
    def self.auto_internationalize(path, options = {})
      raise ArgumentError, "path must be a String" unless path.is_a?(String)
      raise ArgumentError, "Path not found: #{path}" unless File.exist?(path)

      opts = {
        recursive: false,
        file_pattern: "*.html.erb"
      }.merge(options)

      results = []

      if File.directory?(path)
        # Process directory
        pattern = opts[:recursive] ? "**/#{opts[:file_pattern]}" : opts[:file_pattern]
        Dir.glob(File.join(path, pattern)).each do |file|
          next unless File.file?(file)
          
          puts "Processing: #{file}" unless opts[:dry_run]
          result = exchange_text_for_l18n_placeholder(file, opts)
          results << { file: file, result: result }
        end
      else
        # Process single file
        result = exchange_text_for_l18n_placeholder(path, opts)
        results << { file: path, result: result }
      end

      # Summary
      total_replaced = results.sum { |r| r[:result][:replaced] }
      total_keys = results.sum { |r| r[:result][:added_keys] }

      {
        files_processed: results.size,
        total_replaced: total_replaced,
        total_keys: total_keys,
        details: results
      }
    end

    private

    # Generate a translation key from text
    def self.generate_translation_key(text, type, namespace, index)
      # Sanitize text to create a valid key
      base_key = text.downcase
        .gsub(/[^\w\s-]/, '') # Remove non-word chars except spaces and hyphens
        .gsub(/\s+/, '_')      # Replace spaces with underscores
        .gsub(/_+/, '_')       # Collapse multiple underscores
        .gsub(/^_|_$/, '')     # Remove leading/trailing underscores
        .slice(0, 50)          # Limit length
      
      # Add index if key would be too generic
      base_key = "text_#{index}" if base_key.empty? || base_key.length < 3
      
      # Build full key with namespace
      parts = []
      parts << namespace if namespace
      parts << base_key
      
      parts.join('.')
    end

    # Load locale file (YAML)
    def self.load_locale_file(path, locale)
      if File.exist?(path)
        require 'yaml'
        YAML.load_file(path) || { locale => {} }
      else
        { locale => {} }
      end
    end

    # Write locale file (YAML)
    def self.write_locale_file(path, data)
      require 'yaml'
      
      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(path))
      
      # Write with nice formatting
      File.write(path, data.to_yaml)
    end

    # Set a nested key in a hash (e.g., "views.posts.title" => "Title")
    def self.set_nested_key(hash, key_path, value, locale)
      keys = key_path.split('.')
      
      # Ensure locale root exists
      hash[locale] ||= {}
      
      # Navigate/create nested structure
      current = hash[locale]
      keys[0..-2].each do |key|
        current[key] ||= {}
        current = current[key]
      end
      
      # Set the value
      current[keys.last] = value
    end

    # Replace a string in ERB code blocks
    def self.replace_erb_string(content, text, key)
      # Match both single and double quoted strings
      escaped_text = Regexp.escape(text)
      
      # Try double quotes first
      pattern = /"#{escaped_text}"/
      if content =~ pattern
        content.gsub!(pattern, "t('#{key}')")
        return true
      end
      
      # Try single quotes
      pattern = /'#{escaped_text}'/
      if content =~ pattern
        content.gsub!(pattern, "t('#{key}')")
        return true
      end
      
      false
    end

    # Replace text in HTML text nodes
    def self.replace_text_node(content, text, key)
      # Escape special regex characters but preserve the text structure
      escaped = Regexp.escape(text)
      
      # Look for the text outside of ERB tags
      pattern = /(?<![<%=])(\s*)#{escaped}(\s*)(?!%>)/
      
      if content =~ pattern
        content.gsub!(pattern, "\\1<%= t('#{key}') %>\\2")
        return true
      end
      
      false
    end

    # Replace attribute values
    def self.replace_attribute(content, text, key)
      escaped = Regexp.escape(text)
      
      # Match attribute="text" or attribute='text'
      pattern = /(\w+)=["']#{escaped}["']/
      
      if content =~ pattern
        content.gsub!(pattern, "\\1=\"<%= t('#{key}') %>\"")
        return true
      end
      
      false
    end

    # Replace JavaScript strings
    def self.replace_js_string(content, text, key)
      escaped = Regexp.escape(text)
      
      # Try double quotes
      pattern = /"#{escaped}"/
      if content =~ pattern
        content.gsub!(pattern, "\"<%= t('#{key}') %>\"")
        return true
      end
      
      # Try single quotes
      pattern = /'#{escaped}'/
      if content =~ pattern
        content.gsub!(pattern, "'<%= t('#{key}') %>'")
        return true
      end
      
      false
    end

    # Build a map of character positions to line numbers
    def self.build_line_map(content)
      lines = content.lines
      map = []
      pos = 0
      lines.each_with_index do |line, idx|
        map << [pos, idx + 1]
        pos += line.length
      end
      map
    end

    # Estimate line number from character position
    def self.estimate_line(position, line_map)
      return nil unless position && line_map
      line_map.reverse.each do |start_pos, line_num|
        return line_num if position >= start_pos
      end
      1
    end

    # Find approximate position of a string in the original content
    def self.find_position_in_original(str, content)
      # Simple indexOf approach - may not be perfect for duplicates
      content.index(str)
    end

    # Recursively extract string values from JSON structures
    def self.extract_strings_from_json(obj, results = [])
      case obj
      when String
        results << obj unless obj.empty?
      when Array
        obj.each { |item| extract_strings_from_json(item, results) }
      when Hash
        obj.each_value { |value| extract_strings_from_json(value, results) }
      end
      results
    end
  end
end
