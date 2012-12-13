#!/bin/bash

# Version using mythutil for 0.26+ ( 0.25 ? ) no longer needs mythexport: Tuned detect slightly, updated whitelist to include Freesat/Freeview +1 channels. Supports UK Freeview/Freesat HD Channels as they have MPEG audio channels. ( Channels with AC3 Only are not supported. ) Changed ffmpeg to avconv, as ffmpeg is deprecated. and ffmpeg -i occasionally chose the Audio Descriptive track, which is nearly all silence.
 
# edit/tune these #
# Allow ad breaks to be upto 400s long by coalescing non-silence
MAXCOMMBREAKSECS=400
# -80dB and minimum of 0.12s to be considered 'silent'
MP3SPLT_OPTS="th=-70,min=0.15"
#MP3SPLT_OPTS="th=-80,min=0.12"
# Log file
LOGFILE="/var/log/mythtv/mythcommflag-wrapper"
# Copy commercial skiplist to cutlist automatically? 1=Enabled
#COPYTOCUTLIST=1

MYTHCFG=""
# mythbackend in Fedora packages has $HOME=/etc/mythtv
if [ -e $HOME/mysql.txt ]; then
  MYTHCFG="$HOME/mysql.txt"
fi


if [ -e $HOME/.mythtv/mysql.txt ]; then
  MYTHCFG="$HOME/.mythtv/mysql.txt"
fi
if [ "$MYTHCFG" = "" ]; then
  echo >>$LOGFILE "No mysql.txt found in $HOME or $HOME/.mythtv - exiting!"
  exit 1
fi

# DB username and password
MYTHHOST=`grep DBHostName <$MYTHCFG | awk -F= '{print $2}'`
MYTHUSER=`grep DBUserName <$MYTHCFG | awk -F= '{print $2}'`
MYTHPASS=`grep DBPassword <$MYTHCFG | awk -F= '{print $2}'`
MYTHDB=`grep DBName <$MYTHCFG | awk -F= '{print $2}'`
#echo >>$LOGFILE "[$MYTHHOST] [$MYTHUSER] [$MYTHPASS] [$MYTHDB]"

# root of MythTV recordings
RECORDINGSROOT=`mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "select dirname from storagegroup;" $MYTHDB | tail -n +2 | sort | uniq | tr '\n' ' '`


echo >>$LOGFILE "$0 run with [$*] at `date` by `whoami`"
echo >>$LOGFILE "RECORDINGSROOT=$RECORDINGSROOT"

# From <http://www.mythtv.org/wiki/Silence-detect.sh>

silence_detect() {
    local filename=$1
    
    TMPDIR=`mktemp -d /tmp/mythcommflag.XXXXXX` || exit 1   

    cd $TMPDIR
    touch `basename $filename`.touch
    ionice -c3 nice mythffmpeg -i $filename -acodec copy sound.mp3
    ionice -c3 nice mp3splt -s -p $MP3SPLT_OPTS sound.mp3

    CUTLIST=`tail --lines=+3 mp3splt.log|sort -g |\
           awk 'BEGIN{start=0;ORS=","}{if($2-start<'$MAXCOMMBREAKSECS')
           {finish=$2} else {print int(start*25+1)"-"int(finish*25-25);
           start=$1; finish=$2;}}END{print int(start*25+1)"-"9999999}'`
    echo >>$LOGFILE "silence-detect has generated cutlist: $CUTLIST"

    echo >>$LOGFILE "silence-detect(): CHANID=$CHANID, STARTTIME=$STARTTIME"    
    
    rm -rf $TMPDIR
}   


if [ $# -eq 0 ]; then
  # run with no parameters, flag every unflagged recording
  exec mythcommflag
  exit $?
else
  if [ $# -eq 4 -a "$1" = "-j" -a "$3" = "-V" ]; then
    # this is a manual flag job
    # TODO AJB20110129 generate a filelist from recorded table where commflagged=0 and cutlist=0
    # then run silence_detect over each filename
    JOB=$2
  else
    # we're being used in some other way, run the real mythcommmflag
    echo >>$LOGFILE "running mythcommflag $*"
    exec mythcommflag $*
    exit $?
  fi
  echo >>$LOGFILE "running job $JOB"
  HASCUTLIST=`mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "select recorded.cutlist from recorded join jobqueue where jobqueue.id=$JOB and jobqueue.chanid=recorded.chanid and jobqueue.starttime=recorded.starttime;" $MYTHDB | tail -n +2`  
  if [ "$HASCUTLIST" = "1" ]; then
    echo >>$LOGFILE "program already has (manual?) cutlist, exiting"
    exit 0
  fi
  CALLSIGN=`mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "select channel.callsign from channel join jobqueue where jobqueue.id=$JOB and jobqueue.chanid=channel.chanid;" $MYTHDB | tail -n +2`
  CHANID=`mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "select chanid from jobqueue where jobqueue.id=$JOB;" $MYTHDB | tail -n +2`  
  STARTTIME=`mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "select starttime from jobqueue where jobqueue.id=$JOB;" $MYTHDB | tail -n +2`
  echo >>$LOGFILE "channel callsign is $CALLSIGN"
  echo >>$LOGFILE "chanid=$CHANID STARTTIME=$STARTTIME"
  BASENAME=`mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "select recorded.basename from recorded join jobqueue where jobqueue.id=$JOB and jobqueue.chanid=recorded.chanid and jobqueue.starttime=recorded.starttime;" $MYTHDB | tail -n +2` 
  echo >>$LOGFILE "basename is $BASENAME"
  FILENAME=`ionice -c3 nice find ${RECORDINGSROOT} -name $BASENAME`
  echo >>$LOGFILE "filename is $FILENAME" 

#safe list
# Channel 4 channels seem to work too, but sometimes last cut is too long?. E4/channel 4 treats trailers as program. The silence markers are only either side of actual adverts. E4 often has trailers before and after adverts, which will not be cut, and appear within the wanted show. 
# Works for other FIVE channels with caveat that they include news bulletins which are't cut
  if [ "$CALLSIGN" = "FIVE USA" -o "$CALLSIGN" = "FIVE" -o "$CALLSIGN" = "Channel 4" -o "$CALLSIGN" = "Channel 4 HD" -o "$CALLSIGN" = "Channel 4+1" -o "$CALLSIGN" = "More 4" -o "$CALLSIGN" = "More4 +1" -o "$CALLSIGN" = "E4" -o "$CALLSIGN" = "E4+1" -o "$CALLSIGN" = "Film4" -o "$CALLSIGN" = "Film4 +1" -o "$CALLSIGN" = "ITV1" -o "$CALLSIGN" = "ITV1 HD" -o "$CALLSIGN" = "ITV1 +1" -o "$CALLSIGN" = "ITV2" -o "$CALLSIGN" = "ITV2 +1" -o "$CALLSIGN" = "ITV3" -o "$CALLSIGN" = "ITV3 +1" -o "$CALLSIGN" = "ITV4" -o "$CALLSIGN" = "ITV4 +1" -o "$CALLSIGN" = "Dave" -o "$CALLSIGN" = "Dave ja vu" ]; then

#No Safe list, always use silence detect
  #if [ 1 = 1 ]; then   
    echo >>$LOGFILE "Callsign in whitelist - will run silence_detect"   
    mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "update recorded set commflagged=2 where chanid=$CHANID and starttime='${STARTTIME}';" $MYTHDB
    CUTLIST=""
    echo >>$LOGFILE "silence_detect $FILENAME"
    silence_detect $FILENAME
    echo >>$LOGFILE "silence_detect() set CUTLIST to $CUTLIST"
    let BREAKS=`grep -o "-" <<< "$CUTLIST" | wc -l`
    echo >>$LOGFILE "$BREAKS break(s) found."
                mythutil --setskiplist $CUTLIST --chanid="$CHANID" --starttime="${STARTTIME}"
    RC=$?
    echo >>$LOGFILE "mythutil setskiplist returned $RC"
    if [ $RC -eq 0 ]; then
      mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "update recorded set commflagged=1 where chanid=$CHANID and starttime='${STARTTIME}';" ${MYTHDB}
      mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "update jobqueue set status=272, comment='Finished, $BREAKS break(s) found.' where id=$JOB;" ${MYTHDB}     
      if [ $COPYTOCUTLIST -eq 1 ]; then
        mythutil --gencutlist --chanid="$CHANID" --starttime="${STARTTIME}"
        RC=$?
        if [ $RC -eq 0 ]; then
          echo >>$LOGFILE "mythutil --gencutlist successfully copied skip list to cut list"
        else
          echo >>$LOGFILE "mythutil --gencutlist failed, returned $RC"    
        fi
      fi      
    else
      echo >>$LOGFILE "mythcommflag failed; returned $RC"
      mysql -h${MYTHHOST} -u${MYTHUSER} -p${MYTHPASS} -e "update recorded set commflagged=0 where chanid=$CHANID and starttime='${STARTTIME}';" ${MYTHDB}
    fi    
  else
    # Not a whitelisted channel for silence_detect
    echo >>$LOGFILE "won't run silence-detect, running mythcommflag $*"
    exec mythcommflag $*
    exit $?
  fi    
fi
echo >>$LOGFILE
