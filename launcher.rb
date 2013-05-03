#!/usr/bin/env ruby
class Launcher
  # Checks to see if the current process is the child process and if not
  # will update the pid file with the child pid.
  def self.start pid, pidfile, outfile, errfile
    unless pid.nil?
      raise "Fork failed" if pid == -1
      write pid, pidfile if kill pid, pidfile
      exit
    else
      redirect outfile, errfile
    end
  end

  # Attempts to write the pid of the forked process to the pid file.
  def self.write pid, pidfile
    File.open pidfile, "w" do |f|
      f.write pid
    end
    $stdout.puts "writing #{pid} to #{pidfile}"
  rescue ::Exception => e
    $stderr.puts "While writing the PID to file, unexpected #{e.class}: #{e}"
    Process.kill "HUP", pid
  end

  # Try and read the existing pid from the pid file and signal the
  # process. Returns true for a non blocking status.
  def self.kill(pid, pidfile)
    opid = open(pidfile).read.strip.to_i
    Process.kill "HUP", opid
    true
  rescue Errno::ENOENT
    $stdout.puts "#{pidfile} did not exist: Errno::ENOENT"
    true
  rescue Errno::ESRCH
    $stdout.puts "The process #{opid} did not exist: Errno::ESRCH"
    true
  rescue Errno::EPERM
    $stderr.puts "Lack of privileges to manage the process #{opid}: Errno::EPERM"
    false
  rescue ::Exception => e
    $stderr.puts "While signaling the PID, unexpected #{e.class}: #{e}"
    false
  end

  # Send stdout and stderr to log files for the child process
  def self.redirect outfile, errfile
    $stdin.reopen '/dev/null'
    out = File.new outfile, "a"
    err = File.new errfile, "a"
    $stdout.reopen out
    $stderr.reopen err
    $stdout.sync = $stderr.sync = true
  end
end

# Process name of your daemon
$0 = "lesson server"

# Spawn a deamon
Launcher.start fork, 'tmp/pids/server.pid', 'log/server.stdout.log', 'log/server.stderr.log'

# Set up signals for our daemon, for now they just exit the process.
Signal.trap("HUP") { $stdout.puts "SIGHUP and exit"; exit }
Signal.trap("INT") { $stdout.puts "SIGINT and exit"; exit }
Signal.trap("QUIT") { $stdout.puts "SIGQUIT and exit"; exit }


$: << File.expand_path('server')
require 'config'
$stdout.puts 'Starting WebSocketServer'
WebSocketServer.start!