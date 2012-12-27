#!/usr/bin/env ruby
# encoding: utf-8

require 'logger'

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
  end

  def logger
    @logger ||= Logger.new(LOG_FILE)
  end

  class Job
    def initialize(id)
      @id = id.to_i
    end

    #private

    def load_data
      raw = `mysql -h myth -u mythtv -psecret -e 'SELECT r.cutlist, c.callsign, r.chanid, r.starttime, r.basename FROM jobqueue AS j LEFT OUTER JOIN recorded AS r ON j.chanid = r.chanid AND j.starttime = r.starttime LEFT OUTER JOIN channel AS c ON j.chanid = c.chanid WHERE j.id = #{@id}' mythconverg`
      values = raw.split($/).last.split("\t")
      #[:cutlist, :callsign, :chanid, :starttime, :basename].zip(raw.lines[1].split("\t"))
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
