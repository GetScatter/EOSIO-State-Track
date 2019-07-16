if [ x$COUCH_USER = x ]; then echo "COUCH_USER undefined" 1>&2; exit 1; fi
if [ x$COUCH_PW = x ]; then echo "COUCH_PW undefined" 1>&2; exit 1; fi
if [ x$COUCH_BUCKET = x ]; then
    echo "using default COUCH_BUCKET=state_track" 1>&2
    COUCH_BUCKET=state_track
    export COUCH_BUCKET 
fi
