require 'spec_helper'

# fake the docker-api
module Docker
end

module Beaker
  describe Docker do
    let(:hosts) { make_hosts }

    let(:logger) do
      logger = double
      logger.stub(:debug)
      logger.stub(:info)
      logger.stub(:warn)
      logger.stub(:error)
      logger
    end

    before :each do
      # Stub out all of the docker-api gem. we should never really call it
      # from these tests
      ::Beaker::Docker.any_instance.stub(:require).with('docker')
      ::Docker.stub(:options=)
      ::Docker.stub(:logger=)
      ::Docker.stub(:validate_version!)
    end

    describe '#initialize' do
      it 'should require the docker gem' do
        ::Beaker::Docker.any_instance.should_receive(:require).with('docker').once
        ::Beaker::Docker.new([], { :logger => logger })
      end

      describe '@usable' do
        # This isn't part of the public api for the hypervisor, hence the
        # calls to instance_variable_get
        it 'should be true when the gem is there' do
          hypervisor = ::Beaker::Docker.new([], { :logger => logger })
          hypervisor.instance_variable_get(:@usable).should == true
        end

        it 'should be false when the gem is absent' do
          ::Beaker::Docker.any_instance.stub(:require).with('docker').and_raise(LoadError)
          hypervisor = ::Beaker::Docker.new([], { :logger => logger })
          hypervisor.instance_variable_get(:@usable).should == false
        end
      end
    end
  end
end
