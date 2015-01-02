require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe SidekiqClientCLI do
  let(:default_queue) { Sidekiq.default_worker_options['queue'] }
  let(:default_retry_option) { Sidekiq.default_worker_options['retry'] }
  let!(:client) { SidekiqClientCLI.new }

  describe 'ARGV parsing' do
    it 'fails if no command' do
      out = IOHelper.stderr_read do
        stub_const('ARGV', [])
        expect do
          client.parse
        end.to raise_error(SystemExit)
      end

      expect(out).to include("'command' not given")
    end

    it 'fails if wrong command' do
      out = IOHelper.stderr_read do
        stub_const('ARGV', %w(dosomething))
        expect do
          client.parse
        end.to raise_error(SystemExit)
      end

      expect(out).to include('Invalid command')
    end

    it 'fails if push without classes' do
      out = IOHelper.stderr_read do
        stub_const('ARGV', %w(push))
        expect do
          client.parse
        end.to raise_error(SystemExit)
      end

      expect(out).to include('No Worker Classes')
    end

    it 'parses push with classes' do
      worker_klasses = %w(FirstWorker SecondWorker)
      stub_const('ARGV', %w(push).concat(worker_klasses))
      client.parse
      settings = client.settings
      expect(settings.command).to eq 'push'
      expect(settings.command_args).to eq worker_klasses
      expect(settings.config_path).to eq SidekiqClientCLI::DEFAULT_CONFIG_PATH
      expect(settings.queue).to eq nil
      expect(settings.retry).to eq nil
    end

    it 'parses push with a configuration file' do
      worker_klasses = %w(FirstWorker SecondWorker)
      stub_const('ARGV', %w(-c mysidekiq.conf push).concat(worker_klasses))
      client.parse
      expect(client.settings.command).to eq 'push'
      expect(client.settings.command_args).to eq worker_klasses
      expect(client.settings.config_path).to eq 'mysidekiq.conf'
      expect(client.settings.queue).to eq nil
    end

    it 'parses push with a queue' do
      worker_klasses = %w(FirstWorker SecondWorker)
      stub_const('ARGV', %w(-q my_queue push).concat(worker_klasses))
      client.parse
      settings = client.settings
      expect(settings.command).to eq 'push'
      expect(settings.command_args).to eq worker_klasses
      expect(settings.config_path).to eq SidekiqClientCLI::DEFAULT_CONFIG_PATH
      expect(settings.queue).to eq 'my_queue'
    end

    it 'parses push with a boolean retry' do
      worker_klasses = %w(FirstWorker SecondWorker)
      stub_const('ARGV', %w(-r false push).concat(worker_klasses))
      client.parse
      settings = client.settings
      expect(settings.command).to eq 'push'
      expect(settings.command_args).to eq worker_klasses
      expect(settings.config_path).to eq SidekiqClientCLI::DEFAULT_CONFIG_PATH
      expect(settings.retry).to eq false
    end

    it 'parses push with an integer retry' do
      worker_klasses = %w(FirstWorker SecondWorker)
      stub_const('ARGV', %w(-r 42 push).concat(worker_klasses))
      client.parse
      settings = client.settings
      expect(settings.command).to eq 'push'
      expect(settings.command_args).to eq worker_klasses
      expect(settings.config_path).to eq SidekiqClientCLI::DEFAULT_CONFIG_PATH
      expect(settings.retry).to eq 42
    end
  end

  describe 'run' do
    it 'loads the config file if existing and runs the command' do
      config_path = 'sidekiq.conf'
      settings = double(:settings)
      allow(settings).to receive(:config_path).and_return(config_path)
      allow(settings).to receive(:command).and_return('mycommand')
      allow(settings).to receive(:queue).and_return(default_queue)
      allow(settings).to receive(:retry).and_return(default_retry_option)
      client.settings = settings

      expect(client).to receive(:mycommand)

      expect(File).to receive(:exist?).with(config_path).and_return true
      expect(client).to receive(:load).with(config_path)

      client.run
    end

    it "won't load a non-existant config file and the command is run" do
      config_path = 'sidekiq.conf'
      settings = double('settings')
      allow(settings).to receive(:config_path).and_return(config_path)
      allow(settings).to receive(:command).and_return('mycommand')
      allow(settings).to receive(:queue).and_return(default_queue)
      allow(settings).to receive(:retry).and_return(default_retry_option)

      client.settings = settings
      expect(client).to receive(:mycommand)

      expect(File).to receive(:exist?).with(config_path).and_return false
      expect(client).not_to receive(:load)

      client.run
    end

    it 'doesnt try to change the retry value if it has been set to false' do
      config_path = 'sidekiq.conf'
      settings = double(:settings)
      allow(settings).to receive(:config_path).and_return(config_path)
      allow(settings).to receive(:command).and_return('mycommand')
      allow(settings).to receive(:queue).and_return(default_queue)
      allow(settings).to receive(:retry).and_return(false)
      client.settings = settings

      expect(client).to receive(:mycommand)
      expect(client).not_to receive(:retry=)

      client.run
    end

    it 'doesnt try to change the retry value if it has been set to true' do
      config_path = 'sidekiq.conf'
      settings = double(:settings)
      allow(settings).to receive(:config_path).and_return(config_path)
      allow(settings).to receive(:command).and_return('mycommand')
      allow(settings).to receive(:queue).and_return(default_queue)
      allow(settings).to receive(:retry).and_return(true)
      client.settings = settings

      expect(client).to receive(:mycommand)
      expect(client).not_to receive(:retry=)

      client.run
    end
  end

  describe 'push' do
    let(:settings) { double('settings') }
    let(:klass1) { 'FirstWorker' }
    let(:klass2) { 'SecondWorker' }
    let(:client) { SidekiqClientCLI.new }

    before(:each) do
      allow(settings).to receive(:command_args).and_return [klass1, klass2]
      client.settings = settings
    end

    it 'returns true if all #push_argument calls return true' do
      allow(client).to receive(:push_argument).and_return(true)
      expect(client.push).to eq true
    end

    it 'returns false if at least one #push_argument call fails' do
      expect(client)
        .to receive(:push_argument).with('FirstWorker').and_return(true)
      expect(client)
        .to receive(:push_argument).with('SecondWorker').and_return(false)
      expect(client.push).to eq false
    end
  end

  describe '#push_argument' do
    let(:settings) do
      double('settings', queue: default_queue, retry: default_retry_option)
    end
    let(:klass1) { 'FirstWorker' }
    let(:client) { SidekiqClientCLI.new }

    before(:each) do
      client.settings = settings
    end

    it 'pushes the worker classes' do
      jid = SecureRandom.hex(10)
      expect(Sidekiq::Client)
        .to receive(:push).with('class' => klass1,
                                'args' => [],
                                'queue' => default_queue,
                                'retry' => default_retry_option)
        .and_return(jid)

      msg = "Posted FirstWorker to queue 'default', " \
            "Job ID : #{jid}, Retry : true"
      expect(client).to receive(:p).with(msg)
      expect(client.__send__(:push_argument, klass1)).to eq true
    end

    it 'pushes the worker classes to the correct queue' do
      queue = 'Queue'
      allow(settings).to receive(:queue).and_return queue

      jid = SecureRandom.hex(10)
      expect(Sidekiq::Client)
        .to receive(:push).with('class' => klass1,
                                'args' => [],
                                'queue' => queue,
                                'retry' => default_retry_option)
        .and_return(jid)

      msg = "Posted FirstWorker to queue 'Queue', " \
            "Job ID : #{jid}, Retry : true"
      expect(client).to receive(:p).with(msg)
      expect(client.__send__(:push_argument, klass1)).to eq true
    end

    it 'pushes the worker classes with retry disabled' do
      retry_option = false
      allow(settings).to receive(:retry).and_return retry_option

      jid = SecureRandom.hex(10)
      expect(Sidekiq::Client)
        .to receive(:push).with('class' => klass1,
                                'args' => [],
                                'queue' => default_queue,
                                'retry' => retry_option)
        .and_return(jid)

      msg = "Posted FirstWorker to queue 'default', " \
            "Job ID : #{jid}, Retry : false"
      expect(client).to receive(:p).with(msg)
      expect(client.__send__(:push_argument, klass1)).to eq true
    end

    it 'pushes the worker classes with a set retry number' do
      retry_attempts = 5
      allow(settings).to receive(:retry).and_return retry_attempts

      jid = SecureRandom.hex(10)
      expect(Sidekiq::Client)
        .to receive(:push).with('class' => klass1,
                                'args' => [],
                                'queue' => default_queue,
                                'retry' => retry_attempts)
        .and_return(jid)

      msg = "Posted FirstWorker to queue 'default', " \
            "Job ID : #{jid}, Retry : 5"
      expect(client).to receive(:p).with(msg)
      expect(client.__send__(:push_argument, klass1)).to eq true
    end

    it 'prints and continues if an exception is raised' do
      expect(Sidekiq::Client)
        .to receive(:push).with('class' => klass1,
                                'args' => [],
                                'queue' => default_queue,
                                'retry' => default_retry_option)
        .and_raise(StandardError)

      msg = 'Failed to push to queue : StandardError'
      expect(client).to receive(:p).with(msg)
      expect(client.__send__(:push_argument, klass1)).to eq false
    end
  end

  describe 'cast_retry_option' do
    subject { SidekiqClientCLI }

    it 'returns false if the string matches false|f|no|n|0' do
      expect(subject.cast_retry_option('false')).to eq(false)
      expect(subject.cast_retry_option('f')).to eq(false)
      expect(subject.cast_retry_option('no')).to eq(false)
      expect(subject.cast_retry_option('n')).to eq(false)
      expect(subject.cast_retry_option('0')).to eq(false)
    end

    it 'returns true if the string matches true|t|yes|y' do
      expect(subject.cast_retry_option('true')).to eq(true)
      expect(subject.cast_retry_option('t')).to eq(true)
      expect(subject.cast_retry_option('yes')).to eq(true)
      expect(subject.cast_retry_option('y')).to eq(true)
    end

    it 'returns an integer if the passed string is an integer' do
      expect(subject.cast_retry_option('1')).to eq(1)
      expect(subject.cast_retry_option('42')).to eq(42)
    end
  end
end
