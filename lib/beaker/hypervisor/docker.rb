require 'docker'

module Beaker
  class Docker < Beaker::Hypervisor

    def initialize(hosts, options)
      @options = options
      @logger = options[:logger]
      @hosts = hosts
      ::Docker.options = { :write_timeout => 300, :read_timeout => 300 }
    end

    def provision
      @logger.notify "Provisioning docker"

      @hosts.each do |host|
        @logger.notify "provisioning #{host.name}"

        @logger.debug("Creating image")
        image = ::Docker::Image.build(dockerfile_for(host))
        @logger.debug("Tagging image #{image.id} as #{host.name}")
        image.tag({
          :repo => host.name,
          :force => true,
        })

        @logger.debug("Creating container from image")
        container = ::Docker::Container.create({
          'Image' => host.name,
          'Hostname' => host.name,
        })

        @logger.debug("Starting container #{container.id}")
        container.start({"PublishAllPorts" => true})

        # Find out where the ssh port is from the container
        ip   = container.json["NetworkSettings"]["Ports"]["22/tcp"][0]["HostIp"]
        port = container.json["NetworkSettings"]["Ports"]["22/tcp"][0]["HostPort"]

        # Update host metadata
        host['ip']  = ip
        host['port'] = port
        host['ssh']  = {
          :password => root_password,
          :port => port,
        }

        @logger.debug("node available as  ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@#{ip} -p #{port}")
        host['docker_container'] = container
        host['docker_image'] = image
      end
    end

    def cleanup
      @logger.notify "Cleaning up docker"
      @hosts.each do |host|
        if container = host['docker_container']
          @logger.debug("stop container #{container.id}")
          container.stop
          @logger.debug("delete container #{container.id}")
          container.delete
        end

        if image = host['docker_image']
          @logger.debug("delete image #{image.id}")
          image.delete
        end
      end
    end

    private

    def root_password
      'root'
    end

    def dockerfile_for(host)
      # specify base image
      dockerfile = <<-EOF
        FROM #{host['image']}
      EOF

      # ssh_extra_cmd isn't used everywhere so lets default it to empty
      ssh_extra_cmd = ''

      # add os-specific actions
      dockerfile += case host['platform']
      when /ubuntu/, /debian/
        <<-EOF
          RUN apt-get update
          RUN apt-get install -y openssh-server openssh-client
        EOF
      when /centos/, /fedora/, /redhat/
        <<-EOF
          RUN yum clean all
          RUN yum install -y sudo openssh-server openssh-clients
          RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key
          RUN ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key
        EOF
      when /opensuse/, /sles/
        <<-EOF
          RUN zypper -n in openssh
          RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key
          RUN ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key
        EOF
        ssh_extra_cmd = '-o "PermitRootLogin yes" -o "PasswordAuthentication yes" -o "UsePAM no"'
      else
        # TODO add more platform steps here
        raise "platform #{host['platform']} not yet supported on docker"
      end

      # Make sshd directory, set root password
      dockerfile += <<-EOF
        RUN mkdir /var/run/sshd
        RUN echo root:#{root_password} | chpasswd
      EOF

      # Any extra_commands specified for the host
      dockerfile += (host['extra_commands'] || []).map { |command|
        "RUN #{command}\n"
      }.join("\n")

      # Set command to be executed and expose SSH port
      cmd = host['docker_cmd'] || "/usr/sbin/sshd -D #{ssh_extra_cmd}"
      dockerfile += <<-EOF
        EXPOSE 22
        CMD #{cmd}
      EOF

      @logger.debug("Dockerfile is #{dockerfile}")
      return dockerfile
    end

  end
end
