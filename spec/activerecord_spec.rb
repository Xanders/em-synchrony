require "spec/helper/all"
require "em-synchrony/activerecord"
require "em-synchrony/fiber_iterator"

# mysql < spec/widgets.sql

class Widget < ActiveRecord::Base; end;

describe "Fiberized ActiveRecord driver for mysql2" do
  DELAY = 0.25
  QUERY = "SELECT sleep(#{DELAY})"

  def establish_connection
      ActiveRecord::Base.establish_connection(
        :adapter => 'em_mysql2',
        :database => 'widgets',
        :username => 'root',
        :pool => 10
      )
      Widget.delete_all
      Widget.clear_active_connections!
  end

  it "should establish AR connection" do
    EventMachine.synchrony do
      establish_connection

      result = Widget.find_by_sql(QUERY)
      result.size.should eql(1)
      EventMachine.stop
    end
  end

  it "should fire sequential, synchronous requests within single fiber" do
    EventMachine.synchrony do
      establish_connection

      start = now
      res = []

      res.push Widget.find_by_sql(QUERY)
      res.push Widget.find_by_sql(QUERY)

      (now - start.to_f).should be_within(DELAY * res.size * 0.15).of(DELAY * res.size)
      res.size.should eql(2)

      EventMachine.stop
    end
  end

  it "should fire 100 requests in fibers" do
    EM.synchrony do
      establish_connection
      EM::Synchrony::FiberIterator.new(1..100, 40).each do |i|
        widget = Widget.create title: 'hi'
        widget.update_attributes title: 'hello'
        Widget.clear_active_connections!
      end
      EM.stop
    end
  end

  it "should create widget" do
    EM.synchrony do
      establish_connection
      Widget.create
      Widget.create
      Widget.count.should eql(2)
      EM.stop
    end
  end

  it "should update widget" do
    EM.synchrony do
      establish_connection
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE widgets;")
      widget = Widget.create title: 'hi'
      widget.update_attributes title: 'hello'
      Widget.find(widget.id).title.should eql('hello')
      EM.stop
    end
  end

  describe "transactions" do
    it "should work properly" do
      EM.synchrony do
        establish_connection
        EM::Synchrony::FiberIterator.new(1..50, 30).each do |i|
          widget = Widget.create title: "hi#{i}"
          ActiveRecord::Base.transaction do
            widget.update_attributes title: "hello"
          end
          ActiveRecord::Base.transaction do
            raise ActiveRecord::Rollback
          end
          Widget.clear_active_connections!
        end
        Widget.all.each do |widget|
          widget.title.should eq('hello')
        end
        EM.stop
      end
    end
  end

  describe "ActiveRecord 4" do
    before(:all) do
      skip if ActiveRecord::VERSION::MAJOR != 4
    end

    describe "Reaper" do
      it "must recover lost connections" do
        EM.synchrony do
          ActiveRecord::Base.establish_connection(
            :adapter => 'em_mysql2',
            :database => 'widgets',
            :username => 'root',
            :reaping_frequency => DELAY * 2,
            :dead_connection_timeout => DELAY,
            :pool => 2
          )

          connections = []
          EM::Synchrony::FiberIterator.new(1..2, 2).each do
            connections << Widget.connection
          end

          connections.size.should == 2
          ActiveRecord::Base.connection_pool.connections.should == connections

          connections.each do |conn|
            allow(conn).to receive(:active?).and_return(false)
          end

          connections.each { |conn| conn.should be_in_use }

          start_time = Time.now
          Widget.connection
          end_time = Time.now
          (end_time - start_time).should be > DELAY

          EM.stop
        end
      end
    end
  end
end
