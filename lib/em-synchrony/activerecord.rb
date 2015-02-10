require 'active_record'
require 'em-synchrony'

ActiveSupport.on_load(:active_record) do
  class ActiveRecord::ConnectionAdapters::ConnectionPool
    include EventMachine::Synchrony::MonitorMixin
    Monitor = EventMachine::Synchrony::Monitor

    def current_connection_id #:nodoc:
      ActiveRecord::Base.connection_id ||= Fiber.current.object_id
    end

    if ActiveRecord::VERSION::MAJOR == 3
      # on AR 4.0 `clear_stale_cached_connections!` is marked as deprecated and just calls `reap`
      # `reap` on AR 4.x is implemented well and there is no reason to stub it
      # on AR >= 4.1 there is no `clear_stale_cached_connections!`
      def clear_stale_cached_connections!
        []
      end
    end

    if ActiveRecord::VERSION::MAJOR == 4
      # on AR 4.x if `reaping_frequency` option used, it should work correctly
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

    if ActiveRecord::VERSION::MAJOR == 4
      if ActiveRecord::VERSION::MINOR == 2
        # on AR 4.2 `lease` sets @owner to Thread.current so we should implement it fiber aware
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
end
