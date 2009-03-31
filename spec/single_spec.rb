#!/usr/bin/env ruby

require File.expand_path(File.dirname(__FILE__)) + '/spec_common'
require File.expand_path(File.dirname(__FILE__)) + '/example'
require 'bindata/io'
require 'bindata/single'

class ExampleSingle
  # reopen example to make @in_read public for testing
  def in_read?
    @in_read
  end
end

describe BinData::Single, "when subclassing" do
  before(:all) do
    eval <<-END
      class SubClassOfSingle < BinData::Single
        expose_methods_for_testing
      end
    END
  end

  before(:each) do
    @obj = SubClassOfSingle.new
  end

  it "should raise errors on unimplemented methods" do
    lambda { @obj.value_to_string(nil) }.should raise_error(NotImplementedError)
    lambda { @obj.read_and_return_value(nil) }.should raise_error(NotImplementedError)
    lambda { @obj.sensible_default }.should raise_error(NotImplementedError)
  end
end

describe BinData::Single do
  it "should conform to rule 1 for returning a value" do
    data = ExampleSingle.new(:value => 5)
    data.should_not be_in_read
    data.value.should == 5
  end

  it "should conform to rule 2 for returning a value" do
    io = StringIO.new([42].pack("V"))
    data = ExampleSingle.new(:value => 5)
    data.expose_methods_for_testing
    data.do_read(BinData::IO.new(io))
    data.should be_in_read
    data.value.should == 42
  end

  it "should conform to rule 3 for returning a value" do
    data = ExampleSingle.new(:initial_value => 5)
    data.should be_clear
    data.value.should == 5
  end

  it "should conform to rule 4 for returning a value" do
    data = ExampleSingle.new(:initial_value => 5)
    data.value = 17
    data.should_not be_clear
    data.value.should == 17
  end

  it "should conform to rule 5 for returning a value" do
    data = ExampleSingle.new
    data.should be_clear
    data.value.should == 0
  end

  it "should conform to rule 6 for returning a value" do
    data = ExampleSingle.new
    data.value = 8
    data.should_not be_clear
    data.value.should == 8
  end
end

describe BinData::Single, "after initialisation" do
  before(:each) do
    @data = ExampleSingle.new
  end

  it "should not allow both :initial_value and :value" do
    params = {:initial_value => 1, :value => 2}
    lambda { ExampleSingle.new(params) }.should raise_error(ArgumentError)
  end

  it "should have a sensible value" do
    @data.value.should == 0
  end

  it "should have symmetric IO" do
    @data.value = 42
    written = @data.to_s

    ExampleSingle.read(written).should == 42
  end

  it "should be a single_value" do
    @data.should be_single_value
  end

  it "should allowing setting and retrieving value" do
    @data.value = 5
    @data.value.should == 5
  end

  it "should be clear" do
    @data.should be_clear
  end

  it "should not be clear after setting value" do
    @data.value = 5
    @data.should_not be_clear
  end

  it "should not be clear after reading" do
    @data.read("\x11\x22\x33\x44")
    @data.should_not be_clear
  end

  it "should return num_bytes" do
    @data.num_bytes.should == 4
  end

  it "should return a snapshot" do
    @data.value = 5
    @data.snapshot.should == 5
  end
end

describe BinData::Single, "with :initial_value" do
  before(:each) do
    @data = ExampleSingle.new(:initial_value => 5)
  end

  it "should return that initial value before reading or being set" do
    @data.value.should == 5
  end

  it "should forget :initial_value after being set" do
    @data.value = 17
    @data.value.should_not == 5
  end

  it "should forget :initial_value after reading" do
    @data.read("\x11\x22\x33\x44")
    @data.value.should_not == 5
  end

  it "should remember :initial_value after being cleared" do
    @data.value = 17
    @data.clear
    @data.value.should == 5
  end
end

describe BinData::Single, "with :value" do
  before(:each) do
    @data = ExampleSingle.new(:value => 5)
    @data.expose_methods_for_testing
  end

  it "should return that :value" do
    @data.value.should == 5
  end

  it "should change during reading" do
    io = StringIO.new([56].pack("V"))
    @data.do_read(BinData::IO.new(io))
    @data.value.should == 56
    @data.done_read
  end

  it "should not change after reading" do
    io = StringIO.new([56].pack("V"))
    @data.read(io)
    @data.value.should == 5
  end

  it "should not be able to change the value" do
    @data.value = 17
    @data.value.should == 5
  end
end

describe BinData::Single, "with :check_value" do
  before(:each) do
    @io = StringIO.new([34].pack("V"))
  end

  it "should succeed when check_value is non boolean and correct" do
    data = ExampleSingle.new(:check_value => 34)
    lambda { data.read(@io) }.should_not raise_error
  end

  it "should fail when check_value is non boolean and incorrect" do
    data = ExampleSingle.new(:check_value => lambda { 123 * 5 })
    lambda { data.read(@io) }.should raise_error(BinData::ValidityError)
  end

  it "should succeed when check_value is boolean and true" do
    data = ExampleSingle.new(:check_value => lambda { (value % 2) == 0})
    lambda { data.read(@io) }.should_not raise_error
  end

  it "should fail when check_value is boolean and false" do
    data = ExampleSingle.new(:check_value => lambda { value > 100 })
    lambda { data.read(@io) }.should raise_error(BinData::ValidityError)
  end
end
