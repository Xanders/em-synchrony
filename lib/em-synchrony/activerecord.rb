require 'active_record'
require 'em-synchrony'

ActiveSupport.on_load(:active_record) do
  class ActiveRecord::ConnectionAdapters::ConnectionPool
    include EventMachine::Synchrony::MonitorMixin
    Monitor = EventMachine::Synchrony::Monitor

    if ActiveRecord::VERSION::MAJOR >= 5
      def connection_cache_key(scope) #:nodoc:
        scope.kind_of?(Fiber) ? scope : Fiber.current
      end
    else
      def current_connection_id #:nodoc:
        ActiveRecord::Base.connection_id ||= Fiber.current.object_id
      end
    end

    if ActiveRecord::VERSION::MAJOR == 3
      # on AR 3.x `clear_stale_cached_connections!` uses `Thread.list` and must be re-implemented
      # on AR 4.0 `clear_stale_cached_connections!` is marked as deprecated and just calls `reap`
      # `reap` on AR 4.x is implemented well and there is no reason to override it
      # on AR >= 4.1 there is no `clear_stale_cached_connections!`
      def clear_stale_cached_connections!
        keys = @reserved_connections.keys.reject do |conn_id|
          @reserved_connections[conn_id].owner.alive?
        end
        keys.each do |key|
          checkin @reserved_connections[key]
          @reserved_connections.delete(key)
        end
      end

      def checkout_with_fiber_ownership
        conn = checkout_without_fiber_ownership
        conn.owner = Fiber.current
        conn
      end

      alias_method_chain :checkout, :fiber_ownership
    end

    if ActiveRecord::VERSION::MAJOR >= 4
      # on AR 4.x and older if `reaping_frequency` option used, it should work correctly
      class Reaper
        def run
          return unless frequency
          EM::Synchrony.add_periodic_timer(frequency) do
            pool.reap
          end
        end
      end
    end
  end

  class ActiveRecord::ConnectionAdapters::AbstractAdapter
    include EventMachine::Synchrony::MonitorMixin

    if ActiveRecord::VERSION::MAJOR == 3
      attr_accessor :owner
    end

    if ActiveRecord::VERSION::MAJOR == 4 && ActiveRecord::VERSION::MINOR >= 2 || ActiveRecord::VERSION::MAJOR >= 5
      # on AR 4.2 and older `lease` sets @owner to Thread.current so we should implement it fiber aware
      def lease
        synchronize do
          unless in_use?
            @owner = Fiber.current
          end
        end
      end
    end
  end
end
