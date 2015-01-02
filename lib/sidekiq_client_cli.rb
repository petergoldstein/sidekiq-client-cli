require 'sidekiq'
require 'cli'
require_relative 'sidekiq_client_cli/version'

class SidekiqClientCLI
  COMMANDS = %w(push)
  DEFAULT_CONFIG_PATH = 'config/initializers/sidekiq.rb'

  attr_accessor :settings

  def parse
    @settings = cli.parse! do |settings|
      cmd = settings.command
      fail invalid_command_message(cmd) unless COMMANDS.include?(cmd)

      if cmd == 'push' && settings.command_args.empty?
        fail 'No Worker Classes to push'
      end
    end
  end

  def cli
    CLI.new do
      option :config_path, short: :c,
                           default: DEFAULT_CONFIG_PATH,
                           description: 'Sidekiq client config file path'
      option :queue, short: :q, description: 'Queue to place job on'
      option :retry, short: :r,
                     cast: ->(r) { SidekiqClientCLI.cast_retry_option(r) },
                     description: 'Retry option for job'
      argument :command, description: "'push' to push a job to the queue"
      arguments :command_args, required: false,
                               description: 'command arguments'
    end
  end

  def invalid_command_message(cmd)
    "Invalid command '#{cmd}'.
     Available commands: #{COMMANDS.join(',').chomp(',')}"
  end

  def self.cast_retry_option(retry_option)
    return true if retry_option.match(/^(true|t|yes|y)$/i)
    return false if retry_option.match(/^(false|f|no|n|0)$/i)
    retry_option.match(/^\d+$/) ? retry_option.to_i : nil
  end

  def run
    # load the config file
    load settings.config_path if File.exist?(settings.config_path)

    # set queue or retry if they are not given
    default_settings!

    send settings.command.to_sym
  end

  # Set queue or retry if they are not given
  def default_settings!
    settings.queue ||= Sidekiq.default_worker_options['queue']
    return unless settings.retry.nil?
    settings.retry = Sidekiq.default_worker_options['retry']
  end

  # Returns true if all args can be pushed successfully.
  # Returns false if at least one exception occured.
  def push
    settings.command_args.inject(true) do |_success, arg|
      push_argument arg
    end
  end

  private

  def push_argument(arg)
    jid = Sidekiq::Client.push('class' => arg,
                               'queue' => settings.queue,
                               'args'  => [],
                               'retry' => settings.retry)
    p push_message(arg, jid)
    true
  rescue StandardError => ex
    p "Failed to push to queue : #{ex.message}"
    false
  end

  def push_message(arg, jid)
    queue = settings.queue
    retr = settings.retry
    "Posted #{arg} to queue '#{queue}', Job ID : #{jid}, Retry : #{retr}"
  end
end
