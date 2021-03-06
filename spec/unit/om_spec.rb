require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require "nokogiri"
require "om"

describe "OM" do
  
  describe "#{}destringify" do
    it "should recursively change any strings beginning with : to symbols and any number strings to integers" do
      OM.destringify( [{":person"=>"0"}, ":last_name"] ).should == [{:person=>0}, :last_name]
      OM.destringify( [{"person"=>"3"}, "last_name"] ).should == [{:person=>3}, :last_name]
    end
  end
  
end