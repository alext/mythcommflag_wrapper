#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'logger'
require 'tmpdir'
require 'singleton'
require 'rexml/document'
require 'mysql2'

class MythCommflag
  MP3SPLT_OPTS = 'th=-70,min=0.15'
  MAX_COMMBREAK_SECS = 400
  LOG_FILE = "/var/log/mythtv/mythcommflag-wrapper.log"
  #LOG_FILE = STDOUT
  CHANNELS = [
    "FIVE USA",
    "FIVE",
    "Channel 4",
    "Channel 4 HD",
    "Channel 4+1",
    "More 4",
    "More4 +1",
    "E4",
    "E4+1",
    "Film4",
    "Film4 +1",
    "ITV1",
    "ITV1 HD",
    "ITV1 +1",
    "ITV2",
    "ITV2 +1",
    "ITV3",
    "ITV3 +1",
    "ITV4",
    "ITV4 +1",
    "Dave",
    "Dave ja vu",
  ]

  def initialize(job_id)
    @job = Job.new(job_id)
  end

  def process
    logger.info "running job #{@job.id}, callsign:#{@job.callsign}, chanid:#{@job.chanid}, starttime:#{@job.starttime}"
    if has_cutlist?
      logger.warn "program already has (manual?) cutlist, exiting"
      return
    end
    unless whitelisted_channel?
      logger.info "won't run silence-detect for #{@job.callsign}, running mythcommflag #{ARGV.join(' ')}"
      exec 'mythcommflag', *ARGV
    end

    logger.info "Callsign #{@job.callsign} in whitelist - will run slience_detect"
    @job.commflagging_in_progress!
    logger.debug "silence_detect #{filename}"
    silence_detect
    logger.info "#{@breaks.size} break(s) found."
    logger.debug "slience_detect found cuts: #{@breaks.map {|c| c.join('-') }.join(',')}"
    if set_skip_list
      logger.info "set_skip_list returned success"
      @job.commflagging_done!(@breaks.size)
    else
      logger.error "mythutil set_skip_list failed: returned #{$?.exitstatus}"
      @job.commflagging_failed!
    end
  end

  private

  def has_cutlist?
    @job.cutlist > 0
  end

  def whitelisted_channel?
    CHANNELS.include? @job.callsign
  end

  def silence_detect(source_file = filename)
    tmpdir = Dir.mktmpdir('mythcommflag-')
    begin
      Dir.chdir(tmpdir) do
        system 'ionice', '-c3', 'nice', 'mythffmpeg', '-i', source_file, '-acodec', 'copy', 'sound.mp3'
        system 'ionice', '-c3', 'nice', 'mp3splt', '-s', '-p', MP3SPLT_OPTS, 'sound.mp3'
        breaks = []
        File.open('mp3splt.log', 'r') do |f|
          f.gets
          f.gets
          break_start = 0
          break_finish = nil
          f.lines.sort_by {|line| line.to_f }.each do |line|
            start, finish, rest = line.split(/\s+/, 3).map(&:to_f)
            if finish - break_start < MAX_COMMBREAK_SECS
              break_finish = finish
            else
              breaks << [break_start, break_finish]
              break_start = start
              break_finish = finish
            end
          end
          breaks << [break_start, 9999999]
        end

        @breaks = breaks
      end
    ensure
      FileUtils.rm_r(tmpdir)
    end
  end

  def set_skip_list
    break_string = @breaks.map do |(start, finish)|
      [(start * 25 + 1).to_i, (finish * 25 - 25).to_i].join('-')
    end.join(',')
    system 'mythutil', '--setskiplist', break_string, "--chanid=#{@job.chanid}", "--starttime=#{@job.starttime.strftime('%Y%m%d%H%M%S')}"
  end

  def filename
    storage_group_dirs.each do |dir|
      file = File.join(dir, @job.basename)
      return file if File.exist?(file)
    end
    logger.error "Can't find file #{@job.basename} in any of the storage groups"
    exit 1
  end

  def storage_group_dirs
    @storage_group_dirs ||= DB.query('SELECT dirname FROM storagegroup').to_a.map {|r| r['dirname']}
  end

  def logger
    @logger ||= Logger.new(LOG_FILE)
  end

  class Job
    def initialize(id)
      @id = id.to_i
    end
    attr_reader :id

    def commflagging_in_progress!
      DB.query("UPDATE recorded SET commflagged=2 WHERE chanid=#{chanid} AND starttime='#{starttime}'")
    end

    def commflagging_done!(breaks_found)
      DB.query("UPDATE recorded SET commflagged=1 WHERE chanid=#{chanid} AND starttime='#{starttime}'")
      DB.query("UPDATE jobqueue SET status=272, comment='Finished, #{breaks_found} break(s) found.' WHERE id=#{@id}")
    end

    def commflagging_failed!
      DB.query("UPDATE recorded SET commflagged=0 WHERE chanid=#{chanid} AND starttime='#{starttime}'")
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
