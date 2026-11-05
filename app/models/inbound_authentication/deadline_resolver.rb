# Gives each lookup a resolver whose timeouts are cut to the time left, so a check ends by the deadline
# with every lookup it couldn't finish timed out, and asks nothing after it.
class InboundAuthentication::DeadlineResolver
  # +resolver+ builds a resolver for the timeouts it is given.
  def initialize(seconds, &resolver)
    @deadline = monotonic_time + seconds
    @resolver = resolver
  end

  %i[ txt a aaaa mx ptr addresses ].each do |type|
    define_method(type) do |name|
      remaining = @deadline - monotonic_time

      if remaining.positive?
        @resolver.call(timeouts_within(remaining)).public_send(type, name)
      else
        raise MailResolver::Timeout, "out of time resolving #{type.upcase} #{name.inspect}"
      end
    end
  end

  private
    # mailresolver's schedule, scaled down to fit.
    def timeouts_within(remaining)
      scale = [ remaining / MailResolver::Resolver::TIMEOUTS.sum, 1 ].min
      MailResolver::Resolver::TIMEOUTS.map { it * scale }
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
end
