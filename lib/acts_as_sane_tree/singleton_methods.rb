module ActsAsSaneTree
  module SingletonMethods
    
    # Check if we are in rails 3
    def rails_3?
      @is_3 ||= !defined?(Arel).nil?
    end

    # Return all root nodes
    def roots
      if(rails_3?)
        configuration[:class].where(
          "#{configuration[:foreign_key]} IS NULL"
        ).order(configuration[:order])
      else
        configuration[:class].scoped(
          :conditions => "#{configuration[:foreign_key]} IS NULL",
          :order => configuration[:order]
        )
      end
    end

    # Return first root node
    def root
      if(rails_3?)
        configuration[:class].where("#{configuration[:foreign_key]} IS NULL").order(configuration[:order]).first
      else
        configuration[:class].find(
          :first, 
          :conditions => "#{configuration[:foreign_key]} IS NULL", 
          :order => configuration[:order]
        )
      end
    end

    # src:: Array of nodes
    # chk:: Array of nodes
    # Return true if any nodes within chk are found within src
    def nodes_within?(src, chk)
      s = (src.is_a?(Array) ? src : [src]).map{|x|x.is_a?(ActiveRecord::Base) ? eval("x.#{configuration[:primary_key]}") : x.to_s}
      c = (chk.is_a?(Array) ? chk : [chk]).map{|x|x.is_a?(ActiveRecord::Base) ? eval("x.#{configuration[:primary_key]}") : x.to_s}
      if(s.empty? || c.empty?)
        false
      else
        q = configuration[:class].connection.select_all(
          "WITH RECURSIVE crumbs AS (
            SELECT #{configuration[:class].table_name}.*, 0 AS level FROM #{configuration[:class].table_name} WHERE #{configuration[:primary_key]} in (#{s.join(', ')})
            UNION ALL
            SELECT alias1.*, crumbs.level + 1 FROM crumbs JOIN #{configuration[:class].table_name} alias1 on alias1.#{configuration[:foreign_key]} = crumbs.#{configuration[:primary_key]}
          ) SELECT count(*) as count FROM crumbs WHERE #{configuration[:primary_key]} in (#{c.join(', ')})"
        )
        q.first['count'].to_i > 0
      end
    end

    # src:: Array of nodes
    # chk:: Array of nodes
    # Return all nodes that are within both chk and src
    def nodes_within(src, chk)
      s = (src.is_a?(Array) ? src : [src]).map{|x|x.is_a?(ActiveRecord::Base) ? eval("x.#{configuration[:primary_key]}") : x.to_s}
      c = (chk.is_a?(Array) ? chk : [chk]).map{|x|x.is_a?(ActiveRecord::Base) ? eval("x.#{configuration[:primary_key]}") : x.to_s}
      if(s.empty? || c.empty?)
        nil
      else
        query = 
          "(WITH RECURSIVE crumbs AS (
            SELECT #{configuration[:class].table_name}.*, 0 AS depth FROM #{configuration[:class].table_name} WHERE #{configuration[:primary_key]} in (#{s.join(', ')})
            UNION ALL
            SELECT alias1.*, crumbs.depth + 1 FROM crumbs JOIN #{configuration[:class].table_name} alias1 on alias1.#{configuration[:foreign_key]} = crumbs.#{configuration[:primary_key]}
            #{configuration[:max_depth] ? "WHERE crumbs.depth + 1 < #{configuration[:max_depth].to_i}" : ''}
          ) SELECT * FROM crumbs WHERE #{configuration[:primary_key]} in (#{c.join(', ')})) as #{configuration[:class].table_name}"
        if(rails_3?)
          configuration[:class].from(query)
        else
          configuration[:class].scoped(:from => query)
        end
      end
    end
    
    # args:: ActiveRecord models or IDs - Symbols: :raw, :no_self - Hash: {:to_depth => n, :at_depth => n}
    # Returns provided nodes plus all descendants of provided nodes in nested Hash where keys are nodes and values are children
    # :raw:: return value will be flat array
    # :no_self:: Do not include provided nodes in result
    # Hash:
    #   :to_depth:: Only retrieve values to given depth
    #   :at_depth:: Only retrieve values from given depth
    def nodes_and_descendants(*args)
      raw = args.delete(:raw)
      no_self = args.delete(:no_self)
      at_depth = nil
      depth = nil
      hash = args.detect{|x|x.is_a?(Hash)}
      if(hash)
        args.delete(hash)
        depth = hash[:depth] || hash[:to_depth]
        at_depth = hash[:at_depth]
      end
      depth ||= configuration[:max_depth].to_i
      depth_restriction = "WHERE crumbs.depth + 1 < #{depth}" if depth
      depth_clause = nil
      if(at_depth)
        depth_clause = "#{configuration[:class].table_name}.depth + 1 = #{at_depth.to_i + 1}"
      elsif(depth)
        depth_clause = "#{configuration[:class].table_name}.depth + 1 < #{depth.to_i + 2}"
      end
      base_ids = args.map{|x| x.is_a?(ActiveRecord::Base) ? eval("x.#{configuration[:primary_key]}") : x.to_s}
      query = 
        "(WITH RECURSIVE crumbs AS (
          SELECT #{configuration[:class].table_name}.*, #{no_self ? -1 : 0} AS depth FROM #{configuration[:class].table_name} WHERE #{base_ids.empty? ? '#{configuration[:foreign_key]} IS NULL' : "#{configuration[:primary_key]} in (#{base_ids.join(', ')})"}
          UNION ALL
          SELECT alias1.*, crumbs.depth + 1 FROM crumbs JOIN #{configuration[:class].table_name} alias1 on alias1.#{configuration[:foreign_key]} = crumbs.#{configuration[:primary_key]}
          #{depth_restriction}
        ) SELECT * FROM crumbs) as #{configuration[:class].table_name}"
      q = nil
      if(rails_3?)
        q = configuration[:class].from(
          query
        ).where(
          "#{configuration[:class].table_name}.depth >= 0"
        )
        if(depth_clause)
          q = q.where(depth_clause)
        end
        if(configuration[:order].present?)
          q = q.order(configuration[:order])
        end
      else
        q = configuration[:class].scoped(
          :from => query, 
          :conditions => "#{configuration[:class].table_name}.depth >= 0"
        )
        if(configuration[:order].present?)
          q = q.scoped(:order => configuration[:order])
        end
        if(depth_clause)
          q = q.scoped(:conditions => depth_clause)
        end
      end
      unless(rails_3?)
        q = q.scoped(scope(:find))
      end
      unless(raw)
        res = ActiveSupport::OrderedHash.new
        cache = ActiveSupport::OrderedHash.new
        q.all.each do |item|
          res[item] = ActiveSupport::OrderedHash.new
          cache[item] = res[item]
        end
        cache.each_pair do |item, values|
          if(cache[item.parent])
            cache[item.parent][item] = values
            res.delete(item)
          end
        end
        res
      else
        q
      end
    end
    alias_method :nodes_and_descendents, :nodes_and_descendants

  end
end
