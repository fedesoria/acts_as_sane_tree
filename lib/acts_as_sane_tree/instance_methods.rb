module ActsAsSaneTree
  module InstanceMethods

    # Returns all ancestors of the current node. 
    def ancestors
      query = 
        "(WITH RECURSIVE crumbs AS (
          SELECT #{self.class.configuration[:class].table_name}.*,
          1 AS depth
          FROM #{self.class.configuration[:class].table_name}
          WHERE #{configuration[:primary_key]} = #{configuration[:primary_key]} 
          UNION ALL
          SELECT alias1.*, 
          depth + 1 
          FROM crumbs
          JOIN #{self.class.configuration[:class].table_name} alias1 ON alias1.#{configuration[:primary_key]} = crumbs.#{configuration[:foreign_key]}
        ) SELECT * FROM crumbs WHERE crumbs.#{configuration[:primary_key]} != #{configuration[:primary_key]}) as #{self.class.configuration[:class].table_name}"
      if(self.class.rails_3?)
        self.class.configuration[:class].send(:with_exclusive_scope) do
          self.class.configuration[:class].from(
            query
          ).order("#{self.class.configuration[:class].table_name}.depth DESC")
        end
      else
        self.class.configuration[:class].send(:with_exclusive_scope) do
          self.class.configuration[:class].scoped(
            :from => query,
            :order => "#{self.class.configuration[:class].table_name}.depth DESC"
          )
        end
      end
    end

    # Returns the root node of the tree.
    def root
      ancestors.first
    end

    # Returns all siblings of the current node.
    #
    #   subchild1.siblings # => [subchild2]
    def siblings
      self_and_siblings - [self]
    end

    # Returns all siblings and a reference to the current node.
    #
    #   subchild1.self_and_siblings # => [subchild1, subchild2]
    def self_and_siblings
      parent ? parent.children : self.class.configuration[:class].roots
    end
    
    # Returns if the current node is a root
    def root?
      eval("#{configuration[:foreign_key]}.nil?")
    end
    
    # Returns all descendants of the current node. Each level
    # is within its own hash, so for a structure like:
    #   root
    #    \_ child1
    #         \_ subchild1
    #               \_ subsubchild1
    #         \_ subchild2
    # the resulting hash would look like:
    # 
    #  {child1 => 
    #    {subchild1 => 
    #      {subsubchild1 => {}},
    #     subchild2 => {}}}
    #
    # This method will accept two parameters.
    #   * :raw -> Result is scope that can more finders can be chained against with additional 'level' attribute
    #   * {:depth => n} -> Will only search for descendants to the given depth of n
    # NOTE: You can restrict results by depth on the scope returned, but better performance will be
    # gained by specifying it within the args so it will be applied during the recursion, not after.
    def descendants(*args)
      args.delete_if{|x| !x.is_a?(Hash) && x != :raw}
      self.class.configuration[:class].nodes_and_descendants(:no_self, self, *args)
    end
    alias_method :descendents, :descendants
    
    # Returns the depth of the current node. 0 depth represents the root of the tree
    def depth
      query = 
        "WITH RECURSIVE crumbs AS (
          SELECT #{configuration[:foreign_key]}, 0 AS level
          FROM #{self.class.configuration[:class].table_name}
          WHERE #{configuration[:primary_key]} = #{self.send(configuration[:primary_key])} 
          UNION ALL
          SELECT alias1.#{configuration[:foreign_key]}, level + 1 
          FROM crumbs
          JOIN #{self.class.configuration[:class].table_name} alias1 ON alias1.#{configuration[:primary_key]} = crumbs.#{configuration[:foreign_key]}
        ) SELECT level FROM crumbs ORDER BY level DESC LIMIT 1"
      ActiveRecord::Base.connection.select_all(query).first.try(:[], 'level').try(:to_i)
    end
  end
end
