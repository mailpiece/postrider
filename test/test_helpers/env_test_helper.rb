module EnvTestHelper
  extend ActiveSupport::Concern

  included do
    teardown :restore_stubbed_env
  end

  def with_env(**variables)
    previous = variables.keys.index_with { ENV[it.to_s] }
    variables.each { |name, value| ENV[name.to_s] = value&.to_s }
    yield
  ensure
    previous.each { |name, value| value.nil? ? ENV.delete(name.to_s) : ENV[name.to_s] = value }
  end

  def stub_env(**variables)
    @stubbed_env ||= {}
    variables.each do |name, value|
      @stubbed_env[name.to_s] = ENV[name.to_s] unless @stubbed_env.key?(name.to_s)
      ENV[name.to_s] = value&.to_s
    end
  end

  private
    def restore_stubbed_env
      @stubbed_env&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    end
end
