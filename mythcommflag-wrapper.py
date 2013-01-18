#!/usr/bin/python

import os
import logging
from logging.handlers import SysLogHandler
from sys import argv
from MythTV import MythDB, Channel, Recorded, Job

MP3SPLT_OPTS = 'th=-70,min=0.15'
MAX_COMMBREAK_SECS = 400
CHANNELS = (
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
        "Really",
        )

def silence_detect(filename):
    return []

def run_commflagging(jobid):
    db = MythDB()
    job = Job(jobid, db=db)
    print "running job"
    rec = Recorded((job.chanid, job.starttime), db=db)
    if rec.cutlist > 0:
        print "program already has (manual?) cutlist, exiting"
        return

    channel = Channel(job.chanid, db=db)
    if channel.callsign not in CHANNELS:
        print "won't run silence-detect for %(callsign), running mythcommflag %(args)" % \
                {'callsign': channel.callsign, 'args': ' '.join(argv[1:]}
        os.execvp("mythcommflag", argv)

    rec.update({'commflagged': 2})
    # silence_detect
    # set_skip_list
    if success:
        rec.update({'commflagged': 1})
        job.status = 272
        job.comment = 'Finished, %(breaks) break(s) found.' % {'breaks': 0}
        job.update()
    else:
        rec.update({'commflagged': 0})

def logger():
    return logging.getLogger('mythcommflag-wrapper')

def setup_logger():
    my_logger = logger()
    my_logger.setLevel(logging.DEBUG)
    handler = SysLogHandler(address='/dev/log', facility=SysLogHandler.LOG_LOCAL6)
    my_logger.addHandler(handler)


if __name__ == '__main__':
    print ' '.join(argv)
    if len(argv) == 5 and argv[1] == '-j' and argv[3] == '-V':
        print "using wrapper for job " + argv[2]
    else:
        print "running standard mythcommflag"
        os.execvp("mythcommflag", argv)
