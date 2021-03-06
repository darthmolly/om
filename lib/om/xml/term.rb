# Special options: data_type, attributes, index_as
# is_root_term
#
class OM::XML::Term
  
  # Term::Builder Class Definition
  #
  # @example
  #   tb2 = OM::XML::Term::Builder.new("my_term_name").path("fooPath").attributes({:lang=>"foo"}).index_as([:searchable, :facetable]).required(true).data_type(:text) 
  #
  #   
  #
  # When coding against Builders, remember that they rely on MethodMissing, 
  # so any time you call a method on the Builder that it doesn't explicitly recognize, 
  # the Builder will add your method & arguments to the it's settings and return itself.
  class Builder
    attr_accessor :name, :settings, :children, :terminology_builder
    
    def initialize(name, terminology_builder=nil)
      @name = name.to_sym
      @terminology_builder = terminology_builder
      @settings = {:required=>false, :data_type=>:string}
      @children = {}
    end
    
    def add_child(child)
      @children[child.name] = child
    end
    
    def retrieve_child(child_name)
      child = @children.fetch(child_name, nil)
    end
    
    def lookup_refs(nodes_visited=[])
      result = []
      if @settings[:ref]
        # Fail if we do not have terminology builder
        if self.terminology_builder.nil?
          raise "Cannot perform lookup_ref for the #{self.name} builder.  It doesn't have a reference to any terminology builder"
        end
        begin
          target = self.terminology_builder.retrieve_term_builder(*@settings[:ref])
        rescue OM::XML::Terminology::BadPointerError
          # Clarify message on BadPointerErrors
          raise OM::XML::Terminology::BadPointerError, "#{self.name} refers to a Term Builder that doesn't exist.  The bad pointer is #{@settings[:ref].inspect}"
        end
        
        # Fail on circular references and return an intelligible error message
        if nodes_visited.include?(target)
          nodes_visited << self
          nodes_visited << target
          trail = ""
          nodes_visited.each_with_index do |node, z|
            trail << node.name.inspect
            unless z == nodes_visited.length-1
              trail << " => "
            end
          end
          raise OM::XML::Terminology::CircularReferenceError, "Circular reference in Terminology: #{trail}"
        end
        result << target
        result.concat( target.lookup_refs(nodes_visited << self) )
      end
      return result
    end
    
    # If a :ref value has been set, looks up the target of that ref and merges the target's settings & children with the current builder's settings & children
    # operates recursively, so it is possible to apply refs that in turn refer to other nodes.
    def resolve_refs!
      name_of_last_ref = nil
      lookup_refs.each_with_index do |ref,z|        
        @settings = two_layer_merge(@settings, ref.settings)
        @children.merge!(ref.children)
        name_of_last_ref = ref.name
      end
      if @settings[:path].nil? && !name_of_last_ref.nil?
        @settings[:path] = name_of_last_ref.to_s
      end
      @settings.delete :ref
      return self
    end
    
    # Returns a new Hash that merges +downstream_hash+ with +upstream_hash+
    # similar to calling +upstream_hash+.merge(+downstream_hash+) only it also merges 
    # any internal values that are themselves Hashes.
    def two_layer_merge(downstream_hash, upstream_hash)
      up = upstream_hash.dup
      dn = downstream_hash.dup
      up.each_pair do |setting_name, value|
        if value.kind_of?(Hash) && downstream_hash.has_key?(setting_name)  
          dn[setting_name] = value.merge(downstream_hash[setting_name])
          up.delete(setting_name)
        end
      end
      return up.merge(dn)
    end
    
    # Builds a new OM::XML::Term based on the Builder object's current settings
    # If no path has been provided, uses the Builder object's name as the term's path
    # Recursively builds any children, appending the results as children of the Term that's being built.
    # @param [OM::XML::Terminology] terminology that this Term is being built for
    def build(terminology=nil)
      self.resolve_refs!
      if term.self.settings.has_key?(:proxy)
        term = OM::XML::NamedTermProxy.new(self.name, self.settings[:proxy], terminology, self.settings)
      else
        term = OM::XML::Term.new(self.name)
      
        self.settings.each do |name, values|  
          if term.respond_to?(name.to_s+"=")
            term.instance_variable_set("@#{name}", values)
          end
        end
        @children.each_value do |child|
          term.add_child child.build(terminology)
        end
        term.generate_xpath_queries!
      end
      
      return term
    end
    
    # Any unknown method calls will add an entry to the settings hash and return the current object
    def method_missing method, *args, &block 
      if args.length == 1
        args = args.first
      end
      @settings[method] = args
      return self
    end
  end
  
  # Term Class Definition
  
  attr_accessor :name, :xpath, :xpath_constrained, :xpath_relative, :path, :index_as, :required, :data_type, :variant_of, :path, :attributes, :default_content_path, :namespace_prefix, :is_root_term
  attr_accessor :children, :internal_xml, :terminology
  
  include OM::TreeNode
  
  # h2. Namespaces
  # By default, OM assumes that all terms in a Terminology have the namespace set in the root of the document.  If you want to set a different namespace for a Term, pass :namespasce_prefix into its initializer (or call .namespace_prefix= on its builder)
  # If a node has _no_ namespace, you must explicitly set namespace_prefix to nil.
  def initialize(name, opts={})
    opts = {:namespace_prefix=>"oxns", :ancestors=>[], :children=>{}}.merge(opts)
    [:children, :ancestors,:path, :index_as, :required, :type, :variant_of, :path, :attributes, :default_content_path, :namespace_prefix].each do |accessor_name|
      instance_variable_set("@#{accessor_name}", opts.fetch(accessor_name, nil) )     
    end
    @name = name
    if @path.nil? || @path.empty?
      @path = name.to_s
    end
  end
  
  def self.from_node(mapper_xml)    
    name = mapper_xml.attribute("name").text.to_sym
    attributes = {}
    mapper_xml.xpath("./attribute").each do |a|
      attributes[a.attribute("name").text.to_sym] = a.attribute("value").text
    end
    new_mapper = self.new(name, :attributes=>attributes)
    [:index_as, :required, :type, :variant_of, :path, :default_content_path, :namespace_prefix].each do |accessor_name|
      attribute =  mapper_xml.attribute(accessor_name.to_s)
      unless attribute.nil?
        new_mapper.instance_variable_set("@#{accessor_name}", attribute.text )      
      end     
    end
    new_mapper.internal_xml = mapper_xml
    
    mapper_xml.xpath("./mapper").each do |child_node|
      child = self.from_node(child_node)
      new_mapper.add_child(child)
    end
    
    return new_mapper
  end
  
  # crawl down into mapper's children hash to find the desired mapper
  # ie. @test_mapper.retrieve_mapper(:conference, :role, :text)
  def retrieve_term(*pointers)
    children_hash = self.children
    pointers.each do |p|
      if children_hash.has_key?(p)
        target = children_hash[p]
        if pointers.index(p) == pointers.length-1
          return target
        else
          children_hash = target.children
        end
      else
        return nil
      end
    end
    return target
  end
  
  def is_root_term?
    @is_root_term == true
  end
  
  def xpath_absolute
    @xpath
  end
  
  # +term_pointers+ reference to the property you want to generate a builder template for
  # @opts
  def xml_builder_template(extra_opts = {})
    extra_attributes = extra_opts.fetch(:attributes, {})  

    node_options = []
    node_child_template = ""
    if !self.default_content_path.nil?
      node_child_options = ["\':::builder_new_value:::\'"]
      node_child_template = " { xml.#{self.default_content_path}( #{OM::XML.delimited_list(node_child_options)} ) }"
    else
      node_options = ["\':::builder_new_value:::\'"]
    end
    if !self.attributes.nil?
      self.attributes.merge(extra_attributes).each_pair do |k,v|
        node_options << ":#{k}=>\'#{v}\'"
      end
    end
    template = "xml.#{self.path}( #{OM::XML.delimited_list(node_options)} )" + node_child_template
    return template.gsub( /:::(.*?):::/ ) { '#{'+$1+'}' }
  end
  
  # Generates absolute, relative, and constrained xpaths for the term, setting xpath, xpath_relative, and xpath_constrained accordingly.
  # Also triggers update_xpath_values! on all child nodes, as their absolute paths rely on those of their parent nodes.
  def generate_xpath_queries!
    self.xpath = OM::XML::TermXpathGenerator.generate_absolute_xpath(self)
    self.xpath_constrained = OM::XML::TermXpathGenerator.generate_constrained_xpath(self)
    self.xpath_relative = OM::XML::TermXpathGenerator.generate_relative_xpath(self)
    self.children.each_value {|child| child.generate_xpath_queries! }
    return self
  end
  
  # private :update_xpath_values
  
end