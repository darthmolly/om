require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require "nokogiri"
require "om"

describe "OM::XML::Accessors" do
  
  before(:all) do
    class RightsMDTest
      
      include OM::XML::Document
          
      terminology = OM::XML::Terminology::Builder.new do |t|
        t.rightsMetadata(:xmlns=>"http://hydra-collab.stanford.edu/schemas/rightsMetadata/v1", :schema=>"http://github.com/projecthydra/schemas/tree/v1/rightsMetadata.xsd") {
          t.access {
            t.human_readable(:path=>"human")
            t.machine {
              t.group
              t.person
            }
          }
          t.edit_access(:variant_of=>:access, :attributes=>{:type=>"personal"})
        }
      end
      # root_property :rightsMetadata, "rightsMetadata", "http://hydra-collab.stanford.edu/schemas/rightsMetadata/v1", :schema=>"http://github.com/projecthydra/schemas/tree/v1/rightsMetadata.xsd"          
      # 
      # property :access, :path=>"access",
      #             :subelements=>[:machine],
      #             :convenience_methods => {
      #               :human_readable => {:path=>"human"}
      #             }
      #             
      # property :edit_access, :variant_of=>:access, :attributes=>{:type=>"edit"}
      # 
      # property :machine, :path=>"machine",
      #             :subelements=>["group","person"]
      
      # generate_accessors_from_properties
      # Generates an empty Mods Article (used when you call ModsArticle.new without passing in existing xml)
      def self.xml_template
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.rightsMetadata(:version=>"0.1", "xmlns"=>"http://hydra-collab.stanford.edu/schemas/rightsMetadata/v1") {
            xml.copyright {
              xml.human
            }
            xml.access(:type=>"discover") {
              xml.human
              xml.machine
            }
            xml.access(:type=>"read") {
              xml.human
              xml.machine
            }
            xml.access(:type=>"edit") {
              xml.human
              xml.machine
            }
          }
        end  
        return builder.doc
      end
    end
  end
  
  before(:each) do
    @sample = RightsMDTest.from_xml(nil)
  end
  
  describe "update_properties" do
    it "should update the declared properties" do
      pending "nesting is too deep..."
      @sample.retrieve(*[:edit_access, :machine, :person]).length.should == 0
      @sample.update_properties([:edit_access, :machine, :person]=>"user id").should == {"edit_access_machine_person"=>{"-1"=>"user id"}}
      @sample.retrieve(*[:edit_access, :machine, :person]).length.should == 1
      @sample.retrieve(*[:edit_access, :machine, :person]).first.text.should == "user id"
    end
  end
  
end