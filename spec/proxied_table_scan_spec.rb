require File.dirname(__FILE__) + '/spec_helper.rb'

include RR

describe ProxiedTableScan do
  before(:each) do
    Initializer.configuration = proxied_config
    ensure_proxy
  end

  it "initialize should raise exception if session is not proxied" do
    session = Session.new standard_config
    lambda { ProxiedTableScan.new session, 'dummy_table' } \
      .should raise_error(RuntimeError, /only works with proxied sessions/)
  end

  it "initialize should cache the primary keys" do
    session = Session.new
    scan = ProxiedTableScan.new session, 'scanner_records'
    scan.primary_key_names.should == ['id']
  end

  it "initialize should raise exception if table doesn't have primary keys" do
    session = Session.new
    lambda {ProxiedTableScan.new session, 'extender_without_key'} \
      .should raise_error(RuntimeError, "Table extender_without_key doesn't have a primary key. Cannot scan.")
  end
  
  it "block_size should return the :block_size value of the session proxy options" do
    ProxiedTableScan.new(Session.new, 'scanner_records').block_size \
      .should == 2
  end
  
  # Creates, prepares and returns a +ProxyBlockCursor+ for the given database 
  # +connection+ and +table+.
  # Sets the ProxyBlockCursor#max_row_cache_size as per method parameter.
  def get_block_cursor(connection, table, max_row_cache_size = 1000000)
    cursor = ProxyBlockCursor.new connection, table
    cursor.max_row_cache_size = max_row_cache_size
    cursor.prepare_fetch
    cursor.checksum :block_size => 1000
    cursor
  end
  
  it "compare_blocks should compare all the records in the range" do
    session = Session.new

    left_cursor = get_block_cursor session.left, 'scanner_records'
    right_cursor = get_block_cursor session.right, 'scanner_records'

    scan = ProxiedTableScan.new session, 'scanner_records'
    diff = []
    scan.compare_blocks(left_cursor, right_cursor) do |type, row|
      diff.push [type, row]
    end
    # in this scenario the right table has the 'highest' data, 
    # so 'right-sided' data are already implicitely tested here
    diff.should == [
      [:conflict, [
          {'id' => 2, 'name' => 'Bob - left database version'},
          {'id' => 2, 'name' => 'Bob - right database version'}]],
      [:left, {'id' => 3, 'name' => 'Charlie - exists in left database only'}],
      [:right, {'id' => 4, 'name' => 'Dave - exists in right database only'}],
      [:left, {'id' => 5, 'name' => 'Eve - exists in left database only'}],
      [:right, {'id' => 6, 'name' => 'Fred - exists in right database only'}]
    ]    
  end
  
  it "compare_blocks should destroy the created cursors" do
    session = Session.new

    left_cursor = get_block_cursor session.left, 'scanner_records', 0
    right_cursor = get_block_cursor session.right, 'scanner_records', 0

    scan = ProxiedTableScan.new session, 'scanner_records'
    scan.compare_blocks(left_cursor, right_cursor) { |type, row| }
    
    session.left.cursors.should == {}
    session.right.cursors.should == {}
  end
  
  it "run should only call compare single rows if there are different block checksums" do
    config = deep_copy(proxied_config)
    config.right = config.left
    session = Session.new config
    scan = ProxiedTableScan.new session, 'scanner_records'
    scan.should_not_receive(:compare_blocks)
    diff = []
    scan.run do |type, row|
      diff.push [type,row]      
    end
    diff.should == []
  end
  
  it "run should compare all the records in the table" do
    session = Session.new
    scan = ProxiedTableScan.new session, 'scanner_records'
    diff = []
    scan.run do |type, row|
      diff.push [type, row]
    end
    # in this scenario the right table has the 'highest' data, 
    # so 'right-sided' data are already implicitely tested here
    diff.should == [
      [:conflict, [
          {'id' => 2, 'name' => 'Bob - left database version'},
          {'id' => 2, 'name' => 'Bob - right database version'}]],
      [:left, {'id' => 3, 'name' => 'Charlie - exists in left database only'}],
      [:right, {'id' => 4, 'name' => 'Dave - exists in right database only'}],
      [:left, {'id' => 5, 'name' => 'Eve - exists in left database only'}],
      [:right, {'id' => 6, 'name' => 'Fred - exists in right database only'}]
    ]    
  end
end
