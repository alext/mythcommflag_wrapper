#!/usr/bin/env ruby
# encoding: utf-8

require 'logger'
require 'singleton'
require 'rexml/document'
require 'mysql2'

class MythCommflag
  LOG_FILE = "/var/log/mythtv/mythcommflag-wrapper"

  def initialize(job_id)
    @job = Job.new(job_id)
  end

  def process
    logger.info "running job #{@job_id}"
    if has_cutlist?
      logger.warn "program already has (manual?) cutlist, exiting"
      return
    end
    unless whitelisted_channel?
      logger.info "won't run silence-detect, running mythcommflag #{ARGV.join(' ')}"
      exec 'mythcommflag', *ARGV
    end

  end

  private

  def has_cutlist?
    @job.cutlist > 0
  end

  def logger
    @logger ||= Logger.new(LOG_FILE)
  end

  class Job
    def initialize(id)
      @id = id.to_i
    end

    def respond_to_missing?(name, include_private = false)
      data.has_key?(name.to_s) || super
    end
    def method_missing(name, *args)
      if data.has_key?(name.to_s)
        data[name.to_s]
      else
        super
      end
    end

    private

    def data
      @data ||= load_data
    end

    def load_data
      query_str = <<-EOSQL
SELECT r.cutlist, c.callsign, r.chanid, r.starttime, r.basename
FROM jobqueue AS j
LEFT OUTER JOIN recorded AS r ON j.chanid = r.chanid AND j.starttime = r.starttime
LEFT OUTER JOIN channel AS c ON j.chanid = c.chanid
WHERE j.id = #{@id}
      EOSQL
      DB.query(query_str).first
    end
  end

  class DB
    HOME_CONFIG = "#{ENV['HOME']}/.mythtv/config.xml"
    ETC_CONFIG = "/etc/mythtv/config.xml"

    include Singleton

    def self.query(string)
      instance.query(string)
    end

    def query(string)
      connection.query(string)
    end

    private

    def connection
      @connection ||= Mysql2::Client.new(db_config)
    end

    def db_config
      if File.exist?(HOME_CONFIG)
        file = HOME_CONFIG
      elsif File.exist?(ETC_CONFIG)
        file = ETC_CONFIG
      else
        raise "No config.xml found in #{HOME_CONFIG} or #{ETC_CONFIG}"
      end
      doc = REXML::Document.new(File.open(file, 'r'))
      {
        :host => doc.elements.to_a("//DBHostName").first.text,
        :port => doc.elements.to_a("//DBPort").first.text.to_i,
        :username => doc.elements.to_a("//DBUserName").first.text,
        :password => doc.elements.to_a("//DBPassword").first.text,
        :database => doc.elements.to_a("//DBName").first.text,
      }
    end
  end
end

if $0 == __FILE__
  if ARGV.size == 4 and ARGV[0] == '-j' and ARGV[2] == '-V'
    MythCommflag.new(ARGV[1]).process
  else
    exec 'mythcommflag', *ARGV
  end
end
