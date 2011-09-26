#!/usr/bin/env ruby

class DaemonNanny
  def initialize(dir, flapping_cmd)
    @dir = dir
    @flapping_cmd = flapping_cmd

    raise "You must specify a service directory" unless @dir
  end

  def services; Dir.entries(@dir).reject{|x| x =~ /^\.+$/}; end

  def stats(*svcs)
    ret, out, err = Subprocess.run('/usr/bin/svstat', svcs.flatten.map{|svc| File.join(@dir, svc)})
    raise "Error running svscat for #{svcs.inspect}" unless ret.zero?

    stats = {}

    out.split("\n").each do |line|
      svc = $1 if line =~ /\/([^\/]+):/

      up = !line.include?(': down')
      uptime = $1.to_i if line =~ /(\d+) seconds/
      pid = $1.to_i if line =~ /\(pid (\d+)\)/

      stats[svc] = {:up => up, :pid => pid, :uptime => uptime}
    end

    stats
  end

  def up?(stats); stats[:up]; end
  def uptime(stats); stats[:uptime]; end
  def pid(stats); stats[:pid]; end

  def flapping?(uptimes)
    uptimes.count >= 5 && uptimes.all?{|u| u < 60}
  end

  def notify_flapping(svc, uptimes)
    $stderr.puts "#{svc} appears to be flapping with uptimes #{uptimes.join(', ')}"
    Subprocess.run(@flapping_cmd, svc, uptimes.join(',')) if @flapping_cmd
  end

  def run
    uptimes = Hash.new do |h, k|
      h[k] = []
    end
    notified = {}

    puts "Watching #{@dir}..."

    loop do
      st = stats(services)

      services.each do |svc|
        us = uptimes[svc]

        if flapping?(us) && !notified[svc]
          notify_flapping(svc, us)
          notified[svc] = true
        end

        stats = st[svc]

        if up?(stats)
          if !flapping?(us)
            # if it was sick, it's now healthy, and we should report if it gets
            # sick again
            notified[svc] = false
          end

          u = uptime(stats)
          puts "#{svc} has been up for #{u} seconds"
          us.unshift(u)
          us.pop if us.count > 5
        else
          puts "#{svc} is down; ignoring"
        end
      end

      sleep 10
    end
  end
end

if $0 == __FILE__
  dir, flapping = ARGV

  DaemonNanny.new(dir, flapping).run
end
