module ActsAsIndexed
  class MultiSearch

    def self.find_with_index(query, find_options = {}, options = {})

      klasses = options[:classes]
      raise(ArgumentError, 'Must supply an array of classes to search in the :options parameter') if klasses.nil? or klasses.empty?

      results = {}

      klasses.each do |klass|
        klass.send :build_index unless klass.aai_config.index_file.directory?
        klass.send(:new_index).search(query).each do |id, rank|
          results[[klass,id]] = rank
        end
      end

      offset = find_options[:offset] || 0
      limit = find_options.include?(:limit) ? find_options[:limit] : results.size

      ranked_records = results.to_a.sort_by{ |a| a.last }.slice(offset, limit)

      if options[:size_only] == true
        return ranked_records.size
      end

      final_results = {}

      klasses.each do |klass|
        part_query = ranked_records.select {|r| r.first.first == klass}.map {|r| r.first.last}

        klass.send(:with_scope, :find => find_options.except(:limit, :offset)) do
          # Doing the find like this eliminates the possibility of errors occuring
          # on either missing records (out-of-sync) or an empty results array.
          records = klass.find(:all, :conditions => [ "#{klass.table_name}.#{klass.primary_key} IN (?)", part_query])

          records.each do |r|
            final_results[r] = results[[klass, r.id]]
          end

        end
      end

      final_results.to_a.sort_by {|a| a.last}.map(&:first)

    end

    def self.paginate_search(query, find_options = {}, options = {})
      page = find_options.fetch(:page) { raise ArgumentError, ":page parameter required" }
      per_page = find_options.delete(:per_page) || self.per_page
      total_entries = find_options.delete(:total_entries)

      # TODO: The requirement to know a count before performing the actual search means
      # we conduct the search in the index twice. This requirement could (and should)
      # be optimised away.
      total_entries ||= find_with_index(query,{},options.merge({:size_only => true}))

      pager = ::WillPaginate::Collection.new(page, per_page, total_entries)
      find_options.update :offset => pager.offset, :limit => pager.per_page

      find_options = find_options.delete_if {|key, value| [:page, :per_page].include?(key) }

      pager.replace find_with_index(query, find_options, options)
      pager
    end
  end

end
